#!/usr/bin/env bash

set -u

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)

TEST_TMP_ROOT=${TEST_TMP_BASE:-/tmp/tyx}
TEST_RUN_TMP_DIR=${TEST_RUN_TMP_DIR:-}

_cleanup_test_tmpdir() {
    local status=$?

    if [ "${TEST_KEEP_TMP:-0}" != 1 ] && [ -n "${TEST_RUN_TMP_DIR:-}" ]; then
        case "$TEST_RUN_TMP_DIR" in
        "" | "/" | "$HOME" | "$HOME/" | . | .. | ./* | ../*)
            ;;
        "$TEST_TMP_ROOT"/clash-test-run.*)
            /usr/bin/rm -rf "$TEST_RUN_TMP_DIR" 2>/dev/null || true
            ;;
        esac
    fi

    return "$status"
}

_init_test_tmpdir() {
    mkdir -p "$TEST_TMP_ROOT"
    TEST_RUN_TMP_DIR=$(mktemp -d "$TEST_TMP_ROOT/clash-test-run.XXXXXX") || exit 1
    trap _cleanup_test_tmpdir EXIT INT TERM
}

_init_test_tmpdir

TEST_SANDBOX_INSTALL_DIR=${TEST_SANDBOX_INSTALL_DIR:-"$TEST_RUN_TMP_DIR/sandbox-install"}
mkdir -p "$TEST_SANDBOX_INSTALL_DIR/bin" "$TEST_SANDBOX_INSTALL_DIR/config" "$TEST_SANDBOX_INSTALL_DIR/resources"

# Keep sourced clashctl tests away from the developer's real install. These are
# shell variables with export attributes removed, so child-process install tests
# still exercise their own default/argument parsing even if the caller exported
# a real install identity before invoking the test.
export -n CLASH_BASE_DIR KERNEL_NAME INIT_TYPE CLASH_INSTALLED_INIT_TYPE 2>/dev/null || true
CLASH_BASE_DIR=$TEST_SANDBOX_INSTALL_DIR
KERNEL_NAME=mihomo
INIT_TYPE=tmux
CLASH_INSTALLED_INIT_TYPE=tmux

unset_test_install_identity() {
    unset CLASH_BASE_DIR
    unset KERNEL_NAME
    unset INIT_TYPE
    unset CLASH_INSTALLED_INIT_TYPE
}

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

pass() {
    printf 'ok - %s\n' "$1"
}

assert_file_contains() {
    local file=$1
    local pattern=$2
    local message=$3

    grep -Eq -- "$pattern" "$file" || fail "$message"
}

assert_file_not_contains() {
    local file=$1
    local pattern=$2
    local message=$3

    ! grep -Eq -- "$pattern" "$file" || fail "$message"
}

extract_function() {
    local function_name=$1
    local file=$2

    awk -v name="$function_name" '
        $0 ~ "^(function[[:space:]]+)?" name "\\(\\)[[:space:]]*\\{" {
            in_function = 1
            depth = 0
        }
        in_function {
            print
            depth += gsub(/\{/, "{")
            depth -= gsub(/\}/, "}")
            if (depth == 0) {
                exit
            }
        }
    ' "$file"
}

make_test_tmpdir() {
    local name=$1
    local base=${TEST_RUN_TMP_DIR:-$TEST_TMP_ROOT}

    mkdir -p "$base"
    mktemp -d "${base}/${name}.XXXXXX"
}

write_test_install_yq() {
    local install_root=$1

    mkdir -p "$install_root/bin"
    cat >"$install_root/bin/yq" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-n" ]; then
    if [ -n "${INSTALL_STATE_INSTALL_DIR+x}" ]; then
        printf 'install_dir: "%s"\n' "$INSTALL_STATE_INSTALL_DIR"
        printf 'kernel_name: "%s"\n' "$INSTALL_STATE_KERNEL_NAME"
        printf 'default_mode: "%s"\n' "$INSTALL_STATE_DEFAULT_MODE"
        printf 'installed_systemd_service: %s\n' "$INSTALL_STATE_SYSTEMD"
        printf 'versions:\n'
        printf '  mihomo: "%s"\n' "$INSTALL_STATE_VERSION_MIHOMO"
        printf '  yq: "%s"\n' "$INSTALL_STATE_VERSION_YQ"
        printf '  subconverter: "%s"\n' "$INSTALL_STATE_VERSION_SUBCONVERTER"
        exit 0
    fi

    if [ -n "${SERVICE_STATE_ACTIVE_MODE+x}" ]; then
        printf 'active_mode: %s\n' "$SERVICE_STATE_ACTIVE_MODE"
        if [ -n "${SERVICE_STATE_PID:-}" ]; then
            printf 'pid: %s\n' "$SERVICE_STATE_PID"
        fi
        printf 'started_at: %s\n' "$SERVICE_STATE_STARTED_AT"
        printf 'bin_kernel: "%s"\n' "$SERVICE_STATE_BIN_KERNEL"
        printf 'config_runtime: "%s"\n' "$SERVICE_STATE_CONFIG_RUNTIME"
        exit 0
    fi

    printf 'system-proxy:\n'
    printf '  enable: false\n'
    printf '  mode: silent\n'
    exit 0
fi

if [ "${1:-}" = "-i" ]; then
    exit 0
fi

if [ "${1:-}" = "-e" ]; then
    shift
fi

expr=${1:-}
file=${2:-}
case "$expr" in
'.install_dir // ""')
    key=install_dir
    ;;
'.kernel_name // ""')
    key=kernel_name
    ;;
'.default_mode // ""')
    key=default_mode
    ;;
'.installed_systemd_service // ""')
    key=installed_systemd_service
    ;;
'.active_mode // ""')
    key=active_mode
    ;;
'.["system-proxy"].enable')
    printf 'false\n'
    exit 0
    ;;
'.["system-proxy"].mode // "silent"')
    printf 'silent\n'
    exit 0
    ;;
*)
    exit 7
    ;;
esac
awk -F': *' -v key="$key" '
    $1 == key {
        value = $0
        sub(/^[^:]*:[[:space:]]*/, "", value)
        gsub(/^"|"$/, "", value)
        print value
        found = 1
        exit
    }
    END {
        if (!found) {
            print ""
        }
    }
' "$file"
EOF
    chmod +x "$install_root/bin/yq"
}

write_test_install_yq "$TEST_SANDBOX_INSTALL_DIR"
