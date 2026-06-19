#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
SERVICE_RUNTIME_SH="$TEST_ROOT/scripts/lib/service-runtime.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
FISH_SH="$TEST_ROOT/scripts/cmd/clashctl.fish"

assert_file_contains "$SERVICE_RUNTIME_SH" '_clash_adapter_tmux_start\(\)' \
    "clashctl should keep tmux adapter available at runtime"

assert_file_contains "$SERVICE_RUNTIME_SH" '_clash_adapter_nohup_start\(\)' \
    "clashctl should keep nohup adapter available at runtime"

assert_file_contains "$SERVICE_RUNTIME_SH" '_clash_adapter_systemd_start\(\)' \
    "clashctl should keep systemd adapter available at runtime"

assert_file_contains "$CLASHCTL_SH" 'clashon "\$@"|clashon "\$\{@\}"' \
    "clashctl on should pass runtime mode arguments through"

assert_file_contains "$FISH_SH" 'bash -i -c '\''clashon "\$@"'\'' -- \$argv' \
    "fish clashon wrapper should pass runtime mode arguments through"

assert_file_contains "$FISH_SH" 'clashctl update-self "\$@"|clashctl update-self \$argv' \
    "fish clashctl wrapper should pass update-self through to bash clashctl"

assert_file_not_contains "$PREFLIGHT_SH" 'placeholder_start#_clash_service_start' \
    "install rendering should not hard-wire a single service start function"

tmux_quote_tmp=$(make_test_tmpdir "clash-tmux-quote")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_BASE_DIR="$tmux_quote_tmp/base;touch"
    CLASH_RESOURCES_DIR="$CLASH_BASE_DIR/resources"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    FILE_LOG="$CLASH_RESOURCES_DIR/mihomo.log"
    BIN_KERNEL="$CLASH_BASE_DIR/bin/mihomo"
    KERNEL_NAME=mihomo

    tmux() {
        printf '%s\n' "$*" >"$tmux_quote_tmp/tmux-args"
    }

    _clash_adapter_tmux_start
    grep -q '\\;' "$tmux_quote_tmp/tmux-args" ||
        fail "tmux adapter should shell-quote metacharacters in the command string"
)

mode_tmp=$(make_test_tmpdir "clash-runtime-mode")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_RESOURCES_DIR="$mode_tmp/resources"
    CLASH_SERVICE_STATE="$CLASH_RESOURCES_DIR/service-state.yaml"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    CLASH_CONFIG_MIXIN="$CLASH_RESOURCES_DIR/mixin.yaml"
    FILE_PID="$CLASH_RESOURCES_DIR/mihomo.pid"
    BIN_KERNEL="$mode_tmp/bin/mihomo"
    INIT_TYPE=tmux
    mkdir -p "$CLASH_RESOURCES_DIR" "$mode_tmp/bin"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    printf '{}\n' >"$CLASH_CONFIG_MIXIN"

    _detect_proxy_port() {
        printf 'detect-proxy\n' >>"$mode_tmp/calls"
    }
    _detect_ext_addr() {
        printf 'detect-ext\n' >>"$mode_tmp/calls"
        EXT_IP=127.0.0.1
        EXT_PORT=9090
    }
    _get_secret() { :; }
    _set_system_proxy() { :; }
    _unset_system_proxy() { :; }
    _okcat() { :; }
    _failcat() { printf '%s\n' "$*" >>"$mode_tmp/fail.log"; }
    curl() { return 0; }
    sleep() { :; }

    _clash_adapter_tmux_start() {
        printf 'tmux-start\n' >>"$mode_tmp/calls"
        tmux_active=true
    }
    _clash_adapter_tmux_stop() {
        printf 'tmux-stop\n' >>"$mode_tmp/calls"
        tmux_active=false
    }
    _clash_adapter_tmux_is_active() {
        [ "${tmux_active:-false}" = true ]
    }
    _clash_adapter_nohup_start() {
        printf 'nohup-start\n' >>"$mode_tmp/calls"
        nohup_active=true
        printf 'pid: 4242\nstarttime: 99\n' >"$FILE_PID"
    }
    _clash_adapter_nohup_stop() {
        printf 'nohup-stop\n' >>"$mode_tmp/calls"
        nohup_active=false
    }
    _clash_adapter_nohup_is_active() {
        [ "${nohup_active:-false}" = true ]
    }
    _clash_adapter_systemd_start() { return 1; }
    _clash_adapter_systemd_stop() { return 1; }
    _clash_adapter_systemd_is_active() { return 1; }
    _clash_systemd_registered() { return 1; }

    tmux_active=false
    nohup_active=false
    clashon --mode tmux
    status=$?
    [ "$status" -eq 0 ] || fail "clashon --mode tmux should start tmux adapter"
    grep -qx 'tmux-start' "$mode_tmp/calls" ||
        fail "clashon --mode tmux should call tmux adapter"
    awk '
        $0 == "detect-ext" && !seen_start { seen_detect=NR }
        $0 == "tmux-start" && !seen_start { seen_start=NR }
        END { exit (seen_detect && seen_start && seen_detect < seen_start) ? 0 : 1 }
    ' "$mode_tmp/calls" ||
        fail "clashon should detect external-controller conflicts before starting the adapter"
    grep -q '^active_mode: tmux$' "$CLASH_SERVICE_STATE" ||
        fail "clashon should record active mode"

    clashon --mode nohup
    status=$?
    [ "$status" -ne 0 ] || fail "clashon should reject switching mode while another mode is active"

    clashrestart --mode nohup
    status=$?
    [ "$status" -eq 0 ] || fail "clashrestart --mode nohup should switch from tmux to nohup"
    grep -qx 'tmux-stop' "$mode_tmp/calls" ||
        fail "clashrestart should stop previous active mode"
    grep -qx 'nohup-start' "$mode_tmp/calls" ||
        fail "clashrestart should start target mode"
    grep -q '^active_mode: nohup$' "$CLASH_SERVICE_STATE" ||
        fail "clashrestart should update active mode"
    grep -q '^pid: 4242$' "$CLASH_SERVICE_STATE" ||
        fail "clashrestart should record only the nohup pid in service state"

    clashoff
    status=$?
    [ "$status" -eq 0 ] || fail "clashoff should stop active mode"
    grep -qx 'nohup-stop' "$mode_tmp/calls" ||
        fail "clashoff should stop recorded active mode"
)

restart_ext_tmp=$(make_test_tmpdir "clash-restart-ext")
(
    set +e
    . "$CLASHCTL_SH"

    _has_current_proxy_env() { return 1; }
    _get_active_mode() { return 1; }
    _get_default_service_mode() { printf '%s\n' tmux; }
    _merge_config() { printf 'merge\n' >>"$restart_ext_tmp/calls"; }
    _detect_ext_addr() { printf 'detect-ext\n' >>"$restart_ext_tmp/calls"; }
    _clash_service_stop() { printf 'stop-%s\n' "$1" >>"$restart_ext_tmp/calls"; }
    _clash_service_start() { printf 'start-%s\n' "$1" >>"$restart_ext_tmp/calls"; }
    sleep() { :; }

    _merge_config_restart || fail "_merge_config_restart should succeed with stubbed service operations"
)
awk '
    $0 == "merge" { merge=NR }
    $0 == "detect-ext" { detect=NR }
    $0 == "start-tmux" { start=NR }
    END { exit (merge && detect && start && merge < detect && detect < start) ? 0 : 1 }
' "$restart_ext_tmp/calls" ||
    fail "_merge_config_restart should detect external-controller conflicts before restarting"

no_conflict_tmp=$(make_test_tmpdir "clash-no-conflict-return")
(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$no_conflict_tmp/yq"
    CLASH_CONFIG_RUNTIME="$no_conflict_tmp/runtime.yaml"
    CLASH_CONFIG_MIXIN="$no_conflict_tmp/mixin.yaml"
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
'.external-controller // ""')
    printf '127.0.0.1:9090\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    printf '{}\n' >"$CLASH_CONFIG_MIXIN"
    DEFAULT_HTTP_PORT=7890
    DEFAULT_SOCKS_PORT=7891
    _is_port_used() { return 1; }
    clashstatus() { return 1; }
    _merge_config() { printf 'merge\n' >>"$no_conflict_tmp/calls"; }

    _detect_proxy_port
    proxy_status=$?
    _detect_ext_addr
    ext_status=$?
    [ "$proxy_status" -eq 0 ] ||
        fail "_detect_proxy_port should return success when no configured proxy port conflicts"
    [ "$ext_status" -eq 0 ] ||
        fail "_detect_ext_addr should return success when external-controller port is free"
    [ ! -e "$no_conflict_tmp/calls" ] ||
        fail "no-conflict detection should not merge config"
)

on_ext_fail_tmp=$(make_test_tmpdir "clash-on-ext-fail")
(
    set +e
    . "$CLASHCTL_SH"

    INIT_TYPE=tmux
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$on_ext_fail_tmp/calls"; }
    _detect_ext_addr() { printf 'detect-ext\n' >>"$on_ext_fail_tmp/calls"; return 1; }
    _get_active_mode() { return 1; }
    _clash_service_start() { printf 'start-%s\n' "$1" >>"$on_ext_fail_tmp/calls"; return 0; }
    clashstatus() { return 0; }
    _okcat() { :; }
    _failcat() { printf '%s\n' "$*" >>"$on_ext_fail_tmp/fail.log"; }

    clashon --mode tmux
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashon should fail when external-controller conflict resolution fails"
    ! grep -q '^start-tmux$' "$on_ext_fail_tmp/calls" ||
        fail "clashon should not start an adapter after external-controller detection fails"
)

rollback_tmp=$(make_test_tmpdir "clash-runtime-rollback")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_RESOURCES_DIR="$rollback_tmp/resources"
    CLASH_SERVICE_STATE="$CLASH_RESOURCES_DIR/service-state.yaml"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    BIN_KERNEL="$rollback_tmp/bin/mihomo"
    INIT_TYPE=tmux
    mkdir -p "$CLASH_RESOURCES_DIR" "$rollback_tmp/bin"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"

    _detect_proxy_port() { :; }
    _detect_ext_addr() { :; }
    _okcat() { :; }
    _failcat() { printf '%s\n' "$*" >>"$rollback_tmp/fail.log"; }
    clashstatus() { return 1; }
    sleep() { SECONDS=$((SECONDS + 10)); }

    _clash_adapter_tmux_start() {
        tmux_active=true
    }
    _clash_adapter_tmux_stop() {
        printf 'tmux-stop\n' >>"$rollback_tmp/calls"
        tmux_active=false
    }
    _clash_adapter_tmux_is_active() {
        [ "${tmux_active:-false}" = true ]
    }
    _clash_adapter_nohup_is_active() { return 1; }
    _clash_adapter_systemd_is_active() { return 1; }

    tmux_active=false
    clashon --mode tmux
    status=$?
    [ "$status" -ne 0 ] || fail "clashon should fail when health check never succeeds"
    grep -qx 'tmux-stop' "$rollback_tmp/calls" ||
        fail "clashon should rollback the started adapter after health check failure"
    [ ! -f "$CLASH_SERVICE_STATE" ] ||
        fail "clashon should clear service state after rollback"
)

tun_tmp=$(make_test_tmpdir "clash-runtime-tun")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_RESOURCES_DIR="$tun_tmp/resources"
    CLASH_SERVICE_STATE="$CLASH_RESOURCES_DIR/service-state.yaml"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    CLASH_CONFIG_MIXIN="$CLASH_RESOURCES_DIR/mixin.yaml"
    CLASH_CONFIG_TEMP="$CLASH_RESOURCES_DIR/temp.yaml"
    BIN_YQ="$tun_tmp/yq"
    mkdir -p "$CLASH_RESOURCES_DIR"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    printf '{}\n' >"$CLASH_CONFIG_MIXIN"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN_YQ"
    chmod +x "$BIN_YQ"

    _get_active_mode() { printf '%s\n' tmux; }
    _clash_systemd_registered() { return 0; }
    _failcat() { printf '%s\n' "$*" >>"$tun_tmp/fail.log"; }

    tunon
    status=$?
    [ "$status" -ne 0 ] || fail "tunon should require active systemd mode"
    grep -q 'clashrestart --mode systemd' "$tun_tmp/fail.log" ||
        fail "tunon should tell user to restart with systemd mode"
)

pass "runtime mode checks"
