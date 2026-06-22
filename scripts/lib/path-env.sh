#!/usr/bin/env bash

_path_env_expand_path() {
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

_path_env_trim() {
    local value=$1

    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s\n' "$value"
}

_path_env_unquote() {
    local value
    value=$(_path_env_trim "$1")

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

_path_env_key_allowed() {
    case "$1" in
    KERNEL_NAME | CLASHCTL_KERNEL | CLASH_BASE_DIR | CLASHCTL_HOME | CLASH_CONFIG_URL | INIT_TYPE | CLASH_INSTALLED_INIT_TYPE | CLASHCTL_CONFIG_GIT | CLASHCTL_DOWNLOAD_TIMEOUT | CLASHCTL_SUB_TIMEOUT | CLASH_SUB_UA | CLASHCTL_SUB_UA | ZIP_UI | URL_GH_PROXY | URL_CLASH_UI | VERSION_MIHOMO | VERSION_YQ | VERSION_SUBCONVERTER | SUBCONVERTER_REPO)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

_path_env_normalize_key() {
    case "$1" in
    CLASHCTL_KERNEL)
        printf '%s\n' KERNEL_NAME
        ;;
    CLASHCTL_HOME)
        printf '%s\n' CLASH_BASE_DIR
        ;;
    CLASHCTL_SUB_UA)
        printf '%s\n' CLASH_SUB_UA
        ;;
    *)
        printf '%s\n' "$1"
        ;;
    esac
}

_path_env_key_is_path() {
    case "$(_path_env_normalize_key "$1")" in
    CLASH_BASE_DIR)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

_path_env_filter_allows() {
    local key=$1 allowed
    shift

    [ "$#" -gt 0 ] || return 0
    for allowed in "$@"; do
        [ "$key" = "$(_path_env_normalize_key "$allowed")" ] && return 0
    done
    return 1
}

_path_env_read_value() {
    local file=$1 key=$2 line current_key value= found=false
    [ -f "$file" ] || return 1
    _path_env_key_allowed "$key" || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
        "" | "#"*)
            continue
            ;;
        export[[:space:]]*)
            line=${line#export}
            line=${line#"${line%%[![:space:]]*}"}
            ;;
        esac

        case "$line" in
        *=*)
            current_key=${line%%=*}
            current_key=$(_path_env_trim "$current_key")
            [ "$current_key" = "$key" ] || continue
            value=${line#*=}
            found=true
            ;;
        esac
    done <"$file"

    [ "$found" = true ] || return 1
    value=$(_path_env_unquote "$value")
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

_path_env_read_value_any() {
    local file=$1 key value
    shift

    for key in "$@"; do
        value=$(_path_env_read_value "$file" "$key" 2>/dev/null || true)
        [ -n "$value" ] || continue
        printf '%s\n' "$value"
        return 0
    done
    return 1
}

_path_env_read_path_value() {
    local file=$1 key=$2 value

    value=$(_path_env_read_value "$file" "$key") || return 1
    _path_env_expand_path "$value"
}

_path_env_read_path_value_any() {
    local file=$1 key value
    shift

    for key in "$@"; do
        value=$(_path_env_read_path_value "$file" "$key" 2>/dev/null || true)
        [ -n "$value" ] || continue
        printf '%s\n' "$value"
        return 0
    done
    return 1
}

_path_env_read_into_vars() {
    local file=$1 line key canonical value
    shift
    [ -r "$file" ] || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
        "" | "#"*)
            continue
            ;;
        export[[:space:]]*)
            line=${line#export}
            line=${line#"${line%%[![:space:]]*}"}
            ;;
        esac

        case "$line" in
        *=*)
            key=${line%%=*}
            key=$(_path_env_trim "$key")
            _path_env_key_allowed "$key" || continue
            canonical=$(_path_env_normalize_key "$key")
            _path_env_filter_allows "$canonical" "$@" || continue
            value=$(_path_env_unquote "${line#*=}")
            _path_env_key_is_path "$canonical" && value=$(_path_env_expand_path "$value")
            printf -v "$canonical" '%s' "$value"
            ;;
        esac
    done <"$file"
}
