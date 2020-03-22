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

load_compiler_settings(){
    local tarch="$1" conf
    conf=${make_conf_dir}/$tarch.conf

    [[ -f $conf ]] || return 1

    info "Loading compiler settings: %s" "$tarch"
    source $conf

    return 0
}

get_makepkg_conf(){
    local conf="${tmp_dir}/makepkg-$1.conf"

    cp "${DATADIR}/makepkg.conf" "$conf"

    load_compiler_settings "$1"

    sed -i "$conf" \
        -e "s|@CARCH[@]|$carch|g" \
        -e "s|@CHOST[@]|$chost|g" \
        -e "s|@CFLAGS[@]|$cflags|g"

    echo "$conf"
}

# $1: target_arch
prepare_conf(){
    if ! is_valid_arch_pkg "$1"; then
        die "%s is not a valid arch!" "$1"
    fi

    local pac_arch='default'

    if [[ "$1" == 'multilib' ]]; then
        pac_arch='multilib'
        is_multilib=true
    fi

    pacman_conf="${DATADIR}/pacman-$pac_arch.conf"

    work_dir="${chroots_pkg}/${target_branch}/$1"
    pkg_dir="${cache_dir_pkg}/${target_branch}/$1"

    makepkg_conf=$(get_makepkg_conf "$1")

    [[ "$pac_arch" == 'multilib' ]] && target_arch='x86_64'
}

check_build(){
    find_pkg $1
    [[ ! -f $1/PKGBUILD ]] && die "Directory must contain a PKGBUILD!"
}

find_pkg(){
    local result=$(find . -type d -name "$1")
    [[ -z $result ]] && die "%s is not a valid package or build list!" "$1"
}

init_base_devel(){
    if ${is_multilib}; then
        base_packages=('base-devel' 'multilib-devel')
    else
        base_packages=('base-devel')
    fi
}

chroot_create(){
    msg "Creating chroot for [%s] (%s)..." "${target_branch}" "${target_arch}"
    mkdir -p "${work_dir}"
    mkchroot_args+=(-L)
    setarch "${target_arch}" \
        mkchroot ${mkchroot_args[*]} \
        "${work_dir}/root" \
        ${base_packages[*]} || abort
}

chroot_clean(){
    msg "Cleaning chroot for [%s] (%s)..." "${target_branch}" "${target_arch}"
    for copy in "${work_dir}"/*; do
        [[ -d ${copy} ]] || continue
        msg2 "Deleting chroot copy %s ..." "$(basename "${copy}")"

        lock 9 "${copy}.lock" "Locking chroot copy '${copy}'"

        subvolume_delete_recursive "${copy}"
        rm -rf --one-file-system "${copy}"
    done
    exec 9>&-

    rm -rf --one-file-system "${work_dir}"
}

chroot_update(){
    msg "Updating chroot for [%s] (%s)..." "${target_branch}" "${target_arch}"
    chroot-run ${mkchroot_args[*]} \
            "${work_dir}/${OWNER}" \
            pacman -Syu --noconfirm || abort

}

clean_up(){
    msg "Cleaning up ..."
    msg2 "Cleaning [%s]" "${pkg_dir}"
    find ${pkg_dir} -maxdepth 1 -name "*.*" -delete #&> /dev/null
    if [[ -z $SRCDEST ]]; then
        msg2 "Cleaning [source files]"
        find $PWD -maxdepth 1 -name '*.?z?' -delete #&> /dev/null
    fi
}

sign_pkg(){
    su ${OWNER} -c "signfile ${pkg_dir}/$1"
}

move_to_cache(){
    local src="$1"
    [[ -n $PKGDEST ]] && src="$PKGDEST/$1"
    [[ ! -f $src ]] && die
    if [[ ${pkg_dir} != $PKGDEST ]]; then
        msg2 "Moving [%s] -> [%s]" "${src##*/}" "${pkg_dir}"
        mv $src ${pkg_dir}/
    fi
    ${sign} && sign_pkg "${src##*/}"
    user_own "${pkg_dir}" "-R"
}

archive_logs(){
    local archive name="$1" ext=log.tar.xz ver src=${tmp_dir}/archives.list target='.'
    ver=$(get_full_version "$name")
    archive="${name}-${ver}-${target_arch}"
    if [[ -n $LOGDEST ]]; then
            target=$LOGDEST
            find $target -maxdepth 1 -name "$archive*.log" -printf "%f\n" > $src
    else
            find $target -maxdepth 1 -name "$archive*.log" > $src
    fi
    msg2 "Archiving log files [%s] ..." "$archive.$ext"
    tar -cJf ${log_dir}/$archive.$ext  -C "$target" -T $src
    msg2 "Cleaning log files ..."

    find $target -maxdepth 1 -name "$archive*.log" -delete
}

post_build(){
    source PKGBUILD
    local ext='pkg.tar.zst' tarch ver src
    for pkg in ${pkgname[@]}; do
        case $arch in
            any) tarch='any' ;;
            *) tarch=${target_arch}
        esac
        local ver=$(get_full_version "$pkg") src
        src=$pkg-$ver-$tarch.$ext
        move_to_cache "$src"
    done
    local name=${pkgbase:-$pkgname}
    archive_logs "$name"
}

chroot_init(){
    local timer=$(get_timer)
    if ${clean_first} || [[ ! -d "${work_dir}" ]]; then
        chroot_clean
        chroot_create
    else
        chroot_update
    fi
    show_elapsed_time "${FUNCNAME}" "${timer}"
}

build_pkg(){
    setarch "${target_arch}" \
        mkchrootpkg ${mkchrootpkg_args[*]}
    post_build
}

make_pkg(){
    check_build "$1"
    msg "Start building [%s]" "$1"
    cd $1
        build_pkg
    cd ..
    msg "Finished building [%s]" "$1"
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
}

