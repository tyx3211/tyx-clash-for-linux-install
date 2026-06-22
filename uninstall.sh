#!/usr/bin/env bash
THIS_UNINSTALL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
CLASHCTL_ERROR_EXIT=1

_uninstall_die() {
    printf '📢 %s\n' "$1" >&2
    exit 1
}

. "$THIS_UNINSTALL_DIR/scripts/lib/install-state.sh" ||
    _uninstall_die "缺少安装状态解析脚本：$THIS_UNINSTALL_DIR/scripts/lib/install-state.sh"

_uninstall_expand_env_path() {
    local path=$1

    case "$path" in
    "~")
        printf '%s\n' "$HOME"
        ;;
    "~/"*)
        printf '%s/%s\n' "$HOME" "${path#\~/}"
        ;;
    '$HOME')
        printf '%s\n' "$HOME"
        ;;
    '$HOME/'*)
        printf '%s/%s\n' "$HOME" "${path#\$HOME/}"
        ;;
    '${HOME}')
        printf '%s\n' "$HOME"
        ;;
    '${HOME}/'*)
        printf '%s/%s\n' "$HOME" "${path#\$\{HOME\}/}"
        ;;
    *)
        printf '%s\n' "$path"
        ;;
    esac
}

_uninstall_read_env() {
    local env_file=$1 line key value
    [ -r "$env_file" ] || _uninstall_die "缺少安装环境文件：$env_file"

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
        "" | "#"*)
            continue
            ;;
        export[[:space:]]*)
            line=${line#export}
            line=${line#"${line%%[![:space:]]*}"}
            ;;
        esac

        case "$line" in
        *=*)
            key=${line%%=*}
            value=${line#*=}
            ;;
        *)
            continue
            ;;
        esac

        [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        case "$key" in
        KERNEL_NAME | CLASH_BASE_DIR | INIT_TYPE | CLASH_INSTALLED_INIT_TYPE)
            ;;
        *)
            continue
            ;;
        esac
        case "$value" in
        \"*\")
            value=${value#\"}
            value=${value%\"}
            ;;
        \'*\')
            value=${value#\'}
            value=${value%\'}
            ;;
        esac

        [ "$key" = CLASH_BASE_DIR ] && value=$(_uninstall_expand_env_path "$value")
        printf -v "$key" '%s' "$value"
    done <"$env_file"
}

_uninstall_read_metadata() {
    local env_file="$THIS_UNINSTALL_DIR/.env"
    local state_file="$THIS_UNINSTALL_DIR/resources/install-state.yaml"
    local has_env=false has_state=false

    if [ -r "$env_file" ]; then
        has_env=true
        _uninstall_read_env "$env_file"
    fi

    if [ -r "$state_file" ]; then
        has_state=true
        _install_state_read_into_vars "$state_file" ||
            _uninstall_die "安装状态文件解析失败：$state_file"
    fi

    [ "$has_env" = true ] || [ "$has_state" = true ] ||
        _uninstall_die "缺少安装状态文件：$state_file 或 $env_file"
    [ -n "${CLASH_BASE_DIR:-}" ] ||
        _uninstall_die "安装状态缺少安装目录：$state_file"
    [ -n "${KERNEL_NAME:-}" ] || KERNEL_NAME=mihomo
    [ -n "${INIT_TYPE:-}" ] || INIT_TYPE=tmux
    _install_state_validate_kernel_name "$KERNEL_NAME" ||
        _uninstall_die "内核名称不安全，仅支持 mihomo、clash：$KERNEL_NAME"
}

_uninstall_read_metadata

current_dir=$(pwd -P 2>/dev/null || pwd 2>/dev/null || true)
case "$current_dir" in
"$CLASH_BASE_DIR" | "$CLASH_BASE_DIR"/*)
    cd "$HOME" 2>/dev/null || cd /
    ;;
esac

case "$CLASH_BASE_DIR" in
"" | "/" | "$HOME" | "$HOME/" | . | .. | ./* | ../*)
    _uninstall_die "拒绝删除异常安装路径：${CLASH_BASE_DIR:-<empty>}"
    ;;
/*)
    ;;
*)
    _uninstall_die "安装路径必须是绝对路径：$CLASH_BASE_DIR"
    ;;
esac

CLASH_BASE_REAL=$(cd "$CLASH_BASE_DIR" 2>/dev/null && pwd -P) || _uninstall_die "安装路径不存在：$CLASH_BASE_DIR"
HOME_REAL=$(cd "$HOME" 2>/dev/null && pwd -P)
THIS_UNINSTALL_REAL=$THIS_UNINSTALL_DIR
[ "$THIS_UNINSTALL_REAL" = "$CLASH_BASE_REAL" ] ||
    _uninstall_die "卸载脚本所在目录与安装状态目录不一致：$THIS_UNINSTALL_REAL != $CLASH_BASE_REAL"
case "$CLASH_BASE_REAL" in
"" | "/" | "$HOME_REAL" | "$HOME_REAL/")
    _uninstall_die "拒绝删除异常安装路径：${CLASH_BASE_REAL:-<empty>}"
    ;;
esac

INSTALL_MARKER="${CLASH_BASE_REAL}/.clashctl-install-root"
[ ! -L "$INSTALL_MARKER" ] || _uninstall_die "拒绝使用符号链接安装标记：$INSTALL_MARKER"
[ -f "$INSTALL_MARKER" ] || _uninstall_die "拒绝删除未带安装标记的目录：$CLASH_BASE_REAL"
grep -qx 'tyx-clash-for-linux-install' "$INSTALL_MARKER" || _uninstall_die "安装标记不匹配：$INSTALL_MARKER"
[ -f "$CLASH_BASE_REAL/scripts/cmd/clashctl.sh" ] || _uninstall_die "安装目录缺少 clashctl 脚本：$CLASH_BASE_REAL"

. "$THIS_UNINSTALL_DIR/scripts/preflight.sh"
. "$CLASH_BASE_REAL/scripts/cmd/clashctl.sh" 2>/dev/null
_refresh_install_paths
INIT_TYPE=$(_get_installed_init_type)

[ "$INIT_TYPE" = systemd ] && ! _is_root && _error_quit "systemd 模式需要使用 sudo 执行卸载"
clashoff 2>/dev/null
_uninstall_service
_revoke_rc

CLASHCTL_CRON_TAG=${CLASHCTL_CRON_TAG:-"# clashctl-auto-update"}
command -v crontab >&/dev/null && {
    current_cron=$(crontab -l 2>/dev/null || true)
    [ -n "$current_cron" ] && printf '%s\n' "$current_cron" | grep -Fv "$CLASHCTL_CRON_TAG" | crontab -
}

[ ! -d "$CLASH_BASE_REAL/.git" ] ||
    printf '📢 检测到安装根目录 Git 仓库，将随卸载删除：%s/.git\n' "$CLASH_BASE_REAL" >&2
[ ! -d "$CLASH_BASE_REAL/config/.git" ] ||
    printf '📢 检测到配置目录 Git 仓库，将随卸载删除：%s/config/.git\n' "$CLASH_BASE_REAL" >&2

/usr/bin/rm -rf "$CLASH_BASE_REAL"

echo '✨' '已卸载，相关配置已清除'
_quit
