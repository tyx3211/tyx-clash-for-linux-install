#!/usr/bin/env bash
# shellcheck disable=SC2034
_clashctl_source_env() {
    local env_file
    env_file="$(dirname "$(dirname "$THIS_SCRIPT_DIR")")/.env"

    local kernel_name_set=${KERNEL_NAME+x} kernel_name_value=${KERNEL_NAME-}
    local base_dir_set=${CLASH_BASE_DIR+x} base_dir_value=${CLASH_BASE_DIR-}
    local config_url_set=${CLASH_CONFIG_URL+x} config_url_value=${CLASH_CONFIG_URL-}
    local init_type_set=${INIT_TYPE+x} init_type_value=${INIT_TYPE-}
    local installed_init_set=${CLASH_INSTALLED_INIT_TYPE+x} installed_init_value=${CLASH_INSTALLED_INIT_TYPE-}

    [ -r "$env_file" ] || {
        printf 'clashctl: missing required env file: %s\n' "$env_file" >&2
        return 1
    }
    . "$env_file" || {
        printf 'clashctl: failed to source env file: %s\n' "$env_file" >&2
        return 1
    }

    [ "$kernel_name_set" = x ] && KERNEL_NAME=$kernel_name_value
    [ "$base_dir_set" = x ] && CLASH_BASE_DIR=$base_dir_value
    [ "$config_url_set" = x ] && CLASH_CONFIG_URL=$config_url_value
    [ "$init_type_set" = x ] && INIT_TYPE=$init_type_value
    [ "$installed_init_set" = x ] && CLASH_INSTALLED_INIT_TYPE=$installed_init_value
    return 0
}

_clashctl_source_env || { return 1 2>/dev/null || exit 1; }

CLASH_RESOURCES_DIR="${CLASH_BASE_DIR}/resources"
CLASH_CONFIG_BASE="${CLASH_RESOURCES_DIR}/config.yaml"
CLASH_CONFIG_MIXIN="${CLASH_RESOURCES_DIR}/mixin.yaml"
CLASH_CONFIG_SIDECAR="${CLASH_RESOURCES_DIR}/clashctl.yaml"
CLASH_CONFIG_RUNTIME="${CLASH_RESOURCES_DIR}/runtime.yaml"
CLASH_CONFIG_TEMP="${CLASH_RESOURCES_DIR}/temp.yaml"
CLASH_SERVICE_STATE="${CLASH_RESOURCES_DIR}/service-state.yaml"

BIN_BASE_DIR="${CLASH_BASE_DIR}/bin"
BIN_KERNEL="${BIN_BASE_DIR}/$KERNEL_NAME"
BIN_YQ="${BIN_BASE_DIR}/yq"
BIN_SUBCONVERTER_DIR="${BIN_BASE_DIR}/subconverter"
BIN_SUBCONVERTER="${BIN_SUBCONVERTER_DIR}/subconverter"
BIN_SUBCONVERTER_START="$BIN_SUBCONVERTER"
BIN_SUBCONVERTER_CONFIG="$BIN_SUBCONVERTER_DIR/pref.yml"
BIN_SUBCONVERTER_LOG="${BIN_SUBCONVERTER_DIR}/latest.log"
BIN_SUBCONVERTER_PID="${BIN_SUBCONVERTER_DIR}/subconverter.pid"

CLASH_PROFILES_DIR="${CLASH_RESOURCES_DIR}/profiles"
CLASH_PROFILES_META="${CLASH_RESOURCES_DIR}/profiles.yaml"
CLASH_PROFILES_LOG="${CLASH_RESOURCES_DIR}/profiles.log"
INSTALL_MARKER="${CLASH_BASE_DIR}/.clashctl-install-root"
CLASHCTL_CRON_TAG="# clashctl-auto-update"

_is_port_used() {
    local port=$1
    { ss -tunl 2>/dev/null || netstat -tunl; } | grep -qs ":${port}\b"
}

_get_random_port() {
    local fail_count=0
    local randomPort

    while [ "$fail_count" -lt 100 ]; do
        randomPort=$(shuf -i 1024-65535 -n 1)
        ! _is_port_used "$randomPort" && {
            echo "$randomPort"
            return 0
        }
        fail_count=$((fail_count + 1))
    done

    _failcat "未找到可用的代理端口"
    return 1
}

_get_bind_addr() {
    local allowLan bindAddr
    bindAddr=$("$BIN_YQ" '.bind-address // "*"' "$CLASH_CONFIG_RUNTIME")
    allowLan=$("$BIN_YQ" '.allow-lan // false' "$CLASH_CONFIG_RUNTIME")

    case $allowLan in
    true)
        [ "$bindAddr" = "*" ] && bindAddr=$(_get_local_ip)
        ;;
    false)
        bindAddr=127.0.0.1
        ;;
    esac
    echo "$bindAddr"
}

_get_local_ip() {
    local local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    [ -z "$local_ip" ] && local_ip=$(hostname -I | awk '{print $1}')
    echo "$local_ip"
}

function _detect_ext_addr() {
    local ext_addr=$("$BIN_YQ" '.external-controller // ""' "$CLASH_CONFIG_RUNTIME")
    local ext_ip=${ext_addr%%:*}
    EXT_IP=$ext_ip
    EXT_PORT=${ext_addr##*:}
    [ "$ext_ip" = '0.0.0.0' ] && EXT_IP=$(_get_local_ip)
    _is_port_used "$EXT_PORT" && {
        local secret="$(_get_secret)"
        local auth_args=()
        [ -n "$secret" ] && auth_args=(-H "Authorization: Bearer $secret")
        curl --silent --fail --noproxy "*" "${auth_args[@]}" "127.0.0.1:${EXT_PORT}/version" >/dev/null && return 0
        local newPort
        newPort=$(_get_random_port) || return 1
        _failcat '🎯' "端口冲突：[external-controller] ${EXT_PORT} 🎲 随机分配 $newPort"
        EXT_PORT=$newPort
        "$BIN_YQ" -i ".external-controller = \"$ext_ip:$newPort\"" "$CLASH_CONFIG_MIXIN"
        _merge_config
    }
}

_color_log() {
    local color="$1"
    local msg="$2"

    local hex="${color#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))

    local color_code="\033[38;2;${r};${g};${b}m"
    local reset_code="\033[0m"

    printf "%b%s%b\n" "$color_code" "$msg" "$reset_code"
}

function _okcat() {
    local color=#c8d6e5
    local emoji=😼
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _color_log "$color" "$msg"
    return 0
}

function _failcat() {
    local color=#fd79a8
    local emoji=😾
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _color_log "$color" "$msg" >&2
    return 1
}

function _error_quit() {
    [ $# -gt 0 ] && {
        local color=#f92f60
        local emoji=📢
        [ $# -gt 1 ] && emoji=$1 && shift
        local msg="${emoji} $1"
        _color_log "$color" "$msg"
    }
    [ -n "${CLASHCTL_ERROR_EXIT:-}" ] && exit 1
    exec "${SHELL:-/bin/sh}" -i
}

function _valid_config() {
    local config="$1"
    [[ ! -e "$config" || "$(wc -l <"$config")" -lt 1 ]] && return 1

    local test_cmd test_log
    test_cmd=("$BIN_KERNEL" -d "$(dirname "$config")" -f "$config" -t)
    test_log=$("${test_cmd[@]}") || {
        "${test_cmd[@]}"
        grep -qs "unsupport proxy type" <<<"$test_log" && {
            local prefix="检测到订阅中包含不受支持的代理协议"
            [ "$KERNEL_NAME" = "clash" ] && _error_quit "${prefix}, 推荐安装使用 mihomo 内核"
            _error_quit "${prefix}, 请检查并升级内核版本"
        }
    }
}

function _download_config() {
    local dest=$1
    local url=$2
    [ "${url:0:4}" = 'file' ] || _okcat '⏳' '正在下载...'
    _download_raw_config "$dest" "$url" || return 1

    _normalize_sub_config "$dest" || return 1

    _is_html_response "$dest" && {
        _failcat "订阅响应疑似 HTML 页面，请检查订阅链接或 User-Agent"
        return 1
    }

    _is_native_yaml_config "$dest" && {
        _okcat '🍃' '检测到原生 Clash/Mihomo 配置'
        _valid_config "$dest" && _valid_sub_nodes "$dest" && return
        _failcat '🍂' "原生配置验证失败：尝试订阅转换..."
        cat "$dest" >"${dest}.raw"
        _download_convert_config "$dest" "$url" || return
        _validate_downloaded_config "$dest"
        return
    }

    _okcat '🍃' '验证订阅配置...'
    _valid_config "$dest" && _valid_sub_nodes "$dest" && return

    _failcat '🍂' "验证失败：尝试订阅转换..."
    cat "$dest" >"${dest}.raw"
    _download_convert_config "$dest" "$url" || return
    _validate_downloaded_config "$dest"
}

_normalize_sub_config() {
    local dest=$1

    [ -s "$dest" ] || {
        _failcat "订阅响应为空，请检查订阅链接"
        return 1
    }

    LC_ALL=C sed -i '1s/^\xEF\xBB\xBF//' "$dest" 2>/dev/null || true
    sed -i 's/\r$//' "$dest" 2>/dev/null || true

    command -v iconv >/dev/null || return 0
    iconv -f UTF-8 -t UTF-8 "$dest" >/dev/null 2>&1 && return 0

    local charset
    for charset in GB18030 GBK BIG5; do
        iconv -f "$charset" -t UTF-8 "$dest" -o "${dest}.utf8" 2>/dev/null && {
            /bin/mv -f "${dest}.utf8" "$dest"
            _okcat '🔤' "订阅已从 $charset 转为 UTF-8"
            return 0
        }
    done

    /usr/bin/rm -f "${dest}.utf8" 2>/dev/null
    return 0
}

_is_html_response() {
    LC_ALL=C grep -qiE '<[[:space:]]*(!doctype|html|head|body|title)([[:space:]>]|$)' "$1"
}

_is_native_yaml_config() {
    "$BIN_YQ" -e '
      ((.proxies // []) | type == "!!seq" and length > 0) or
      ((.proxy-providers // {}) | type == "!!map" and length > 0)
    ' "$1" >/dev/null 2>&1
}

_valid_sub_nodes() {
    local config=$1 count
    count=$("$BIN_YQ" '
      ((.proxies // []) | length) +
      ((.proxy-providers // {}) | length)
    ' "$config" 2>/dev/null) || return 0

    [ "${count:-0}" -gt 0 ] || {
        _failcat "订阅未解析出任何节点，请检查订阅内容或转换器版本"
        return 1
    }
}

_validate_downloaded_config() {
    local dest=$1

    _normalize_sub_config "$dest" || return 1
    _is_html_response "$dest" && {
        _failcat "订阅响应疑似 HTML 页面，请检查订阅链接或 User-Agent"
        return 1
    }
    _valid_sub_nodes "$dest"
}

_download_raw_config() {
    local dest=$1
    local url=$2
    local sub_timeout=${CLASHCTL_SUB_TIMEOUT:-5}

    curl \
        --silent \
        --show-error \
        --fail \
        --insecure \
        --location \
        --max-time "$sub_timeout" \
        --retry 1 \
        --user-agent "$CLASH_SUB_UA" \
        --output "$dest" \
        "$url" ||
        wget \
            --no-verbose \
            --no-check-certificate \
            --timeout "$sub_timeout" \
            --tries 1 \
            --user-agent "$CLASH_SUB_UA" \
            --output-document "$dest" \
            "$url"
}
_download_convert_config() {
    local dest=$1
    local url=$2
    local flag
    local sub_timeout=${CLASHCTL_SUB_TIMEOUT:-5}
    [ "${url:0:4}" = 'file' ] && {
        _download_raw_config "$dest" "$url"
        return $?
    }
    _start_convert || return 1
    local convert_url=$(
        target='clash'
        base_url="http://127.0.0.1:${BIN_SUBCONVERTER_PORT}/sub"
        curl \
            --get \
            --silent \
            --show-error \
            --location \
            --output /dev/null \
            --data-urlencode "target=$target" \
            --data-urlencode "url=$url" \
            --write-out '%{url_effective}' \
            "$base_url"
    )
    curl --user-agent "$CLASH_SUB_UA" --silent --max-time "$sub_timeout" --output "$dest" "$convert_url"
    flag=$?
    _stop_convert
    return $flag
}

_detect_subconverter_port() {
    BIN_SUBCONVERTER_PORT=$("$BIN_YQ" '.server.port' "$BIN_SUBCONVERTER_CONFIG")
    _is_port_used "$BIN_SUBCONVERTER_PORT" && {
        local newPort
        newPort=$(_get_random_port) || return 1
        _failcat '🎯' "端口冲突：[subconverter] ${BIN_SUBCONVERTER_PORT} 🎲 随机分配：$newPort"
        BIN_SUBCONVERTER_PORT=$newPort
        "$BIN_YQ" -i ".server.port = $newPort" "$BIN_SUBCONVERTER_CONFIG" 2>/dev/null
    }
}

_start_convert() {
    _detect_subconverter_port || return 1
    local check_cmd="curl http://localhost:${BIN_SUBCONVERTER_PORT}/version"
    $check_cmd >&/dev/null && return 0
    "$BIN_SUBCONVERTER_START" >&"$BIN_SUBCONVERTER_LOG" &
    echo "$!" >"$BIN_SUBCONVERTER_PID"
    local start=$(date +%s)
    while ! $check_cmd >&/dev/null; do
        sleep 0.5s
        local now=$(date +%s)
        [ $((now - start)) -gt 2 ] && {
            _stop_convert
            _failcat "订阅转换服务未启动，请检查日志：$BIN_SUBCONVERTER_LOG"
            return 1
        }
    done
}
_stop_convert() {
    local pid exe
    pid=$(cat "$BIN_SUBCONVERTER_PID" 2>/dev/null || true)
    [ -n "$pid" ] || return 0

    exe=$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)
    [ "$exe" = "$BIN_SUBCONVERTER" ] || {
        /usr/bin/rm -f "$BIN_SUBCONVERTER_PID"
        return 0
    }

    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.2
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    /usr/bin/rm -f "$BIN_SUBCONVERTER_PID"
    return 0
}

_set_env() {
    local key=$1
    local value=$2
    local env_path="${CLASH_BASE_DIR}/.env"

    grep -qE "^${key}=" "$env_path" && {
        value=${value//&/\\&}
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_path"
        return $?
    }
    echo "${key}=${value}" >>"$env_path"
}
