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

write_machineid_conf(){
    local conf="${modules_dir}/machineid.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo '---' > "$conf"
    echo "systemd: true" >> $conf
    echo "dbus: true" >> $conf
    echo "symlink: true" >> $conf
}

write_finished_conf(){
    msg2 "Writing %s ..." "finished.conf"
    local conf="${modules_dir}/finished.conf" cmd="systemctl reboot"
    echo '---' > "$conf"
    echo 'restartNowEnabled: true' >> "$conf"
    echo 'restartNowChecked: false' >> "$conf"
    echo "restartNowCommand: \"${cmd}\"" >> "$conf"
}

get_preset(){
    local p=${tmp_dir}/${kernel}.preset kvmaj kvmin digit
    cp ${DATADIR}/linux.preset $p
    digit=${kernel##linux}
    kvmaj=${digit:0:1}
    kvmin=${digit:1}

    sed -e "s|@kvmaj@|$kvmaj|g" \
        -e "s|@kvmin@|$kvmin|g" \
        -e "s|@arch@|${target_arch}|g"\
        -i $p
    echo $p
}

write_bootloader_conf(){
    local conf="${modules_dir}/bootloader.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    source "$(get_preset)"
    echo '---' > "$conf"
    echo "efiBootLoader: \"${efi_boot_loader}\"" >> "$conf"
    echo 'grubInstall: "grub-install"' >> "$conf"
    echo 'grubMkconfig: "grub-mkconfig"' >> "$conf"
    echo 'grubCfg: "/boot/grub/grub.cfg"' >> "$conf"
    echo 'grubProbe: "grub-probe"' >> "$conf"
    echo 'efiBootMgr: "efibootmgr"' >> "$conf"
    echo 'installEFIFallback: true' >> "$conf"
}

write_services_conf(){
    local conf="${modules_dir}/services-systemd.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo '---' >  "$conf"
    echo 'units:' > "$conf"
    for s in ${enable_systemd[@]}; do
        echo "    - name: $s" >> "$conf"
        echo '      action: "enable"' >> "$conf"
    done
    echo '    - name: "graphical"' >> "$conf"
    echo '      action: "set-default"' >> "$conf"
    if ${zfs_used}; then
    echo '    - name: "zfs"' >> "$conf"
    echo '      mandatory: true' >> "$conf"
    echo '      action: "enable"' >> "$conf"
    echo '    - name: "zfs-import"' >> "$conf"
    echo '      mandatory: true' >> "$conf"
    echo '      action: "enable"' >> "$conf"
    fi
    for s in ${disable_systemd[@]}; do
        echo "    - name: $s" >> "$conf"
        echo '      action: "disable"' >> "$conf"
    done
}

write_displaymanager_conf(){
    local conf="${modules_dir}/displaymanager.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "displaymanagers:" >> "$conf"
    echo "  - lightdm" >> "$conf"
    echo "  - gdm" >> "$conf"
    echo "  - mdm" >> "$conf"
    echo "  - sddm" >> "$conf"
    echo "  - lxdm" >> "$conf"
    echo "  - slim" >> "$conf"
    echo '' >> "$conf"
    echo "basicSetup: false" >> "$conf"
}

write_initcpio_conf(){
    local conf="${modules_dir}/initcpio.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "kernel: ${kernel}" >> "$conf"
}

write_dracut_conf(){
    local conf="${modules_dir}/dracut.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "initramfsName: /boot/initramfs-${kernel}.img" >> "$conf"
}

write_unpack_conf(){
    local conf="${modules_dir}/unpackfs.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "unpack:" >> "$conf"
    echo "    - source: \"/run/miso/bootmnt/${iso_name}/${target_arch}/rootfs.sfs\"" >> "$conf"
    echo "      sourcefs: \"squashfs\"" >> "$conf"
    echo "      destination: \"\"" >> "$conf"
    if [[ -f "${packages_desktop}" ]] ; then
        echo "    - source: \"/run/miso/bootmnt/${iso_name}/${target_arch}/desktopfs.sfs\"" >> "$conf"
        echo "      sourcefs: \"squashfs\"" >> "$conf"
        echo "      destination: \"\"" >> "$conf"
    fi
}

write_users_conf(){
    local conf="${modules_dir}/users.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "defaultGroups:" >> "$conf"
    local IFS=','
    for g in ${addgroups[@]}; do
        echo "    - $g" >> "$conf"
    done
    unset IFS
    echo "autologinGroup:  autologin" >> "$conf"
    echo "doAutologin:     false" >> "$conf" # can be either 'true' or 'false'
    echo "sudoersGroup:    wheel" >> "$conf"
    echo "setRootPassword: true" >> "$conf" # must be true, else some options get hidden
    echo "doReusePassword: true" >> "$conf" # only used in old 'users' module
    echo "availableShells: /bin/bash, /bin/zsh" >> "$conf" # only used in new 'users' module
    echo "avatarFilePath:  ~/.face" >> "$conf" # mostly used file-name for avatar
    if [[ -n "$user_shell" ]]; then
        echo "userShell:       $user_shell" >> "$conf"
    fi
    echo "passwordRequirements:
    nonempty: true" >> "$conf" # make sure the user doesn't enter an empty password
}

write_packages_conf(){
    local conf="${modules_dir}/packages.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "backend: pacman" >> "$conf"
    echo '' >> "$conf"
    if ${needs_internet}; then
        echo "skip_if_no_internet: false" >> "$conf"
    else
        echo "skip_if_no_internet: true" >> "$conf"
    fi 
    echo "update_db: true" >> "$conf"
    echo "update_system: true" >> "$conf"
}

write_welcome_conf(){
    local conf="${modules_dir}/welcome.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf" >> "$conf"
    echo "showSupportUrl:         true" >> "$conf"
    echo "showKnownIssuesUrl:     true" >> "$conf"
    echo "showReleaseNotesUrl:    true" >> "$conf"
    echo '' >> "$conf"
    echo "requirements:" >> "$conf"
    echo "    requiredStorage:    29.9" >> "$conf"
    echo "    requiredRam:        2.5" >> "$conf"
    echo "    internetCheckUrl:   https://garudalinux.org" >> "$conf"
    echo "    check:" >> "$conf"
    echo "      - storage" >> "$conf"
    echo "      - ram" >> "$conf"
    echo "      - power" >> "$conf"
    echo "      - internet" >> "$conf"
    echo "      - root" >> "$conf"
    echo "      - efi" >> "$conf"
    echo "    required:" >> "$conf"
    echo "      - storage" >> "$conf"
    echo "      - ram" >> "$conf"
    echo "      - root" >> "$conf"
    if ${needs_internet}; then
        echo "      - internet" >> "$conf"
    fi
    if ${geoip}; then
        echo 'geoip:' >> "$conf"
        echo '    style:  "json"' >> "$conf"
        echo '    url:    "https://ipapi.co/json"' >> "$conf"
        echo '    selector: "country"' >> "$conf"
    fi
}

write_mhwdcfg_conf(){
    local conf="${modules_dir}/ghtcfg.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    local drv="free"
    ${nonfree_mhwd} && drv="nonfree"
    echo "driver: ${drv}" >> "$conf"
    echo '' >> "$conf"
    local switch='true'
    ${netinstall} && switch='false'
    echo "local: ${switch}" >> "$conf"
    echo '' >> "$conf"
    echo 'repo: /opt/ght/pacman-ght.conf' >> "$conf"
}

write_postcfg_conf(){
    local conf="${modules_dir}/postcfg.conf"
    if [[ -n ${smb_workgroup} ]]; then
        msg2 "Writing %s ..." "${conf##*/}"
        echo "---" > "$conf"
        echo "samba:" >> "$conf"
        echo "    - workgroup:  ${smb_workgroup}" >> "$conf"
    fi
}

write_zfspartitioncfg_conf(){
    local conf="${modules_dir}/partition.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo 'defaultFileSystemType:  "zfs"' >> "$conf"
}

#get_yaml(){
#    local args=() yaml
#    if ${chrootcfg}; then
#        args+=("${profile}/chrootcfg")
#    else
#        args+=("${profile}/packages")
#   fi
#    args+=("systemd")
#    for arg in ${args[@]}; do
#        yaml=${yaml:-}${yaml:+-}${arg}
#    done
#    echo "${yaml}.yaml"
#}

write_netinstall_conf(){
    local conf="${modules_dir}/netinstall.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "groupsUrl: ${netgroups}" >> "$conf"
    echo "label:" >> "$conf"
    echo "    sidebar: \"${netinstall_label}\"" >> "$conf"
}

write_plymouthcfg_conf(){
    local conf="${modules_dir}/plymouthcfg.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "plymouth_theme: ${plymouth_theme}" >> "$conf"
}

write_locale_conf(){
    local conf="${modules_dir}/locale.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "localeGenPath: /etc/locale.gen" >> "$conf"
    if ${geoip}; then
        echo 'geoip:' >> "$conf"
        echo '    style:  "json"' >> "$conf"
        echo '    url:    "https://ipapi.co/json"' >> "$conf"
        echo '    selector: "timezone"' >> "$conf"
    else
        echo "region: America" >> "$conf"
        echo "zone: New_York" >> "$conf"
    fi
}

write_partition_conf(){
    local conf="${modules_dir}/partition.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo 'efiSystemPartition: "/boot/efi"' >> "$conf"
    echo 'drawNestedPartitions: false' >> "$conf"
    echo 'alwaysShowPartitionLabels: true' >> "$conf"
    echo "efi:" >> "$conf"
    echo "    minimumSize: 260MiB" >> "$conf"
    echo "userSwapChoices:" >> "$conf"
    echo "    - none" >> "$conf"
    echo "    - suspend" >> "$conf"
    echo "defaultFileSystemType: btrfs" >> "$conf"
    echo "directoryFilesystemRestrictions:" >> "$conf"
    echo '    - directory: "/"' >> "$conf"
    echo '      allowedFilesystemTypes: ["btrfs"]' >> "$conf"
    echo '    - directory: "efi"' >> "$conf"
    echo '      allowedFilesystemTypes: ["fat32"]' >> "$conf"
    echo '      onlyWhenMountpoint: true' >> "$conf"
}

write_mount_conf(){
    local conf="${modules_dir}/mount.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "btrfsSubvolumes:" >> "$conf"
    echo "    - mountPoint: /" >> "$conf"
    echo "      subvolume: /@" >> "$conf"
    echo "    - mountPoint: /home" >> "$conf"
    echo "      subvolume: /@home" >> "$conf"
    echo "    - mountPoint: /root" >> "$conf"
    echo "      subvolume: /@root" >> "$conf"
    echo "    - mountPoint: /srv" >> "$conf"
    echo "      subvolume: /@srv" >> "$conf"
    echo "    - mountPoint: /var/cache" >> "$conf"
    echo "      subvolume: /@cache" >> "$conf"
    echo "    - mountPoint: /var/log" >> "$conf"
    echo "      subvolume: /@log" >> "$conf"
    echo "    - mountPoint: /var/tmp" >> "$conf"
    echo "      subvolume: /@tmp" >> "$conf"
    echo "mountOptions:" >> "$conf"
    echo "    - filesystem: default" >> "$conf"
    echo "      options: [ defaults ]" >> "$conf"
    echo "    - filesystem: efi" >> "$conf"
    echo "      options: [ defaults, umask=0077 ]" >> "$conf"
    echo "    - filesystem: btrfs" >> "$conf"
    echo "      options: [ defaults, noatime, compress=zstd ]" >> "$conf"
    echo "    - filesystem: btrfs_swap" >> "$conf"
    echo "      options: [ defaults, noatime ]" >> "$conf"
    echo "extraMounts:" >> "$conf"
    echo "    - device: proc" >> "$conf"
    echo "      fs: proc" >> "$conf"
    echo "      mountPoint: /proc" >> "$conf"
    echo "    - device: sys" >> "$conf"
    echo "      fs: sysfs" >> "$conf"
    echo "      mountPoint: /sys" >> "$conf"
    echo "    - device: /dev" >> "$conf"
    echo "      mountPoint: /dev" >> "$conf"
    echo "      options: [ bind ]" >> "$conf"
    echo "    - device: tmpfs" >> "$conf"
    echo "      fs: tmpfs" >> "$conf"
    echo "      mountPoint: /run" >> "$conf"
    echo "    - device: /run/udev" >> "$conf"
    echo "      mountPoint: /run/udev" >> "$conf"
    echo "      options: [ bind ]" >> "$conf"
    echo "    - device: efivarfs" >> "$conf"
    echo "      fs: efivarfs" >> "$conf"
    echo "      mountPoint: /sys/firmware/efi/efivars" >> "$conf"
    echo "      efi: true" >> "$conf"
}

write_settings_conf(){
    local conf="$1/etc/calamares/settings.conf"
    msg2 "Writing %s ..." "${conf##*/}"
    echo "---" > "$conf"
    echo "modules-search: [ local ]" >> "$conf"
    echo '' >> "$conf"
    echo "sequence:" >> "$conf"
    echo "    - show:" >> "$conf"
    echo "        - welcome" >> "$conf" && write_welcome_conf
    if ${oem_used}; then
        msg2 "Skipping to show locale and keyboard modules."
    else
        echo "        - locale" >> "$conf" && write_locale_conf
        echo "        - keyboard" >> "$conf"
    fi
    echo "        - partition" >> "$conf" && write_partition_conf
    if ${oem_used}; then
        msg2 "Skipping to show users module."
    else
        echo "        - users" >> "$conf" && write_users_conf
    fi
    # WIP - OfficeChooser
    if ${extra}; then
#        if ${oem_used}; then
            msg2 "Skipping enabling PackageChooser module."
#        else
#            msg2 "Enabling PackageChooser module."
#            echo "        - packagechooser" >> "$conf"
#        fi
    fi
    if ${netinstall}; then
        echo "        - netinstall" >> "$conf" && write_netinstall_conf
    fi
    echo "        - summary" >> "$conf"
    echo "    - exec:" >> "$conf"
    echo "        - partition" >> "$conf"
    if ${zfs_used}; then
        echo "        - zfs" >> "$conf" && write_zfspartitioncfg_conf
    else
        msg2 "Skipping to set zfs module."
    fi
    echo "        - mount" >> "$conf" && write_mount_conf
    if ${netinstall}; then
        if ${chrootcfg}; then
            echo "        - chrootcfg" >> "$conf"
            echo "        - networkcfg" >> "$conf"
        else
            echo "        - unpackfs" >> "$conf" && write_unpack_conf
            echo "        - networkcfg" >> "$conf"
            echo "        - packages" >> "$conf" && write_packages_conf
        fi
    else
        echo "        - unpackfs" >> "$conf" && write_unpack_conf
        echo "        - networkcfg" >> "$conf"
    fi
    echo "        - machineid" >> "$conf" && write_machineid_conf
    if ${oem_used}; then
        msg2 "Skipping to set locale, keyboard and localecfg modules."
    else
        echo "        - locale" >> "$conf"
        echo "        - keyboard" >> "$conf"
        echo "        - localecfg" >> "$conf"
    fi
    echo "        - luksbootkeyfile" >> "$conf"
    echo "        - fstab" >> "$conf"
    echo "        - plymouthcfg" >> "$conf" && write_plymouthcfg_conf
    if ${oem_used}; then
        msg2 "Skipping to set users module."
    else
        echo "        - users" >> "$conf"
    fi
    echo "        - displaymanager" >> "$conf" && write_displaymanager_conf
    if ${mhwd_used}; then
        echo "        - ghtcfg" >> "$conf" && write_mhwdcfg_conf
    else
        msg2 "Skipping to set mhwdcfg module."
    fi
    echo "        - hwclock" >> "$conf"
    echo "        - services-systemd" >> "$conf" && write_services_conf
    if ${use_dracut}; then
        echo "        - dracutlukscfg" >> "$conf"
    else
        echo "        - luksopenswaphookcfg" >> "$conf"
        echo "        - initcpiocfg" >> "$conf"
        echo "        - initcpio" >> "$conf" && write_initcpio_conf
    fi
    echo "        - postcfg" >> "$conf" && write_postcfg_conf
    echo "        - grubcfg" >> "$conf"
    echo "        - bootloader" >> "$conf" && write_bootloader_conf
    echo "        - umount" >> "$conf"
    echo "    - show:" >> "$conf"
    echo "        - finished" >> "$conf" && write_finished_conf
    echo '' >> "$conf"
    echo "branding: ${iso_name}" >> "$conf"
    echo '' >> "$conf"
    if ${oem_used}; then
        echo "prompt-install: false" >> "$conf"
    else
        echo "prompt-install: true" >> "$conf"
    fi
    echo '' >> "$conf"
    echo "dont-chroot: false" >> "$conf"
    if ${oem_used}; then
        echo "oem-setup: true" >> "$conf"
        echo "disable-cancel: true" >> "$conf"        
    else
        echo "oem-setup: false" >> "$conf"
        echo "disable-cancel: false" >> "$conf"
    fi
    echo "disable-cancel-during-exec: true" >> "$conf"
    echo "quit-at-end: false" >> "$conf"
}

configure_calamares(){
    info "Configuring [Calamares]"
    modules_dir=$1/etc/calamares/modules
    prepare_dir "${modules_dir}"
    write_settings_conf "$1"
    info "Done configuring [Calamares]"
}

check_yaml(){
    msg2 "Checking validity [%s] ..." "${1##*/}"
    local name=${1##*/} data=$1 schema
    case ${name##*.} in
        yaml)
            name=netgroups
#             data=$1
        ;;
        conf)
            name=${name%.conf}
#             data=${tmp_dir}/$name.yaml
#             cp $1 $data
        ;;
    esac
    local schemas_dir=/usr/share/calamares/schemas
    schema=${schemas_dir}/$name.schema.yaml
#     pykwalify -d $data -s $schema
    kwalify -lf $schema $data
}

write_calamares_yaml(){
    configure_calamares "${yaml_dir}"
    if ${validate}; then
        for conf in "${yaml_dir}"/etc/calamares/modules/*.conf "${yaml_dir}"/etc/calamares/settings.conf; do
            check_yaml "$conf"
        done
    fi
}

write_netgroup_yaml(){
    msg2 "Writing %s ..." "${2##*/}"
    echo "---" > "$2"
    echo "- name: '$1'" >> "$2"
    echo "  description: '$1'" >> "$2"
    echo "  selected: false" >> "$2"
    echo "  hidden: false" >> "$2"
    echo "  critical: false" >> "$2"
    echo "  packages:" >> "$2"
    for p in ${packages[@]}; do
        echo "       - $p" >> "$2"
    done
    ${validate} && check_yaml "$2"
}

write_pacman_group_yaml(){
    packages=$(pacman -Sgq "$1")
    prepare_dir "${cache_dir_netinstall}/pacman"
    write_netgroup_yaml "$1" "${cache_dir_netinstall}/pacman/$1.yaml"
    ${validate} && check_yaml "${cache_dir_netinstall}/pacman/$1.yaml"
    user_own "${cache_dir_netinstall}/pacman" "-R"
}

prepare_check(){
    profile=$1
    local edition=$(get_edition ${profile})
    profile_dir=${run_dir}/${edition}/${profile}
    check_profile "${profile_dir}"
    load_profile_config "${profile_dir}/profile.conf"

    yaml_dir=${cache_dir_netinstall}/${profile}/${target_arch}

    prepare_dir "${yaml_dir}"
    user_own "${yaml_dir}"
}

gen_fn(){
    echo "${yaml_dir}/$1-${target_arch}-systemd.yaml"
}

make_profile_yaml(){
    prepare_check "$1"
    load_pkgs "${profile_dir}/Packages-Root"
    write_netgroup_yaml "$1" "$(gen_fn "Packages-Root")"
    if [[ -f "${packages_desktop}" ]]; then
        load_pkgs "${packages_desktop}"
        if [[ -f "${packages_desktop_common}" ]]; then
            load_pkgs "${packages_desktop_common}" true
        fi
        write_netgroup_yaml "$1" "$(gen_fn "Packages-Desktop")"
    fi
    ${calamares} && write_calamares_yaml "$1"
    user_own "${cache_dir_netinstall}/$1" "-R"
    reset_profile
    unset yaml_dir
}
