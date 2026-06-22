#!/usr/bin/env bash

_runtime_config_yq_value() {
    local file=$1 expr=$2 label=$3 value

    value=$("$BIN_YQ" "$expr" "$file") || {
        _failcat "$label 读取失败：$file"
        return 1
    }
    printf '%s\n' "$value"
}

_runtime_config_read_ports() {
    local file=$1 mixed_port http_port socks_port

    mixed_port=$(_runtime_config_yq_value "$file" '.mixed-port // ""' mixed-port) || return 1
    http_port=$(_runtime_config_yq_value "$file" '.port // ""' port) || return 1
    socks_port=$(_runtime_config_yq_value "$file" '.socks-port // ""' socks-port) || return 1

    if [ -z "$mixed_port" ] && [ -z "$http_port" ] && [ -z "$socks_port" ]; then
        http_port=${DEFAULT_HTTP_PORT:-7890}
        socks_port=${DEFAULT_SOCKS_PORT:-7891}
    fi

    printf '%s|%s|%s\n' "$mixed_port" "$http_port" "$socks_port"
}

_runtime_config_http_port() {
    local ports mixed_port http_port socks_port

    ports=$(_runtime_config_read_ports "$1") || return 1
    IFS='|' read -r mixed_port http_port socks_port <<<"$ports"
    [ -n "$http_port" ] || http_port=$mixed_port
    [ -n "$http_port" ] || http_port=${DEFAULT_HTTP_PORT:-7890}
    printf '%s\n' "$http_port"
}

_runtime_config_socks_port() {
    local ports mixed_port http_port socks_port

    ports=$(_runtime_config_read_ports "$1") || return 1
    IFS='|' read -r mixed_port http_port socks_port <<<"$ports"
    [ -n "$socks_port" ] || socks_port=$mixed_port
    [ -n "$socks_port" ] || socks_port=${DEFAULT_SOCKS_PORT:-7891}
    printf '%s\n' "$socks_port"
}

_runtime_config_controller() {
    _runtime_config_yq_value "$1" '.external-controller // ""' external-controller
}
