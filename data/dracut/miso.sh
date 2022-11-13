#!/bin/bash

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh

# args: device, mountpoint, flags, opts
_mnt_dev() {
    local dev="${1}"
    local mnt="${2}"
    local flg="${3}"
    local opts="${4}"

    mkdir -p "${mnt}"

    echo ":: Mounting '${dev}' to '${mnt}'"

    if mount -o "${opts}" "${flg}" "${dev}" "${mnt}"; then
        echo ":: Device '${dev}' mounted successfully."
    else
        die "Failed to mount '${dev}'"
    fi
}

_mnt_sfs() {
    local img="${1}"
    local mnt="${2}"
    local img_fullname="${img##*/}"
    local sfs_dev

    sfs_dev=$(losetup --find --show --read-only "${img}")
    _mnt_dev "${sfs_dev}" "${mnt}" "-r" "defaults"
}

# args: source, newroot, mountpoint
_mnt_overlayfs() {
    local src="${1}"
    local newroot="${2}"
    local mnt="${3}"
    local work_dir="/run/miso/overlay_root/work"
    local upper_dir="/run/miso/overlay_root/upper"

    mkdir -p "${upper_dir}" "${work_dir}"

    mount -t overlay overlay -o lowerdir="${src}",upperdir="${upper_dir}",workdir="${work_dir}" "${newroot}${mnt}"
}

misobasedir=$(getarg misobasedir=)
misodevice=$(getarg misodevice=)
overlay_root_size=$(getarg overlay_root_size=)

[[ -z "${misobasedir}" ]] && misobasedir="garuda"
[[ -z "${overlay_root_size}" ]] && overlay_root_size="75%"
[[ -z "${arch}" ]] && arch="$(uname -m)"

mount_miso_root() {
    if ! mountpoint -q "/run/miso/bootmnt"; then
        _mnt_dev "${misodevice}" "/run/miso/bootmnt" "-r" "defaults"
    fi

    mkdir -p /run/miso/overlay_root
    mount -t tmpfs -o "size=${overlay_root_size}",mode=0755 overlay_root /run/miso/overlay_root

    local src="/run/miso/bootmnt/${misobasedir}/${arch}"
    local dest_sfs="/run/miso/sfs" dest_img="/run/miso/img"
    local lower_dir

    for sfs in livefs mhwdfs desktopfs rootfs; do
        if [[ -f "${src}/${sfs}.sfs" ]]; then
            _mnt_sfs "${src}/${sfs}.sfs" "${dest_sfs}/${sfs}"
            lower_dir=${lower_dir:-}${lower_dir:+:}"${dest_sfs}/${sfs}"
        fi
    done

    _mnt_overlayfs "${lower_dir}" "${NEWROOT}" "/"
}

mount_miso_root