#!/usr/bin/env bash

CLASH_BASE_DIR=${CLASH_BASE_DIR:-}
CLASH_RESOURCES_DIR=${CLASH_RESOURCES_DIR:-"${CLASH_BASE_DIR}/resources"}
KERNEL_NAME=${KERNEL_NAME:-mihomo}

_PREFLIGHT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$_PREFLIGHT_SCRIPT_DIR/lib/install-state.sh"
. "$_PREFLIGHT_SCRIPT_DIR/install/archive-safe.sh"
. "$_PREFLIGHT_SCRIPT_DIR/install/service-render.sh"
. "$_PREFLIGHT_SCRIPT_DIR/install/rc.sh"
unset _PREFLIGHT_SCRIPT_DIR

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
CLASH_INSTALL_SERVICE_TOUCHED=false
CLASH_INSTALL_SERVICE_WRITTEN=false
CLASH_INSTALL_RC_TOUCHED=false

_refresh_install_paths() {
    CLASH_RESOURCES_DIR="${CLASH_BASE_DIR}/resources"
    CLASH_CONFIG_DIR="${CLASH_BASE_DIR}/config"
    CLASH_INSTALL_STATE="${CLASH_RESOURCES_DIR}/install-state.yaml"
    CLASH_CONFIG_BASE="${CLASH_RESOURCES_DIR}/config.yaml"
    CLASH_CONFIG_MIXIN="${CLASH_CONFIG_DIR}/mixin.yaml"
    CLASH_CONFIG_SIDECAR="${CLASH_CONFIG_DIR}/clashctl.yaml"
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
    CLASH_PROFILES_META="${CLASH_CONFIG_DIR}/subscriptions.yaml"
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
    /root/)
        return 0
        ;;
    /root/*)
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

_validate_kernel_name() {
    _install_state_validate_kernel_name "$KERNEL_NAME" ||
        _error_quit "内核名称不安全，仅支持 mihomo、clash：$KERNEL_NAME"
}

_validate_install_path() {
    case "$CLASH_BASE_DIR" in
    "" | "/" | /root | /root/ | "$HOME" | "$HOME/" | . | .. | ./* | ../*)
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

    case "$CLASH_BASE_DIR" in
    */../* | */.. | */./* | */.)
        _error_quit "安装路径不能包含 . 或 .. 路径组件：$CLASH_BASE_DIR"
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
    case "$CLASH_INSTALL_CREATED_DIR" in
    /*)
        ;;
    *)
        return "$status"
        ;;
    esac
    case "$CLASH_INSTALL_CREATED_DIR" in
    *[!A-Za-z0-9_./-]* | */../* | */.. | */./* | */.)
        return "$status"
        ;;
    esac

    if [ "${CLASH_INSTALL_SERVICE_WRITTEN:-false}" = true ]; then
        _uninstall_service --force-current-attempt >/dev/null 2>&1 || true
    elif [ "${CLASH_INSTALL_SERVICE_TOUCHED:-false}" = true ]; then
        _uninstall_service >/dev/null 2>&1 || true
    fi
    if [ "${CLASH_INSTALL_RC_TOUCHED:-false}" = true ]; then
        _revoke_rc >/dev/null 2>&1 || true
    fi
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
    if [ "${#missing[@]}" -gt 0 ]; then
        _error_quit "请先安装以下命令：${missing[*]}"
        return $?
    fi
    return 0
}

_valid() {
    _validate_install_path || return 1
    _valid_required || return 1

    if [ -d "$CLASH_BASE_DIR" ]; then
        _error_quit "请先执行卸载脚本,以清除安装路径：$CLASH_BASE_DIR"
        return $?
    fi

    local msg="${CLASH_BASE_DIR}：当前路径不可用，请在 .env 中更换安装路径。"
    mkdir -p "$CLASH_BASE_DIR" || _error_quit "$msg"
    if _is_regular_sudo && [[ $CLASH_BASE_DIR == /root* ]]; then
        _error_quit "$msg"
        return $?
    fi

    if [ -z "${ZSH_VERSION:-}" ] && [ -z "${BASH_VERSION:-}" ]; then
        _error_quit "仅支持：bash、zsh 执行"
        return $?
    fi
    return 0
}

_print_install_help() {
    cat <<EOF
Usage:
  bash install.sh [mihomo|clash] [subscription_url] [OPTIONS]

Options:
  --init <tmux|nohup|systemd>
                         设置默认运行托管模式；systemd 需要 root 或 sudo
  --init=<mode>          等价写法
  --config-git           安装时在 <安装目录>/config 下执行 git init
  --no-config-git        即使 CLASHCTL_CONFIG_GIT=1 也不初始化配置仓库
  --gh-proxy <url>       设置 GitHub 下载代理前缀，例如 https://gh-proxy.org
  --gh-proxy=<url>       等价写法
  --no-gh-proxy          不使用 GitHub 下载代理；这是默认行为
  -h, --help             显示帮助信息

Environment:
  CLASHCTL_CONFIG_GIT=1  等价于 --config-git
  URL_GH_PROXY=<url>     等价于 --gh-proxy <url>
  CLASHCTL_NO_RC=1       不写入 shell rc
  CLASHCTL_NO_QUIT=1     跳过安装末尾的订阅导入交互

Examples:
  bash install.sh
  bash install.sh --init nohup
  bash install.sh --gh-proxy https://gh-proxy.org
  CLASHCTL_CONFIG_GIT=1 bash install.sh
  sudo bash install.sh --init systemd
EOF
}

_validate_gh_proxy() {
    [ -z "${URL_GH_PROXY:-}" ] && return 0

    case "$URL_GH_PROXY" in
    http://* | https://*)
        ;;
    *)
        _error_quit "GitHub 下载代理前缀必须以 http:// 或 https:// 开头：$URL_GH_PROXY"
        ;;
    esac

    case "$URL_GH_PROXY" in
    *[[:space:]]* | *\'* | *\"* | *'`'* | *'$('* | *';'* | *'|'* | *'&'* | *'<'* | *'>'*)
        _error_quit "GitHub 下载代理前缀包含不支持的字符：$URL_GH_PROXY"
        ;;
    esac
}

_parse_args() {
    while [ "$#" -gt 0 ]; do
        local arg=$1
        case $arg in
        -h | --help)
            _print_install_help
            exit 0
            ;;
        mihomo)
            KERNEL_NAME=mihomo
            ;;
        clash)
            KERNEL_NAME=clash
            ;;
        http* | file://*)
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
        --config-git | --config-git=1 | --config-git=true | --config-git=yes | --config-git=on)
            CLASHCTL_CONFIG_GIT=1
            ;;
        --config-git=0 | --config-git=false | --config-git=no | --config-git=off | --no-config-git)
            CLASHCTL_CONFIG_GIT=0
            ;;
        --gh-proxy=*)
            URL_GH_PROXY=${arg#--gh-proxy=}
            ;;
        --gh-proxy)
            shift
            [ "$#" -gt 0 ] || _error_quit "--gh-proxy 需要指定 URL，例如：https://gh-proxy.org"
            URL_GH_PROXY=$1
            ;;
        --no-gh-proxy)
            URL_GH_PROXY=
            ;;
        esac
        shift
    done
    _validate_gh_proxy
    _refresh_install_paths
}

_config_git_enabled() {
    case "${CLASHCTL_CONFIG_GIT:-0}" in
    1 | true | yes | on)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

_init_config_git() {
    _config_git_enabled || return 0

    [ -d "$CLASH_CONFIG_DIR" ] || _error_quit "配置目录不存在，无法初始化 git：$CLASH_CONFIG_DIR"
    [ ! -L "$CLASH_CONFIG_DIR" ] || _error_quit "配置目录不能是符号链接：$CLASH_CONFIG_DIR"
    local base_real config_real expected_config_real
    base_real=$(cd "$CLASH_BASE_DIR" && pwd -P) || _error_quit "安装目录不存在：$CLASH_BASE_DIR"
    config_real=$(cd "$CLASH_CONFIG_DIR" && pwd -P) || _error_quit "配置目录不存在：$CLASH_CONFIG_DIR"
    expected_config_real="${base_real}/config"
    [ "$config_real" = "$expected_config_real" ] ||
        _error_quit "配置目录不属于当前安装目录：$CLASH_CONFIG_DIR"
    command -v git >/dev/null || _error_quit "未检测到 git，无法初始化配置仓库；可去掉 --config-git 后重试"

    if [ -d "$CLASH_CONFIG_DIR/.git" ]; then
        _okcat "配置目录已经是 git 仓库：$CLASH_CONFIG_DIR"
        return 0
    fi

    (cd "$CLASH_CONFIG_DIR" && git init >/dev/null) ||
        _error_quit "配置目录 git 初始化失败：$CLASH_CONFIG_DIR"
    _okcat "已在配置目录初始化 git 仓库：$CLASH_CONFIG_DIR"
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

    if ((${#fail_zips[@]})); then
        _error_quit "文件验证失败：${fail_zips[*]} 请删除后重试，或自行下载对应版本至 ${ZIP_BASE_DIR} 目录"
        return $?
    fi
    return 0
}
_unzip_zip() {
    _valid_zip "$ZIP_KERNEL" "$ZIP_YQ" "$ZIP_SUBCONVERTER" "$ZIP_UI"
    /usr/bin/install -D <(gzip -dc "$ZIP_KERNEL") "$BIN_KERNEL" || return 1
    _extract_tar_archive "$ZIP_YQ" "${BIN_BASE_DIR}" || return 1
    /bin/mv -f "${BIN_BASE_DIR}"/yq_* "${BIN_BASE_DIR}/yq" || return 1
    _extract_tar_archive "$ZIP_SUBCONVERTER" "$BIN_BASE_DIR" || return 1
    /bin/cp "$BIN_SUBCONVERTER_DIR/pref.example.yml" "$BIN_SUBCONVERTER_CONFIG" || return 1
    _extract_zip_archive "$ZIP_UI" "$RESOURCES_BASE_DIR" 2>/dev/null ||
        _extract_tar_archive "$ZIP_UI" "$RESOURCES_BASE_DIR" || return 1
    [ -x "$BIN_KERNEL" ] || return 1
    [ -x "$BIN_YQ" ] || return 1
    [ -x "$BIN_SUBCONVERTER" ] || return 1
}

_shell_quote() {
    printf '%q' "$1"
}

_set_envs() {
    local installed_systemd=false
    [ "$INIT_TYPE" = systemd ] && installed_systemd=true

    _install_state_write \
        "$CLASH_INSTALL_STATE" \
        "$CLASH_BASE_DIR" \
        "$KERNEL_NAME" \
        "$INIT_TYPE" \
        "$installed_systemd" \
        "${VERSION_MIHOMO:-}" \
        "${VERSION_YQ:-}" \
        "${VERSION_SUBCONVERTER:-}" ||
        _error_quit "安装状态写入失败：$CLASH_INSTALL_STATE"

    _set_env INIT_TYPE "$INIT_TYPE"
    _set_env CLASH_INSTALLED_INIT_TYPE "$INIT_TYPE"
    _set_env KERNEL_NAME "$KERNEL_NAME"
    _set_env CLASH_BASE_DIR "$CLASH_BASE_DIR"
    _set_env VERSION_MIHOMO "$VERSION_MIHOMO"
    _set_env URL_GH_PROXY "${URL_GH_PROXY:-}"
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
