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
PATH_ENV_SH="$TEST_ROOT/scripts/lib/path-env.sh"
RC_SH="$TEST_ROOT/scripts/install/rc.sh"

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

assert_file_not_contains "$PREFLIGHT_SH" '--insecure' \
    "dependency downloads should not disable TLS certificate verification by default"

assert_file_not_contains "$COMMON_SH" '--no-check-certificate|--insecure' \
    "subscription downloads should not disable TLS certificate verification by default"

assert_file_contains "$PREFLIGHT_SH" '_normalize_sudo_install_path\(\)' \
    "regular sudo systemd install should normalize default /root path back to invoking user home"

assert_file_contains "$UNINSTALL_SH" '_normalize_sudo_uninstall_path\(\)' \
    "regular sudo uninstall should normalize default /root path back to invoking user home before checking install dir"

assert_file_contains "$UNINSTALL_SH" '_normalize_sudo_uninstall_path' \
    "uninstall should call sudo path normalization before resolving CLASH_BASE_DIR"

assert_file_contains "$PREFLIGHT_SH" '_refresh_install_paths\(\)' \
    "command-line kernel/path overrides should refresh derived install paths"

env_override_tmp=$(make_test_tmpdir "clash-env-override")
write_test_install_yq "$env_override_tmp/custom-install"
(
    THIS_SCRIPT_DIR="$TEST_ROOT/scripts/cmd"
    CLASH_BASE_DIR="$env_override_tmp/custom-install"
    . "$COMMON_SH"
    [ "$CLASH_BASE_DIR" = "$env_override_tmp/custom-install" ] ||
        fail "explicit CLASH_BASE_DIR environment override should win over .env defaults"
)

tilde_env_tmp=$(make_test_tmpdir "clash-tilde-env")
tilde_env_repo="$tilde_env_tmp/repo"
tilde_home="$tilde_env_tmp/home"
mkdir -p "$tilde_home" "$tilde_env_repo"
write_test_install_yq "$tilde_home/clashctl"
cp -a "$TEST_ROOT/scripts" "$tilde_env_repo/scripts"
cat >"$tilde_env_repo/.env" <<'EOF'
KERNEL_NAME=mihomo
CLASH_BASE_DIR=~/clashctl
CLASH_CONFIG_URL=""
INIT_TYPE=tmux
URL_CLASH_UI=http://board.example.invalid
CLASH_SUB_UA=test-agent
EOF
(
    set +e
    HOME="$tilde_home"
    unset_test_install_identity
    . "$tilde_env_repo/scripts/cmd/clashctl.sh" || exit 1
    [ "$CLASH_BASE_DIR" = "$tilde_home/clashctl" ] ||
        fail "literal ~/ in .env CLASH_BASE_DIR should expand to HOME without keeping a literal tilde: $CLASH_BASE_DIR"
)
(
    set +e
    HOME="$tilde_home"
    . "$TEST_ROOT/scripts/lib/install-state.sh" || exit 1
    [ "$(_install_state_expand_path "~/state")" = "$tilde_home/state" ] ||
        fail "install-state path expansion should strip literal ~/ before prefixing HOME"
    [ "$(_install_state_expand_path '${HOME}/state')" = "$tilde_home/state" ] ||
        fail "install-state path expansion should support literal \${HOME}/ prefixes"
)
bad_tilde_pattern='${path#~/}'
! grep -R -nF "$bad_tilde_pattern" \
    "$TEST_ROOT/scripts" \
    "$TEST_ROOT/update.sh" \
    "$TEST_ROOT/migrate.sh" \
    "$TEST_ROOT/uninstall.sh" ||
    fail "path expansion must escape literal tilde in parameter removal patterns"

assert_file_contains "$PREFLIGHT_SH" '\[\!A-Za-z0-9_\./-\]' \
    "install path validation should reject shell metacharacters"

path_expand_tmp=$(make_test_tmpdir "clash-path-expand")
(
    set +e
    HOME="$path_expand_tmp/home"
    mkdir -p "$HOME"
    . "$PATH_ENV_SH"
    [ "$(_path_env_expand_path '${HOME}/clashctl')" = "$HOME/clashctl" ] ||
        fail "shared path expansion should support literal \${HOME}/ prefixes"
)

sudo_path_tmp=$(make_test_tmpdir "clash-sudo-path")
(
    set +e
    . "$PREFLIGHT_SH"

    sudo_home=$(awk -F: -v user="$(id -un)" '$1==user{print $6}' /etc/passwd)
    [ -n "$sudo_home" ] || fail "test should resolve current user home from passwd"
    SUDO_USER=$(id -un)
    _is_regular_sudo() { return 0; }

    CLASH_BASE_DIR=/root
    _normalize_sudo_install_path
    [ "$CLASH_BASE_DIR" = /root ] ||
        fail "sudo install normalization should not map /root itself to the sudo user home"

    CLASH_BASE_DIR=/root/clashctl
    _normalize_sudo_install_path
    [ "$CLASH_BASE_DIR" = "$sudo_home/clashctl" ] ||
        fail "sudo install normalization should map /root child paths to the sudo user home"
)

sudo_uninstall_path_tmp=$(make_test_tmpdir "clash-sudo-uninstall-path")
(
    set +e
    _uninstall_die() { return 97; }
    eval "$(extract_function "_uninstall_is_regular_sudo" "$UNINSTALL_SH")"
    eval "$(extract_function "_normalize_sudo_uninstall_path" "$UNINSTALL_SH")"

    sudo_home=$(awk -F: -v user="$(id -un)" '$1==user{print $6}' /etc/passwd)
    [ -n "$sudo_home" ] || fail "test should resolve current user home from passwd"
    SUDO_USER=$(id -un)
    id() {
        if [ "${1:-}" = -u ]; then
            printf '0\n'
            return 0
        fi
        command id "$@"
    }

    CLASH_BASE_DIR=/root
    _normalize_sudo_uninstall_path
    [ "$CLASH_BASE_DIR" = /root ] ||
        fail "sudo uninstall normalization should not map /root itself to the sudo user home"

    CLASH_BASE_DIR=/root/clashctl
    _normalize_sudo_uninstall_path
    [ "$CLASH_BASE_DIR" = "$sudo_home/clashctl" ] ||
        fail "sudo uninstall normalization should map /root child paths to the sudo user home"
)

archive_safe_tmp=$(make_test_tmpdir "clash-archive-safe")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    mkdir -p "$archive_safe_tmp/src" "$archive_safe_tmp/out"
    printf 'good\n' >"$archive_safe_tmp/src/good.txt"
    tar -C "$archive_safe_tmp/src" -czf "$archive_safe_tmp/good.tar.gz" good.txt
    _tar_archive_is_safe "$archive_safe_tmp/good.tar.gz" ||
        fail "safe tar archive should be accepted"

    tar -C "$archive_safe_tmp/src" --transform='s#good.txt#dir/../../escape.txt#' -czf "$archive_safe_tmp/evil.tar.gz" good.txt >/dev/null 2>&1
    _tar_archive_is_safe "$archive_safe_tmp/evil.tar.gz" &&
        fail "tar archive with parent traversal members should be rejected"

    if command -v zip >/dev/null; then
        ln -s good.txt "$archive_safe_tmp/src/link.txt"
        (cd "$archive_safe_tmp/src" && zip -y "$archive_safe_tmp/link.zip" link.txt >/dev/null)
        _zip_archive_is_safe "$archive_safe_tmp/link.zip" &&
            fail "zip archive with symlink members should be rejected"
    fi

    fake_unzip_dir="$archive_safe_tmp/fake-bin"
    mkdir -p "$fake_unzip_dir"
    cat >"$fake_unzip_dir/unzip" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
"-Z -1")
    case "${ZIP_FAKE_MODE:-good}" in
    path_traverse) printf '../escape.txt\n' ;;
    *) printf 'good.txt\n' ;;
    esac
    ;;
"-Z -l")
    case "${ZIP_FAKE_MODE:-good}" in
    fail_long)
        exit 9
        ;;
    unknown_long)
        printf 'mystery listing format\n'
        ;;
    special_long)
        printf 'Archive: fake.zip\n'
        printf 'Zip file size: 1 bytes, number of entries: 1\n'
        printf 'crw-r--r--  3.0 unx        0 bx        0 stor 26-Jun-22 00:00 node\n'
        printf '1 file, 0 bytes uncompressed, 0 bytes compressed:  0.0%%\n'
        ;;
    *)
        printf 'Archive: fake.zip\n'
        printf 'Zip file size: 1 bytes, number of entries: 1\n'
        printf -- '-rw-------  3.0 unx        1 tx        1 stor 26-Jun-22 00:00 good.txt\n'
        printf '1 file, 1 bytes uncompressed, 1 bytes compressed:  0.0%%\n'
        ;;
    esac
    ;;
*)
    exit 1
    ;;
esac
EOF
    chmod +x "$fake_unzip_dir/unzip"
    PATH="$fake_unzip_dir:$PATH" ZIP_FAKE_MODE=good _zip_archive_is_safe "$archive_safe_tmp/fake.zip" ||
        fail "zip archive checker should accept ordinary files with known unzip listing format"
    PATH="$fake_unzip_dir:$PATH" ZIP_FAKE_MODE=fail_long _zip_archive_is_safe "$archive_safe_tmp/fake.zip" &&
        fail "zip archive checker should fail closed when long listing fails"
    PATH="$fake_unzip_dir:$PATH" ZIP_FAKE_MODE=unknown_long _zip_archive_is_safe "$archive_safe_tmp/fake.zip" &&
        fail "zip archive checker should reject unknown long listing formats"
    PATH="$fake_unzip_dir:$PATH" ZIP_FAKE_MODE=path_traverse _zip_archive_is_safe "$archive_safe_tmp/fake.zip" &&
        fail "zip archive checker should reject parent traversal members"
    PATH="$fake_unzip_dir:$PATH" ZIP_FAKE_MODE=special_long _zip_archive_is_safe "$archive_safe_tmp/fake.zip" &&
        fail "zip archive checker should reject special-file members"

    if _archive_member_path_is_safe "../escape.txt"; then
        fail "archive member path validator should reject parent traversal"
    fi
)

file_url_tmp=$(make_test_tmpdir "clash-install-file-url")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    CLASH_CONFIG_URL=
    _parse_args file://"$file_url_tmp/config.yaml"
    [ "$CLASH_CONFIG_URL" = "file://$file_url_tmp/config.yaml" ] ||
        fail "install argument parsing should accept file:// subscription or config URLs"
)

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
write_test_install_yq "$uninstall_state_repo"
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
write_test_install_yq "$uninstall_bad_kernel_repo"
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
write_test_install_yq "$uninstall_marker_symlink_repo"
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

assert_file_contains "$RC_SH" '_revoke_rc_file' \
    "rc cleanup should be scoped to the current install block"

assert_file_not_contains "$RC_SH" '/\$start_flag/,/\$end_flag/d' \
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
