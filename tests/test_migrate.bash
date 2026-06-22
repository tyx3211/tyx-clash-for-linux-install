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
[ -f "$legacy_dir/resources/mixin.yaml" ] ||
    fail "default migration should keep legacy mixin.yaml in resources/"
[ -f "$legacy_dir/resources/clashctl.yaml" ] ||
    fail "default migration should keep legacy clashctl.yaml in resources/"
[ -f "$legacy_dir/resources/profiles.yaml" ] ||
    fail "default migration should keep legacy profiles.yaml in resources/"
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

installed_migrate_tmp="$migrate_tmp/installed-migrate-runner"
installed_migrate_target="$migrate_tmp/installed-migrate-target"
installed_migrate_source_home="$migrate_tmp/installed-migrate-source-home"
installed_migrate_source="$installed_migrate_source_home/source"
mkdir -p "$installed_migrate_tmp" "$installed_migrate_source_home" "$installed_migrate_target/resources" "$installed_migrate_target/scripts/cmd"
cp -a "$TEST_ROOT/." "$installed_migrate_source"
cp "$TEST_ROOT/migrate.sh" "$installed_migrate_tmp/migrate.sh"
cat >"$installed_migrate_target/.env" <<EOF
CLASH_BASE_DIR=$installed_migrate_target
KERNEL_NAME=mihomo
INIT_TYPE=tmux
EOF
printf 'installed-migrate-mixin\n' >"$installed_migrate_target/resources/mixin.yaml"
printf 'legacy-script\n' >"$installed_migrate_target/scripts/cmd/clashctl.sh"
CLASHCTL_MIGRATE_SKIP_STATUS=1 HOME="$installed_migrate_source_home" bash "$installed_migrate_tmp/migrate.sh" --target "$installed_migrate_target" --source '${HOME}/source' >/dev/null ||
    fail "standalone migrate.sh should expand literal \${HOME} in explicit --source before loading helpers"
grep -q 'function clashctl' "$installed_migrate_target/scripts/cmd/clashctl.sh" ||
    fail "standalone migrate.sh with literal \${HOME} --source should refresh target scripts"

auto_target_source="$migrate_tmp/auto-target-source"
auto_target_install="$migrate_tmp/auto-target-install"
mkdir -p "$auto_target_source" "$auto_target_install/resources" "$auto_target_install/scripts/cmd"
cp "$TEST_ROOT/migrate.sh" "$auto_target_source/migrate.sh"
cat >"$auto_target_source/.env" <<EOF
CLASHCTL_HOME=$auto_target_install
EOF
cat >"$auto_target_install/.env" <<EOF
CLASHCTL_HOME=$auto_target_install
CLASHCTL_KERNEL=clash
INIT_TYPE=nohup
EOF
printf 'auto-mixin\n' >"$auto_target_install/resources/mixin.yaml"
printf 'legacy-script\n' >"$auto_target_install/scripts/cmd/clashctl.sh"
CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$auto_target_source/migrate.sh" --source "$TEST_ROOT" >/dev/null ||
    fail "migrate should auto-discover target from local CLASHCTL_HOME"
grep -qx 'kernel_name: "clash"' "$auto_target_install/resources/install-state.yaml" ||
    fail "auto-discovered CLASHCTL_HOME migration should preserve legacy CLASHCTL_KERNEL"

legacy_home_source="$migrate_tmp/legacy-home-source"
legacy_home_target="$migrate_tmp/legacy-home-target"
mkdir -p "$legacy_home_source" "$legacy_home_target/resources" "$legacy_home_target/scripts/cmd"
cat >"$legacy_home_source/.env" <<EOF
CLASHCTL_HOME=$legacy_home_target
EOF
cat >"$legacy_home_target/.env" <<EOF
CLASHCTL_HOME=$legacy_home_target
CLASHCTL_KERNEL=clash
INIT_TYPE=nohup
EOF
printf 'legacy-mixin\n' >"$legacy_home_target/resources/mixin.yaml"
printf 'legacy-script\n' >"$legacy_home_target/scripts/cmd/clashctl.sh"
CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$MIGRATE_SH" --source "$TEST_ROOT" --target "$legacy_home_target" >/dev/null
grep -qx 'kernel_name: "clash"' "$legacy_home_target/resources/install-state.yaml" ||
    fail "migrate should preserve legacy upstream CLASHCTL_KERNEL through update.sh"

legacy_move_dir="$migrate_tmp/legacy-move"
mkdir -p "$legacy_move_dir/resources/profiles" "$legacy_move_dir/scripts/cmd"
cat >"$legacy_move_dir/.env" <<EOF
CLASH_BASE_DIR=$legacy_move_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
EOF
printf 'move-mixin\n' >"$legacy_move_dir/resources/mixin.yaml"
printf 'move-sidecar\n' >"$legacy_move_dir/resources/clashctl.yaml"
printf 'move-profiles\n' >"$legacy_move_dir/resources/profiles.yaml"
printf 'script\n' >"$legacy_move_dir/scripts/cmd/clashctl.sh"

CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$MIGRATE_SH" --target "$legacy_move_dir" --source "$TEST_ROOT" --move-legacy-config >/dev/null

[ "$(cat "$legacy_move_dir/config/mixin.yaml")" = "move-mixin" ] ||
    fail "--move-legacy-config should move mixin.yaml into config/"
[ "$(cat "$legacy_move_dir/config/clashctl.yaml")" = "move-sidecar" ] ||
    fail "--move-legacy-config should move clashctl.yaml into config/"
[ "$(cat "$legacy_move_dir/config/subscriptions.yaml")" = "move-profiles" ] ||
    fail "--move-legacy-config should move profiles.yaml into config/subscriptions.yaml"
[ ! -e "$legacy_move_dir/resources/mixin.yaml" ] ||
    fail "--move-legacy-config should remove legacy resources/mixin.yaml"
[ ! -e "$legacy_move_dir/resources/clashctl.yaml" ] ||
    fail "--move-legacy-config should remove legacy resources/clashctl.yaml"
[ ! -e "$legacy_move_dir/resources/profiles.yaml" ] ||
    fail "--move-legacy-config should remove legacy resources/profiles.yaml"

legacy_conflict_dir="$migrate_tmp/legacy-conflict"
mkdir -p "$legacy_conflict_dir/resources" "$legacy_conflict_dir/config" "$legacy_conflict_dir/scripts/cmd"
cat >"$legacy_conflict_dir/.env" <<EOF
CLASH_BASE_DIR=$legacy_conflict_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
EOF
printf 'legacy-value\n' >"$legacy_conflict_dir/resources/mixin.yaml"
printf 'config-value\n' >"$legacy_conflict_dir/config/mixin.yaml"
printf 'script\n' >"$legacy_conflict_dir/scripts/cmd/clashctl.sh"
CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$MIGRATE_SH" --target "$legacy_conflict_dir" --source "$TEST_ROOT" --move-legacy-config >/dev/null 2>&1 &&
    fail "--move-legacy-config should reject divergent legacy and config files without force"
[ -f "$legacy_conflict_dir/resources/mixin.yaml" ] ||
    fail "failed --move-legacy-config should preserve divergent legacy source"

CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$MIGRATE_SH" --target "$legacy_conflict_dir" --source "$TEST_ROOT" --move-legacy-config --force-remove-legacy-config >/dev/null
[ "$(cat "$legacy_conflict_dir/config/mixin.yaml")" = "config-value" ] ||
    fail "--force-remove-legacy-config should not overwrite existing config/mixin.yaml"
[ ! -e "$legacy_conflict_dir/resources/mixin.yaml" ] ||
    fail "--force-remove-legacy-config should delete divergent legacy source only when explicit"

legacy_default_conflict_dir="$migrate_tmp/legacy-default-conflict"
mkdir -p "$legacy_default_conflict_dir/resources" "$legacy_default_conflict_dir/config" "$legacy_default_conflict_dir/scripts/cmd"
cat >"$legacy_default_conflict_dir/.env" <<EOF
CLASH_BASE_DIR=$legacy_default_conflict_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
EOF
printf 'legacy-value\n' >"$legacy_default_conflict_dir/resources/mixin.yaml"
printf 'config-value\n' >"$legacy_default_conflict_dir/config/mixin.yaml"
printf 'script\n' >"$legacy_default_conflict_dir/scripts/cmd/clashctl.sh"
printf 'stale\n' >"$legacy_default_conflict_dir/placeholder_start1"
CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$MIGRATE_SH" --target "$legacy_default_conflict_dir" --source "$TEST_ROOT" >/dev/null 2>&1 &&
    fail "default migration should reject divergent legacy and config files before update"
[ -e "$legacy_default_conflict_dir/placeholder_start1" ] ||
    fail "failed default migration should not refresh or clean files before config conflict is resolved"

legacy_bad_dest_dir="$migrate_tmp/legacy-bad-dest"
mkdir -p "$legacy_bad_dest_dir/resources" "$legacy_bad_dest_dir/config/mixin.yaml" "$legacy_bad_dest_dir/scripts/cmd"
cat >"$legacy_bad_dest_dir/.env" <<EOF
CLASH_BASE_DIR=$legacy_bad_dest_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
EOF
printf 'legacy-value\n' >"$legacy_bad_dest_dir/resources/mixin.yaml"
printf 'script\n' >"$legacy_bad_dest_dir/scripts/cmd/clashctl.sh"
CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$MIGRATE_SH" --target "$legacy_bad_dest_dir" --source "$TEST_ROOT" >/dev/null 2>&1 &&
    fail "default migration should reject existing non-file config destinations"

legacy_config_symlink_dir="$migrate_tmp/legacy-config-symlink"
legacy_config_symlink_external="$migrate_tmp/legacy-config-symlink-external"
mkdir -p "$legacy_config_symlink_dir/resources" "$legacy_config_symlink_dir/scripts/cmd" "$legacy_config_symlink_external"
cat >"$legacy_config_symlink_dir/.env" <<EOF
CLASH_BASE_DIR=$legacy_config_symlink_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
EOF
printf 'legacy-value\n' >"$legacy_config_symlink_dir/resources/mixin.yaml"
printf 'script\n' >"$legacy_config_symlink_dir/scripts/cmd/clashctl.sh"
printf 'stale\n' >"$legacy_config_symlink_dir/placeholder_start1"
ln -s "$legacy_config_symlink_external" "$legacy_config_symlink_dir/config"
CLASHCTL_MIGRATE_SKIP_STATUS=1 bash "$MIGRATE_SH" --target "$legacy_config_symlink_dir" --source "$TEST_ROOT" >/dev/null 2>&1 &&
    fail "migration should reject a symlink config directory before refreshing scripts"
[ -e "$legacy_config_symlink_dir/placeholder_start1" ] ||
    fail "failed migration with symlink config directory should not refresh or clean files"

pass "one-shot migration checks"
