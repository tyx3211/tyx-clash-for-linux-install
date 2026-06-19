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

pass "update self checks"
