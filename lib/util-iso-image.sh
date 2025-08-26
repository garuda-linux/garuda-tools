#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

copy_overlay(){
    if [[ -e $1 ]]; then
        msg2 "Copying [%s] ..." "${1##*/}"
        if [[ -L $1 ]]; then
            cp -a --no-preserve=ownership $1/* $2
        else
            cp -LR $1/* $2
        fi
    fi
}

configure_plymouth(){
    if [[ -f "$1"/usr/bin/plymouth ]];then
        msg2 "Configuring plymouth: %s" "${plymouth_theme}"
        local conf=$1/etc/plymouth/plymouthd.conf
        sed -i -e "s/^.*Theme=.*/Theme=${plymouth_theme}/" "${conf}"
    fi
}

add_svc_rc(){
    if [[ -f $1/etc/init.d/$2 ]]; then
        msg2 "Setting %s ..." "$2"
        chroot $1 rc-update add $2 default &>/dev/null
    fi
}

add_svc_sd(){
    if [[ -f $1/etc/systemd/system/$2.service ]] || \
    [[ -f $1/usr/lib/systemd/system/$2.service ]]; then
        msg2 "Setting %s ..." "$2"
        chroot $1 systemctl enable $2 &>/dev/null
    fi
    if [[ -f $1/etc/systemd/system/$2 ]] || \
    [[ -f $1/usr/lib/systemd/system/$2 ]]; then
        msg2 "Setting %s ..." "$2"
        chroot $1 systemctl enable $2 &>/dev/null
    fi
}

set_xdm(){
    if [[ -f $1/etc/conf.d/xdm ]]; then
        local conf='DISPLAYMANAGER="'${displaymanager}'"'
        sed -i -e "s|^.*DISPLAYMANAGER=.*|${conf}|" $1/etc/conf.d/xdm
    fi
}

configure_branding(){
    msg2 "Configuring branding"
    echo "---
componentName:  garuda

# This selects between different welcome texts. When false, uses
# the traditional 'Welcome to the %1 installer.', and when true,
# uses 'Welcome to the Calamares installer for %1.'. This allows
# to distinguish this installer from other installers for the
# same distribution.
welcomeStyleCalamares:   ${welcomestyle}

# Should the welcome image (productWelcome, below) be scaled
# up beyond its natural size? If false, the image does not grow
# with the window but remains the same size throughout (this
# may have surprising effects on HiDPI monitors).
welcomeExpandingLogo:   ${welcomelogo}

# Size and expansion policy for Calamares.
#  - "normal" or unset, expand as needed, use *windowSize*
#  - "fullscreen", start as large as possible, ignore *windowSize*
#  - "noexpand", never expand, use *windowSize*
windowExpanding:    ${windowexp}

# Size of Calamares window, expressed as w,h. Both w and h
# may be either pixels (suffix px) or font-units (suffix em).
#   e.g.    "800px,600px"
#           "60em,480px"
# This setting is ignored if "fullscreen" is selected for
# *windowExpanding*, above. If not set, use constants defined
# in CalamaresUtilsGui, 800x520.
windowSize: ${windowsize}

# Placement of Calamares window. Either "center" or "free".
# Whether "center" actually works does depend on the window
# manager in use (and only makes sense if you're not using
# *windowExpanding* set to "fullscreen").
windowPlacement: ${windowplacement}

# These are strings shown to the user in the user interface.
# There is no provision for translating them -- since they
# are names, the string is included as-is.
#
# The four Url strings are the Urls used by the buttons in
# the welcome screen, and are not shown to the user. Clicking
# on the "Support" button, for instance, opens the link supportUrl.
# If a Url is empty, the corresponding button is not shown.
#
# bootloaderEntryName is how this installation / distro is named
# in the boot loader (e.g. in the GRUB menu).
strings:
    productName:         ${dist_name} Linux
    shortProductName:    ${dist_name}
    version:             ${dist_release}
    shortVersion:        ${dist_release}
    versionedName:       ${dist_name} Linux ${dist_release}
    shortVersionedName:  ${dist_name} ${dist_release}
    bootloaderEntryName: ${dist_name}

# These images are loaded from the branding module directory.
#
# productIcon is used as the window icon, and will (usually) be used
#       by the window manager to represent the application. This image
#       should be square, and may be displayed by the window manager
#       as small as 16x16 (but possibly larger).
# productLogo is used as the logo at the top of the left-hand column
#       which shows the steps to be taken. The image should be square,
#       and is displayed at 80x80 pixels (also on HiDPI).
# productWelcome is shown on the welcome page of the application in
#       the middle of the window, below the welcome text. It can be
#       any size and proportion, and will be scaled to fit inside
#       the window. Use 'welcomeExpandingLogo' to make it non-scaled.
#       Recommended size is 320x150.
images:
    productLogo:         "logo.png"
    productIcon:         "logo.png"
    productWelcome:      "languages.png"

# The slideshow is displayed during execution steps (e.g. when the
# installer is actually writing to disk and doing other slow things).
slideshow:               "show.qml"

# There are two available APIs for the slideshow:
#  - 1 (the default) loads the entire slideshow when the installation-
#      slideshow page is shown and starts the QML then. The QML
#      is never stopped (after installation is done, times etc.
#      continue to fire).
#  - 2 loads the slideshow on startup and calls onActivate() and
#      onLeave() in the root object. After the installation is done,
#      the show is stopped (first by calling onLeave(), then destroying
#      the QML components).
slideshowAPI: 1

# Colors for text and background components.
#
#  - sidebarBackground is the background of the sidebar
#  - sidebarText is the (foreground) text color
#  - sidebarTextHighlight sets the background of the selected (current) step.
#    Optional, and defaults to the application palette.
#  - sidebarSelect is the text color of the selected step.
#
style:
   SidebarBackground:    "\"${sidebarbackground}"\"
   SidebarText:          "\"${sidebartext}"\"
   SidebarTextCurrent:    "\"${sidebartextcurrent}"\"
   SidebarBackgroundCurrent: "\"${sidebarbackgroundcurrent}"\"" > $1/usr/share/calamares/branding/garuda/branding.desc
}

configure_polkit_user_rules(){
    msg2 "Configuring polkit user rules"
    echo "/* Stop asking the user for a password while they are in a live session
 */
polkit.addRule(function(action, subject) {
    if (subject.user == \"${username}\")
    {
        return polkit.Result.YES;
    }
});" > $1/etc/polkit-1/rules.d/49-nopasswd-live.rules
}

configure_logind(){
    msg2 "Configuring logind ..."
    local conf=$1/etc/systemd/logind.conf
    sed -i 's/#\(HandleSuspendKey=\)suspend/\1ignore/' "$conf"
    sed -i 's/#\(HandleLidSwitch=\)suspend/\1ignore/' "$conf"
    sed -i 's/#\(HandleHibernateKey=\)hibernate/\1ignore/' "$conf"
}

configure_journald(){
    msg2 "Configuring journald ..."
    local conf=$1/etc/systemd/journald.conf
    sed -i 's/#\(Storage=\)auto/\1volatile/' "$conf"
}

disable_srv_live(){
    for srv in ${disable_systemd_live[@]}; do
         enable_systemd_live=(${enable_systemd_live[@]//*$srv*})
    done
}

configure_services(){
    info "Configuring services"
    use_apparmor="false"
    apparmor_boot_args=""
    enable_systemd_live=(${enable_systemd_live[@]} ${enable_systemd[@]})

    [[ ! -z $disable_systemd_live ]] && disable_srv_live

    for svc in ${enable_systemd_live[@]}; do
        add_svc_sd "$1" "$svc"
        [[ "$svc" == "apparmor" ]] && use_apparmor="true"
    done

    if [[ ${use_apparmor} == 'true' ]]; then
        msg2 "Enable apparmor kernel parameters"
        apparmor_boot_args="'apparmor=1' 'security=apparmor'"
    fi

    info "Done configuring services"
}

write_live_session_conf(){
    local path=$1${SYSCONFDIR}
    [[ ! -d $path ]] && mkdir -p $path
    local conf=$path/live.conf
    msg2 "Writing %s" "${conf##*/}"
    echo '# live session configuration' > ${conf}
    echo '' >> ${conf}
    echo '# autologin' >> ${conf}
    echo "autologin=${autologin}" >> ${conf}
    echo '' >> ${conf}
    echo '# login shell' >> ${conf}
    echo "login_shell=${login_shell}" >> ${conf}
    echo '' >> ${conf}
    echo '# live username' >> ${conf}
    echo "username=${username}" >> ${conf}
    echo '' >> ${conf}
    echo '# live password' >> ${conf}
    echo "password=${password}" >> ${conf}
    echo '' >> ${conf}
    echo '# live group membership' >> ${conf}
    echo "addgroups='${addgroups}'" >> ${conf}
    if [[ -n ${smb_workgroup} ]]; then
        echo '' >> ${conf}
        echo '# samba workgroup' >> ${conf}
        echo "smb_workgroup=${smb_workgroup}" >> ${conf}
    fi
}

configure_hosts(){
    sed -e "s|localhost.localdomain|localhost.localdomain ${hostname}|" -i $1/etc/hosts
}

configure_system(){
    configure_logind "$1"
    configure_journald "$1"

    # Prevent some services to be started in the livecd
    echo 'File created by garuda-tools. See systemd-update-done.service(8).' \
    | tee "${path}/etc/.updated" >"${path}/var/.updated"

    msg2 "Disable systemd-gpt-auto-generator"
    ln -sf /dev/null "${path}/usr/lib/systemd/system-generators/systemd-gpt-auto-generator"
    echo ${hostname} > $1/etc/hostname
}

configure_thus(){
    msg2 "Configuring Thus ..."
    source "$1/etc/mkinitcpio.d/${kernel}.preset"
    local conf="$1/etc/thus.conf"
    echo "[distribution]" > "$conf"
    echo "DISTRIBUTION_NAME = \"${dist_name} Linux\"" >> "$conf"
    echo "DISTRIBUTION_VERSION = \"${dist_release}\"" >> "$conf"
    echo "SHORT_NAME = \"${dist_name}\"" >> "$conf"
    echo "[install]" >> "$conf"
    echo "LIVE_MEDIA_SOURCE = \"/run/miso/bootmnt/${iso_name}/${target_arch}/rootfs.sfs\"" >> "$conf"
    echo "LIVE_MEDIA_DESKTOP = \"/run/miso/bootmnt/${iso_name}/${target_arch}/desktopfs.sfs\"" >> "$conf"
    echo "LIVE_MEDIA_TYPE = \"squashfs\"" >> "$conf"
    echo "LIVE_USER_NAME = \"${username}\"" >> "$conf"
    echo "KERNEL = \"${kernel}\"" >> "$conf"
    echo "VMLINUZ = \"$(echo ${ALL_kver} | sed s'|/boot/||')\"" >> "$conf"
    echo "INITRAMFS = \"$(echo ${default_image} | sed s'|/boot/||')\"" >> "$conf"
    echo "FALLBACK = \"$(echo ${fallback_image} | sed s'|/boot/||')\"" >> "$conf"

#    if [[ -f $1/usr/share/applications/thus.desktop && -f $1/usr/bin/kdesu ]]; then
#        sed -i -e 's|sudo|kdesu|g' $1/usr/share/applications/thus.desktop
#    fi
}

configure_live_image(){
    msg "Configuring [livefs]"
    configure_hosts "$1"
    configure_system "$1"
    configure_services "$1"
    configure_calamares "$1"
    configure_plymouth "$1"
#    [[ ${edition} == "sonar" ]] && configure_thus "$1"
    write_live_session_conf "$1"
    msg "Done configuring [livefs]"
}

make_repo(){
    repo-add $1${mhwd_repo}/ght.db.tar.gz $1${mhwd_repo}/*pkg.tar*
}

copy_from_cache(){
    local list="${tmp_dir}"/mhwd-cache.list
    chroot-run \
        -r "${mountargs_ro}" \
        -w "${mountargs_rw}" \
        -B "${build_mirror}/${target_branch}" \
        "$1" \
        pacman -v -Syw $2 --noconfirm || return 1
    chroot-run \
        -r "${mountargs_ro}" \
        -w "${mountargs_rw}" \
        -B "${build_mirror}/${target_branch}" \
        "$1" \
        pacman -v -Sp $2 --noconfirm > "$list"
    sed -ni '/pkg.tar/p' "$list"
    sed -i "s/.*\///" "$list"

    msg2 "Copying mhwd package cache ..."
    rsync -v --files-from="$list" /var/cache/pacman/pkg "$1${mhwd_repo}"
}

chroot_create(){
    [[ "${1##*/}" == "rootfs" ]] && local flag="-L"
    setarch "${target_arch}" \
        mkchroot ${mkchroot_args[*]} ${flag} $@
}

clean_iso_root(){
    msg2 "Deleting isoroot [%s] ..." "${1##*/}"
    rm -rf --one-file-system "$1"
}

chroot_clean(){
    msg "Cleaning up ..."
    for image in "$1"/*fs; do
        [[ -d ${image} ]] || continue
        local name=${image##*/}
        if [[ $name != "ghtfs" ]]; then
            msg2 "Deleting chroot [%s] (%s) ..." "$name" "${1##*/}"
            lock 9 "${image}.lock" "Locking chroot '${image}'"
            if [[ "$(stat -f -c %T "${image}")" == btrfs ]]; then
                { type -P btrfs && btrfs subvolume delete "${image}"; } #&> /dev/null
            fi
        rm -rf --one-file-system "${image}"
        fi
    done
    exec 9>&-
    rm -rf --one-file-system "$1"
}

clean_up_image(){
    msg2 "Cleaning [%s]" "${1##*/}"

    local path
    if [[ ${1##*/} == 'ghtfs' ]]; then
        path=$1/var
        if [[ -d $path/lib/mhwd ]]; then
            mv $path/lib/mhwd $1 &> /dev/null
        fi
        if [[ -d $path ]]; then
            find "$path" -mindepth 0 -delete &> /dev/null
        fi
        if [[ -d $1/mhwd ]]; then
            mkdir -p $path/lib
            mv $1/mhwd $path/lib &> /dev/null
        fi
        path=$1/etc
        if [[ -d $path ]]; then
            find "$path" -mindepth 0 -delete &> /dev/null
        fi
    else
        [[ -f "$1/etc/locale.gen.bak" ]] && mv "$1/etc/locale.gen.bak" "$1/etc/locale.gen"
        [[ -f "$1/etc/locale.conf.bak" ]] && mv "$1/etc/locale.conf.bak" "$1/etc/locale.conf"
        path=$1/boot
        if [[ -d "$path" ]]; then
            find "$path" -name 'initramfs*.img' -delete &> /dev/null
        fi
        path=$1/var/lib/pacman/sync
        if [[ -d $path ]]; then
            find "$path" -type f -delete &> /dev/null
        fi
        path=$1/var/cache/pacman/pkg
        if [[ -d $path ]]; then
            find "$path" -type f -delete &> /dev/null
        fi
        path=$1/var/log
        if [[ -d $path ]]; then
            find "$path" -type f -delete &> /dev/null
        fi
        path=$1/var/tmp
        if [[ -d $path ]]; then
            find "$path" -mindepth 1 -delete &> /dev/null
        fi
        path=$1/tmp
        if [[ -d $path ]]; then
            find "$path" -mindepth 1 -delete &> /dev/null
        fi
    fi
	find "$1" -name *.pacnew -name *.pacsave -name *.pacorig -delete
	rm -f "$1"/boot/grub/grub.cfg
	rm -f "$1"/var/lib/garuda/partial_upgrade
    rm -rf "$1"/var/lib/garuda/tmp/
}
