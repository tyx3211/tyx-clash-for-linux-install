#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
COMMON_SH="$TEST_ROOT/scripts/cmd/common.sh"
PROXY_SH="$TEST_ROOT/scripts/lib/proxy.sh"
SERVICE_RUNTIME_SH="$TEST_ROOT/scripts/lib/service-runtime.sh"
CONFIG_SH="$TEST_ROOT/scripts/lib/config.sh"
TUN_SH="$TEST_ROOT/scripts/lib/tun.sh"
SUBSCRIPTION_SH="$TEST_ROOT/scripts/lib/subscription.sh"

for file in "$PROXY_SH" "$SERVICE_RUNTIME_SH" "$CONFIG_SH" "$TUN_SH" "$SUBSCRIPTION_SH"; do
    [ -f "$file" ] || fail "clashctl domain library should exist: $file"
done

assert_file_contains "$CLASHCTL_SH" '^_clashctl_source_lib\(\)' \
    "clashctl should guard domain library sourcing"

assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/common\.sh"' \
    "clashctl should source common helpers through the guarded helper"

assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/proxy\.sh"' \
    "clashctl should source proxy helpers from scripts/lib"
assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/service-runtime\.sh"' \
    "clashctl should source runtime service helpers from scripts/lib"
assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/config\.sh"' \
    "clashctl should source config helpers from scripts/lib"
assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/tun\.sh"' \
    "clashctl should source tun helpers from scripts/lib"
assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/subscription\.sh"' \
    "clashctl should source subscription helpers from scripts/lib"

missing_lib_tmp=$(make_test_tmpdir "clash-missing-lib")
missing_lib_repo="$missing_lib_tmp/repo"
cp -a "$TEST_ROOT/." "$missing_lib_repo"
/usr/bin/rm -f "$missing_lib_repo/scripts/lib/proxy.sh"
(
    set +e
    . "$missing_lib_repo/scripts/cmd/clashctl.sh" 2>"$missing_lib_tmp/source.err"
    source_status=$?
    declare -F clashctl >/dev/null
    defined_status=$?
    printf '%s %s\n' "$source_status" "$defined_status" >"$missing_lib_tmp/source.status"
)
read -r source_status defined_status <"$missing_lib_tmp/source.status"
[ "$source_status" -ne 0 ] ||
    fail "clashctl source should fail when a required domain library is missing"
[ "$defined_status" -ne 0 ] ||
    fail "clashctl dispatcher should not be defined after required library source failure"
grep -q 'proxy.sh' "$missing_lib_tmp/source.err" ||
    fail "missing library source failure should name the missing file"

missing_common_tmp=$(make_test_tmpdir "clash-missing-common")
missing_common_repo="$missing_common_tmp/repo"
cp -a "$TEST_ROOT/." "$missing_common_repo"
/usr/bin/rm -f "$missing_common_repo/scripts/cmd/common.sh"
(
    set +e
    . "$missing_common_repo/scripts/cmd/clashctl.sh" 2>"$missing_common_tmp/source.err"
    source_status=$?
    declare -F clashctl >/dev/null
    defined_status=$?
    printf '%s %s\n' "$source_status" "$defined_status" >"$missing_common_tmp/source.status"
)
read -r source_status defined_status <"$missing_common_tmp/source.status"
[ "$source_status" -ne 0 ] ||
    fail "clashctl source should fail when common helpers are missing"
[ "$defined_status" -ne 0 ] ||
    fail "clashctl dispatcher should not be defined after common helper source failure"
grep -q 'common.sh' "$missing_common_tmp/source.err" ||
    fail "missing common source failure should name the missing file"

missing_env_tmp=$(make_test_tmpdir "clash-missing-env")
missing_env_repo="$missing_env_tmp/repo"
cp -a "$TEST_ROOT/." "$missing_env_repo"
/usr/bin/rm -f "$missing_env_repo/.env"
bash -c '
    . "$1/scripts/cmd/clashctl.sh" 2>"$2/source.err"
    source_status=$?
    declare -F clashctl >/dev/null
    defined_status=$?
    printf "%s %s\n" "$source_status" "$defined_status" >"$2/source.status"
' -- "$missing_env_repo" "$missing_env_tmp" || true
read -r source_status defined_status <"$missing_env_tmp/source.status"
[ "$source_status" -ne 0 ] ||
    fail "clashctl source should fail when .env is missing"
[ "$defined_status" -ne 0 ] ||
    fail "clashctl dispatcher should not be defined after .env source failure"
grep -q '\.env' "$missing_env_tmp/source.err" ||
    fail "missing .env source failure should name the missing file"

assert_file_contains "$PROXY_SH" '^function clashproxy\(\)' \
    "proxy command should live in proxy library"
assert_file_contains "$PROXY_SH" '^watch_proxy\(\)' \
    "interactive proxy watcher should live in proxy library"

assert_file_contains "$SERVICE_RUNTIME_SH" '^_clash_adapter_tmux_start\(\)' \
    "tmux adapter should live in runtime service library"
assert_file_contains "$SERVICE_RUNTIME_SH" '^function clashon\(\)' \
    "clashon command should live in runtime service library"
assert_file_contains "$SERVICE_RUNTIME_SH" '^function clashstatus\(\)' \
    "clashstatus command should live in runtime service library"

assert_file_contains "$CONFIG_SH" '^_merge_config\(\)' \
    "config merge should live in config library"
assert_file_contains "$CONFIG_SH" '^function clashmixin\(\)' \
    "mixin command should live in config library"
assert_file_contains "$CONFIG_SH" '^function clashupgrade\(\)' \
    "kernel upgrade command should live in config library"

assert_file_contains "$TUN_SH" '^function clashtun\(\)' \
    "tun command should live in tun library"
assert_file_contains "$TUN_SH" '^_require_tun_runtime\(\)' \
    "tun runtime gate should live in tun library"

assert_file_contains "$SUBSCRIPTION_SH" '^function clashsub\(\)' \
    "subscription command should live in subscription library"
assert_file_contains "$SUBSCRIPTION_SH" '^_sub_add\(\)' \
    "subscription mutation helpers should live in subscription library"

assert_file_contains "$CLASHCTL_SH" '^function clashctl\(\)' \
    "clashctl dispatcher should remain in the command entrypoint"
assert_file_contains "$CLASHCTL_SH" '^clashhelp\(\)' \
    "clashhelp should remain in the command entrypoint"

assert_file_not_contains "$CLASHCTL_SH" '^_clash_adapter_tmux_start\(\)' \
    "runtime adapters should not remain in clashctl entrypoint"
assert_file_not_contains "$CLASHCTL_SH" '^_merge_config\(\)' \
    "config merge implementation should not remain in clashctl entrypoint"
assert_file_not_contains "$CLASHCTL_SH" '^_sub_add\(\)' \
    "subscription helpers should not remain in clashctl entrypoint"
assert_file_not_contains "$CLASHCTL_SH" '^function clashtun\(\)' \
    "tun command should not remain in clashctl entrypoint"
assert_file_not_contains "$CLASHCTL_SH" '^function clashproxy\(\)' \
    "proxy command should not remain in clashctl entrypoint"

pass "clashctl split checks"
