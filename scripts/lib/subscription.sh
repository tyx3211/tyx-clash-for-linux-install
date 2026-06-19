function clashsub() {
    case "$1" in
    add)
        shift
        _sub_add "$@"
        ;;
    del | delete)
        shift
        _sub_del "$@"
        ;;
    list | ls | '')
        shift
        _sub_list "$@"
        ;;
    use)
        shift
        _sub_use "$@"
        ;;
    update)
        shift
        _sub_update "$@"
        ;;
    log)
        shift
        _sub_log "$@"
        ;;
    -h | --help | *)
        cat <<EOF
clashsub - Clash 订阅管理工具

Usage:
  clashsub COMMAND [OPTIONS]

Commands:
  add [-u|--use] <url>
                  添加订阅
  ls              查看订阅
  del|delete <id> 删除订阅
  use <id>        使用订阅
  update [id]     更新订阅
  log             订阅日志

Options:
  update:
    --auto        配置自动更新
    --convert     使用订阅转换
EOF
        ;;
    esac
}
_sub_add() {
    local use_after_add=false url=
    while (($#)); do
        case "$1" in
        -h | --help)
            cat <<EOF

- 添加订阅
  clashsub add <url>

- 添加后立即使用该订阅
  clashsub add -u <url>
  clashsub add --use <url>

EOF
            return 0
            ;;
        -u | --use)
            use_after_add=true
            ;;
        --)
            shift
            break
            ;;
        -*)
            _error_quit "未知选项：$1"
            return 1
            ;;
        *)
            [ -n "$url" ] && {
                _error_quit "仅支持一个订阅链接"
                return 1
            }
            url=$1
            ;;
        esac
        shift
    done
    [ -z "$url" ] && [ $# -gt 0 ] && url=$1
    [ -z "$url" ] && {
        echo -n "$(_okcat '✈️ ' '请输入要添加的订阅链接：')"
        read -r url
        [ -z "$url" ] && _error_quit "订阅链接不能为空"
    }
    local existing_id
    existing_id=$(_get_id_by_url "$url") && {
        _error_quit "该订阅链接已存在：[$existing_id] $url"
        return 1
    }

    local CLASH_CONFIG_TEMP
    CLASH_CONFIG_TEMP=$(_make_config_temp) || {
        _error_quit "无法创建订阅临时文件"
        return 1
    }
    _download_config "$CLASH_CONFIG_TEMP" "$url" || {
        _error_quit "订阅下载失败：$url"
        return 1
    }
    _valid_config "$CLASH_CONFIG_TEMP" || {
        _error_quit "订阅无效，请检查：
    原始订阅：${CLASH_CONFIG_TEMP}.raw
    转换订阅：$CLASH_CONFIG_TEMP
    转换日志：$BIN_SUBCONVERTER_LOG"
        return 1
    }

    local id=$("$BIN_YQ" '.profiles // [] | (map(.id) | max) // 0 | . + 1' "$CLASH_PROFILES_META")
    local profile_path="${CLASH_PROFILES_DIR}/${id}.yaml"
    mv "$CLASH_CONFIG_TEMP" "$profile_path"

    PROFILE_ID=$id PROFILE_PATH=$profile_path PROFILE_URL=$url \
        "$BIN_YQ" -i '
            .profiles = (.profiles // []) +
            [{
              "id": (env(PROFILE_ID) | tonumber),
              "path": env(PROFILE_PATH),
              "url": env(PROFILE_URL)
            }]
        ' "$CLASH_PROFILES_META"
    _logging_sub "➕ 已添加订阅：[$id] $url"
    _okcat '🎉' "订阅已添加：[$id] $url"
    [ "$use_after_add" = true ] && _sub_use "$id"
}
_sub_del() {
    local id=$1
    [ -z "$id" ] && {
        echo -n "$(_okcat '✈️ ' '请输入要删除的订阅 id：')"
        read -r id
        [ -z "$id" ] && _error_quit "订阅 id 不能为空"
    }
    local profile_path url
    profile_path=$(_get_path_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    url=$(_get_url_by_id "$id")
    use=$("$BIN_YQ" '.use // ""' "$CLASH_PROFILES_META")
    [ "$use" = "$id" ] && _error_quit "删除失败：订阅 $id 正在使用中，请先切换订阅"
    /usr/bin/rm -f "$profile_path"
    PROFILE_ID=$id "$BIN_YQ" -i 'del(.profiles[] | select((.id | tostring) == env(PROFILE_ID)))' "$CLASH_PROFILES_META"
    _logging_sub "➖ 已删除订阅：[$id] $url"
    _okcat '🎉' "订阅已删除：[$id] $url"
}
_sub_list() {
    "$BIN_YQ" "$CLASH_PROFILES_META"
}
_sub_use() {
    "$BIN_YQ" -e '.profiles // [] | length == 0' "$CLASH_PROFILES_META" >&/dev/null &&
        _error_quit "当前无可用订阅，请先添加订阅"
    local id=$1
    [ -z "$id" ] && {
        clashsub ls
        echo -n "$(_okcat '✈️ ' '请输入要使用的订阅 id：')"
        read -r id
        [ -z "$id" ] && _error_quit "订阅 id 不能为空"
    }
    local profile_path url
    profile_path=$(_get_path_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    url=$(_get_url_by_id "$id")
    local base_backup="${CLASH_CONFIG_BASE}.sub-use.bak.$$" had_base=false
    [ -f "$CLASH_CONFIG_BASE" ] && {
        cat "$CLASH_CONFIG_BASE" >"$base_backup" || return 1
        had_base=true
    }
    cat "$profile_path" >"$CLASH_CONFIG_BASE" || return 1
    _merge_config_restart || {
        if [ "$had_base" = true ]; then
            /bin/mv -f "$base_backup" "$CLASH_CONFIG_BASE"
        else
            /usr/bin/rm -f "$CLASH_CONFIG_BASE" "$base_backup"
        fi
        _merge_config >/dev/null 2>&1 || true
        return 1
    }
    /usr/bin/rm -f "$base_backup"
    "$BIN_YQ" -i ".use = $id" "$CLASH_PROFILES_META"
    _logging_sub "🔥 订阅已切换为：[$id] $url"
    _okcat '🔥' '订阅已生效'
}
_get_path_by_id() {
    PROFILE_ID=$1 "$BIN_YQ" -e '.profiles[] | select((.id | tostring) == env(PROFILE_ID)) | .path' "$CLASH_PROFILES_META" 2>/dev/null
}
_get_url_by_id() {
    PROFILE_ID=$1 "$BIN_YQ" -e '.profiles[] | select((.id | tostring) == env(PROFILE_ID)) | .url' "$CLASH_PROFILES_META" 2>/dev/null
}
_make_config_temp() {
    mkdir -p "$CLASH_RESOURCES_DIR"
    mktemp "${CLASH_RESOURCES_DIR}/temp.XXXXXX.yaml"
}
_get_id_by_url() {
    PROFILE_URL=$1 "$BIN_YQ" -e '.profiles[] | select(.url == env(PROFILE_URL)) | (.id | tostring)' "$CLASH_PROFILES_META" 2>/dev/null
}
_sub_update() {
    local id= is_convert=false
    while (($#)); do
        case "$1" in
        --auto)
            command -v crontab >/dev/null || _error_quit "未检测到 crontab 命令，请先安装 cron 服务"
            crontab -l 2>/dev/null | grep -Fqs "$CLASHCTL_CRON_TAG" || {
                (
                    crontab -l 2>/dev/null | grep -Fv "$CLASHCTL_CRON_TAG"
                    printf "0 0 */2 * * %s -i -c 'clashsub update' %s\n" "$SHELL" "$CLASHCTL_CRON_TAG"
                ) | crontab -
            }
            _okcat "已设置定时更新订阅"
            return 0
            ;;
        --convert)
            is_convert=true
            ;;
        --)
            shift
            break
            ;;
        -*)
            _error_quit "未知选项：$1"
            return 1
            ;;
        *)
            [ -n "$id" ] && {
                _error_quit "仅支持一个订阅 id"
                return 1
            }
            id=$1
            ;;
        esac
        shift
    done
    [ -z "$id" ] && [ $# -gt 0 ] && id=$1
    [ -z "$id" ] && id=$("$BIN_YQ" '.use // 1' "$CLASH_PROFILES_META")
    local url profile_path
    url=$(_get_url_by_id "$id") || {
        _error_quit "订阅 id 不存在，请检查"
        return 1
    }
    profile_path=$(_get_path_by_id "$id") || {
        _error_quit "订阅 id 不存在，请检查"
        return 1
    }
    _okcat "✈️ " "更新订阅：[$id] $url"

    local CLASH_CONFIG_TEMP
    CLASH_CONFIG_TEMP=$(_make_config_temp) || {
        _error_quit "无法创建订阅临时文件"
        return 1
    }
    [ "$is_convert" = true ] && {
        _download_convert_config "$CLASH_CONFIG_TEMP" "$url" || {
            _logging_sub "❌ 订阅更新失败：[$id] $url"
            _error_quit "订阅转换失败：$url"
            return 1
        }
        _validate_downloaded_config "$CLASH_CONFIG_TEMP" || {
            _logging_sub "❌ 订阅更新失败：[$id] $url"
            _error_quit "订阅转换结果无效：$CLASH_CONFIG_TEMP"
            return 1
        }
    }
    [ "$is_convert" != true ] && {
        _download_config "$CLASH_CONFIG_TEMP" "$url" || {
            _logging_sub "❌ 订阅更新失败：[$id] $url"
            _error_quit "订阅下载失败：$url"
            return 1
        }
    }
    _valid_config "$CLASH_CONFIG_TEMP" || {
        _logging_sub "❌ 订阅更新失败：[$id] $url"
        _error_quit "订阅无效：请检查：
    原始订阅：${CLASH_CONFIG_TEMP}.raw
    转换订阅：$CLASH_CONFIG_TEMP
    转换日志：$BIN_SUBCONVERTER_LOG"
        return 1
    }
    local profile_backup="${profile_path}.update.bak.$$" had_profile=false
    [ -f "$profile_path" ] && {
        cat "$profile_path" >"$profile_backup" || return 1
        had_profile=true
    }
    cat "$CLASH_CONFIG_TEMP" >"$profile_path" || return 1
    use=$("$BIN_YQ" '.use // ""' "$CLASH_PROFILES_META")
    [ "$use" = "$id" ] && {
        clashsub use "$use" && {
            /usr/bin/rm -f "$profile_backup"
            _logging_sub "✅ 订阅更新成功：[$id] $url"
            return 0
        }
        if [ "$had_profile" = true ]; then
            /bin/mv -f "$profile_backup" "$profile_path"
        else
            /usr/bin/rm -f "$profile_path" "$profile_backup"
        fi
        return 1
    }
    /usr/bin/rm -f "$profile_backup"
    _logging_sub "✅ 订阅更新成功：[$id] $url"
    _okcat '订阅已更新'
}
_logging_sub() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") $1" >>"${CLASH_PROFILES_LOG}"
}
_sub_log() {
    tail <"${CLASH_PROFILES_LOG}" "$@"
}
