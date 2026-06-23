#!/usr/bin/env bash

_detect_init() {
    _validate_init_mode

    service_log_body="less < $(_shell_quote "$FILE_LOG") \"\$@\""
    service_follow_log_body="tail -f -n 0 $(_shell_quote "$FILE_LOG") \"\$@\""
    _is_regular_sudo && {
        _SUDO=sudo
    }

    case "${INIT_TYPE}" in
    tmux)
        command -v tmux >&/dev/null || _error_quit "未检测到 tmux，请先安装后再继续"
        _tmux
        ;;
    nohup)
        _nohup
        ;;
    systemd)
        _systemd
        ;;
    *)
        _error_quit "仅支持 INIT_TYPE=tmux、nohup、systemd"
        ;;
    esac
    INIT_TYPE=$(basename "$INIT_TYPE")
}

_quote_command() {
    local out= item quoted

    for item in "$@"; do
        quoted=$(_shell_quote "$item")
        out="${out:+$out }$quoted"
    done
    printf '%s' "$out"
}

_openrc() {
    service_src="${SCRIPT_INIT_DIR}/OpenRC.sh"
    service_target="/etc/init.d/$KERNEL_NAME"

    service_enable=(rc-update add "$KERNEL_NAME" default)
    service_disable=(rc-update del "$KERNEL_NAME" default)

    service_start=(rc-service "$KERNEL_NAME" start)
    service_stop=(rc-service "$KERNEL_NAME" stop)
    service_is_active=(rc-service "$KERNEL_NAME" status)
}

_runit() {
    service_src="${SCRIPT_INIT_DIR}/runit.sh"
    service_target="/etc/sv/${KERNEL_NAME}/run"
    service_del=(rm -rf "/etc/sv/${KERNEL_NAME:-mihomo}")

    service_reload=(sleep 2)
    service_enable=(ln -s "$(dirname "$service_target")" "/etc/runit/runsvdir/default/${KERNEL_NAME}")
    service_disable=(rm -f "/etc/runit/runsvdir/current/${KERNEL_NAME}")

    service_start=(sv up "$KERNEL_NAME")
    service_stop=(sv down "$KERNEL_NAME")
    service_is_active=(sv status "$KERNEL_NAME" \| grep -qs '^run')
}

_sysvinit() {
    service_src="${SCRIPT_INIT_DIR}/SysVinit.sh"
    service_target="/etc/init.d/$KERNEL_NAME"

    command -v chkconfig >&/dev/null && {
        service_add=(chkconfig --add "$KERNEL_NAME")
        service_del=(chkconfig --del "$KERNEL_NAME")

        service_enable=(chkconfig "$KERNEL_NAME" on)
        service_disable=(chkconfig "$KERNEL_NAME" off)
    }
    command -v update-rc.d >&/dev/null && {
        service_add=(update-rc.d "$KERNEL_NAME" defaults)
        service_del=(update-rc.d "$KERNEL_NAME" remove)

        service_enable=(update-rc.d "$KERNEL_NAME" enable)
        service_disable=(update-rc.d "$KERNEL_NAME" disable)
    }

    service_start=(service "$KERNEL_NAME" start)
    service_stop=(service "$KERNEL_NAME" stop)
    service_is_active=(service "$KERNEL_NAME" status)
}

# shellcheck disable=SC2206
_systemd() {
    service_src="${SCRIPT_INIT_DIR}/systemd.sh"
    service_target="/etc/systemd/system/${KERNEL_NAME}.service"

    service_reload=($_SUDO systemctl daemon-reload)

    service_enable=($_SUDO systemctl enable "$KERNEL_NAME")
    service_disable=($_SUDO systemctl disable "$KERNEL_NAME")

    service_start=($_SUDO systemctl start "$KERNEL_NAME")
    service_stop=($_SUDO systemctl stop "$KERNEL_NAME")
    service_is_active=($_SUDO systemctl is-active "$KERNEL_NAME")

    service_run_as_user=
    _is_regular_sudo && service_run_as_user="User=$SUDO_USER"
    service_start_body="$(_quote_command "${service_start[@]}")"
    service_stop_body="$(_quote_command "${service_stop[@]}")"
    service_is_active_body="$(_quote_command "${service_is_active[@]}")"
}

_tmux() {
    TMUX_SESSION="clash-${KERNEL_NAME}"
    local kernel_cmd
    kernel_cmd="$(_quote_command "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME") >> $(_shell_quote "$FILE_LOG") 2>&1"
    service_enable=(false)
    service_disable=(false)

    service_start=(tmux new-session -d -s "$TMUX_SESSION" "$kernel_cmd")
    service_is_active=(tmux has-session -t "$TMUX_SESSION")
    service_stop=(false)

    service_start_body="tmux new-session -d -s $(_shell_quote "$TMUX_SESSION") $(_shell_quote "$kernel_cmd")"
    service_is_active_body="tmux has-session -t $(_shell_quote "$TMUX_SESSION")"
    service_stop_body="return 0"
}

_nohup() {
    service_enable=(false)
    service_disable=(false)

    service_start=(nohup "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" ">>" "$FILE_LOG" "2>&1" "&")
    service_is_active=(pgrep -fa "^${BIN_KERNEL}( |$)")
    service_stop=(false)

    service_start_body="nohup $(_shell_quote "$BIN_KERNEL") -d $(_shell_quote "$CLASH_RESOURCES_DIR") -f $(_shell_quote "$CLASH_CONFIG_RUNTIME") >> $(_shell_quote "$FILE_LOG") 2>&1 &"
    service_is_active_body="pgrep -fa $(_shell_quote "^${BIN_KERNEL}( |$)")"
    service_stop_body="return 0"
}

_preflight_escape_sed_repl() {
    printf '%s' "$1" | sed -e 's/[#&\\]/\\&/g'
}

_service_target_expected_execstart() {
    printf 'ExecStart=%s -d %s -f %s\n' "$BIN_KERNEL" "$CLASH_RESOURCES_DIR" "$CLASH_CONFIG_RUNTIME"
}

_service_target_belongs_to_current_install() {
    [ -n "${service_target:-}" ] || return 1
    [ -f "$service_target" ] || return 1

    case "${INIT_TYPE:-}" in
    systemd)
        grep -Fqx "$(_service_target_expected_execstart)" "$service_target"
        ;;
    *)
        return 0
        ;;
    esac
}

_systemd_registered_unit_belongs_to_current_install() {
    [ "${INIT_TYPE:-}" = systemd ] || return 1
    command -v systemctl >/dev/null || return 1

    local expected unit_body
    expected=$(_service_target_expected_execstart)
    unit_body=$(systemctl cat "$KERNEL_NAME" 2>/dev/null) || return 1
    printf '%s\n' "$unit_body" | grep -Fqx "$expected"
}

_systemd_registered_unit_exists() {
    [ "${INIT_TYPE:-}" = systemd ] || return 1
    command -v systemctl >/dev/null || return 1
    systemctl cat "$KERNEL_NAME" >/dev/null 2>&1
}

_install_service() {
    local kernel_desc="$KERNEL_NAME Daemon, A[nother] Clash Kernel."

    local cmd_path="${BIN_KERNEL}"
    local cmd_arg="-d ${CLASH_RESOURCES_DIR} -f ${CLASH_CONFIG_RUNTIME}"
    local cmd_full="${BIN_KERNEL} -d ${CLASH_RESOURCES_DIR} -f ${CLASH_CONFIG_RUNTIME}"

    [ -n "${service_src:-}" ] && {
        if { [ -e "$service_target" ] || [ -L "$service_target" ]; } &&
            ! _service_target_belongs_to_current_install; then
            _error_quit "systemd 服务已存在且不属于当前安装，拒绝覆盖：$service_target"
            return 1
        fi
        if [ "${INIT_TYPE:-}" = systemd ] &&
            _systemd_registered_unit_exists &&
            ! _systemd_registered_unit_belongs_to_current_install; then
            _error_quit "systemd 已注册同名服务且不属于当前安装，拒绝覆盖：$KERNEL_NAME"
            return 1
        fi

        local sed_cmd_path sed_cmd_arg sed_cmd_full sed_log_file sed_pid_file
        local sed_kernel_name sed_kernel_desc sed_run_as_user
        sed_cmd_path=$(_preflight_escape_sed_repl "$cmd_path")
        sed_cmd_arg=$(_preflight_escape_sed_repl "$cmd_arg")
        sed_cmd_full=$(_preflight_escape_sed_repl "$cmd_full")
        sed_log_file=$(_preflight_escape_sed_repl "$FILE_LOG")
        sed_pid_file=$(_preflight_escape_sed_repl "$FILE_PID")
        sed_kernel_name=$(_preflight_escape_sed_repl "$KERNEL_NAME")
        sed_kernel_desc=$(_preflight_escape_sed_repl "$kernel_desc")
        sed_run_as_user=$(_preflight_escape_sed_repl "${service_run_as_user:-}")
        /usr/bin/install -D -m 755 "$service_src" "$service_target" || return 1
        CLASH_INSTALL_SERVICE_WRITTEN=true
        if declare -p service_add >/dev/null 2>&1 && ((${#service_add[@]})); then
            "${service_add[@]}" || return 1
        fi
        sed -i \
            -e "s#placeholder_cmd_path#$sed_cmd_path#g" \
            -e "s#placeholder_cmd_args#$sed_cmd_arg#g" \
            -e "s#placeholder_cmd_full#$sed_cmd_full#g" \
            -e "s#placeholder_log_file#$sed_log_file#g" \
            -e "s#placeholder_pid_file#$sed_pid_file#g" \
            -e "s#placeholder_kernel_name#$sed_kernel_name#g" \
            -e "s#placeholder_kernel_desc#$sed_kernel_desc#g" \
            -e "s#placeholder_run_as_user#$sed_run_as_user#g" \
            "$service_target" || return 1
    }
    local sed_installed_init
    sed_installed_init=$(_preflight_escape_sed_repl "CLASH_INSTALLED_INIT_TYPE=\${CLASH_INSTALLED_INIT_TYPE:-${INIT_TYPE}}")
    sed -i \
        -e "s#^CLASH_INSTALLED_INIT_TYPE=.*#${sed_installed_init}#g" \
        "$CLASH_CMD_DIR/clashctl.sh" "$CLASH_CMD_DIR/common.sh"

    "${service_enable[@]}" >&/dev/null && _okcat '🚀' '已设置开机自启'
    if ((${#service_reload[@]})); then
        "${service_reload[@]}" || return 1
    fi
    return 0
}

_uninstall_service() {
    local force_current_attempt=false
    [ "${1:-}" = --force-current-attempt ] && force_current_attempt=true

    _detect_init
    if [ -n "${service_target:-}" ] && [ "$force_current_attempt" != true ] &&
        ! _service_target_belongs_to_current_install; then
        return 0
    fi

    "${service_disable[@]}" >&/dev/null
    if declare -p service_del >/dev/null 2>&1 && ((${#service_del[@]})); then
        "${service_del[@]}"
    fi
    [ -n "${service_target:-}" ] && rm -f "$service_target"
    if declare -p service_reload >/dev/null 2>&1 && ((${#service_reload[@]})); then
        "${service_reload[@]}"
    fi
}
