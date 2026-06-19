#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

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
