#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

bootstrap_tmp=$(make_test_tmpdir "clash-install-bootstrap")
bootstrap_source="$bootstrap_tmp/source"
bootstrap_home="$bootstrap_tmp/home"
cp -a "$TEST_ROOT/." "$bootstrap_source"
mkdir -p "$bootstrap_home"
HOME="$bootstrap_home" bash "$bootstrap_source/install.sh" --help \
    >"$bootstrap_tmp/help.out" 2>"$bootstrap_tmp/help.err" ||
    fail "install --help should work before an installed yq exists"
! grep -q 'missing executable yq' "$bootstrap_tmp/help.err" ||
    fail "install bootstrap should not source runtime yq validation before dependencies are installed"
! grep -q 'command not found' "$bootstrap_tmp/help.err" ||
    fail "install bootstrap should define install helpers before preflight uses them"
grep -q 'Usage:' "$bootstrap_tmp/help.out" ||
    fail "install --help should still show usage during bootstrap"

grep -q 'CLASH_INSTALL_SERVICE_TOUCHED=true' "$TEST_ROOT/install.sh" ||
    fail "install should mark service setup as touched before rendering system service"
grep -q '_uninstall_service' "$TEST_ROOT/scripts/preflight.sh" ||
    fail "incomplete install cleanup should try to remove a partially installed service"
grep -q 'CLASH_INSTALL_RC_TOUCHED=true' "$TEST_ROOT/install.sh" ||
    fail "install should mark shell rc setup as touched before applying rc snippets"
grep -q '_revoke_rc' "$TEST_ROOT/scripts/preflight.sh" ||
    fail "incomplete install cleanup should revoke partially applied shell rc snippets"

bad_marker_tmp=$(make_test_tmpdir "clash-install-bad-marker")
bad_marker_source="$bad_marker_tmp/source"
cp -a "$TEST_ROOT/." "$bad_marker_source"
rm -f "$bad_marker_source/bin/yq"
printf '%s\n' 'broken-marker' >"$bad_marker_source/.clashctl-install-root"
HOME="$bad_marker_tmp/home" bash "$bad_marker_source/install.sh" --help \
    >"$bad_marker_tmp/help.out" 2>"$bad_marker_tmp/help.err" &&
    fail "install bootstrap should reject any existing install marker before yq is installed"
grep -q 'missing executable yq' "$bad_marker_tmp/help.err" ||
    fail "bad marker install bootstrap rejection should still require installed yq"

broken_marker_tmp=$(make_test_tmpdir "clash-install-broken-marker")
broken_marker_source="$broken_marker_tmp/source"
cp -a "$TEST_ROOT/." "$broken_marker_source"
rm -f "$broken_marker_source/bin/yq"
ln -s "$broken_marker_tmp/missing-marker-target" "$broken_marker_source/.clashctl-install-root"
HOME="$broken_marker_tmp/home" bash "$broken_marker_source/install.sh" --help \
    >"$broken_marker_tmp/help.out" 2>"$broken_marker_tmp/help.err" &&
    fail "install bootstrap should reject a broken symlink install marker before yq is installed"
grep -q 'missing executable yq' "$broken_marker_tmp/help.err" ||
    fail "broken marker install bootstrap rejection should still require installed yq"

render_mode() {
    local mode=$1
    local tmp source_dir install_dir

    tmp=$(make_test_tmpdir "clash-render-${mode}")
    source_dir="${tmp}/source"
    install_dir="${tmp}/install"
    mkdir -p "$install_dir"
    cp -a "$TEST_ROOT/." "$source_dir"
    cp -a "$source_dir/." "$install_dir"

    (
        set +u
        cd "$source_dir"
        . scripts/cmd/clashctl.sh
        . scripts/preflight.sh

        INIT_TYPE=$mode
        KERNEL_NAME=mihomo
        CLASH_BASE_DIR=$install_dir
        _refresh_install_paths
        _detect_init
        _install_service || true
    ) >/dev/null

    bash -n "$install_dir/scripts/cmd/clashctl.sh"
    bash -n "$install_dir/scripts/cmd/common.sh"
    ! grep -Eq '"" \\| (tmux|nohup|systemd)\\)' "$install_dir/scripts/cmd/clashctl.sh" ||
        fail "rendered ${mode} script should not replace the unset init sentinel in case patterns"
}

render_mode tmux
render_mode nohup

pass "rendered install scripts"
