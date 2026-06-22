#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/lib/test_helpers.bash"

PATH_ENV_SH="$TEST_ROOT/scripts/lib/path-env.sh"
[ -f "$PATH_ENV_SH" ] || fail "path-env helper should exist"

. "$PATH_ENV_SH"

path_env_tmp=$(make_test_tmpdir "clash-path-env")
path_env_home="$path_env_tmp/home"
path_env_file="$path_env_tmp/.env"
path_env_executed="$path_env_tmp/executed"
mkdir -p "$path_env_home"

cat >"$path_env_file" <<EOF
# ignored comment
export CLASHCTL_HOME='\${HOME}/legacy-clash'
CLASHCTL_KERNEL=clash
CLASHCTL_SUB_UA=legacy-agent
CLASH_CONFIG_URL="\$(touch $path_env_executed)"
PATH=/definitely/not/a/path
EOF

_path_env_key_allowed CLASH_BASE_DIR ||
    fail "path-env should allow canonical install directory keys"
_path_env_key_allowed CLASHCTL_HOME ||
    fail "path-env should allow legacy upstream install directory keys"
! _path_env_key_allowed PATH ||
    fail "path-env should reject non-whitelisted keys such as PATH"

(
    HOME="$path_env_home"
    [ "$(_path_env_expand_path '~/clashctl')" = "$path_env_home/clashctl" ] ||
        fail "path-env should expand literal ~/ prefixes"
    [ "$(_path_env_expand_path '${HOME}/clashctl')" = "$path_env_home/clashctl" ] ||
        fail "path-env should expand literal \${HOME}/ prefixes"
    [ "$(_path_env_read_path_value "$path_env_file" CLASHCTL_HOME)" = "$path_env_home/legacy-clash" ] ||
        fail "path-env should expand path values only when requested"
)

config_url=$(_path_env_read_value "$path_env_file" CLASH_CONFIG_URL)
[ "$config_url" = "\$(touch $path_env_executed)" ] ||
    fail "path-env should read quoted values without executing them"
[ ! -e "$path_env_executed" ] ||
    fail "path-env should not execute command substitutions while reading .env"

! _path_env_read_value "$path_env_file" PATH >/dev/null 2>&1 ||
    fail "path-env should refuse reads of non-whitelisted keys"

(
    HOME="$path_env_home"
    old_path=$PATH
    _path_env_read_into_vars "$path_env_file"
    [ "$CLASH_BASE_DIR" = "$path_env_home/legacy-clash" ] ||
        fail "path-env should normalize CLASHCTL_HOME into CLASH_BASE_DIR"
    [ "$KERNEL_NAME" = clash ] ||
        fail "path-env should normalize CLASHCTL_KERNEL into KERNEL_NAME"
    [ "$CLASH_SUB_UA" = legacy-agent ] ||
        fail "path-env should normalize CLASHCTL_SUB_UA into CLASH_SUB_UA"
    [ "$PATH" = "$old_path" ] ||
        fail "path-env should not let .env override PATH"
)

pass "path-env helper checks"
