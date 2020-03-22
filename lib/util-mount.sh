#!/bin/bash
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

ignore_error() {
    "$@" 2>/dev/null
    return 0
}

parse_fstab(){
    echo $(perl -ane 'printf("%s:%s\n", @F[0,1]) if $F[0] =~ m#^UUID=#;' $1/etc/fstab)
# 	perl -ane 'printf("%s:%s\n", @F[0,1]) if $F[0] =~ m#^/dev#;' $1/etc/fstab
# 	perl -ane 'printf("%s:%s\n", @F[0,1]) if $F[0] =~ m#^LABEL=#;' $1/etc/fstab
}

detect(){
    local detected="$(os-prober | tr ' ' '_' | paste -s -d ' ')"
    echo ${detected}
}

# $1: os-prober array
get_os_name(){
    local str=$1
    str="${str#*:}"
    str="${str#*:}"
    str="${str%:*}"
    echo "$str"
}

get_chroot_arch(){
    local elf=$(file $1/usr/bin/file)
    elf=${elf//*executable,}
    echo ${elf%%,*}
}

chroot_part_mount() {
    info "mount: [%s]" "$2"
    mount "$@" && CHROOT_ACTIVE_PART_MOUNTS=("$2" "${CHROOT_ACTIVE_PART_MOUNTS[@]}")
}

select_os(){
        local os_list=( $(detect) ) count=${#os_list[@]}
    if [[ ${count} > 1 ]]; then
                msg "Detected systems:"
                local i=0
                for os in ${os_list[@]}; do
            local last=${os##*:}
            case $last in
                'efi') count=$((count-1)) ;;
                *) info "$i) $(get_os_name $os)"; i=$((i+1)) ;;
            esac
                done
                i=0
        msg "Select system to mount [0-%s] : " "$((count-1))"
                read select
        else
        select=0
    fi
    local os_str=${os_list[$select]} type
    type=$os_str
    root=${os_str%%:*}
    type=${type##*:}
        if [[ "${type##*:}" == 'linux' ]]; then
        msg "Mounting (%s) [%s]" "$(get_os_name $os_str)" "$root"
        chroot_mount_partitions "$1" "$root"
        else
                die "You can't mount %s!" "$select"
        fi
}

chroot_mount_partitions(){

    CHROOT_ACTIVE_PART_MOUNTS=()
    CHROOT_ACTIVE_MOUNTS=()

    [[ $(trap -p EXIT) ]] && die 'Error! Attempting to overwrite existing EXIT trap'
    trap 'trap_handler' EXIT

    chroot_part_mount $2 $1

    local mounts=$(parse_fstab "$1")

    for entry in ${mounts[@]}; do
        entry=${entry//UUID=}
        local dev=${entry%:*} mp=${entry#*:}
        case "${entry#*:}" in
            '/'|'swap'|'none') continue ;;
            *) chroot_part_mount "/dev/disk/by-uuid/${dev}" "$1${mp}" ;;
        esac
    done

    local chroot_arch=$(get_chroot_arch $1)
    [[ ${chroot_arch} == x86-64 ]] && chroot_arch=${chroot_arch/-/_}
    case ${target_arch} in
        i686)
            if [[ ${chroot_arch} == x86_64 ]]; then
                die "You can't chroot from %s host into %s!" "${target_arch}" "${chroot_arch}"
            fi
        ;;
    esac

    chroot_mount_conditional "! mountpoint -q '$1'" "$1" "$1" --bind &&
    chroot_mount proc "$1/proc" -t proc -o nosuid,noexec,nodev &&
    chroot_mount sys "$1/sys" -t sysfs -o nosuid,noexec,nodev,ro &&
    ignore_error chroot_mount_conditional "[[ -d '$1/sys/firmware/efi/efivars' ]]" \
        efivarfs "$1/sys/firmware/efi/efivars" -t efivarfs -o nosuid,noexec,nodev &&
    chroot_mount udev "$1/dev" -t devtmpfs -o mode=0755,nosuid &&
    chroot_mount devpts "$1/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec &&
    chroot_mount shm "$1/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev &&
    chroot_mount run "$1/run" -t tmpfs -o nosuid,nodev,mode=0755 &&
    chroot_mount tmp "$1/tmp" -t tmpfs -o mode=1777,strictatime,nodev,nosuid
    chroot_mount /etc/resolv.conf "$1/etc/resolv.conf" --bind
}

chroot_mount() {
    #info "mount: [%s]" "$2"
    mount "$@" && CHROOT_ACTIVE_MOUNTS=("$2" "${CHROOT_ACTIVE_MOUNTS[@]}")
}

chroot_mount_conditional() {
    local cond=$1; shift
    if eval "$cond"; then
        chroot_mount "$@"
    fi
}

chroot_api_efi_mount() {
    CHROOT_ACTIVE_MOUNTS=()
    [[ $(trap -p EXIT) ]] && die 'Error! Attempting to overwrite existing EXIT trap'
    trap 'chroot_api_efi_umount' EXIT

    chroot_mount_conditional "! mountpoint -q '$1'" "$1" "$1" --bind &&
    chroot_mount proc "$1/proc" -t proc -o nosuid,noexec,nodev &&
    chroot_mount sys "$1/sys" -t sysfs -o nosuid,noexec,nodev,ro &&
    ignore_error chroot_mount_conditional "[[ -d '$1/sys/firmware/efi/efivars' ]]" \
        efivarfs "$1/sys/firmware/efi/efivars" -t efivarfs -o nosuid,noexec,nodev &&
    chroot_mount udev "$1/dev" -t devtmpfs -o mode=0755,nosuid &&
    chroot_mount devpts "$1/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec &&
    chroot_mount shm "$1/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev &&
    chroot_mount run "$1/run" -t tmpfs -o nosuid,nodev,mode=0755 &&
    chroot_mount tmp "$1/tmp" -t tmpfs -o mode=1777,strictatime,nodev,nosuid
}

chroot_api_mount() {
    CHROOT_ACTIVE_MOUNTS=()
    [[ $(trap -p EXIT) ]] && die 'Error! Attempting to overwrite existing EXIT trap'
    trap 'chroot_api_umount' EXIT

    chroot_mount_conditional "! mountpoint -q '$1'" "$1" "$1" --bind &&
    chroot_mount proc "$1/proc" -t proc -o nosuid,noexec,nodev &&
    chroot_mount sys "$1/sys" -t sysfs -o nosuid,noexec,nodev,ro &&
    chroot_mount udev "$1/dev" -t devtmpfs -o mode=0755,nosuid &&
    chroot_mount devpts "$1/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec &&
    chroot_mount shm "$1/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev &&
    chroot_mount run "$1/run" -t tmpfs -o nosuid,nodev,mode=0755 &&
    chroot_mount tmp "$1/tmp" -t tmpfs -o mode=1777,strictatime,nodev,nosuid
}

chroot_part_umount() {
    info "umount: [%s]" "${CHROOT_ACTIVE_PART_MOUNTS[@]}"
    umount "${CHROOT_ACTIVE_PART_MOUNTS[@]}"
    unset CHROOT_ACTIVE_PART_MOUNTS
}

chroot_api_umount() {
    #info "umount: [%s]" "${CHROOT_ACTIVE_MOUNTS[@]}"
    umount "${CHROOT_ACTIVE_MOUNTS[@]}"
    unset CHROOT_ACTIVE_MOUNTS
}

chroot_api_efi_umount() {
    #info "umount: [%s]" "${CHROOT_ACTIVE_MOUNTS[@]}"
    umount "${CHROOT_ACTIVE_MOUNTS[@]}"
    unset CHROOT_ACTIVE_MOUNTS
}

trap_handler(){
    chroot_api_umount
    chroot_part_umount
}
