#!/bin/bash
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# $1: section
parse_section() {
    local is_section=0
    while read line; do
        [[ $line =~ ^\ {0,}# ]] && continue
        [[ -z "$line" ]] && continue
        if [ $is_section == 0 ]; then
            if [[ $line =~ ^\[.*?\] ]]; then
                line=${line:1:$((${#line}-2))}
                section=${line// /}
                if [[ $section == $1 ]]; then
                    is_section=1
                    continue
                fi
                continue
            fi
        elif [[ $line =~ ^\[.*?\] && $is_section == 1 ]]; then
            break
        else
            pc_key=${line%%=*}
            pc_key=${pc_key// /}
            pc_value=${line##*=}
            pc_value=${pc_value## }
            eval "$pc_key='$pc_value'"
        fi
    done < "$2"
}

get_repos() {
    local section repos=() filter='^\ {0,}#'
    while read line; do
        [[ $line =~ "${filter}" ]] && continue
        [[ -z "$line" ]] && continue
        if [[ $line =~ ^\[.*?\] ]]; then
            line=${line:1:$((${#line}-2))}
            section=${line// /}
            case ${section} in
                "options") continue ;;
                *) repos+=("${section}") ;;
            esac
        fi
    done < "$1"
    echo ${repos[@]}
}

check_user_repos_conf(){
    local repositories=$(get_repos "$1") uri='file://'
    for repo in ${repositories[@]}; do
        msg2 "parsing repo [%s] ..." "${repo}"
        parse_section "${repo}" "$1"
        [[ ${pc_value} == $uri* ]] && die "Using local repositories is not supported!"
    done
}

get_pac_mirrors_conf(){
    local conf="$tmp_dir/pacman-mirrors-$1.conf"
    cp "${DATADIR}/pacman-mirrors.conf" "$conf"
    sed -i "$conf" \
        -e "s|Branch = archlinux|Branch = $1|"

    echo "$conf"
}

read_build_list(){
    local _space="s| ||g" \
        _clean=':a;N;$!ba;s/\n/ /g' \
        _com_rm="s|#.*||g"

    build_list=$(sed "$_com_rm" "$1.list" \
        | sed "$_space" \
        | sed "$_clean")
}

# $1: list_dir
show_build_lists(){
    local list temp
    for item in $(ls $1/*.list); do
        temp=${item##*/}
        list=${list:-}${list:+|}${temp%.list}
    done
    echo $list
}

# $1: make_conf_dir
show_build_profiles(){
    local cpuarch temp
    for item in $(ls $1/*.conf); do
        temp=${item##*/}
        cpuarch=${cpuarch:-}${cpuarch:+|}${temp%.conf}
    done
    echo $cpuarch
}

# $1: list_dir
# $2: build list
eval_build_list(){
    eval "case $2 in
        $(show_build_lists $1)) is_build_list=true; read_build_list $1/$2 ;;
        *) is_build_list=false ;;
    esac"
}

in_array() {
    local needle=$1; shift
    local item
    for item in "$@"; do
        [[ $item = $needle ]] && return 0 # Found
    done
    return 1 # Not Found
}

get_timer(){
    echo $(date +%s)
}


# $1: start timer
elapsed_time(){
    echo $(echo $1 $(get_timer) | awk '{ printf "%0.2f",($2-$1)/60 }')
}

show_elapsed_time(){
    info "Time %s: %s minutes" "$1" "$(elapsed_time $2)"
}

lock() {
    eval "exec $1>"'"$2"'
    if ! flock -n $1; then
        stat_busy "$3"
        flock $1
        stat_done
    fi
}

slock() {
    eval "exec $1>"'"$2"'
    if ! flock -sn $1; then
        stat_busy "$3"
        flock -s $1
        stat_done
    fi
}

check_root() {
    (( EUID == 0 )) && return
    if type -P sudo >/dev/null; then
        exec sudo -- "$@"
    else
        exec su root -c "$(printf ' %q' "$@")"
    fi
}

copy_mirrorlist(){
    cp -a /etc/pacman.d/mirrorlist "$1/etc/pacman.d/"
    cp -a /etc/pacman.d/chaotic-mirrorlist "$1/etc/pacman.d/"

    if [[ -d /etc/pacman.d/blackarch-mirrorlist ]] && [[ ! -d $1/etc/pacman.d/blackarch-mirrorlist ]]; then
        cp -a /etc/pacman.d/blackarch-mirrorlist "$1/etc/pacman.d/"
    fi

}

copy_keyring(){
    if [[ -d /etc/pacman.d/gnupg ]] && [[ ! -d $1/etc/pacman.d/gnupg ]]; then
        cp -a /etc/pacman.d/gnupg "$1/etc/pacman.d/"
    fi
}

load_vars() {
    local var

    [[ -f $1 ]] || return 1

    for var in {SRC,SRCPKG,PKG,LOG}DEST MAKEFLAGS PACKAGER CARCH GPGKEY; do
        [[ -z ${!var} ]] && eval $(grep -a "^${var}=" "$1")
    done

    return 0
}

prepare_dir(){
    if [[ ! -d $1 ]]; then
        mkdir -p $1
    fi
}

# $1: chroot
get_branch(){
    echo $(cat "$1/etc/pacman-mirrors.conf" | grep '^Branch = ' | sed 's/Branch = \s*//g')
}

# $1: chroot
# $2: branch
set_branch(){
    if [[ $1 =~ "rootfs" ]]; then
        info "Setting mirrorlist branch: %s" "$2"
        sed -e "s|/archlinux|/$2|g" -i "$1/etc/pacman.d/mirrorlist"
    fi
}

init_common(){
    [[ -z ${target_branch} ]] && target_branch='archlinux'

    [[ -z ${target_arch} ]] && target_arch=$(uname -m)

    [[ -z ${cache_dir} ]] && cache_dir='/var/cache/garuda-tools/garuda-builds'

    [[ -z ${chroots_dir} ]] && chroots_dir='/var/cache/garuda-tools/garuda-chroots'

    [[ -z ${log_dir} ]] && log_dir='/var/cache/garuda-tools/garuda-logs'

    [[ -z ${build_mirror} ]] && build_mirror='http://mirrors.kernel.org'

    [[ -z ${tmp_dir} ]] && tmp_dir='/tmp/garuda-tools'
}

init_buildtree(){
    tree_dir=${cache_dir}/pkgtree

    tree_dir_abs=${tree_dir}/packages-archlinux

    [[ -z ${repo_tree[@]} ]] && repo_tree=('core' 'extra' 'community' 'multilib')

    [[ -z ${host_tree} ]] && host_tree='https://gitlab.com/garuda-linux'

    [[ -z ${host_tree_abs} ]] && host_tree_abs='https://projects.archlinux.org/git/svntogit'
}

init_buildpkg(){
    chroots_pkg="${chroots_dir}/buildpkg"

    list_dir_pkg="${SYSCONFDIR}/pkg.list.d"

    make_conf_dir="${SYSCONFDIR}/make.conf.d"

    [[ -d ${USERCONFDIR}/pkg.list.d ]] && list_dir_pkg=${USERCONFDIR}/pkg.list.d

    [[ -z ${build_list_pkg} ]] && build_list_pkg='default'

    cache_dir_pkg=${cache_dir}/pkg
}

get_iso_label(){
    local label="$1"
    #label="${label//_}"	# relace all _
    label="${label//-}"	# relace all -
    label="${label^^}"		# all uppercase
    label="${label::32}"	# limit to 32 characters
    echo ${label}
}

get_codename(){
    source /etc/lsb-release
    echo "${DISTRIB_CODENAME}"
}

get_release(){
    source /etc/lsb-release
    echo "${DISTRIB_RELEASE}"
}

get_distname(){
    source /etc/lsb-release
    echo "${DISTRIB_ID%Linux}"
}

get_distid(){
    source /etc/lsb-release
    echo "${DISTRIB_ID}"
}

get_disturl(){
    source /usr/lib/os-release
    echo "${HOME_URL}"
}

get_osname(){
    source /usr/lib/os-release
    echo "${NAME}"
}

get_osid(){
    source /usr/lib/os-release
    echo "${ID}"
}

init_buildiso(){
    chroots_iso="${chroots_dir}/buildiso"

    list_dir_iso="${SYSCONFDIR}/iso.list.d"

    [[ -d ${USERCONFDIR}/iso.list.d ]] && list_dir_iso=${USERCONFDIR}/iso.list.d

    [[ -z ${build_list_iso} ]] && build_list_iso='default'

    cache_dir_iso="${cache_dir}/iso"

    profile_repo='iso-profiles'

    ##### iso settings #####

    [[ -z ${dist_timestamp} ]] && dist_timestamp="$(date +%y%m%d)"

    [[ -z ${dist_release} ]] && dist_release=$(get_release)

    [[ -z ${dist_codename} ]] && dist_codename=$(get_codename)

    dist_name=$(get_distname)

    iso_name=$(get_osid)

    [[ -z ${dist_branding} ]] && dist_branding="garuda"

    [[ -z ${iso_compression} ]] && iso_compression='xz'

    [[ -z ${kernel} ]] && kernel="linux-zen"

    load_run_dir "${profile_repo}"

    if [[ -d ${run_dir}/.git ]]; then
    	current_path=$(pwd)
    	cd ${run_dir}
    	branch=$(git rev-parse --abbrev-ref HEAD)
    	cd ${current_path}
    else
    	[[ -z ${branch} ]] && branch="master" #current branch release
    fi

    [[ -z ${gpgkey} ]] && gpgkey=''

    mhwd_repo="/opt/ght/pkg"
}

init_calamares(){

	[[ -z ${welcomestyle} ]] && welcomestyle=false

	[[ -z ${welcomelogo} ]] && welcomelogo=true

	[[ -z ${windowexp} ]] && windowexp=noexpand

	[[ -z ${windowsize} ]] && windowsize="910px,664px"

	[[ -z ${windowplacement} ]] && windowplacement="center"

	[[ -z ${sidebarbackground} ]] && sidebarbackground=#5c0285

	[[ -z ${sidebartext} ]] &&  sidebartext=#efefef

	[[ -z ${sidebartextcurrent} ]] && sidebartextcurrent=#efefef

	[[ -z ${sidebarbackgroundcurrent} ]] && sidebarbackgroundcurrent=#7f03b8
}


init_deployiso(){

    host="sourceforge.net"

    [[ -z ${account} ]] && account="[SetUser]"

    [[ -z ${alt_storage} ]] && alt_storage=false

    [[ -z ${tracker_url} ]] && tracker_url='udp://lonewolf-builder.duckdns.org:23069'

    [[ -z ${piece_size} ]] && piece_size=21

    torrent_meta="$(get_distid)"
}

load_config(){

    [[ -f $1 ]] || return 1

    garuda_tools_conf="$1"

    [[ -r ${garuda_tools_conf} ]] && source ${garuda_tools_conf}

    init_common

    init_buildtree

    init_buildpkg

    init_buildiso

    init_calamares

    init_deployiso

    return 0
}

load_profile_config(){

    [[ -f $1 ]] || return 1

    profile_conf="$1"

    [[ -r ${profile_conf} ]] && source ${profile_conf}

    [[ -z ${displaymanager} ]] && displaymanager="none"

    [[ -z ${autologin} ]] && autologin="true"
    [[ ${displaymanager} == 'none' ]] && autologin="false"

    [[ -z ${snap_channel} ]] && snap_channel="stable"

    [[ -z ${multilib} ]] && multilib="true"

    [[ -z ${plymouth_boot} ]] && plymouth_boot="true"

    [[ -z ${nonfree_mhwd} ]] && nonfree_mhwd="true"

    [[ -z ${efi_boot_loader} ]] && efi_boot_loader="grub"

    [[ -z ${hostname} ]] && hostname="garuda"

    [[ -z ${username} ]] && username="garuda"

    [[ -z ${use_dracut} ]] && use_dracut="true"

    [[ -z ${plymouth_theme} ]] && plymouth_theme="garuda"

    [[ -z ${password} ]] && password="garuda"

    [[ -z ${user_shell} ]] && user_shell='/bin/zsh'

    [[ -z ${login_shell} ]] && login_shell='/bin/zsh'

    if [[ -z ${addgroups} ]]; then
        addgroups="lp,network,power,sys,wheel"
    fi

    if [[ -z ${enable_systemd[@]} ]]; then
        enable_systemd=('avahi-daemon' 'bluetooth' 'cronie' 'ModemManager' 'NetworkManager' 'cups' 'systemd-timesyncd')
    fi

    [[ -z ${disable_systemd[@]} ]] && disable_systemd=('pacman-init')

    if [[ -z ${enable_systemd_live[@]} ]]; then
        enable_systemd_live=('garuda-live' 'ght-live' 'pacman-init' 'mirrors-live')
    fi

    if [[ ${displaymanager} != "none" ]]; then
        enable_systemd+=("${displaymanager}")
    fi

    [[ -z ${needs_internet} ]] && needs_internet='false'
    [[ -z ${netinstall} ]] && netinstall='false'
    [[ -z ${netinstall_label} ]] && netinstall_label='Package selection'

    [[ -z ${zfs_used} ]] && zfs_used='false'

    [[ -z ${mhwd_used} ]] && mhwd_used='true'

    [[ -z ${oem_used} ]] && oem_used='false'

    [[ -z ${chrootcfg} ]] && chrootcfg='false'

    netgroups="https://gitlab.com/garuda-linux/packages/pkgbuilds/garuda-pkgbuilds/-/raw/master/pkgbuilds/calamares-netinstall-settings/netinstall-software.yaml"

    [[ -z ${geoip} ]] && geoip='true'

    [[ -z ${smb_workgroup} ]] && smb_workgroup=''

    [[ -z ${extra} ]] && extra='true'
    [[ ${full_iso} ]] && extra='true'

    basic='true'
    [[ ${extra} == 'true' ]] && basic='false'

    return 0
}

get_edition(){
    local result=$(find ${run_dir} -maxdepth 2 -name "$1") path
    [[ -z $result ]] && die "%s is not a valid profile or build list!" "$1"
    path=${result%/*}
    echo ${path##*/}
}

get_project(){
    case "${edition}" in
        'garuda')
            project="garuda"
        ;;
        'garuda-wm')
            project="garuda-wm"
        ;;
    esac
    echo "${project}"
}

reset_profile(){
    unset displaymanager
    unset strict_snaps
    unset classic_snaps
    unset snap_channel
    unset autologin
    unset multilib
    unset nonfree_mhwd
    unset efi_boot_loader
    unset hostname
    unset username
    unset password
    unset addgroups
    unset enable_systemd
    unset disable_systemd
    unset enable_systemd_live
    unset disable_systemd_live
    unset packages_desktop
    unset packages_desktop_common
    unset packages_mhwd
    unset user_shell
    unset login_shell
    unset netinstall
    unset chrootcfg
    unset geoip
    unset plymouth_boot
    unset plymouth_theme
    unset extra
    unset full_iso
}

check_profile(){
    local keyfiles=("$1/Packages-Root"
            "$1/Packages-Live")

    local keydirs=("$1/root-overlay"
            "$1/live-overlay")

    local has_keyfiles=false has_keydirs=false
    for f in ${keyfiles[@]}; do
        if [[ -f $f ]]; then
            has_keyfiles=true
        else
            has_keyfiles=false
            break
        fi
    done
    for d in ${keydirs[@]}; do
        if [[ -d $d ]]; then
            has_keydirs=true
        else
            has_keydirs=false
            break
        fi
    done
    if ! ${has_keyfiles} && ! ${has_keydirs}; then
        die "Profile [%s] sanity check failed!" "$1"
    fi

    [[ -f "$1/Packages-Desktop" ]] && packages_desktop=$1/Packages-Desktop
    [[ -f "$1/Packages-Desktop-Common" ]] && packages_desktop_common=$1/Packages-Desktop-Common

    [[ -f "$1/Packages-Mhwd" ]] && packages_mhwd=$1/Packages-Mhwd

    if ! ${netinstall}; then
        chrootcfg="false"
    fi
}

# $1: file name
# $2: append, default: false
load_pkgs(){
    info "Loading Packages: [%s] ..." "${1##*/}"

    local _multi _nonfree_default _nonfree_multi _arch _arch_rm _nonfree_i686 _nonfree_x86_64 _basic _basic_rm _extra _extra_rm

    if ${basic}; then
        _basic="s|>basic||g"
    else
        _basic_rm="s|>basic.*||g"
    fi

    if ${extra}; then
        _extra="s|>extra||g"
    else
        _extra_rm="s|>extra.*||g"
    fi

    case "${target_arch}" in
        "i686")
            _arch="s|>i686||g"
            _arch_rm="s|>x86_64.*||g"
            _multi="s|>multilib.*||g"
            _nonfree_multi="s|>nonfree_multilib.*||g"
            _nonfree_x86_64="s|>nonfree_x86_64.*||g"
            if ${nonfree_mhwd}; then
                _nonfree_default="s|>nonfree_default||g"
                _nonfree_i686="s|>nonfree_i686||g"

            else
                _nonfree_default="s|>nonfree_default.*||g"
                _nonfree_i686="s|>nonfree_i686.*||g"
            fi
        ;;
        *)
            _arch="s|>x86_64||g"
            _arch_rm="s|>i686.*||g"
            _nonfree_i686="s|>nonfree_i686.*||g"
            if ${multilib}; then
                _multi="s|>multilib||g"
                if ${nonfree_mhwd}; then
                    _nonfree_default="s|>nonfree_default||g"
                    _nonfree_x86_64="s|>nonfree_x86_64||g"
                    _nonfree_multi="s|>nonfree_multilib||g"
                else
                    _nonfree_default="s|>nonfree_default.*||g"
                    _nonfree_multi="s|>nonfree_multilib.*||g"
                    _nonfree_x86_64="s|>nonfree_x86_64.*||g"
                fi
            else
                _multi="s|>multilib.*||g"
                if ${nonfree_mhwd}; then
                    _nonfree_default="s|>nonfree_default||g"
                    _nonfree_x86_64="s|>nonfree_x86_64||g"
                    _nonfree_multi="s|>nonfree_multilib.*||g"
                else
                    _nonfree_default="s|>nonfree_default.*||g"
                    _nonfree_x86_64="s|>nonfree_x86_64.*||g"
                    _nonfree_multi="s|>nonfree_multilib.*||g"
                fi
            fi
        ;;
    esac

# We can reuse this code
    local _edition _edition_rm
    case "${edition}" in
        'sonar')
            _edition="s|>sonar||g"
            _edition_rm="s|>garuda.*||g"
        ;;
        *)
            _edition="s|>garuda||g"
            _edition_rm="s|>sonar.*||g"
        ;;
    esac

    local _blacklist="s|>blacklist.*||g" \
        _kernel="s|KERNEL|$kernel|g" \
        _used_kernel=${kernel:5:2} \
        _space="s| ||g" \
        _clean=':a;N;$!ba;s/\n/ /g' \
        _com_rm="s|#.*||g" \
        _purge="s|>cleanup.*||g" \
        _purge_rm="s|>cleanup||g"

    local pkgs=$(sed "$_com_rm" "$1" \
            | sed "$_space" \
            | sed "$_blacklist" \
            | sed "$_purge" \
            | sed "$_arch" \
            | sed "$_arch_rm" \
            | sed "$_nonfree_default" \
            | sed "$_multi" \
            | sed "$_nonfree_i686" \
            | sed "$_nonfree_x86_64" \
            | sed "$_nonfree_multi" \
            | sed "$_kernel" \
            | sed "$_edition" \
            | sed "$_edition_rm" \
            | sed "$_basic" \
            | sed "$_basic_rm" \
            | sed "$_extra" \
            | sed "$_extra_rm" \
            | sed "$_clean")

    if [[ "$2" == "true" ]]; then
        packages="$packages $pkgs"
    else
        packages="$pkgs"
    fi

    if [[ $1 == "${packages_mhwd}" ]]; then

        [[ ${_used_kernel} < "42" ]] && local _amd="s|xf86-video-amdgpu||g"

        packages_cleanup=$(sed "$_com_rm" "$1" \
            | grep cleanup \
            | sed "$_purge_rm" \
            | sed "$_kernel" \
            | sed "$_clean" \
            | sed "$_amd")
    fi
}

user_own(){
    local flag=$2
    chown ${flag} "${OWNER}:$(id --group ${OWNER})" "$1"
}

clean_dir(){
    if [[ -d $1 ]]; then
        msg "Cleaning [%s] ..." "$1"
        rm -r $1/*
    fi
}

write_repo_conf(){
    local repos=$(find $USER_HOME -type f -name "repo_info")
    local path name
    _workdir='/var/cache/garuda-tools'
    [[ -z ${repos[@]} ]] && run_dir=${_workdir}/iso-profiles && return 1
    for r in ${repos[@]}; do
        path=${r%/repo_info}
        name=${path##*/}
        echo "run_dir=$path" > ${USERCONFDIR}/$name.conf
    done
}

load_user_info(){
    OWNER=${SUDO_USER:-$USER}

    if [[ -n $SUDO_USER ]]; then
        eval "USER_HOME=~$SUDO_USER"
    else
        USER_HOME=$HOME
    fi

    USERCONFDIR="$USER_HOME/.config/garuda-tools"
    prepare_dir "${USERCONFDIR}"
}

load_run_dir(){
    [[ -f ${USERCONFDIR}/$1.conf ]] || write_repo_conf
    [[ -r ${USERCONFDIR}/$1.conf ]] && source ${USERCONFDIR}/$1.conf
    return 0
}

show_version(){
    msg "garuda-tools"
    msg2 "version: %s" "${version}"
}

show_config(){
    if [[ -f ${USERCONFDIR}/garuda-tools.conf ]]; then
        msg2 "config: %s" "~/.config/garuda-tools/garuda-tools.conf"
    else
        msg2 "config: %s" "${garuda_tools_conf}"
    fi
}

# $1: chroot
kill_chroot_process(){
    # enable to have more debug info
    #msg "machine-id (etc): $(cat $1/etc/machine-id)"
    #[[ -e $1/var/lib/dbus/machine-id ]] && msg "machine-id (lib): $(cat $1/var/lib/dbus/machine-id)"
    #msg "running processes: "
    #lsof | grep $1

    local prefix="$1" flink pid name
    for root_dir in /proc/*/root; do
        flink=$(readlink $root_dir)
        if [ "x$flink" != "x" ]; then
            if [ "x${flink:0:${#prefix}}" = "x$prefix" ]; then
                # this process is in the chroot...
                pid=$(basename $(dirname "$root_dir"))
                name=$(ps -p $pid -o comm=)
                info "Killing chroot process: %s (%s)" "$name" "$pid"
                kill -9 "$pid"
            fi
        fi
    done
}

create_min_fs(){
    msg "Creating install root at %s" "$1"
    mkdir -m 0755 -p $1/var/{cache/pacman/pkg,lib/pacman,log} $1/{dev,run,etc}
    mkdir -m 1777 -p $1/tmp
    mkdir -m 0555 -p $1/{sys,proc}
}

is_valid_arch_pkg(){
    eval "case $1 in
        $(show_build_profiles "${make_conf_dir}")) return 0 ;;
        *) return 1 ;;
    esac"
}

is_valid_arch_iso(){
    case $1 in
        'i686'|'x86_64') return 0 ;;
        *) return 1 ;;
    esac
}

is_valid_branch(){
    case $1 in
        'stable'|'stable-staging'|'testing'|'unstable'|'archlinux') return 0 ;;
        *) return 1 ;;
    esac
}

is_valid_comp(){
    case $1 in
        'gzip'|'lzma'|'lz4'|'lzo'|'xz'|'zstd') return 0 ;;
        *) return 1 ;;
    esac
}

run(){
    if ${is_build_list}; then
        for item in ${build_list[@]}; do
            $1 $item
        done
    else
        $1 $2
    fi
}

is_btrfs() {
    [[ -e "$1" && "$(stat -f -c %T "$1")" == btrfs ]]
}

subvolume_delete_recursive() {
    local subvol

    is_btrfs "$1" || return 0

    while IFS= read -d $'\0' -r subvol; do
        if ! btrfs subvolume delete "$subvol" &>/dev/null; then
            error "Unable to delete subvolume %s" "$subvol"
            return 1
        fi
    done < <(find "$1" -xdev -depth -inum 256 -print0)

    return 0
}

create_chksums() {
    msg2 "creating checksums for [$1]"
    sha1sum $1 > $1.sha1
    sha256sum $1 > $1.sha256
}

init_profiles() {
	_workdir='/var/cache/garuda-tools'
	if [[ -d ${_workdir}/iso-profiles ]]; then
		rm -Rf ${_workdir}/iso-profiles
	fi
	git clone -q --depth 1 -b ${branch} https://gitlab.com/garuda-linux/tools/iso-profiles.git ${_workdir}/iso-profiles/

	#Check if git clone is done
	if [[ -d ${_workdir}/iso-profiles/garuda ]] || [[ -d ${_workdir}/iso-profiles/community ]]; then

		for i in ${_workdir}/iso-profiles/.gitignore ${_workdir}/iso-profiles/README.md; do
		rm -f $i
		done

		for i in ${_workdir}/iso-profiles/.git ${_workdir}/iso-profiles/sonar; do
			rm -Rf $i
		done
	else msg2 "Impossible to initialize iso-profiles, please check internet connection or browse at 'https://gitlab.com/garuda-linux/tools/iso-profiles'"
	exit 1
	fi
}
