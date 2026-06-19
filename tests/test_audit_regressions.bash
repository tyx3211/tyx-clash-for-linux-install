#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

INSTALL_SH="$TEST_ROOT/install.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
COMMON_SH="$TEST_ROOT/scripts/cmd/common.sh"
CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
PROXY_SH="$TEST_ROOT/scripts/lib/proxy.sh"
SERVICE_RUNTIME_SH="$TEST_ROOT/scripts/lib/service-runtime.sh"
TUN_SH="$TEST_ROOT/scripts/lib/tun.sh"
SUBSCRIPTION_SH="$TEST_ROOT/scripts/lib/subscription.sh"
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

env_override_tmp=$(make_test_tmpdir "clash-env-override")
(
    THIS_SCRIPT_DIR="$TEST_ROOT/scripts/cmd"
    CLASH_BASE_DIR="$env_override_tmp/custom-install"
    . "$COMMON_SH"
    [ "$CLASH_BASE_DIR" = "$env_override_tmp/custom-install" ] ||
        fail "explicit CLASH_BASE_DIR environment override should win over .env defaults"
)

assert_file_contains "$PREFLIGHT_SH" '\[\!A-Za-z0-9_\./-\]' \
    "install path validation should reject shell metacharacters"

assert_file_contains "$INSTALL_SH" 'INSTALL_MARKER' \
    "install should create an ownership marker before uninstall can remove the install root"

assert_file_contains "$UNINSTALL_SH" 'INSTALL_MARKER' \
    "uninstall should require the install marker before rm -rf"

assert_file_contains "$UNINSTALL_SH" 'CLASH_BASE_REAL' \
    "uninstall should canonicalize the install path before rm -rf"

assert_file_contains "$PREFLIGHT_SH" '_revoke_rc_file' \
    "rc cleanup should be scoped to the current install block"

assert_file_not_contains "$PREFLIGHT_SH" '/\$start_flag/,/\$end_flag/d' \
    "rc cleanup should not remove every clashctl block regardless of install path"

rc_symlink_tmp=$(make_test_tmpdir "clash-rc-symlink")
(
    CLASH_BASE_DIR="$rc_symlink_tmp/install"
    CLASH_RESOURCES_DIR="$CLASH_BASE_DIR/resources"
    KERNEL_NAME=mihomo
    . "$PREFLIGHT_SH"

    CLASH_CMD_DIR="$CLASH_BASE_DIR/scripts/cmd"
    mkdir -p "$rc_symlink_tmp/dotfiles" "$CLASH_CMD_DIR"
    rc_real="$rc_symlink_tmp/dotfiles/bashrc"
    rc_link="$rc_symlink_tmp/.bashrc"
    cat >"$rc_real" <<EOF
keep-before
# clashctl START /other/install/scripts/cmd
. /other/install/scripts/cmd/clashctl.sh
# clashctl END /other/install/scripts/cmd
# clashctl START $CLASH_CMD_DIR
. $CLASH_CMD_DIR/clashctl.sh
# clashctl END $CLASH_CMD_DIR
keep-after
EOF
    ln -s "$rc_real" "$rc_link"

    _revoke_rc_file "$rc_link"
    [ -L "$rc_link" ] ||
        fail "rc cleanup should preserve symlink rc files"
    grep -q '/other/install/scripts/cmd/clashctl.sh' "$rc_real" ||
        fail "rc cleanup should keep unrelated clashctl blocks"
    ! grep -q "$CLASH_CMD_DIR/clashctl.sh" "$rc_real" ||
        fail "rc cleanup should remove only the current install block"
    grep -q 'keep-after' "$rc_real" ||
        fail "rc cleanup should preserve trailing user rc content"
)

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

assert_file_contains "$TUN_SH" '_restore_tun_mixin' \
    "tunon should restore mixin config if enabling Tun fails"

assert_file_contains "$TUN_SH" '_is_tun_enabled' \
    "tunoff should be able to disable stale tun.enable even when the device is absent"

assert_file_contains "$COMMON_SH" 'BIN_SUBCONVERTER_PID' \
    "subconverter stop should be scoped to the process started by this install"

assert_file_not_contains "$COMMON_SH" 'pkill -KILL -x subconverter' \
    "subconverter stop should not kill every same-name process"

assert_file_contains "$COMMON_SH" 'newPort=\$\(_get_random_port\) \|\| return 1' \
    "random port allocation failures should propagate to callers"

assert_file_contains "$COMMON_SH" '_detect_subconverter_port \|\| return 1' \
    "subconverter port detection failures should stop conversion startup"

assert_file_contains "$SUBSCRIPTION_SH" '_validate_downloaded_config "\$CLASH_CONFIG_TEMP"' \
    "clashsub update --convert should run post-conversion safety validation"

assert_file_contains "$FISH_SH" 'clashtun' \
    "fish wrapper should expose clashtun for clashctl tun"

assert_file_contains "$SERVICE_RUNTIME_SH" 'sudo -n systemctl' \
    "systemd adapter should fail fast instead of prompting for sudo password"

assert_file_contains "$SERVICE_RUNTIME_SH" '_proc_cmdline_has_arg' \
    "nohup pid matching should parse /proc cmdline as NUL-separated arguments"

assert_file_contains "$SERVICE_RUNTIME_SH" '_proc_starttime' \
    "nohup pid matching should record process starttime to reduce PID reuse risk"

assert_file_contains "$PROXY_SH" '_clash_service_is_active.*\|\| return 0|_clash_service_is_active' \
    "watch_proxy should check that the managed kernel is active before exporting proxy variables"

pass "audit regression checks"
