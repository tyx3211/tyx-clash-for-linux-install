#!/usr/bin/env bash

set -euo pipefail

THIS_UPDATE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
SOURCE_DIR=
source_explicit=false
target=
UPDATE_REPO=${CLASHCTL_UPDATE_REPO:-tyx3211/tyx-clash-for-linux-install}
UPDATE_REF=${CLASHCTL_UPDATE_REF:-main}
download_tmp=

_die() {
    printf '📢 %s\n' "$1" >&2
    [ -n "${download_tmp:-}" ] && /usr/bin/rm -rf "$download_tmp"
    exit 1
}

_expand_path() {
    local path=$1
    case "$path" in
    "~")
        printf '%s\n' "$HOME"
        ;;
    "~/"*)
        printf '%s/%s\n' "$HOME" "${path#~/}"
        ;;
    '$HOME')
        printf '%s\n' "$HOME"
        ;;
    '$HOME/'*)
        printf '%s/%s\n' "$HOME" "${path#\$HOME/}"
        ;;
    *)
        printf '%s\n' "$path"
        ;;
    esac
}

_read_env_value() {
    local file=$1 key=$2 line value=
    [ -f "$file" ] || return 1

    while IFS= read -r line; do
        case "$line" in
        "$key="*)
            value=${line#*=}
            ;;
        esac
    done <"$file"

    [ -n "$value" ] || return 1
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
    _expand_path "$value"
}

_canonical_dir() {
    local path
    path=$(_expand_path "$1")
    cd "$path" 2>/dev/null && pwd -P
}

_is_install_root() {
    local dir=$1 marker
    marker="$dir/.clashctl-install-root"
    [ -f "$marker" ] && grep -qx 'tyx-clash-for-linux-install' "$marker"
}

_validate_target_path() {
    local path=$1
    case "$path" in
    "" | "/" | "$HOME" | "$HOME/" | . | .. | ./* | ../*)
        _die "拒绝更新异常安装目录：${path:-<empty>}"
        ;;
    esac

    case "$path" in
    *[!A-Za-z0-9_./-]*)
        _die "安装目录包含 shell 模板不支持的字符，请仅使用字母、数字、_、-、.、/：$path"
        ;;
    esac
}

_validate_repo_slug() {
    local repo=$1
    [[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
        _die "更新仓库必须是 owner/repo 格式：$repo"
}

_validate_ref() {
    local ref=$1
    [[ $ref =~ ^[A-Za-z0-9._/-]+$ ]] ||
        _die "更新 ref 只能包含字母、数字、.、_、-、/：$ref"

    case "$ref" in
    "" | /* | */ | *..* | *//*)
        _die "更新 ref 不安全：$ref"
        ;;
    esac
}

_download_remote_source() {
    local update_target=$1
    local archive archive_root proxy url

    download_tmp=$(mktemp -d "$update_target/.update-source.XXXXXX")
    archive="$download_tmp/source.tar.gz"
    url="https://github.com/${UPDATE_REPO}/archive/${UPDATE_REF}.tar.gz"
    proxy=$(_read_env_value "$update_target/.env" URL_GH_PROXY 2>/dev/null || true)
    [ -n "$proxy" ] && url="${proxy%/}/${url}"

    printf '⏳ 正在下载项目源码：%s@%s\n' "$UPDATE_REPO" "$UPDATE_REF" >&2
    if ! curl --fail --location --show-error --silent -o "$archive" "$url"; then
        /usr/bin/rm -rf "$download_tmp"
        download_tmp=
        _die "项目源码下载失败：$url"
    fi

    if ! tar -xzf "$archive" -C "$download_tmp"; then
        /usr/bin/rm -rf "$download_tmp"
        download_tmp=
        _die "项目源码归档解压失败：$url"
    fi

    archive_root=$(find "$download_tmp" -mindepth 2 -maxdepth 2 -type f -name update.sh -print -quit)
    [ -n "$archive_root" ] || {
        /usr/bin/rm -rf "$download_tmp"
        download_tmp=
        _die "项目源码归档中没有找到 update.sh"
    }
    dirname "$archive_root"
}

_reject_managed_symlinks() {
    local path full found
    [ -L "$target/.update-backup" ] && _die "拒绝使用符号链接备份目录：$target/.update-backup"
    for path in "$@"; do
        full="$target/$path"
        [ -e "$full" ] || [ -L "$full" ] || continue
        [ -L "$full" ] && _die "拒绝更新包含符号链接的托管路径：$full"
        [ -d "$full" ] || continue
        found=$(find -P "$full" -type l -print -quit)
        [ -n "$found" ] && _die "拒绝更新包含符号链接的托管路径：$found"
    done
    return 0
}

_validate_source_tree() {
    local source=$1 path full found

    [ -f "$source/update.sh" ] && [ -f "$source/.env" ] && [ -d "$source/scripts/cmd" ] ||
        _die "源码目录不像 tyx-clash-for-linux-install 仓库：$source"

    for path in "${managed_paths[@]}"; do
        full="$source/$path"
        [ -e "$full" ] || _die "源码目录缺少托管路径：$full"
        [ -L "$full" ] && _die "拒绝更新包含符号链接的源码托管路径：$full"
        [ -d "$full" ] || continue
        found=$(find -P "$full" -type l -print -quit)
        [ -n "$found" ] && _die "拒绝更新包含符号链接的源码托管路径：$found"
    done
    return 0
}

_set_env_value() {
    local file=$1 key=$2 value=$3 escaped
    escaped=$(printf '%s' "$value" | sed -e 's/[#&\\]/\\&/g')
    if grep -qE "^${key}=" "$file"; then
        sed -i -e "s#^${key}=.*#${key}=${escaped}#g" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >>"$file"
    fi
}

while (($#)); do
    case "$1" in
    --target=*)
        target=${1#--target=}
        ;;
    --target)
        shift
        [ $# -gt 0 ] || _die "--target 需要指定安装目录"
        target=$1
        ;;
    --source=*)
        SOURCE_DIR=${1#--source=}
        source_explicit=true
        ;;
    --source)
        shift
        [ $# -gt 0 ] || _die "--source 需要指定源码目录"
        SOURCE_DIR=$1
        source_explicit=true
        ;;
    --repo=*)
        UPDATE_REPO=${1#--repo=}
        ;;
    --repo)
        shift
        [ $# -gt 0 ] || _die "--repo 需要指定 owner/repo"
        UPDATE_REPO=$1
        ;;
    --ref=*)
        UPDATE_REF=${1#--ref=}
        ;;
    --ref)
        shift
        [ $# -gt 0 ] || _die "--ref 需要指定 branch、tag 或 commit"
        UPDATE_REF=$1
        ;;
    -h | --help)
        cat <<EOF
Usage:
  bash update.sh [--target <install_dir>] [--source <source_dir>]
  bash update.sh [--target <install_dir>] [--repo <owner/repo>] [--ref <branch_or_tag>]

默认从当前源码仓库刷新已安装的 clashctl 脚本和文档资产，并保留用户配置、订阅和运行状态。
如果在已安装目录中运行且未指定 --source，则默认从 GitHub 下载 tyx3211/tyx-clash-for-linux-install 的 main 分支后无损更新。
EOF
        exit 0
        ;;
    *)
        _die "未知参数：$1"
        ;;
    esac
    shift
done

_validate_repo_slug "$UPDATE_REPO"
_validate_ref "$UPDATE_REF"

if [ "$source_explicit" = true ]; then
    SOURCE_DIR=$(_canonical_dir "$SOURCE_DIR") || _die "源码目录不存在：$SOURCE_DIR"
elif _is_install_root "$THIS_UPDATE_DIR"; then
    SOURCE_DIR=
else
    SOURCE_DIR=$(_canonical_dir "$THIS_UPDATE_DIR") || _die "源码目录不存在：$THIS_UPDATE_DIR"
fi

if [ -z "$target" ]; then
    if [ -n "$SOURCE_DIR" ]; then
        target=$(_read_env_value "$SOURCE_DIR/.env" CLASH_BASE_DIR) || true
        [ -n "$target" ] || _die "无法从源码 .env 读取 CLASH_BASE_DIR，请显式指定 --target"
    else
        target=$(_read_env_value "$THIS_UPDATE_DIR/.env" CLASH_BASE_DIR 2>/dev/null || true)
        [ -n "$target" ] || target=$THIS_UPDATE_DIR
    fi
fi

target=$(_canonical_dir "$target") || _die "安装目录不存在：$target"
_validate_target_path "$target"

marker="$target/.clashctl-install-root"
legacy=false
if [ -f "$marker" ] && grep -qx 'tyx-clash-for-linux-install' "$marker"; then
    :
elif [ -f "$target/scripts/cmd/clashctl.sh" ] && [ -f "$target/resources/mixin.yaml" ]; then
    legacy=true
else
    _die "目标目录不像 clashctl 安装目录，拒绝更新：$target"
fi

managed_paths=(install.sh uninstall.sh update.sh README.md scripts docs tests)
backup_paths=(.env .clashctl-install-root "${managed_paths[@]}")
_reject_managed_symlinks "${backup_paths[@]}"

[ -n "$SOURCE_DIR" ] || SOURCE_DIR=$(_download_remote_source "$target")
SOURCE_DIR=$(_canonical_dir "$SOURCE_DIR") || _die "源码目录不存在：$SOURCE_DIR"
_validate_source_tree "$SOURCE_DIR"

backup_root="$target/.update-backup"
mkdir -p "$backup_root"
backup_dir=$(mktemp -d "$backup_root/$(date +%Y%m%d%H%M%S).XXXXXX")
staging_dir=$(mktemp -d "$target/.update-staging.XXXXXX")
rollback_needed=false

_rollback_update() {
    local status=$?
    if [ "${rollback_needed:-false}" = true ]; then
        local path
        for path in "${backup_paths[@]}"; do
            /usr/bin/rm -rf "$target/$path"
            [ -e "$backup_dir/$path" ] || continue
            mkdir -p "$target/$(dirname "$path")"
            cp -a "$backup_dir/$path" "$target/$path"
        done
    fi
    [ -n "${staging_dir:-}" ] && /usr/bin/rm -rf "$staging_dir"
    [ -n "${download_tmp:-}" ] && /usr/bin/rm -rf "$download_tmp"
    return "$status"
}
trap _rollback_update EXIT INT TERM

for path in "${backup_paths[@]}"; do
    [ -e "$target/$path" ] || continue
    mkdir -p "$backup_dir/$(dirname "$path")"
    cp -a "$target/$path" "$backup_dir/$path"
done

rollback_needed=true

tar -C "$SOURCE_DIR" -cf - "${managed_paths[@]}" | tar -C "$staging_dir" -xf -

for path in "${managed_paths[@]}"; do
    /usr/bin/rm -rf "$target/$path"
    mkdir -p "$target/$(dirname "$path")"
    cp -a "$staging_dir/$path" "$target/$path"
done

printf '%s\n' 'tyx-clash-for-linux-install' >"$marker"

env_path="$target/.env"
if [ -f "$env_path" ]; then
    existing_target=$(_read_env_value "$env_path" CLASH_BASE_DIR 2>/dev/null || true)
    if [ -n "$existing_target" ]; then
        existing_target=$(_canonical_dir "$existing_target" 2>/dev/null || true)
        [ -z "$existing_target" ] || [ "$existing_target" = "$target" ] ||
            _die "目标 .env 中的 CLASH_BASE_DIR 不属于当前安装目录：$existing_target != $target"
    fi
else
    /usr/bin/install -m 644 "$SOURCE_DIR/.env" "$env_path"
fi
_set_env_value "$env_path" CLASH_BASE_DIR "$target"

while IFS= read -r line; do
    case "$line" in
    "" | "#"*)
        continue
        ;;
    *=*)
        key=${line%%=*}
        [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        grep -qE "^${key}=" "$env_path" || printf '%s\n' "$line" >>"$env_path"
        ;;
    esac
done <"$SOURCE_DIR/.env"

rollback_needed=false
trap - EXIT INT TERM
/usr/bin/rm -rf "$staging_dir"
[ -n "${download_tmp:-}" ] && /usr/bin/rm -rf "$download_tmp"

[ "$legacy" = true ] && printf '📢 已按历史 nosudo-tmux 安装目录执行原地迁移，旧配置已保留。\n'
printf '✨ 项目脚本已更新，用户配置和订阅状态已保留：%s\n' "$target"
