#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

import ${LIBDIR}/util-iso-image.sh
import ${LIBDIR}/util-iso-boot.sh
import ${LIBDIR}/util-yaml.sh

error_function() {
    if [[ -p $logpipe ]]; then
        rm "$logpipe"
    fi
    # first exit all subshells, then print the error
    if (( ! BASH_SUBSHELL )); then
        error "A failure occurred in %s()." "$1"
        plain "Aborting..."
    fi
    umount_fs
    umount_img
    exit 2
}

# $1: function
run_log(){
    local func="$1"
    local tmpfile=${tmp_dir}/$func.ansi.log logfile=${log_dir}/$(gen_iso_fn).$func.log
    logpipe=$(mktemp -u "${tmp_dir}/$func.pipe.XXXXXXXX")
    mkfifo "$logpipe"
    tee "$tmpfile" < "$logpipe" &
    local teepid=$!
    $func &> "$logpipe"
    wait $teepid
    rm "$logpipe"
    cat $tmpfile | perl -pe 's/\e\[?.*?[\@-~]//g' > $logfile
    rm "$tmpfile"
}

run_safe() {
    local restoretrap func="$1"
    set -e
    set -E
    restoretrap=$(trap -p ERR)
    trap 'error_function $func' ERR

    if ${verbose}; then
        run_log "$func"
    else
        "$func"
    fi

    eval $restoretrap
    set +E
    set +e
}

trap_exit() {
    local sig=$1; shift
    error "$@"
    umount_fs
    trap -- "$sig"
    kill "-$sig" "$$"
}

make_sig () {
    msg2 "Creating signature file..."
    cd "$1"
    user_own "$1"
    su ${OWNER} -c "gpg --detach-sign --default-key ${gpgkey} $2.sfs"
    chown -R root "$1"
    cd ${OLDPWD}
}

# $1: file
make_checksum(){
    msg2 "Creating md5sum ..."
    cd $1
    md5sum $2.sfs > $2.md5
    cd ${OLDPWD}
}

# $1: image path
make_sfs() {
    local src="$1"
    if [[ ! -e "${src}" ]]; then
        error "The path %s does not exist" "${src}"
        retrun 1
    fi
    local timer=$(get_timer) dest=${iso_root}/${iso_name}/${target_arch}
    local name=${1##*/}
    local sfs="${dest}/${name}.sfs"
    mkdir -p ${dest}
    msg "Generating SquashFS image for %s" "${src}"
    if [[ -f "${sfs}" ]]; then
        local has_changed_dir=$(find ${src} -newer ${sfs})
        msg2 "Possible changes for %s ..." "${src}"  >> ${tmp_dir}/buildiso.debug
        msg2 "%s" "${has_changed_dir}" >> ${tmp_dir}/buildiso.debug
        if [[ -n "${has_changed_dir}" ]]; then
            msg2 "SquashFS image %s is not up to date, rebuilding..." "${sfs}"
            rm "${sfs}"
        else
            msg2 "SquashFS image %s is up to date, skipping." "${sfs}"
            return
        fi
    fi

    if ${persist}; then
        local size=32G
        local mnt="${mnt_dir}/${name}"
        msg2 "Creating ext4 image of %s ..." "${size}"
        truncate -s ${size} "${src}.img"
        local ext4_args=()
        ${verbose} && ext4_args+=(-q)
        ext4_args+=(-O ^has_journal,^resize_inode -E lazy_itable_init=0 -m 0)
        mkfs.ext4 ${ext4_args[@]} -F "${src}.img" &>/dev/null
        tune2fs -c 0 -i 0 "${src}.img" &> /dev/null
        mount_img "${work_dir}/${name}.img" "${mnt}"
        msg2 "Copying %s ..." "${src}/"
        cp -aT "${src}/" "${mnt}/"
        umount_img "${mnt}"

    fi

    msg2 "Creating SquashFS image, this may take some time..."
    local used_kernel=${kernel:5:1} mksfs_args=()
    if ${persist}; then
        mksfs_args+=(${work_dir}/${name}.img)
    else
        mksfs_args+=(${src})
    fi

    mksfs_args+=(${sfs} -noappend)

    local highcomp

    [[ "${iso_compression}" == "xz" ]] && highcomp="-b 1M -Xdict-size 1M -Xbcj x86"
    
    [[ "${iso_compression}" == "zstd" ]] && highcomp="-b 1M -Xcompression-level 22" #compression level max 22 (default 15)

    mksfs_args+=(-comp ${iso_compression} ${highcomp})

    if ${verbose}; then
        mksquashfs "${mksfs_args[@]}" 
    else
        mksquashfs "${mksfs_args[@]}" >/dev/null
    fi
    make_checksum "${dest}" "${name}"
    ${persist} && rm "${src}.img"

    if [[ -n ${gpgkey} ]]; then
        make_sig "${dest}" "${name}"
    fi

    show_elapsed_time "${FUNCNAME}" "${timer_start}"
}

assemble_iso(){
    msg "Creating ISO image..."
    local iso_publisher="$(get_osname) <$(get_disturl)>" \
        iso_app_id="$(get_osname) Live/Rescue CD" \
        mod_date=$(date -u +%Y-%m-%d-%H-%M-%S-00  | sed -e s/-//g)

    xorriso -as mkisofs \
        --modification-date=${mod_date} \
        --protective-msdos-label \
        -volid "${iso_label}" \
        -appid "${iso_app_id}" \
        -publisher "${iso_publisher}" \
        -preparer "Prepared by garuda-tools/${0##*/}" \
        -r -graft-points -no-pad \
        --sort-weight 0 / \
        --sort-weight 1 /boot \
        --grub2-mbr ${iso_root}/boot/grub/i386-pc/boot_hybrid.img \
        -iso_mbr_part_type 0x00 \
        -partition_offset 16 \
        -b boot/grub/i386-pc/eltorito.img \
        -c boot.catalog \
        -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
        -eltorito-alt-boot \
        -append_partition 2 0xef ${iso_root}/efi.img \
        -e --interval:appended_partition_2:all:: \
        -no-emul-boot \
        -full-iso9660-filenames \
        -iso-level 3 -rock -joliet \
        -o ${iso_dir}/${iso_file} \
        ${iso_root}/
}

# Build ISO
make_iso() {
    msg "Start [Build ISO]"
    touch "${iso_root}/.miso"
    for sfs_dir in $(find "${work_dir}" -maxdepth 1 -type d); do
        if [[ "${sfs_dir}" != "${work_dir}" ]]; then
            if [[ -e "${sfs_dir}"/etc/pacman.d/gnupg ]]; then
                msg2 "Removing '/etc/pacman.d/gnupg' folder from ${sfs_dir}"
                rm -rf "${sfs_dir}"/etc/pacman.d/gnupg
            fi
            make_sfs "${sfs_dir}"
        fi
    done

    msg "Making bootable image"
    # Sanity checks
    [[ ! -d "${iso_root}" ]] && return 1
    if [[ -f "${iso_dir}/${iso_file}" ]]; then
        msg2 "Removing ${iso_file} related files ..."
        [[ -f "${iso_dir}/${iso_file}" ]] && rm -f "${iso_dir}/${iso_file}"
        [[ -f "${iso_dir}/${iso_file}.sig" ]] && rm -f "${iso_dir}/${iso_file}.sig"
        [[ -f "${iso_dir}/${iso_file}.sha1" ]] && rm -f "${iso_dir}/${iso_file}.sha1"
        [[ -f "${iso_dir}/${iso_file}.sha256" ]] && rm -f "${iso_dir}/${iso_file}.sha256"
        [[ -f "${iso_dir}/${iso_file}.torrent" ]] && rm -f "${iso_dir}/${iso_file}.torrent"
        [[ -f "${iso_dir}/${iso_file}.zsync" ]] && rm -f "${iso_dir}/${iso_file}.zsync"
    fi
    assemble_iso

    ${permalink} && gen_permalink
    ${torrent} && make_torrent
    ${zsync} && make_zsync
    ${checksum} && checksumiso "${iso_dir}"

    if [ -e "/var/cache/garuda-tools/garuda-builds/.env" ]; then
        source /var/cache/garuda-tools/garuda-builds/.env
    fi
    if [ ! -z "$TELEGRAM" ]; then
        echo "${iso_file} built successfully!" | apprise -vv "${TELEGRAM}" -t "New ISO build available!"
    fi

    msg "Done [Build ISO]"
}

make_torrent(){
    find ${iso_dir} -type f -name "*.torrent" -delete
    if [[ -f "${iso_dir}/${iso_file}" ]]; then
        mirror_path="${edition}/${profile}/${dist_timestamp}/${iso_file}"
        local seed="https://downloads.sourceforge.net/project/garuda-linux/${mirror_path}"
        local tracker_url1=udp://tracker.opentrackr.org:1337/announce
        local tracker_url2=udp://tracker.openbittorrent.com:80/announce
        local tracker_url3=http://fosstorrents.com:6969/announce
        local tracker_url4=udp://tracker.leechers-paradise.org:6969/announce
        mktorrent_args=(-c "${torrent_meta}" -l ${piece_size} -a ${tracker_url1} -a ${tracker_url2} -a ${tracker_url3} -a ${tracker_url4} -w ${seed}) 
        ${verbose} && mktorrent_args+=(-v)
        msg2 "Creating (%s) ..." "${iso##*/}.torrent"
        mktorrent ${mktorrent_args[*]} -o "${iso_dir}/${iso_file}.torrent" "${iso_dir}/${iso_file}"
    fi
}

make_zsync(){
    find ${iso_dir} -type f -name "*.zsync" -delete

    if [[ -n $(find ${iso_dir} -type f -name "*.iso") ]]; then
        isos=$(ls ${iso_dir}/*.iso)
        for iso in ${isos}; do
            msg2 "Creating (%s) ..." "${iso##*/}.zsync"
            zsyncmake ${iso} -u "${iso##*/}" -o ${iso}.zsync
        done
    fi
}

gen_permalink(){
    if [[ ${edition} == "community" ]] || [[ ${edition} == "garuda" ]]; then
        if [[ -f "${iso_dir}/${iso_file}" ]]; then
            msg2 "Creating download link ..."
            direct_url="https://sourceforge.net/projects/garuda-linux/files/${iso_file}"
            [[ ${edition} == "community" ]] && direct_url="https://sourceforge.net/projects/garuda-linux/files/${iso_file}"
            ## html permalink
            html_doc="<!DOCTYPE HTML>"
            html_doc+="<meta charset=\"UTF-8\">"
            html_doc+="<meta http-equiv=\"refresh\" content=\"1; url=${direct_url}\">"
            html_doc+="<script>window.location.href=\"${direct_url}\"</script>"
            html_doc+="<title>Download Redirection</title>"
            html_doc+="If you are not redirected automatically, follow the <a href=\"${direct_url}\">link to latest iso</a>"
            ## php permalink
            php_doc="<?php "
            php_doc+="header('Location: ' . '${direct_url}', true, 303); "
            php_doc+="die(); "
            php_doc+="?>"
            ## write files
            if [[ ${extra} == "true" ]]; then
                echo ${html_doc} > "${iso_dir}/.latest"
                echo ${php_doc} > "${iso_dir}/.latest.php"
            else
                echo ${html_doc} > "${iso_dir}/.latest-minimal"
                echo ${php_doc} > "${iso_dir}/.latest-minimal.php"
            fi
        fi
    fi
}

gen_iso_fn(){
    local vars=() name
    vars+=("${iso_name}")
    if ! ${chrootcfg}; then
        [[ -n ${profile} ]] && vars+=("${profile}")
    fi

    [[ ! ${target_branch} == "archlinux" ]] && vars+=("${target_branch}")
    
   ## [[ ${extra} == 'true' ]] && vars+=("ultimate")

    vars+=("${kernel}")
    
    vars+=("${dist_timestamp}")

    [[ ${target_arch} == "i686" ]] && vars+=("${target_arch}")
    for n in ${vars[@]}; do
        name=${name:-}${name:+-}${n}
    done

    echo $name
}

reset_pac_conf(){
    info "Restoring [%s/etc/pacman.conf] ..." "$1"
    sed -e "s|^.*#CheckSpace|CheckSpace|" \
        -i "$1/etc/pacman.conf"
}

# Snap support
function seed_snaps() {
    local SEED_DIR="/var/lib/snapd/seed"
    local SEED_CHANNEL="${snap_channel}"
    local SEED_SNAPS="${strict_snaps} ${classic_snaps}"

    if [[ -n "${strict_snaps}" ]] || [[ -n "${classic_snaps}" ]]; then
        msg2 "Configuring snaps"
        # Preseeded snaps should be downloaded from a versioned channel
        rm -rfv "$1/${SEED_DIR}"
        mkdir -p "$1/${SEED_DIR}/snaps"
        mkdir -p "$1/${SEED_DIR}/assertions"
        SEED_LIST=()

        # Update SEED_LIST
        for SEED_SNAP in ${SEED_SNAPS}; do
            if [[ "${SEED_SNAP}" == "core" ]] || [[ "${SEED_SNAP}" == "core16" ]] || [[ "${SEED_SNAP}" == "core18" ]]; then
                SEED_LIST+=(--snap=${SEED_SNAP}=stable)
            else
                SEED_LIST+=(--snap=${SEED_SNAP}=${SEED_CHANNEL})
            fi
        done

        # Create model and account assertions
        # Runs outside the container.
        snap known model > /tmp/generic.model
        snap prepare-image --arch amd64 --classic /tmp/generic.model "${SEED_LIST[@]}" "$1"
    else
        msg2 "No snaps found in profile. Skipping adding snaps"
    fi
}

# Base installation (rootfs)
make_image_root() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [Base installation] (rootfs)"
        local path="${work_dir}/rootfs"
        mkdir -p ${path}

        chroot_create "${path}" "${packages}" || die

        echo -e "TIMESTAMP=${dist_timestamp}\nCODENAME=${dist_codename}" >> "${path}/usr/lib/garuda/garuda-release"

        # /build/grub needs to exist if grub is in use, otherwise grub-mkconfig will fail on calamares in BIOS mode
        if [[ "${efi_boot_loader}" == "grub" ]]; then
            mkdir -p "${path}/boot/grub"
        fi

        copy_overlay "${profile_dir}/root-overlay" "${path}"

        reset_pac_conf "${path}"

        clean_up_image "${path}"
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [Base installation] (rootfs)"
    fi
}

make_image_desktop() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [Desktop installation] (desktopfs)"
        local path="${work_dir}/desktopfs"
        mkdir -p ${path}

        mount_fs_root "${path}"

        chroot_create "${path}" "${packages}"

        pacman -Qr "${path}" > ${iso_dir}/$(gen_iso_fn).pkgs.txt
        [[ -e ${profile_dir}/desktop-overlay-common ]] && copy_overlay "${profile_dir}/desktop-overlay-common" "${path}"
        [[ -e ${profile_dir}/desktop-overlay ]] && copy_overlay "${profile_dir}/desktop-overlay" "${path}"

        if [[ -e "${path}/usr/share/calamares/branding/garuda/branding.desc" ]]; then
            configure_branding "${path}"
            msg "Done [Distribution: Release ${dist_release} Codename ${dist_codename}]"
        fi
        
        reset_pac_conf "${path}"

        seed_snaps ${path}

        echo "Enable os-prober"
        sed -i -r 's,^(#|)GRUB_DISABLE_OS_PROBER=.*,GRUB_DISABLE_OS_PROBER=false,' "${path}/etc/default/grub"

        umount_fs
        clean_up_image "${path}"
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [Desktop installation] (desktopfs)"
    fi
}

mount_fs_select(){
    if [[ -f "${packages_desktop}" ]]; then
        mount_fs_desktop "$1"
    else
        mount_fs_root "$1"
    fi
}

make_image_live() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [Live installation] (livefs)"
        local path="${work_dir}/livefs"
        mkdir -p ${path}

        mount_fs_select "${path}"

        chroot_create "${path}" "${packages}"

        [[ -e ${profile_dir}/live-overlay-common ]] && copy_overlay "${profile_dir}/live-overlay-common" "${path}"
        [[ -e ${profile_dir}/live-overlay ]] && copy_overlay "${profile_dir}/live-overlay" "${path}"
        configure_live_image "${path}"

        if [[ -e "${path}/usr/share/calamares/branding/garuda/branding.desc" ]]; then
            configure_branding "${path}"
            msg "Done [Distribution: Release ${dist_release} Codename ${dist_codename}]"
        fi

        configure_polkit_user_rules "${path}"

        reset_pac_conf "${path}"

        umount_fs

        clean_up_image "${path}"
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [Live installation] (livefs)"
    fi
}

make_image_mhwd() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [drivers repository] (ghtfs)"
        local path="${work_dir}/ghtfs"
        mkdir -p ${path}${mhwd_repo}

        mount_fs_select "${path}"

        reset_pac_conf "${path}"

        copy_from_cache "${path}" "${packages}"

        if [[ -n "${packages_cleanup}" ]]; then
            for mhwd_clean in ${packages_cleanup}; do
                rm ${path}${mhwd_repo}/${mhwd_clean}
            done
        fi
        cp ${DATADIR}/pacman-ght.conf ${path}/opt/ght
        make_repo "${path}"

        umount_fs
        clean_up_image "${path}"
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [drivers repository] (ghtfs)"
    fi
}

make_image_boot() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [/iso/boot]"
        local boot="${iso_root}/boot"

        mkdir -p ${boot}

        cp ${work_dir}/rootfs/boot/vmlinuz* ${boot}/vmlinuz-${target_arch}

        local path="${work_dir}/bootfs"
        mkdir -p ${path}

        if [[ -f "${packages_desktop}" ]]; then
            mount_fs_live "${path}"
        else
            mount_fs_net "${path}"
        fi

        prepare_boot_extras "${path}" "${boot}"
        prepare_initcpio "${path}"
        prepare_initramfs "${path}"

        cp ${path}/boot/initramfs.img ${boot}/initramfs-${target_arch}.img

        umount_fs

        rm -R ${path}
        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [/iso/boot]"
    fi
}

configure_grub(){
    local boot_args=('quiet' 'systemd.show_status=1' 'checksum=y' ${custom_boot_args} ${apparmor_boot_args})
    if ${use_dracut}; then
        local default_args="misobasedir=${iso_name} root=miso:LABEL=${iso_label}"
    else
        local default_args="misobasedir=${iso_name} misolabel=${iso_label}"
    fi

    sed -e "s|@DIST_NAME@|${dist_name}|g" \
        -e "s|@ARCH@|${target_arch}|g" \
        -e "s|@DEFAULT_ARGS@|${default_args}|g" \
        -e "s|@BOOT_ARGS@|${boot_args[*]}|g" \
        -e "s|@PROFILE@|${profile}|g" \
        -i $1
}

configure_grub_theme(){
    sed -e "s|@ISO_NAME@|${iso_name}|" -i "$1"
}

make_grub(){
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        msg "Prepare [/iso/boot/grub]"

        local path="${work_dir}/livefs"

        prepare_grub "${path}" "${iso_root}"

        configure_grub "${iso_root}/boot/grub/kernels.cfg"
        configure_grub_theme "${iso_root}/boot/grub/variable.cfg"

        : > ${work_dir}/build.${FUNCNAME}
        msg "Done [/iso/boot/grub]"
    fi
}

check_requirements(){
    [[ -f ${run_dir}/repo_info ]] || die "%s is not a valid iso profiles directory!" "${run_dir}"
    if ! $(is_valid_arch_iso ${target_arch}); then
        die "%s is not a valid arch!" "${target_arch}"
    fi
    if ! $(is_valid_branch ${target_branch}); then
        die "%s is not a valid branch!" "${target_branch}"
    fi
    if ! $(is_valid_comp ${iso_compression}); then
        die "%s is not a valid compression algorithm!" "${iso_compression}"
    fi

    local iso_kernel=${kernel:5:1}
#    [[ ${iso_kernel} < "4" ]] && die "ISO kernel must be version>=4.0!"
}

compress_images(){
    local timer=$(get_timer)
    run_safe "make_iso"
    user_own "${cache_dir_iso}" "-R"
    show_elapsed_time "${FUNCNAME}" "${timer}"
}

prepare_images(){
    local timer=$(get_timer)
    load_pkgs "${profile_dir}/Packages-Root"
    run_safe "make_image_root"
    if [[ -f "${packages_desktop}" ]] ; then
        load_pkgs "${packages_desktop}"
        if [[ -f "${packages_desktop_common}" ]] ; then
            load_pkgs "${packages_desktop_common}" true
        fi
        run_safe "make_image_desktop"
    fi
    if [[ -f ${profile_dir}/Packages-Live ]]; then
        load_pkgs "${profile_dir}/Packages-Live"
        run_safe "make_image_live"
    fi
    if [[ -f ${packages_mhwd} ]] ; then
        load_pkgs "${packages_mhwd}"
        run_safe "make_image_mhwd"
    fi
    run_safe "make_image_boot"
    run_safe "make_grub"

    show_elapsed_time "${FUNCNAME}" "${timer}"
}

archive_logs(){
    local name=$(gen_iso_fn) ext=log.tar.xz src=${tmp_dir}/archives.list
    find ${log_dir} -maxdepth 1 -name "$name*.log" -printf "%f\n" > $src
    msg2 "Archiving log files [%s] ..." "$name.$ext"
    tar -cJf ${log_dir}/$name.$ext -C ${log_dir} -T $src
    msg2 "Cleaning log files ..."
    find ${log_dir} -maxdepth 1 -name "$name*.log" -delete
}

make_profile(){
    msg "Start building [%s]" "${profile}"
    if ${clean_first}; then
        chroot_clean "${chroots_iso}/${profile}/${target_arch}"

        local unused_arch=''
        case ${target_arch} in
            i686) unused_arch='x86_64' ;;
            x86_64) unused_arch='i686' ;;
        esac
        if [[ -d "${chroots_iso}/${profile}/${unused_arch}" ]]; then
            chroot_clean "${chroots_iso}/${profile}/${unused_arch}"
        fi
        clean_iso_root "${iso_root}"
    fi

    if ${iso_only}; then
        [[ ! -d ${work_dir} ]] && die "Create images: buildiso -p %s -x" "${profile}"
        compress_images
        ${verbose} && archive_logs
        exit 1
    fi
    if ${images_only}; then
        prepare_images
        ${verbose} && archive_logs
        warning "Continue compress: buildiso -p %s -zc ..." "${profile}"
        exit 1
    else
        prepare_images
        compress_images
        ${verbose} && archive_logs
    fi
    reset_profile
    msg "Finished building [%s]" "${profile}"
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
}

get_pacman_conf(){
    local user_conf=${profile_dir}/user-repos.conf pac_arch='default' conf
    [[ "${target_arch}" == 'x86_64' ]] && pac_arch='multilib'
    if [[ -f ${user_conf} ]]; then
        info "detected: %s" "user-repos.conf"
        check_user_repos_conf "${user_conf}"
        conf=${tmp_dir}/custom-pacman.conf
        cat ${DATADIR}/pacman-$pac_arch.conf ${user_conf} > "$conf"
    else
        conf="${DATADIR}/pacman-$pac_arch.conf"
    fi
    echo "$conf"
}

load_profile(){
    conf="$1/profile.conf"

    info "Profile: [%s]" "${profile}"

    load_profile_config "$conf"

    pacman_conf=$(get_pacman_conf)

    mirrors_conf=$(get_pac_mirrors_conf "${target_branch}")

    iso_file=$(gen_iso_fn).iso

    iso_label=$(get_iso_label "${dist_branding}_${profile}_${dist_codename//.}")

    mkchroot_args+=(-C ${pacman_conf} -S ${mirrors_conf} -B "${build_mirror}/${target_branch}" -K)
    work_dir=${chroots_iso}/${profile}/${target_arch}

    iso_dir="${cache_dir_iso}/${edition}/${profile}/${dist_timestamp}"

    iso_root=${chroots_iso}/${profile}/iso
    mnt_dir=${chroots_iso}/${profile}/mnt
    prepare_dir "${mnt_dir}"

    prepare_dir "${iso_dir}"
    user_own "${cache_dir_iso}" "-R"
}

prepare_profile(){
    profile=$1
    edition=$(get_edition ${profile})
    profile_dir=${run_dir}/${edition}/${profile}
    check_profile "${profile_dir}"
    load_profile "${profile_dir}"
}

build(){
    prepare_profile "$1"
    make_profile
}
