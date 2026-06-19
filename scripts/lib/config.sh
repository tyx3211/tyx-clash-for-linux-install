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
