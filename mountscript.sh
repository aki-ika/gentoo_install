#!/bin/bash

echo "Gentoo インストールの再開スクリプト"

# モード選択
select_mode() {
    PS3="スクリプトモードを選択してください (1: デスクトップ, 2: サーバ): "
    select mode in "desktop" "server"; do
        case $mode in
            desktop)
                suffix="desktop-systemd-mergedusr"
                break
                ;;
            server)
                suffix="systemd-mergeduser"
                break
                ;;
            *)
                echo "無効な選択です。再度選択してください。"
                ;;
        esac
    done
}

# パーティションのマウント
mount_partitions() {
    echo "ルートパーティションをマウントしています..."
    mkdir -p /mnt/gentoo
    mount "/dev/${disk}2" /mnt/gentoo

    echo "EFIシステムパーティションをマウントしています..."
    mkdir -p /mnt/gentoo/efi
    mount "/dev/${disk}${efi_partition_number}" /mnt/gentoo/efi

    if [ "$create_home_on_separate_disk" == "y" ]; then
        echo "ホームパーティションをマウントしています..."
        mkdir -p /mnt/gentoo/home
        mount "/dev/${home_disk}${home_partition_number}" /mnt/gentoo/home
    fi

    echo "マウントが完了しました。"
}

# chroot 内のスクリプト
chroot_script() {
    chroot /mnt/gentoo /bin/bash << 'EOF'
        source /etc/profile
        export PS1="(chroot) ${PS1}"
EOF
}

# ディスクのマウント
mount_partitions

# モード選択
select_mode

# make.conf ファイルの作成
echo "make.conf ファイルを作成しています..."
cp "make.conf.${mode}" /etc/portage/make.conf


mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# 必要なファイルシステムをマウントする

mount --types proc /proc /mnt/gentoo/proc 
mount --rbind /sys /mnt/gentoo/sys 
mount --make-rslave /mnt/gentoo/sys 
mount --rbind /dev /mnt/gentoo/dev 
mount --make-rslave /mnt/gentoo/dev 
mount --bind /run /mnt/gentoo/run 
mount --make-slave /mnt/gentoo/run 

test -L /dev/shm && rm /dev/shm && mkdir /dev/shm 
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm 
chmod 1777 /dev/shm /run/shm

chroot_script