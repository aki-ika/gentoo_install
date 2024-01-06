#!/bin/bash

set -e

prepare_installation() {
    echo "インストールの前準備を行います..."
    source /etc/profile
    export PS1="(chroot) ${PS1}"
}

sync_repositories() {
    echo "Gentoo リポジトリを同期しています..."
    if ! emerge-webrsync; then
        echo "Failed to sync web repository. Exiting."
        exit 1
    fi
    if ! emerge --sync; then
        echo "Failed to sync repository. Exiting."
        exit 1
    fi
}

select_profile() {
    eselect profile list
    echo "プロファイルを選択してください..."
    read -p "プロファイルを選択してください: " profile_number
    if [ -n "$profile_number" ]; then
        echo "選択されたプロファイル: $profile_number"
        if ! eselect profile set "$profile_number"; then
            echo "Failed to set profile. Exiting."
            exit 1
        fi
    else
        echo "無効な選択です。再度選択してください。"
    fi
}

update_world() {
    echo "ワールドを更新しています..."
    if ! emerge -atvUDN @world; then
        echo "Failed to update world. Exiting."
        exit 1
    fi
}

create_license_directory() {
    echo "ライセンスディレクトリを作成しています..."
    if ! mkdir /etc/portage/package.license; then
        echo "Failed to create license directory. Exiting."
        exit 1
    fi   
}

set_timezone() {
    echo "Setting timezone..."

    # Get list of timezones
    local timezones
    timezones=$(find /usr/share/zoneinfo -type f | cut -d/ -f5- | sort)

    # Let user select timezone
    PS3="Please select a timezone: "
    select timezone in $timezones; do
        if [ -n "$timezone" ]; then
            echo "Selected timezone: $timezone"
            if ! ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime; then
                echo "Failed to set timezone. Exiting."
                exit 1
            fi
            break
        else
            echo "Invalid selection. Please select again."
        fi
    done
}

edit_locale_gen() {
    echo "locale.gen ファイルを編集しています..."
    if ! echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen; then
        echo "Failed to edit locale.gen. Exiting."
        exit 1
    fi
    if ! echo "ja_JP.UTF-8 UTF-8" >> /etc/locale.gen; then
        echo "Failed to edit locale.gen. Exiting."
        exit 1
    fi
}

generate_locale() {
    echo "ロケールを生成しています..."
    locale-gen
    echo "環境変数を更新しています..."
    env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
}

install_linux_firmware() {
    echo "Linux firmware パッケージをインストールしています..."
    echo "sys-kernel/linux-firmware linux-fw-redistributable" >> /etc/portage/package.license/linux-firmware
    emerge --ask sys-kernel/linux-firmware
}


install_kernel() {
    echo "カーネルをインストールしています..."
    emerge --ask sys-kernel/gentoo-kernel-bin
}

crate_fstab () {
    echo "fstab ファイルを作成するためのパッケージをインストールしています..."
    emerge -a sys-fs/genfstab
    echo "fstab ファイルを作成しています..."
    emerge -a sys-fs/genfstab
    genfstab -U / > /etc/fstab
}

set_host () {
    echo "ホスト名を設定しています..."
    read -p "ホスト名を入力してください: " hostname
    echo "$hostname" > /etc/hostname
    echo "hosts ファイルを編集しています..."
    hosts_file="/etc/hosts"
    backup_file="${hosts_file}.bak"
    cp "$hosts_file" "$backup_file"
    sed -i "s/127.0.0.1\s*localhost/127.0.0.1     $hostname localhost/g" "$hosts_file"

    echo "hosts ファイルを変更しました。変更前のバックアップは $backup_file です。"
} 

set_root_password() {
    echo "root パスワードを設定しています..."
    passwd
}

install_bootloader() {
    echo "ブートローダーをインストールしています..."
    emerge --ask sys-boot/grub
    grub-install --target=x86_64-efi --efi-directory=/efi
    grub-mkconfig -o /boot/grub/grub.cfg
}

create_user() {
    read -p "ユーザ名を入力してください: " username
    useradd -m -G users,wheel,audio,video,input "$username"
    passwd "$username"
}

prepare_installation
sync_repositories
select_profile
update_world
create_license_directory
edit_locale_gen
generate_locale
install_linux_firmware
install_kernel
crate_fstab
set_host
set_root_password
install_bootloader
create_user
exit
