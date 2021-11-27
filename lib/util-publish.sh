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

connect_sourceforge(){
    echo "garuda-team@frs.sourceforge.net:/home/frs/project/garuda-linux/"
}

connect_fosshost(){
    echo "garuda@$1.mirrors.fossho.st:/iso/"
}

sync_sourceforge(){
    local count=1
    local max_count=3
    local delete=""
    [ "$sourceforge_remove" == true ] && delete="--delete-after --delete-excluded"

    msg "Start upload [%s] to [sourceforge] ..." "$dist_timestamp"

    while [[ $count -le $max_count ]]; do
        rsync --exclude 'latest' --include='/'                           \
            --include='/*/'                  \
            --include='/*/*/' \
            --include="/*/*/${dist_timestamp}/"   \
            --include="/*/*/${dist_timestamp}/**" \
            --exclude='*' \
            ${rsync_args[*]} \
            --max-size=5G $delete -e "ssh -o StrictHostKeyChecking=no" \
            "${run_dir}/" "$(connect_sourceforge)"
        if [[ $? != 0 ]]; then
            count=$(($count + 1))
            msg "Upload failed. retrying (%s/%s) ..." "$count" "$max_count"
            sleep 2
        else
            msg "Done upload [sourceforge]"
            show_elapsed_time "${FUNCNAME}" "${timer_start}"
            break
        fi
    done
}

sync_fosshost(){
    local count=1
    local max_count=3

    msg "Start upload [%s] to [fosshost %s] ..." "$dist_timestamp" "$1"

    while [[ $count -le $max_count ]]; do
        rsync --include='/'                           \
            --include='/*/'                  \
            --include='/*/*/' \
            --include="/*/*/${dist_timestamp}/"   \
            --include="/*/*/${dist_timestamp}/**" \
            --include="/latest/" \
            --include="/latest/**" \
            --exclude='*' \
            ${rsync_args[*]} \
            -e "ssh -o StrictHostKeyChecking=no" \
            "${run_dir}/" "$(connect_fosshost $1)"
        if [[ $? != 0 ]]; then
            count=$(($count + 1))
            msg "Upload failed. retrying (%s/%s) ..." "$count" "$max_count"
            sleep 2
        else
            msg "Done upload [fosshost %s]" "$1"
            show_elapsed_time "${FUNCNAME}" "${timer_start}"
            break
        fi
    done
}

update_release_symlinks(){
    msg "Updating release ISO profiles to ${1}}"
    # Delete any existing invalid entries. We don't want to just delete the entire folder, since old links that may not yet exist for our current $1 may still be perfectly valid.
    find "${cache_dir_iso}/latest" -name \*.iso -type l ! -exec test -e {} \; -exec bash -c '
        rm -r "$(dirname "$1")"
    ' _ "{}" \;

    find "${cache_dir_iso}" -not -path "${cache_dir_iso}/latest*" -type f -exec bash -c '
        path="$(realpath --relative-to="$3" "$1")"
        if ! [[ "$path" =~ ^.*\/$2\/.*\..* ]]; then
            exit
        fi
        path="${path/$2\/}"
        folder="$(dirname $path)"
        extension="${path#*.}"

        mkdir -p "$3/latest/$folder"
        filename="$3/latest/$folder/latest.$extension"
        if [ "$extension" == "iso.zsync" ]; then
            \cp "$1" "$filename"
            relative="$(realpath --relative-to="$3/latest/$folder" "${1%.*}")"
            sed -i "0,/.*URL.*/{s|.*URL.*|URL: $relative|}" "$filename"
        else
            relative="$(realpath --relative-to="$3/latest/$folder" "$1")"
            ln -fs "$relative" "$filename"
        fi
        ' _ "{}" "$1" "${cache_dir_iso}" \;
    msg2 "Done!"
}

sync_dir(){
    [ "$release_symlinks" == true ] && update_release_symlinks

    [ "$sourceforge" == true ] && sync_sourceforge
    [ "$fosshost" == true ] && sync_fosshost us && sync_fosshost uk
}