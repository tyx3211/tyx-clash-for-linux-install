#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

INSTALL_SH="$TEST_ROOT/install.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
UPDATE_SH="$TEST_ROOT/update.sh"

config_git_tmp=$(make_test_tmpdir "clash-config-git")

install_payload_source="$config_git_tmp/source"
install_payload_target="$config_git_tmp/target"
cp -a "$TEST_ROOT/." "$install_payload_source"
mkdir -p "$install_payload_target"
(
    THIS_INSTALL_DIR="$install_payload_source"
    CLASH_BASE_DIR="$install_payload_target"
    eval "$(extract_function _copy_install_payload "$INSTALL_SH")"
    _copy_install_payload
) || fail "install payload copy with config directory should succeed"
[ -f "$install_payload_target/config/mixin.yaml" ] ||
    fail "install payload should include config/mixin.yaml"
[ -f "$install_payload_target/config/clashctl.yaml" ] ||
    fail "install payload should include config/clashctl.yaml"
[ -f "$install_payload_target/config/subscriptions.yaml" ] ||
    fail "install payload should include config/subscriptions.yaml"
grep -qx 'external-controller: "127.0.0.1:9090"' "$install_payload_target/config/mixin.yaml" ||
    fail "new install default controller port should be 9090"
[ ! -e "$install_payload_target/resources/mixin.yaml" ] ||
    fail "new install payload should keep editable mixin config out of resources"
[ ! -e "$install_payload_target/resources/clashctl.yaml" ] ||
    fail "new install payload should keep editable clashctl config out of resources"
[ ! -e "$install_payload_target/resources/profiles.yaml" ] ||
    fail "new install payload should keep subscription metadata out of resources"

install_symlink_source="$config_git_tmp/source-symlink"
install_symlink_target="$config_git_tmp/target-symlink"
install_symlink_outside="$config_git_tmp/outside-config"
cp -a "$TEST_ROOT/." "$install_symlink_source"
mkdir -p "$install_symlink_target" "$install_symlink_outside"
rm -rf "$install_symlink_source/config"
ln -s "$install_symlink_outside" "$install_symlink_source/config"
(
    THIS_INSTALL_DIR="$install_symlink_source"
    CLASH_BASE_DIR="$install_symlink_target"
    eval "$(extract_function _copy_install_payload "$INSTALL_SH")"
    _copy_install_payload
) >/dev/null 2>&1 && fail "install payload should reject symlinked config directory"
[ ! -L "$install_symlink_target/config" ] ||
    fail "install payload should not install symlinked config directory"

new_layout="$config_git_tmp/new-layout"
mkdir -p "$new_layout"
cp -a "$TEST_ROOT/scripts" "$new_layout/scripts"
mkdir -p "$new_layout/config" "$new_layout/resources"
write_test_install_yq "$new_layout"
cat >"$new_layout/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$new_layout
CLASH_CONFIG_URL=""
INIT_TYPE=tmux
URL_CLASH_UI=http://board.example.invalid
CLASH_SUB_UA=test-agent
EOF
printf 'new-mixin\n' >"$new_layout/config/mixin.yaml"
printf 'new-sidecar\n' >"$new_layout/config/clashctl.yaml"
printf 'new-subscriptions\n' >"$new_layout/config/subscriptions.yaml"
printf 'legacy-mixin\n' >"$new_layout/resources/mixin.yaml"
printf 'legacy-sidecar\n' >"$new_layout/resources/clashctl.yaml"
printf 'legacy-profiles\n' >"$new_layout/resources/profiles.yaml"
(
    set +e
    unset_test_install_identity
    . "$new_layout/scripts/cmd/clashctl.sh" || exit 1
    [ "$CLASH_CONFIG_MIXIN" = "$new_layout/config/mixin.yaml" ] ||
        fail "clashctl should prefer config/mixin.yaml when present"
    [ "$CLASH_CONFIG_SIDECAR" = "$new_layout/config/clashctl.yaml" ] ||
        fail "clashctl should prefer config/clashctl.yaml when present"
    [ "$CLASH_PROFILES_META" = "$new_layout/config/subscriptions.yaml" ] ||
        fail "clashctl should prefer config/subscriptions.yaml when present"
)

legacy_layout="$config_git_tmp/legacy-layout"
mkdir -p "$legacy_layout"
cp -a "$TEST_ROOT/scripts" "$legacy_layout/scripts"
mkdir -p "$legacy_layout/resources"
write_test_install_yq "$legacy_layout"
cat >"$legacy_layout/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$legacy_layout
CLASH_CONFIG_URL=""
INIT_TYPE=tmux
URL_CLASH_UI=http://board.example.invalid
CLASH_SUB_UA=test-agent
EOF
printf 'legacy-mixin\n' >"$legacy_layout/resources/mixin.yaml"
printf 'legacy-sidecar\n' >"$legacy_layout/resources/clashctl.yaml"
printf 'legacy-profiles\n' >"$legacy_layout/resources/profiles.yaml"
(
    set +e
    unset_test_install_identity
    . "$legacy_layout/scripts/cmd/clashctl.sh" || exit 1
    [ "$CLASH_CONFIG_MIXIN" = "$legacy_layout/resources/mixin.yaml" ] ||
        fail "legacy installs should keep using resources/mixin.yaml"
    [ "$CLASH_CONFIG_SIDECAR" = "$legacy_layout/resources/clashctl.yaml" ] ||
        fail "legacy installs should keep using resources/clashctl.yaml"
    [ "$CLASH_PROFILES_META" = "$legacy_layout/resources/profiles.yaml" ] ||
        fail "legacy installs should keep using resources/profiles.yaml"
)

env_override_layout="$config_git_tmp/env-override"
mkdir -p "$env_override_layout"
cp -a "$TEST_ROOT/scripts" "$env_override_layout/scripts"
mkdir -p "$env_override_layout/config"
write_test_install_yq "$env_override_layout"
cat >"$env_override_layout/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$env_override_layout
CLASH_CONFIG_URL=""
INIT_TYPE=tmux
CLASHCTL_CONFIG_GIT=0
URL_CLASH_UI=http://board.example.invalid
CLASH_SUB_UA=test-agent
EOF
(
    set +e
    unset_test_install_identity
    CLASHCTL_CONFIG_GIT=1
    . "$env_override_layout/scripts/cmd/clashctl.sh" || exit 1
    [ "$CLASHCTL_CONFIG_GIT" = 1 ] ||
        fail "explicit CLASHCTL_CONFIG_GIT environment override should win over .env"
)

assert_file_contains "$PREFLIGHT_SH" '--config-git|CLASHCTL_CONFIG_GIT' \
    "install should expose an install-time config git option and environment switch"

parse_args_tmp="$config_git_tmp/parse-args"
mkdir -p "$parse_args_tmp"
(
    set +e
    . "$TEST_ROOT/scripts/cmd/clashctl.sh"
    . "$PREFLIGHT_SH"

    CLASH_BASE_DIR="$parse_args_tmp/install"
    CLASHCTL_CONFIG_GIT=0
    _parse_args --config-git
    [ "$CLASHCTL_CONFIG_GIT" = 1 ] ||
        fail "--config-git should enable config git initialization"

    CLASHCTL_CONFIG_GIT=1
    _parse_args --no-config-git
    [ "$CLASHCTL_CONFIG_GIT" = 0 ] ||
        fail "--no-config-git should disable config git initialization"
)

init_git_tmp="$config_git_tmp/init-git"
mkdir -p "$init_git_tmp/install/config" "$init_git_tmp/bin"
printf 'mixin\n' >"$init_git_tmp/install/config/mixin.yaml"
cat >"$init_git_tmp/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_SEEN"
if [ "$1" = init ]; then
    mkdir -p .git
fi
EOF
chmod +x "$init_git_tmp/bin/git"
(
    set +e
    . "$TEST_ROOT/scripts/cmd/clashctl.sh"
    . "$PREFLIGHT_SH"

    CLASH_BASE_DIR="$init_git_tmp/install"
    CLASH_CONFIG_DIR="$init_git_tmp/install/config"
    CLASHCTL_CONFIG_GIT=1
    export GIT_SEEN="$init_git_tmp/git.seen"
    PATH="$init_git_tmp/bin:$PATH"
    _init_config_git || exit 1
    [ -d "$CLASH_CONFIG_DIR/.git" ] ||
        fail "config git initialization should create .git under config directory"
)
grep -qx 'init' "$init_git_tmp/git.seen" ||
    fail "config git initialization should call git init"

init_git_symlink_tmp="$config_git_tmp/init-git-symlink"
mkdir -p "$init_git_symlink_tmp/install" "$init_git_symlink_tmp/outside"
ln -s "$init_git_symlink_tmp/outside" "$init_git_symlink_tmp/install/config"
(
    set +e
    . "$TEST_ROOT/scripts/cmd/clashctl.sh"
    . "$PREFLIGHT_SH"

    CLASHCTL_ERROR_EXIT=1
    CLASH_BASE_DIR="$init_git_symlink_tmp/install"
    CLASH_CONFIG_DIR="$init_git_symlink_tmp/install/config"
    CLASHCTL_CONFIG_GIT=1
    _init_config_git
) >/dev/null 2>&1 && fail "config git initialization should reject symlinked config directory"
[ ! -d "$init_git_symlink_tmp/outside/.git" ] ||
    fail "config git initialization should not follow config symlinks outside install dir"

install_state_tmp="$config_git_tmp/install-state"
(
    set +e
    . "$TEST_ROOT/scripts/cmd/clashctl.sh"
    . "$PREFLIGHT_SH"

    CLASH_BASE_DIR="$install_state_tmp/install"
    KERNEL_NAME=mihomo
    INIT_TYPE=nohup
    CLASH_INSTALLED_INIT_TYPE=nohup
    VERSION_MIHOMO=v1.2.3
    VERSION_YQ=v4.5.6
    VERSION_SUBCONVERTER=v0.9.0
    _refresh_install_paths
    mkdir -p "$CLASH_BASE_DIR" "$CLASH_RESOURCES_DIR"
    write_test_install_yq "$CLASH_BASE_DIR"
    cp "$TEST_ROOT/.env" "$CLASH_BASE_DIR/.env"

    _set_envs
    [ -f "$CLASH_RESOURCES_DIR/install-state.yaml" ] ||
        fail "_set_envs should write resources/install-state.yaml"
    grep -qx 'install_dir: "'$CLASH_BASE_DIR'"' "$CLASH_RESOURCES_DIR/install-state.yaml" ||
        fail "install-state.yaml should record the canonical install directory"
    grep -qx 'kernel_name: "mihomo"' "$CLASH_RESOURCES_DIR/install-state.yaml" ||
        fail "install-state.yaml should record kernel_name"
    grep -qx 'default_mode: "nohup"' "$CLASH_RESOURCES_DIR/install-state.yaml" ||
        fail "install-state.yaml should record default_mode"
    grep -qx 'installed_systemd_service: false' "$CLASH_RESOURCES_DIR/install-state.yaml" ||
        fail "install-state.yaml should record whether systemd was installed"
)

sudo_systemd_state_tmp="$config_git_tmp/sudo-systemd-state"
(
    set +e
    . "$TEST_ROOT/scripts/cmd/clashctl.sh"
    . "$PREFLIGHT_SH"

    fake_sudo_home="$sudo_systemd_state_tmp/home"
    mkdir -p "$fake_sudo_home"
    SUDO_USER=clash_sudo_user
    awk() {
        if [ "${1:-}" = -F: ]; then
            printf '%s\n' "$fake_sudo_home"
            return 0
        fi
        command awk "$@"
    }
    _is_regular_sudo() { return 0; }
    _error_quit() { fail "$*"; }

    CLASH_BASE_DIR=/root/clashctl
    KERNEL_NAME=mihomo
    INIT_TYPE=systemd
    CLASH_INSTALLED_INIT_TYPE=systemd
    VERSION_MIHOMO=v1.2.3
    VERSION_YQ=v4.53.3
    VERSION_SUBCONVERTER=v0.9.0

    _normalize_sudo_install_path
    _refresh_install_paths
    mkdir -p "$CLASH_BASE_DIR" "$CLASH_RESOURCES_DIR"
    write_test_install_yq "$CLASH_BASE_DIR"
    cp "$TEST_ROOT/.env" "$CLASH_BASE_DIR/.env"

    _set_envs
    grep -qx 'CLASH_BASE_DIR='"$fake_sudo_home"'/clashctl' "$CLASH_BASE_DIR/.env" ||
        fail "sudo systemd install should persist the invoking user install dir instead of /root or ~"
    grep -qx 'install_dir: "'$fake_sudo_home'/clashctl"' "$CLASH_RESOURCES_DIR/install-state.yaml" ||
        fail "sudo systemd install-state should record an absolute invoking-user path"
    ! grep -Eq '(^|[" ])~|/root/clashctl' "$CLASH_BASE_DIR/.env" "$CLASH_RESOURCES_DIR/install-state.yaml" ||
        fail "sudo systemd persisted install metadata should not contain ~ or /root/clashctl"
)

update_source="$config_git_tmp/update-source"
update_target="$config_git_tmp/update-target"
cp -a "$TEST_ROOT/." "$update_source"
mkdir -p "$update_target/resources" "$update_target/scripts/cmd" "$update_target/config/.git"
write_test_install_yq "$update_target"
printf 'tyx-clash-for-linux-install\n' >"$update_target/.clashctl-install-root"
cat >"$update_target/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$update_target
INIT_TYPE=tmux
EOF
printf 'script\n' >"$update_target/scripts/cmd/clashctl.sh"
printf 'mixin\n' >"$update_target/resources/mixin.yaml"
printf 'user-config\n' >"$update_target/config/mixin.yaml"
printf 'config-git\n' >"$update_target/config/.git/config"
bash "$UPDATE_SH" --target "$update_target" --source "$update_source" >/dev/null 2>&1 ||
    fail "update should succeed when config directory contains a user git repository"
[ "$(cat "$update_target/config/mixin.yaml")" = "user-config" ] ||
    fail "update should preserve user config/mixin.yaml"
[ "$(cat "$update_target/config/.git/config")" = "config-git" ] ||
    fail "update should preserve config directory git metadata"

pass "config directory and optional git behavior"
