#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

ENV_FILE="$TEST_ROOT/.env"
INSTALL_SH="$TEST_ROOT/install.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
SERVICE_RENDER_SH="$TEST_ROOT/scripts/install/service-render.sh"
CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
TUN_SH="$TEST_ROOT/scripts/lib/tun.sh"

assert_file_contains "$ENV_FILE" '^INIT_TYPE=tmux$' \
    "tmux should remain the default init mode"

assert_file_contains "$SERVICE_RENDER_SH" 'tmux\)' \
    "_detect_init should support tmux mode"

assert_file_contains "$SERVICE_RENDER_SH" 'nohup\)' \
    "_detect_init should support explicit nohup mode"

assert_file_contains "$SERVICE_RENDER_SH" 'systemd\)' \
    "_detect_init should support explicit systemd mode"

assert_file_contains "$PREFLIGHT_SH" '--init=' \
    "_parse_args should accept --init=<mode>"

assert_file_contains "$PREFLIGHT_SH" '--init' \
    "_parse_args should accept --init <mode>"

clashtun_body=$(extract_function "clashtun" "$TUN_SH")
[ -n "$clashtun_body" ] ||
    fail "extract_function should read function-style clashtun definitions"
grep -q 'no-sudo 版已禁用' <<<"$clashtun_body" &&
    fail "clashtun should be mode-gated instead of permanently disabled"

assert_file_contains "$TUN_SH" 'tunon\(\)' \
    "clashctl should provide tunon implementation for sudo-capable mode"

assert_file_contains "$INSTALL_SH" '_parse_args "\$@"' \
    "install.sh should parse command-line overrides before detecting init"

service_guard_tmp=$(make_test_tmpdir "clash-service-guard")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    KERNEL_NAME=mihomo
    INIT_TYPE=systemd
    CLASH_BASE_DIR="$service_guard_tmp/current"
    CLASH_RESOURCES_DIR="$CLASH_BASE_DIR/resources"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    BIN_KERNEL="$CLASH_BASE_DIR/bin/mihomo"
    service_target="$service_guard_tmp/mihomo.service"
    service_src="$service_guard_tmp/systemd.sh"
    service_add=()
    service_enable=(true)
    service_reload=(true)
    mkdir -p "$service_guard_tmp" "$CLASH_RESOURCES_DIR" "$CLASH_BASE_DIR/bin"
    printf 'ExecStart=/opt/other/mihomo -d /opt/other/resources -f /opt/other/runtime.yaml\n' >"$service_target"
    printf 'ExecStart=placeholder_cmd_full\n' >"$service_src"
    _error_quit() {
        printf '%s\n' "$*" >"$service_guard_tmp/error.log"
        return 1
    }

    _install_service
    status=$?
    [ "$status" -ne 0 ] ||
        fail "_install_service should reject an existing systemd unit that belongs to another install"
    grep -qx 'ExecStart=/opt/other/mihomo -d /opt/other/resources -f /opt/other/runtime.yaml' "$service_target" ||
        fail "_install_service should not overwrite an unrelated existing systemd unit"
)

service_uninstall_guard_tmp=$(make_test_tmpdir "clash-service-uninstall-guard")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    KERNEL_NAME=mihomo
    INIT_TYPE=systemd
    CLASH_BASE_DIR="$service_uninstall_guard_tmp/current"
    CLASH_RESOURCES_DIR="$CLASH_BASE_DIR/resources"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    BIN_KERNEL="$CLASH_BASE_DIR/bin/mihomo"
    service_target="$service_uninstall_guard_tmp/mihomo.service"
    mkdir -p "$service_uninstall_guard_tmp" "$CLASH_RESOURCES_DIR" "$CLASH_BASE_DIR/bin"
    printf 'ExecStart=/opt/other/mihomo -d /opt/other/resources -f /opt/other/runtime.yaml\n' >"$service_target"
    _detect_init() {
        service_target="$service_uninstall_guard_tmp/mihomo.service"
        service_disable=(sh -c "printf disable >> '$service_uninstall_guard_tmp/calls'")
        service_del=()
        service_reload=()
    }

    _uninstall_service
    status=$?
    [ "$status" -eq 0 ] ||
        fail "_uninstall_service should skip unrelated systemd units without failing"
    [ -f "$service_target" ] ||
        fail "_uninstall_service should not delete an unrelated existing systemd unit"
    [ ! -e "$service_uninstall_guard_tmp/calls" ] ||
        fail "_uninstall_service should not disable an unrelated existing systemd unit"
)

service_uninstall_force_tmp=$(make_test_tmpdir "clash-service-uninstall-force")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    KERNEL_NAME=mihomo
    INIT_TYPE=systemd
    CLASH_BASE_DIR="$service_uninstall_force_tmp/current"
    CLASH_RESOURCES_DIR="$CLASH_BASE_DIR/resources"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    BIN_KERNEL="$CLASH_BASE_DIR/bin/mihomo"
    service_target="$service_uninstall_force_tmp/mihomo.service"
    mkdir -p "$service_uninstall_force_tmp" "$CLASH_RESOURCES_DIR" "$CLASH_BASE_DIR/bin"
    printf 'ExecStart=placeholder_cmd_full\n' >"$service_target"
    _detect_init() {
        service_target="$service_uninstall_force_tmp/mihomo.service"
        service_disable=(true)
        service_del=()
        service_reload=()
    }

    _uninstall_service --force-current-attempt
    status=$?
    [ "$status" -eq 0 ] ||
        fail "_uninstall_service --force-current-attempt should remove a unit written by a failed install attempt"
    [ ! -e "$service_target" ] ||
        fail "_uninstall_service --force-current-attempt should remove a partially rendered unit"
)

pass "service mode checks"
