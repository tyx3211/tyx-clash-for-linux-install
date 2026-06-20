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
cat >"$install_dir/resources/install-state.yaml" <<EOF
install_dir: "$install_dir"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
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
grep -qx 'install_dir: "'$install_dir'"' "$install_dir/resources/install-state.yaml" ||
    fail "update should preserve an existing install-state.yaml"
[ "$(cat "$install_dir/resources/profiles.yaml")" = "user-profiles" ] ||
    fail "update should preserve profiles.yaml"
[ "$(cat "$install_dir/resources/profiles/1.yaml")" = "user-profile-one" ] ||
    fail "update should preserve profile files"
[ "$(cat "$install_dir/resources/mihomo.log")" = "user-log" ] ||
    fail "update should preserve logs"

grep -q 'function clashctl' "$install_dir/scripts/cmd/clashctl.sh" ||
    fail "update should refresh installed clashctl script"

[ ! -e "$install_dir/.git" ] ||
    fail "update should not create .git in install dir when source is a git checkout"

grep -q '^CLASH_BASE_DIR=' "$install_dir/.env" ||
    fail "update should preserve installed .env"

state_install_dir="$update_tmp/state-install"
mkdir -p "$state_install_dir/resources" "$state_install_dir/scripts/cmd"
printf 'tyx-clash-for-linux-install\n' >"$state_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$state_install_dir/resources/mixin.yaml"
printf 'script\n' >"$state_install_dir/scripts/cmd/clashctl.sh"
rm -f "$state_install_dir/.env"
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$state_install_dir" >/dev/null
)
[ -f "$state_install_dir/resources/install-state.yaml" ] ||
    fail "update should create install-state.yaml when .env is absent"
grep -qx 'install_dir: "'$state_install_dir'"' "$state_install_dir/resources/install-state.yaml" ||
    fail "generated install-state.yaml should record update target"
[ ! -e "$state_install_dir/.env" ] ||
    fail "update should not recreate .env when the target already uses install-state.yaml"

state_mismatch_install_dir="$update_tmp/state-mismatch-install"
state_mismatch_other_dir="$update_tmp/state-mismatch-other"
mkdir -p "$state_mismatch_install_dir/resources" "$state_mismatch_install_dir/scripts/cmd" "$state_mismatch_other_dir"
printf 'tyx-clash-for-linux-install\n' >"$state_mismatch_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$state_mismatch_install_dir/resources/mixin.yaml"
printf 'script\n' >"$state_mismatch_install_dir/scripts/cmd/clashctl.sh"
cat >"$state_mismatch_install_dir/resources/install-state.yaml" <<EOF
install_dir: "$state_mismatch_other_dir"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$state_mismatch_install_dir"
) >/dev/null 2>&1 && fail "update should reject install-state.yaml that points at another directory"
grep -qx 'script' "$state_mismatch_install_dir/scripts/cmd/clashctl.sh" ||
    fail "rejected install-state mismatch should not refresh target scripts"

state_bad_kernel_install_dir="$update_tmp/state-bad-kernel-install"
mkdir -p "$state_bad_kernel_install_dir/resources" "$state_bad_kernel_install_dir/scripts/cmd"
printf 'tyx-clash-for-linux-install\n' >"$state_bad_kernel_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$state_bad_kernel_install_dir/resources/mixin.yaml"
printf 'script\n' >"$state_bad_kernel_install_dir/scripts/cmd/clashctl.sh"
cat >"$state_bad_kernel_install_dir/resources/install-state.yaml" <<EOF
install_dir: "$state_bad_kernel_install_dir"
kernel_name: "../../tmp/evil"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$state_bad_kernel_install_dir"
) >/dev/null 2>&1 && fail "update should reject an existing install-state.yaml with invalid kernel_name"
grep -qx 'script' "$state_bad_kernel_install_dir/scripts/cmd/clashctl.sh" ||
    fail "rejected invalid kernel state should not refresh target scripts"

(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$install_dir" >/dev/null
) || fail "update should succeed when managed docs/tests directories already exist"

legacy_dir="$update_tmp/legacy"
mkdir -p "$legacy_dir/resources" "$legacy_dir/scripts/cmd"
printf 'legacy-mixin\n' >"$legacy_dir/resources/mixin.yaml"
printf 'legacy-script\n' >"$legacy_dir/scripts/cmd/clashctl.sh"
printf 'stale\n' >"$legacy_dir/placeholder_start1"
mkdir -p "$legacy_dir/.github"
printf 'stale\n' >"$legacy_dir/.github/config.yml"
printf 'stale\n' >"$legacy_dir/.editorconfig"
(
    cd "$source_dir"
    CLASHCTL_NO_RC=1 bash update.sh --target "$legacy_dir" >/dev/null
)
[ "$(cat "$legacy_dir/resources/mixin.yaml")" = "legacy-mixin" ] ||
    fail "legacy migration should preserve mixin.yaml"
[ -f "$legacy_dir/.clashctl-install-root" ] ||
    fail "legacy migration should add install marker"
[ ! -e "$legacy_dir/placeholder_start1" ] ||
    fail "legacy migration should remove obsolete placeholder files"
[ ! -e "$legacy_dir/.github" ] ||
    fail "legacy migration should remove obsolete project metadata directories"
[ ! -e "$legacy_dir/.editorconfig" ] ||
    fail "legacy migration should remove obsolete project metadata files"

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
[ -f "$legacy_env_dir/resources/install-state.yaml" ] ||
    fail "legacy migration should write install-state.yaml"
grep -qx 'install_dir: "'$legacy_env_dir'"' "$legacy_env_dir/resources/install-state.yaml" ||
    fail "legacy migration should write install-state.yaml install_dir to the requested target"
grep -qx 'default_mode: "tmux"' "$legacy_env_dir/resources/install-state.yaml" ||
    fail "legacy migration should keep tmux as the default mode"
[ ! -e "$legacy_env_dir/.env" ] ||
    fail "legacy migration should not create .env when the target did not already have one"

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

implicit_installed_source_dir="$update_tmp/implicit-installed-source"
implicit_current_install_dir="$update_tmp/implicit-current-install"
implicit_other_install_dir="$update_tmp/implicit-other-install"
cp -a "$TEST_ROOT/." "$implicit_installed_source_dir"
mkdir -p "$implicit_current_install_dir/resources" "$implicit_current_install_dir/scripts/cmd" "$implicit_other_install_dir/resources" "$implicit_other_install_dir/scripts/cmd"
printf 'tyx-clash-for-linux-install\n' >"$implicit_current_install_dir/.clashctl-install-root"
printf 'tyx-clash-for-linux-install\n' >"$implicit_other_install_dir/.clashctl-install-root"
printf 'current-script\n' >"$implicit_current_install_dir/scripts/cmd/clashctl.sh"
printf 'other-script\n' >"$implicit_other_install_dir/scripts/cmd/clashctl.sh"
printf 'mixin\n' >"$implicit_current_install_dir/resources/mixin.yaml"
printf 'mixin\n' >"$implicit_other_install_dir/resources/mixin.yaml"
cp "$TEST_ROOT/update.sh" "$implicit_current_install_dir/update.sh"
cat >"$implicit_current_install_dir/resources/install-state.yaml" <<EOF
install_dir: "$implicit_current_install_dir"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
cat >"$implicit_installed_source_dir/resources/install-state.yaml" <<EOF
install_dir: "$implicit_other_install_dir"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
printf '\n# implicit-installed-source-marker\n' >>"$implicit_installed_source_dir/scripts/cmd/clashctl.sh"
bash "$implicit_current_install_dir/update.sh" --source "$implicit_installed_source_dir" >/dev/null 2>&1 ||
    fail "installed update.sh --source should default target to the current install dir"
grep -q 'implicit-installed-source-marker' "$implicit_current_install_dir/scripts/cmd/clashctl.sh" ||
    fail "installed update.sh --source should refresh the current install dir"
grep -qx 'other-script' "$implicit_other_install_dir/scripts/cmd/clashctl.sh" ||
    fail "installed update.sh --source should not update the source directory recorded target"

backup_fail_source_dir="$update_tmp/backup-fail-source"
backup_fail_install_dir="$update_tmp/backup-fail-install"
cp -a "$TEST_ROOT/." "$backup_fail_source_dir"
cp -a "$TEST_ROOT/." "$backup_fail_install_dir"
cat >"$backup_fail_install_dir/.env" <<EOF
CLASH_BASE_DIR=$backup_fail_install_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
EOF
printf 'tyx-clash-for-linux-install\n' >"$backup_fail_install_dir/.clashctl-install-root"
printf 'installed-script\n' >"$backup_fail_install_dir/scripts/cmd/clashctl.sh"
chmod 000 "$backup_fail_install_dir/README.md"
bash "$TEST_ROOT/update.sh" --target "$backup_fail_install_dir" --source "$backup_fail_source_dir" >/dev/null 2>&1 &&
    fail "update should fail when a managed target file cannot be backed up"
chmod 644 "$backup_fail_install_dir/README.md" 2>/dev/null || true
grep -qx 'installed-script' "$backup_fail_install_dir/scripts/cmd/clashctl.sh" ||
    fail "backup failure before replacement should not delete unbacked target files"

source_symlink_dir="$update_tmp/source-symlink"
source_symlink_install_dir="$update_tmp/source-symlink-install"
source_symlink_outside="$update_tmp/source-symlink-outside"
cp -a "$TEST_ROOT/." "$source_symlink_dir"
mkdir -p "$source_symlink_install_dir/resources" "$source_symlink_install_dir/scripts/cmd" "$source_symlink_outside"
printf 'tyx-clash-for-linux-install\n' >"$source_symlink_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$source_symlink_install_dir/resources/mixin.yaml"
printf 'script\n' >"$source_symlink_install_dir/scripts/cmd/clashctl.sh"
rm -rf "$source_symlink_dir/scripts"
mkdir -p "$source_symlink_dir/scripts/cmd"
rm -rf "$source_symlink_dir/docs"
printf 'outside-doc\n' >"$source_symlink_outside/README.md"
ln -s "$source_symlink_outside" "$source_symlink_dir/docs"
bash "$TEST_ROOT/update.sh" --target "$source_symlink_install_dir" --source "$source_symlink_dir" >/dev/null 2>&1 &&
    fail "update should reject managed source paths that are symlinks"
[ ! -L "$source_symlink_install_dir/docs" ] ||
    fail "rejected source symlink update should not install symlinks into target"

source_missing_env_dir="$update_tmp/source-missing-env"
source_missing_env_install_dir="$update_tmp/source-missing-env-install"
cp -a "$TEST_ROOT/." "$source_missing_env_dir"
mkdir -p "$source_missing_env_install_dir/resources" "$source_missing_env_install_dir/scripts/cmd"
printf 'tyx-clash-for-linux-install\n' >"$source_missing_env_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$source_missing_env_install_dir/resources/mixin.yaml"
printf 'script\n' >"$source_missing_env_install_dir/scripts/cmd/clashctl.sh"
rm -f "$source_missing_env_dir/.env"
bash "$TEST_ROOT/update.sh" --target "$source_missing_env_install_dir" --source "$source_missing_env_dir" >/dev/null 2>&1 ||
    fail "update should accept source directories without .env"
grep -q 'function clashctl' "$source_missing_env_install_dir/scripts/cmd/clashctl.sh" ||
    fail "source without .env should still refresh managed scripts"

git_preserve_source_dir="$update_tmp/git-preserve-source"
git_preserve_install_dir="$update_tmp/git-preserve-install"
cp -a "$TEST_ROOT/." "$git_preserve_source_dir"
mkdir -p "$git_preserve_install_dir/resources" "$git_preserve_install_dir/scripts/cmd" "$git_preserve_install_dir/.git"
printf 'tyx-clash-for-linux-install\n' >"$git_preserve_install_dir/.clashctl-install-root"
printf 'mixin\n' >"$git_preserve_install_dir/resources/mixin.yaml"
printf 'script\n' >"$git_preserve_install_dir/scripts/cmd/clashctl.sh"
printf 'user-managed-git\n' >"$git_preserve_install_dir/.git/config"
bash "$TEST_ROOT/update.sh" --target "$git_preserve_install_dir" --source "$git_preserve_source_dir" >/dev/null 2>&1 ||
    fail "update should succeed when a legacy install dir already has .git"
grep -qx 'user-managed-git' "$git_preserve_install_dir/.git/config" ||
    fail "update should not silently delete existing install dir .git"

remote_source_parent="$update_tmp/remote-source-parent"
remote_source_dir="$remote_source_parent/tyx-clash-for-linux-install-main"
remote_install_dir="$update_tmp/remote-install"
remote_archive="$update_tmp/remote.tar.gz"
remote_fake_bin="$update_tmp/remote-fake-bin"
remote_seen_url="$update_tmp/remote-seen-url"
mkdir -p "$remote_source_parent" "$remote_install_dir" "$remote_fake_bin"
cp -a "$TEST_ROOT/." "$remote_source_dir"
printf '\n# remote-source-marker\n' >>"$remote_source_dir/scripts/cmd/clashctl.sh"
tar -C "$remote_source_parent" -czf "$remote_archive" "$(basename "$remote_source_dir")"
cp -a "$TEST_ROOT/." "$remote_install_dir"
cat >"$remote_install_dir/.env" <<EOF
CLASH_BASE_DIR=$remote_install_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
URL_GH_PROXY=https://gh-proxy.org
EOF
printf 'tyx-clash-for-linux-install\n' >"$remote_install_dir/.clashctl-install-root"
cat >"$remote_fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
out=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
    -o | --output)
        shift
        out=$1
        ;;
    -*)
        ;;
    *)
        url=$1
        ;;
    esac
    shift
done
[ -n "$out" ] || exit 2
[ -n "$url" ] || exit 3
printf '%s\n' "$url" >"$CURL_SEEN_URL"
cp "$REMOTE_ARCHIVE" "$out"
EOF
chmod +x "$remote_fake_bin/curl"
PATH="$remote_fake_bin:$PATH" \
    CURL_SEEN_URL="$remote_seen_url" \
    REMOTE_ARCHIVE="$remote_archive" \
    bash "$remote_install_dir/update.sh" --target "$remote_install_dir" >/dev/null 2>&1 ||
    fail "installed update.sh should fetch the default remote source when --source is omitted"
grep -q 'remote-source-marker' "$remote_install_dir/scripts/cmd/clashctl.sh" ||
    fail "default update-self should refresh files from the downloaded archive"
grep -qx 'https://gh-proxy.org/https://github.com/tyx3211/tyx-clash-for-linux-install/archive/main.tar.gz' "$remote_seen_url" ||
    fail "default update-self should normalize URL_GH_PROXY before the fork GitHub URL"
PATH="$remote_fake_bin:$PATH" \
    CURL_SEEN_URL="$remote_seen_url" \
    REMOTE_ARCHIVE="$remote_archive" \
    bash "$remote_install_dir/update.sh" --target "$remote_install_dir" --ref release-test >/dev/null 2>&1 ||
    fail "installed update.sh should accept --ref for remote updates"
grep -q 'release-test.tar.gz' "$remote_seen_url" ||
    fail "remote update should include the selected ref in the download URL"
PATH="$remote_fake_bin:$PATH" \
    CURL_SEEN_URL="$remote_seen_url" \
    REMOTE_ARCHIVE="$remote_archive" \
    bash "$remote_install_dir/update.sh" --target "$remote_install_dir" --repo example-owner/example-repo --ref repo-test >/dev/null 2>&1 ||
    fail "installed update.sh should accept --repo for remote updates"
grep -qx 'https://gh-proxy.org/https://github.com/example-owner/example-repo/archive/repo-test.tar.gz' "$remote_seen_url" ||
    fail "remote update should include the selected repo in the download URL"

wrapper_install_dir="$update_tmp/wrapper-install"
cp -a "$TEST_ROOT/." "$wrapper_install_dir"
cat >"$wrapper_install_dir/.env" <<EOF
CLASH_BASE_DIR=$wrapper_install_dir
KERNEL_NAME=mihomo
INIT_TYPE=tmux
URL_GH_PROXY=
EOF
printf 'tyx-clash-for-linux-install\n' >"$wrapper_install_dir/.clashctl-install-root"
PATH="$remote_fake_bin:$PATH" \
    CURL_SEEN_URL="$remote_seen_url" \
    REMOTE_ARCHIVE="$remote_archive" \
    bash -c '. "$1/scripts/cmd/clashctl.sh"; clashctl update-self --repo wrapper-owner/wrapper-repo --ref wrapper-test' _ "$wrapper_install_dir" >/dev/null 2>&1 ||
    fail "clashctl update-self wrapper should forward --repo and --ref to update.sh"
grep -qx 'https://github.com/wrapper-owner/wrapper-repo/archive/wrapper-test.tar.gz' "$remote_seen_url" ||
    fail "clashctl update-self wrapper should preserve remote update arguments"

pass "update self checks"
