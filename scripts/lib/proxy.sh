_ensure_sidecar_config() {
    [ -s "$CLASH_CONFIG_SIDECAR" ] && return 0

    mkdir -p "$(dirname "$CLASH_CONFIG_SIDECAR")"
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
watch_proxy() {
    [[ $- == *i* ]] || return 0
    _has_current_proxy_env && return 0
    [ "$(_get_system_proxy_enable)" = true ] || return 0
    _clash_service_is_active >/dev/null 2>&1 || return 0

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
