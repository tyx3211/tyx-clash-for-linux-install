#!/usr/bin/env bash

set -euo pipefail

THIS_UPDATE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
cd "$THIS_UPDATE_DIR" || exit 1

target=
while (($#)); do
    case "$1" in
    --target=*)
        target=${1#--target=}
        ;;
    --target)
        shift
        [ $# -gt 0 ] || {
            printf '📢 --target 需要指定安装目录\n' >&2
            exit 1
        }
        target=$1
        ;;
    -h | --help)
        cat <<EOF
Usage:
  bash update.sh [--target <install_dir>]

默认从当前源码仓库刷新已安装的 clashctl 脚本和文档资产，并保留用户配置、订阅和运行状态。
EOF
        exit 0
        ;;
    *)
        printf '📢 未知参数：%s\n' "$1" >&2
        exit 1
        ;;
    esac
    shift
done

[ -z "$target" ] && {
    # shellcheck disable=SC1091
    . "$THIS_UPDATE_DIR/.env"
    target=$CLASH_BASE_DIR
}

case "$target" in
~/*)
    target="${HOME}/${target#~/}"
    ;;
esac

target=$(cd "$target" 2>/dev/null && pwd -P) || {
    printf '📢 安装目录不存在：%s\n' "$target" >&2
    exit 1
}

case "$target" in
"" | "/" | "$HOME" | "$HOME/" | . | .. | ./* | ../*)
    printf '📢 拒绝更新异常安装目录：%s\n' "${target:-<empty>}" >&2
    exit 1
    ;;
esac

marker="$target/.clashctl-install-root"
legacy=false
if [ -f "$marker" ] && grep -qx 'tyx-clash-for-linux-install' "$marker"; then
    :
elif [ -f "$target/scripts/cmd/clashctl.sh" ] && [ -f "$target/resources/mixin.yaml" ]; then
    legacy=true
else
    printf '📢 目标目录不像 clashctl 安装目录，拒绝更新：%s\n' "$target" >&2
    exit 1
fi

backup_dir="$target/.update-backup/$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
for path in .env scripts install.sh uninstall.sh update.sh README.md docs tests; do
    [ -e "$target/$path" ] || continue
    mkdir -p "$backup_dir/$(dirname "$path")"
    tar -C "$target" -cf - "$path" | tar -C "$backup_dir" -xf -
done

tar -cf - \
    install.sh \
    uninstall.sh \
    update.sh \
    README.md \
    scripts \
    docs \
    tests |
    tar -C "$target" -xf -

printf '%s\n' 'tyx-clash-for-linux-install' >"$marker"

env_path="$target/.env"
[ -f "$env_path" ] || /usr/bin/install -m 644 "$THIS_UPDATE_DIR/.env" "$env_path"
while IFS= read -r line; do
    case "$line" in
    "" | "#"*)
        continue
        ;;
    *=*)
        key=${line%%=*}
        grep -qE "^${key}=" "$env_path" || printf '%s\n' "$line" >>"$env_path"
        ;;
    esac
done <"$THIS_UPDATE_DIR/.env"

[ "$legacy" = true ] && printf '📢 已按历史 nosudo-tmux 安装目录执行原地迁移，旧配置已保留。\n'
printf '✨ 项目脚本已更新，用户配置和订阅状态已保留：%s\n' "$target"
