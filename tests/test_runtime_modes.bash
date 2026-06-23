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

assert_file_contains "$SERVICE_RUNTIME_SH" '_with_service_lock\(\)' \
    "runtime start/stop/restart operations should share a service lock"

assert_file_contains "$SERVICE_RUNTIME_SH" '/proc/\$pid/comm' \
    "nohup pid validation should handle replaced kernel binaries by falling back to comm and cmdline checks"

assert_file_contains "$CLASHCTL_SH" 'clashon "\$@"|clashon "\$\{@\}"' \
    "clashctl on should pass runtime mode arguments through"

assert_file_contains "$FISH_SH" '_clashctl_bash_call clashon \$argv' \
    "fish clashon wrapper should pass runtime mode arguments through a non-interactive helper"

assert_file_contains "$FISH_SH" '_clashctl_watch_proxy' \
    "fish wrapper should run the automatic proxy refresh hook for interactive shells"

assert_file_contains "$FISH_SH" '_clashctl_import_proxy_env --quiet watch_proxy' \
    "fish wrapper should import watch_proxy results quietly during interactive shell startup"

assert_file_contains "$FISH_SH" 'bash -c "\$bash_snippet" -- "\$CLASHCTL_CMD_DIR" \$argv >\$env_tmp$' \
    "fish explicit proxy commands should surface bash-side error messages"

assert_file_contains "$FISH_SH" 'clashproxy "\$@" >/dev/null$' \
    "fish clashproxy off should suppress duplicate success output"

assert_file_not_contains "$FISH_SH" 'clashproxy "\$@" >/dev/null 2>&1' \
    "fish clashproxy off should not suppress bash-side error messages"

assert_file_not_contains "$FISH_SH" 'bash -i' \
    "fish wrapper should not load interactive bash rc and trigger watch_proxy side effects"

assert_file_not_contains "$FISH_SH" 'bash -c "\\. \\"\\$CLASHCTL_CMD_DIR' \
    "fish wrapper should pass command directory as a bash positional argument instead of interpolating it"

assert_file_contains "$FISH_SH" '_clashctl_bash_call clashctl update-self \$argv' \
    "fish clashctl wrapper should pass update-self through to bash clashctl"

assert_file_not_contains "$PREFLIGHT_SH" 'placeholder_start#_clash_service_start' \
    "install rendering should not hard-wire a single service start function"

source_isolation_tmp=$(make_test_tmpdir "clash-source-isolation")
(
    set +e
    . "$CLASHCTL_SH"

    case "$CLASH_BASE_DIR" in
    "$TEST_RUN_TMP_DIR"/*)
        ;;
    *)
        fail "tests should source clashctl with an isolated CLASH_BASE_DIR, got: $CLASH_BASE_DIR"
        ;;
    esac

    _current_kernel_pids >"$source_isolation_tmp/pids"
    [ ! -s "$source_isolation_tmp/pids" ] ||
        fail "test defaults should not discover real user mihomo processes"
)

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

legacy_tmux_tmp=$(make_test_tmpdir "clash-legacy-tmux")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_BASE_DIR="$legacy_tmux_tmp/install"
    CLASH_RESOURCES_DIR="$CLASH_BASE_DIR/resources"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    BIN_KERNEL="$CLASH_BASE_DIR/bin/mihomo"
    KERNEL_NAME=mihomo
    mkdir -p "$CLASH_RESOURCES_DIR" "$CLASH_BASE_DIR/bin"

    tmux() {
        case "$1" in
        has-session)
            [ "$3" = "clash-mihomo" ] && return 0
            return 1
            ;;
        list-panes)
            [ "$3" = "clash-mihomo" ] && {
                printf '777\n'
                return 0
            }
            return 1
            ;;
        kill-session)
            printf 'kill %s\n' "$3" >>"$legacy_tmux_tmp/calls"
            return 0
            ;;
        *)
            return 1
            ;;
        esac
    }
    _pid_matches_current_kernel() {
        [ "$1" = 777 ]
    }
    sleep() { :; }
    kill() {
        printf 'kill-pid %s %s\n' "$1" "$2" >>"$legacy_tmux_tmp/calls"
    }

    _clash_adapter_tmux_is_active ||
        fail "tmux adapter should detect a legacy clash-mihomo session owned by this install"
    _clash_adapter_tmux_stop ||
        fail "tmux adapter should stop a legacy clash-mihomo session owned by this install"
    grep -qx 'kill clash-mihomo' "$legacy_tmux_tmp/calls" ||
        fail "tmux adapter should kill the matching legacy session during migration cleanup"
    grep -qx 'kill-pid -TERM 777' "$legacy_tmux_tmp/calls" ||
        fail "tmux adapter should terminate current-install kernel pids left behind by a legacy session"
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
    _ensure_ext_addr_available() {
        printf 'ensure-ext\n' >>"$mode_tmp/calls"
        EXT_IP=127.0.0.1
        EXT_PORT=9090
    }
    _get_secret() { :; }
    _set_system_proxy() { :; }
    _unset_system_proxy() { :; }
    _okcat() { :; }
    _failcat() { printf '%s\n' "$*" >>"$mode_tmp/fail.log"; }
    clashstatus() {
        [ "${tmux_active:-false}" = true ] || [ "${nohup_active:-false}" = true ]
    }
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
        $0 == "ensure-ext" && !seen_start { seen_detect=NR }
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

    unset_proxy_called=false
    _unset_system_proxy() {
        unset_proxy_called=true
    }
    clashrestart --mode tmux
    status=$?
    [ "$status" -eq 0 ] || fail "clashrestart should switch modes without using user-facing clashoff side effects"
    [ "$unset_proxy_called" = false ] ||
        fail "clashrestart should not clear current shell proxy variables"

    unset_proxy_called=false
    tmux_stop_count_before=$(grep -c '^tmux-stop$' "$mode_tmp/calls" || true)
    clashoff
    status=$?
    [ "$status" -eq 0 ] || fail "clashoff should stop active mode"
    tmux_stop_count_after=$(grep -c '^tmux-stop$' "$mode_tmp/calls" || true)
    [ "$tmux_stop_count_after" -gt "$tmux_stop_count_before" ] ||
        fail "clashoff should stop recorded active mode"
    [ "$unset_proxy_called" = false ] ||
        fail "clashoff should not clear current shell proxy variables"
)

restart_ext_tmp=$(make_test_tmpdir "clash-restart-ext")
(
    set +e
    . "$CLASHCTL_SH"

    _get_active_mode() { return 1; }
    _get_default_service_mode() { printf '%s\n' tmux; }
    _merge_config() { printf 'merge\n' >>"$restart_ext_tmp/calls"; }
    _ensure_ext_addr_available() { printf 'ensure-ext\n' >>"$restart_ext_tmp/calls"; }
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$restart_ext_tmp/calls"; }
    _clash_service_stop() { printf 'stop-%s\n' "$1" >>"$restart_ext_tmp/calls"; }
    _clash_service_start() { printf 'start-%s\n' "$1" >>"$restart_ext_tmp/calls"; }
    clashstatus() { printf 'status\n' >>"$restart_ext_tmp/calls"; return 0; }
    sleep() { :; }

    _merge_config_restart || fail "_merge_config_restart should succeed with stubbed service operations"
)
awk '
    $0 == "merge" { merge=NR }
    $0 == "ensure-ext" { detect=NR }
    $0 == "detect-proxy" { proxy=NR }
    $0 == "start-tmux" { start=NR }
    END { exit (merge && detect && proxy && start && merge < detect && detect < proxy && proxy < start) ? 0 : 1 }
' "$restart_ext_tmp/calls" ||
    fail "_merge_config_restart should check external-controller and proxy port conflicts before starting"

restart_proxy_env_tmp=$(make_test_tmpdir "clash-restart-proxy-env")
(
    set +e
    . "$CLASHCTL_SH"

    _get_active_mode() { printf '%s\n' tmux; return 0; }
    _detect_ext_addr() { EXT_PORT=23571; }
    _merge_config() { printf 'merge\n' >>"$restart_proxy_env_tmp/calls"; }
    _ensure_ext_addr_available() { printf 'ensure-ext %s\n' "${1:-}" >>"$restart_proxy_env_tmp/calls"; }
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$restart_proxy_env_tmp/calls"; }
    _clash_service_stop() { printf 'stop-%s\n' "$1" >>"$restart_proxy_env_tmp/calls"; }
    _clash_service_start() { printf 'start-%s\n' "$1" >>"$restart_proxy_env_tmp/calls"; }
    _set_system_proxy() { printf 'set-proxy\n' >>"$restart_proxy_env_tmp/calls"; }
    clashstatus() { printf 'status\n' >>"$restart_proxy_env_tmp/calls"; return 0; }
    sleep() { :; }

    _merge_config_restart || fail "_merge_config_restart should succeed with an existing proxy environment"
)
! grep -q '^set-proxy$' "$restart_proxy_env_tmp/calls" ||
    fail "_merge_config_restart should not rewrite current shell proxy variables"

restart_proxy_port_conflict_tmp=$(make_test_tmpdir "clash-restart-proxy-port-conflict")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_RUNTIME="$restart_proxy_port_conflict_tmp/runtime.yaml"
    printf 'old-runtime\n' >"$CLASH_CONFIG_RUNTIME"

    _get_active_mode() { printf '%s\n' tmux; return 0; }
    _detect_ext_addr() { EXT_PORT=23571; }
    _merge_config() {
        printf 'new-runtime\n' >"$CLASH_CONFIG_RUNTIME"
        printf 'merge\n' >>"$restart_proxy_port_conflict_tmp/calls"
    }
    _ensure_ext_addr_available() { printf 'ensure-ext %s\n' "${1:-}" >>"$restart_proxy_port_conflict_tmp/calls"; }
    _clash_service_stop() { printf 'stop-%s\n' "$1" >>"$restart_proxy_port_conflict_tmp/calls"; }
    _clash_service_start() {
        printf 'start-%s:%s\n' "$1" "$(cat "$CLASH_CONFIG_RUNTIME")" >>"$restart_proxy_port_conflict_tmp/calls"
    }
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$restart_proxy_port_conflict_tmp/calls"; return 1; }
    _failcat() { printf '%s\n' "$*" >>"$restart_proxy_port_conflict_tmp/fail.log"; }
    sleep() { :; }

    _merge_config_restart
    status=$?
    [ "$status" -ne 0 ] ||
        fail "_merge_config_restart should fail when the refreshed proxy ports are occupied"
    [ "$(cat "$CLASH_CONFIG_RUNTIME")" = "old-runtime" ] ||
        fail "_merge_config_restart should restore the previous runtime after proxy port conflicts"
)
awk '
    $0 == "merge" { merge=NR }
    $0 == "ensure-ext 23571" { ensure=NR }
    $0 == "stop-tmux" && !stop { stop=NR }
    $0 == "detect-proxy" { proxy=NR }
    $0 == "start-tmux:old-runtime" { rollback_start=NR }
    /^start-tmux:new-runtime$/ { bad=1 }
    END {
        exit (!bad && merge && ensure && stop && proxy && rollback_start &&
              merge < ensure && ensure < stop && stop < proxy && proxy < rollback_start) ? 0 : 1
    }
' "$restart_proxy_port_conflict_tmp/calls" ||
    fail "_merge_config_restart should stop old service, check proxy ports, then restore old service on conflict"

on_active_conflict_tmp=$(make_test_tmpdir "clash-on-active-conflict")
(
    set +e
    . "$CLASHCTL_SH"

    _get_active_mode() { printf '%s\n' tmux; return 0; }
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$on_active_conflict_tmp/calls"; }
    _ensure_ext_addr_available() { printf 'ensure-ext\n' >>"$on_active_conflict_tmp/calls"; return 1; }
    _clash_service_start() { printf 'start-%s\n' "$1" >>"$on_active_conflict_tmp/calls"; }
    _okcat() { printf '%s\n' "$*" >>"$on_active_conflict_tmp/ok.log"; }
    _failcat() { printf '%s\n' "$*" >>"$on_active_conflict_tmp/fail.log"; }

    clashon --mode nohup
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashon should reject a different mode when another mode is already active"
    [ ! -e "$on_active_conflict_tmp/calls" ] ||
        fail "clashon should reject active mode conflicts before port checks or adapter start"
    grep -q 'clashrestart --mode nohup' "$on_active_conflict_tmp/fail.log" ||
        fail "clashon active mode conflict should tell users to use clashrestart"
)

multi_mode_state_tmp=$(make_test_tmpdir "clash-multi-mode-state")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_RESOURCES_DIR="$multi_mode_state_tmp/resources"
    CLASH_SERVICE_STATE="$CLASH_RESOURCES_DIR/service-state.yaml"
    mkdir -p "$CLASH_RESOURCES_DIR"
    printf 'active_mode: tmux\n' >"$CLASH_SERVICE_STATE"

    _clash_adapter_tmux_is_active() { return 0; }
    _clash_adapter_nohup_is_active() { return 0; }
    _clash_adapter_systemd_is_active() { return 1; }

    _get_active_mode >/dev/null
    status=$?
    [ "$status" -eq 2 ] ||
        fail "_get_active_mode should report conflicts before trusting service-state.yaml"
)

restart_health_tmp=$(make_test_tmpdir "clash-restart-health")
(
    set +e
    . "$CLASHCTL_SH"

    _get_active_mode() { return 1; }
    _get_default_service_mode() { printf '%s\n' tmux; }
    _merge_config() { printf 'merge\n' >>"$restart_health_tmp/calls"; }
    _ensure_ext_addr_available() { printf 'ensure-ext\n' >>"$restart_health_tmp/calls"; }
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$restart_health_tmp/calls"; }
    _clash_service_stop() { printf 'stop-%s\n' "$1" >>"$restart_health_tmp/calls"; }
    _clash_service_start() { printf 'start-%s\n' "$1" >>"$restart_health_tmp/calls"; }
    clashstatus() { printf 'status\n' >>"$restart_health_tmp/calls"; return 1; }
    _failcat() { printf '%s\n' "$*" >>"$restart_health_tmp/fail.log"; }
    sleep() { SECONDS=$((SECONDS + 10)); }

    _merge_config_restart
    status=$?
    [ "$status" -ne 0 ] ||
        fail "_merge_config_restart should fail when the restarted kernel never becomes healthy"
    grep -qx 'stop-tmux' "$restart_health_tmp/calls" ||
        fail "_merge_config_restart should stop the adapter after restart health check failure"
    grep -q '重启后健康检查失败' "$restart_health_tmp/fail.log" ||
        fail "_merge_config_restart should report restart health check failure clearly"
)

restart_secret_tmp=$(make_test_tmpdir "clash-restart-secret")
(
    set +e
    . "$CLASHCTL_SH"

    _get_active_mode() { printf '%s\n' tmux; return 0; }
    _detect_ext_addr() { EXT_PORT=23571; }
    _merge_config() { printf 'merge\n' >>"$restart_secret_tmp/calls"; }
    _ensure_ext_addr_available() { printf 'ensure-ext %s\n' "${1:-}" >>"$restart_secret_tmp/calls"; }
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$restart_secret_tmp/calls"; }
    _clash_service_stop() { printf 'stop-%s\n' "$1" >>"$restart_secret_tmp/calls"; }
    _clash_service_start() { printf 'start-%s\n' "$1" >>"$restart_secret_tmp/calls"; }
    clashstatus() { printf 'status\n' >>"$restart_secret_tmp/calls"; return 0; }
    sleep() { :; }

    _merge_config_restart || fail "_merge_config_restart should support secret changes while the old kernel is still active"
)
awk '
    $0 == "merge" { merge=NR }
    $0 == "ensure-ext 23571" { ensure=NR }
    $0 == "stop-tmux" { stop=NR }
    $0 == "start-tmux" { start=NR }
    END { exit (merge && ensure && stop && start && merge < ensure && ensure < stop && stop < start) ? 0 : 1 }
' "$restart_secret_tmp/calls" ||
    fail "_merge_config_restart should allow the old active external-controller port while checking the new runtime"

same_mode_health_tmp=$(make_test_tmpdir "clash-same-mode-health")
(
    set +e
    . "$CLASHCTL_SH"

    _get_active_mode() { printf '%s\n' tmux; return 0; }
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$same_mode_health_tmp/calls"; }
    _ensure_ext_addr_available() { printf 'ensure-ext\n' >>"$same_mode_health_tmp/calls"; }
    _clash_service_start() { printf 'start-%s\n' "$1" >>"$same_mode_health_tmp/calls"; }
    clashstatus() { printf 'status %s\n' "$*" >>"$same_mode_health_tmp/calls"; return 1; }
    _okcat() { printf '%s\n' "$*" >>"$same_mode_health_tmp/ok.log"; }
    _failcat() { printf '%s\n' "$*" >>"$same_mode_health_tmp/fail.log"; }

    clashon --mode tmux
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashon should not claim success when the active same-mode process is unhealthy"
    grep -qx 'status --mode tmux' "$same_mode_health_tmp/calls" ||
        fail "clashon same-mode path should verify API health"
    ! grep -q '^detect-proxy$' "$same_mode_health_tmp/calls" ||
        fail "clashon same-mode path should not run startup port checks"
    ! grep -q '^start-tmux$' "$same_mode_health_tmp/calls" ||
        fail "clashon same-mode path should not start another adapter"
)

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

proxy_conflict_tmp=$(make_test_tmpdir "clash-proxy-conflict-readonly")
(
    set +e -u
    . "$CLASHCTL_SH"

    BIN_YQ="$proxy_conflict_tmp/yq"
    CLASH_CONFIG_RUNTIME="$proxy_conflict_tmp/runtime.yaml"
    CLASH_CONFIG_MIXIN="$proxy_conflict_tmp/mixin.yaml"
    cat >"$BIN_YQ" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-i" ]; then
    printf 'yq-write\n' >>"$proxy_conflict_tmp/calls"
    exit 0
fi
case "\$1" in
'.mixed-port // ""')
    printf '\n'
    ;;
'.port // ""')
    printf '7890\n'
    ;;
'.socks-port // ""')
    printf '7891\n'
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
    _is_port_used() { return 0; }
    _get_random_port() { printf '%s\n' 18080; }
    clashstatus() { return 1; }
    _merge_config() { printf 'merge\n' >>"$proxy_conflict_tmp/calls"; }
    _failcat() { printf '%s\n' "$*" >>"$proxy_conflict_tmp/fail.log"; }

    _detect_proxy_port
    status=$?
    [ "$status" -ne 0 ] ||
        fail "_detect_proxy_port should fail when proxy ports are occupied before startup"
    ! grep -q '^yq-write$' "$proxy_conflict_tmp/calls" 2>/dev/null ||
        fail "_detect_proxy_port should not rewrite mixin.yaml automatically"
    ! grep -q '^merge$' "$proxy_conflict_tmp/calls" 2>/dev/null ||
        fail "_detect_proxy_port should not merge config after proxy port conflicts"
    grep -q '建议改 mixin.yaml' "$proxy_conflict_tmp/fail.log" ||
        fail "_detect_proxy_port should tell users to edit mixin.yaml explicitly"
    grep -q '18080' "$proxy_conflict_tmp/fail.log" ||
        fail "_detect_proxy_port should include a suggested free proxy port"
)

empty_ext_host_tmp=$(make_test_tmpdir "clash-empty-ext-host")
(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$empty_ext_host_tmp/yq"
    CLASH_CONFIG_RUNTIME="$empty_ext_host_tmp/runtime.yaml"
    CLASH_CONFIG_MIXIN="$empty_ext_host_tmp/mixin.yaml"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.external-controller // ""')
    printf ':41907\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    printf '{}\n' >"$CLASH_CONFIG_MIXIN"
    _is_port_used() { return 1; }

    _detect_ext_addr || fail "_detect_ext_addr should accept controller values with an empty host"
    [ "$EXT_IP" = 127.0.0.1 ] ||
        fail "_detect_ext_addr should normalize an empty external-controller host to 127.0.0.1"
    [ "$EXT_PORT" = 41907 ] ||
        fail "_detect_ext_addr should preserve the external-controller port"
)

numeric_ext_tmp=$(make_test_tmpdir "clash-numeric-ext")
(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$numeric_ext_tmp/yq"
    CLASH_CONFIG_RUNTIME="$numeric_ext_tmp/runtime.yaml"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.external-controller // ""')
    printf '23571\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"

    _detect_ext_addr || fail "_detect_ext_addr should accept numeric-only external-controller values"
    [ "$EXT_IP" = 127.0.0.1 ] ||
        fail "_detect_ext_addr should treat numeric-only external-controller values as loopback ports"
    [ "$EXT_PORT" = 23571 ] ||
        fail "_detect_ext_addr should preserve numeric-only external-controller ports"
)

ext_yq_fail_tmp=$(make_test_tmpdir "clash-ext-yq-fail")
(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$ext_yq_fail_tmp/yq"
    CLASH_CONFIG_RUNTIME="$ext_yq_fail_tmp/runtime.yaml"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    _failcat() { printf '%s\n' "$*" >>"$ext_yq_fail_tmp/fail.log"; }

    _detect_ext_addr
    status=$?
    [ "$status" -ne 0 ] ||
        fail "_detect_ext_addr should fail when yq cannot read runtime.yaml"
    grep -q 'external-controller 读取失败' "$ext_yq_fail_tmp/fail.log" ||
        fail "_detect_ext_addr should report yq read failures clearly"
)

status_read_only_tmp=$(make_test_tmpdir "clash-status-read-only")
(
    set +e
    . "$CLASHCTL_SH"

    BIN_YQ="$status_read_only_tmp/yq"
    CLASH_CONFIG_RUNTIME="$status_read_only_tmp/runtime.yaml"
    CLASH_CONFIG_MIXIN="$status_read_only_tmp/mixin.yaml"
    cat >"$BIN_YQ" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-i" ]; then
    printf 'yq-write\n' >>"$status_read_only_tmp/calls"
    exit 0
fi
case "\$1" in
'.external-controller // ""')
    printf '192.0.2.10:19090\n'
    ;;
*)
    printf '\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    printf '{}\n' >"$CLASH_CONFIG_MIXIN"

    _get_active_mode() { printf '%s\n' tmux; return 0; }
    _clash_service_is_active() { return 0; }
    _get_secret() { :; }
    _merge_config() { printf 'merge\n' >>"$status_read_only_tmp/calls"; }
    curl() {
        printf '%s\n' "$*" >>"$status_read_only_tmp/calls"
        return 1
    }
    _failcat() { printf '%s\n' "$*" >>"$status_read_only_tmp/fail.log"; }

    clashstatus >/dev/null 2>&1
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashstatus should fail when API probe fails"
    grep -q 'http://192.0.2.10:19090/version' "$status_read_only_tmp/calls" ||
        fail "clashstatus should probe the configured external-controller host"
    ! grep -q '^yq-write$' "$status_read_only_tmp/calls" ||
        fail "clashstatus should not write mixin.yaml"
    ! grep -q '^merge$' "$status_read_only_tmp/calls" ||
        fail "clashstatus should not merge config"
)

orphan_restart_tmp=$(make_test_tmpdir "clash-orphan-restart")
(
    set +e
    . "$CLASHCTL_SH"

    _get_active_mode() { return 1; }
    _current_kernel_pids() { printf '1234\n'; }
    _terminate_current_kernel_pids() { printf 'terminate %s\n' "$*" >>"$orphan_restart_tmp/calls"; }
    _clashon_impl() { printf 'on %s\n' "$*" >>"$orphan_restart_tmp/calls"; }
    _okcat() { printf '%s\n' "$*" >>"$orphan_restart_tmp/ok.log"; }

    clashrestart --mode tmux || fail "clashrestart should recover from exact current-install orphan kernel processes"
)
awk '
    $0 == "terminate 1234" { terminate=NR }
    $0 == "on --mode tmux" { on=NR }
    END { exit (terminate && on && terminate < on) ? 0 : 1 }
' "$orphan_restart_tmp/calls" ||
    fail "clashrestart should terminate exact current-install orphan kernels before starting the target mode"

log_path_tmp=$(make_test_tmpdir "clash-log-path")
(
    set +e
    . "$CLASHCTL_SH"

    _failcat() { printf '%s\n' "$*" >>"$log_path_tmp/fail.log"; }
    FILE_LOG=
    _clash_service_log >/dev/null 2>&1
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashlog should fail when FILE_LOG is empty"
    grep -q '日志路径未初始化' "$log_path_tmp/fail.log" ||
        fail "clashlog should print a clear error when FILE_LOG is empty"
)

status_ext_fail_tmp=$(make_test_tmpdir "clash-status-ext-fail")
(
    set +e
    . "$CLASHCTL_SH"

    _get_active_mode() { printf '%s\n' tmux; return 0; }
    _clash_service_is_active() { return 0; }
    _detect_ext_addr() { printf 'detect-ext\n' >>"$status_ext_fail_tmp/calls"; return 1; }
    _get_secret() { :; }
    curl() { printf 'curl\n' >>"$status_ext_fail_tmp/calls"; return 0; }
    _failcat() { printf '%s\n' "$*" >>"$status_ext_fail_tmp/fail.log"; }

    clashstatus >/dev/null 2>&1
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashstatus should fail when external-controller detection fails"
    ! grep -q '^curl$' "$status_ext_fail_tmp/calls" ||
        fail "clashstatus should not call curl after external-controller detection fails"
)

on_ext_fail_tmp=$(make_test_tmpdir "clash-on-ext-fail")
(
    set +e
    . "$CLASHCTL_SH"

    INIT_TYPE=tmux
    _detect_proxy_port() { printf 'detect-proxy\n' >>"$on_ext_fail_tmp/calls"; }
    _ensure_ext_addr_available() { printf 'ensure-ext\n' >>"$on_ext_fail_tmp/calls"; return 1; }
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
    _ensure_ext_addr_available() { :; }
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

tun_restore_tmp=$(make_test_tmpdir "clash-tun-restore")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_MIXIN="$tun_restore_tmp/mixin.yaml"
    printf 'new\n' >"$CLASH_CONFIG_MIXIN"
    printf 'old\n' >"$tun_restore_tmp/backup.yaml"
    _merge_config() { printf 'merge\n' >>"$tun_restore_tmp/calls"; }
    _clash_service_stop() {
        printf 'stop-%s\n' "$1" >>"$tun_restore_tmp/calls"
    }
    _clash_service_start() {
        printf 'start-%s\n' "$1" >>"$tun_restore_tmp/calls"
        return 1
    }
    _failcat() { printf '%s\n' "$*" >>"$tun_restore_tmp/fail.log"; }

    _restore_tun_mixin "$tun_restore_tmp/backup.yaml" false
    status=$?
    [ "$status" -eq 0 ] ||
        fail "_restore_tun_mixin should succeed when no service restart is requested"
    [ "$(cat "$CLASH_CONFIG_MIXIN")" = "old" ] ||
        fail "_restore_tun_mixin should restore the mixin content"
    ! grep -q '^start-systemd$' "$tun_restore_tmp/calls" ||
        fail "_restore_tun_mixin should not start systemd when restart_after_restore=false"

    printf 'newer\n' >"$CLASH_CONFIG_MIXIN"
    printf 'older\n' >"$tun_restore_tmp/backup2.yaml"
    _restore_tun_mixin "$tun_restore_tmp/backup2.yaml" true
    status=$?
    [ "$status" -ne 0 ] ||
        fail "_restore_tun_mixin should fail when requested systemd restart fails"
    awk '
        $0 == "stop-systemd" { stop=NR }
        $0 == "start-systemd" { start=NR }
        END { exit (stop && start && stop < start) ? 0 : 1 }
    ' "$tun_restore_tmp/calls" ||
        fail "_restore_tun_mixin should stop systemd before starting rollback runtime"
    grep -q 'Tun 配置已回滚，但 systemd 内核恢复启动失败' "$tun_restore_tmp/fail.log" ||
        fail "_restore_tun_mixin should report failed systemd restart after rollback"
)

pass "runtime mode checks"
