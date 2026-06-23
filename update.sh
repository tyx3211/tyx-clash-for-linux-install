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

_bootstrap_expand_path() {
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

_load_path_env_lib() {
    local root expanded candidate
    for root in "$THIS_UPDATE_DIR" "${SOURCE_DIR:-}"; do
        [ -n "$root" ] || continue
        for expanded in "$root" "$(_bootstrap_expand_path "$root")"; do
            [ -n "$expanded" ] || continue
            candidate="$expanded/scripts/lib/path-env.sh"
            [ -r "$candidate" ] || continue
            . "$candidate" || _die "环境解析脚本加载失败：$candidate"
            declare -F _path_env_read_value >/dev/null ||
                _die "环境解析脚本缺少必要函数：$candidate"
            return 0
        done
    done

    _die "缺少环境解析脚本：$THIS_UPDATE_DIR/scripts/lib/path-env.sh"
}

_load_install_state_lib() {
    [ "${INSTALL_STATE_LIB_LOADED:-false}" = true ] && return 0

    local candidate
    for candidate in "$THIS_UPDATE_DIR/scripts/lib/install-state.sh" "${SOURCE_DIR:-}/scripts/lib/install-state.sh"; do
        [ -n "$candidate" ] || continue
        [ -r "$candidate" ] || continue
        . "$candidate" || _die "安装状态解析脚本加载失败：$candidate"
        INSTALL_STATE_LIB_LOADED=true
        return 0
    done

    _die "缺少安装状态解析脚本：$THIS_UPDATE_DIR/scripts/lib/install-state.sh"
}

_read_state_value() {
    local root=$1 key=$2
    _load_install_state_lib
    _install_state_read_yaml_value "$root/resources/install-state.yaml" "$key"
}

_read_install_dir_value() {
    local root=$1 value=

    if [ -e "$root/resources/install-state.yaml" ]; then
        value=$(_read_state_value "$root" install_dir) ||
            _die "安装状态读取失败：$root/resources/install-state.yaml"
    else
        value=$(_path_env_read_path_value_any "$root/.env" CLASH_BASE_DIR CLASHCTL_HOME 2>/dev/null || true)
    fi
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

_read_target_metadata() {
    local root=$1 key=$2 env_key=$3 value=

    if [ -e "$root/resources/install-state.yaml" ]; then
        value=$(_read_state_value "$root" "$key") ||
            _die "安装状态读取失败：$root/resources/install-state.yaml"
    else
        case "$env_key" in
        KERNEL_NAME)
            value=$(_path_env_read_value_any "$root/.env" KERNEL_NAME CLASHCTL_KERNEL 2>/dev/null || true)
            ;;
        CLASH_BASE_DIR)
            value=$(_path_env_read_path_value_any "$root/.env" CLASH_BASE_DIR CLASHCTL_HOME 2>/dev/null || true)
            ;;
        *)
            value=$(_path_env_read_value "$root/.env" "$env_key" 2>/dev/null || true)
            ;;
        esac
    fi
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

_canonical_dir() {
    local path
    path=$(_path_env_expand_path "$1")
    cd "$path" 2>/dev/null && pwd -P
}

_is_install_root() {
    local dir=$1 marker
    marker="$dir/.clashctl-install-root"
    [ ! -L "$marker" ] && [ -f "$marker" ] && grep -qx 'tyx-clash-for-linux-install' "$marker"
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
    case "$path" in
    */../* | */.. | */./* | */.)
        _die "安装目录不能包含 . 或 .. 路径组件：$path"
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

_archive_member_path_is_safe() {
    local member=${1#./}

    case "$member" in
    "" | "/" | /* | "." | ".." | ../* | */../* | */.. | */./* | */.)
        return 1
        ;;
    esac
    return 0
}

_tar_archive_is_safe() {
    local archive=$1 mode member

    tar -tf "$archive" >/dev/null 2>&1 || return 1
    while IFS= read -r member; do
        _archive_member_path_is_safe "$member" || return 1
    done < <(tar -tf "$archive" 2>/dev/null)

    while IFS= read -r mode _; do
        case "$mode" in
        -* | d*)
            ;;
        *)
            return 1
            ;;
        esac
    done < <(tar -tvf "$archive" 2>/dev/null)
    return 0
}

_download_remote_source() {
    local update_target=$1
    local archive archive_root proxy url

    download_tmp=$(mktemp -d "$update_target/.update-source.XXXXXX")
    archive="$download_tmp/source.tar.gz"
    url="https://github.com/${UPDATE_REPO}/archive/${UPDATE_REF}.tar.gz"
    proxy=$(_path_env_read_value "$update_target/.env" URL_GH_PROXY 2>/dev/null || true)
    [ -n "$proxy" ] && url="${proxy%/}/${url}"

    printf '⏳ 正在下载项目源码：%s@%s\n' "$UPDATE_REPO" "$UPDATE_REF" >&2
    if ! curl --fail --location --show-error --silent -o "$archive" "$url"; then
        /usr/bin/rm -rf "$download_tmp"
        download_tmp=
        _die "项目源码下载失败：$url"
    fi

    if ! _tar_archive_is_safe "$archive"; then
        /usr/bin/rm -rf "$download_tmp"
        download_tmp=
        _die "项目源码归档包含不安全路径或特殊文件：$url"
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
    local source=$1 path full found required_file
    local required_files=(
        update.sh
        install.sh
        uninstall.sh
        migrate.sh
        scripts/preflight.sh
        scripts/cmd/clashctl.sh
        scripts/cmd/common.sh
        scripts/cmd/clashctl.fish
        scripts/lib/config.sh
        scripts/lib/install-state.sh
        scripts/lib/path-env.sh
        scripts/lib/proxy.sh
        scripts/lib/runtime-config.sh
        scripts/lib/service-runtime.sh
        scripts/lib/subscription.sh
        scripts/lib/tun.sh
        scripts/install/archive-safe.sh
        scripts/install/service-render.sh
        scripts/install/rc.sh
        scripts/init/systemd.sh
        scripts/init/OpenRC.sh
        scripts/init/SysVinit.sh
        scripts/init/runit.sh
    )

    [ -f "$source/update.sh" ] && [ -d "$source/scripts/cmd" ] && [ -f "$source/scripts/lib/install-state.sh" ] ||
        _die "源码目录不像 tyx-clash-for-linux-install 仓库：$source"

    for required_file in "${required_files[@]}"; do
        [ -f "$source/$required_file" ] ||
            _die "源码目录缺少必需文件：$source/$required_file"
    done

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

_validate_existing_install_state() {
    local state_path="$target/resources/install-state.yaml"
    local state_target= kernel_name=

    [ -e "$state_path" ] || return 0
    _load_install_state_lib
    [ ! -L "$target/resources" ] && [ ! -L "$state_path" ] ||
        _die "拒绝读取符号链接安装状态文件：$state_path"

    state_target=$(_read_state_value "$target" install_dir) ||
        _die "安装状态读取失败：$state_path"
    [ -n "$state_target" ] || _die "安装状态缺少 install_dir：$state_path"
    state_target=$(_canonical_dir "$state_target" 2>/dev/null || true)
    [ -n "$state_target" ] || _die "安装状态 install_dir 不存在：$state_path"
    [ "$state_target" = "$target" ] ||
        _die "安装状态目录不属于当前目标：$state_target != $target"

    kernel_name=$(_read_state_value "$target" kernel_name) ||
        _die "安装状态读取失败：$state_path"
    [ -n "$kernel_name" ] || _die "安装状态缺少 kernel_name：$state_path"
    _install_state_validate_kernel_name "$kernel_name" ||
        _die "内核名称不安全，仅支持 mihomo、clash：$kernel_name"
}

_set_env_value() {
    local file=$1 key=$2 value=$3 escaped
    escaped=$(printf '%s' "$value" | sed -e 's/[#&\\]/\\&/g')
    if _env_has_any_key "$file" "$key"; then
        sed -i -E -e "s#^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=.*#${key}=${escaped}#g" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >>"$file"
    fi
}

_env_has_any_key() {
    local file=$1 key
    shift

    [ -f "$file" ] || return 1
    for key in "$@"; do
        [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        grep -qE "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$file" && return 0
    done
    return 1
}

_env_assignment_payload() {
    local line=$1

    case "$line" in
    "" | "#"*)
        return 1
        ;;
    export[[:space:]]*)
        line=${line#export}
        line=${line#"${line%%[![:space:]]*}"}
        ;;
    esac

    case "$line" in
    *=*)
        printf '%s\n' "$line"
        ;;
    *)
        return 1
        ;;
    esac
}

_migrate_known_env_defaults() {
    local env_file=$1 line payload key value
    local has_bad_subconverter=false has_custom_subconverter=false
    local wrote_default=false tmp_file=

    [ -f "$env_file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        payload=$(_env_assignment_payload "$line" 2>/dev/null || true)
        [ -n "$payload" ] || continue
        key=${payload%%=*}
        key=$(_path_env_trim "$key")
        [ "$key" = SUBCONVERTER_REPO ] || continue
        value=$(_path_env_unquote "${payload#*=}")
        if [ "$value" = asdlokj1qpi233/subconverter ]; then
            has_bad_subconverter=true
        else
            has_custom_subconverter=true
        fi
    done <"$env_file"

    [ "$has_bad_subconverter" = true ] || return 0

    tmp_file=$(mktemp "${env_file}.migrate.XXXXXX") || _die "无法创建 .env 迁移临时文件：$env_file"
    while IFS= read -r line || [ -n "$line" ]; do
        payload=$(_env_assignment_payload "$line" 2>/dev/null || true)
        if [ -n "$payload" ]; then
            key=${payload%%=*}
            key=$(_path_env_trim "$key")
            value=$(_path_env_unquote "${payload#*=}")
            if [ "$key" = SUBCONVERTER_REPO ] && [ "$value" = asdlokj1qpi233/subconverter ]; then
                if [ "$has_custom_subconverter" = false ] && [ "$wrote_default" = false ]; then
                    printf '%s\n' 'SUBCONVERTER_REPO=tindy2013/subconverter' >>"$tmp_file"
                    wrote_default=true
                fi
                continue
            fi
        fi
        printf '%s\n' "$line" >>"$tmp_file"
    done <"$env_file"
    mv "$tmp_file" "$env_file"
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
安装状态优先保存在 resources/install-state.yaml；旧 .env 如存在会继续保留用于兼容。
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

_load_path_env_lib

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
    if _is_install_root "$THIS_UPDATE_DIR"; then
        target=$THIS_UPDATE_DIR
    elif [ -n "$SOURCE_DIR" ]; then
        target=$(_read_install_dir_value "$SOURCE_DIR") || true
        [ -n "$target" ] || _die "无法从源码安装状态读取安装目录，请显式指定 --target"
    else
        target=$(_read_install_dir_value "$THIS_UPDATE_DIR" 2>/dev/null || true)
        [ -n "$target" ] || target=$THIS_UPDATE_DIR
    fi
fi

target=$(_canonical_dir "$target") || _die "安装目录不存在：$target"
_validate_target_path "$target"

marker="$target/.clashctl-install-root"
legacy=false
if [ -L "$marker" ]; then
    _die "拒绝使用符号链接安装标记：$marker"
elif [ -f "$marker" ] && grep -qx 'tyx-clash-for-linux-install' "$marker"; then
    :
elif [ -f "$target/scripts/cmd/clashctl.sh" ] &&
    { [ -f "$target/resources/mixin.yaml" ] || [ -f "$target/config/mixin.yaml" ]; }; then
    legacy=true
else
    _die "目标目录不像 clashctl 安装目录，拒绝更新：$target"
fi

_validate_existing_install_state

managed_paths=(install.sh uninstall.sh update.sh migrate.sh README.md scripts docs tests)
obsolete_paths=(placeholder_start1 preview.png .github .editorconfig .gitattributes .shellcheckrc resources/preview.png)
backup_paths=(.env .clashctl-install-root "${managed_paths[@]}" "${obsolete_paths[@]}")
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

for path in "${obsolete_paths[@]}"; do
    [ -e "$target/$path" ] || [ -L "$target/$path" ] || continue
    /usr/bin/rm -rf "$target/$path"
done

printf '%s\n' 'tyx-clash-for-linux-install' >"$marker"

env_path="$target/.env"
if [ -f "$env_path" ]; then
    existing_target=$(_path_env_read_path_value_any "$env_path" CLASH_BASE_DIR CLASHCTL_HOME 2>/dev/null || true)
    if [ -n "$existing_target" ]; then
        existing_target=$(_canonical_dir "$existing_target" 2>/dev/null || true)
        [ -z "$existing_target" ] || [ "$existing_target" = "$target" ] ||
            _die "目标 .env 中的 CLASH_BASE_DIR 不属于当前安装目录：$existing_target != $target"
    fi
    _set_env_value "$env_path" CLASH_BASE_DIR "$target"
fi

if [ -f "$env_path" ] && [ -f "$SOURCE_DIR/.env" ]; then
    while IFS= read -r line; do
        case "$line" in
        "" | "#"*)
            continue
            ;;
        *=*)
            key=${line%%=*}
            [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
            case "$key" in
            CLASH_BASE_DIR)
                _env_has_any_key "$env_path" CLASH_BASE_DIR CLASHCTL_HOME || printf '%s\n' "$line" >>"$env_path"
                ;;
            KERNEL_NAME)
                _env_has_any_key "$env_path" KERNEL_NAME CLASHCTL_KERNEL || printf '%s\n' "$line" >>"$env_path"
                ;;
            CLASH_SUB_UA)
                _env_has_any_key "$env_path" CLASH_SUB_UA CLASHCTL_SUB_UA || printf '%s\n' "$line" >>"$env_path"
                ;;
            *)
                _env_has_any_key "$env_path" "$key" || printf '%s\n' "$line" >>"$env_path"
                ;;
            esac
            ;;
        esac
    done <"$SOURCE_DIR/.env"
fi
_migrate_known_env_defaults "$env_path"

state_path="$target/resources/install-state.yaml"
if [ -L "$target/resources" ] || [ -L "$state_path" ]; then
    _die "拒绝写入符号链接安装状态文件：$state_path"
fi
if [ ! -f "$state_path" ]; then
    _load_install_state_lib
    kernel_name=$(_read_target_metadata "$target" kernel_name KERNEL_NAME 2>/dev/null || printf '%s\n' mihomo)
    _install_state_validate_kernel_name "$kernel_name" ||
        _die "内核名称不安全，仅支持 mihomo、clash：$kernel_name"
    default_mode=$(_read_target_metadata "$target" default_mode INIT_TYPE 2>/dev/null || printf '%s\n' tmux)
    installed_systemd=false
    installed_init=$(_path_env_read_value "$env_path" CLASH_INSTALLED_INIT_TYPE 2>/dev/null || true)
    [ "$installed_init" = systemd ] && installed_systemd=true
    [ "$default_mode" = systemd ] && installed_systemd=true
    version_mihomo=$(_path_env_read_value "$env_path" VERSION_MIHOMO 2>/dev/null || true)
    version_yq=$(_path_env_read_value "$env_path" VERSION_YQ 2>/dev/null || true)
    version_subconverter=$(_path_env_read_value "$env_path" VERSION_SUBCONVERTER 2>/dev/null || true)
    _install_state_write \
        "$state_path" \
        "$target" \
        "$kernel_name" \
        "$default_mode" \
        "$installed_systemd" \
        "$version_mihomo" \
        "$version_yq" \
        "$version_subconverter" ||
        _die "安装状态写入失败：$state_path"
fi

rollback_needed=false
trap - EXIT INT TERM
/usr/bin/rm -rf "$staging_dir"
[ -n "${download_tmp:-}" ] && /usr/bin/rm -rf "$download_tmp"

[ "$legacy" = true ] && printf '📢 已按历史 nosudo-tmux 安装目录执行原地迁移，旧配置已保留。\n'
printf '✨ 项目脚本已更新，用户配置和订阅状态已保留：%s\n' "$target"
