#!/usr/bin/env bash

THIS_INSTALL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
cd "$THIS_INSTALL_DIR" || exit 1

CLASHCTL_INSTALL_BOOTSTRAP=1
CLASHCTL_INSTALL_BOOTSTRAP_SOURCE_DIR=$THIS_INSTALL_DIR
. "$THIS_INSTALL_DIR/scripts/cmd/clashctl.sh" || exit 1
unset CLASHCTL_INSTALL_BOOTSTRAP CLASHCTL_INSTALL_BOOTSTRAP_SOURCE_DIR
. "$THIS_INSTALL_DIR/scripts/preflight.sh" || exit 1

CLASHCTL_ERROR_EXIT=1

_copy_install_payload() {
    local payload_paths=(
        .env
        LICENSE
        README.md
        install.sh
        migrate.sh
        uninstall.sh
        update.sh
        scripts
        docs
        tests
        config
        resources
    )
    local path missing=() full found

    for path in "${payload_paths[@]}"; do
        full="$THIS_INSTALL_DIR/$path"
        [ -e "$full" ] || missing+=("$path")
        [ -L "$full" ] && {
            printf '安装载荷包含符号链接，拒绝复制：%s\n' "$full" >&2
            return 1
        }
        [ -d "$full" ] || continue
        found=$(find -P "$full" -type l -print -quit)
        [ -n "$found" ] && {
            printf '安装载荷包含符号链接，拒绝复制：%s\n' "$found" >&2
            return 1
        }
    done

    [ "${#missing[@]}" -eq 0 ] || {
        printf '缺少安装载荷：%s\n' "${missing[*]}" >&2
        return 1
    }

    tar -C "$THIS_INSTALL_DIR" -cf - "${payload_paths[@]}" |
        tar -C "$CLASH_BASE_DIR" -xf -
}

_parse_args "$@"
_normalize_sudo_install_path
_validate_kernel_name
_refresh_install_paths
_validate_init_mode
_register_install_cleanup
_valid

_prepare_zip || _error_quit "依赖准备失败，请检查下载归档和权限"
_detect_init || _error_quit "启动方式检测失败，请检查 --init 参数和本机依赖"

_okcat "安装内核：$KERNEL_NAME by ${INIT_TYPE}"
_okcat '📦' "安装路径：$CLASH_BASE_DIR"

_copy_install_payload || _error_quit "安装文件复制失败"
printf '%s\n' 'clash-for-linux-install-multimode' >"$INSTALL_MARKER"
touch "$CLASH_CONFIG_BASE"
_set_envs
_init_config_git
_is_regular_sudo && chown -R "$SUDO_USER" "$CLASH_BASE_DIR"

CLASH_INSTALL_SERVICE_TOUCHED=true
_install_service || _error_quit "服务安装失败，请检查启动方式和权限"
if [ -z "$CLASHCTL_NO_RC" ]; then
    CLASH_INSTALL_RC_TOUCHED=true
    _apply_rc || _error_quit "shell rc 写入失败，请检查 shell 配置文件权限"
fi


# 重新加载已替换占位符的脚本
. "$CLASH_CMD_DIR/clashctl.sh"

_merge_config || _error_quit "验证失败：请检查 Mixin 配置"
_detect_proxy_port || _error_quit "代理端口冲突，请按提示修改 Mixin 配置后重试"

_valid_config "$CLASH_CONFIG_BASE" && CLASH_CONFIG_URL="file://$CLASH_CONFIG_BASE"
[ -n "$CLASHCTL_NO_QUIT" ] && {
    _okcat "已跳过自动订阅导入（CLASHCTL_NO_QUIT=1）"
    if [ -n "$CLASHCTL_NO_RC" ]; then
        _okcat "已跳过写入 shell rc；如需立即使用，请执行：. $CLASH_CMD_DIR/clashctl.sh"
    else
        _okcat "安装已写入 shell rc；如需在当前 shell 立即使用，请执行：. $CLASH_CMD_DIR/clashctl.sh"
    fi
    _mark_install_complete
    exit 0
}

if [ -n "$CLASH_CONFIG_URL" ]; then
    clashsub add "$CLASH_CONFIG_URL" || exit $?
else
    clashsub add || exit $?
fi
clashsub use 1 || exit $?

[ -z "$(_get_secret)" ] && clashsecret "$(_get_random_val)" >/dev/null
clashui || _error_quit "Web 控制台地址检测失败"
clashsecret

_mark_install_complete
_okcat '🎉' 'enjoy 🎉'
clashctl

[ -n "$CLASHCTL_NO_RC" ] && {
    _okcat "已跳过写入 shell rc；如需立即使用，请执行：. $CLASH_CMD_DIR/clashctl.sh"
    exit 0
}

_okcat "即将进入新的交互 shell，clashctl 已可直接使用"
_quit
