#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

MIGRATE_SH="$TEST_ROOT/migrate.sh"
[ -f "$MIGRATE_SH" ] || fail "migrate.sh should exist for one-shot legacy migrations"

migrate_tmp=$(make_test_tmpdir "clash-migrate")
legacy_dir="$migrate_tmp/legacy"
mkdir -p "$legacy_dir/resources/profiles" "$legacy_dir/scripts/cmd" "$legacy_dir/.github"

cat >"$legacy_dir/.env" <<EOF
CLASH_BASE_DIR=$legacy_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
VERSION_MIHOMO=v-old
VERSION_YQ=v-old
VERSION_SUBCONVERTER=v-old
EOF
printf 'legacy-mixin\n' >"$legacy_dir/resources/mixin.yaml"
printf 'legacy-sidecar\n' >"$legacy_dir/resources/clashctl.yaml"
printf 'legacy-profiles\n' >"$legacy_dir/resources/profiles.yaml"
printf 'legacy-runtime\n' >"$legacy_dir/resources/runtime.yaml"
printf 'legacy-script\n' >"$legacy_dir/scripts/cmd/clashctl.sh"
printf 'stale\n' >"$legacy_dir/placeholder_start1"
printf 'stale\n' >"$legacy_dir/.github/config.yml"
printf 'stale\n' >"$legacy_dir/.editorconfig"

CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$MIGRATE_SH" --target "$legacy_dir" --source "$TEST_ROOT" >/dev/null

[ -f "$legacy_dir/resources/install-state.yaml" ] ||
    fail "migrate should create install-state.yaml"
grep -qx 'install_dir: "'$legacy_dir'"' "$legacy_dir/resources/install-state.yaml" ||
    fail "migrate should write target install_dir"
[ "$(cat "$legacy_dir/config/mixin.yaml")" = "legacy-mixin" ] ||
    fail "migrate should copy legacy mixin.yaml into config/"
[ "$(cat "$legacy_dir/config/clashctl.yaml")" = "legacy-sidecar" ] ||
    fail "migrate should copy legacy clashctl.yaml into config/"
[ "$(cat "$legacy_dir/config/subscriptions.yaml")" = "legacy-profiles" ] ||
    fail "migrate should copy legacy profiles.yaml into config/subscriptions.yaml"
[ "$(cat "$legacy_dir/resources/runtime.yaml")" = "legacy-runtime" ] ||
    fail "migrate should preserve runtime.yaml"
grep -q 'function clashctl' "$legacy_dir/scripts/cmd/clashctl.sh" ||
    fail "migrate should refresh installed command scripts"
[ ! -e "$legacy_dir/placeholder_start1" ] ||
    fail "migrate should remove obsolete placeholder files"
[ ! -e "$legacy_dir/.github" ] ||
    fail "migrate should remove obsolete project metadata directories"
[ ! -e "$legacy_dir/.editorconfig" ] ||
    fail "migrate should remove obsolete project metadata files"

bash "$MIGRATE_SH" --help >/dev/null ||
    fail "migrate should expose a help page"

pass "one-shot migration checks"
