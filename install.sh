#!/usr/bin/env bash

. scripts/cmd/clashctl.sh
. scripts/preflight.sh

_valid
_parse_args "$@"

_prepare_zip
_detect_init

_okcat "安装内核：$KERNEL_NAME by ${INIT_TYPE}"
_okcat '📦' "安装路径：$CLASH_BASE_DIR"

/bin/cp -rf . "$CLASH_BASE_DIR"
touch "$CLASH_CONFIG_BASE"
_set_envs
_is_regular_sudo && chown -R "$SUDO_USER" "$CLASH_BASE_DIR"

_install_service
[ -n "$CLASHCTL_NO_RC" ] || _apply_rc


# 重新加载已替换占位符的脚本
. "$CLASH_CMD_DIR/clashctl.sh"

_merge_config
_detect_proxy_port
clashui
clashsecret "$(_get_random_val)" >/dev/null
clashsecret

_okcat '🎉' 'enjoy 🎉'
clashctl

_valid_config "$CLASH_CONFIG_BASE" && CLASH_CONFIG_URL="file://$CLASH_CONFIG_BASE"
[ -n "$CLASHCTL_NO_QUIT" ] && {
    _okcat "已跳过自动订阅导入（CLASHCTL_NO_QUIT=1）"
    exit 0
}

# 优先导入预先给定的订阅；若未提供，则回退到交互式输入。
if [ -n "$CLASH_CONFIG_URL" ]; then
    printf -v quit_cmd 'clashsub add %q && clashsub use 1' "$CLASH_CONFIG_URL"
else
    quit_cmd='clashsub add && clashsub use 1'
fi

_quit "$quit_cmd"
