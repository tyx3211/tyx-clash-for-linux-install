#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

INSTALL_SH="$TEST_ROOT/install.sh"
PREFLIGHT_SH="$TEST_ROOT/scripts/preflight.sh"
SERVICE_RENDER_SH="$TEST_ROOT/scripts/install/service-render.sh"
CLASHCTL_SH="$TEST_ROOT/scripts/cmd/clashctl.sh"
TUN_SH="$TEST_ROOT/scripts/lib/tun.sh"
SUBSCRIPTION_SH="$TEST_ROOT/scripts/lib/subscription.sh"
SYSTEMD_SH="$TEST_ROOT/scripts/init/systemd.sh"
ENV_FILE="$TEST_ROOT/.env"

assert_file_contains "$INSTALL_SH" 'THIS_INSTALL_DIR=' \
    "install should resolve paths from the install script location"

assert_file_contains "$INSTALL_SH" 'cd "\$THIS_INSTALL_DIR"' \
    "install should run source-relative operations from the script directory"

assert_file_not_contains "$INSTALL_SH" '/bin/cp -rf \\. ' \
    "install should not copy the caller current directory"

assert_file_not_contains "$INSTALL_SH" '/bin/cp -rf "\$THIS_INSTALL_DIR"/\. "\$CLASH_BASE_DIR"' \
    "install should not copy the whole source checkout including .git"

assert_file_contains "$INSTALL_SH" '_copy_install_payload\(\)' \
    "install should copy an explicit runtime payload instead of the whole source checkout"

install_payload_tmp=$(make_test_tmpdir "clash-install-payload")
install_payload_source="$install_payload_tmp/source"
install_payload_target="$install_payload_tmp/target"
cp -a "$TEST_ROOT/." "$install_payload_source"
mkdir -p "$install_payload_source/.git" "$install_payload_source/.github/workflows" "$install_payload_target"
printf 'git metadata\n' >"$install_payload_source/.git/config"
printf 'ci metadata\n' >"$install_payload_source/.github/workflows/ci.yml"
(
    THIS_INSTALL_DIR="$install_payload_source"
    CLASH_BASE_DIR="$install_payload_target"
    eval "$(extract_function _copy_install_payload "$INSTALL_SH")"
    _copy_install_payload
) || fail "install payload copy should succeed"
[ -f "$install_payload_target/scripts/cmd/clashctl.sh" ] ||
    fail "install payload should include runtime scripts"
[ -f "$install_payload_target/config/mixin.yaml" ] ||
    fail "install payload should include default editable config"
[ ! -e "$install_payload_target/.git" ] ||
    fail "install payload should not copy source git metadata"
[ ! -e "$install_payload_target/.github" ] ||
    fail "install payload should not copy GitHub workflow metadata"
[ ! -e "$install_payload_target/.editorconfig" ] ||
    fail "install payload should not copy editor-only metadata"

assert_file_contains "$SYSTEMD_SH" 'placeholder_run_as_user' \
    "systemd service should be able to run as the sudo invoking user"

assert_file_contains "$SERVICE_RENDER_SH" 'User=\$SUDO_USER|User="\$SUDO_USER"|service_run_as_user' \
    "regular sudo systemd install should render a User= line"

assert_file_contains "$SERVICE_RENDER_SH" '/usr/bin/install -D -m 755' \
    "rendered service files should keep read permission for init managers"

assert_file_contains "$PREFLIGHT_SH" '_validate_install_path' \
    "install should explicitly reject paths that shell templates cannot safely support"

assert_file_contains "$SERVICE_RENDER_SH" '_install_service\(\)' \
    "preflight should define install service rendering"

assert_file_contains "$PREFLIGHT_SH" '_fetch_latest_tag\(\)' \
    "preflight should support resolving latest dependency versions when version variables are empty"

assert_file_contains "$PREFLIGHT_SH" '_resolve_version VERSION_MIHOMO MetaCubeX/mihomo' \
    "preflight should resolve missing mihomo version from GitHub latest release"

assert_file_contains "$PREFLIGHT_SH" '_resolve_version VERSION_YQ mikefarah/yq' \
    "preflight should resolve missing yq version from GitHub latest release"

assert_file_contains "$PREFLIGHT_SH" '_resolve_version VERSION_SUBCONVERTER "\$subconverter_repo"' \
    "preflight should resolve missing subconverter version from the configured repository"

latest_version_tmp=$(make_test_tmpdir "clash-latest-version")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    curl() {
        printf '%s\n' '{"tag_name":"v9.9.9"}'
    }

    VERSION_YQ=
    _resolve_version VERSION_YQ mikefarah/yq >/dev/null || exit 1
    printf '%s\n' "$VERSION_YQ" >"$latest_version_tmp/version"
)
grep -qx 'v9.9.9' "$latest_version_tmp/version" ||
    fail "empty dependency version should be resolved from the latest release tag"

latest_version_proxy_tmp=$(make_test_tmpdir "clash-latest-version-proxy")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    curl() {
        printf '%s\n' "$*" >"$latest_version_proxy_tmp/curl.args"
        printf '%s\n' '{"tag_name":"v9.9.9"}'
    }

    VERSION_YQ=
    URL_GH_PROXY=https://gh-proxy.org
    _resolve_version VERSION_YQ mikefarah/yq >/dev/null || exit 1
)
grep -q 'https://gh-proxy.org/https://api.github.com/repos/mikefarah/yq/releases/latest' "$latest_version_proxy_tmp/curl.args" ||
    fail "latest release tag resolution should honor URL_GH_PROXY"

assert_file_contains "$SYSTEMD_SH" 'CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE' \
    "systemd service should keep only network-related capabilities"

assert_file_not_contains "$SYSTEMD_SH" 'CAP_SYS_PTRACE|CAP_DAC_OVERRIDE|CAP_DAC_READ_SEARCH|CAP_SYS_TIME' \
    "systemd service should not grant unrelated broad capabilities"

assert_file_contains "$SUBSCRIPTION_SH" '_download_config "\$CLASH_CONFIG_TEMP" "\$url" \\|\\|' \
    "clashsub add should stop immediately when subscription download fails"

assert_file_contains "$SUBSCRIPTION_SH" '_download_convert_config "\$CLASH_CONFIG_TEMP" "\$url" \\|\\|' \
    "clashsub update --convert should stop immediately when conversion download fails"

assert_file_contains "$SUBSCRIPTION_SH" '_download_config "\$CLASH_CONFIG_TEMP" "\$url" \\|\\|' \
    "clashsub update should stop immediately when subscription download fails"

assert_file_contains "$SUBSCRIPTION_SH" '_make_config_temp' \
    "subscription updates should use a fresh temporary file instead of reusing stale temp.yaml"

assert_file_contains "$SUBSCRIPTION_SH" 'mktemp "\$\{CLASH_RESOURCES_DIR\}/temp\.' \
    "subscription temporary files should be created with mktemp"

assert_file_contains "$TUN_SH" '_merge_config \\|\\|' \
    "tun operations should be able to recover when merge validation fails"

assert_file_contains "$TEST_ROOT/scripts/lib/config.sh" 'mktemp "\$\{runtime_dir\}/\.runtime\.' \
    "runtime config merges should write a same-directory temporary file before replacing runtime.yaml"

assert_file_contains "$SUBSCRIPTION_SH" '_merge_config_restart \\|\\| return 1' \
    "clashsub use should stop when runtime merge fails"

assert_file_contains "$CLASHCTL_SH" 'tun[[:space:]]+管理 Tun 模式' \
    "clashctl help should list the tun command"

assert_file_contains "$PREFLIGHT_SH" 'CLASH_INSTALL_CREATED_DIR|trap .*CLASH_BASE_DIR|staging' \
    "install should clean up directories it created when install preparation fails"

cleanup_tmp=$(make_test_tmpdir "clash-cleanup")
cleanup_target="${cleanup_tmp}/install"
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    CLASHCTL_ERROR_EXIT=1
    CLASH_BASE_DIR="$cleanup_target"
    _refresh_install_paths
    _register_install_cleanup
    mkdir -p "$CLASH_BASE_DIR"
    _error_quit "probe failure"
) >/dev/null 2>&1 || true
[ ! -e "$cleanup_target" ] ||
    fail "install cleanup trap should remove directories created before an install failure"

missing_service_tmp=$(make_test_tmpdir "clash-missing-service")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    KERNEL_NAME=mihomo
    BIN_KERNEL="$missing_service_tmp/mihomo"
    CLASH_RESOURCES_DIR="$missing_service_tmp/resources"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    FILE_LOG="$CLASH_RESOURCES_DIR/mihomo.log"
    FILE_PID="$CLASH_RESOURCES_DIR/mihomo.pid"
    service_src="$missing_service_tmp/missing.service"
    service_target="$missing_service_tmp/out.service"
    service_add=()
    service_enable=(false)
    service_reload=()

    _install_service >/dev/null 2>&1
    status=$?
    [ "$status" -ne 0 ] || fail "service template install failures should propagate"
)

bad_render_tmp=$(make_test_tmpdir "clash-bad-render")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    KERNEL_NAME=mihomo
    BIN_KERNEL="$bad_render_tmp/mihomo"
    CLASH_RESOURCES_DIR="$bad_render_tmp/resources"
    CLASH_CONFIG_RUNTIME="$CLASH_RESOURCES_DIR/runtime.yaml"
    FILE_LOG="$CLASH_RESOURCES_DIR/mihomo.log"
    FILE_PID="$CLASH_RESOURCES_DIR/mihomo.pid"
    service_src="$bad_render_tmp/template.service"
    service_target="$bad_render_tmp/render-target"
    service_add=()
    service_enable=(false)
    service_reload=()
    printf '%s\n' 'ExecStart=placeholder_cmd_full' >"$service_src"
    mkdir -p "$service_target"

    _install_service >/dev/null 2>&1
    status=$?
    [ "$status" -ne 0 ] || fail "service template render failures should propagate"
)

assert_file_contains "$ENV_FILE" 'SUBCONVERTER_REPO=' \
    "subconverter source should be configurable like upstream"

assert_file_contains "$ENV_FILE" '^SUBCONVERTER_REPO=tindy2013/subconverter$' \
    "default subconverter source should point at the official release repository"

assert_file_contains "$ENV_FILE" '^VERSION_YQ=v4\.53\.3$' \
    "default yq version should track the current vetted latest release"

assert_file_contains "$ENV_FILE" 'CLASHCTL_DOWNLOAD_TIMEOUT=' \
    "dependency download timeout should be configurable like upstream"

assert_file_contains "$ENV_FILE" 'CLASHCTL_SUB_TIMEOUT=' \
    "subscription download timeout should be configurable like upstream"

assert_file_contains "$ENV_FILE" 'VERSION_MIHOMO.*VERSION_YQ.*VERSION_SUBCONVERTER|留空时安装脚本会通过 GitHub releases/latest 自动解析最新 tag' \
    "dependency version comments should document latest-tag resolution"

valid_zip_tmp=$(make_test_tmpdir "clash-valid-zip")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    printf 'ok\n' | gzip >"$valid_zip_tmp/ok.gz"
    _valid_zip "$valid_zip_tmp/ok.gz"
    status=$?
    [ "$status" -eq 0 ] ||
        fail "_valid_zip should return success when every archive validates"
)

valid_install_tmp=$(make_test_tmpdir "clash-valid-install")
(
    set +e
    . "$CLASHCTL_SH"
    . "$PREFLIGHT_SH"

    INIT_TYPE=nohup
    CLASH_BASE_DIR="$valid_install_tmp/install"
    HOME="$valid_install_tmp/home"
    mkdir -p "$HOME"
    _refresh_install_paths

    _valid_required
    status=$?
    [ "$status" -eq 0 ] ||
        fail "_valid_required should return success when required commands exist"

    _valid
    status=$?
    [ "$status" -eq 0 ] ||
        fail "_valid should return success for a safe fresh install directory"
)

subconverter_port_tmp=$(make_test_tmpdir "clash-subconverter-port")
(
    set +e
    . "$CLASHCTL_SH"

    BIN_SUBCONVERTER_CONFIG="$subconverter_port_tmp/pref.yml"
    BIN_YQ="$subconverter_port_tmp/yq"
    BIN_SUBCONVERTER_PORT=
    printf 'server:\n  port: 25500\n' >"$BIN_SUBCONVERTER_CONFIG"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-i" ]; then
    exit 0
fi
if [ "${1:-}" = ".server.port" ]; then
    printf '25500\n'
    exit 0
fi
exit 7
EOF
    chmod +x "$BIN_YQ"

    "$BIN_YQ" -i '.server.port = 25500' "$BIN_SUBCONVERTER_CONFIG" >/dev/null 2>&1 || true
    _is_port_used() { return 1; }
    _detect_subconverter_port
    status=$?
    [ "$status" -eq 0 ] ||
        fail "_detect_subconverter_port should return success when the configured port is free"
    [ "$BIN_SUBCONVERTER_PORT" = 25500 ] ||
        fail "_detect_subconverter_port should keep the configured port when it is free"
)

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

sub_add_use_tmp=$(make_test_tmpdir "clash-sub-add-use")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_RESOURCES_DIR="$sub_add_use_tmp/resources"
    CLASH_PROFILES_DIR="$sub_add_use_tmp/profiles"
    CLASH_PROFILES_META="$sub_add_use_tmp/profiles.yaml"
    CLASH_PROFILES_LOG="$sub_add_use_tmp/profiles.log"
    BIN_YQ="$sub_add_use_tmp/yq"
    mkdir -p "$CLASH_RESOURCES_DIR" "$CLASH_PROFILES_DIR"
    printf 'profiles: []\n' >"$CLASH_PROFILES_META"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
-i)
    exit 0
    ;;
*)
    printf '7\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"

    _error_quit() { return 97; }
    _get_id_by_url() { return 1; }
    _make_config_temp() {
        printf '%s\n' "$sub_add_use_tmp/temp.yaml"
    }
    _download_config() {
        printf '%s\n' "$2" >>"$sub_add_use_tmp/downloaded-url"
        printf 'profile\n' >"$1"
    }
    _valid_config() { return 0; }
    _logging_sub() { :; }
    _okcat() { :; }
    _sub_use() {
        printf '%s\n' "$1" >>"$sub_add_use_tmp/used-id"
    }

    _sub_add -u "https://example.invalid/sub-a"
    _sub_add --use "https://example.invalid/sub-b"
    _sub_add "https://example.invalid/sub-c"
    plain_add_status=$?
    [ "$plain_add_status" -eq 0 ] ||
        fail "clashsub add without --use should return success after adding the subscription"
)
grep -qx 'https://example.invalid/sub-a' "$sub_add_use_tmp/downloaded-url" ||
    fail "clashsub add -u should treat the following argument as the subscription URL"
grep -qx 'https://example.invalid/sub-b' "$sub_add_use_tmp/downloaded-url" ||
    fail "clashsub add --use should treat the following argument as the subscription URL"
grep -qx 'https://example.invalid/sub-c' "$sub_add_use_tmp/downloaded-url" ||
    fail "clashsub add without --use should still add the subscription"
[ "$(grep -c '^7$' "$sub_add_use_tmp/used-id")" -eq 2 ] ||
    fail "clashsub add -u/--use should immediately activate the added subscription"

install_subscribe_flow_tmp=$(make_test_tmpdir "clash-install-subscribe-flow")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_RESOURCES_DIR="$install_subscribe_flow_tmp/resources"
    CLASH_PROFILES_DIR="$install_subscribe_flow_tmp/profiles"
    CLASH_PROFILES_META="$install_subscribe_flow_tmp/profiles.yaml"
    CLASH_PROFILES_LOG="$install_subscribe_flow_tmp/profiles.log"
    CLASH_CONFIG_URL="https://example.invalid/install-sub"
    BIN_YQ="$install_subscribe_flow_tmp/yq"
    mkdir -p "$CLASH_RESOURCES_DIR" "$CLASH_PROFILES_DIR"
    printf 'profiles: []\n' >"$CLASH_PROFILES_META"
    cat >"$BIN_YQ" <<'EOF'
#!/usr/bin/env bash
case "$1" in
-i)
    exit 0
    ;;
*)
    printf '1\n'
    ;;
esac
EOF
    chmod +x "$BIN_YQ"

    _error_quit() { return 97; }
    _get_id_by_url() { return 1; }
    _make_config_temp() {
        printf '%s\n' "$install_subscribe_flow_tmp/temp.yaml"
    }
    _download_config() {
        printf 'profile\n' >"$1"
    }
    _valid_config() { return 0; }
    _logging_sub() { :; }
    _okcat() { :; }
    _sub_use() {
        printf '%s\n' "$1" >"$install_subscribe_flow_tmp/used-id"
        return 0
    }

    if [ -n "$CLASH_CONFIG_URL" ]; then
        clashsub add "$CLASH_CONFIG_URL" || exit $?
    else
        clashsub add || exit $?
    fi
    printf 'continued\n' >"$install_subscribe_flow_tmp/continued"
    clashsub use 1 || exit $?
)
[ -f "$install_subscribe_flow_tmp/continued" ] ||
    fail "install subscribe flow should continue after clashsub add succeeds without --use"
grep -qx '1' "$install_subscribe_flow_tmp/used-id" ||
    fail "install subscribe flow should activate subscription after adding it"

sub_delete_tmp=$(make_test_tmpdir "clash-sub-delete")
(
    set +e
    . "$CLASHCTL_SH"

    _sub_del() {
        printf '%s\n' "$1" >"$sub_delete_tmp/deleted-id"
    }

    clashsub delete 5
)
grep -qx '5' "$sub_delete_tmp/deleted-id" ||
    fail "clashsub delete should alias clashsub del like upstream"

sub_update_args_tmp=$(make_test_tmpdir "clash-sub-update-args")
(
    set +e
    . "$CLASHCTL_SH"

    _error_quit() { return 97; }
    _get_url_by_id() {
        printf '%s\n' "$1" >"$sub_update_args_tmp/seen-id"
        return 1
    }

    _sub_update 1 --convert || true
)
grep -qx '1' "$sub_update_args_tmp/seen-id" ||
    fail "clashsub update <id> --convert should preserve the subscription id"

rollback_tmp=$(make_test_tmpdir "clash-rollback")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_BASE="$rollback_tmp/config.yaml"
    CLASH_PROFILES_META="$rollback_tmp/profiles.yaml"
    test_profile_path="$rollback_tmp/profile.yaml"
    yq_stub="$rollback_tmp/yq"
    printf 'old-base\n' >"$CLASH_CONFIG_BASE"
    printf 'use: 0\n' >"$CLASH_PROFILES_META"
    printf 'new-profile\n' >"$test_profile_path"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$yq_stub"
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _error_quit() { return 97; }
    _get_path_by_id() { printf '%s\n' "$test_profile_path"; }
    _get_url_by_id() { printf '%s\n' "file://profile"; }
    _merge_config_restart() { return 1; }
    _logging_sub() { :; }
    _okcat() { :; }

    _sub_use 1
    status=$?
    [ "$status" -ne 0 ] || fail "clashsub use should fail when runtime merge fails"
    [ "$(cat "$CLASH_CONFIG_BASE")" = "old-base" ] ||
        fail "clashsub use should restore config.yaml when runtime merge fails"
)

sub_use_missing_tmp=$(make_test_tmpdir "clash-sub-use-missing")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_BASE="$sub_use_missing_tmp/config.yaml"
    CLASH_PROFILES_META="$sub_use_missing_tmp/profiles.yaml"
    yq_stub="$sub_use_missing_tmp/yq"
    printf 'old-base\n' >"$CLASH_CONFIG_BASE"
    printf 'profiles: []\n' >"$CLASH_PROFILES_META"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$yq_stub"
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _error_quit() { return 97; }
    _get_path_by_id() { printf '%s\n' "$sub_use_missing_tmp/missing-profile.yaml"; }
    _get_url_by_id() { printf '%s\n' "file://missing"; }
    _merge_config_restart() {
        printf 'merge-restart\n' >>"$sub_use_missing_tmp/calls"
        return 0
    }

    _sub_use 1
    status=$?
    [ "$status" -ne 0 ] || fail "clashsub use should fail when the selected profile file is missing"
    [ "$(cat "$CLASH_CONFIG_BASE")" = "old-base" ] ||
        fail "clashsub use should not truncate config.yaml when the selected profile is missing"
    [ ! -e "$sub_use_missing_tmp/calls" ] ||
        fail "clashsub use should not restart when profile replacement failed"
)

sub_use_meta_fail_tmp=$(make_test_tmpdir "clash-sub-use-meta-fail")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_BASE="$sub_use_meta_fail_tmp/config.yaml"
    CLASH_PROFILES_META="$sub_use_meta_fail_tmp/profiles.yaml"
    test_profile_path="$sub_use_meta_fail_tmp/profile.yaml"
    yq_stub="$sub_use_meta_fail_tmp/yq"
    printf 'old-base\n' >"$CLASH_CONFIG_BASE"
    printf 'new-profile\n' >"$test_profile_path"
    printf 'use: 0\n' >"$CLASH_PROFILES_META"
    cat >"$yq_stub" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-i" ]; then
    exit 9
fi
exit 0
EOF
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _error_quit() { return 97; }
    _get_path_by_id() { printf '%s\n' "$test_profile_path"; }
    _get_url_by_id() { printf '%s\n' "file://profile"; }
    _merge_config_restart() {
        printf 'merge-restart\n' >>"$sub_use_meta_fail_tmp/calls"
        return 0
    }

    _sub_use 1
    status=$?
    [ "$status" -ne 0 ] || fail "clashsub use should fail when metadata write fails"
    [ "$(cat "$CLASH_CONFIG_BASE")" = "old-base" ] ||
        fail "clashsub use should not switch config.yaml when metadata write fails"
    [ ! -e "$sub_use_meta_fail_tmp/calls" ] ||
        fail "clashsub use should not restart when metadata write fails"
)

sub_del_meta_fail_tmp=$(make_test_tmpdir "clash-sub-del-meta-fail")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_PROFILES_META="$sub_del_meta_fail_tmp/profiles.yaml"
    test_profile_path="$sub_del_meta_fail_tmp/profile.yaml"
    yq_stub="$sub_del_meta_fail_tmp/yq"
    printf 'profile\n' >"$test_profile_path"
    printf 'profiles:\n  - id: 1\n    path: %s\n    url: file://profile\n' "$test_profile_path" >"$CLASH_PROFILES_META"
    cat >"$yq_stub" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-i" ]; then
    exit 9
fi
case "$1" in
'.use // ""')
    printf '\n'
    ;;
*)
    exit 0
    ;;
esac
EOF
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _error_quit() { return 97; }
    _get_path_by_id() { printf '%s\n' "$test_profile_path"; }
    _get_url_by_id() { printf '%s\n' "file://profile"; }

    _sub_del 1
    status=$?
    [ "$status" -ne 0 ] || fail "clashsub del should fail when metadata write fails"
    [ -f "$test_profile_path" ] ||
        fail "clashsub del should not delete profile before metadata update succeeds"
)

update_tmp=$(make_test_tmpdir "clash-update-rollback")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_RESOURCES_DIR="$update_tmp"
    CLASH_CONFIG_BASE="$update_tmp/config.yaml"
    CLASH_PROFILES_META="$update_tmp/profiles.yaml"
    CLASH_CONFIG_TEMP="$update_tmp/temp.yaml"
    CLASH_PROFILES_LOG="$update_tmp/profiles.log"
    test_profile_path="$update_tmp/profile.yaml"
    yq_stub="$update_tmp/yq"
    printf 'old-base\n' >"$CLASH_CONFIG_BASE"
    printf 'use: 1\n' >"$CLASH_PROFILES_META"
    printf 'old-profile\n' >"$test_profile_path"
    cat >"$yq_stub" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.use // ""'|'.use // 1')
    printf '1\n'
    ;;
*)
    exit 0
    ;;
esac
EOF
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _error_quit() { return 97; }
    _make_config_temp() { printf '%s\n' "$update_tmp/download.yaml"; }
    _download_config() { printf 'new-download\n' >"$1"; return 0; }
    _valid_config() { return 0; }
    _get_url_by_id() { printf '%s\n' "https://example.invalid/sub"; }
    _get_path_by_id() { printf '%s\n' "$test_profile_path"; }
    _merge_config_restart() { return 1; }
    _logging_sub() {
        case "$1" in
        *"订阅更新成功"*) logged_update_success=true ;;
        esac
    }
    _okcat() { :; }

    logged_update_success=false
    _sub_update 1
    status=$?
    [ "$status" -ne 0 ] || fail "clashsub update should fail when current profile merge fails"
    [ "$logged_update_success" = false ] ||
        fail "clashsub update should not log success before the active profile is applied"
    [ "$(cat "$test_profile_path")" = "old-profile" ] ||
        fail "clashsub update should keep old profile when current profile merge fails"
    [ "$(cat "$CLASH_CONFIG_BASE")" = "old-base" ] ||
        fail "clashsub update should keep old base when current profile merge fails"
)

update_missing_tmp=$(make_test_tmpdir "clash-update-missing-temp")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_RESOURCES_DIR="$update_missing_tmp"
    CLASH_CONFIG_BASE="$update_missing_tmp/config.yaml"
    CLASH_PROFILES_META="$update_missing_tmp/profiles.yaml"
    CLASH_CONFIG_TEMP="$update_missing_tmp/temp.yaml"
    CLASH_PROFILES_LOG="$update_missing_tmp/profiles.log"
    test_profile_path="$update_missing_tmp/profile.yaml"
    yq_stub="$update_missing_tmp/yq"
    printf 'old-profile\n' >"$test_profile_path"
    cat >"$yq_stub" <<'EOF'
#!/usr/bin/env bash
case "$1" in
'.use // ""'|'.use // 1')
    printf '\n'
    ;;
*)
    exit 0
    ;;
esac
EOF
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _error_quit() { return 97; }
    _make_config_temp() { printf '%s\n' "$update_missing_tmp/download.yaml"; }
    _download_config() { return 0; }
    _valid_config() { return 0; }
    _get_url_by_id() { printf '%s\n' "https://example.invalid/sub"; }
    _get_path_by_id() { printf '%s\n' "$test_profile_path"; }

    _sub_update 1
    status=$?
    [ "$status" -ne 0 ] || fail "clashsub update should fail when the downloaded temp file is missing"
    [ "$(cat "$test_profile_path")" = "old-profile" ] ||
        fail "clashsub update should not truncate an existing profile when temp replacement fails"
)

secret_tmp=$(make_test_tmpdir "clash-secret-rollback")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_MIXIN="$secret_tmp/mixin.yaml"
    yq_stub="$secret_tmp/yq"
    printf 'secret: old\n' >"$CLASH_CONFIG_MIXIN"
    cat >"$yq_stub" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-i" ]; then
    printf 'secret: new\n' >"$3"
fi
EOF
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _merge_config_restart() { return 1; }
    _failcat() { :; }
    _okcat() { :; }

    clashsecret new
    status=$?
    [ "$status" -ne 0 ] || fail "clashsecret should fail when runtime merge/restart fails"
    [ "$(cat "$CLASH_CONFIG_MIXIN")" = "secret: old" ] ||
        fail "clashsecret should restore mixin when runtime merge/restart fails"
)

secret_quote_tmp=$(make_test_tmpdir "clash-secret-quote")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_MIXIN="$secret_quote_tmp/mixin.yaml"
    yq_stub="$secret_quote_tmp/yq"
    printf 'secret: old\n' >"$CLASH_CONFIG_MIXIN"
    cat >"$yq_stub" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-i" ]; then
    [ "$2" = '.secret = strenv(CLASHCTL_SECRET)' ] || exit 2
    printf 'secret: %s\n' "$CLASHCTL_SECRET" >"$3"
fi
EOF
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _merge_config_restart() { return 0; }
    _failcat() { :; }
    _okcat() { :; }

    clashsecret 'a"b'
    status=$?
    [ "$status" -eq 0 ] || fail "clashsecret should pass literal secret values through yq environment input"
    [ "$(cat "$CLASH_CONFIG_MIXIN")" = 'secret: a"b' ] ||
        fail "clashsecret should preserve quote characters in secret values"
)

secret_yq_fail_tmp=$(make_test_tmpdir "clash-secret-yq-fail")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_MIXIN="$secret_yq_fail_tmp/mixin.yaml"
    yq_stub="$secret_yq_fail_tmp/yq"
    printf 'secret: old\n' >"$CLASH_CONFIG_MIXIN"
    cat >"$yq_stub" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-i" ]; then
    printf 'secret: partial\n' >"$3"
    exit 1
fi
EOF
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _merge_config_restart() { return 0; }
    _failcat() { :; }
    _okcat() { :; }

    clashsecret new
    status=$?
    [ "$status" -ne 0 ] || fail "clashsecret should fail when yq cannot write the secret"
    [ "$(cat "$CLASH_CONFIG_MIXIN")" = "secret: old" ] ||
        fail "clashsecret should restore mixin when yq write fails"
)

tun_tmp=$(make_test_tmpdir "clash-tunoff")
(
    set +e
    . "$CLASHCTL_SH"

    CLASH_CONFIG_MIXIN="$tun_tmp/mixin.yaml"
    CLASH_CONFIG_TEMP="$tun_tmp/temp.yaml"
    yq_stub="$tun_tmp/yq"
    printf 'tun:\n  enable: true\n' >"$CLASH_CONFIG_MIXIN"
    cat >"$yq_stub" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$yq_stub"
    BIN_YQ="$yq_stub"

    _tun_supported() { return 0; }
    _is_tun_enabled() { return 0; }
    tunstatus() { return 1; }
    placeholder_is_active() { return 1; }
    placeholder_stop() { stop_called=true; }
    placeholder_start() { start_called=true; return 0; }
    _merge_config() { return 0; }
    _failcat() { :; }
    _okcat() { :; }

    start_called=false
    stop_called=false
    tunoff
    status=$?
    [ "$status" -eq 0 ] || fail "tunoff should succeed when only disabling stale tun.enable"
    [ "$start_called" = false ] || fail "tunoff should not start a service that was stopped before"
)

pass "review regression checks"
