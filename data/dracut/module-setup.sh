#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    return 0
}

# called by dracut
install() {
    inst losetup
    inst mountpoint
    inst md5sum
    inst /usr/lib/udev/rules.d/60-cdrom_id.rules

    hostonly='' instmods overlay
    hostonly='' instmods loop
    hostonly='' instmods cdrom

    inst_hook cmdline 15 "$moddir/parse-miso.sh"
    inst_hook pre-mount 000 "$moddir/miso.sh"
    inst_script "$moddir/miso-generator.sh" "$systemdutildir"/system-generators/dracut-miso-generator
}
