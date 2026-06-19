#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

INSTALL_SH="$TEST_ROOT/install.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
COMMON_SH="$TEST_ROOT/scripts/cmd/common.sh"
CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
FISH_SH="$TEST_ROOT/scripts/cmd/clashctl.fish"
UNINSTALL_SH="$TEST_ROOT/uninstall.sh"

install_order=$(
    awk '
        /_parse_args "\$@"/ { print "parse"; next }
        /_validate_init_mode/ { print "validate_init"; next }
        /^_valid$/ { print "valid"; next }
    ' "$INSTALL_SH"
)
grep -q $'parse\nvalidate_init\nvalid' <<<"$install_order" ||
    fail "install should validate init mode before creating install directories"

assert_file_contains "$PREFLIGHT_SH" '_normalize_sudo_install_path\(\)' \
    "regular sudo systemd install should normalize default /root path back to invoking user home"

assert_file_contains "$PREFLIGHT_SH" '_refresh_install_paths\(\)' \
    "command-line kernel/path overrides should refresh derived install paths"

assert_file_contains "$INSTALL_SH" 'INSTALL_MARKER' \
    "install should create an ownership marker before uninstall can remove the install root"

assert_file_contains "$UNINSTALL_SH" 'INSTALL_MARKER' \
    "uninstall should require the install marker before rm -rf"

assert_file_contains "$UNINSTALL_SH" 'CLASH_BASE_REAL' \
    "uninstall should canonicalize the install path before rm -rf"

uninstall_order=$(
    awk '
        /INSTALL_MARKER=/ { print "marker"; next }
        /scripts\/cmd\/clashctl.sh/ { print "source_installed"; next }
    ' "$UNINSTALL_SH"
)
grep -q $'marker\nsource_installed' <<<"$uninstall_order" ||
    fail "uninstall should validate the install marker before sourcing installed scripts"

assert_file_contains "$CLASHCTL_SH" 'CLASH_INSTALLED_INIT_TYPE' \
    "tun gate should use the installed service mode, not only mutable .env INIT_TYPE"

assert_file_contains "$CLASHCTL_SH" '_restore_tun_mixin' \
    "tunon should restore mixin config if enabling Tun fails"

assert_file_contains "$CLASHCTL_SH" '_is_tun_enabled' \
    "tunoff should be able to disable stale tun.enable even when the device is absent"

assert_file_contains "$COMMON_SH" 'BIN_SUBCONVERTER_PID' \
    "subconverter stop should be scoped to the process started by this install"

assert_file_not_contains "$COMMON_SH" 'pkill -KILL -x subconverter' \
    "subconverter stop should not kill every same-name process"

assert_file_contains "$COMMON_SH" 'newPort=\$\(_get_random_port\) \|\| return 1' \
    "random port allocation failures should propagate to callers"

assert_file_contains "$COMMON_SH" '_detect_subconverter_port \|\| return 1' \
    "subconverter port detection failures should stop conversion startup"

assert_file_contains "$CLASHCTL_SH" '_validate_downloaded_config "\$CLASH_CONFIG_TEMP"' \
    "clashsub update --convert should run post-conversion safety validation"

assert_file_contains "$FISH_SH" 'clashtun' \
    "fish wrapper should expose clashtun for clashctl tun"

pass "audit regression checks"
