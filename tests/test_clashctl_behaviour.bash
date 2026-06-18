#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
UNINSTALL_SH="$TEST_ROOT/uninstall.sh"

detect_proxy_port_body=$(extract_function "_detect_proxy_port" "$CLASHCTL_SH")
grep -q 'eval ' <<<"$detect_proxy_port_body" &&
    fail "_detect_proxy_port should not use eval to resolve port variables"

assert_file_contains "$CLASHCTL_SH" 'CLASHCTL_CRON_TAG|CLASH_CRON_TAG' \
    "clashsub auto-update should use a stable crontab tag"

assert_file_not_contains "$CLASHCTL_SH" "grep -qs 'clashsub update'" \
    "clashsub auto-update should not identify jobs by broad command text"

assert_file_not_contains "$UNINSTALL_SH" 'grep -v "clashsub"' \
    "uninstall should not delete unrelated user crontab entries containing clashsub"

assert_file_not_contains "$CLASHCTL_SH" 'pkill -9 -f' \
    "clashctl should not use broad force-kill command matching"

assert_file_not_contains "$PREFLIGHT_SH" 'pkill -9 -f' \
    "service templates should not use broad force-kill command matching"

assert_file_contains "$CLASHCTL_SH" '_get_id_by_url\(\)' \
    "clashsub should look up duplicate subscriptions by URL"

assert_file_contains "$CLASHCTL_SH" 'PROFILE_URL=\$url' \
    "clashsub should pass subscription URL into yq through environment"

assert_file_contains "$CLASHCTL_SH" 'env\(PROFILE_URL\)' \
    "clashsub should read subscription URL from yq environment"

assert_file_contains "$CLASHCTL_SH" 'PROFILE_ID=\$id' \
    "clashsub should pass subscription id into yq through environment"

assert_file_contains "$CLASHCTL_SH" 'clashtun\(\)' \
    "clashctl should keep a tun command entry point"

pass "clashctl safety checks"
