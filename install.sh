#!/bin/bash

set -e

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

# ディスク選択
select_disk() {
    local available_disks
    available_disks=$(lsblk -d -o NAME,SIZE -n | awk '{print $1}')
    PS3="パーティションを切るディスクを選択してください: "
    select disk in $available_disks; do
        if [ -n "$disk" ]; then
            echo "選択されたディスク: $disk"
            break
        else
            echo "無効な選択です。再度選択してください。"
        fi
    done
}

# EFIパーティションの作成
create_efi_partition() {
    local efi_size efi_partition_number
    echo "EFIシステムパーティションのサイズを指定してください (例: 512M): "
    read efi_size

    echo "EFIシステムパーティションのパーティション番号を指定してください (例: 1): "
    read efi_partition_number

    # パーティションの作成前に確認メッセージを表示
    echo "以下のパーティションを作成します:"
    echo "1. EFIシステムパーティション: /dev/${disk}1 (サイズ: $efi_size)"
    echo "2. ルートパーティション: /dev/${disk}2 (残りの領域)"

    read -p "本当に続行しますか？ (y/n): " confirmation
    if [ "$confirmation" != "y" ]; then
        echo "作業がキャンセルされました。"
        exit 1
    fi

    parted -s "/dev/$disk" mklabel gpt
    parted -s "/dev/$disk" mkpart primary fat32 1M "$efi_size"
    parted -s "/dev/$disk" mkpart primary btrfs "$efi_size" 100%

    mkfs.vfat -F 32 "/dev/${disk}${efi_partition_number}"
}

# 別ディスクに /home パーティションを作成
create_home_partition() {
    local home_disk home_partition_number
    echo "利用可能なディスクリスト: $available_disks"
    read -p "別ディスクとして使用するディスクを選択してください: " home_disk
    echo "別ディスクの /home パーティションのパーティション番号を指定してください (例: 1): "
    read home_partition_number

    # パーティションの作成前に確認メッセージを表示
    echo "以下のパーティションを作成します:"
    echo "3. /home パーティション: /dev/${home_disk}1"

    read -p "本当に続行しますか？ (y/n): " confirmation
    if [ "$confirmation" != "y" ]; then
        echo "作業がキャンセルされました。"
        exit 1
    fi

    mkfs.btrfs -f "/dev/${home_disk}${home_partition_number}"
    echo "別ディスクに /home パーティションを作成しました。"
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

# chroot 内のスクリプトを実行
chroot_script() {
    chroot /mnt/gentoo /bin/bash /chroot_script.sh
}


merge_make_conf() {
    local base_conf="make.conf.base"
    local mode_conf="make.conf.${mode}"

    # ベースの make.conf が存在するか確認
    if [ ! -e "$base_conf" ]; then
        echo "エラー: $base_conf が見つかりません。"
        exit 1
    fi

    # モードの make.conf が存在するか確認
    if [ ! -e "$mode_conf" ]; then
        echo "エラー: $mode_conf が見つかりません。"
        exit 1
    fi

    # マージした make.conf を作成
    cat "$base_conf" "$mode_conf" > merged_make.conf

    # /mnt/gentoo にコピー
    cp merged_make.conf /mnt/gentoo/etc/portage/make.conf

    # 一時ファイルを削除
    rm merged_make.conf
}

# インストールの前準備
pre_install

# モード選択
select_mode

# ディスク選択
select_disk

# EFIパーティションの作成
create_efi_partition

# 別ディスクに /home パーティションを作成するか確認
read -p "別ディスクに /home パーティションを作成しますか？ (y/n): " create_home_on_separate_disk
if [ "$create_home_on_separate_disk" == "y" ]; then
    create_home_partition
fi

# パーティションのマウント
mount_partitions

# make.conf を /mnt/gentoo にコピー
merge_make_conf

# chroot 内のスクリプトを実行
chroot_script

# インストールの後処理
echo "インストールが完了しました。"

# ユーザにrebootの選択を促す
read -p "インストールが完了しました。再起動しますか？ (y/n): " reboot_choice
if [ "$reboot_choice" == "y" ]; then
    echo "システムを再起動しています..."
    reboot
else
    echo "再起動せずに終了します。"
fi
