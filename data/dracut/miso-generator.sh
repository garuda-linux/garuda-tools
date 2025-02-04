#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

[ -z "$root" ] && root=$(getarg root=)

[ "${root%%:*}" = "miso" ] || exit 0

{
    echo "[Unit]"
    echo "Before=initrd-root-fs.target"
    echo "[Mount]"
    echo "Where=/sysroot"
    echo "What=/run/miso/root"
    echo "Options=bind"
} > "$GENERATOR_DIR"/sysroot.mount