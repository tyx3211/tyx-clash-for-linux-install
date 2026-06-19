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
    _detect_proxy_port
    clashstatus >&/dev/null || placeholder_start >/dev/null 2>&1

    local deadline=$((SECONDS + 5))
    while [ "$SECONDS" -le "$deadline" ]; do
        clashstatus >&/dev/null && {
            _okcat '已开启代理环境'
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
    local is_active=false
    placeholder_is_active >&/dev/null && is_active=true
    pgrep -f "$BIN_KERNEL" >/dev/null && is_active=true
    [ "$is_active" = true ] && {
        placeholder_stop >/dev/null
        placeholder_stop >/dev/null
        placeholder_is_active >&/dev/null || pgrep -f "$BIN_KERNEL" >/dev/null && {
            _failcat '代理环境关闭失败'
            return 1
        }
    }
    _unset_system_proxy
    _okcat '已关闭代理环境'
}

clashrestart() {
    clashoff >/dev/null
    clashon
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
    placeholder_is_active >&/dev/null || {
        _failcat "内核未运行"
        return 1
    }
    _detect_ext_addr
    local api="http://${EXT_IP}:${EXT_PORT}/version"
    local secret="$(_get_secret)"
    local auth_args=()
    [ -n "$secret" ] && auth_args=(-H "Authorization: Bearer $secret")
    curl --silent --fail --noproxy "*" "${auth_args[@]}" "$api" >/dev/null && {
        _okcat "内核运行中"
        return 0
    }
    _failcat "内核运行中但 API 不可达：$api"
    return 1
}

function clashlog() {
    placeholder_log "$@"
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
    local had_proxy_env=false
    _has_current_proxy_env && had_proxy_env=true

    _merge_config || return 1
    placeholder_stop >/dev/null
    placeholder_stop >/dev/null
    sleep 0.1
    placeholder_start >/dev/null
    sleep 0.1

    [ "$had_proxy_env" = true ] && _set_system_proxy
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
        "$BIN_YQ" -i ".secret = \"$1\"" "$CLASH_CONFIG_MIXIN" || {
            _failcat "密钥更新失败，请重新输入"
            return 1
        }
        _merge_config_restart
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
    [ "$(_get_installed_init_type)" = "systemd" ]
}

_restore_tun_mixin() {
    local backup=$1
    local restart_after_restore=$2

    [ -f "$backup" ] || return 0
    /bin/mv -f "$backup" "$CLASH_CONFIG_MIXIN"
    _merge_config || return 1
    [ "$restart_after_restore" = true ] && placeholder_start >/dev/null
}

tunstatus() {
    _tun_supported || {
        _failcat "当前 INIT_TYPE=${INIT_TYPE:-tmux} 不支持 Tun；如需 Tun，请使用 --init systemd 重新安装"
        return 1
    }

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
    _tun_supported || {
        _failcat "当前 INIT_TYPE=${INIT_TYPE:-tmux} 不支持 Tun；如需 Tun，请使用 --init systemd 重新安装"
        return 1
    }

    local was_active=false backup="${CLASH_CONFIG_TEMP}.tun.bak"
    placeholder_is_active >&/dev/null && was_active=true
    tunstatus 2>/dev/null && return 0
    cat "$CLASH_CONFIG_MIXIN" >"$backup" || return 1
    placeholder_stop >/dev/null
    "$BIN_YQ" -i '.tun.enable = true' "$CLASH_CONFIG_MIXIN"
    _merge_config || {
        _restore_tun_mixin "$backup" "$was_active"
        return 1
    }
    placeholder_start >/dev/null || {
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
            placeholder_stop >/dev/null
            placeholder_start >/dev/null
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
        _failcat "当前 INIT_TYPE=${INIT_TYPE:-tmux} 不支持 Tun；如需 Tun，请使用 --init systemd 重新安装"
        return 1
    }

    _is_tun_enabled || {
        tunstatus >/dev/null 2>&1 || return 0
    }
    local was_active=false backup="${CLASH_CONFIG_TEMP}.tun.bak"
    placeholder_is_active >&/dev/null && was_active=true
    cat "$CLASH_CONFIG_MIXIN" >"$backup" || return 1
    placeholder_stop >/dev/null
    "$BIN_YQ" -i '.tun.enable = false' "$CLASH_CONFIG_MIXIN"
    _merge_config || {
        _restore_tun_mixin "$backup" "$was_active"
        return 1
    }
    placeholder_start >/dev/null
    tunstatus >&/dev/null && {
        _failcat "Tun 模式关闭失败"
        return 1
    }
    /usr/bin/rm -f "$backup"
    _okcat "Tun 模式已关闭"
}

function clashtun() {
    case "$1" in
    -h | --help)
        cat <<EOF

- 查看 Tun 状态
  clashtun

- 开启 Tun 模式（仅 INIT_TYPE=systemd）
  clashtun on

- 关闭 Tun 模式（仅 INIT_TYPE=systemd）
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
        placeholder_follow_log &
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
    cat "$profile_path" >"$CLASH_CONFIG_BASE"
    _merge_config_restart || return 1
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
    local arg is_convert
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
    _logging_sub "✅ 订阅更新成功：[$id] $url"
    cat "$CLASH_CONFIG_TEMP" >"$profile_path"
    use=$("$BIN_YQ" '.use // ""' "$CLASH_PROFILES_META")
    [ "$use" = "$id" ] && clashsub use "$use" && return
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
        clashon
        ;;
    off)
        shift
        clashoff
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
  proxy                 系统代理
  status                内核状态
  ui                    面板地址
  sub                   订阅管理
  log                   内核日志
  tun                   管理 Tun 模式
  mixin                 Mixin 配置
  secret                Web 密钥
  upgrade               升级内核

Global Options:
  -h, --help            显示帮助信息

For more help on how to use clashctl, head to https://github.com/tyx3211/tyx-clash-for-linux-install/tree/nosudo-tmux
EOF
}
