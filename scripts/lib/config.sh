function clashui() {
    _detect_ext_addr || return 1
    clashstatus >&/dev/null || clashon >/dev/null || return 1
    _detect_ext_addr || return 1
    local local_ip=$EXT_IP
    local local_address
    local_address=$(_format_http_url "$local_ip" "$EXT_PORT" /ui)
    case "$local_ip" in
    127.* | localhost | ::1)
        printf "\n"
        printf "╔═══════════════════════════════════════════════╗\n"
        printf "║                %s                  ║\n" "$(_okcat 'Web 控制台')"
        printf "║═══════════════════════════════════════════════║\n"
        printf "║                                               ║\n"
        printf "║     🏠 本机：%-31s  ║\n" "$local_address"
        printf "║     🔁 转发：ssh -L %-22s ║\n" "${EXT_PORT}:127.0.0.1:${EXT_PORT} user@remote-host"
        printf "║     🌐 浏览器：%-27s  ║\n" "http://localhost:${EXT_PORT}/ui"
        printf "║     ☁️  公共：%-31s  ║\n" "$URL_CLASH_UI"
        printf "║                                               ║\n"
        printf "╚═══════════════════════════════════════════════╝\n"
        printf "\n"
        return 0
        ;;
    esac

    local query_url='api64.ipify.org' # ifconfig.me
    local public_ip=$(curl -s --noproxy "*" --location --max-time 2 $query_url)
    local public_address
    public_address=$(_format_http_url "${public_ip:-公网}" "$EXT_PORT" /ui)
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

_restore_runtime_after_restart_failure() {
    local backup=$1 mode=$2 was_active=$3

    if [ -f "$backup" ]; then
        /bin/mv -f "$backup" "$CLASH_CONFIG_RUNTIME"
    else
        /usr/bin/rm -f "$CLASH_CONFIG_RUNTIME"
    fi

    if [ "$was_active" = true ]; then
        _clash_service_start "$mode" >/dev/null 2>&1 || {
            _failcat "旧运行时配置已恢复，但 $mode 内核恢复启动失败"
            return 1
        }
    fi
    return 0
}

_merge_config_restart() {
    local had_proxy_env=false mode active_status was_active=false allowed_ext_port=
    local runtime_restart_backup="${CLASH_CONFIG_RUNTIME}.restart.bak.$$"

    _has_current_proxy_env && had_proxy_env=true
    mode=$(_get_active_mode 2>/dev/null)
    active_status=$?
    [ "$active_status" -eq 2 ] && {
        _failcat "检测到多个托管模式同时运行，请先手动清理后再刷新配置"
        return 1
    }
    if [ "$active_status" -eq 0 ]; then
        was_active=true
        _detect_ext_addr || return 1
        allowed_ext_port=$EXT_PORT
    else
        mode=$(_get_default_service_mode)
    fi

    [ -f "$CLASH_CONFIG_RUNTIME" ] && cat "$CLASH_CONFIG_RUNTIME" >"$runtime_restart_backup"

    _merge_config || {
        /usr/bin/rm -f "$runtime_restart_backup"
        return 1
    }
    _ensure_ext_addr_available "$allowed_ext_port" || {
        _restore_runtime_after_restart_failure "$runtime_restart_backup" "$mode" false >/dev/null 2>&1 || true
        return 1
    }
    [ "$was_active" = true ] && _clash_service_stop "$mode" >/dev/null 2>&1 || true
    sleep 0.1
    _clash_service_start "$mode" >/dev/null || {
        _restore_runtime_after_restart_failure "$runtime_restart_backup" "$mode" "$was_active" >/dev/null 2>&1 || true
        _failcat "配置已合并，但内核无法以 $mode 模式重启"
        return 1
    }

    local deadline=$((SECONDS + 5))
    while [ "$SECONDS" -le "$deadline" ]; do
        clashstatus >&/dev/null && {
            if [ "$had_proxy_env" = true ]; then
                _set_system_proxy || return 1
            fi
            /usr/bin/rm -f "$runtime_restart_backup"
            return 0
        }
        sleep 0.2
    done

    _clash_service_stop "$mode" >/dev/null 2>&1 || true
    _clear_service_state
    _restore_runtime_after_restart_failure "$runtime_restart_backup" "$mode" "$was_active" >/dev/null 2>&1 || true
    _failcat "配置已合并，但内核重启后健康检查失败：请执行 clashlog 查看日志"
    return 1
}
_get_secret() {
    "$BIN_YQ" '.secret // ""' "$CLASH_CONFIG_RUNTIME"
}
function clashsecret() {
    case "${1:-}" in
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
function clashmixin() {
    case "${1:-}" in
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
    local channel="" log_flag=false

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
            log_flag=true
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

    clashstatus >&/dev/null || clashon >/dev/null || return 1
    _detect_ext_addr || return 1
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
            "$(_ext_api_url "/upgrade?channel=$channel")"
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
