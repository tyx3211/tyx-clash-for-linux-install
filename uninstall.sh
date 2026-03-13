#!/usr/bin/env bash
THIS_UNINSTALL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$THIS_UNINSTALL_DIR/.env"
. "$CLASH_BASE_DIR/scripts/cmd/clashctl.sh" 2>/dev/null
. "$THIS_UNINSTALL_DIR/scripts/preflight.sh"

pgrep -f "$BIN_KERNEL" -u 0 >/dev/null && ! _is_root && _error_quit "请先关闭 Tun 模式"
clashoff 2>/dev/null
_uninstall_service
_revoke_rc

command -v crontab >&/dev/null && crontab -l | grep -v "clashsub" | crontab -

current_dir=$(pwd -P 2>/dev/null || pwd 2>/dev/null || true)
case "$current_dir" in
"$CLASH_BASE_DIR" | "$CLASH_BASE_DIR"/*)
    cd "$HOME" 2>/dev/null || cd /
    ;;
esac

/usr/bin/rm -rf "$CLASH_BASE_DIR"

echo '✨' '已卸载，相关配置已清除'
_quit
