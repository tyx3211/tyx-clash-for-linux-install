#!/usr/bin/env bash

_INSTALL_STATE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || {
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
unset _INSTALL_STATE_LIB_DIR _INSTALL_STATE_PATH_ENV_LIB

_install_state_trim() {
    local value=$1

    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s\n' "$value"
}

_install_state_unquote() {
    local value
    value=$(_install_state_trim "$1")

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
    printf '%s\n' "$value"
}

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
    local file=$1 key=$2 line current_key value=
    [ -f "$file" ] || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
        "$key:"*)
            current_key=${line%%:*}
            [ "$current_key" = "$key" ] || continue
            value=${line#*:}
            ;;
        esac
    done <"$file"

    [ -n "$value" ] || return 1
    value=$(_install_state_unquote "$value")
    [ "$key" = install_dir ] && value=$(_install_state_expand_path "$value")
    printf '%s\n' "$value"
}

_install_state_read_into_vars() {
    local file=$1 value installed_systemd=false
    [ -f "$file" ] || return 1

    value=$(_install_state_read_yaml_value "$file" install_dir) && CLASH_BASE_DIR=$value
    value=$(_install_state_read_yaml_value "$file" kernel_name) && KERNEL_NAME=$value
    value=$(_install_state_read_yaml_value "$file" default_mode) && INIT_TYPE=$value
    value=$(_install_state_read_yaml_value "$file" installed_systemd_service) && installed_systemd=$value

    case "$installed_systemd" in
    true | yes | 1 | systemd)
        CLASH_INSTALLED_INIT_TYPE=systemd
        ;;
    false | no | 0 | "")
        CLASH_INSTALLED_INIT_TYPE=${INIT_TYPE:-tmux}
        ;;
    esac
}

_install_state_quote_yaml() {
    local value=$1

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '"%s"' "$value"
}

_install_state_write() {
    local file=$1 install_dir=$2 kernel_name=$3 default_mode=$4 installed_systemd=$5
    local version_mihomo=${6:-} version_yq=${7:-} version_subconverter=${8:-}
    local dir tmp

    dir=$(dirname "$file")
    [ ! -L "$dir" ] || return 1
    [ ! -L "$file" ] || return 1
    mkdir -p "$dir" || return 1
    tmp=$(mktemp "${dir}/.install-state.XXXXXX") || return 1

    {
        printf 'install_dir: %s\n' "$(_install_state_quote_yaml "$install_dir")"
        printf 'kernel_name: %s\n' "$(_install_state_quote_yaml "$kernel_name")"
        printf 'default_mode: %s\n' "$(_install_state_quote_yaml "$default_mode")"
        case "$installed_systemd" in
        true | yes | 1 | systemd)
            printf 'installed_systemd_service: true\n'
            ;;
        *)
            printf 'installed_systemd_service: false\n'
            ;;
        esac
        printf 'versions:\n'
        printf '  mihomo: %s\n' "$(_install_state_quote_yaml "$version_mihomo")"
        printf '  yq: %s\n' "$(_install_state_quote_yaml "$version_yq")"
        printf '  subconverter: %s\n' "$(_install_state_quote_yaml "$version_subconverter")"
    } >"$tmp" || {
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
