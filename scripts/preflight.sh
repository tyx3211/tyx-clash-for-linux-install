#!/usr/bin/env bash

RESOURCES_BASE_DIR=".${CLASH_RESOURCES_DIR#"$CLASH_BASE_DIR"}"

ZIP_BASE_DIR=".${CLASH_RESOURCES_DIR#"$CLASH_BASE_DIR"}/zip"

SCRIPT_BASE_DIR='scripts'
SCRIPT_INIT_DIR="${SCRIPT_BASE_DIR}/init"
SCRIPT_CMD_DIR="${SCRIPT_BASE_DIR}/cmd"
SCRIPT_CMD_FISH="${SCRIPT_CMD_DIR}/clashctl.fish"

CLASH_CMD_DIR="${CLASH_BASE_DIR}/$SCRIPT_CMD_DIR"

FILE_LOG="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.log"
FILE_PID="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.pid"
INSTALL_MARKER="${CLASH_BASE_DIR}/.clashctl-install-root"
CLASH_INSTALL_CREATED_DIR=
CLASH_INSTALL_COMPLETE=false

_refresh_install_paths() {
    CLASH_RESOURCES_DIR="${CLASH_BASE_DIR}/resources"
    CLASH_CONFIG_BASE="${CLASH_RESOURCES_DIR}/config.yaml"
    CLASH_CONFIG_MIXIN="${CLASH_RESOURCES_DIR}/mixin.yaml"
    CLASH_CONFIG_SIDECAR="${CLASH_RESOURCES_DIR}/clashctl.yaml"
    CLASH_CONFIG_RUNTIME="${CLASH_RESOURCES_DIR}/runtime.yaml"
    CLASH_CONFIG_TEMP="${CLASH_RESOURCES_DIR}/temp.yaml"
    CLASH_SERVICE_STATE="${CLASH_RESOURCES_DIR}/service-state.yaml"

    BIN_BASE_DIR="${CLASH_BASE_DIR}/bin"
    BIN_KERNEL="${BIN_BASE_DIR}/$KERNEL_NAME"
    BIN_YQ="${BIN_BASE_DIR}/yq"
    BIN_SUBCONVERTER_DIR="${BIN_BASE_DIR}/subconverter"
    BIN_SUBCONVERTER="${BIN_SUBCONVERTER_DIR}/subconverter"
    BIN_SUBCONVERTER_START="$BIN_SUBCONVERTER"
    BIN_SUBCONVERTER_CONFIG="$BIN_SUBCONVERTER_DIR/pref.yml"
    BIN_SUBCONVERTER_LOG="${BIN_SUBCONVERTER_DIR}/latest.log"
    BIN_SUBCONVERTER_PID="${BIN_SUBCONVERTER_DIR}/subconverter.pid"

    CLASH_PROFILES_DIR="${CLASH_RESOURCES_DIR}/profiles"
    CLASH_PROFILES_META="${CLASH_RESOURCES_DIR}/profiles.yaml"
    CLASH_PROFILES_LOG="${CLASH_RESOURCES_DIR}/profiles.log"

    RESOURCES_BASE_DIR=".${CLASH_RESOURCES_DIR#"$CLASH_BASE_DIR"}"
    ZIP_BASE_DIR=".${CLASH_RESOURCES_DIR#"$CLASH_BASE_DIR"}/zip"
    CLASH_CMD_DIR="${CLASH_BASE_DIR}/$SCRIPT_CMD_DIR"
    FILE_LOG="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.log"
    FILE_PID="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.pid"
    INSTALL_MARKER="${CLASH_BASE_DIR}/.clashctl-install-root"
}

_normalize_sudo_install_path() {
    _is_regular_sudo || return 0

    case "$CLASH_BASE_DIR" in
    /root | /root/*)
        local sudo_home
        sudo_home=$(awk -F: -v user="$SUDO_USER" '$1==user{print $6}' /etc/passwd)
        [ -n "$sudo_home" ] || _error_quit "无法识别 sudo 调用用户的 HOME：$SUDO_USER"
        CLASH_BASE_DIR="${sudo_home}${CLASH_BASE_DIR#/root}"
        ;;
    esac
}

_validate_init_mode() {
    [ -z "$INIT_TYPE" ] && INIT_TYPE='tmux'

    case "$INIT_TYPE" in
    tmux | nohup)
        return 0
        ;;
    systemd)
        command -v systemctl >&/dev/null || _error_quit "未检测到 systemctl，请改用 INIT_TYPE=tmux 或 INIT_TYPE=nohup"
        _is_root || _is_regular_sudo || _error_quit "INIT_TYPE=systemd 需要 root 或 sudo 执行"
        return 0
        ;;
    *)
        _error_quit "仅支持 INIT_TYPE=tmux、nohup、systemd"
        ;;
    esac
}

_validate_install_path() {
    case "$CLASH_BASE_DIR" in
    "" | "/" | "$HOME" | "$HOME/" | . | .. | ./* | ../*)
        _error_quit "安装路径不安全，请在 .env 中更换 CLASH_BASE_DIR：${CLASH_BASE_DIR:-<empty>}"
        ;;
    /*)
        ;;
    *)
        _error_quit "安装路径必须是绝对路径：$CLASH_BASE_DIR"
        ;;
    esac

    case "$CLASH_BASE_DIR" in
    *[!A-Za-z0-9_./-]*)
        _error_quit "安装路径包含 shell 模板不支持的字符，请仅使用字母、数字、_、-、.、/：$CLASH_BASE_DIR"
        ;;
    esac
}

_register_install_cleanup() {
    [ -e "$CLASH_BASE_DIR" ] || CLASH_INSTALL_CREATED_DIR=$CLASH_BASE_DIR
    trap _cleanup_incomplete_install EXIT
}

_mark_install_complete() {
    CLASH_INSTALL_COMPLETE=true
    trap - EXIT
}

_cleanup_incomplete_install() {
    local status=$?

    [ "$CLASH_INSTALL_COMPLETE" = true ] && return "$status"
    [ -n "$CLASH_INSTALL_CREATED_DIR" ] || return "$status"

    case "$CLASH_INSTALL_CREATED_DIR" in
    "" | "/" | "$HOME" | "$HOME/" | . | .. | ./* | ../*)
        return "$status"
        ;;
    esac

    /usr/bin/rm -rf "$CLASH_INSTALL_CREATED_DIR" 2>/dev/null || true
    return "$status"
}

_valid_required() {
    local required_cmds=("xz" "pgrep" "pkill" "curl" "tar" 'unzip' "shuf")
    local missing=()

    case "${INIT_TYPE:-tmux}" in
    tmux)
        required_cmds+=("tmux")
        ;;
    systemd)
        required_cmds+=("systemctl" "ip")
        ;;
    esac

    for cmd in "${required_cmds[@]}"; do
        command -v "$cmd" >&/dev/null || missing+=("$cmd")
    done
    [ "${#missing[@]}" -gt 0 ] && _error_quit "请先安装以下命令：${missing[*]}"
}

_valid() {
    _validate_install_path
    _valid_required

    [ -d "$CLASH_BASE_DIR" ] && _error_quit "请先执行卸载脚本,以清除安装路径：$CLASH_BASE_DIR"

    local msg="${CLASH_BASE_DIR}：当前路径不可用，请在 .env 中更换安装路径。"
    mkdir -p "$CLASH_BASE_DIR" || _error_quit "$msg"
    _is_regular_sudo && [[ $CLASH_BASE_DIR == /root* ]] && _error_quit "$msg"

    [ -z "$ZSH_VERSION" ] && [ -z "$BASH_VERSION" ] && _error_quit "仅支持：bash、zsh 执行"
}

_parse_args() {
    while [ "$#" -gt 0 ]; do
        local arg=$1
        case $arg in
        mihomo)
            KERNEL_NAME=mihomo
            ;;
        clash)
            KERNEL_NAME=clash
            ;;
        http*)
            CLASH_CONFIG_URL=$arg
            ;;
        --init=*)
            INIT_TYPE=${arg#--init=}
            ;;
        --init)
            shift
            [ "$#" -gt 0 ] || _error_quit "--init 需要指定模式：tmux、nohup、systemd"
            INIT_TYPE=$1
            ;;
        esac
        shift
    done
    _refresh_install_paths
}

_prepare_zip() {
    _load_zip >&/dev/null
    local required_zips=()
    case "${KERNEL_NAME}" in
    clash)
        [ ! -f "$ZIP_CLASH" ] && required_zips+=("clash")
        ;;
    mihomo | *)
        [ ! -f "$ZIP_MIHOMO" ] && required_zips+=("mihomo")
        ;;
    esac
    [ ! -f "$ZIP_YQ" ] && required_zips+=("yq")
    [ ! -f "$ZIP_SUBCONVERTER" ] && required_zips+=("subconverter")

    _download_zip "${required_zips[@]}"

    case "${KERNEL_NAME}" in
    clash)
        ZIP_KERNEL="$ZIP_CLASH"
        ;;
    mihomo | *)
        ZIP_KERNEL="$ZIP_MIHOMO"
        ;;
    esac
    BIN_KERNEL="${BIN_BASE_DIR}/$KERNEL_NAME"
    _unzip_zip
}
_load_zip() {
    ZIP_CLASH=$(echo "${ZIP_BASE_DIR}"/clash*)
    ZIP_MIHOMO=$(echo "${ZIP_BASE_DIR}"/mihomo*)
    ZIP_YQ=$(echo "${ZIP_BASE_DIR}"/yq*)
    ZIP_SUBCONVERTER=$(echo "${ZIP_BASE_DIR}"/subconverter*)
}
_fetch_latest_tag() {
    local repo=$1 body tag
    body=$(
        curl \
            --silent \
            --location \
            --max-time 10 \
            --retry 1 \
            -H 'Accept: application/vnd.github+json' \
            "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null
    ) || return 1
    tag=$(
        printf '%s' "$body" |
            grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' |
            head -1 |
            sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/'
    )
    [ -n "$tag" ] && printf '%s\n' "$tag"
}
_resolve_version() {
    local varname=$1 repo=$2 tag
    [ -n "${!varname:-}" ] && return 0

    tag=$(_fetch_latest_tag "$repo") || {
        _error_quit "${repo} 版本获取失败，请在 .env 中手动指定 $varname"
        return 1
    }
    printf -v "$varname" '%s' "$tag"
    _okcat '🏷️ ' "${repo} -> $tag"
}
_download_zip() {
    (($#)) || return 0
    local url_clash url_mihomo url_yq url_subconverter
    local subconverter_repo=${SUBCONVERTER_REPO:-tindy2013/subconverter}
    local download_timeout=${CLASHCTL_DOWNLOAD_TIMEOUT:-60}
    local arch=$(uname -m)
    local item
    for item in "$@"; do
        case $item in
        mihomo)
            _resolve_version VERSION_MIHOMO MetaCubeX/mihomo || return 1
            ;;
        yq)
            _resolve_version VERSION_YQ mikefarah/yq || return 1
            ;;
        subconverter)
            _resolve_version VERSION_SUBCONVERTER "$subconverter_repo" || return 1
            ;;
        esac
    done

    case "$arch" in
    x86_64)
        local flags=$(grep -m1 '^flags' /proc/cpuinfo)
        local level=v1
        grep -qw sse4_2 <<<"$flags" && grep -qw popcnt <<<"$flags" && level=v2
        grep -qw avx2 <<<"$flags" && grep -qw fma <<<"$flags" && level=v3
        VERSION_MIHOMO=${level}-$VERSION_MIHOMO

        url_clash=https://downloads.clash.wiki/ClashPremium/clash-linux-amd64-2023.08.17.gz
        url_mihomo=https://github.com/MetaCubeX/mihomo/releases/download/${VERSION_MIHOMO##*-}/mihomo-linux-amd64-${VERSION_MIHOMO}.gz
        url_yq=https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_amd64.tar.gz
        url_subconverter=https://github.com/${subconverter_repo}/releases/download/${VERSION_SUBCONVERTER}/subconverter_linux64.tar.gz
        ;;
    *86*)
        url_clash=https://downloads.clash.wiki/ClashPremium/clash-linux-386-2023.08.17.gz
        url_mihomo=https://github.com/MetaCubeX/mihomo/releases/download/${VERSION_MIHOMO##*-}/mihomo-linux-386-${VERSION_MIHOMO}.gz
        url_yq=https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_386.tar.gz
        url_subconverter=https://github.com/${subconverter_repo}/releases/download/${VERSION_SUBCONVERTER}/subconverter_linux32.tar.gz
        ;;
    armv*)
        url_clash=https://downloads.clash.wiki/ClashPremium/clash-linux-armv5-2023.08.17.gz
        url_mihomo=https://github.com/MetaCubeX/mihomo/releases/download/${VERSION_MIHOMO##*-}/mihomo-linux-armv7-${VERSION_MIHOMO}.gz
        url_yq=https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_arm.tar.gz
        url_subconverter=https://github.com/${subconverter_repo}/releases/download/${VERSION_SUBCONVERTER}/subconverter_armv7.tar.gz
        ;;
    aarch64)
        url_clash=https://downloads.clash.wiki/ClashPremium/clash-linux-arm64-2023.08.17.gz
        url_mihomo=https://github.com/MetaCubeX/mihomo/releases/download/${VERSION_MIHOMO##*-}/mihomo-linux-arm64-${VERSION_MIHOMO}.gz
        url_yq=https://github.com/mikefarah/yq/releases/download/${VERSION_YQ}/yq_linux_arm64.tar.gz
        url_subconverter=https://github.com/${subconverter_repo}/releases/download/${VERSION_SUBCONVERTER}/subconverter_aarch64.tar.gz
        ;;
    *)
        _error_quit "未知的架构版本：$arch，请自行下载对应版本至 ${ZIP_BASE_DIR} 目录"
        ;;
    esac

    local -A urls=(
        [clash]="$url_clash"
        [mihomo]="$url_mihomo"
        [yq]="$url_yq"
        [subconverter]="$url_subconverter"
    )

    local target_zips=()
    _okcat '🖥️ ' "系统架构：$arch $level"
    for item in "$@"; do
        local url="${urls[$item]}"
        local proxy_url="${URL_GH_PROXY:+${URL_GH_PROXY%/}/}${url}"
        [ "$item" != 'clash' ] && url="$proxy_url"
        _okcat '⏳' "正在下载：${item}：$url"
        local target="${ZIP_BASE_DIR}/$(basename "$url")"
        curl \
            --progress-bar \
            --show-error \
            --fail \
            --insecure \
            --location \
            --max-time "$download_timeout" \
            --retry 1 \
            --output "$target" \
            "$url"
        target_zips+=("$target")
    done
    _valid_zip "${target_zips[@]}"
    _load_zip >&/dev/null
}
_valid_zip() {
    (($#)) || return 1
    local zip fail_zips=()
    for zip in "$@"; do
        gzip -tq "$zip" || unzip -tqq "$zip" || fail_zips+=("$zip")
    done

    ((${#fail_zips[@]})) && _error_quit "文件验证失败：${fail_zips[*]} 请删除后重试，或自行下载对应版本至 ${ZIP_BASE_DIR} 目录"
}
_unzip_zip() {
    _valid_zip "$ZIP_KERNEL" "$ZIP_YQ" "$ZIP_SUBCONVERTER" "$ZIP_UI"
    /usr/bin/install -D <(gzip -dc "$ZIP_KERNEL") "$BIN_KERNEL"
    tar -xf "$ZIP_YQ" -C "${BIN_BASE_DIR}"
    /bin/mv -f "${BIN_BASE_DIR}"/yq_* "${BIN_BASE_DIR}/yq"
    tar -xf "$ZIP_SUBCONVERTER" -C "$BIN_BASE_DIR"
    /bin/cp "$BIN_SUBCONVERTER_DIR/pref.example.yml" "$BIN_SUBCONVERTER_CONFIG"
    unzip -oqq "$ZIP_UI" -d "$RESOURCES_BASE_DIR" 2>/dev/null || tar -xf "$ZIP_UI" -C "$RESOURCES_BASE_DIR"
}

# shellcheck disable=SC2206
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

_shell_quote() {
    printf '%q' "$1"
}

_quote_command() {
    local out= item quoted

    for item in "$@"; do
        quoted=$(_shell_quote "$item")
        out="${out:+$out }$quoted"
    done
    printf '%s' "$out"
}

_append_service_functions() {
    return 0
}

_install_service() {
    local kernel_desc="$KERNEL_NAME Daemon, A[nother] Clash Kernel."

    local cmd_path="${BIN_KERNEL}"
    local cmd_arg="-d ${CLASH_RESOURCES_DIR} -f ${CLASH_CONFIG_RUNTIME}"
    local cmd_full="${BIN_KERNEL} -d ${CLASH_RESOURCES_DIR} -f ${CLASH_CONFIG_RUNTIME}"

    _escape_sed_repl() {
        printf '%s' "$1" | sed -e 's/[#&\\]/\\&/g'
    }

    [ -n "$service_src" ] && {
        local sed_cmd_path sed_cmd_arg sed_cmd_full sed_log_file sed_pid_file
        local sed_kernel_name sed_kernel_desc sed_run_as_user
        sed_cmd_path=$(_escape_sed_repl "$cmd_path")
        sed_cmd_arg=$(_escape_sed_repl "$cmd_arg")
        sed_cmd_full=$(_escape_sed_repl "$cmd_full")
        sed_log_file=$(_escape_sed_repl "$FILE_LOG")
        sed_pid_file=$(_escape_sed_repl "$FILE_PID")
        sed_kernel_name=$(_escape_sed_repl "$KERNEL_NAME")
        sed_kernel_desc=$(_escape_sed_repl "$kernel_desc")
        sed_run_as_user=$(_escape_sed_repl "${service_run_as_user:-}")
        /usr/bin/install -D -m 755 "$service_src" "$service_target" || return 1
        if ((${#service_add[@]})); then
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
    sed_installed_init=$(_escape_sed_repl "CLASH_INSTALLED_INIT_TYPE=\${CLASH_INSTALLED_INIT_TYPE:-${INIT_TYPE}}")
    sed -i \
        -e "s#^CLASH_INSTALLED_INIT_TYPE=.*#${sed_installed_init}#g" \
        "$CLASH_CMD_DIR/clashctl.sh" "$CLASH_CMD_DIR/common.sh"
    _append_service_functions

    "${service_enable[@]}" >&/dev/null && _okcat '🚀' '已设置开机自启'
    if ((${#service_reload[@]})); then
        "${service_reload[@]}" || return 1
    fi
    return 0
}
_uninstall_service() {
    _detect_init
    "${service_disable[@]}" >&/dev/null
    ((${#service_del[@]})) && "${service_del[@]}"
    rm -f "$service_target"
    ((${#service_reload[@]})) && "${service_reload[@]}"
}

_detect_rc() {
    local home=$HOME
    _is_regular_sudo && home=$(awk -F: -v user="$SUDO_USER" '$1==user{print $6}' /etc/passwd)

    command -v bash >&/dev/null && {
        SHELL_RC_BASH="${home}/.bashrc"
    }
    command -v zsh >&/dev/null && {
        SHELL_RC_ZSH="${home}/.zshrc"
    }
    command -v fish >&/dev/null && {
        SHELL_RC_FISH="${home}/.config/fish/conf.d/clashctl.fish"
    }
    start_flag="# clashctl START"
    end_flag="# clashctl END"
}
_apply_rc() {
    _detect_rc
    local source_clashctl=". $CLASH_CMD_DIR/clashctl.sh"
    _revoke_rc
    # shellcheck disable=SC2086
    tee -a "$SHELL_RC_BASH" $SHELL_RC_ZSH >/dev/null <<EOF

$start_flag $CLASH_CMD_DIR
# 加载 clashctl 命令
$source_clashctl
# 自动开启代理环境
watch_proxy
$end_flag $CLASH_CMD_DIR
EOF
    [ -n "$SHELL_RC_FISH" ] && /usr/bin/install "$SCRIPT_CMD_FISH" "$SHELL_RC_FISH"
    $source_clashctl
}
_revoke_rc_file() {
    local rc_file=$1 source_clashctl=". $CLASH_CMD_DIR/clashctl.sh"
    [ -f "$rc_file" ] || return 0

    local rc_target=$rc_file
    if [ -L "$rc_file" ]; then
        rc_target=$(readlink -f "$rc_file") || return 1
    fi
    [ -f "$rc_target" ] || return 0

    local rc_dir tmp_file
    rc_dir=$(dirname "$rc_target")
    tmp_file=$(mktemp "${rc_dir}/.clashctl-rc.XXXXXX") || return 1
    chmod --reference="$rc_target" "$tmp_file" 2>/dev/null || true
    chown --reference="$rc_target" "$tmp_file" 2>/dev/null || true

    awk -v source="$source_clashctl" '
        /^# clashctl START/ {
            in_block = 1
            matched = 0
            block = $0 ORS
            next
        }
        in_block {
            block = block $0 ORS
            if ($0 == source) {
                matched = 1
            }
            if ($0 ~ /^# clashctl END/) {
                if (!matched) {
                    printf "%s", block
                }
                in_block = 0
                block = ""
            }
            next
        }
        { print }
        END {
            if (in_block) {
                printf "%s", block
            }
        }
    ' "$rc_target" >"$tmp_file" && /bin/mv -f "$tmp_file" "$rc_target"
}
_revoke_rc() {
    _detect_rc
    _revoke_rc_file "$SHELL_RC_BASH"
    _revoke_rc_file "$SHELL_RC_ZSH"
    [ -n "$SHELL_RC_FISH" ] && rm -f "$SHELL_RC_FISH" 2>/dev/null
}

_set_envs() {
    _set_env INIT_TYPE "$INIT_TYPE"
    _set_env CLASH_INSTALLED_INIT_TYPE "$INIT_TYPE"
    _set_env KERNEL_NAME "$KERNEL_NAME"
    _set_env CLASH_BASE_DIR "$CLASH_BASE_DIR"
    _set_env VERSION_MIHOMO "$VERSION_MIHOMO"
}

_get_random_val() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 6
}

_is_regular_sudo() {
    _is_root && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != 'root' ]
}
_is_root() {
    [ "$(id -u)" -eq 0 ]
}

_quit() {
    _is_regular_sudo && exec su "$SUDO_USER"
    exec "$SHELL" -i
}
