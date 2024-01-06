#!/bin/bash

set -e

set_working_directory() {
    # どのディレクトリで作業するか入力させる
    read -p "作業ディレクトリを入力してください: " work_dir
    if [ -n "$work_dir" ]; then
        echo "作業ディレクトリ: $work_dir を作成します。"
        mkdir -p $work_dir
    else
        echo "無効な選択です。再度選択してください。"
    fi
}

#インストールするマシンがサーバかデスクトップかを選択
select_target_machine(){
    PS3="インストールするマシンを選択してください: "
    select mode in "server" "desktop"; do
        if [ -n "$mode" ]; then
            break
        else
            echo "無効な選択です。再度選択してください。"
        fi
    done
}

select_target_disk() {
    lsblk
    read -p "インストールするディスクを入力してください: " selected_disk
    if [ -n "$selected_disk" ]; then
        echo "選択されたディスク: $selected_disk"
    else
        echo "無効な選択です。再度選択してください。"
    fi
    # /homeを別ディスクにするかの確認
    read -p "ホームを別ディスクにしますか？:y/n " selected_home_divide
    if [ "$selected_home_divide" = "y" ]; then
        read -p "インストールするディスクを入力してください: " selected_home_disk
        if [ -n "$selected_home_disk" ]; then
            echo "選択されたディスク: $selected_home_disk"
        else
            echo "無効な選択です。再度選択してください。"
        fi
    else
        echo "ホームを別ディスクにしません。"
    fi
}

# パーティションを作成する
consent_disk_partition() {
    # 作成するディスクがあってるかの確認
    read -p "次のディスクはフォーマットされます。よろしいですか？: $selected_disk y/n" selected_disk_confirm
    if [ "$selected_disk_confirm" = "y" ]; then
        # ホームを別ディスクにしてる場合、それもフォーマットするかの確認
        if [ "$selected_home_divide" = "y" ]; then
            read -p "次のディスクもフォーマットされます。よろしいですか？: $selected_home_disk y/n" selected_home_disk_confirm
            if [ "$selected_home_disk_confirm" = "y" ]; then
                echo "パーティションの作成を行います"
            else 
                echo "インストールを終了します。"
                exit 1
            fi
        else
            echo "パーティションの作成を行います"
        fi
    else 
        echo "インストールを終了します。"
        exit 1
    fi
}

create_partition() {
    echo "パーティションを作成しています..."
    sgdisk -Z /dev/$selected_disk
    sgdisk -o /dev/$selected_disk
    sgdisk -n 1::+1024M -t 1:ef02 /dev/$selected_disk
    sgdisk -n 2:: -t 2:8300 /dev/$selected_disk

    if [[ "$selected_disk" == nvme* ]]; then
        mkfs.vfat -F 32 /dev/${selected_disk}p1
        mkfs.btrfs -f /dev/${selected_disk}p2
    else
        mkfs.vfat -F 32 /dev/${selected_disk}1
        mkfs.btrfs -f /dev/${selected_disk}2
    fi

    # /homeを別ディスクにする場合、それも作成する
    if [ "$selected_home_divide" = "y" ]; then
        sgdisk -Z /dev/$selected_home_disk
        sgdisk -o /dev/$selected_home_disk
        sgdisk -n 1:: -t 1:8300 /dev/$selected_home_disk
        mkfs.btrfs -f /dev/${selected_home_disk}1
        if [[ "$selected_disk" == nvme* ]]; then
            mkfs.btrfs -f /dev/${selected_disk}p1
        else
            mkfs.btrfs -f /dev/${selected_disk}1
        fi
    fi
}

# 作業ディレクトリを作成する
create_work_directory() {
    echo "作業ディレクトリを作成しています..."
    if ! mkdir -p ${work_dir}; then
        echo "Failed to create work directory. Exiting."
        exit 1
    fi
}

mount_disk_to_work_directory() {
    echo "ディスクをマウントしています..."
    if [[ "$selected_disk" == nvme* ]]; then
        mount /dev/${selected_disk}p2 ${work_dir}
        mkdir ${work_dir}/efi
        mount /dev/${selected_disk}p1 ${work_dir}/efi
    else
        mount /dev/${selected_disk}2 ${work_dir}
        mkdir ${work_dir}/efi
        mount /dev/${selected_disk}1 ${work_dir}/efi
    fi

    # /homeを別ディスクにする場合、それもマウントする
    if [ "$selected_home_divide" = "y" ]; then
        mkdir ${work_dir}/home
        mount /dev/${selected_home_disk}1 ${work_dir}/home
    fi
}

download_stage3_tarball() {
    if [ "$mode" == "server" ]; then
        wget -O index.html https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/current-stage3-amd64-systemd-mergedusr/
        tarball_name=$(grep -o 'stage3-amd64-systemd-mergedusr-[0-9]\+T[0-9]\+Z.tar.xz' index.html | grep -v '.asc' | tail -n 1)
        rm index.html
        wget https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/current-stage3-amd64-systemd-mergedusr/$tarball_name
        mv $tarball_name ${work_dir}
        cd ${work_dir}
        tar xpvf $tarball_name --xattrs-include='*.*' --numeric-owner
        cd -
    elif [ "$mode" == "desktop" ]; then
        wget -O index.html https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/current-stage3-amd64-desktop-systemd-mergedusr/
        tarball_name=$(grep -o 'stage3-amd64-desktop-systemd-mergedusr-[0-9]\+T[0-9]\+Z.tar.xz' index.html | grep -v '.asc' | tail -n 1)
        rm index.html
        wget https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/current-stage3-amd64-desktop-systemd-mergedusr/$tarball_name
        mv $tarball_name ${work_dir}
        cd ${work_dir}
        tar xpvf $tarball_name --xattrs-include='*.*' --numeric-owner
        cd -
    fi
}

generate_make_conf() {
    local base_conf="make.conf.base"
    local mode_conf="make.conf.${mode}"

    if [ ! -e "$base_conf" ]; then
        echo "Error: $base_conf not found."
        exit 1
    fi

    if [ ! -e "$mode_conf" ]; then
        echo "Error: $mode_conf not found."
        exit 1
    fi

    cat "$base_conf" <(echo) "$mode_conf" > merged_make.conf
    cp merged_make.conf $work_dir/etc/portage/make.conf

    rm merged_make.conf
}

prepare_chroot(){
    mkdir --parents $work_dir/etc/portage/repos.conf
    cp $work_dir/usr/share/portage/config/repos.conf $work_dir/etc/portage/repos.conf/gentoo.conf
    cp --dereference /etc/resolv.conf $work_dir/etc/
    mount --types proc /proc $work_dir/proc 
    mount --rbind /sys $work_dir/sys 
    mount --make-rslave $work_dir/sys 
    mount --rbind /dev $work_dir/dev 
    mount --make-rslave $work_dir/dev 
    mount --bind /run $work_dir/run 
    mount --make-slave $work_dir/run 
    test -L /dev/shm && rm /dev/shm && mkdir /dev/shm 
    mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm 
    # /run/shmが存在する場合は以下を実行
    if [ -L /run/shm ]; then
        chmod 1777 /dev/shm /run/shm
    fi
}

chroot_with_script() {
    cp chroot_script.sh $work_dir
    chroot $work_dir /bin/bash chroot_script.sh
}

umount_all() {
    echo "Unmounting all partitions..."
    umount -l $work_dir/dev{/shm,/pts,}
    umount -R $work_dir
}

reboot() {
read -p "Installation completed. Do you want to reboot? (y/n): " reboot_choice
if [ "$reboot_choice" == "y" ]; then
    echo "Rebooting system..."
    reboot
else
    echo "Exiting without rebooting."
fi
}

set_working_directory
select_target_machine
select_target_disk
consent_disk_partition
create_partition
create_work_directory
download_stage3_tarball
generate_make_conf
prepare_chroot
chroot_with_script
umount_all
reboot