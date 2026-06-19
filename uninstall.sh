#!/usr/bin/env bash
THIS_UNINSTALL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$THIS_UNINSTALL_DIR/.env"

_uninstall_die() {
    printf '📢 %s\n' "$1" >&2
    exit 1
}

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
esac

CLASH_BASE_REAL=$(cd "$CLASH_BASE_DIR" 2>/dev/null && pwd -P) || _uninstall_die "安装路径不存在：$CLASH_BASE_DIR"
HOME_REAL=$(cd "$HOME" 2>/dev/null && pwd -P)
case "$CLASH_BASE_REAL" in
"" | "/" | "$HOME_REAL" | "$HOME_REAL/")
    _uninstall_die "拒绝删除异常安装路径：${CLASH_BASE_REAL:-<empty>}"
    ;;
esac

INSTALL_MARKER="${CLASH_BASE_REAL}/.clashctl-install-root"
[ -f "$INSTALL_MARKER" ] || _uninstall_die "拒绝删除未带安装标记的目录：$CLASH_BASE_REAL"
grep -qx 'tyx-clash-for-linux-install' "$INSTALL_MARKER" || _uninstall_die "安装标记不匹配：$INSTALL_MARKER"
[ -f "$CLASH_BASE_REAL/scripts/cmd/clashctl.sh" ] || _uninstall_die "安装目录缺少 clashctl 脚本：$CLASH_BASE_REAL"

. "$THIS_UNINSTALL_DIR/scripts/preflight.sh"
. "$CLASH_BASE_REAL/scripts/cmd/clashctl.sh" 2>/dev/null

pgrep -f "$BIN_KERNEL" -u 0 >/dev/null && ! _is_root && _error_quit "请先关闭 Tun 模式"
clashoff 2>/dev/null
_uninstall_service
_revoke_rc

CLASHCTL_CRON_TAG=${CLASHCTL_CRON_TAG:-"# clashctl-auto-update"}
command -v crontab >&/dev/null && {
    current_cron=$(crontab -l 2>/dev/null || true)
    [ -n "$current_cron" ] && printf '%s\n' "$current_cron" | grep -Fv "$CLASHCTL_CRON_TAG" | crontab -
}

/usr/bin/rm -rf "$CLASH_BASE_REAL"

echo '✨' '已卸载，相关配置已清除'
_quit
