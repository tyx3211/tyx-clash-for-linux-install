#!/usr/bin/env bash

set -euo pipefail

THIS_MIGRATE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
target=
source_dir=
restart_mode=
status_check=true
move_legacy_config=false
force_remove_legacy_config=false

_die() {
    printf '📢 %s\n' "$1" >&2
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
    for root in "$THIS_MIGRATE_DIR" "${source_dir:-}"; do
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

    _die "缺少环境解析脚本：$THIS_MIGRATE_DIR/scripts/lib/path-env.sh"
}

_canonical_dir() {
    local path
    path=$(_path_env_expand_path "$1")
    cd "$path" 2>/dev/null && pwd -P
}

_find_target_from_env() {
    local candidate
    for candidate in "$THIS_MIGRATE_DIR/.env" "$HOME/clashctl/.env"; do
        [ -f "$candidate" ] || continue
        _path_env_read_path_value "$candidate" CLASH_BASE_DIR && return 0
        _path_env_read_path_value "$candidate" CLASHCTL_HOME && return 0
    done
    return 1
}

_validate_mode() {
    case "$1" in
    "" | tmux | nohup | systemd)
        return 0
        ;;
    *)
        _die "迁移后重启模式仅支持 tmux、nohup、systemd：$1"
        ;;
    esac
}

_print_help() {
    cat <<EOF
Usage:
  bash migrate.sh [--target <install_dir>] [--source <source_dir>] [--restart-mode <tmux|nohup|systemd>]

默认行为：
  - 原地刷新旧安装目录中的项目脚本。
  - 写入 resources/install-state.yaml。
  - 默认将旧 resources/mixin.yaml、resources/clashctl.yaml、resources/profiles.yaml 复制到 config/，并保留旧位置文件。
  - 清理旧项目遗留文件，如 placeholder_start1、.github、.editorconfig。
  - 不停止内核，不启动内核，不修改当前 shell 的代理变量。

Options:
  --move-legacy-config
      将旧 resources/mixin.yaml、resources/clashctl.yaml、resources/profiles.yaml 移动到 config/，
      或在目标文件已存在且内容相同时删除旧位置文件。
      若目标文件已存在且内容不同，默认拒绝，避免误删。
  --force-remove-legacy-config
      配合 --move-legacy-config 使用。目标 config 文件已存在且和旧 resources 文件不同时，
      保留 config 文件并删除旧 resources 文件。
  --skip-status
      迁移结束后不执行 clashstatus --all。

如果传入 --restart-mode，则迁移完成后执行：
  source <install_dir>/scripts/cmd/clashctl.sh
  clashrestart --mode <mode>

代理链路可能抖动时，建议先不传 --restart-mode；确认迁移完成后再手动执行 clashstatus --all 和 clashrestart。
EOF
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
        source_dir=${1#--source=}
        ;;
    --source)
        shift
        [ $# -gt 0 ] || _die "--source 需要指定源码目录"
        source_dir=$1
        ;;
    --restart-mode=*)
        restart_mode=${1#--restart-mode=}
        ;;
    --restart-mode)
        shift
        [ $# -gt 0 ] || _die "--restart-mode 需要指定 tmux、nohup 或 systemd"
        restart_mode=$1
        ;;
    --skip-status)
        status_check=false
        ;;
    --move-legacy-config)
        move_legacy_config=true
        ;;
    --force-remove-legacy-config)
        force_remove_legacy_config=true
        ;;
    -h | --help)
        _print_help
        exit 0
        ;;
    *)
        _die "未知参数：$1"
        ;;
    esac
    shift
done

[ "${CLASHCTL_MIGRATE_SKIP_STATUS:-0}" = 1 ] && status_check=false
_validate_mode "$restart_mode"
[ "$force_remove_legacy_config" = false ] || [ "$move_legacy_config" = true ] ||
    _die "--force-remove-legacy-config 需要配合 --move-legacy-config 使用"

_load_path_env_lib

[ -n "$source_dir" ] || source_dir=$THIS_MIGRATE_DIR
source_dir=$(_canonical_dir "$source_dir") || _die "源码目录不存在：$source_dir"
[ -f "$source_dir/update.sh" ] || _die "源码目录缺少 update.sh：$source_dir"

if [ -z "$target" ]; then
    target=$(_find_target_from_env 2>/dev/null || true)
    [ -n "$target" ] || target="$HOME/clashctl"
fi
target=$(_canonical_dir "$target") || _die "安装目录不存在：$target"

[ -f "$target/scripts/cmd/clashctl.sh" ] || _die "目标目录缺少 clashctl 脚本：$target"
[ -d "$target/resources" ] || _die "目标目录缺少 resources：$target"

_legacy_config_plan=()

_precheck_legacy_config_file() {
    local src=$1 dest=$2 dest_parent
    dest_parent=$(dirname "$dest")

    [ -e "$src" ] || [ -L "$src" ] || return 0
    [ ! -L "$src" ] || _die "拒绝迁移符号链接旧配置：$src"
    [ -f "$src" ] || _die "旧配置不是普通文件：$src"
    [ ! -L "$dest_parent" ] || _die "配置目录不能是符号链接：$dest_parent"
    [ ! -e "$dest_parent" ] || [ -d "$dest_parent" ] || _die "配置父路径不是目录：$dest_parent"
    [ ! -L "$dest" ] || _die "拒绝覆盖符号链接配置：$dest"

    if [ -e "$dest" ]; then
        [ -f "$dest" ] || _die "目标配置不是普通文件：$dest"
        if ! cmp -s "$src" "$dest"; then
            if [ "$move_legacy_config" = true ] && [ "$force_remove_legacy_config" = true ]; then
                _legacy_config_plan+=("remove|$src|$dest")
                return 0
            fi
            _die "旧配置与新版 config 配置内容不同，拒绝半迁移：$src -> $dest；请先手工 diff，或确认以 config/ 为准后使用 --move-legacy-config --force-remove-legacy-config"
        fi
        if [ "$move_legacy_config" = true ]; then
            _legacy_config_plan+=("remove|$src|$dest")
        else
            _legacy_config_plan+=("keep|$src|$dest")
        fi
        return 0
    fi

    if [ "$move_legacy_config" = true ]; then
        _legacy_config_plan+=("move|$src|$dest")
    else
        _legacy_config_plan+=("copy|$src|$dest")
    fi
}

[ ! -L "$target/config" ] || _die "配置目录不能是符号链接：$target/config"
[ ! -e "$target/config" ] || [ -d "$target/config" ] || _die "配置路径不是目录：$target/config"

_precheck_legacy_config_file "$target/resources/mixin.yaml" "$target/config/mixin.yaml"
_precheck_legacy_config_file "$target/resources/clashctl.yaml" "$target/config/clashctl.yaml"
_precheck_legacy_config_file "$target/resources/profiles.yaml" "$target/config/subscriptions.yaml"

printf '⏳ 正在迁移安装目录：%s\n' "$target"
bash "$source_dir/update.sh" --target "$target" --source "$source_dir"

mkdir -p "$target/config"

config_backup_dir=$(mktemp -d "$target/.migrate-config-backup.XXXXXX")
config_migration_started=false
_rollback_legacy_config_files() {
    local status=$? plan action src dest rel file
    if [ "$config_migration_started" = true ]; then
        for plan in "${_legacy_config_plan[@]}"; do
            IFS='|' read -r action src dest <<<"$plan"
            /usr/bin/rm -f "$src" "$dest"
        done
        while IFS= read -r file; do
            rel=${file#"$config_backup_dir"/}
            /usr/bin/rm -rf "$target/$rel"
            mkdir -p "$target/$(dirname "$rel")"
            cp -a "$file" "$target/$rel"
        done < <(find "$config_backup_dir" -type f)
    fi
    /usr/bin/rm -rf "$config_backup_dir"
    return "$status"
}
trap _rollback_legacy_config_files EXIT INT TERM

for plan in "${_legacy_config_plan[@]}"; do
    IFS='|' read -r action src dest <<<"$plan"
    [ -e "$src" ] || [ -L "$src" ] || continue
    for path in "$src" "$dest"; do
        [ -e "$path" ] || continue
        rel=${path#"$target"/}
        mkdir -p "$config_backup_dir/$(dirname "$rel")"
        cp -a "$path" "$config_backup_dir/$rel"
    done

    config_migration_started=true
    mkdir -p "$(dirname "$dest")"
    case "$action" in
    copy)
        cp -a "$src" "$dest"
        ;;
    move)
        mv "$src" "$dest"
        ;;
    remove)
        rm -f "$src"
        ;;
    keep)
        ;;
    esac
done
config_migration_started=false
/usr/bin/rm -rf "$config_backup_dir"
trap - EXIT INT TERM

if [ -n "$restart_mode" ]; then
    # shellcheck disable=SC1091
    . "$target/scripts/cmd/clashctl.sh"
    clashrestart --mode "$restart_mode"
elif [ "$status_check" = true ]; then
    # shellcheck disable=SC1091
    . "$target/scripts/cmd/clashctl.sh"
    clashstatus --all || true
fi

cat <<EOF
✨ 迁移完成：$target

下一步建议：
  source "$target/scripts/cmd/clashctl.sh"
  clashstatus --all
  clashrestart

如果当前代理连接承载着远程会话，建议先只执行前两条，确认后再重启。
EOF
