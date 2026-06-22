#!/usr/bin/env bash

_detect_rc() {
    local home=$HOME
    _is_regular_sudo && home=$(awk -F: -v user="$SUDO_USER" '$1==user{print $6}' /etc/passwd)

    command -v bash >&/dev/null && {
        SHELL_RC_BASH="${home}/.bashrc"
    }
    command -v zsh >&/dev/null && {
        SHELL_RC_ZSH="${home}/.zshrc"
    }
    command -v fish >&/dev/null && {
        SHELL_RC_FISH="${home}/.config/fish/conf.d/clashctl.fish"
    }
    start_flag="# clashctl START"
    end_flag="# clashctl END"
}

_chown_sudo_user_path() {
    local path=$1 group
    _is_regular_sudo || return 0
    [ -e "$path" ] || return 0

    group=$(id -gn "$SUDO_USER" 2>/dev/null || true)
    if [ -n "$group" ]; then
        chown "$SUDO_USER:$group" "$path" 2>/dev/null || true
    else
        chown "$SUDO_USER" "$path" 2>/dev/null || true
    fi
}

_apply_rc() {
    _detect_rc
    local source_clashctl=". $CLASH_CMD_DIR/clashctl.sh"
    _revoke_rc
    # shellcheck disable=SC2086
    tee -a "$SHELL_RC_BASH" $SHELL_RC_ZSH >/dev/null <<EOF

$start_flag $CLASH_CMD_DIR
# 加载 clashctl 命令
$source_clashctl
# 按 sidecar 配置检查是否写入代理变量
watch_proxy
$end_flag $CLASH_CMD_DIR
EOF
    [ -n "$SHELL_RC_BASH" ] && _chown_sudo_user_path "$SHELL_RC_BASH"
    [ -n "$SHELL_RC_ZSH" ] && _chown_sudo_user_path "$SHELL_RC_ZSH"
    [ -n "$SHELL_RC_FISH" ] && {
        /usr/bin/install -D -m 644 "$SCRIPT_CMD_FISH" "$SHELL_RC_FISH"
        sed -i "1iset -gx CLASHCTL_CMD_DIR $(_shell_quote "$CLASH_CMD_DIR")" "$SHELL_RC_FISH"
        _chown_sudo_user_path "$(dirname "$(dirname "$(dirname "$SHELL_RC_FISH")")")"
        _chown_sudo_user_path "$(dirname "$(dirname "$SHELL_RC_FISH")")"
        _chown_sudo_user_path "$(dirname "$SHELL_RC_FISH")"
        _chown_sudo_user_path "$SHELL_RC_FISH"
    }
    $source_clashctl
}

_revoke_rc_file() {
    local rc_file=$1 source_clashctl=". $CLASH_CMD_DIR/clashctl.sh"
    [ -f "$rc_file" ] || return 0

    local rc_target=$rc_file
    if [ -L "$rc_file" ]; then
        rc_target=$(readlink -f "$rc_file") || return 1
    fi
    [ -f "$rc_target" ] || return 0

    local rc_dir tmp_file
    rc_dir=$(dirname "$rc_target")
    tmp_file=$(mktemp "${rc_dir}/.clashctl-rc.XXXXXX") || return 1
    chmod --reference="$rc_target" "$tmp_file" 2>/dev/null || true
    chown --reference="$rc_target" "$tmp_file" 2>/dev/null || true

    awk -v source="$source_clashctl" '
        /^# clashctl START/ {
            in_block = 1
            matched = 0
            block = $0 ORS
            next
        }
        in_block {
            block = block $0 ORS
            if ($0 == source) {
                matched = 1
            }
            if ($0 ~ /^# clashctl END/) {
                if (!matched) {
                    printf "%s", block
                }
                in_block = 0
                block = ""
            }
            next
        }
        { print }
        END {
            if (in_block) {
                printf "%s", block
            }
        }
    ' "$rc_target" >"$tmp_file" && /bin/mv -f "$tmp_file" "$rc_target"
}

_revoke_rc() {
    _detect_rc
    _revoke_rc_file "$SHELL_RC_BASH"
    _revoke_rc_file "$SHELL_RC_ZSH"
    [ -n "$SHELL_RC_FISH" ] && rm -f "$SHELL_RC_FISH" 2>/dev/null
}
