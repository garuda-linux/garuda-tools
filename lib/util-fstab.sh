#!/bin/bash
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

declare -A pseudofs_types=([anon_inodefs]=1
                        [autofs]=1
                        [bdev]=1
                        [binfmt_misc]=1
                        [cgroup]=1
                        [configfs]=1
                        [cpuset]=1
                        [debugfs]=1
                        [devfs]=1
                        [devpts]=1
                        [devtmpfs]=1
                        [dlmfs]=1
                        [fuse.gvfs-fuse-daemon]=1
                        [fusectl]=1
                        [hugetlbfs]=1
                        [mqueue]=1
                        [nfsd]=1
                        [none]=1
                        [pipefs]=1
                        [proc]=1
                        [pstore]=1
                        [ramfs]=1
                        [rootfs]=1
                        [rpc_pipefs]=1
                        [securityfs]=1
                        [sockfs]=1
                        [spufs]=1
                        [sysfs]=1
                        [tmpfs]=1)

declare -A fsck_types=([cramfs]=1
                    [exfat]=1
                    [ext2]=1
                    [ext3]=1
                    [ext4]=1
                    [ext4dev]=1
                    [jfs]=1
                    [minix]=1
                    [msdos]=1
                    [reiserfs]=1
                    [vfat]=1
                    [xfs]=1)

fstype_is_pseudofs() {
    (( pseudofs_types["$1"] ))
}

fstype_has_fsck() {
    (( fsck_types["$1"] ))
}

valid_number_of_base() {
    local base=$1 len=${#2} i=

    for (( i = 0; i < len; i++ )); do
        { _=$(( $base#${2:i:1} )) || return 1; } 2>/dev/null
    done

    return 0
}

mangle() {
    local i= chr= out=

    unset {a..f} {A..F}

    for (( i = 0; i < ${#1}; i++ )); do
        chr=${1:i:1}
        case $chr in
            [[:space:]\\])
                printf -v chr '%03o' "'$chr"
                out+=\\
            ;;
        esac
        out+=$chr
    done

    printf '%s' "$out"
}

unmangle() {
    local i= chr= out= len=$(( ${#1} - 4 ))

    unset {a..f} {A..F}

    for (( i = 0; i < len; i++ )); do
        chr=${1:i:1}
        case $chr in
            \\)
                if valid_number_of_base 8 "${1:i+1:3}" ||
                    valid_number_of_base 16 "${1:i+1:3}"; then
                    printf -v chr '%b' "${1:i:4}"
                    (( i += 3 ))
                fi
            ;;
        esac
        out+=$chr
    done

    printf '%s' "$out${1:i}"
}

dm_name_for_devnode() {
    read dm_name <"/sys/class/block/${1#/dev/}/dm/name"
    if [[ $dm_name ]]; then
        printf '/dev/mapper/%s' "$dm_name"
    else
        # don't leave the caller hanging, just print the original name
        # along with the failure.
        print '%s' "$1"
        error 'Failed to resolve device mapper name for: %s' "$1"
    fi
}

optstring_match_option() {
    local candidate pat patterns

    IFS=, read -ra patterns <<<"$1"
    for pat in "${patterns[@]}"; do
        if [[ $pat = *=* ]]; then
            # "key=val" will only ever match "key=val"
            candidate=$2
        else
            # "key" will match "key", but also "key=anyval"
            candidate=${2%%=*}
        fi

        [[ $pat = "$candidate" ]] && return 0
    done

    return 1
}

optstring_remove_option() {
    local o options_ remove=$2 IFS=,

    read -ra options_ <<<"${!1}"

    for o in "${!options_[@]}"; do
        optstring_match_option "$remove" "${options_[o]}" && unset 'options_[o]'
    done

    declare -g "$1=${options_[*]}"
}

optstring_normalize() {
    local o options_ norm IFS=,

    read -ra options_ <<<"${!1}"

    # remove empty fields
    for o in "${options_[@]}"; do
        [[ $o ]] && norm+=("$o")
    done

    # avoid empty strings, reset to "defaults"
    declare -g "$1=${norm[*]:-defaults}"
}

optstring_append_option() {
    if ! optstring_has_option "$1" "$2"; then
        declare -g "$1=${!1},$2"
    fi

    optstring_normalize "$1"
}

optstring_prepend_option() {
    local options_=$1

    if ! optstring_has_option "$1" "$2"; then
        declare -g "$1=$2,${!1}"
    fi

    optstring_normalize "$1"
}

optstring_get_option() {
    local opts o

    IFS=, read -ra opts <<<"${!1}"
    for o in "${opts[@]}"; do
        if optstring_match_option "$2" "$o"; then
            declare -g "$o"
            return 0
        fi
    done

    return 1
}

optstring_has_option() {
    local "${2%%=*}"

    optstring_get_option "$1" "$2"
}
