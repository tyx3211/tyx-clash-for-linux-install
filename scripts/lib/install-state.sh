#!/usr/bin/env bash

_INSTALL_STATE_SELF=${BASH_SOURCE:-${(%):-%N}}
_INSTALL_STATE_LIB_DIR=$(cd "$(dirname "$_INSTALL_STATE_SELF")" && pwd -P) || {
    printf 'install-state: failed to resolve library directory\n' >&2
    return 1 2>/dev/null || exit 1
}
_INSTALL_STATE_PATH_ENV_LIB="$_INSTALL_STATE_LIB_DIR/path-env.sh"
[ -r "$_INSTALL_STATE_PATH_ENV_LIB" ] || {
    printf 'install-state: missing required library: %s\n' "$_INSTALL_STATE_PATH_ENV_LIB" >&2
    return 1 2>/dev/null || exit 1
}
. "$_INSTALL_STATE_PATH_ENV_LIB" || {
    printf 'install-state: failed to source library: %s\n' "$_INSTALL_STATE_PATH_ENV_LIB" >&2
    return 1 2>/dev/null || exit 1
}
unset _INSTALL_STATE_SELF _INSTALL_STATE_LIB_DIR _INSTALL_STATE_PATH_ENV_LIB

_install_state_expand_path() {
    _path_env_expand_path "$1"
}

_install_state_read_env_value() {
    local file=$1 key=$2

    if _path_env_key_is_path "$key"; then
        _path_env_read_path_value "$file" "$key"
    else
        _path_env_read_value "$file" "$key"
    fi
}

_install_state_read_yaml_value() {
    local file=$1 key=$2 yq expr value
    [ -f "$file" ] || return 1

    case "$key" in
    install_dir | kernel_name | default_mode | installed_systemd_service)
        ;;
    *)
        printf 'install-state: unsupported yaml key: %s\n' "$key" >&2
        return 1
        ;;
    esac

    yq=$(_install_state_yq_for_file "$file") || return 1
    case "$key" in
    installed_systemd_service)
        expr='select(has("installed_systemd_service")) | .installed_systemd_service'
        ;;
    *)
        expr=".${key} // \"\""
        ;;
    esac
    value=$("$yq" "$expr" "$file") || {
        printf 'install-state: failed to read %s from %s\n' "$key" "$file" >&2
        return 1
    }
    [ -n "$value" ] || return 1
    [ "$key" = install_dir ] && value=$(_install_state_expand_path "$value")
    printf '%s\n' "$value"
}

_install_state_yq_for_file() {
    local file=$1 install_root yq

    install_root=$(cd "$(dirname "$file")/.." 2>/dev/null && pwd -P) || {
        printf 'install-state: failed to resolve install root for %s\n' "$file" >&2
        return 1
    }
    yq="$install_root/bin/yq"
    [ -x "$yq" ] || {
        printf 'install-state: missing executable yq: %s\n' "$yq" >&2
        return 1
    }
    printf '%s\n' "$yq"
}

_install_state_read_into_vars() {
    local file=$1 value installed_systemd=false
    [ -f "$file" ] || return 1

    value=$(_install_state_read_yaml_value "$file" install_dir) || return 1
    CLASH_BASE_DIR=$value
    value=$(_install_state_read_yaml_value "$file" kernel_name) || return 1
    KERNEL_NAME=$value
    value=$(_install_state_read_yaml_value "$file" default_mode) || return 1
    INIT_TYPE=$value
    value=$(_install_state_read_yaml_value "$file" installed_systemd_service) || return 1
    installed_systemd=$value

    case "$installed_systemd" in
    true | yes | 1 | systemd)
        CLASH_INSTALLED_INIT_TYPE=systemd
        ;;
    false | no | 0 | "")
        CLASH_INSTALLED_INIT_TYPE=${INIT_TYPE:-tmux}
        ;;
    esac
}

_install_state_write() {
    local file=$1 install_dir=$2 kernel_name=$3 default_mode=$4 installed_systemd=$5
    local version_mihomo=${6:-} version_yq=${7:-} version_subconverter=${8:-}
    local dir tmp yq installed_systemd_bool=false

    dir=$(dirname "$file")
    [ ! -L "$dir" ] || return 1
    [ ! -L "$file" ] || return 1
    mkdir -p "$dir" || return 1
    tmp=$(mktemp "${dir}/.install-state.XXXXXX") || return 1
    yq=$(_install_state_yq_for_file "$file") || {
        /usr/bin/rm -f "$tmp"
        return 1
    }

    case "$installed_systemd" in
    true | yes | 1 | systemd)
        installed_systemd_bool=true
        ;;
    esac

    INSTALL_STATE_INSTALL_DIR=$install_dir \
        INSTALL_STATE_KERNEL_NAME=$kernel_name \
        INSTALL_STATE_DEFAULT_MODE=$default_mode \
        INSTALL_STATE_SYSTEMD=$installed_systemd_bool \
        INSTALL_STATE_VERSION_MIHOMO=$version_mihomo \
        INSTALL_STATE_VERSION_YQ=$version_yq \
        INSTALL_STATE_VERSION_SUBCONVERTER=$version_subconverter \
        "$yq" -n '
            .install_dir = strenv(INSTALL_STATE_INSTALL_DIR) |
            .kernel_name = strenv(INSTALL_STATE_KERNEL_NAME) |
            .default_mode = strenv(INSTALL_STATE_DEFAULT_MODE) |
            .installed_systemd_service = (strenv(INSTALL_STATE_SYSTEMD) == "true") |
            .versions.mihomo = strenv(INSTALL_STATE_VERSION_MIHOMO) |
            .versions.yq = strenv(INSTALL_STATE_VERSION_YQ) |
            .versions.subconverter = strenv(INSTALL_STATE_VERSION_SUBCONVERTER)
        ' >"$tmp" || {
        /usr/bin/rm -f "$tmp"
        return 1
    }

    /bin/mv -f "$tmp" "$file"
}

_install_state_validate_kernel_name() {
    case "$1" in
    mihomo | clash)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}
