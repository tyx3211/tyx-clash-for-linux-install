#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
RUNTIME_CONFIG_SH="$TEST_ROOT/scripts/lib/runtime-config.sh"
[ -f "$RUNTIME_CONFIG_SH" ] || fail "runtime-config helper should exist"

runtime_config_tmp=$(make_test_tmpdir "clash-runtime-config")

write_runtime_proxy_yq() {
    local yq_path=$1

    cat >"$yq_path" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.mixed-port // ""')
    printf '\n'
    ;;
'.port // ""')
    printf '25329\n'
    ;;
'.socks-port // ""')
    printf '25330\n'
    ;;
'.authentication[0] // ""')
    printf '\n'
    ;;
'.bind-address // "*"')
    printf '127.0.0.1\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$yq_path"
}

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-defaults"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    DEFAULT_HTTP_PORT=7890
    DEFAULT_SOCKS_PORT=7891
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.mixed-port // ""' | '.port // ""' | '.socks-port // ""')
    printf '\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"

    IFS='|' read -r mixed_port http_port socks_port <<<"$(_runtime_config_read_ports "$CLASH_CONFIG_RUNTIME")"
    [ -z "$mixed_port" ] ||
        fail "runtime-config should keep missing mixed-port empty"
    [ "$http_port" = 7890 ] ||
        fail "runtime-config should use DEFAULT_HTTP_PORT when all proxy ports are missing"
    [ "$socks_port" = 7891 ] ||
        fail "runtime-config should use DEFAULT_SOCKS_PORT when all proxy ports are missing"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-mixed"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    DEFAULT_HTTP_PORT=7890
    DEFAULT_SOCKS_PORT=7891
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.mixed-port // ""')
    printf '17890\n'
    ;;
'.port // ""' | '.socks-port // ""')
    printf '\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"

    [ "$(_runtime_config_http_port "$CLASH_CONFIG_RUNTIME")" = 17890 ] ||
        fail "runtime-config should use mixed-port as the effective HTTP proxy port"
    [ "$(_runtime_config_socks_port "$CLASH_CONFIG_RUNTIME")" = 17890 ] ||
        fail "runtime-config should use mixed-port as the effective SOCKS proxy port"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-fail"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    _failcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/fail.log"; }

    _runtime_config_read_ports "$CLASH_CONFIG_RUNTIME" >/dev/null
    status=$?
    [ "$status" -ne 0 ] ||
        fail "runtime-config should fail when yq cannot read proxy ports"
    grep -q 'mixed-port 读取失败' "$runtime_config_tmp/fail.log" ||
        fail "runtime-config should report the failed runtime.yaml field"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-proxy-fail"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    CLASH_CONFIG_SIDECAR="$runtime_config_tmp/clashctl.yaml"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    _failcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/proxy-fail.log"; }

    clashproxy on
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashproxy on should fail when runtime proxy ports cannot be read"
    [ -z "${http_proxy+x}" ] && [ -z "${HTTP_PROXY+x}" ] &&
        [ -z "${all_proxy+x}" ] && [ -z "${ALL_PROXY+x}" ] ||
        fail "clashproxy on should not export proxy variables after runtime port read failures"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-proxy-global-fail"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    CLASH_CONFIG_SIDECAR="$runtime_config_tmp/global-clashctl.yaml"
    cat >"$BIN_YQ" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-i" ]; then
    printf 'yq-write\n' >>"$runtime_config_tmp/global-calls"
    exit 0
fi
exit 7
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    _failcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/global-fail.log"; }

    clashproxy on -g
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashproxy on -g should fail when runtime proxy ports cannot be read"
    [ ! -e "$runtime_config_tmp/global-calls" ] ||
        fail "clashproxy on -g should not enable global proxy after current proxy setup fails"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-auth-fail"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.mixed-port // ""')
    printf '\n'
    ;;
'.port // ""')
    printf '7890\n'
    ;;
'.socks-port // ""')
    printf '7891\n'
    ;;
'.authentication[0] // ""')
    exit 7
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    _failcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/auth-fail.log"; }

    clashproxy on
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashproxy on should fail when authentication cannot be read"
    [ -z "${http_proxy+x}" ] && [ -z "${all_proxy+x}" ] ||
        fail "clashproxy on should not export proxy variables after authentication read failures"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-bind-fail"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.mixed-port // ""')
    printf '\n'
    ;;
'.port // ""')
    printf '7890\n'
    ;;
'.socks-port // ""')
    printf '7891\n'
    ;;
'.authentication[0] // ""')
    printf '\n'
    ;;
'.bind-address // "*"')
    exit 7
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    _failcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/bind-fail.log"; }

    clashproxy on
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashproxy on should fail when bind-address cannot be read"
    [ -z "${http_proxy+x}" ] && [ -z "${all_proxy+x}" ] ||
        fail "clashproxy on should not export proxy variables after bind-address read failures"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-auto-refresh-local"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    write_runtime_proxy_yq "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    export http_proxy=http://127.0.0.1:7890
    export HTTP_PROXY=http://127.0.0.1:7890
    export https_proxy=http://127.0.0.1:7890
    export HTTPS_PROXY=http://127.0.0.1:7890
    export all_proxy=socks5h://127.0.0.1:7891
    export ALL_PROXY=socks5h://127.0.0.1:7891

    _set_system_proxy || fail "proxy setup should refresh stale local proxy ports"
    [ "$http_proxy" = "http://127.0.0.1:25329" ] ||
        fail "auto proxy should refresh stale local HTTP proxy port"
    [ "$all_proxy" = "socks5h://127.0.0.1:25330" ] ||
        fail "auto proxy should refresh stale local SOCKS proxy port"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-auto-refresh-existing"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    write_runtime_proxy_yq "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    export http_proxy=http://proxy.internal:8080
    export HTTP_PROXY=http://proxy.internal:8080
    export https_proxy=http://proxy.internal:8080
    export HTTPS_PROXY=http://proxy.internal:8080
    unset all_proxy ALL_PROXY

    _set_system_proxy || fail "proxy setup should refresh existing proxy env from runtime config"
    [ "$http_proxy" = "http://127.0.0.1:25329" ] ||
        fail "auto proxy should replace stale HTTP proxy env with runtime config"
    [ "$all_proxy" = "socks5h://127.0.0.1:25330" ] ||
        fail "auto proxy should replace stale SOCKS proxy env with runtime config"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-auto-no-proxy-only"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    write_runtime_proxy_yq "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY
    export no_proxy=localhost,127.0.0.1,::1
    export NO_PROXY=localhost,127.0.0.1,::1

    _set_system_proxy || fail "proxy setup should treat no_proxy alone as proxy disabled"
    [ "$http_proxy" = "http://127.0.0.1:25329" ] ||
        fail "auto proxy should set HTTP proxy when only no_proxy exists"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-status-mismatch"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    write_runtime_proxy_yq "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    export http_proxy=http://127.0.0.1:7890
    export HTTP_PROXY=http://127.0.0.1:7890
    export https_proxy=http://127.0.0.1:7890
    export HTTPS_PROXY=http://127.0.0.1:7890
    export all_proxy=socks5h://127.0.0.1:7891
    export ALL_PROXY=socks5h://127.0.0.1:7891
    _okcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/status-ok.log"; }
    _failcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/status-warn.log"; }

    clashproxy status
    grep -q '当前终端代理与当前运行配置不一致' "$runtime_config_tmp/status-warn.log" ||
        fail "clashproxy status should warn when current proxy env differs from runtime config"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-status-no-proxy-mismatch"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    write_runtime_proxy_yq "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    export http_proxy=http://127.0.0.1:25329
    export HTTP_PROXY=http://127.0.0.1:25329
    export https_proxy=http://127.0.0.1:25329
    export HTTPS_PROXY=http://127.0.0.1:25329
    export all_proxy=socks5h://127.0.0.1:25330
    export ALL_PROXY=socks5h://127.0.0.1:25330
    export no_proxy=localhost
    export NO_PROXY=localhost
    _okcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/status-no-proxy-ok.log"; }
    _failcat() { printf '%s\n' "$*" >>"$runtime_config_tmp/status-no-proxy-warn.log"; }

    clashproxy status
    grep -q '当前终端代理与当前运行配置不一致' "$runtime_config_tmp/status-no-proxy-warn.log" ||
        fail "clashproxy status should warn when no_proxy differs from runtime config"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-detect-mixed"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.mixed-port // ""')
    printf '17890\n'
    ;;
'.port // ""' | '.socks-port // ""')
    printf '\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    clashstatus() { return 1; }
    _is_port_used() { printf '%s\n' "$1" >>"$runtime_config_tmp/detect-mixed-calls"; return 1; }

    _detect_proxy_port || fail "_detect_proxy_port should accept a free mixed-port"
    [ "$(wc -l <"$runtime_config_tmp/detect-mixed-calls")" -eq 1 ] ||
        fail "_detect_proxy_port should check only mixed-port when port and socks-port are unset"
    grep -qx '17890' "$runtime_config_tmp/detect-mixed-calls" ||
        fail "_detect_proxy_port should check the configured mixed-port"
)

(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$runtime_config_tmp/yq-ext-defaults"
    CLASH_CONFIG_RUNTIME="$runtime_config_tmp/runtime.yaml"
    ext_case=empty
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1:$EXT_CASE" in
'.external-controller // "":empty')
    printf '\n'
    ;;
'.external-controller // "":localhost')
    printf 'localhost:19090\n'
    ;;
'.external-controller // "":wildcard')
    printf '0.0.0.0:19091\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    _get_local_ip() { printf '192.0.2.44\n'; }

    EXT_CASE=empty _detect_ext_addr || fail "_detect_ext_addr should accept missing external-controller"
    [ "$EXT_API_HOST" = 127.0.0.1 ] && [ "$EXT_PORT" = 9090 ] ||
        fail "_detect_ext_addr should default missing external-controller to loopback:9090"

    EXT_CASE=localhost _detect_ext_addr || fail "_detect_ext_addr should accept localhost external-controller"
    [ "$EXT_API_HOST" = 127.0.0.1 ] && [ "$EXT_PORT" = 19090 ] ||
        fail "_detect_ext_addr should normalize localhost to loopback API host"

    EXT_CASE=wildcard _detect_ext_addr || fail "_detect_ext_addr should accept wildcard external-controller"
    [ "$EXT_IP" = 192.0.2.44 ] && [ "$EXT_API_HOST" = 127.0.0.1 ] && [ "$EXT_PORT" = 19091 ] ||
        fail "_detect_ext_addr should expose wildcard externally but probe through loopback"
)

pass "runtime config helper checks"
