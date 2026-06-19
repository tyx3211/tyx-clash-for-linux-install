#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

INSTALL_SH="$TEST_ROOT/install.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
SYSTEMD_SH="$TEST_ROOT/scripts/init/systemd.sh"
ENV_FILE="$TEST_ROOT/.env"

assert_file_contains "$INSTALL_SH" 'THIS_INSTALL_DIR=' \
    "install should resolve paths from the install script location"

assert_file_not_contains "$INSTALL_SH" '/bin/cp -rf \\. ' \
    "install should not copy the caller current directory"

assert_file_contains "$SYSTEMD_SH" 'placeholder_run_as_user' \
    "systemd service should be able to run as the sudo invoking user"

assert_file_contains "$PREFLIGHT_SH" 'User=\$SUDO_USER|User="\$SUDO_USER"|service_run_as_user' \
    "regular sudo systemd install should render a User= line"

assert_file_contains "$PREFLIGHT_SH" '/usr/bin/install -D -m 755' \
    "rendered service files should keep read permission for init managers"

assert_file_contains "$PREFLIGHT_SH" '_install_service\(\)' \
    "preflight should define install service rendering"

assert_file_contains "$PREFLIGHT_SH" 'return 0' \
    "install service rendering should not report failure when optional reload commands are absent"

assert_file_contains "$SYSTEMD_SH" 'CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE' \
    "systemd service should keep only network-related capabilities"

assert_file_not_contains "$SYSTEMD_SH" 'CAP_SYS_PTRACE|CAP_DAC_OVERRIDE|CAP_DAC_READ_SEARCH|CAP_SYS_TIME' \
    "systemd service should not grant unrelated broad capabilities"

assert_file_contains "$CLASHCTL_SH" '_download_config "\$CLASH_CONFIG_TEMP" "\$url" \\|\\|' \
    "clashsub add should stop immediately when subscription download fails"

assert_file_contains "$CLASHCTL_SH" '_download_convert_config "\$CLASH_CONFIG_TEMP" "\$url" \\|\\|' \
    "clashsub update --convert should stop immediately when conversion download fails"

assert_file_contains "$CLASHCTL_SH" '_download_config "\$CLASH_CONFIG_TEMP" "\$url" \\|\\|' \
    "clashsub update should stop immediately when subscription download fails"

assert_file_contains "$CLASHCTL_SH" '_make_config_temp' \
    "subscription updates should use a fresh temporary file instead of reusing stale temp.yaml"

assert_file_contains "$CLASHCTL_SH" 'mktemp "\$\{CLASH_RESOURCES_DIR\}/temp\.' \
    "subscription temporary files should be created with mktemp"

assert_file_contains "$CLASHCTL_SH" '_merge_config \\|\\|' \
    "tun operations should be able to recover when merge validation fails"

assert_file_contains "$CLASHCTL_SH" '_merge_config_restart \\|\\| return 1' \
    "clashsub use should stop when runtime merge fails"

assert_file_contains "$CLASHCTL_SH" 'tun[[:space:]]+管理 Tun 模式' \
    "clashctl help should list the tun command"

assert_file_contains "$PREFLIGHT_SH" 'CLASH_INSTALL_CREATED_DIR|trap .*CLASH_BASE_DIR|staging' \
    "install should clean up directories it created when install preparation fails"

assert_file_contains "$ENV_FILE" 'SUBCONVERTER_REPO=' \
    "subconverter source should be configurable like upstream"

assert_file_contains "$ENV_FILE" 'CLASHCTL_DOWNLOAD_TIMEOUT=' \
    "dependency download timeout should be configurable like upstream"

assert_file_contains "$ENV_FILE" 'CLASHCTL_SUB_TIMEOUT=' \
    "subscription download timeout should be configurable like upstream"

tmp=$(make_test_tmpdir "clash-sub-fail")
(
    set +e
    . "$CLASHCTL_SH"

    _error_quit() { return 97; }
    _get_id_by_url() { return 1; }
    _make_config_temp() { printf '%s\n' "$tmp/stale.yaml"; }
    _download_config() { return 1; }
    _valid_config() {
        valid_called=true
        return 0
    }

    valid_called=false
    _sub_add "https://example.invalid/sub"
    status=$?
    [ "$status" -ne 0 ] || fail "clashsub add should fail when download fails"
    [ "$valid_called" = false ] || fail "clashsub add should not validate stale temp after download failure"
)

pass "review regression checks"
