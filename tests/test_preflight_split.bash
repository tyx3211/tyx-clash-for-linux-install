#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
ARCHIVE_SAFE_SH="$TEST_ROOT/scripts/install/archive-safe.sh"
SERVICE_RENDER_SH="$TEST_ROOT/scripts/install/service-render.sh"
RC_SH="$TEST_ROOT/scripts/install/rc.sh"

[ -f "$ARCHIVE_SAFE_SH" ] ||
    fail "archive safety helpers should live in scripts/install/archive-safe.sh"
[ -f "$SERVICE_RENDER_SH" ] ||
    fail "service rendering helpers should live in scripts/install/service-render.sh"
[ -f "$RC_SH" ] ||
    fail "shell rc helpers should live in scripts/install/rc.sh"

assert_file_contains "$PREFLIGHT_SH" 'install/archive-safe\.sh' \
    "preflight should source archive safety helpers"
assert_file_contains "$PREFLIGHT_SH" 'install/service-render\.sh' \
    "preflight should source service rendering helpers"
assert_file_contains "$PREFLIGHT_SH" 'install/rc\.sh' \
    "preflight should source shell rc helpers"

assert_file_contains "$ARCHIVE_SAFE_SH" '^_archive_member_path_is_safe\(\)' \
    "archive member validation should be in archive-safe module"
assert_file_contains "$ARCHIVE_SAFE_SH" '^_extract_tar_archive\(\)' \
    "tar extraction guard should be in archive-safe module"
assert_file_contains "$SERVICE_RENDER_SH" '^_install_service\(\)' \
    "service rendering should be in service-render module"
assert_file_contains "$SERVICE_RENDER_SH" '^_detect_init\(\)' \
    "service init detection should be in service-render module"
assert_file_contains "$SERVICE_RENDER_SH" '^_quote_command\(\)' \
    "service command quoting should be in service-render module"
assert_file_contains "$SERVICE_RENDER_SH" '^_preflight_escape_sed_repl\(\)' \
    "sed replacement escaping should stay with service rendering"
assert_file_contains "$RC_SH" '^_apply_rc\(\)' \
    "shell rc apply helper should be in rc module"
assert_file_contains "$RC_SH" '^_revoke_rc_file\(\)' \
    "shell rc revoke helper should be in rc module"

assert_file_not_contains "$PREFLIGHT_SH" '^_archive_member_path_is_safe\(\)' \
    "preflight should not keep archive safety function bodies"
assert_file_not_contains "$PREFLIGHT_SH" '^_install_service\(\)' \
    "preflight should not keep service rendering function bodies"
assert_file_not_contains "$PREFLIGHT_SH" '^_detect_init\(\)' \
    "preflight should not keep service init detection function bodies"
assert_file_not_contains "$PREFLIGHT_SH" '^_apply_rc\(\)' \
    "preflight should not keep shell rc function bodies"

pass "preflight split checks"
