#!/usr/bin/env bash

THIS_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE:-${(%):-%N}}")")
. "$THIS_SCRIPT_DIR/common.sh"

DEFAULT_HTTP_PORT=7890
DEFAULT_SOCKS_PORT=7891
CLASH_INSTALLED_INIT_TYPE=${CLASH_INSTALLED_INIT_TYPE:-__CLASH_INIT_TYPE_UNSET__}

_ensure_sidecar_config() {
    [ -s "$CLASH_CONFIG_SIDECAR" ] && return 0

    mkdir -p "$CLASH_RESOURCES_DIR"
    cat >"$CLASH_CONFIG_SIDECAR" <<'EOF'
# clashctl 自身的附加行为配置，不会传给 mihomo / clash 内核。
system-proxy:
  enable: true
  # none: shell 启动时不自动写入代理变量
  # silent: shell 启动时静默写入代理变量
  # verbose: shell 启动时写入代理变量并打印提示
  mode: silent
EOF
}

_get_system_proxy_enable() {
    _ensure_sidecar_config

    local enable
    enable=$("$BIN_YQ" '.["system-proxy"].enable' "$CLASH_CONFIG_SIDECAR" 2>/dev/null)
    case $enable in
    true | false)
        echo "$enable"
        ;;
    *)
        echo true
        ;;
    esac
}

_is_valid_system_proxy_mode() {
    case "$1" in
    none | silent | verbose)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

_get_system_proxy_mode() {
    _ensure_sidecar_config

    local mode
    mode=$("$BIN_YQ" '.["system-proxy"].mode // "silent"' "$CLASH_CONFIG_SIDECAR" 2>/dev/null)
    _is_valid_system_proxy_mode "$mode" && {
        echo "$mode"
        return 0
    }

    echo silent
}

_set_system_proxy_enable() {
    _ensure_sidecar_config
    "$BIN_YQ" -i ".\"system-proxy\".enable = $1" "$CLASH_CONFIG_SIDECAR"
}

_set_system_proxy_mode() {
    _ensure_sidecar_config
    "$BIN_YQ" -i ".\"system-proxy\".mode = \"$1\"" "$CLASH_CONFIG_SIDECAR"
}

_get_current_proxy_env() {
    env | grep -i -E '^(http|https|all|no)_proxy=' || true
}

_has_current_proxy_env() {
    [ -n "$(_get_current_proxy_env)" ]
}

_show_current_proxy_status() {
    local proxy_env
    proxy_env=$(_get_current_proxy_env)
    if [ -n "$proxy_env" ]; then
        _okcat "当前终端代理：开启
$proxy_env"
    else
        _failcat "当前终端代理：关闭"
    fi
}

_show_system_proxy_mode_status() {
    _okcat "全局自动代理：enable=$(_get_system_proxy_enable) mode=$(_get_system_proxy_mode)"
}

_get_runtime_proxy_ports() {
    local mixed_port http_port socks_port
    mixed_port=$("$BIN_YQ" '.mixed-port // ""' "$CLASH_CONFIG_RUNTIME")
    http_port=$("$BIN_YQ" '.port // ""' "$CLASH_CONFIG_RUNTIME")
    socks_port=$("$BIN_YQ" '.socks-port // ""' "$CLASH_CONFIG_RUNTIME")

    [ -z "$http_port" ] && http_port=$mixed_port
    [ -z "$socks_port" ] && socks_port=$mixed_port
    [ -z "$http_port" ] && http_port=$DEFAULT_HTTP_PORT
    [ -z "$socks_port" ] && socks_port=$DEFAULT_SOCKS_PORT

    printf '%s %s\n' "$http_port" "$socks_port"
}

_set_system_proxy() {
    local http_port socks_port
    read -r http_port socks_port <<<"$(_get_runtime_proxy_ports)"

    local auth=$("$BIN_YQ" '.authentication[0] // ""' "$CLASH_CONFIG_RUNTIME")
    [ -n "$auth" ] && auth=$auth@

    local bind_addr=$(_get_bind_addr)
    local http_proxy_addr="http://${auth}${bind_addr}:${http_port}"
    local socks_proxy_addr="socks5h://${auth}${bind_addr}:${socks_port}"
    local no_proxy_addr="localhost,127.0.0.1,::1"

    export http_proxy=$http_proxy_addr
    export HTTP_PROXY=$http_proxy

    export https_proxy=$http_proxy
    export HTTPS_PROXY=$https_proxy

    export all_proxy=$socks_proxy_addr
    export ALL_PROXY=$all_proxy

    export no_proxy=$no_proxy_addr
    export NO_PROXY=$no_proxy
}
_unset_system_proxy() {
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset all_proxy
    unset ALL_PROXY
    unset no_proxy
    unset NO_PROXY
}

_validate_service_mode() {
    case "$1" in
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
    _validate_service_mode "$mode" >/dev/null || mode=tmux
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
    awk -F': *' '$1 == "active_mode" { print $2; found=1; exit } END { exit found ? 0 : 1 }' "$CLASH_SERVICE_STATE"
}

_write_service_state() {
    local mode=$1 pid=${2:-}
    mkdir -p "$CLASH_RESOURCES_DIR"
    {
        printf 'active_mode: %s\n' "$mode"
        [ -n "$pid" ] && printf 'pid: %s\n' "$pid"
        printf 'started_at: %s\n' "$(date +%s)"
        printf 'bin_kernel: %s\n' "$BIN_KERNEL"
        printf 'config_runtime: %s\n' "$CLASH_CONFIG_RUNTIME"
    } >"$CLASH_SERVICE_STATE"
}

_clear_service_state() {
    /usr/bin/rm -f "$CLASH_SERVICE_STATE"
}

_clash_install_id() {
    printf '%s' "$CLASH_BASE_DIR" | cksum | awk '{print $1}'
}

_clash_tmux_session() {
    printf 'clash-%s-%s\n' "$KERNEL_NAME" "$(_clash_install_id)"
}

_pid_matches_current_kernel() {
    local pid=$1 exe cmdline
    [ -n "$pid" ] && [ -d "/proc/$pid" ] || return 1
    exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
    [ "$exe" = "$BIN_KERNEL" ] || return 1
    cmdline=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)
    case "$cmdline" in
    *" -d ${CLASH_RESOURCES_DIR} "* | *" -d ${CLASH_RESOURCES_DIR}"*)
        case "$cmdline" in
        *" -f ${CLASH_CONFIG_RUNTIME} "* | *" -f ${CLASH_CONFIG_RUNTIME}"*)
            return 0
            ;;
        esac
        ;;
    esac
    return 1
}

_clash_adapter_tmux_start() {
    command -v tmux >/dev/null || {
        _failcat "未检测到 tmux，请先安装 tmux 或使用 --mode nohup"
        return 1
    }
    local session kernel_cmd
    session=$(_clash_tmux_session)
    kernel_cmd="$BIN_KERNEL -d $CLASH_RESOURCES_DIR -f $CLASH_CONFIG_RUNTIME >> $FILE_LOG 2>&1"
    tmux new-session -d -s "$session" "$kernel_cmd"
}

_clash_adapter_tmux_stop() {
    local session
    session=$(_clash_tmux_session)
    tmux has-session -t "$session" 2>/dev/null || return 0
    tmux kill-session -t "$session" 2>/dev/null
}

_clash_adapter_tmux_is_active() {
    command -v tmux >/dev/null || return 1
    tmux has-session -t "$(_clash_tmux_session)" 2>/dev/null
}

_clash_adapter_nohup_start() {
    nohup "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" >>"$FILE_LOG" 2>&1 &
    echo $! >"$FILE_PID"
}

_clash_adapter_nohup_stop() {
    local pid
    pid=$(cat "$FILE_PID" 2>/dev/null || true)
    _pid_matches_current_kernel "$pid" || {
        /usr/bin/rm -f "$FILE_PID"
        return 0
    }
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.2
    _pid_matches_current_kernel "$pid" && kill -KILL "$pid" 2>/dev/null || true
    /usr/bin/rm -f "$FILE_PID"
}

_clash_adapter_nohup_is_active() {
    local pid
    pid=$(cat "$FILE_PID" 2>/dev/null || true)
    _pid_matches_current_kernel "$pid"
}

_systemctl() {
    if [ "$(id -u)" -eq 0 ]; then
        systemctl "$@"
    else
        sudo systemctl "$@"
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
    _systemctl start "$KERNEL_NAME"
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
    mode=$(_service_state_active_mode 2>/dev/null || true)
    if [ -n "$mode" ] && _validate_service_mode "$mode" >/dev/null &&
        _clash_adapter_call "$mode" is_active >/dev/null 2>&1; then
        printf '%s\n' "$mode"
        return 0
    fi

    modes=$(_list_active_modes)
    count=$(printf '%s\n' "$modes" | sed '/^$/d' | wc -l)
    case "$count" in
    0)
        return 1
        ;;
    1)
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
    [ "$mode" = nohup ] && pid=$(cat "$FILE_PID" 2>/dev/null || true)
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
    less <"$FILE_LOG" "$@"
}

_clash_service_follow_log() {
    tail -f -n 0 "$FILE_LOG" "$@"
}

_detect_proxy_port() {
    local mixed_port=$("$BIN_YQ" '.mixed-port // ""' "$CLASH_CONFIG_RUNTIME")
    local http_port=$("$BIN_YQ" '.port // ""' "$CLASH_CONFIG_RUNTIME")
    local socks_port=$("$BIN_YQ" '.socks-port // ""' "$CLASH_CONFIG_RUNTIME")
    [ -z "$mixed_port" ] && [ -z "$http_port" ] && [ -z "$socks_port" ] && {
        http_port=$DEFAULT_HTTP_PORT
        socks_port=$DEFAULT_SOCKS_PORT
    }

    local newPort count=0
    local port_list=()
    [ -n "$mixed_port" ] && port_list+=("mixed-port|$mixed_port")
    [ -n "$http_port" ] && port_list+=("port|$http_port")
    [ -n "$socks_port" ] && port_list+=("socks-port|$socks_port")
    clashstatus >&/dev/null && local isActive='true'
    for entry in "${port_list[@]}"; do
        local yaml_key="${entry%|*}"
        local var_val="${entry#*|}"

        [ -n "$var_val" ] && _is_port_used "$var_val" && [ "$isActive" != "true" ] && {
            newPort=$(_get_random_port) || return
            ((count++))
            _failcat '🎯' "端口冲突：[$yaml_key] $var_val 🎲 随机分配 $newPort"
            "$BIN_YQ" -i ".${yaml_key} = $newPort" "$CLASH_CONFIG_MIXIN"
        }
    done
    ((count)) && _merge_config
}

function clashon() {
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

    _detect_proxy_port
    active=$(_get_active_mode 2>/dev/null)
    active_status=$?
    if [ "$active_status" -eq 0 ]; then
        [ "$active" = "$mode" ] && {
            _okcat "已开启代理环境（mode=$active）"
            return 0
        }
        _failcat "当前 $active 模式正在运行，请先 clashoff，或执行 clashrestart --mode $mode"
        return 1
    fi
    if [ "$active_status" -eq 2 ]; then
        _failcat "检测到多个托管模式同时运行，请先执行 clashstatus --all 并用 clashoff --mode <mode> 清理"
        return 1
    fi

    _clash_service_start "$mode" >/dev/null 2>&1 || {
        _failcat "启动失败：无法以 $mode 模式启动"
        return 1
    }

    local deadline=$((SECONDS + 5))
    while [ "$SECONDS" -le "$deadline" ]; do
        clashstatus >&/dev/null && {
            _okcat "已开启代理环境（mode=$mode）"
            return 0
        }
        sleep 0.2
    done

    {
        _failcat '启动失败: 执行 clashlog 查看日志'
        return 1
    }
}

watch_proxy() {
    [[ $- == *i* ]] || return 0
    _has_current_proxy_env && return 0
    [ "$(_get_system_proxy_enable)" = true ] || return 0

    case "$(_get_system_proxy_mode)" in
    none)
        return 0
        ;;
    silent)
        _set_system_proxy
        ;;
    verbose)
        _set_system_proxy
        _okcat '已按 sidecar 配置自动开启系统代理'
        ;;
    esac
}

function clashoff() {
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
            _unset_system_proxy
            _okcat '已关闭代理环境'
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
            _failcat '代理环境关闭失败'
            return 1
        }
    }
    _unset_system_proxy
    _okcat '已关闭代理环境'
}

clashrestart() {
    local mode active active_status has_mode_arg=false arg
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
        clashoff --mode "$active" >/dev/null || return 1
    fi
    clashon --mode "$mode"
}

_proxy_set_global_enable() {
    _set_system_proxy_enable "$1" || {
        _failcat "全局自动代理开关更新失败"
        return 1
    }
}

function clashproxy() {
    local global=false
    local args=()
    while (($#)); do
        case "$1" in
        -g | --global)
            global=true
            ;;
        *)
            args+=("$1")
            ;;
        esac
        shift
    done

    local action="${args[0]}"
    local action_arg="${args[1]}"

    case "$action" in
    -h | --help)
        cat <<EOF

- 查看当前终端代理状态
  clashproxy status

- 仅为当前终端开启代理
  clashproxy on

- 仅为当前终端关闭代理
  clashproxy off

- 为当前终端开启代理，并开启全局自动代理
  clashproxy on -g
  clashproxy -g on

- 为当前终端关闭代理，并关闭全局自动代理
  clashproxy off -g
  clashproxy -g off

- 查看或设置新终端自动代理模式
  clashproxy mode
  clashproxy mode status
  clashproxy mode none|silent|verbose
  clashproxy mode --help

EOF
        return 0
        ;;
    on)
        if [ "$global" = true ]; then
            _proxy_set_global_enable true || return 1
        fi
        _set_system_proxy
        if [ "$global" = true ]; then
            _okcat '已为当前终端开启代理，并开启全局自动代理'
        else
            _okcat '已为当前终端开启代理'
        fi
        ;;
    off)
        if [ "$global" = true ]; then
            _proxy_set_global_enable false || return 1
        fi
        _unset_system_proxy
        if [ "$global" = true ]; then
            _okcat '已为当前终端关闭代理，并关闭全局自动代理'
        else
            _okcat '已为当前终端关闭代理'
        fi
        ;;
    mode)
        [ "$global" = true ] && {
            _failcat "mode 子命令不支持 -g/--global"
            return 1
        }
        case "$action_arg" in
        "" | status)
            _show_system_proxy_mode_status
            ;;
        -h | --help)
            cat <<EOF

- 查看新终端自动代理模式
  clashproxy mode
  clashproxy mode status

- 设置新终端自动代理模式
  clashproxy mode none|silent|verbose

EOF
            ;;
        *)
            _is_valid_system_proxy_mode "$action_arg" || {
                _failcat "无效模式：$action_arg，可选值：none、silent、verbose"
                return 1
            }
            _set_system_proxy_mode "$action_arg" || {
                _failcat "自动系统代理模式更新失败"
                return 1
            }
            _okcat "全局自动代理模式已更新：$action_arg"
            ;;
        esac
        ;;
    "" | status)
        [ "$global" = true ] && {
            _failcat "status 子命令不支持 -g/--global；查看全局状态请用 clashproxy mode status"
            return 1
        }
        _show_current_proxy_status
        ;;
    *)
        _failcat "未知参数：${action:-<empty>}"
        return 1
        ;;
    esac
}

function clashstatus() {
    local mode active_status status=1
    case "${1:-}" in
    --all)
        for mode in tmux nohup systemd; do
            if _clash_service_is_active "$mode" >/dev/null 2>&1; then
                _okcat "$mode：运行中"
                status=0
            else
                _failcat "$mode：未运行" || true
            fi
        done
        return "$status"
        ;;
    --mode=*)
        mode=${1#--mode=}
        _validate_service_mode "$mode" || return 1
        ;;
    --mode)
        shift
        mode=${1:-}
        _validate_service_mode "$mode" || return 1
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
    [ -n "$mode" ] && _clash_service_is_active "$mode" >/dev/null 2>&1 || {
        _failcat "内核未运行"
        return 1
    }
    _detect_ext_addr
    local api="http://${EXT_IP}:${EXT_PORT}/version"
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

function clashui() {
    _detect_ext_addr
    clashstatus >&/dev/null || clashon >/dev/null
    local query_url='api64.ipify.org' # ifconfig.me
    local public_ip=$(curl -s --noproxy "*" --location --max-time 2 $query_url)
    local public_address="http://${public_ip:-公网}:${EXT_PORT}/ui"

    local local_ip=$EXT_IP
    local local_address="http://${local_ip}:${EXT_PORT}/ui"
    printf "\n"
    printf "╔═══════════════════════════════════════════════╗\n"
    printf "║                %s                  ║\n" "$(_okcat 'Web 控制台')"
    printf "║═══════════════════════════════════════════════║\n"
    printf "║                                               ║\n"
    printf "║     🔓 注意放行端口：%-5s                    ║\n" "$EXT_PORT"
    printf "║     🏠 内网：%-31s  ║\n" "$local_address"
    printf "║     🌏 公网：%-31s  ║\n" "$public_address"
    printf "║     ☁️  公共：%-31s  ║\n" "$URL_CLASH_UI"
    printf "║                                               ║\n"
    printf "╚═══════════════════════════════════════════════╝\n"
    printf "\n"
}

_merge_config() {
    local runtime_backup="${CLASH_CONFIG_RUNTIME}.merge.bak.$$"
    [ -f "$CLASH_CONFIG_RUNTIME" ] && cat "$CLASH_CONFIG_RUNTIME" >"$runtime_backup"

    # shellcheck disable=SC2016
    "$BIN_YQ" eval-all '
      ########################################
      #              Load Files              #
      ########################################
      select(fileIndex==0) as $config |
      select(fileIndex==1) as $mixin |
      
      ########################################
      #              Deep Merge              #
      ########################################
      (($config // {}) * $mixin) as $runtime |
      $runtime |
      
      ########################################
      #               Rules                  #
      ########################################
      .rules = (
        ($mixin.rules.prefix // []) +
        ($config.rules // []) +
        ($mixin.rules.suffix // [])
      ) |
      
      ########################################
      #                Proxies               #
      ########################################
      .proxies = (
        ($mixin.proxies.prefix // []) +
        (
          ($config.proxies // []) as $configList |
          ($mixin.proxies.override // []) as $overrideList |
          $configList | map(
            . as $configItem |
            (
              $overrideList[] | select(.name == $configItem.name)
            ) // $configItem
          )
        ) +
        ($mixin.proxies.suffix // [])
      ) |
      
      ########################################
      #             ProxyGroups              #
      ########################################
      .proxy-groups = (
        ($mixin.proxy-groups.prefix // []) +
        (
          ($config.proxy-groups // []) as $configList |
          ($mixin.proxy-groups.override // []) as $overrideList |
          $configList | map(
            . as $configItem |
            (
              $overrideList[] | select(.name == $configItem.name)
            ) // $configItem
          )
        ) +
        ($mixin.proxy-groups.suffix // [])
      ) |

      ########################################
      #         ProxyGroups Inject           #
      ########################################
      ($mixin.proxy-groups.inject // {}) as $inj |
      .proxy-groups[] |= (
        . as $g |
        ($inj | .[$g.name] // []) as $extra |
        .proxies = (.proxies + $extra | unique)
      )
    ' "$CLASH_CONFIG_BASE" "$CLASH_CONFIG_MIXIN" >"$CLASH_CONFIG_RUNTIME" || {
        if [ -f "$runtime_backup" ]; then
            /bin/mv -f "$runtime_backup" "$CLASH_CONFIG_RUNTIME"
        else
            /usr/bin/rm -f "$CLASH_CONFIG_RUNTIME"
        fi
        _failcat "验证失败：请检查 Mixin 配置"
        return 1
    }
    _valid_config "$CLASH_CONFIG_RUNTIME" || {
        if [ -f "$runtime_backup" ]; then
            /bin/mv -f "$runtime_backup" "$CLASH_CONFIG_RUNTIME"
        else
            /usr/bin/rm -f "$CLASH_CONFIG_RUNTIME"
        fi
        _failcat "验证失败：请检查 Mixin 配置"
        return 1
    }
    /usr/bin/rm -f "$runtime_backup"
}

_merge_config_restart() {
    local had_proxy_env=false mode active_status
    _has_current_proxy_env && had_proxy_env=true
    mode=$(_get_active_mode 2>/dev/null)
    active_status=$?
    [ "$active_status" -eq 2 ] && {
        _failcat "检测到多个托管模式同时运行，请先手动清理后再刷新配置"
        return 1
    }
    [ "$active_status" -ne 0 ] && mode=$(_get_default_service_mode)

    _merge_config || return 1
    _clash_service_stop "$mode" >/dev/null 2>&1 || true
    sleep 0.1
    _clash_service_start "$mode" >/dev/null || return 1
    sleep 0.1

    if [ "$had_proxy_env" = true ]; then
        _set_system_proxy || return 1
    fi
    return 0
}
_get_secret() {
    "$BIN_YQ" '.secret // ""' "$CLASH_CONFIG_RUNTIME"
}
function clashsecret() {
    case "$1" in
    -h | --help)
        cat <<EOF

- 查看 Web 密钥
  clashsecret

- 修改 Web 密钥
  clashsecret <new_secret>

EOF
        return 0
        ;;
    esac

    case $# in
    0)
        _okcat "当前密钥：$(_get_secret)"
        ;;
    1)
        local backup="${CLASH_CONFIG_MIXIN}.secret.bak.$$"
        cat "$CLASH_CONFIG_MIXIN" >"$backup" || return 1
        CLASHCTL_SECRET=$1 "$BIN_YQ" -i '.secret = strenv(CLASHCTL_SECRET)' "$CLASH_CONFIG_MIXIN" || {
            /bin/mv -f "$backup" "$CLASH_CONFIG_MIXIN"
            _failcat "密钥更新失败，请重新输入"
            return 1
        }
        _merge_config_restart || {
            /bin/mv -f "$backup" "$CLASH_CONFIG_MIXIN"
            _merge_config >/dev/null 2>&1 || true
            _failcat "密钥未生效，请检查配置或内核状态"
            return 1
        }
        /usr/bin/rm -f "$backup"
        _okcat "密钥更新成功，已重启生效"
        ;;
    *)
        _failcat "密钥不要包含空格或使用引号包围"
        ;;
    esac
}

_get_installed_init_type() {
    case "$CLASH_INSTALLED_INIT_TYPE" in
    "" | __CLASH_INIT_TYPE_UNSET__)
        echo "${INIT_TYPE:-tmux}"
        ;;
    *)
        echo "$CLASH_INSTALLED_INIT_TYPE"
        ;;
    esac
}

_tun_supported() {
    _clash_systemd_registered
}

_require_tun_runtime() {
    _tun_supported || {
        _failcat "当前安装未注册可用的 systemd 服务；如需 Tun，请先 sudo bash install.sh --init systemd"
        return 1
    }

    local active active_status
    active=$(_get_active_mode 2>/dev/null)
    active_status=$?
    [ "$active_status" -eq 0 ] && [ "$active" = systemd ] && return 0

    _failcat "Tun 需要当前内核以 systemd 模式运行；请先执行 clashrestart --mode systemd"
    return 1
}

_restore_tun_mixin() {
    local backup=$1
    local restart_after_restore=$2

    [ -f "$backup" ] || return 0
    /bin/mv -f "$backup" "$CLASH_CONFIG_MIXIN"
    _merge_config || return 1
    [ "$restart_after_restore" = true ] && _clash_service_start systemd >/dev/null
}

tunstatus() {
    _require_tun_runtime || return 1

    command -v ip >/dev/null || {
        _failcat "未检测到 ip 命令，无法判断 Tun 状态"
        return 1
    }

    local device
    device=$("$BIN_YQ" '.tun.device // ""' "$CLASH_CONFIG_RUNTIME")
    [ -z "$device" ] && device="Meta"
    ip link show "$device" >/dev/null 2>&1 && {
        _okcat 'Tun 状态：启用'
        return 0
    }
    _failcat 'Tun 状态：关闭'
    return 1
}

_is_tun_enabled() {
    "$BIN_YQ" -e '.tun.enable == true' "$CLASH_CONFIG_RUNTIME" >&/dev/null
}

tunon() {
    _require_tun_runtime || return 1

    local was_active=false backup="${CLASH_CONFIG_TEMP}.tun.bak"
    _clash_service_is_active systemd >&/dev/null && was_active=true
    tunstatus 2>/dev/null && return 0
    cat "$CLASH_CONFIG_MIXIN" >"$backup" || return 1
    _clash_service_stop systemd >/dev/null
    "$BIN_YQ" -i '.tun.enable = true' "$CLASH_CONFIG_MIXIN"
    _merge_config || {
        _restore_tun_mixin "$backup" "$was_active"
        return 1
    }
    _clash_service_start systemd >/dev/null || {
        _restore_tun_mixin "$backup" "$was_active"
        _failcat 'Tun 模式开启失败'
        return 1
    }
    sleep 1
    tunstatus >&/dev/null || {
        [ "$KERNEL_NAME" = 'mihomo' ] && {
            "$BIN_YQ" -i '.tun.auto-redirect = false' "$CLASH_CONFIG_MIXIN"
            _merge_config || {
                _restore_tun_mixin "$backup" "$was_active"
                return 1
            }
            _clash_service_stop systemd >/dev/null
            _clash_service_start systemd >/dev/null
            sleep 1
            tunstatus >&/dev/null || {
                _restore_tun_mixin "$backup" "$was_active"
                _failcat 'Tun 模式开启失败，请检查代理内核日志'
                return 1
            }
            /usr/bin/rm -f "$backup"
            _okcat "Tun 模式已开启"
            return 0
        }
        _restore_tun_mixin "$backup" "$was_active"
        _failcat 'Tun 模式开启失败，请检查代理内核日志'
        return 1
    }
    /usr/bin/rm -f "$backup"
    _okcat "Tun 模式已开启"
}

tunoff() {
    _tun_supported || {
        _failcat "当前安装未注册可用的 systemd 服务；如需 Tun，请先 sudo bash install.sh --init systemd"
        return 1
    }

    _is_tun_enabled || {
        tunstatus >/dev/null 2>&1 || return 0
    }
    local was_active=false backup="${CLASH_CONFIG_TEMP}.tun.bak"
    _clash_service_is_active systemd >&/dev/null && was_active=true
    cat "$CLASH_CONFIG_MIXIN" >"$backup" || return 1
    [ "$was_active" = true ] && _clash_service_stop systemd >/dev/null
    "$BIN_YQ" -i '.tun.enable = false' "$CLASH_CONFIG_MIXIN"
    _merge_config || {
        _restore_tun_mixin "$backup" "$was_active"
        return 1
    }
    if [ "$was_active" = true ]; then
        _clash_service_start systemd >/dev/null || {
            _restore_tun_mixin "$backup" "$was_active"
            _failcat "Tun 模式关闭失败，内核未能恢复启动"
            return 1
        }
        tunstatus >&/dev/null && {
            _restore_tun_mixin "$backup" "$was_active"
            _failcat "Tun 模式关闭失败"
            return 1
        }
    fi
    /usr/bin/rm -f "$backup"
    _okcat "Tun 模式已关闭"
}

function clashtun() {
    case "$1" in
    -h | --help)
        cat <<EOF

- 查看 Tun 状态
  clashtun

- 开启 Tun 模式（需要当前内核以 systemd 模式运行）
  clashtun on

- 关闭 Tun 模式（需要已注册 systemd 服务）
  clashtun off

EOF
        return 0
        ;;
    on)
        tunon
        ;;
    off)
        tunoff
        ;;
    *)
        tunstatus
        ;;
    esac
}

function clashmixin() {
    case "$1" in
    -h | --help)
        cat <<EOF

- 查看 Mixin 配置：$CLASH_CONFIG_MIXIN
  clashmixin

- 编辑 Mixin 配置
  clashmixin -e

- 显式合并 Mixin 并重启内核
  clashmixin -m

- 查看原始订阅配置：$CLASH_CONFIG_BASE
  clashmixin -c

- 查看运行时配置：$CLASH_CONFIG_RUNTIME
  clashmixin -r

EOF
        return 0
        ;;
    -m | --merge)
        _merge_config_restart && _okcat "配置已显式合并并重启生效"
        ;;
    -e)
        "${EDITOR:-vim}" "$CLASH_CONFIG_MIXIN" && {
            _merge_config_restart && _okcat "配置更新成功，已重启生效"
        }
        ;;
    -r)
        less "$CLASH_CONFIG_RUNTIME"
        ;;
    -c)
        less "$CLASH_CONFIG_BASE"
        ;;
    *)
        less "$CLASH_CONFIG_MIXIN"
        ;;
    esac
}

function clashupgrade() {
    for arg in "$@"; do
        case $arg in
        -h | --help)
            cat <<EOF
Usage:
  clashupgrade [OPTIONS]

Options:
  -v, --verbose       输出内核升级日志
  -r, --release       升级至稳定版
  -a, --alpha         升级至测试版
  -h, --help          显示帮助信息

EOF
            return 0
            ;;
        -v | --verbose)
            local log_flag=true
            ;;
        -r | --release)
            channel="release"
            ;;
        -a | --alpha)
            channel="alpha"
            ;;
        *)
            channel=""
            ;;
        esac
    done

    _detect_ext_addr
    clashstatus >&/dev/null || clashon >/dev/null
    _okcat '⏳' "请求内核升级..."
    local follow_pid=
    [ "$log_flag" = true ] && {
        _clash_service_follow_log &
        follow_pid=$!
    }
    local res=$(
        curl -X POST \
            --silent \
            --noproxy "*" \
            --location \
            -H "Authorization: Bearer $(_get_secret)" \
            "http://${EXT_IP}:${EXT_PORT}/upgrade?channel=$channel"
    )
    [ -n "$follow_pid" ] && kill "$follow_pid" >/dev/null 2>&1

    grep '"status":"ok"' <<<"$res" && {
        _okcat "内核升级成功"
        return 0
    }
    grep 'already using latest version' <<<"$res" && {
        _okcat "已是最新版本"
        return 0
    }
    _failcat "内核升级失败，请检查网络或稍后重试"
}

function clashsub() {
    case "$1" in
    add)
        shift
        _sub_add "$@"
        ;;
    del)
        shift
        _sub_del "$@"
        ;;
    list | ls | '')
        shift
        _sub_list "$@"
        ;;
    use)
        shift
        _sub_use "$@"
        ;;
    update)
        shift
        _sub_update "$@"
        ;;
    log)
        shift
        _sub_log "$@"
        ;;
    -h | --help | *)
        cat <<EOF
clashsub - Clash 订阅管理工具

Usage: 
  clashsub COMMAND [OPTIONS]

Commands:
  add <url>       添加订阅
  ls              查看订阅
  del <id>        删除订阅
  use <id>        使用订阅
  update [id]     更新订阅
  log             订阅日志

Options:
  update:
    --auto        配置自动更新
    --convert     使用订阅转换
EOF
        ;;
    esac
}
_sub_add() {
    local url=$1
    [ -z "$url" ] && {
        echo -n "$(_okcat '✈️ ' '请输入要添加的订阅链接：')"
        read -r url
        [ -z "$url" ] && _error_quit "订阅链接不能为空"
    }
    local existing_id
    existing_id=$(_get_id_by_url "$url") && _error_quit "该订阅链接已存在：[$existing_id] $url"

    local CLASH_CONFIG_TEMP
    CLASH_CONFIG_TEMP=$(_make_config_temp) || {
        _error_quit "无法创建订阅临时文件"
        return 1
    }
    _download_config "$CLASH_CONFIG_TEMP" "$url" || {
        _error_quit "订阅下载失败：$url"
        return 1
    }
    _valid_config "$CLASH_CONFIG_TEMP" || {
        _error_quit "订阅无效，请检查：
    原始订阅：${CLASH_CONFIG_TEMP}.raw
    转换订阅：$CLASH_CONFIG_TEMP
    转换日志：$BIN_SUBCONVERTER_LOG"
        return 1
    }

    local id=$("$BIN_YQ" '.profiles // [] | (map(.id) | max) // 0 | . + 1' "$CLASH_PROFILES_META")
    local profile_path="${CLASH_PROFILES_DIR}/${id}.yaml"
    mv "$CLASH_CONFIG_TEMP" "$profile_path"

    PROFILE_ID=$id PROFILE_PATH=$profile_path PROFILE_URL=$url \
        "$BIN_YQ" -i '
            .profiles = (.profiles // []) +
            [{
              "id": (env(PROFILE_ID) | tonumber),
              "path": env(PROFILE_PATH),
              "url": env(PROFILE_URL)
            }]
        ' "$CLASH_PROFILES_META"
    _logging_sub "➕ 已添加订阅：[$id] $url"
    _okcat '🎉' "订阅已添加：[$id] $url"
}
_sub_del() {
    local id=$1
    [ -z "$id" ] && {
        echo -n "$(_okcat '✈️ ' '请输入要删除的订阅 id：')"
        read -r id
        [ -z "$id" ] && _error_quit "订阅 id 不能为空"
    }
    local profile_path url
    profile_path=$(_get_path_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    url=$(_get_url_by_id "$id")
    use=$("$BIN_YQ" '.use // ""' "$CLASH_PROFILES_META")
    [ "$use" = "$id" ] && _error_quit "删除失败：订阅 $id 正在使用中，请先切换订阅"
    /usr/bin/rm -f "$profile_path"
    PROFILE_ID=$id "$BIN_YQ" -i 'del(.profiles[] | select((.id | tostring) == env(PROFILE_ID)))' "$CLASH_PROFILES_META"
    _logging_sub "➖ 已删除订阅：[$id] $url"
    _okcat '🎉' "订阅已删除：[$id] $url"
}
_sub_list() {
    "$BIN_YQ" "$CLASH_PROFILES_META"
}
_sub_use() {
    "$BIN_YQ" -e '.profiles // [] | length == 0' "$CLASH_PROFILES_META" >&/dev/null &&
        _error_quit "当前无可用订阅，请先添加订阅"
    local id=$1
    [ -z "$id" ] && {
        clashsub ls
        echo -n "$(_okcat '✈️ ' '请输入要使用的订阅 id：')"
        read -r id
        [ -z "$id" ] && _error_quit "订阅 id 不能为空"
    }
    local profile_path url
    profile_path=$(_get_path_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    url=$(_get_url_by_id "$id")
    local base_backup="${CLASH_CONFIG_BASE}.sub-use.bak.$$" had_base=false
    [ -f "$CLASH_CONFIG_BASE" ] && {
        cat "$CLASH_CONFIG_BASE" >"$base_backup" || return 1
        had_base=true
    }
    cat "$profile_path" >"$CLASH_CONFIG_BASE" || return 1
    _merge_config_restart || {
        if [ "$had_base" = true ]; then
            /bin/mv -f "$base_backup" "$CLASH_CONFIG_BASE"
        else
            /usr/bin/rm -f "$CLASH_CONFIG_BASE" "$base_backup"
        fi
        _merge_config >/dev/null 2>&1 || true
        return 1
    }
    /usr/bin/rm -f "$base_backup"
    "$BIN_YQ" -i ".use = $id" "$CLASH_PROFILES_META"
    _logging_sub "🔥 订阅已切换为：[$id] $url"
    _okcat '🔥' '订阅已生效'
}
_get_path_by_id() {
    PROFILE_ID=$1 "$BIN_YQ" -e '.profiles[] | select((.id | tostring) == env(PROFILE_ID)) | .path' "$CLASH_PROFILES_META" 2>/dev/null
}
_get_url_by_id() {
    PROFILE_ID=$1 "$BIN_YQ" -e '.profiles[] | select((.id | tostring) == env(PROFILE_ID)) | .url' "$CLASH_PROFILES_META" 2>/dev/null
}
_make_config_temp() {
    mkdir -p "$CLASH_RESOURCES_DIR"
    mktemp "${CLASH_RESOURCES_DIR}/temp.XXXXXX.yaml"
}
_get_id_by_url() {
    PROFILE_URL=$1 "$BIN_YQ" -e '.profiles[] | select(.url == env(PROFILE_URL)) | (.id | tostring)' "$CLASH_PROFILES_META" 2>/dev/null
}
_sub_update() {
    local arg is_convert=false
    for arg in "$@"; do
        case $arg in
        --auto)
            command -v crontab >/dev/null || _error_quit "未检测到 crontab 命令，请先安装 cron 服务"
            crontab -l 2>/dev/null | grep -Fqs "$CLASHCTL_CRON_TAG" || {
                (
                    crontab -l 2>/dev/null | grep -Fv "$CLASHCTL_CRON_TAG"
                    printf "0 0 */2 * * %s -i -c 'clashsub update' %s\n" "$SHELL" "$CLASHCTL_CRON_TAG"
                ) | crontab -
            }
            _okcat "已设置定时更新订阅"
            return 0
            ;;
        --convert)
            is_convert=true
            shift
            ;;
        esac
    done
    local id=$1
    [ -z "$id" ] && id=$("$BIN_YQ" '.use // 1' "$CLASH_PROFILES_META")
    local url profile_path
    url=$(_get_url_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    profile_path=$(_get_path_by_id "$id")
    _okcat "✈️ " "更新订阅：[$id] $url"

    local CLASH_CONFIG_TEMP
    CLASH_CONFIG_TEMP=$(_make_config_temp) || {
        _error_quit "无法创建订阅临时文件"
        return 1
    }
    [ "$is_convert" = true ] && {
        _download_convert_config "$CLASH_CONFIG_TEMP" "$url" || {
            _logging_sub "❌ 订阅更新失败：[$id] $url"
            _error_quit "订阅转换失败：$url"
            return 1
        }
        _validate_downloaded_config "$CLASH_CONFIG_TEMP" || {
            _logging_sub "❌ 订阅更新失败：[$id] $url"
            _error_quit "订阅转换结果无效：$CLASH_CONFIG_TEMP"
            return 1
        }
    }
    [ "$is_convert" != true ] && {
        _download_config "$CLASH_CONFIG_TEMP" "$url" || {
            _logging_sub "❌ 订阅更新失败：[$id] $url"
            _error_quit "订阅下载失败：$url"
            return 1
        }
    }
    _valid_config "$CLASH_CONFIG_TEMP" || {
        _logging_sub "❌ 订阅更新失败：[$id] $url"
        _error_quit "订阅无效：请检查：
    原始订阅：${CLASH_CONFIG_TEMP}.raw
    转换订阅：$CLASH_CONFIG_TEMP
    转换日志：$BIN_SUBCONVERTER_LOG"
        return 1
    }
    local profile_backup="${profile_path}.update.bak.$$" had_profile=false
    [ -f "$profile_path" ] && {
        cat "$profile_path" >"$profile_backup" || return 1
        had_profile=true
    }
    cat "$CLASH_CONFIG_TEMP" >"$profile_path" || return 1
    use=$("$BIN_YQ" '.use // ""' "$CLASH_PROFILES_META")
    [ "$use" = "$id" ] && {
        clashsub use "$use" && {
            /usr/bin/rm -f "$profile_backup"
            _logging_sub "✅ 订阅更新成功：[$id] $url"
            return 0
        }
        if [ "$had_profile" = true ]; then
            /bin/mv -f "$profile_backup" "$profile_path"
        else
            /usr/bin/rm -f "$profile_path" "$profile_backup"
        fi
        return 1
    }
    /usr/bin/rm -f "$profile_backup"
    _logging_sub "✅ 订阅更新成功：[$id] $url"
    _okcat '订阅已更新'
}
_logging_sub() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") $1" >>"${CLASH_PROFILES_LOG}"
}
_sub_log() {
    tail <"${CLASH_PROFILES_LOG}" "$@"
}

function clashctl() {
    case "$1" in
    on)
        shift
        clashon "$@"
        ;;
    off)
        shift
        clashoff "$@"
        ;;
    restart)
        shift
        clashrestart "$@"
        ;;
    ui)
        shift
        clashui
        ;;
    status)
        shift
        clashstatus "$@"
        ;;
    log)
        shift
        clashlog "$@"
        ;;
    proxy)
        shift
        clashproxy "$@"
        ;;
    tun)
        shift
        clashtun "$@"
        ;;
    mixin)
        shift
        clashmixin "$@"
        ;;
    secret)
        shift
        clashsecret "$@"
        ;;
    sub)
        shift
        clashsub "$@"
        ;;
    update-self)
        shift
        bash "$CLASH_BASE_DIR/update.sh" --target "$CLASH_BASE_DIR" "$@"
        ;;
    upgrade)
        shift
        clashupgrade "$@"
        ;;
    *)
        (($#)) && shift
        clashhelp "$@"
        ;;
    esac
}

clashhelp() {
    cat <<EOF
    
Usage: 
  clashctl COMMAND [OPTIONS]

Commands:
  on                    开启代理
  off                   关闭代理
  restart               重启或切换托管模式
  proxy                 系统代理
  status                内核状态
  ui                    面板地址
  sub                   订阅管理
  log                   内核日志
  tun                   管理 Tun 模式
  mixin                 Mixin 配置
  secret                Web 密钥
  update-self           无损更新项目脚本
  upgrade               升级内核

Global Options:
  -h, --help            显示帮助信息

For more help on how to use clashctl, head to https://github.com/tyx3211/tyx-clash-for-linux-install/tree/main
EOF
}
