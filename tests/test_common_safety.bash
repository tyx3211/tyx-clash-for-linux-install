#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

COMMON_SH="$TEST_ROOT/scripts/cmd/common.sh"

assert_file_contains "$COMMON_SH" '^_normalize_sub_config\(\)' \
    "common.sh should normalize downloaded subscription text"

assert_file_contains "$COMMON_SH" '^_is_html_response\(\)' \
    "common.sh should detect HTML subscription responses"

assert_file_contains "$COMMON_SH" '^_valid_sub_nodes\(\)' \
    "common.sh should reject subscriptions without proxies or providers"

assert_file_contains "$COMMON_SH" '_normalize_sub_config "\$dest"' \
    "_download_config should normalize raw subscription before validation"

assert_file_contains "$COMMON_SH" '_is_html_response "\$dest"' \
    "_download_config should reject HTML responses before kernel validation"

assert_file_contains "$COMMON_SH" 'fail_count|for .*attempt|while .*100' \
    "_get_random_port should have a bounded retry guard"

assert_file_not_contains "$COMMON_SH" 'BIN_SUBCONVERTER_STOP=.*pkill -9 -f' \
    "subconverter stop command should not be stored as an unquoted pkill -f string"

assert_file_contains "$COMMON_SH" 'FILE_LOG="\$\{CLASH_RESOURCES_DIR\}/\$\{KERNEL_NAME\}\.log"' \
    "common.sh should initialize FILE_LOG for clashlog and tmux/nohup redirection"

assert_file_contains "$COMMON_SH" 'FILE_PID="\$\{CLASH_RESOURCES_DIR\}/\$\{KERNEL_NAME\}\.pid"' \
    "common.sh should initialize FILE_PID for nohup pid tracking"

pass "common safety checks"
