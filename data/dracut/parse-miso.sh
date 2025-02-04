#!/bin/bash

case "${root#miso:}" in
    LABEL=* | UUID=* | PARTUUID=* | PARTLABEL=*)
        root="miso:$(label_uuid_to_dev "block:${root#miso:}")"
        rootok=1
        ;;
    /dev/*)
        root="miso:${root#miso:}"
        rootok=1
        ;;
esac

[ "${root%%:*}" = "miso" ] && wait_for_dev "${root#miso:}"
