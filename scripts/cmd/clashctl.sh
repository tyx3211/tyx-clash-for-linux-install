#!/usr/bin/env bash

THIS_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE:-${(%):-%N}}")")

_clashctl_source_lib() {
    local lib_file=$1
    [ -r "$lib_file" ] || {
        printf 'clashctl: missing required library: %s\n' "$lib_file" >&2
        return 1
    }
    . "$lib_file" || {
        printf 'clashctl: failed to source library: %s\n' "$lib_file" >&2
        return 1
    }
}

_clashctl_source_lib "$THIS_SCRIPT_DIR/common.sh" || { return 1 2>/dev/null || exit 1; }

DEFAULT_HTTP_PORT=7890
DEFAULT_SOCKS_PORT=7891
CLASH_INSTALLED_INIT_TYPE=${CLASH_INSTALLED_INIT_TYPE:-__CLASH_INIT_TYPE_UNSET__}

_clashctl_source_lib "$THIS_SCRIPT_DIR/../lib/proxy.sh" || { return 1 2>/dev/null || exit 1; }
_clashctl_source_lib "$THIS_SCRIPT_DIR/../lib/service-runtime.sh" || { return 1 2>/dev/null || exit 1; }
_clashctl_source_lib "$THIS_SCRIPT_DIR/../lib/config.sh" || { return 1 2>/dev/null || exit 1; }
_clashctl_source_lib "$THIS_SCRIPT_DIR/../lib/tun.sh" || { return 1 2>/dev/null || exit 1; }
_clashctl_source_lib "$THIS_SCRIPT_DIR/../lib/subscription.sh" || { return 1 2>/dev/null || exit 1; }
unset -f _clashctl_source_lib

function clashctl() {
    case "$1" in
    on)
        shift
        clashon "$@"
        ;;
    off)
        shift
        clashoff "$@"
        ;;
    restart)
        shift
        clashrestart "$@"
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
    update-self)
        shift
        bash "$CLASH_BASE_DIR/update.sh" --target "$CLASH_BASE_DIR" "$@"
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
  restart               重启或切换托管模式
  proxy                 系统代理
  status                内核状态
  ui                    面板地址
  sub                   订阅管理
  log                   内核日志
  tun                   管理 Tun 模式
  mixin                 Mixin 配置
  secret                Web 密钥
  update-self           无损更新项目脚本
  upgrade               升级内核

Global Options:
  -h, --help            显示帮助信息

For more help on how to use clashctl, head to https://github.com/tyx3211/tyx-clash-for-linux-install/tree/main
EOF
}
