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
