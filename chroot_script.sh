#!/bin/bash

set -e

# chroot 内のスクリプトの内容
# インストールの前準備
echo "インストールの前準備を行います..."
source /etc/profile
export PS1="(chroot) ${PS1}"

# Gentoo リポジトリの同期
echo "Gentoo リポジトリを同期しています..."
emerge-webrsync
emerge --sync

# 有効なプロファイルのリストを取得
echo "有効なプロファイルのリストを取得しています..."
profile_list=$(eselect profile list)

# プロファイルの選択
PS3="プロファイルを選択してください: "
select selected_profile in $profile_list; do
    if [ -n "$selected_profile" ]; then
        echo "選択されたプロファイル: $selected_profile"
        break
    else
        echo "無効な選択です。再度選択してください。"
    fi
done

# ワールドの更新
echo "ワールドを更新しています..."
emerge -atvUDN @world

# パッケージライセンスの設定
echo "パッケージライセンスの設定を行います..."
mkdir /etc/portage/package.license

# /etc/locale.gen ファイルの編集
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ja_JP.UTF-8 UTF-8" >> /etc/locale.gen

# 変更後の /etc/locale.gen ファイルの内容表示
echo "変更後の /etc/locale.gen ファイルの内容:"
cat /etc/locale.gen

# locale.gen ファイルの変更が完了
echo "locale.gen ファイルの変更が完了しました。"
locale-gen
echo "locale-gen が完了しました。"
echo "環境変数を更新しています..."
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

# Linux firmware パッケージのインストール
echo "Linux firmware パッケージをインストールしています..."
echo "sys-kernel/linux-firmware linux-fw-redistributable" >> /etc/portage/package.license/linux-firmware
emerge --ask sys-kernel/linux-firmware

# カーネルのインストール
echo "カーネルをインストールしています..."
emerge --prune sys-kernel/gentoo-kernel sys-kernel/gentoo-kernel-bin

# fstab ファイルの作成
echo "fstab ファイルを作成しています..."
emerge -a sys-fs/genfstab
genfstab -U / > /etc/fstab
echo "fstab ファイルの作成が完了しました。"

# ホスト名の設定
echo "ホスト名を設定しています..."
read -p "ホスト名を入力してください: " hostname
echo "$hostname" > /etc/hostname

# hosts ファイルの編集
# hosts ファイルのパス
hosts_file="/etc/hosts"

# バックアップファイル名
backup_file="${hosts_file}.bak"

# 変更前の hosts ファイルのバックアップ
cp "$hosts_file" "$backup_file"

# ホスト名の入力
read -p "新しいホスト名を入力してください: " new_hostname

# hosts ファイルの変更
sed -i "s/127.0.0.1\s*localhost/127.0.0.1     $new_hostname localhost/g" "$hosts_file"

echo "hosts ファイルを変更しました。変更前のバックアップは $backup_file です。"

# root パスワードの設定
passwd

# DHCP クライアントのインストール
emerge --ask net-misc/dhcpcd

# Grub のインストール
echo "Grub をインストールしています..."
emerge --ask sys-boot/grub
grub-install --target=x86_64-efi --efi-directory=/efi
grub-mkconfig -o /boot/grub/grub.cfg
echo "Grub のインストールが完了しました。"

# ユーザ名の入力
read -p "ユーザ名を入力してください: " username

# ユーザの作成
useradd -m -G users,wheel,audio,video,input "$username"

# ユーザのパスワード設定
passwd "$username"

# スクリプト終了
exit
