_ensure_sidecar_config() {
    [ -s "$CLASH_CONFIG_SIDECAR" ] && return 0

    mkdir -p "$(dirname "$CLASH_CONFIG_SIDECAR")"
    [ -x "$BIN_YQ" ] || {
        _failcat "缺少 yq：$BIN_YQ"
        return 1
    }
    "$BIN_YQ" -n '
        .["system-proxy"].enable = false |
        .["system-proxy"].mode = "silent"
    ' >"$CLASH_CONFIG_SIDECAR"
}

_get_system_proxy_enable() {
    _ensure_sidecar_config || return 1

    local enable
    enable=$("$BIN_YQ" '.["system-proxy"].enable' "$CLASH_CONFIG_SIDECAR" 2>/dev/null)
    case $enable in
    true | false)
        echo "$enable"
        ;;
    *)
        echo false
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
    _ensure_sidecar_config || return 1

    local mode
    mode=$("$BIN_YQ" '.["system-proxy"].mode // "silent"' "$CLASH_CONFIG_SIDECAR" 2>/dev/null)
    _is_valid_system_proxy_mode "$mode" && {
        echo "$mode"
        return 0
    }

    echo silent
}

_set_system_proxy_enable() {
    _ensure_sidecar_config || return 1
    "$BIN_YQ" -i ".\"system-proxy\".enable = $1" "$CLASH_CONFIG_SIDECAR"
}

_set_system_proxy_mode() {
    _ensure_sidecar_config || return 1
    "$BIN_YQ" -i ".\"system-proxy\".mode = \"$1\"" "$CLASH_CONFIG_SIDECAR"
}

_get_current_proxy_env() {
    env | grep -i -E '^(http|https|all|no)_proxy=' || true
}

_get_current_effective_proxy_env() {
    env | grep -i -E '^(http|https|all)_proxy=' || true
}

_show_current_proxy_status() {
    local proxy_env effective_proxy_env
    proxy_env=$(_get_current_proxy_env)
    effective_proxy_env=$(_get_current_effective_proxy_env)
    if [ -n "$effective_proxy_env" ]; then
        _okcat "当前终端代理：开启
$proxy_env"
        _warn_proxy_env_mismatch
    elif [ -n "$proxy_env" ]; then
        _failcat "当前终端代理：关闭（仅存在 no_proxy，不视为代理开启）
$proxy_env"
    else
        _failcat "当前终端代理：关闭"
    fi
}

_warn_proxy_env_mismatch() {
    _current_proxy_matches_system_proxy && return 0
    _failcat "当前终端代理与当前运行配置不一致；如需使用本项目代理，请执行 clashproxy off && clashproxy on 刷新" || true
    return 0
}

_show_system_proxy_mode_status() {
    _okcat "全局自动代理：enable=$(_get_system_proxy_enable) mode=$(_get_system_proxy_mode)"
}

_warn_global_auto_proxy_still_enabled() {
    local enabled

    enabled=$(_get_system_proxy_enable 2>/dev/null || printf '%s\n' false)
    [ "$enabled" = true ] || return 0
    _failcat "全局自动代理仍为开启状态；如需新终端也停止自动代理，请执行 clashproxy off -g" || true
    return 0
}

_get_runtime_proxy_ports() {
    local ports mixed_port http_port socks_port

    ports=$(_runtime_config_read_ports "$CLASH_CONFIG_RUNTIME") || return 1
    IFS='|' read -r mixed_port http_port socks_port <<<"$ports"
    [ -n "$http_port" ] || http_port=$mixed_port
    [ -n "$socks_port" ] || socks_port=$mixed_port
    [ -n "$http_port" ] || http_port=${DEFAULT_HTTP_PORT:-7890}
    [ -n "$socks_port" ] || socks_port=${DEFAULT_SOCKS_PORT:-7891}

    printf '%s %s\n' "$http_port" "$socks_port"
}

_get_system_proxy_addrs() {
    local ports http_port socks_port auth bind_addr
    ports=$(_get_runtime_proxy_ports) || return 1
    read -r http_port socks_port <<<"$ports"

    auth=$("$BIN_YQ" '.authentication[0] // ""' "$CLASH_CONFIG_RUNTIME") || {
        _failcat "authentication 读取失败：$CLASH_CONFIG_RUNTIME"
        return 1
    }
    [ -n "$auth" ] && auth=$auth@

    bind_addr=$(_get_bind_addr) || return 1
    printf '%s %s %s\n' \
        "http://${auth}${bind_addr}:${http_port}" \
        "socks5h://${auth}${bind_addr}:${socks_port}" \
        "localhost,127.0.0.1,::1"
}

_current_proxy_matches_system_proxy() {
    local addrs http_proxy_addr socks_proxy_addr no_proxy_addr
    addrs=$(_get_system_proxy_addrs) || return 1
    read -r http_proxy_addr socks_proxy_addr no_proxy_addr <<<"$addrs"

    [ "${http_proxy-}" = "$http_proxy_addr" ] &&
        [ "${HTTP_PROXY-}" = "$http_proxy_addr" ] &&
        [ "${https_proxy-}" = "$http_proxy_addr" ] &&
        [ "${HTTPS_PROXY-}" = "$http_proxy_addr" ] &&
        [ "${all_proxy-}" = "$socks_proxy_addr" ] &&
        [ "${ALL_PROXY-}" = "$socks_proxy_addr" ] &&
        [ "${no_proxy-}" = "$no_proxy_addr" ] &&
        [ "${NO_PROXY-}" = "$no_proxy_addr" ]
}

_set_system_proxy() {
    local addrs http_proxy_addr socks_proxy_addr no_proxy_addr
    addrs=$(_get_system_proxy_addrs) || return 1
    read -r http_proxy_addr socks_proxy_addr no_proxy_addr <<<"$addrs"

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
watch_proxy() {
    [[ $- == *i* ]] || return 0
    [ "$(_get_system_proxy_enable)" = true ] || return 0
    _clash_service_is_active >/dev/null 2>&1 || return 0

    case "$(_get_system_proxy_mode)" in
    none)
        return 0
        ;;
    silent)
        _set_system_proxy || return 1
        ;;
    verbose)
        _set_system_proxy || return 1
        _okcat '已按 sidecar 配置自动开启系统代理'
        ;;
    esac
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

    local action="${args[0]-}"
    local action_arg="${args[1]-}"
    local extra_arg="${args[2]-}"

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
        [ -z "$action_arg" ] && [ -z "$extra_arg" ] || {
            _failcat "未知参数：${action_arg:-$extra_arg}"
            return 1
        }
        _set_system_proxy || return 1
        if [ "$global" = true ]; then
            _proxy_set_global_enable true || return 1
            _okcat '已为当前终端开启代理，并开启全局自动代理'
        else
            _okcat '已为当前终端开启代理'
        fi
        ;;
    off)
        [ -z "$action_arg" ] && [ -z "$extra_arg" ] || {
            _failcat "未知参数：${action_arg:-$extra_arg}"
            return 1
        }
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
        [ -z "$action_arg" ] && [ -z "$extra_arg" ] || {
            _failcat "未知参数：${action_arg:-$extra_arg}"
            return 1
        }
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
