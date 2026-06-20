#!/usr/bin/env bash
# shellcheck disable=SC2034
_CLASHCTL_INSTALL_STATE_LIB="$THIS_SCRIPT_DIR/../lib/install-state.sh"
[ -r "$_CLASHCTL_INSTALL_STATE_LIB" ] || {
    printf 'clashctl: missing required library: %s\n' "$_CLASHCTL_INSTALL_STATE_LIB" >&2
    return 1 2>/dev/null || exit 1
}
. "$_CLASHCTL_INSTALL_STATE_LIB" || {
    printf 'clashctl: failed to source library: %s\n' "$_CLASHCTL_INSTALL_STATE_LIB" >&2
    return 1 2>/dev/null || exit 1
}
unset _CLASHCTL_INSTALL_STATE_LIB

_clashctl_expand_env_path() {
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

_clashctl_parse_env_file() {
    local env_file=$1 line key value

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
            value=${line#*=}
            ;;
        *)
            continue
            ;;
        esac

        [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        case "$key" in
        KERNEL_NAME | CLASHCTL_KERNEL | CLASH_BASE_DIR | CLASHCTL_HOME | CLASH_CONFIG_URL | INIT_TYPE | CLASH_INSTALLED_INIT_TYPE | CLASHCTL_CONFIG_GIT | CLASHCTL_DOWNLOAD_TIMEOUT | CLASHCTL_SUB_TIMEOUT | CLASH_SUB_UA | CLASHCTL_SUB_UA | ZIP_UI | URL_GH_PROXY | URL_CLASH_UI | VERSION_MIHOMO | VERSION_YQ | VERSION_SUBCONVERTER | SUBCONVERTER_REPO)
            ;;
        *)
            continue
            ;;
        esac
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

        case "$key" in
        CLASHCTL_KERNEL)
            key=KERNEL_NAME
            ;;
        CLASHCTL_HOME)
            key=CLASH_BASE_DIR
            ;;
        CLASHCTL_SUB_UA)
            key=CLASH_SUB_UA
            ;;
        esac

        [ "$key" = CLASH_BASE_DIR ] && value=$(_clashctl_expand_env_path "$value")
        printf -v "$key" '%s' "$value"
    done <"$env_file"
}

_clashctl_source_env() {
    local install_root env_file state_file has_env=false has_state=false
    local install_root_real state_root_real
    install_root="$(dirname "$(dirname "$THIS_SCRIPT_DIR")")"
    env_file="$install_root/.env"
    state_file="$install_root/resources/install-state.yaml"

    local kernel_name_set=${KERNEL_NAME+x} kernel_name_value=${KERNEL_NAME-}
    local base_dir_set=${CLASH_BASE_DIR+x} base_dir_value=${CLASH_BASE_DIR-}
    local config_url_set=${CLASH_CONFIG_URL+x} config_url_value=${CLASH_CONFIG_URL-}
    local init_type_set=${INIT_TYPE+x} init_type_value=${INIT_TYPE-}
    local installed_init_set=${CLASH_INSTALLED_INIT_TYPE+x} installed_init_value=${CLASH_INSTALLED_INIT_TYPE-}
    local config_git_set=${CLASHCTL_CONFIG_GIT+x} config_git_value=${CLASHCTL_CONFIG_GIT-}
    local download_timeout_set=${CLASHCTL_DOWNLOAD_TIMEOUT+x} download_timeout_value=${CLASHCTL_DOWNLOAD_TIMEOUT-}
    local sub_timeout_set=${CLASHCTL_SUB_TIMEOUT+x} sub_timeout_value=${CLASHCTL_SUB_TIMEOUT-}
    local sub_ua_set=${CLASH_SUB_UA+x} sub_ua_value=${CLASH_SUB_UA-}
    local zip_ui_set=${ZIP_UI+x} zip_ui_value=${ZIP_UI-}
    local gh_proxy_set=${URL_GH_PROXY+x} gh_proxy_value=${URL_GH_PROXY-}
    local clash_ui_set=${URL_CLASH_UI+x} clash_ui_value=${URL_CLASH_UI-}
    local version_mihomo_set=${VERSION_MIHOMO+x} version_mihomo_value=${VERSION_MIHOMO-}
    local version_yq_set=${VERSION_YQ+x} version_yq_value=${VERSION_YQ-}
    local version_subconverter_set=${VERSION_SUBCONVERTER+x} version_subconverter_value=${VERSION_SUBCONVERTER-}
    local subconverter_repo_set=${SUBCONVERTER_REPO+x} subconverter_repo_value=${SUBCONVERTER_REPO-}

    if [ -r "$env_file" ]; then
        has_env=true
        _clashctl_parse_env_file "$env_file" || {
            printf 'clashctl: failed to parse env file: %s\n' "$env_file" >&2
            return 1
        }
    fi

    if [ -r "$state_file" ]; then
        has_state=true
        _install_state_read_into_vars "$state_file" || {
            printf 'clashctl: failed to parse install state file: %s\n' "$state_file" >&2
            return 1
        }
        install_root_real=$(cd "$install_root" 2>/dev/null && pwd -P) || {
            printf 'clashctl: failed to resolve install root: %s\n' "$install_root" >&2
            return 1
        }
        state_root_real=$(cd "$CLASH_BASE_DIR" 2>/dev/null && pwd -P) || {
            printf 'clashctl: failed to resolve install-state.yaml install_dir: %s\n' "$CLASH_BASE_DIR" >&2
            return 1
        }
        [ "$install_root_real" = "$state_root_real" ] || {
            printf 'clashctl: install-state.yaml install_dir mismatch: %s != %s\n' "$state_root_real" "$install_root_real" >&2
            return 1
        }
    fi

    [ "$has_env" = true ] || [ "$has_state" = true ] || {
        printf 'clashctl: missing required install state or env file: %s or %s\n' "$state_file" "$env_file" >&2
        return 1
    }

    if [ "$has_state" != true ]; then
        [ "$kernel_name_set" = x ] && KERNEL_NAME=$kernel_name_value
        [ "$base_dir_set" = x ] && CLASH_BASE_DIR=$base_dir_value
        [ "$init_type_set" = x ] && INIT_TYPE=$init_type_value
        [ "$installed_init_set" = x ] && CLASH_INSTALLED_INIT_TYPE=$installed_init_value
    fi
    [ "$config_url_set" = x ] && CLASH_CONFIG_URL=$config_url_value
    [ "$config_git_set" = x ] && CLASHCTL_CONFIG_GIT=$config_git_value
    [ "$download_timeout_set" = x ] && CLASHCTL_DOWNLOAD_TIMEOUT=$download_timeout_value
    [ "$sub_timeout_set" = x ] && CLASHCTL_SUB_TIMEOUT=$sub_timeout_value
    [ "$sub_ua_set" = x ] && CLASH_SUB_UA=$sub_ua_value
    [ "$zip_ui_set" = x ] && ZIP_UI=$zip_ui_value
    [ "$gh_proxy_set" = x ] && URL_GH_PROXY=$gh_proxy_value
    [ "$clash_ui_set" = x ] && URL_CLASH_UI=$clash_ui_value
    [ "$version_mihomo_set" = x ] && VERSION_MIHOMO=$version_mihomo_value
    [ "$version_yq_set" = x ] && VERSION_YQ=$version_yq_value
    [ "$version_subconverter_set" = x ] && VERSION_SUBCONVERTER=$version_subconverter_value
    [ "$subconverter_repo_set" = x ] && SUBCONVERTER_REPO=$subconverter_repo_value
    _install_state_validate_kernel_name "$KERNEL_NAME" || {
        printf 'clashctl: invalid kernel name in install metadata: %s\n' "$KERNEL_NAME" >&2
        return 1
    }
    return 0
}

_clashctl_source_env || { return 1 2>/dev/null || exit 1; }

_clashctl_first_existing_path() {
    local preferred=$1 legacy=$2

    [ -e "$preferred" ] && {
        printf '%s\n' "$preferred"
        return 0
    }
    [ -e "$legacy" ] && {
        printf '%s\n' "$legacy"
        return 0
    }
    printf '%s\n' "$preferred"
}

CLASH_RESOURCES_DIR="${CLASH_BASE_DIR}/resources"
CLASH_CONFIG_DIR="${CLASH_BASE_DIR}/config"
CLASH_INSTALL_STATE="${CLASH_RESOURCES_DIR}/install-state.yaml"
CLASH_CONFIG_BASE="${CLASH_RESOURCES_DIR}/config.yaml"
CLASH_CONFIG_MIXIN=$(_clashctl_first_existing_path "${CLASH_CONFIG_DIR}/mixin.yaml" "${CLASH_RESOURCES_DIR}/mixin.yaml")
CLASH_CONFIG_SIDECAR=$(_clashctl_first_existing_path "${CLASH_CONFIG_DIR}/clashctl.yaml" "${CLASH_RESOURCES_DIR}/clashctl.yaml")
CLASH_CONFIG_RUNTIME="${CLASH_RESOURCES_DIR}/runtime.yaml"
CLASH_CONFIG_TEMP="${CLASH_RESOURCES_DIR}/temp.yaml"
CLASH_SERVICE_STATE="${CLASH_RESOURCES_DIR}/service-state.yaml"
FILE_LOG="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.log"
FILE_PID="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.pid"

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
CLASH_PROFILES_META=$(_clashctl_first_existing_path "${CLASH_CONFIG_DIR}/subscriptions.yaml" "${CLASH_RESOURCES_DIR}/profiles.yaml")
CLASH_PROFILES_LOG="${CLASH_RESOURCES_DIR}/profiles.log"
INSTALL_MARKER="${CLASH_BASE_DIR}/.clashctl-install-root"
CLASHCTL_CRON_TAG="# clashctl-auto-update"

_clashctl_validate_runtime_paths() {
    local name value
    for name in CLASH_BASE_DIR CLASH_RESOURCES_DIR CLASH_CONFIG_RUNTIME CLASH_CONFIG_MIXIN FILE_LOG FILE_PID BIN_KERNEL BIN_YQ; do
        value=${!name-}
        [ -n "$value" ] || {
            printf 'clashctl: critical runtime variable is empty: %s\n' "$name" >&2
            return 1
        }
    done

    case "$CLASH_BASE_DIR" in
    /*)
        [ "$CLASH_BASE_DIR" != "/" ] || {
            printf 'clashctl: CLASH_BASE_DIR must not be / \n' >&2
            return 1
        }
        ;;
    *)
        printf 'clashctl: CLASH_BASE_DIR must be an absolute path: %s\n' "$CLASH_BASE_DIR" >&2
        return 1
        ;;
    esac
}

_clashctl_validate_runtime_paths || { return 1 2>/dev/null || exit 1; }

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

_format_http_url() {
    local host=$1 port=$2 path=${3:-}

    case "$host" in
    *:*)
        case "$host" in
        \[*\])
            ;;
        *)
            host="[$host]"
            ;;
        esac
        ;;
    esac
    printf 'http://%s:%s%s\n' "$host" "$port" "$path"
}

function _detect_ext_addr() {
    local ext_addr ext_ip
    ext_addr=$("$BIN_YQ" '.external-controller // ""' "$CLASH_CONFIG_RUNTIME") || {
        _failcat "external-controller 读取失败：$CLASH_CONFIG_RUNTIME"
        return 1
    }
    case "$ext_addr" in
    "")
        ext_ip=127.0.0.1
        EXT_PORT=9090
        ;;
    *:*)
        ext_ip=${ext_addr%:*}
        EXT_PORT=${ext_addr##*:}
        ;;
    *)
        if [[ $ext_addr =~ ^[0-9]+$ ]]; then
            ext_ip=127.0.0.1
            EXT_PORT=$ext_addr
        else
            ext_ip=$ext_addr
            EXT_PORT=9090
        fi
        ;;
    esac

    [[ $EXT_PORT =~ ^[0-9]+$ ]] || {
        _failcat "external-controller 端口无效：${EXT_PORT:-<empty>}（来自 $CLASH_CONFIG_RUNTIME）"
        return 1
    }

    EXT_CONFIG_HOST=$ext_ip
    [ -n "$EXT_CONFIG_HOST" ] || EXT_CONFIG_HOST=127.0.0.1
    case "$ext_ip" in
    "" | localhost)
        ext_ip=127.0.0.1
        ;;
    esac

    case "$ext_ip" in
    0.0.0.0 | "*")
        EXT_IP=$(_get_local_ip)
        EXT_API_HOST=127.0.0.1
        ;;
    *)
        EXT_IP=$ext_ip
        EXT_API_HOST=$ext_ip
        ;;
    esac
    [ -n "$EXT_API_HOST" ] || EXT_API_HOST=127.0.0.1
    return 0
}

_ext_api_url() {
    local path=${1:-}
    _format_http_url "${EXT_API_HOST:-${EXT_IP:-127.0.0.1}}" "$EXT_PORT" "$path"
}

_ensure_ext_addr_available() {
    local allowed_occupied_port=${1:-}

    _detect_ext_addr || return 1

    _is_port_used "$EXT_PORT" && {
        [ -n "$allowed_occupied_port" ] && [ "$EXT_PORT" = "$allowed_occupied_port" ] && return 0
        local newPort
        newPort=$(_get_random_port) || return 1
        _failcat '🎯' "端口冲突：[external-controller] ${EXT_PORT} 已被其他进程占用，建议改 mixin.yaml 中的 external-controller 为 ${EXT_CONFIG_HOST}:$newPort 后执行 clashmixin -m"
        return 1
    }
    return 0
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
