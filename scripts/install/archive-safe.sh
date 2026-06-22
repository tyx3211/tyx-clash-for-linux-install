#!/usr/bin/env bash

_archive_member_path_is_safe() {
    local member=${1#./}

    case "$member" in
    "" | "/" | /* | "." | ".." | ../* | */../* | */.. | */./* | */.)
        return 1
        ;;
    esac
    return 0
}

_tar_archive_is_safe() {
    local archive=$1 mode member

    tar -tf "$archive" >/dev/null 2>&1 || return 1
    while IFS= read -r member; do
        _archive_member_path_is_safe "$member" || return 1
    done < <(tar -tf "$archive" 2>/dev/null)

    while IFS= read -r mode _; do
        case "$mode" in
        -* | d*)
            ;;
        *)
            return 1
            ;;
        esac
    done < <(tar -tvf "$archive" 2>/dev/null)
    return 0
}

_zip_archive_is_safe() {
    local archive=$1 member members listing

    members=$(unzip -Z -1 "$archive" 2>/dev/null) || return 1
    [ -n "$members" ] || return 1
    while IFS= read -r member; do
        _archive_member_path_is_safe "$member" || return 1
    done <<<"$members"

    listing=$(unzip -Z -l "$archive" 2>/dev/null) || return 1
    [ -n "$listing" ] || return 1
    awk '
            BEGIN { seen = 0; bad = 0 }
            length($1) == 10 && $2 ~ /^[0-9]+(\.[0-9]+)?$/ {
                seen = 1
                kind = substr($1, 1, 1)
                if (kind != "-" && kind != "d") {
                    bad = 1
                }
                if ($1 !~ /^[-d][rwxStTs-]{9}$/) {
                    bad = 1
                }
                next
            }
            /^Archive:/ || /^Zip file size:/ || /^[[:space:]]*[0-9]+ files?,/ || NF == 0 {
                next
            }
            {
                bad = 1
            }
            END { exit (seen && !bad) ? 0 : 1 }
        ' <<<"$listing"
}

_extract_tar_archive() {
    local archive=$1 dest=$2

    _tar_archive_is_safe "$archive" ||
        _error_quit "归档包含不安全路径或特殊文件，请删除后重试：$archive"
    tar -xf "$archive" -C "$dest"
}

_extract_zip_archive() {
    local archive=$1 dest=$2

    _zip_archive_is_safe "$archive" || return 1
    unzip -oqq "$archive" -d "$dest"
}
