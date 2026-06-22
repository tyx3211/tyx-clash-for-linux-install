#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
SERVICE_RUNTIME_SH="$TEST_ROOT/scripts/lib/service-runtime.sh"
CONFIG_SH="$TEST_ROOT/scripts/lib/config.sh"
SUBSCRIPTION_SH="$TEST_ROOT/scripts/lib/subscription.sh"
TUN_SH="$TEST_ROOT/scripts/lib/tun.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
SERVICE_RENDER_SH="$TEST_ROOT/scripts/install/service-render.sh"
UNINSTALL_SH="$TEST_ROOT/uninstall.sh"
FISH_SH="$TEST_ROOT/scripts/cmd/clashctl.fish"

detect_proxy_port_body=$(extract_function "_detect_proxy_port" "$SERVICE_RUNTIME_SH")
grep -q 'eval ' <<<"$detect_proxy_port_body" &&
    fail "_detect_proxy_port should not use eval to resolve port variables"

assert_file_contains "$SUBSCRIPTION_SH" 'CLASHCTL_CRON_TAG|CLASH_CRON_TAG' \
    "clashsub auto-update should use a stable crontab tag"

assert_file_not_contains "$SUBSCRIPTION_SH" "grep -qs 'clashsub update'" \
    "clashsub auto-update should not identify jobs by broad command text"

assert_file_not_contains "$UNINSTALL_SH" 'grep -v "clashsub"' \
    "uninstall should not delete unrelated user crontab entries containing clashsub"

assert_file_not_contains "$SERVICE_RUNTIME_SH" 'pkill -9 -f' \
    "clashctl should not use broad force-kill command matching"

assert_file_not_contains "$PREFLIGHT_SH" 'pkill -9 -f' \
    "service templates should not use broad force-kill command matching"

assert_file_contains "$SUBSCRIPTION_SH" '_get_id_by_url\(\)' \
    "clashsub should look up duplicate subscriptions by URL"

assert_file_contains "$SUBSCRIPTION_SH" 'PROFILE_URL=\$url' \
    "clashsub should pass subscription URL into yq through environment"

assert_file_contains "$SUBSCRIPTION_SH" 'env\(PROFILE_URL\)' \
    "clashsub should read subscription URL from yq environment"

assert_file_contains "$SUBSCRIPTION_SH" 'PROFILE_ID=\$id' \
    "clashsub should pass subscription id into yq through environment"

assert_file_contains "$SUBSCRIPTION_SH" 'local profile_path url use' \
    "subscription delete helper should keep use as a local variable"

assert_file_contains "$SUBSCRIPTION_SH" 'local profile_backup=.*had_profile=false use' \
    "subscription update helper should keep use as a local variable"

assert_file_contains "$TUN_SH" 'clashtun\(\)' \
    "clashctl should keep a tun command entry point"

assert_file_not_contains "$FISH_SH" 'eval ' \
    "fish wrapper should not use eval to generate fixed command wrappers"

assert_file_contains "$SERVICE_RENDER_SH" '^_preflight_escape_sed_repl\(\)' \
    "service rendering should keep sed replacement escaping as a top-level helper"

assert_file_not_contains "$SERVICE_RENDER_SH" '^[[:space:]]*_escape_sed_repl\(\)' \
    "service rendering should not define helper functions inside _install_service"

proxy_args_tmp=$(make_test_tmpdir "clash-proxy-args")
(
    set +e
    . "$CLASHCTL_SH"

    _failcat() { printf '%s\n' "$*" >>"$proxy_args_tmp/fail.log"; }
    _set_system_proxy() { printf 'set-proxy\n' >>"$proxy_args_tmp/calls"; }

    clashproxy on typo
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashproxy on should reject unexpected extra arguments"
    [ ! -e "$proxy_args_tmp/calls" ] ||
        fail "clashproxy on should not set proxy variables after argument errors"
    grep -q '未知参数' "$proxy_args_tmp/fail.log" ||
        fail "clashproxy argument errors should be readable"
)

sidecar_tmp=$(make_test_tmpdir "clash-sidecar-parent")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_SIDECAR="$sidecar_tmp/config/clashctl.yaml"
    CLASH_RESOURCES_DIR="$sidecar_tmp/resources"
    _ensure_sidecar_config || exit 1
    [ -s "$CLASH_CONFIG_SIDECAR" ] ||
        fail "sidecar config creation should create the selected parent directory"
)

ui_loopback_tmp=$(make_test_tmpdir "clash-ui-loopback")
(
    set +e
    . "$CLASHCTL_SH"

    _detect_ext_addr() {
        EXT_IP=127.0.0.1
        EXT_PORT=9090
    }
    clashstatus() { return 0; }
    curl() { return 0; }
    _okcat() {
        [ "$#" -gt 1 ] && shift
        printf '%s\n' "$1"
    }

    clashui >"$ui_loopback_tmp/out"
)
grep -q 'http://localhost:9090/ui' "$ui_loopback_tmp/out" ||
    fail "loopback clashui output should show localhost browser URL"
grep -q 'ssh -L 9090:127.0.0.1:9090' "$ui_loopback_tmp/out" ||
    fail "loopback clashui output should show an SSH forwarding example"
! grep -q '公网' "$ui_loopback_tmp/out" ||
    fail "loopback clashui output should not show public address"
! grep -q '放行端口' "$ui_loopback_tmp/out" ||
    fail "loopback clashui output should not ask users to open firewall ports"

ui_ext_fail_tmp=$(make_test_tmpdir "clash-ui-ext-fail")
(
    set +e
    . "$CLASHCTL_SH"

    _detect_ext_addr() { return 1; }
    clashstatus() { return 0; }
    clashon() { printf 'start\n' >>"$ui_ext_fail_tmp/calls"; return 0; }
    clashui >"$ui_ext_fail_tmp/out" 2>"$ui_ext_fail_tmp/err"
    status=$?
    [ "$status" -ne 0 ] ||
        fail "clashui should fail when external-controller conflict resolution fails"
    [ ! -e "$ui_ext_fail_tmp/calls" ] ||
        fail "clashui should not start the kernel after external-controller detection fails"
    [ ! -s "$ui_ext_fail_tmp/out" ] ||
        fail "clashui should not print a stale URL after external-controller detection fails"
)

assert_file_contains "$CONFIG_SH" '_detect_ext_addr \|\| return 1' \
    "config commands should propagate external-controller detection failures"

upgrade_setu_tmp=$(make_test_tmpdir "clash-upgrade-setu")
(
    set -eu
    . "$CLASHCTL_SH"

    _detect_ext_addr() {
        EXT_IP=127.0.0.1
        EXT_PORT=9090
    }
    clashstatus() { return 0; }
    _get_secret() { :; }
    _okcat() { :; }
    curl() {
        printf '{"status":"ok"}\n'
    }

    clashupgrade >"$upgrade_setu_tmp/out"
)

set_u_tmp=$(make_test_tmpdir "clash-set-u-entrypoints")
(
    set -eu
    . "$CLASHCTL_SH"

    clashhelp() { printf 'help\n' >>"$set_u_tmp/calls"; }
    tunstatus() { printf 'tunstatus\n' >>"$set_u_tmp/calls"; return 0; }
    _sub_list() { printf 'sub-list\n' >>"$set_u_tmp/calls"; }
    _get_secret() { printf 'secret\n'; }
    _okcat() { printf '%s\n' "$*" >>"$set_u_tmp/calls"; }
    less() { printf 'less %s\n' "$1" >>"$set_u_tmp/calls"; }

    clashctl
    clashsub
    clashsecret
    clashtun
    clashmixin
) || fail "public clashctl entrypoints should support no-argument calls under set -u"
grep -qx 'help' "$set_u_tmp/calls" ||
    fail "no-argument clashctl should show help under set -u"
grep -qx 'sub-list' "$set_u_tmp/calls" ||
    fail "no-argument clashsub should list subscriptions under set -u"
grep -qx 'tunstatus' "$set_u_tmp/calls" ||
    fail "no-argument clashtun should show status under set -u"

pass "clashctl safety checks"
