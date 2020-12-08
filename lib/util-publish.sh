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

local MINIMAL

connect(){
    ${alt_storage} && server="storage-in" || server="storage"
    local storage="@${server}.sourceforge.net:/home/frs/project/garuda-linux/"
    echo "${account}${storage}${project}"
}

connect_shell(){
    local shell="@shell.sourceforge.net:/home/frs/project/garuda-linux/"
    echo "${account}${shell}${project}"
}

make_torrent(){
    find ${src_dir} -type f -name "*.torrent" -delete

    if [[ -n $(find ${src_dir} -type f -name "*.iso") ]]; then
        isos=$(ls ${src_dir}/*.iso)
        for iso in ${isos}; do
            local seed=https://${host}/projects/garuda-linux/files/${project}/${iso##*/}
            local mktorrent_args=(-c "${torrent_meta}" -l ${piece_size} -a ${tracker_url} -w ${seed})
            ${verbose} && mktorrent_args+=(-v)
            msg2 "Creating (%s) ..." "${iso##*/}.torrent"
            mktorrent ${mktorrent_args[*]} -o ${isos}.torrent ${isos}
        done
    fi
}

prepare_transfer(){
    profile="$1"
    hidden="$2"
    edition=$(get_edition "${profile}")
    [[ -z ${project} ]] && project="$(get_project)"
    server=$(connect)

    webshell=$(connect_shell)
    htdocs="htdocs/${profile}"
    [[ ${extra} == 'false' ]] && _edition=("lite")
    [[ ${extra} == 'true' ]] && _edition=("ultimate")
    target_dir="${profile}/${_edition}/$(date +%y%m%d)"
    src_dir="${run_dir}/${_edition}/${target_dir}"

    ${hidden} && target_dir="${profile}/.${_edition}/$(date +%y%m%d)"
}

start_agent(){
    msg2 "Initializing SSH agent..."
    ssh-agent | sed 's/^echo/#echo/' > "$1"
    chmod 600 "$1"
    . "$1" > /dev/null
    ssh-add
}

ssh_add(){
    local ssh_env="$USER_HOME/.ssh/environment"

    if [ -f "${ssh_env}" ]; then
         . "${ssh_env}" > /dev/null
         ps -ef | grep ${SSH_AGENT_PID} | grep ssh-agent$ > /dev/null || {
            start_agent ${ssh_env};
        }
    else
        start_agent ${ssh_env};
    fi
}

sync_dir(){
    count=1
    max_count=10
    prepare_transfer "$1" "${hidden}"

    ${torrent} && make_torrent
    ${sign} && signiso "${src_dir}"
    ${ssh_agent} && ssh_add
    ${checksum} && checksumiso "${src_dir}"

    msg "Start upload [%s] to [%s] ..." "$1" "${project}"

    while [[ $count -le $max_count ]]; do
        rsync ${rsync_args[*]} --exclude '.latest*' --exclude 'index.html' --exclude 'links.txt' ${src_dir}/ ${server}/${target_dir}/
        if [[ $? != 0 ]]; then
            count=$(($count + 1))
            msg "Upload failed. retrying (%s/%s) ..." "$count" "$max_count"
            sleep 2
        else
            count=$(($max_count + 1))

            ${upd_homepage} && pull_hp_repo
            ${shell_upload} && upload_permalinks

            msg "Done upload [%s]" "$1"
            show_elapsed_time "${FUNCNAME}" "${timer_start}"
        fi
    done

}

upload_permalinks(){
    ## permalinks for full ISO
    if [[ -f "${src_dir}/.latest" ]]; then
        msg "Uploading permalinks ..."
        LATEST_ISO=$(sed -e 's/\"/\n/g' < "${src_dir}/.latest" | grep -Eo 'http.*iso$' -m1 | awk '{split($0,x,"/"); print x[6]}')
        PKGLIST="${LATEST_ISO/.iso/-pkgs.txt}"

        ## upload redirector files
        [[ -f "${src_dir}/.latest" ]] && sync_latest_html
        [[ -f "${src_dir}/.latest.php" ]] && sync_latest_php

        ## upload verification files, torrent and package list
        [[ -f "${src_dir}/${LATEST_ISO}.torrent" ]] && sync_latest_torrent
        [[ -f "${src_dir}/${LATEST_ISO}.sig" ]] && sync_latest_signature
        [[ -f "${src_dir}/${LATEST_ISO}.sha1" ]] && sync_latest_checksum_sha1
        [[ -f "${src_dir}/${LATEST_ISO}.sha256" ]] && sync_latest_checksum_sha256
        [[ -f "${src_dir}/${PKGLIST}" ]] && sync_latest_pkg_list
        
        ${upd_homepage} && upd_dl_checksum
    fi

    ## permalinks for minimal ISO
    if [[ -f "${src_dir}/.latest-minimal" ]]; then
        msg "Uploading permalinks (minimal) ..."
        MINIMAL="yes"
        LATEST_ISO=$(sed -e 's/\"/\n/g' < "${src_dir}/.latest-minimal" | grep -Eo 'http.*iso$' -m1 | awk '{split($0,x,"/"); print x[6]}')
        PKGLIST="${LATEST_ISO/.iso/-pkgs.txt}"

        ## upload redirector files
        [[ -f "${src_dir}/.latest-minimal" ]] && sync_latest_html
        [[ -f "${src_dir}/.latest-minimal.php" ]] && sync_latest_php

        ## upload verification files, torrent and package list
        [[ -f "${src_dir}/${LATEST_ISO}.torrent" ]] && sync_latest_torrent
        [[ -f "${src_dir}/${LATEST_ISO}.sig" ]] && sync_latest_signature
        [[ -f "${src_dir}/${LATEST_ISO}.sha1" ]] && sync_latest_checksum_sha1
        [[ -f "${src_dir}/${LATEST_ISO}.sha256" ]] && sync_latest_checksum_sha256
        [[ -f "${src_dir}/${PKGLIST}" ]] && sync_latest_pkg_list
        
        ${upd_homepage} && upd_dl_checksum_minimal
    fi

    ${upd_homepage} && upd_dl_version && push_hp_repo
}

sync_latest_pkg_list(){
    msg2 "Uploading package list ..."
    local pkglist="latest-pkgs.txt"
    [[ ${MINIMAL} == "yes" ]] && pkglist="latest-minimal-pkgs.txt"
    chmod g+w "${src_dir}/${PKGLIST}"
    scp -p "${src_dir}/${PKGLIST}" "${webshell}/${htdocs}/${pkglist}"
}

sync_latest_checksum_sha256(){
    msg2 "Uploading sha256 checksum file ..."
    local filename="${LATEST_ISO}.sha256"
    local checksum_file="latest.sha256"
    [[ ${MINIMAL} == "yes" ]] && checksum_file="latest-minimal.sha256"
    chmod g+w "${src_dir}/${filename}"
    scp -p "${src_dir}/${filename}" "${webshell}/${htdocs}/${checksum_file}"
}

sync_latest_checksum_sha1(){
    msg2 "Uploading sha1 checksum file ..."
    local filename="${LATEST_ISO}.sha1"
    local checksum_file="latest.sha1"
    [[ ${MINIMAL} == "yes" ]] && checksum_file="latest-minimal.sha1"
    chmod g+w "${src_dir}/${filename}"
    scp -p "${src_dir}/${filename}" "${webshell}/${htdocs}/${checksum_file}"
}

sync_latest_signature(){
    msg2 "Uploading signature file ..."
    local filename="${LATEST_ISO}.sig"
    local signature="latest.sig"
    [[ ${MINIMAL} == "yes" ]] && signature="latest-minimal.sig"
    chmod g+w "${src_dir}/${filename}"
    scp -p "${src_dir}/${filename}" "${webshell}/${htdocs}/${signature}"
}

sync_latest_torrent(){
    msg2 "Uploading torrent file ..."
    local filename="${LATEST_ISO}.torrent"
    local torrent="latest.torrent"
    [[ ${MINIMAL} == "yes" ]] && torrent="latest-minimal.torrent"
    chmod g+w "${src_dir}/${filename}"
    scp -p "${src_dir}/${filename}" "${webshell}/${htdocs}/${torrent}"
}

sync_latest_php(){
    msg2 "Uploading php redirector ..."
    local filename=".latest.php"
    local php="latest.php"
    [[ ${MINIMAL} == "yes" ]] && filename=".latest-minimal.php" && php="latest-minimal.php"
    chmod g+w "${src_dir}/${filename}"
    scp -p "${src_dir}/.${php}" "${webshell}/${htdocs}/${php}"
}

sync_latest_html(){
    msg2 "Uploading url redirector ..."
    local filename=".latest"
    local html="latest"
    [[ ${MINIMAL} == "yes" ]] && filename=".latest-minimal" && html="latest-minimal"
    chmod g+w "${src_dir}/${filename}"
    scp -p "${src_dir}/.${html}" "${webshell}/${htdocs}/${html}"
}

pull_hp_repo(){
    load_vars "$USER_HOME/.makepkg.conf" || load_vars /etc/makepkg.conf
    [[ -z $SRCDEST ]] && SRCDEST=${cache_dir}
    
    hp_repo=garuda-homepage
    dl_file="${SRCDEST}/${hp_repo}/site/content/downloads/${edition}/${profile}.md"

    cd "${SRCDEST}"
    if [[ ! -d "${hp_repo}" ]]; then
        msg "Cloning garuda.org"
        git clone "ssh://git@gitlab.garuda.org:22277/webpage/${hp_repo}.git"
    else
        cd "${hp_repo}"
        msg "Pulling garuda.org"
        git pull
    fi
}

push_hp_repo(){
    cd "${SRCDEST}/${hp_repo}"
    msg "Updating garuda.org"
    git add ${dl_file}
    git commit -m "update download ${profile}"
    git push
}

upd_dl_checksum(){
    local checksum=$(cat "${src_dir}/${LATEST_ISO}.sha1" | cut -d' ' -f1)
    msg "Updating download page:"
    msg2 "checksum > ${checksum}"
    sed -i "/Download_x64_Checksum/c\Download_x64_Checksum = \"${checksum}\"" ${dl_file}
}

upd_dl_checksum_minimal(){
    local checksum=$(cat "${src_dir}/${LATEST_ISO}.sha1" | cut -d' ' -f1)
    msg "Updating download page:"
    msg2 "checksum_minimal > ${checksum}"
    sed -i "/Download_Minimal_x64_Checksum/c\Download_Minimal_x64_Checksum = \"${checksum}\"" ${dl_file}
}

upd_dl_version(){
    timestamp=$(date -u +%Y-%m-%dT%T%Z)
    msg2 "Version > ${dist_release}"
    sed -i "/Version/c\Version = \"${dist_release}\"" ${dl_file}
    msg2 "date > ${timestamp}"
    sed -i "/date/c\date = \"${timestamp}\"" ${dl_file}
}
