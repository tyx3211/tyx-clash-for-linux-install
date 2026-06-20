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
    if [ "$restart_after_restore" = true ]; then
        _clash_service_start systemd >/dev/null || {
            _failcat "Tun 配置已回滚，但 systemd 内核恢复启动失败"
            return 1
        }
    fi
    return 0
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
            _clash_service_start systemd >/dev/null || {
                _restore_tun_mixin "$backup" "$was_active"
                _failcat 'Tun 模式开启失败，请检查代理内核日志'
                return 1
            }
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
    case "${1:-}" in
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
