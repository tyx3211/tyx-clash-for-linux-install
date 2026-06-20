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

assert_file_contains "$INSTALL_SH" '_detect_proxy_port \|\| _error_quit' \
    "install should fail when proxy port conflict handling cannot be persisted"

assert_file_contains "$INSTALL_SH" 'clashui \|\| _error_quit' \
    "install should fail when Web console endpoint detection or startup fails"

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

path_traversal_tmp=$(make_test_tmpdir "clash-install-path-traversal")
(
    set +e
    . "$TEST_ROOT/scripts/cmd/clashctl.sh"
    . "$PREFLIGHT_SH"

    CLASHCTL_ERROR_EXIT=1
    CLASH_BASE_DIR="$path_traversal_tmp/install/.."
    _validate_install_path
) >"$path_traversal_tmp/out" 2>"$path_traversal_tmp/err" &&
    fail "install path validation should reject absolute paths containing .. components"

assert_file_contains "$INSTALL_SH" 'INSTALL_MARKER' \
    "install should create an ownership marker before uninstall can remove the install root"

assert_file_contains "$UNINSTALL_SH" 'INSTALL_MARKER' \
    "uninstall should require the install marker before rm -rf"

assert_file_contains "$UNINSTALL_SH" 'CLASH_BASE_REAL' \
    "uninstall should canonicalize the install path before rm -rf"

uninstall_env_tmp=$(make_test_tmpdir "clash-uninstall-env")
uninstall_env_repo="$uninstall_env_tmp/repo"
cp -a "$TEST_ROOT/." "$uninstall_env_repo"
cat >"$uninstall_env_repo/.env" <<EOF
KERNEL_NAME=\$(touch "$uninstall_env_tmp/executed")
CLASH_BASE_DIR=$uninstall_env_repo
INIT_TYPE=tmux
EOF
(
    set +e
    cd "$uninstall_env_repo"
    bash -n "$uninstall_env_repo/uninstall.sh"
    bash "$uninstall_env_repo/uninstall.sh" >/dev/null 2>&1
) || true
[ ! -e "$uninstall_env_tmp/executed" ] ||
    fail "uninstall should parse .env without executing shell code"

uninstall_state_tmp=$(make_test_tmpdir "clash-uninstall-state")
uninstall_state_repo="$uninstall_state_tmp/repo"
cp -a "$TEST_ROOT/." "$uninstall_state_repo"
rm -f "$uninstall_state_repo/.env"
mkdir -p "$uninstall_state_repo/resources"
printf 'tyx-clash-for-linux-install\n' >"$uninstall_state_repo/.clashctl-install-root"
cat >"$uninstall_state_repo/resources/install-state.yaml" <<EOF
install_dir: "$uninstall_state_repo"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
(
    set +e
    bash "$uninstall_state_repo/uninstall.sh" >"$uninstall_state_tmp/out" 2>"$uninstall_state_tmp/err"
    status=$?
    [ "$status" -eq 0 ] ||
        fail "uninstall should use install-state.yaml when .env is absent"
)
[ ! -e "$uninstall_state_repo" ] ||
    fail "uninstall should remove a state-only install directory after ownership checks"

uninstall_bad_kernel_tmp=$(make_test_tmpdir "clash-uninstall-bad-kernel")
uninstall_bad_kernel_repo="$uninstall_bad_kernel_tmp/repo"
cp -a "$TEST_ROOT/." "$uninstall_bad_kernel_repo"
rm -f "$uninstall_bad_kernel_repo/.env"
mkdir -p "$uninstall_bad_kernel_repo/resources"
printf 'tyx-clash-for-linux-install\n' >"$uninstall_bad_kernel_repo/.clashctl-install-root"
cat >"$uninstall_bad_kernel_repo/resources/install-state.yaml" <<EOF
install_dir: "$uninstall_bad_kernel_repo"
kernel_name: "../../tmp/evil"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
(
    set +e
    bash "$uninstall_bad_kernel_repo/uninstall.sh" >"$uninstall_bad_kernel_tmp/out" 2>"$uninstall_bad_kernel_tmp/err"
    status=$?
    [ "$status" -ne 0 ] ||
        fail "uninstall should reject invalid kernel names before service path construction"
)
[ -d "$uninstall_bad_kernel_repo" ] ||
    fail "uninstall should not delete install dir when kernel name is invalid"
grep -q '内核名称' "$uninstall_bad_kernel_tmp/err" ||
    fail "invalid kernel name error should explain the kernel name problem"

uninstall_mismatch_tmp=$(make_test_tmpdir "clash-uninstall-mismatch")
uninstall_mismatch_a="$uninstall_mismatch_tmp/install-a"
uninstall_mismatch_b="$uninstall_mismatch_tmp/install-b"
cp -a "$TEST_ROOT/." "$uninstall_mismatch_a"
cp -a "$TEST_ROOT/." "$uninstall_mismatch_b"
printf 'tyx-clash-for-linux-install\n' >"$uninstall_mismatch_b/.clashctl-install-root"
cat >"$uninstall_mismatch_a/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$uninstall_mismatch_b
INIT_TYPE=tmux
EOF
cat >"$uninstall_mismatch_b/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$uninstall_mismatch_b
INIT_TYPE=tmux
EOF
(
    set +e
    bash "$uninstall_mismatch_a/uninstall.sh" >"$uninstall_mismatch_tmp/out" 2>"$uninstall_mismatch_tmp/err"
    status=$?
    [ "$status" -ne 0 ] ||
        fail "uninstall should reject .env or state that points at another install directory"
)
[ -d "$uninstall_mismatch_b" ] ||
    fail "uninstall should not delete an install directory owned by another uninstall.sh"
grep -q '卸载脚本所在目录' "$uninstall_mismatch_tmp/err" ||
    fail "uninstall mismatch error should explain the script directory mismatch"

uninstall_marker_symlink_tmp=$(make_test_tmpdir "clash-uninstall-marker-symlink")
uninstall_marker_symlink_repo="$uninstall_marker_symlink_tmp/repo"
cp -a "$TEST_ROOT/." "$uninstall_marker_symlink_repo"
mkdir -p "$uninstall_marker_symlink_repo/resources"
rm -f "$uninstall_marker_symlink_repo/.env" "$uninstall_marker_symlink_repo/.clashctl-install-root"
printf 'tyx-clash-for-linux-install\n' >"$uninstall_marker_symlink_tmp/marker"
ln -s "$uninstall_marker_symlink_tmp/marker" "$uninstall_marker_symlink_repo/.clashctl-install-root"
cat >"$uninstall_marker_symlink_repo/resources/install-state.yaml" <<EOF
install_dir: "$uninstall_marker_symlink_repo"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
(
    set +e
    bash "$uninstall_marker_symlink_repo/uninstall.sh" >"$uninstall_marker_symlink_tmp/out" 2>"$uninstall_marker_symlink_tmp/err"
    status=$?
    [ "$status" -ne 0 ] ||
        fail "uninstall should reject symlinked install markers"
)
[ -d "$uninstall_marker_symlink_repo" ] ||
    fail "uninstall should not delete install dir when marker is a symlink"

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

assert_file_contains "$COMMON_SH" '建议改 mixin\.yaml 中的 external-controller' \
    "external-controller conflicts should tell users to edit mixin.yaml explicitly"

assert_file_not_contains "$COMMON_SH" 'external-controller = "' \
    "external-controller conflict handling should not rewrite mixin.yaml automatically"

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
