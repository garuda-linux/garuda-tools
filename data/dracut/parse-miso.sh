#!/bin/bash

[ -z "$root" ] && root=$(getarg root=)

if [ "${root%%:*}" = "misolabel" ]; then
    rootok=1
    misolabel="${root#misolabel:}"
    [[ -z "${misodevice}" ]] && misodevice="/dev/disk/by-label/${misolabel}"

    wait_for_dev "${misodevice}"
fi