#!/bin/bash

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh

# args: device, mountpoint, flags, opts
miso_mnt_dev() {
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

miso_mnt_sfs() {
    local img="${1}"
    local mnt="${2}"
    local img_fullname="${img##*/}"
    local sfs_dev

    if [[ "${copytoram}" == "y" ]]; then
        echo ":: Copying $img_fullname squashfs image to RAM..."
        if ! cp "${img}" "/run/miso/copytoram/${img_fullname}" ; then
            die "Failed to copy '${img}' to '/run/miso/copytoram/${img_fullname}'"
            return 1
        fi
        img="/run/miso/copytoram/${img_fullname}"
    fi

    sfs_dev=$(losetup --find --show --read-only "${img}")
    miso_mnt_dev "${sfs_dev}" "${mnt}" "-r" "defaults"
}

# args: source, newroot, mountpoint
miso_mnt_overlayfs() {
    local src="${1}"
    local newroot="${2}"
    local mnt="${3}"
    local work_dir="/run/miso/overlay_root/work"
    local upper_dir="/run/miso/overlay_root/upper"

    mkdir -p "${upper_dir}" "${work_dir}"

    mount -t overlay overlay -o lowerdir="${src}",upperdir="${upper_dir}",workdir="${work_dir}" "${newroot}${mnt}"
}

miso_verify_checksum() {
    local _status
    pushd "/run/miso/bootmnt/${misobasedir}/${arch}" >/dev/null
    md5sum -c $1.md5 > /tmp/checksum.log 2>&1
    _status=$?
    popd >/dev/null
    return ${_status}
}

miso_mount_root() {
    local misobasedir=$(getarg misobasedir=)
    local overlay_root_size=$(getarg overlay_root_size=)
    local arch="$(uname -m)"
    local copytoram="$(getarg copytoram=)"
    local copytoram_size=$(getarg overlay_root_size=)
    local checksum="$(getarg checksum=)"

    [[ -z "${misobasedir}" ]] && misobasedir="garuda"
    [[ -z "${overlay_root_size}" ]] && overlay_root_size="75%"
    [[ -z "${copytoram_size}" ]] && copytoram_size="75%"

    if ! mountpoint -q "/run/miso/bootmnt"; then
        miso_mnt_dev "${root#miso:}" "/run/miso/bootmnt" "-r" "defaults"
    fi

    if [[ "${checksum}" == "y" ]]; then
        echo ":: Self-test requested, please wait..."
        for fs in rootfs desktopfs ghtfs livefs; do
            echo "Testing ${fs}..."
            if [[ -f "/run/miso/bootmnt/${misobasedir}/${arch}/${fs}.sfs" ]]; then
                if [[ -f "/run/miso/bootmnt/${misobasedir}/${arch}/${fs}.md5" ]]; then
                    if ! miso_verify_checksum "${fs}"; then
                        die "one or more files are corrupted. See /tmp/checksum.log for details"
                        return 1
                    fi
                else
                    die "checksum=y option specified but ${misobasedir}/${arch}/${fs}.md5 not found"
                    return 1
                fi
            fi
        done
        echo ":: Checksum is OK, continuing boot process"
    fi

    if [[ "${copytoram}" == "y" ]]; then
        echo ":: Mounting /run/miso/copytoram (tmpfs) filesystem, size=${copytoram_size}"
        mkdir -p /run/miso/copytoram
        mount -t tmpfs -o "size=${copytoram_size}",mode=0755 copytoram /run/miso/copytoram
    fi

    mkdir -p /run/miso/overlay_root
    mount -t tmpfs -o "size=${overlay_root_size}",mode=0755 overlay_root /run/miso/overlay_root

    local src="/run/miso/bootmnt/${misobasedir}/${arch}"
    local dest_sfs="/run/miso/sfs" dest_img="/run/miso/img"
    local lower_dir

    for sfs in livefs ghtfs desktopfs rootfs; do
        if [[ -f "${src}/${sfs}.sfs" ]]; then
            miso_mnt_sfs "${src}/${sfs}.sfs" "${dest_sfs}/${sfs}"
            lower_dir=${lower_dir:-}${lower_dir:+:}"${dest_sfs}/${sfs}"
        fi
    done

    mkdir -p /run/miso/root
    miso_mnt_overlayfs "${lower_dir}" "/run/miso/root" "/"

    if [[ "${copytoram}" == "y" ]]; then
        umount -d /run/miso/bootmnt
        mkdir -p /run/miso/bootmnt/${misobasedir}/${arch}
        mount -o bind /run/miso/copytoram /run/miso/bootmnt/${misobasedir}/${arch}
    fi
}
if [ -n "$root" -a -z "${root%%miso:*}" ]; then
    miso_mount_root
fi
