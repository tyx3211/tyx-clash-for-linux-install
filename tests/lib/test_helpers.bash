#!/usr/bin/env bash

set -u

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)

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
        $0 ~ "^" name "\\(\\)[[:space:]]*\\{" {
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
