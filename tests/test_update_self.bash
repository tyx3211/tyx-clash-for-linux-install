#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

UPDATE_SH="$TEST_ROOT/update.sh"
CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"

[ -f "$UPDATE_SH" ] || fail "update.sh should provide lossless project updates"

assert_file_contains "$CLASHCTL_SH" 'update-self' \
    "clashctl should expose update-self command"

update_tmp=$(make_test_tmpdir "clash-update-self")
source_dir="$update_tmp/source"
install_dir="$update_tmp/install"
mkdir -p "$source_dir" "$install_dir/resources/profiles" "$install_dir/scripts/cmd"
cp -a "$TEST_ROOT/." "$source_dir"

cat >"$install_dir/.env" <<EOF
CLASH_BASE_DIR=$install_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
CLASH_INSTALLED_INIT_TYPE=tmux
CLASH_CONFIG_URL="user-sub"
URL_GH_PROXY=https://example.invalid
EOF
printf 'tyx-clash-for-linux-install\n' >"$install_dir/.clashctl-install-root"
printf 'user-mixin\n' >"$install_dir/resources/mixin.yaml"
printf 'user-sidecar\n' >"$install_dir/resources/clashctl.yaml"
printf 'user-base\n' >"$install_dir/resources/config.yaml"
printf 'user-runtime\n' >"$install_dir/resources/runtime.yaml"
printf 'user-profiles\n' >"$install_dir/resources/profiles.yaml"
printf 'user-profile-one\n' >"$install_dir/resources/profiles/1.yaml"
printf 'user-log\n' >"$install_dir/resources/mihomo.log"
printf 'old-script\n' >"$install_dir/scripts/cmd/clashctl.sh"

(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$install_dir"
)

[ "$(cat "$install_dir/resources/mixin.yaml")" = "user-mixin" ] ||
    fail "update should preserve mixin.yaml"
[ "$(cat "$install_dir/resources/clashctl.yaml")" = "user-sidecar" ] ||
    fail "update should preserve clashctl.yaml"
[ "$(cat "$install_dir/resources/config.yaml")" = "user-base" ] ||
    fail "update should preserve config.yaml"
[ "$(cat "$install_dir/resources/runtime.yaml")" = "user-runtime" ] ||
    fail "update should preserve runtime.yaml"
[ "$(cat "$install_dir/resources/profiles.yaml")" = "user-profiles" ] ||
    fail "update should preserve profiles.yaml"
[ "$(cat "$install_dir/resources/profiles/1.yaml")" = "user-profile-one" ] ||
    fail "update should preserve profile files"
[ "$(cat "$install_dir/resources/mihomo.log")" = "user-log" ] ||
    fail "update should preserve logs"

grep -q 'function clashctl' "$install_dir/scripts/cmd/clashctl.sh" ||
    fail "update should refresh installed clashctl script"

grep -q '^CLASH_BASE_DIR=' "$install_dir/.env" ||
    fail "update should preserve installed .env"

(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$install_dir" >/dev/null
) || fail "update should succeed when managed docs/tests directories already exist"

legacy_dir="$update_tmp/legacy"
mkdir -p "$legacy_dir/resources" "$legacy_dir/scripts/cmd"
printf 'legacy-mixin\n' >"$legacy_dir/resources/mixin.yaml"
printf 'legacy-script\n' >"$legacy_dir/scripts/cmd/clashctl.sh"
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$legacy_dir" >/dev/null
)
[ "$(cat "$legacy_dir/resources/mixin.yaml")" = "legacy-mixin" ] ||
    fail "legacy migration should preserve mixin.yaml"
[ -f "$legacy_dir/.clashctl-install-root" ] ||
    fail "legacy migration should add install marker"

not_install_dir="$update_tmp/not-install"
mkdir -p "$not_install_dir"
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$not_install_dir"
) >/dev/null 2>&1 && fail "update should reject non-clash directories"

symlink_install_dir="$update_tmp/symlink-install"
symlink_outside="$update_tmp/outside"
mkdir -p "$symlink_install_dir/resources" "$symlink_outside"
printf 'tyx-clash-for-linux-install\n' >"$symlink_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$symlink_install_dir/resources/mixin.yaml"
ln -s "$symlink_outside" "$symlink_install_dir/scripts"
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$symlink_install_dir"
) >/dev/null 2>&1 && fail "update should reject managed paths that are symlinks"

env_source_dir="$update_tmp/env-source"
env_install_dir="$update_tmp/env-install"
cp -a "$TEST_ROOT/." "$env_source_dir"
mkdir -p "$env_install_dir/resources" "$env_install_dir/scripts/cmd"
printf 'tyx-clash-for-linux-install\n' >"$env_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$env_install_dir/resources/mixin.yaml"
printf 'script\n' >"$env_install_dir/scripts/cmd/clashctl.sh"
cat >"$env_source_dir/.env" <<EOF
CLASH_BASE_DIR=$env_install_dir
touch "$update_tmp/env-was-sourced"
EOF
(
    cd "$env_source_dir"
    CLASHCTL_NO_RC=1 bash update.sh >/dev/null
)
[ ! -e "$update_tmp/env-was-sourced" ] ||
    fail "update should parse .env instead of sourcing executable shell code"

legacy_env_dir="$update_tmp/legacy-env"
mkdir -p "$legacy_env_dir/resources" "$legacy_env_dir/scripts/cmd"
printf 'legacy-mixin\n' >"$legacy_env_dir/resources/mixin.yaml"
printf 'legacy-script\n' >"$legacy_env_dir/scripts/cmd/clashctl.sh"
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$legacy_env_dir" >/dev/null
)
grep -qx "CLASH_BASE_DIR=$legacy_env_dir" "$legacy_env_dir/.env" ||
    fail "legacy migration should write .env CLASH_BASE_DIR to the requested target"

legacy_fail_dir="$update_tmp/legacy-fail"
legacy_other_dir="$update_tmp/legacy-other"
mkdir -p "$legacy_fail_dir/resources" "$legacy_fail_dir/scripts/cmd" "$legacy_other_dir"
printf 'legacy-mixin\n' >"$legacy_fail_dir/resources/mixin.yaml"
printf 'legacy-script\n' >"$legacy_fail_dir/scripts/cmd/clashctl.sh"
printf 'CLASH_BASE_DIR=%s\n' "$legacy_other_dir" >"$legacy_fail_dir/.env"
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$legacy_fail_dir"
) >/dev/null 2>&1 && fail "legacy migration should reject .env that points at another directory"
[ ! -e "$legacy_fail_dir/.clashctl-install-root" ] ||
    fail "failed legacy migration should not leave a new install marker"

explicit_source_dir="$update_tmp/explicit-source"
explicit_install_dir="$update_tmp/explicit-install"
cp -a "$TEST_ROOT/." "$explicit_source_dir"
mkdir -p "$explicit_install_dir/resources" "$explicit_install_dir/scripts/cmd"
printf 'tyx-clash-for-linux-install\n' >"$explicit_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$explicit_install_dir/resources/mixin.yaml"
cp "$TEST_ROOT/update.sh" "$explicit_install_dir/update.sh"
cat >"$explicit_install_dir/.env" <<EOF
CLASH_BASE_DIR=$explicit_install_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
EOF
printf 'old installed script\n' >"$explicit_install_dir/scripts/cmd/clashctl.sh"
printf '\n# explicit-source-marker\n' >>"$explicit_source_dir/scripts/cmd/clashctl.sh"
bash "$explicit_install_dir/update.sh" --target "$explicit_install_dir" --source "$explicit_source_dir" >/dev/null 2>&1 ||
    fail "installed update.sh should accept an explicit source directory"
grep -q 'explicit-source-marker' "$explicit_install_dir/scripts/cmd/clashctl.sh" ||
    fail "update --source should refresh files from the explicit source directory"

pass "update self checks"
