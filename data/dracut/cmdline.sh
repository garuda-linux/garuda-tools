#!/bin/bash

[ -z "$root" ] && root=$(getarg root=)

if [ "${root%%:*}" = "misolabel" ]; then
    rootok=1
fi