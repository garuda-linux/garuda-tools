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

sync_tree(){
    local master=$(git log --pretty=%H ...refs/heads/master^ | head -n 1) \
        master_remote=$(git ls-remote origin -h refs/heads/master | cut -f1) \
        timer=$(get_timer)
    msg "Checking [%s] ..." "$1"
    msg2 "local: %s" "${master}"
    msg2 "remote: %s" "${master_remote}"
    if [[ "${master}" == "${master_remote}" ]]; then
        info "nothing to do"
    else
        info "needs sync"
        git pull origin master
    fi
    msg "Done [%s]" "$1"
    show_elapsed_time "${FUNCNAME}" "${timer}"
}

clone_tree(){
    local timer=$(get_timer)
    msg "Preparing [%s] ..." "$1"
    info "clone"
    git clone $2.git
    msg "Done [%s]" "$1"
    show_elapsed_time "${FUNCNAME}" "${timer}"
}

sync_tree_garuda(){
    cd ${tree_dir}
        for repo in ${repo_tree[@]}; do
            if [[ -d packages-${repo} ]]; then
                cd packages-${repo}
                    sync_tree "${repo}"
                cd ..
            else
                clone_tree "${repo}" "${host_tree}/packages-${repo}"
            fi
        done
    cd ..
}

sync_tree_abs(){
    local repo_tree_abs=('packages' 'community')
    cd ${tree_dir_abs}
        for repo in ${repo_tree_abs[@]}; do
            if [[ -d ${repo} ]]; then
                cd ${repo}
                    sync_tree "${repo}"
                cd ..
            else
                clone_tree "${repo}" "${host_tree_abs}/${repo}"
            fi
        done
    cd ..
}
