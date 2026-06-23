_validate_service_mode() {
    case "${1:-}" in
    tmux | nohup | systemd)
        return 0
        ;;
    *)
        _failcat "无效托管模式：${1:-<empty>}，可选值：tmux、nohup、systemd"
        return 1
        ;;
    esac
}

_get_default_service_mode() {
    local mode="${INIT_TYPE:-tmux}"
    case "$mode" in
    tmux | nohup | systemd)
        ;;
    *)
        mode=tmux
        ;;
    esac
    printf '%s\n' "$mode"
}

_parse_mode_args() {
    local __mode_var=$1
    shift
    local parsed_mode=
    while (($#)); do
        case "$1" in
        --mode=*)
            parsed_mode=${1#--mode=}
            ;;
        --mode)
            shift
            [ $# -gt 0 ] || {
                _failcat "--mode 需要指定：tmux、nohup、systemd"
                return 1
            }
            parsed_mode=$1
            ;;
        -h | --help)
            parsed_mode=__help__
            ;;
        *)
            _failcat "未知参数：$1"
            return 1
            ;;
        esac
        shift
    done
    [ -z "$parsed_mode" ] && parsed_mode=$(_get_default_service_mode)
    [ "$parsed_mode" = __help__ ] || _validate_service_mode "$parsed_mode" || return 1
    printf -v "$__mode_var" '%s' "$parsed_mode"
}

_service_state_active_mode() {
    [ -f "$CLASH_SERVICE_STATE" ] || return 1
    [ -x "$BIN_YQ" ] || {
        _failcat "缺少 yq：$BIN_YQ"
        return 1
    }
    "$BIN_YQ" -e '.active_mode // ""' "$CLASH_SERVICE_STATE"
}

_write_service_state() {
    local mode=$1 pid=${2:-} tmp
    mkdir -p "$CLASH_RESOURCES_DIR"
    [ -x "$BIN_YQ" ] || {
        _failcat "缺少 yq：$BIN_YQ"
        return 1
    }
    tmp=$(mktemp "${CLASH_RESOURCES_DIR}/.service-state.XXXXXX") || return 1
    SERVICE_STATE_ACTIVE_MODE=$mode \
        SERVICE_STATE_PID=$pid \
        SERVICE_STATE_STARTED_AT=$(date +%s) \
        SERVICE_STATE_BIN_KERNEL=$BIN_KERNEL \
        SERVICE_STATE_CONFIG_RUNTIME=$CLASH_CONFIG_RUNTIME \
        "$BIN_YQ" -n '
            .active_mode = strenv(SERVICE_STATE_ACTIVE_MODE) |
            .started_at = (strenv(SERVICE_STATE_STARTED_AT) | tonumber) |
            .bin_kernel = strenv(SERVICE_STATE_BIN_KERNEL) |
            .config_runtime = strenv(SERVICE_STATE_CONFIG_RUNTIME) |
            if strenv(SERVICE_STATE_PID) != "" then
                .pid = (strenv(SERVICE_STATE_PID) | tonumber)
            else
                .
            end
        ' >"$tmp" || {
        /usr/bin/rm -f "$tmp"
        return 1
    }
    /bin/mv -f "$tmp" "$CLASH_SERVICE_STATE"
}

_with_service_lock() {
    local lock_file="${CLASH_RESOURCES_DIR}/service.lock"

    mkdir -p "$CLASH_RESOURCES_DIR" || return 1
    command -v flock >/dev/null || {
        local lock_dir="${lock_file}.d" cmd_status
        mkdir "$lock_dir" 2>/dev/null || {
            _failcat "另一个 clashctl 操作正在进行，请稍后重试"
            return 1
        }
        "$@"
        cmd_status=$?
        rmdir "$lock_dir" 2>/dev/null || true
        return "$cmd_status"
    }
    local cmd_status
    exec 9>"$lock_file" || return 1
    flock 9 || {
        exec 9>&-
        return 1
    }
    "$@"
    cmd_status=$?
    flock -u 9 2>/dev/null || true
    exec 9>&-
    return "$cmd_status"
}

_clear_service_state() {
    /usr/bin/rm -f "$CLASH_SERVICE_STATE"
}

_clash_install_id() {
    printf '%s' "$CLASH_BASE_DIR" | cksum | awk '{print $1}'
}

_shell_quote_arg() {
    printf '%q' "$1"
}

_clash_kernel_command_for_shell() {
    printf '%s -d %s -f %s >> %s 2>&1' \
        "$(_shell_quote_arg "$BIN_KERNEL")" \
        "$(_shell_quote_arg "$CLASH_RESOURCES_DIR")" \
        "$(_shell_quote_arg "$CLASH_CONFIG_RUNTIME")" \
        "$(_shell_quote_arg "$FILE_LOG")"
}

_clash_tmux_session() {
    printf 'clash-%s-%s\n' "$KERNEL_NAME" "$(_clash_install_id)"
}

_clash_legacy_tmux_session() {
    printf 'clash-%s\n' "$KERNEL_NAME"
}

_pid_or_children_match_current_kernel() {
    local pid=$1 child
    _pid_matches_current_kernel "$pid" && return 0

    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
        _pid_or_children_match_current_kernel "$child" && return 0
    done
    return 1
}

_collect_current_kernel_pids_from_tree() {
    local pid=$1 child
    _pid_matches_current_kernel "$pid" && printf '%s\n' "$pid"

    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
        _collect_current_kernel_pids_from_tree "$child"
    done
}

_clash_tmux_session_current_kernel_pids() {
    local session=$1 pane_pid
    command -v tmux >/dev/null || return 1
    tmux has-session -t "$session" 2>/dev/null || return 1

    while IFS= read -r pane_pid; do
        [ -n "$pane_pid" ] || continue
        _collect_current_kernel_pids_from_tree "$pane_pid"
    done < <(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null) |
        awk 'NF && !seen[$0]++'
}

_terminate_current_kernel_pids() {
    local pid
    [ "$#" -gt 0 ] || return 0

    for pid in "$@"; do
        _pid_matches_current_kernel "$pid" && kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 0.2
    for pid in "$@"; do
        _pid_matches_current_kernel "$pid" && kill -KILL "$pid" 2>/dev/null || true
    done
}

_current_kernel_pids() {
    local pid
    {
        pgrep -u "$(id -u)" -x "$KERNEL_NAME" 2>/dev/null || true
        pgrep -u "$(id -u)" -f "$BIN_KERNEL" 2>/dev/null || true
    } |
        awk 'NF && !seen[$0]++' |
        while IFS= read -r pid; do
            _pid_matches_current_kernel "$pid" && printf '%s\n' "$pid"
        done
}

_clash_tmux_kill_session() {
    local session=$1
    local kernel_pids=()
    mapfile -t kernel_pids < <(_clash_tmux_session_current_kernel_pids "$session" 2>/dev/null || true)
    tmux kill-session -t "$session" 2>/dev/null || return 1
    _terminate_current_kernel_pids "${kernel_pids[@]}"
}

_clash_tmux_session_has_current_kernel() {
    local session=$1 pane_pid
    command -v tmux >/dev/null || return 1
    tmux has-session -t "$session" 2>/dev/null || return 1

    while IFS= read -r pane_pid; do
        [ -n "$pane_pid" ] || continue
        _pid_or_children_match_current_kernel "$pane_pid" && return 0
    done < <(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null)
    return 1
}

_pid_matches_current_kernel() {
    local pid=$1 expected_starttime=${2:-} exe starttime
    [ -n "$pid" ] && [ -d "/proc/$pid" ] || return 1
    exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
    if [ "$exe" != "$BIN_KERNEL" ]; then
        [ -n "$expected_starttime" ] || return 1
        [ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" = "$KERNEL_NAME" ] || return 1
    fi

    if [ -n "$expected_starttime" ]; then
        starttime=$(_proc_starttime "$pid") || return 1
        [ "$starttime" = "$expected_starttime" ] || return 1
    fi

    _proc_cmdline_has_arg "$pid" -d "$CLASH_RESOURCES_DIR" &&
        _proc_cmdline_has_arg "$pid" -f "$CLASH_CONFIG_RUNTIME"
}

_proc_cmdline_has_arg() {
    local pid=$1 key=$2 expected=$3
    tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null |
        awk -v key="$key" -v expected="$expected" '
            want_next {
                if ($0 == expected) {
                    found = 1
                }
                want_next = 0
            }
            $0 == key {
                want_next = 1
            }
            END {
                exit found ? 0 : 1
            }
        '
}

_proc_starttime() {
    local pid=$1 stat rest
    stat=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
    rest=${stat#*) }
    awk '{print $20}' <<<"$rest"
}

_read_nohup_pid() {
    [ -f "$FILE_PID" ] || return 1
    awk -F': *' '
        NR == 1 && $1 ~ /^[0-9]+$/ { print $1; found=1; exit }
        $1 == "pid" { print $2; found=1; exit }
        END { exit found ? 0 : 1 }
    ' "$FILE_PID"
}

_read_nohup_starttime() {
    [ -f "$FILE_PID" ] || return 1
    awk -F': *' '$1 == "starttime" { print $2; found=1; exit } END { exit found ? 0 : 1 }' "$FILE_PID"
}

_write_nohup_pid() {
    local pid=$1 starttime
    starttime=$(_proc_starttime "$pid" 2>/dev/null || true)
    {
        printf 'pid: %s\n' "$pid"
        [ -n "$starttime" ] && printf 'starttime: %s\n' "$starttime"
    } >"$FILE_PID"
}

_clash_adapter_tmux_start() {
    command -v tmux >/dev/null || {
        _failcat "未检测到 tmux，请先安装 tmux 或使用 --mode nohup"
        return 1
    }
    local session kernel_cmd
    session=$(_clash_tmux_session)
    kernel_cmd=$(_clash_kernel_command_for_shell)
    tmux new-session -d -s "$session" "$kernel_cmd"
}

_clash_adapter_tmux_stop() {
    local session legacy_session
    session=$(_clash_tmux_session)
    tmux has-session -t "$session" 2>/dev/null &&
        _clash_tmux_kill_session "$session"

    legacy_session=$(_clash_legacy_tmux_session)
    [ "$legacy_session" = "$session" ] && return 0
    _clash_tmux_session_has_current_kernel "$legacy_session" &&
        _clash_tmux_kill_session "$legacy_session"

    return 0
}

_clash_adapter_tmux_is_active() {
    local session legacy_session
    command -v tmux >/dev/null || return 1
    session=$(_clash_tmux_session)
    _clash_tmux_session_has_current_kernel "$session" && return 0

    legacy_session=$(_clash_legacy_tmux_session)
    [ "$legacy_session" = "$session" ] && return 1
    _clash_tmux_session_has_current_kernel "$legacy_session"
}

_clash_adapter_nohup_start() {
    nohup "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" >>"$FILE_LOG" 2>&1 &
    _write_nohup_pid "$!"
}

_clash_adapter_nohup_stop() {
    local pid starttime
    pid=$(_read_nohup_pid 2>/dev/null || true)
    starttime=$(_read_nohup_starttime 2>/dev/null || true)
    _pid_matches_current_kernel "$pid" "$starttime" || {
        /usr/bin/rm -f "$FILE_PID"
        return 0
    }
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.2
    _pid_matches_current_kernel "$pid" "$starttime" && kill -KILL "$pid" 2>/dev/null || true
    /usr/bin/rm -f "$FILE_PID"
}

_clash_adapter_nohup_is_active() {
    local pid starttime
    pid=$(_read_nohup_pid 2>/dev/null || true)
    starttime=$(_read_nohup_starttime 2>/dev/null || true)
    _pid_matches_current_kernel "$pid" "$starttime"
}

_systemctl() {
    if [ "$(id -u)" -eq 0 ]; then
        systemctl "$@"
    else
        sudo -n systemctl "$@"
    fi
}

_clash_systemd_unit_path() {
    printf '/etc/systemd/system/%s.service\n' "$KERNEL_NAME"
}

_clash_systemd_registered() {
    local unit expected
    unit=$(_clash_systemd_unit_path)
    expected="ExecStart=${BIN_KERNEL} -d ${CLASH_RESOURCES_DIR} -f ${CLASH_CONFIG_RUNTIME}"
    [ -f "$unit" ] && grep -Fqx "$expected" "$unit" && return 0
    systemctl cat "$KERNEL_NAME" 2>/dev/null | grep -Fqx "$expected"
}

_clash_adapter_systemd_start() {
    command -v systemctl >/dev/null || {
        _failcat "未检测到 systemctl，无法使用 --mode systemd"
        return 1
    }
    _clash_systemd_registered || {
        _failcat "systemd 服务未注册或不属于当前安装，请先 sudo bash install.sh --init systemd"
        return 1
    }
    _systemctl start "$KERNEL_NAME" || {
        _failcat "systemd 服务启动失败：请确认当前用户有 root 或免密 sudo 的 systemctl 权限"
        return 1
    }
}

_clash_adapter_systemd_stop() {
    command -v systemctl >/dev/null || return 1
    _clash_systemd_registered || return 1
    _systemctl stop "$KERNEL_NAME"
}

_clash_adapter_systemd_is_active() {
    command -v systemctl >/dev/null || return 1
    _clash_systemd_registered || return 1
    systemctl is-active "$KERNEL_NAME" >/dev/null 2>&1
}

_clash_adapter_call() {
    local mode=$1 action=$2
    "_clash_adapter_${mode}_${action}"
}

_list_active_modes() {
    local mode
    for mode in tmux nohup systemd; do
        _clash_adapter_call "$mode" is_active >/dev/null 2>&1 && printf '%s\n' "$mode"
    done
}

_get_active_mode() {
    local mode modes count
    modes=$(_list_active_modes)
    count=$(printf '%s\n' "$modes" | sed '/^$/d' | wc -l)
    case "$count" in
    0)
        return 1
        ;;
    1)
        mode=$(_service_state_active_mode 2>/dev/null || true)
        if [ -n "$mode" ] && _validate_service_mode "$mode" >/dev/null &&
            printf '%s\n' "$modes" | grep -qx "$mode"; then
            printf '%s\n' "$mode"
            return 0
        fi
        printf '%s\n' "$modes"
        return 0
        ;;
    *)
        printf '%s\n' "$modes"
        return 2
        ;;
    esac
}

_clash_service_is_active() {
    local mode=${1:-}
    if [ -n "$mode" ]; then
        _validate_service_mode "$mode" >/dev/null &&
            _clash_adapter_call "$mode" is_active
        return $?
    fi
    _get_active_mode >/dev/null
}

_clash_service_start() {
    local mode=$1 pid=
    _validate_service_mode "$mode" || return 1
    _clash_adapter_call "$mode" start || return 1
    [ "$mode" = nohup ] && pid=$(_read_nohup_pid 2>/dev/null || true)
    _write_service_state "$mode" "$pid"
}

_clash_service_stop() {
    local mode=$1
    _validate_service_mode "$mode" || return 1
    _clash_adapter_call "$mode" stop || return 1
    _clash_adapter_call "$mode" is_active >/dev/null 2>&1 && return 1
    local active
    active=$(_service_state_active_mode 2>/dev/null || true)
    [ "$active" = "$mode" ] && _clear_service_state
    return 0
}

_clash_service_log() {
    [ -n "${FILE_LOG:-}" ] || {
        _failcat "日志路径未初始化，请重新 source 安装目录中的 clashctl.sh"
        return 1
    }
    [ -f "$FILE_LOG" ] || {
        _failcat "日志文件不存在：$FILE_LOG"
        return 1
    }
    less <"$FILE_LOG" "$@"
}

_clash_service_follow_log() {
    [ -n "${FILE_LOG:-}" ] || {
        _failcat "日志路径未初始化，请重新 source 安装目录中的 clashctl.sh"
        return 1
    }
    [ -f "$FILE_LOG" ] || {
        _failcat "日志文件不存在：$FILE_LOG"
        return 1
    }
    tail -f -n 0 "$FILE_LOG" "$@"
}

_detect_proxy_port() {
    local ports mixed_port http_port socks_port
    ports=$(_runtime_config_read_ports "$CLASH_CONFIG_RUNTIME") || return 1
    IFS='|' read -r mixed_port http_port socks_port <<<"$ports"

    local newPort count=0
    local isActive=false
    local port_list=()
    [ -n "$mixed_port" ] && port_list+=("mixed-port|$mixed_port")
    [ -n "$http_port" ] && port_list+=("port|$http_port")
    [ -n "$socks_port" ] && port_list+=("socks-port|$socks_port")
    clashstatus >&/dev/null && isActive=true
    for entry in "${port_list[@]}"; do
        local yaml_key="${entry%|*}"
        local var_val="${entry#*|}"

        [ -n "$var_val" ] && _is_port_used "$var_val" && [ "$isActive" != "true" ] && {
            newPort=$(_get_random_port) || return 1
            count=$((count + 1))
            _failcat '🎯' "端口冲突：[$yaml_key] $var_val 已被其他进程占用，建议改 mixin.yaml 中的 $yaml_key 为 $newPort 后执行 clashmixin -m"
        }
    done
    ((count)) && return 1
    return 0
}

_clashon_impl() {
    local mode active active_status
    _parse_mode_args mode "$@" || return 1
    [ "$mode" = __help__ ] && {
        cat <<EOF

- 按默认托管模式启动
  clashon

- 按指定托管模式启动
  clashon --mode tmux|nohup|systemd

EOF
        return 0
    }

    active=$(_get_active_mode 2>/dev/null)
    active_status=$?
    if [ "$active_status" -eq 0 ]; then
        [ "$active" = "$mode" ] && {
            clashstatus --mode "$active" >&/dev/null && {
                _okcat "内核已运行（mode=$active）；当前终端如需走代理，请执行 clashproxy on"
                return 0
            }
            _failcat "检测到 $active 托管进程，但 API 不可达；请执行 clashstatus 或 clashlog 排查"
            return 1
        }
        _failcat "当前 $active 模式正在运行，请先 clashoff，或执行 clashrestart --mode $mode"
        return 1
    fi
    if [ "$active_status" -eq 2 ]; then
        _failcat "检测到多个托管模式同时运行，请先执行 clashstatus --all 并用 clashoff --mode <mode> 清理"
        return 1
    fi

    _detect_proxy_port || return 1
    _ensure_ext_addr_available || return 1

    _clash_service_start "$mode" >/dev/null || {
        _failcat "启动失败：无法以 $mode 模式启动"
        return 1
    }

    local deadline=$((SECONDS + 5))
    while [ "$SECONDS" -le "$deadline" ]; do
        clashstatus >&/dev/null && {
            _okcat "内核已启动（mode=$mode）；当前终端如需走代理，请执行 clashproxy on"
            return 0
        }
        sleep 0.2
    done

    {
        _clash_service_stop "$mode" >/dev/null 2>&1 || true
        _clear_service_state
        _failcat '启动失败: 执行 clashlog 查看日志'
        return 1
    }
}

function clashon() {
    _with_service_lock _clashon_impl "$@"
}

_clashoff_impl() {
    local mode active active_status
    mode=
    while (($#)); do
        case "$1" in
        --mode=*)
            mode=${1#--mode=}
            ;;
        --mode)
            shift
            [ $# -gt 0 ] || {
                _failcat "--mode 需要指定：tmux、nohup、systemd"
                return 1
            }
            mode=$1
            ;;
        -h | --help)
            cat <<EOF

- 关闭当前活跃托管模式
  clashoff

- 显式关闭指定托管模式
  clashoff --mode tmux|nohup|systemd

EOF
            return 0
            ;;
        *)
            _failcat "未知参数：$1"
            return 1
            ;;
        esac
        shift
    done
    if [ -n "$mode" ]; then
        _validate_service_mode "$mode" || return 1
    fi
    if [ -z "$mode" ]; then
        active=$(_get_active_mode 2>/dev/null)
        active_status=$?
        [ "$active_status" -eq 1 ] && {
            _okcat '内核未运行；当前终端代理变量未改动'
            _warn_global_auto_proxy_still_enabled
            return 0
        }
        [ "$active_status" -eq 2 ] && {
            _failcat "检测到多个托管模式同时运行，请先执行 clashstatus --all，再用 clashoff --mode <mode> 指定关闭"
            return 1
        }
        mode=$active
    fi

    _clash_service_is_active "$mode" >/dev/null 2>&1 && {
        _clash_service_stop "$mode" >/dev/null
        _clash_service_is_active "$mode" >/dev/null 2>&1 && {
            _failcat '内核关闭失败'
            return 1
        }
    }
    _okcat '内核已关闭；当前终端代理变量未改动，如需关闭请执行 clashproxy off'
    _warn_global_auto_proxy_still_enabled
}

function clashoff() {
    _with_service_lock _clashoff_impl "$@"
}

_clashrestart_impl() {
    local mode active active_status has_mode_arg=false arg
    local current_pids=()
    for arg in "$@"; do
        case "$arg" in
        --mode | --mode=*)
            has_mode_arg=true
            ;;
        esac
    done
    _parse_mode_args mode "$@" || return 1
    [ "$mode" = __help__ ] && {
        cat <<EOF

- 重启当前活跃托管模式
  clashrestart

- 切换到指定托管模式
  clashrestart --mode tmux|nohup|systemd

EOF
        return 0
    }
    active=$(_get_active_mode 2>/dev/null)
    active_status=$?
    [ "$active_status" -eq 2 ] && {
        _failcat "检测到多个托管模式同时运行，请先执行 clashstatus --all 并手动清理"
        return 1
    }
    if [ "$active_status" -eq 0 ]; then
        [ "$has_mode_arg" = false ] && mode=$active
        _clash_service_stop "$active" >/dev/null || return 1
    elif [ "$active_status" -eq 1 ]; then
        mapfile -t current_pids < <(_current_kernel_pids)
        if [ "${#current_pids[@]}" -gt 0 ]; then
            _okcat "检测到未托管的当前安装内核进程，先接管重启"
            _terminate_current_kernel_pids "${current_pids[@]}"
        fi
    fi
    _clashon_impl --mode "$mode"
}

clashrestart() {
    _with_service_lock _clashrestart_impl "$@"
}
function clashstatus() {
    local mode active_status any_active_status=1
    case "${1:-}" in
    --all)
        shift
        [ "$#" -eq 0 ] || {
            _failcat "未知参数：$1"
            return 1
        }
        for mode in tmux nohup systemd; do
            if _clash_service_is_active "$mode" >/dev/null 2>&1; then
                _okcat "$mode：托管进程运行中"
                any_active_status=0
            else
                _failcat "$mode：托管进程未运行" || true
            fi
        done
        return "$any_active_status"
        ;;
    --mode=*)
        mode=${1#--mode=}
        shift
        _validate_service_mode "$mode" || return 1
        ;;
    --mode)
        shift
        mode=${1:-}
        _validate_service_mode "$mode" || return 1
        shift
        ;;
    -h | --help)
        cat <<EOF

- 查看当前活跃模式状态
  clashstatus

- 查看全部托管模式状态
  clashstatus --all

EOF
        return 0
        ;;
    "")
        mode=$(_get_active_mode 2>/dev/null)
        active_status=$?
        [ "$active_status" -eq 2 ] && {
            _failcat "检测到多个托管模式同时运行，请执行 clashstatus --all"
            return 1
        }
        ;;
    *)
        _failcat "未知参数：$1"
        return 1
        ;;
    esac
    [ "$#" -eq 0 ] || {
        _failcat "未知参数：$1"
        return 1
    }
    [ -n "$mode" ] && _clash_service_is_active "$mode" >/dev/null 2>&1 || {
        _failcat "内核未运行"
        return 1
    }
    _detect_ext_addr || return 1
    local api
    api=$(_ext_api_url /version)
    local secret="$(_get_secret)"
    local auth_args=()
    [ -n "$secret" ] && auth_args=(-H "Authorization: Bearer $secret")
    curl --silent --fail --noproxy "*" "${auth_args[@]}" "$api" >/dev/null && {
        _okcat "内核运行中（mode=$mode）"
        return 0
    }
    _failcat "内核运行中但 API 不可达：$api"
    return 1
}

function clashlog() {
    _clash_service_log "$@"
}
