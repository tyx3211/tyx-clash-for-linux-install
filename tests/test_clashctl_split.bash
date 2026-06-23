#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
COMMON_SH="$TEST_ROOT/scripts/cmd/common.sh"
PROXY_SH="$TEST_ROOT/scripts/lib/proxy.sh"
SERVICE_RUNTIME_SH="$TEST_ROOT/scripts/lib/service-runtime.sh"
CONFIG_SH="$TEST_ROOT/scripts/lib/config.sh"
TUN_SH="$TEST_ROOT/scripts/lib/tun.sh"
SUBSCRIPTION_SH="$TEST_ROOT/scripts/lib/subscription.sh"

for file in "$PROXY_SH" "$SERVICE_RUNTIME_SH" "$CONFIG_SH" "$TUN_SH" "$SUBSCRIPTION_SH"; do
    [ -f "$file" ] || fail "clashctl domain library should exist: $file"
done

assert_file_contains "$CLASHCTL_SH" '^_clashctl_source_lib\(\)' \
    "clashctl should guard domain library sourcing"

assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/common\.sh"' \
    "clashctl should source common helpers through the guarded helper"

assert_file_contains "$COMMON_SH" '_CLASHCTL_PATH_ENV_LIB=' \
    "common helpers should source path-env directly instead of relying on install-state transitive loading"

assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/proxy\.sh"' \
    "clashctl should source proxy helpers from scripts/lib"
assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/service-runtime\.sh"' \
    "clashctl should source runtime service helpers from scripts/lib"
assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/config\.sh"' \
    "clashctl should source config helpers from scripts/lib"
assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/tun\.sh"' \
    "clashctl should source tun helpers from scripts/lib"
assert_file_contains "$CLASHCTL_SH" '_clashctl_source_lib "\$THIS_SCRIPT_DIR/\.\./lib/subscription\.sh"' \
    "clashctl should source subscription helpers from scripts/lib"

missing_lib_tmp=$(make_test_tmpdir "clash-missing-lib")
missing_lib_repo="$missing_lib_tmp/repo"
cp -a "$TEST_ROOT/." "$missing_lib_repo"
/usr/bin/rm -f "$missing_lib_repo/scripts/lib/proxy.sh"
(
    set +e
    . "$missing_lib_repo/scripts/cmd/clashctl.sh" 2>"$missing_lib_tmp/source.err"
    source_status=$?
    declare -F clashctl >/dev/null
    defined_status=$?
    printf '%s %s\n' "$source_status" "$defined_status" >"$missing_lib_tmp/source.status"
)
read -r source_status defined_status <"$missing_lib_tmp/source.status"
[ "$source_status" -ne 0 ] ||
    fail "clashctl source should fail when a required domain library is missing"
[ "$defined_status" -ne 0 ] ||
    fail "clashctl dispatcher should not be defined after required library source failure"
grep -q 'proxy.sh' "$missing_lib_tmp/source.err" ||
    fail "missing library source failure should name the missing file"

missing_common_tmp=$(make_test_tmpdir "clash-missing-common")
missing_common_repo="$missing_common_tmp/repo"
cp -a "$TEST_ROOT/." "$missing_common_repo"
/usr/bin/rm -f "$missing_common_repo/scripts/cmd/common.sh"
(
    set +e
    . "$missing_common_repo/scripts/cmd/clashctl.sh" 2>"$missing_common_tmp/source.err"
    source_status=$?
    declare -F clashctl >/dev/null
    defined_status=$?
    printf '%s %s\n' "$source_status" "$defined_status" >"$missing_common_tmp/source.status"
)
read -r source_status defined_status <"$missing_common_tmp/source.status"
[ "$source_status" -ne 0 ] ||
    fail "clashctl source should fail when common helpers are missing"
[ "$defined_status" -ne 0 ] ||
    fail "clashctl dispatcher should not be defined after common helper source failure"
grep -q 'common.sh' "$missing_common_tmp/source.err" ||
    fail "missing common source failure should name the missing file"

missing_env_tmp=$(make_test_tmpdir "clash-missing-env")
missing_env_repo="$missing_env_tmp/repo"
cp -a "$TEST_ROOT/." "$missing_env_repo"
/usr/bin/rm -f "$missing_env_repo/.env"
bash -c '
    . "$1/scripts/cmd/clashctl.sh" 2>"$2/source.err"
    source_status=$?
    declare -F clashctl >/dev/null
    defined_status=$?
    printf "%s %s\n" "$source_status" "$defined_status" >"$2/source.status"
' -- "$missing_env_repo" "$missing_env_tmp" || true
read -r source_status defined_status <"$missing_env_tmp/source.status"
[ "$source_status" -ne 0 ] ||
    fail "clashctl source should fail when both install-state.yaml and .env are missing"
[ "$defined_status" -ne 0 ] ||
    fail "clashctl dispatcher should not be defined after install metadata source failure"
grep -q 'install-state.yaml' "$missing_env_tmp/source.err" ||
    fail "missing install metadata source failure should name install-state.yaml"

env_parse_tmp=$(make_test_tmpdir "clash-env-parse")
env_parse_repo="$env_parse_tmp/repo"
cp -a "$TEST_ROOT/." "$env_parse_repo"
write_test_install_yq "$env_parse_repo"
cat >"$env_parse_repo/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$env_parse_repo
CLASH_CONFIG_URL="\$(touch "$env_parse_tmp/executed")"
INIT_TYPE=tmux
URL_CLASH_UI=http://board.example.invalid
CLASH_SUB_UA=test-agent
PATH=/definitely/not/a/path
EOF
bash -c '. "$1/scripts/cmd/clashctl.sh"' -- "$env_parse_repo" >/dev/null 2>&1 ||
    fail "clashctl source should parse simple .env assignments"
[ ! -e "$env_parse_tmp/executed" ] ||
    fail "clashctl should parse .env without executing shell code"
bash -c '
    old_path=$PATH
    . "$1/scripts/cmd/clashctl.sh" || exit 1
    [ "$PATH" = "$old_path" ]
' -- "$env_parse_repo" >/dev/null 2>&1 ||
    fail "clashctl should ignore non-whitelisted .env variables such as PATH"

upstream_env_parse_tmp=$(make_test_tmpdir "clash-upstream-env-parse")
upstream_env_parse_repo="$upstream_env_parse_tmp/repo"
cp -a "$TEST_ROOT/." "$upstream_env_parse_repo"
rm -f "$upstream_env_parse_repo/resources/install-state.yaml"
write_test_install_yq "$upstream_env_parse_repo"
cat >"$upstream_env_parse_repo/.env" <<EOF
CLASHCTL_HOME=$upstream_env_parse_repo
CLASHCTL_KERNEL=clash
CLASHCTL_SUB_UA=legacy-agent
INIT_TYPE=nohup
EOF
bash -c '
    . "$1/scripts/cmd/clashctl.sh" || exit 1
    [ "$CLASH_BASE_DIR" = "$1" ] || exit 2
    [ "$KERNEL_NAME" = clash ] || exit 3
    [ "$CLASH_SUB_UA" = legacy-agent ] || exit 4
    [ "$INIT_TYPE" = nohup ] || exit 5
' -- "$upstream_env_parse_repo" >/dev/null 2>&1 ||
    fail "clashctl should parse legacy upstream CLASHCTL_HOME / CLASHCTL_KERNEL env names"

env_empty_base_tmp=$(make_test_tmpdir "clash-env-empty-base")
env_empty_base_repo="$env_empty_base_tmp/repo"
cp -a "$TEST_ROOT/." "$env_empty_base_repo"
rm -f "$env_empty_base_repo/resources/install-state.yaml"
cat >"$env_empty_base_repo/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=
INIT_TYPE=tmux
EOF
bash -c '. "$1/scripts/cmd/clashctl.sh"' -- "$env_empty_base_repo" >"$env_empty_base_tmp/out" 2>"$env_empty_base_tmp/err" &&
    fail "clashctl should reject an empty CLASH_BASE_DIR from legacy .env"
grep -q 'critical runtime variable is empty: CLASH_BASE_DIR' "$env_empty_base_tmp/err" ||
    fail "empty CLASH_BASE_DIR failure should name the invalid runtime variable"

env_state_tmp=$(make_test_tmpdir "clash-env-state")
env_state_repo="$env_state_tmp/repo"
cp -a "$TEST_ROOT/." "$env_state_repo"
rm -f "$env_state_repo/.env"
mkdir -p "$env_state_repo/resources"
write_test_install_yq "$env_state_repo"
cat >"$env_state_repo/resources/install-state.yaml" <<EOF
install_dir: "$env_state_repo"
kernel_name: "mihomo"
default_mode: "nohup"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
bash -c '
    . "$1/scripts/cmd/clashctl.sh" || exit 1
    [ "$CLASH_BASE_DIR" = "$1" ] || exit 2
    [ "$KERNEL_NAME" = mihomo ] || exit 3
    [ "$INIT_TYPE" = nohup ] || exit 4
' -- "$env_state_repo" >/dev/null 2>&1 ||
    fail "clashctl should source install-state.yaml without requiring .env"

state_false_tmp=$(make_test_tmpdir "clash-state-false")
state_false_repo="$state_false_tmp/repo"
cp -a "$TEST_ROOT/." "$state_false_repo"
rm -f "$state_false_repo/.env"
mkdir -p "$state_false_repo/bin" "$state_false_repo/resources"
cat >"$state_false_repo/bin/yq" <<'EOF'
#!/usr/bin/env bash
expr=${1:-}
file=${2:-}
case "$expr" in
'.install_dir // ""')
    awk -F': *' '$1 == "install_dir" { gsub(/^"|"$/, "", $2); print $2 }' "$file"
    ;;
'.kernel_name // ""')
    awk -F': *' '$1 == "kernel_name" { gsub(/^"|"$/, "", $2); print $2 }' "$file"
    ;;
'.default_mode // ""')
    awk -F': *' '$1 == "default_mode" { gsub(/^"|"$/, "", $2); print $2 }' "$file"
    ;;
'.installed_systemd_service // ""')
    printf '\n'
    ;;
'select(has("installed_systemd_service")) | .installed_systemd_service')
    awk -F': *' '$1 == "installed_systemd_service" { print $2 }' "$file"
    ;;
*)
    exit 7
    ;;
esac
EOF
chmod +x "$state_false_repo/bin/yq"
cat >"$state_false_repo/resources/install-state.yaml" <<EOF
install_dir: "$state_false_repo"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
EOF
bash -c '. "$1/scripts/cmd/clashctl.sh"' -- "$state_false_repo" >/dev/null 2>&1 ||
    fail "clashctl should preserve false installed_systemd_service from install-state.yaml"

state_missing_yq_tmp=$(make_test_tmpdir "clash-state-missing-yq")
state_missing_yq_repo="$state_missing_yq_tmp/repo"
cp -a "$TEST_ROOT/." "$state_missing_yq_repo"
rm -f "$state_missing_yq_repo/.env"
rm -f "$state_missing_yq_repo/bin/yq"
mkdir -p "$state_missing_yq_repo/resources"
cat >"$state_missing_yq_repo/resources/install-state.yaml" <<EOF
install_dir: "$state_missing_yq_repo"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
bash -c '. "$1/scripts/cmd/clashctl.sh"' -- "$state_missing_yq_repo" >"$state_missing_yq_tmp/out" 2>"$state_missing_yq_tmp/err" &&
    fail "clashctl should fail when install-state.yaml exists but bin/yq is missing"
grep -q 'missing executable yq' "$state_missing_yq_tmp/err" ||
    fail "missing yq error should mention the missing install yq"
! grep -q 'install-state.yaml install_dir mismatch' "$state_missing_yq_tmp/err" ||
    fail "missing yq should stop install-state parsing before install_dir mismatch checks"
bash -c 'CLASHCTL_INSTALL_BOOTSTRAP=1 . "$1/scripts/cmd/clashctl.sh"' -- "$state_missing_yq_repo" >"$state_missing_yq_tmp/bootstrap.out" 2>"$state_missing_yq_tmp/bootstrap.err" &&
    fail "installed clashctl should not allow bootstrap mode to bypass missing yq validation"
grep -q 'missing executable yq' "$state_missing_yq_tmp/bootstrap.err" ||
    fail "bootstrap bypass rejection should still mention the missing install yq"
! grep -q 'install-state.yaml install_dir mismatch' "$state_missing_yq_tmp/bootstrap.err" ||
    fail "bootstrap bypass rejection should stop before install_dir mismatch checks"
if command -v zsh >/dev/null; then
    zsh -c 'source "$1/scripts/cmd/clashctl.sh"' -- "$state_missing_yq_repo" >"$state_missing_yq_tmp/zsh.out" 2>"$state_missing_yq_tmp/zsh.err" &&
        fail "zsh source should still reject an install missing bin/yq"
    grep -q 'missing executable yq' "$state_missing_yq_tmp/zsh.err" ||
        fail "zsh source should resolve install-state helpers before reporting missing yq"
    ! grep -q 'missing required library' "$state_missing_yq_tmp/zsh.err" ||
        fail "zsh source should not resolve install-state helper paths from the caller directory"
fi

if command -v zsh >/dev/null; then
    zsh_env_missing_yq_tmp=$(make_test_tmpdir "clash-zsh-env-missing-yq")
    zsh_env_missing_yq_repo="$zsh_env_missing_yq_tmp/repo"
    cp -a "$TEST_ROOT/." "$zsh_env_missing_yq_repo"
    rm -f "$zsh_env_missing_yq_repo/resources/install-state.yaml"
    rm -f "$zsh_env_missing_yq_repo/bin/yq"
    cat >"$zsh_env_missing_yq_repo/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$zsh_env_missing_yq_repo
INIT_TYPE=tmux
EOF
    zsh -c 'source "$1/scripts/cmd/clashctl.sh"' -- "$zsh_env_missing_yq_repo" >"$zsh_env_missing_yq_tmp/out" 2>"$zsh_env_missing_yq_tmp/err" &&
        fail "zsh source should reject a legacy .env install missing bin/yq"
    grep -q 'missing executable yq' "$zsh_env_missing_yq_tmp/err" ||
        fail "zsh legacy .env source should report missing yq"
    ! grep -q 'bad substitution' "$zsh_env_missing_yq_tmp/err" ||
        fail "zsh legacy .env source should not use bash-only indirect expansion"
fi

legacy_bootstrap_bypass_tmp=$(make_test_tmpdir "clash-legacy-bootstrap-bypass")
legacy_bootstrap_repo="$legacy_bootstrap_bypass_tmp/repo"
legacy_bootstrap_other="$legacy_bootstrap_bypass_tmp/other"
cp -a "$TEST_ROOT/." "$legacy_bootstrap_repo"
rm -f "$legacy_bootstrap_repo/resources/install-state.yaml"
rm -f "$legacy_bootstrap_repo/bin/yq"
mkdir -p "$legacy_bootstrap_repo/resources" "$legacy_bootstrap_other"
printf '%s\n' 'tyx-clash-for-linux-install' >"$legacy_bootstrap_repo/.clashctl-install-root"
cat >"$legacy_bootstrap_repo/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$legacy_bootstrap_repo
INIT_TYPE=tmux
EOF
bash -c '
    CLASHCTL_INSTALL_BOOTSTRAP=1 \
    CLASHCTL_INSTALL_BOOTSTRAP_SOURCE_DIR=$1 \
    CLASH_BASE_DIR=$2 \
    . "$1/scripts/cmd/clashctl.sh"
' -- "$legacy_bootstrap_repo" "$legacy_bootstrap_other" >"$legacy_bootstrap_bypass_tmp/out" 2>"$legacy_bootstrap_bypass_tmp/err" &&
    fail "installed legacy clashctl should not allow external CLASH_BASE_DIR to spoof install bootstrap"
grep -q 'missing executable yq' "$legacy_bootstrap_bypass_tmp/err" ||
    fail "legacy bootstrap spoof rejection should still require installed yq"

markerless_bootstrap_bypass_tmp=$(make_test_tmpdir "clash-markerless-bootstrap-bypass")
markerless_bootstrap_repo="$markerless_bootstrap_bypass_tmp/repo"
markerless_bootstrap_other="$markerless_bootstrap_bypass_tmp/other"
cp -a "$TEST_ROOT/." "$markerless_bootstrap_repo"
rm -f "$markerless_bootstrap_repo/.clashctl-install-root"
rm -f "$markerless_bootstrap_repo/resources/install-state.yaml"
rm -f "$markerless_bootstrap_repo/bin/yq"
mkdir -p "$markerless_bootstrap_repo/resources" "$markerless_bootstrap_other"
cat >"$markerless_bootstrap_repo/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$markerless_bootstrap_repo
INIT_TYPE=tmux
EOF
bash -c '
    CLASHCTL_INSTALL_BOOTSTRAP=1 \
    CLASHCTL_INSTALL_BOOTSTRAP_SOURCE_DIR=$1 \
    CLASH_BASE_DIR=$2 \
    . "$1/scripts/cmd/clashctl.sh"
' -- "$markerless_bootstrap_repo" "$markerless_bootstrap_other" >"$markerless_bootstrap_bypass_tmp/out" 2>"$markerless_bootstrap_bypass_tmp/err" &&
    fail "markerless clashctl should not allow direct source to spoof install bootstrap"
grep -q 'missing executable yq' "$markerless_bootstrap_bypass_tmp/err" ||
    fail "markerless bootstrap spoof rejection should still require installed yq"

state_mismatch_tmp=$(make_test_tmpdir "clash-state-mismatch")
state_mismatch_repo="$state_mismatch_tmp/repo"
state_mismatch_other="$state_mismatch_tmp/other"
cp -a "$TEST_ROOT/." "$state_mismatch_repo"
mkdir -p "$state_mismatch_repo/resources" "$state_mismatch_other"
rm -f "$state_mismatch_repo/.env"
write_test_install_yq "$state_mismatch_repo"
cat >"$state_mismatch_repo/resources/install-state.yaml" <<EOF
install_dir: "$state_mismatch_other"
kernel_name: "mihomo"
default_mode: "tmux"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
bash -c '. "$1/scripts/cmd/clashctl.sh"' -- "$state_mismatch_repo" >"$state_mismatch_tmp/out" 2>"$state_mismatch_tmp/err" &&
    fail "clashctl should reject install-state.yaml that belongs to another install directory"
grep -q 'install-state.yaml' "$state_mismatch_tmp/err" ||
    fail "install-state mismatch error should name install-state.yaml"

state_precedence_tmp=$(make_test_tmpdir "clash-state-precedence")
state_precedence_repo="$state_precedence_tmp/repo"
cp -a "$TEST_ROOT/." "$state_precedence_repo"
mkdir -p "$state_precedence_repo/resources"
write_test_install_yq "$state_precedence_repo"
cat >"$state_precedence_repo/.env" <<EOF
KERNEL_NAME=clash
CLASH_BASE_DIR=/stale/path
INIT_TYPE=tmux
EOF
cat >"$state_precedence_repo/resources/install-state.yaml" <<EOF
install_dir: "$state_precedence_repo"
kernel_name: "mihomo"
default_mode: "nohup"
installed_systemd_service: true
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
bash -c '
    . "$1/scripts/cmd/clashctl.sh" || exit 1
    [ "$CLASH_BASE_DIR" = "$1" ] || exit 2
    [ "$KERNEL_NAME" = mihomo ] || exit 3
    [ "$INIT_TYPE" = nohup ] || exit 4
    [ "$CLASH_INSTALLED_INIT_TYPE" = systemd ] || exit 5
' -- "$state_precedence_repo" >/dev/null 2>&1 ||
    fail "install-state.yaml should take precedence over stale .env install metadata"

state_env_override_tmp=$(make_test_tmpdir "clash-state-env-override")
state_env_override_repo="$state_env_override_tmp/repo"
state_env_override_other="$state_env_override_tmp/other"
cp -a "$TEST_ROOT/." "$state_env_override_repo"
mkdir -p "$state_env_override_repo/resources" "$state_env_override_other"
write_test_install_yq "$state_env_override_repo"
cat >"$state_env_override_repo/resources/install-state.yaml" <<EOF
install_dir: "$state_env_override_repo"
kernel_name: "mihomo"
default_mode: "nohup"
installed_systemd_service: false
versions:
  mihomo: "v-state"
  yq: "v-state"
  subconverter: "v-state"
EOF
bash -c '
    export CLASH_BASE_DIR="$2" KERNEL_NAME=clash INIT_TYPE=systemd
    . "$1/scripts/cmd/clashctl.sh" || exit 1
    [ "$CLASH_BASE_DIR" = "$1" ] || exit 2
    [ "$KERNEL_NAME" = mihomo ] || exit 3
    [ "$INIT_TYPE" = nohup ] || exit 4
' -- "$state_env_override_repo" "$state_env_override_other" >/dev/null 2>&1 ||
    fail "install-state.yaml should take precedence over ambient install identity environment variables"

ext_conflict_tmp=$(make_test_tmpdir "clash-ext-conflict-readonly")
ext_conflict_repo="$ext_conflict_tmp/repo"
cp -a "$TEST_ROOT/." "$ext_conflict_repo"
cat >"$ext_conflict_repo/.env" <<EOF
KERNEL_NAME=mihomo
CLASH_BASE_DIR=$ext_conflict_repo
INIT_TYPE=tmux
EOF
cat >"$ext_conflict_tmp/yq" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "-i" ]; then
    printf 'yq-write\n' >>"$ext_conflict_tmp/calls"
    exit 0
fi
case "\${1:-}" in
'.external-controller // ""')
    printf '%s\n' '127.0.0.1:9090'
    ;;
*)
    printf '%s\n' ''
    ;;
esac
EOF
chmod +x "$ext_conflict_tmp/yq"
(
    set +e
    . "$ext_conflict_repo/scripts/cmd/clashctl.sh"
    BIN_YQ="$ext_conflict_tmp/yq"
    CLASH_CONFIG_RUNTIME="$ext_conflict_tmp/runtime.yaml"
    CLASH_CONFIG_MIXIN="$ext_conflict_tmp/mixin.yaml"
    printf '{}\n' >"$CLASH_CONFIG_RUNTIME"
    printf '{}\n' >"$CLASH_CONFIG_MIXIN"
    _is_port_used() { return 0; }
    curl() { return 1; }
    _get_secret() { :; }
    _get_random_port() { printf '%s\n' 19090; }
    _merge_config() { printf 'merge\n' >>"$ext_conflict_tmp/calls"; }
    _failcat() { printf '%s\n' "$*" >>"$ext_conflict_tmp/fail.log"; }

    _ensure_ext_addr_available
    status=$?
    [ "$status" -ne 0 ] ||
        fail "_ensure_ext_addr_available should fail when external-controller port is occupied by another process"
    ! grep -q '^yq-write$' "$ext_conflict_tmp/calls" 2>/dev/null ||
        fail "_ensure_ext_addr_available should not write mixin.yaml automatically"
    ! grep -q '^merge$' "$ext_conflict_tmp/calls" 2>/dev/null ||
        fail "_ensure_ext_addr_available should not merge config after external-controller conflict"
    grep -q '建议改' "$ext_conflict_tmp/fail.log" ||
        fail "_ensure_ext_addr_available should suggest editing mixin.yaml"
    grep -q '19090' "$ext_conflict_tmp/fail.log" ||
        fail "_ensure_ext_addr_available should include a suggested free external-controller port"
)

assert_file_contains "$PROXY_SH" '^function clashproxy\(\)' \
    "proxy command should live in proxy library"
assert_file_contains "$PROXY_SH" '^watch_proxy\(\)' \
    "interactive proxy watcher should live in proxy library"

assert_file_contains "$SERVICE_RUNTIME_SH" '^_clash_adapter_tmux_start\(\)' \
    "tmux adapter should live in runtime service library"
assert_file_contains "$SERVICE_RUNTIME_SH" '^function clashon\(\)' \
    "clashon command should live in runtime service library"
assert_file_contains "$SERVICE_RUNTIME_SH" '^function clashstatus\(\)' \
    "clashstatus command should live in runtime service library"

assert_file_contains "$CONFIG_SH" '^_merge_config\(\)' \
    "config merge should live in config library"
assert_file_contains "$CONFIG_SH" '^function clashmixin\(\)' \
    "mixin command should live in config library"
assert_file_contains "$CONFIG_SH" '^function clashupgrade\(\)' \
    "kernel upgrade command should live in config library"

assert_file_contains "$TUN_SH" '^function clashtun\(\)' \
    "tun command should live in tun library"
assert_file_contains "$TUN_SH" '^_require_tun_runtime\(\)' \
    "tun runtime gate should live in tun library"

assert_file_contains "$SUBSCRIPTION_SH" '^function clashsub\(\)' \
    "subscription command should live in subscription library"
assert_file_contains "$SUBSCRIPTION_SH" '^_sub_add\(\)' \
    "subscription mutation helpers should live in subscription library"

assert_file_contains "$CLASHCTL_SH" '^function clashctl\(\)' \
    "clashctl dispatcher should remain in the command entrypoint"
assert_file_contains "$CLASHCTL_SH" '^clashhelp\(\)' \
    "clashhelp should remain in the command entrypoint"

assert_file_not_contains "$CLASHCTL_SH" '^_clash_adapter_tmux_start\(\)' \
    "runtime adapters should not remain in clashctl entrypoint"
assert_file_not_contains "$CLASHCTL_SH" '^_merge_config\(\)' \
    "config merge implementation should not remain in clashctl entrypoint"
assert_file_not_contains "$CLASHCTL_SH" '^_sub_add\(\)' \
    "subscription helpers should not remain in clashctl entrypoint"
assert_file_not_contains "$CLASHCTL_SH" '^function clashtun\(\)' \
    "tun command should not remain in clashctl entrypoint"
assert_file_not_contains "$CLASHCTL_SH" '^function clashproxy\(\)' \
    "proxy command should not remain in clashctl entrypoint"

pass "clashctl split checks"
