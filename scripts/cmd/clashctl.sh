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
  on                    开启代理内核，可传 --mode tmux|nohup|systemd
  off                   关闭代理内核，可传 --mode 处理异常残留
  restart               重启或切换托管模式
  proxy                 管理当前终端代理变量
  status                内核状态
  ui                    面板地址
  sub                   订阅管理
  log                   内核日志
  tun                   管理 Tun 模式，仅 systemd
  mixin                 Mixin 配置
  secret                Web 密钥
  update-self           从 GitHub 或本地源码无损更新项目脚本
  upgrade               升级内核

Global Options:
  -h, --help            显示帮助信息

Quick Start:
  clashon                         启动内核，默认 tmux
  clashstatus                     查看当前运行状态
  clashproxy on                   当前终端开启代理变量
  clashui                         输出 Web 面板地址
  clashoff                        关闭当前活跃托管模式

Mode Switch:
  clashrestart --mode tmux        切到 tmux
  clashrestart --mode nohup       切到 nohup
  clashrestart --mode systemd     切到 systemd，需已 sudo 注册服务

Project Update:
  clashctl update-self            从 GitHub main 直接无损更新项目脚本
  clashctl update-self --ref vX   从指定分支或 tag 更新
  clashctl update-self --repo owner/repo
                                   从指定 GitHub 仓库更新
  clashctl update-self --source <dir>
                                   从本地源码目录更新

Docs:
  https://github.com/tyx3211/tyx-clash-for-linux-install/blob/main/docs/quickstart.md
  https://github.com/tyx3211/tyx-clash-for-linux-install/blob/main/docs/config-versioning.md
EOF
}
