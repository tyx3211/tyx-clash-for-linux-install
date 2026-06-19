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

    _detect_proxy_port() { :; }
    _detect_ext_addr() {
        EXT_IP=127.0.0.1
        EXT_PORT=23571
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
