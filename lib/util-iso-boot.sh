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

prepare_initcpio(){
    msg2 "Copying initcpio ..."
    if ${use_dracut}; then
        install -Dm755 "${DATADIR}"/miso.sh $1/usr/lib/dracut/modules.d/95miso/miso.sh
        install -Dm755 "${DATADIR}"/parse-miso.sh $1/usr/lib/dracut/modules.d/95miso/parse-miso.sh
        install -Dm755 "${DATADIR}"/miso-generator.sh $1/usr/lib/dracut/modules.d/95miso/miso-generator.sh
        install -Dm755 "${DATADIR}"/module-setup.sh $1/usr/lib/dracut/modules.d/95miso/module-setup.sh
    else
        cp /etc/initcpio/hooks/miso* $1/etc/initcpio/hooks
        cp /etc/initcpio/install/miso* $1/etc/initcpio/install
        cp /etc/initcpio/miso_shutdown $1/etc/initcpio
    fi
}

prepare_initramfs(){
    local _kernver=$(ls $1/usr/lib/modules/ | awk '{print $1}')
    if ${use_dracut}; then
        chroot-run $1 \
            /usr/bin/dracut /boot/initramfs.img ${_kernver} --force -o "network" -a miso --no-hostonly
    else
        cp ${DATADIR}/mkinitcpio.conf $1/etc/mkinitcpio-${iso_name}.conf
        if [[ -n ${gpgkey} ]]; then
            su ${OWNER} -c "gpg --export ${gpgkey} >${USERCONFDIR}/gpgkey"
            exec 17<>${USERCONFDIR}/gpgkey
        fi
        MISO_GNUPG_FD=${gpgkey:+17} chroot-run $1 \
            /usr/bin/mkinitcpio -k ${_kernver} \
            -c /etc/mkinitcpio-${iso_name}.conf \
            -g /boot/initramfs.img

        if [[ -n ${gpgkey} ]]; then
            exec 17<&-
        fi
        if [[ -f ${USERCONFDIR}/gpgkey ]]; then
            rm ${USERCONFDIR}/gpgkey
        fi
    fi
}

prepare_boot_extras(){
    cp $1/boot/amd-ucode.img $2/amd_ucode.img
    cp $1/boot/intel-ucode.img $2/intel_ucode.img
    cp $1/usr/share/licenses/amd-ucode/LIC* $2/amd_ucode.LICENSE
    cp $1/usr/share/licenses/intel-ucode/LIC* $2/intel_ucode.LICENSE
    cp $1/boot/memtest86+/memtest.bin $2/memtest
    cp $1/usr/share/licenses/spdx/GPL-2.0-only.txt $2/memtest.COPYING
}

prepare_grub(){
    local platform=i386-pc img='core.img' grub=$2/boot/grub efi=$2/efi/boot \
        data_live=$1/usr/share/grub lib=usr/lib/grub prefix=/boot/grub data=/usr/share/grub \
        path="${work_dir}/rootfs"

    prepare_dir ${grub}/${platform}

    cp ${data_live}/cfg/*.cfg ${grub}

    cp ${path}/${lib}/${platform}/* ${grub}/${platform}

    msg2 "Building %s ..." "${img}"

    grub-mkimage -d ${grub}/${platform} -o ${grub}/${platform}/${img} -O ${platform} -p ${prefix} biosdisk iso9660

    cat ${grub}/${platform}/cdboot.img ${grub}/${platform}/${img} > ${grub}/${platform}/eltorito.img

    case ${target_arch} in
        'i686')
            platform=i386-efi
            img=bootia32.efi
        ;;
        'x86_64')
            platform=x86_64-efi
            img=bootx64.efi
        ;;
    esac

    prepare_dir ${efi}
    prepare_dir ${grub}/${platform}

    cp ${path}/${lib}/${platform}/* ${grub}/${platform}

    msg2 "Building %s ..." "${img}"

    grub-mkimage -d ${grub}/${platform} -o ${efi}/${img} -O ${platform} -p ${prefix} iso9660

    prepare_dir ${grub}/themes
    cp -r ${data_live}/themes/${iso_name}-live ${grub}/themes/
    cp ${data}/unicode.pf2 ${grub}
    cp -r ${data_live}/{locales,tz} ${grub}

    msg2 "Set menu_show_once=1 in '${grub}/grubenv'"
    grub-editenv ${grub}/grubenv set menu_show_once=1

    local size=4M mnt="${mnt_dir}/efiboot" efi_img="$2/efi.img"
    msg2 "Creating fat image of %s ..." "${size}"
    truncate -s ${size} "${efi_img}"
    mkfs.fat -n MISO_EFI "${efi_img}" &>/dev/null
    prepare_dir "${mnt}"
    mount_img "${efi_img}" "${mnt}"
    prepare_dir ${mnt}/efi/boot
    msg2 "Building %s ..." "${img}"
    grub-mkimage -d ${grub}/${platform} -o ${mnt}/efi/boot/${img} -O ${platform} -p ${prefix} iso9660
    umount_img "${mnt}"
}
