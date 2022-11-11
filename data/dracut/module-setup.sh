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

    hostonly='' instmods overlay
    hostonly='' instmods loop
    inst_hook mount 000 "$moddir/miso.sh"
}
