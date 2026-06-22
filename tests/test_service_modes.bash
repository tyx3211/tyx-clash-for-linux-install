#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

ENV_FILE="$TEST_ROOT/.env"
INSTALL_SH="$TEST_ROOT/install.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
SERVICE_RENDER_SH="$TEST_ROOT/scripts/install/service-render.sh"
CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
TUN_SH="$TEST_ROOT/scripts/lib/tun.sh"

assert_file_contains "$ENV_FILE" '^INIT_TYPE=tmux$' \
    "tmux should remain the default init mode"

assert_file_contains "$SERVICE_RENDER_SH" 'tmux\)' \
    "_detect_init should support tmux mode"

assert_file_contains "$SERVICE_RENDER_SH" 'nohup\)' \
    "_detect_init should support explicit nohup mode"

assert_file_contains "$SERVICE_RENDER_SH" 'systemd\)' \
    "_detect_init should support explicit systemd mode"

assert_file_contains "$PREFLIGHT_SH" '--init=' \
    "_parse_args should accept --init=<mode>"

assert_file_contains "$PREFLIGHT_SH" '--init' \
    "_parse_args should accept --init <mode>"

clashtun_body=$(extract_function "clashtun" "$TUN_SH")
[ -n "$clashtun_body" ] ||
    fail "extract_function should read function-style clashtun definitions"
grep -q 'no-sudo 版已禁用' <<<"$clashtun_body" &&
    fail "clashtun should be mode-gated instead of permanently disabled"

assert_file_contains "$TUN_SH" 'tunon\(\)' \
    "clashctl should provide tunon implementation for sudo-capable mode"

assert_file_contains "$INSTALL_SH" '_parse_args "\$@"' \
    "install.sh should parse command-line overrides before detecting init"

pass "service mode checks"
