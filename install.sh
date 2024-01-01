#!/bin/bash

set -e

# Mode selection
select_mode() {
    PS3="Please select script mode (1: Desktop, 2: Server): "
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
                echo "Invalid selection. Please select again."
                ;;
        esac
    done
}

# Disk selection
select_disk() {
    local available_disks
    available_disks=$(lsblk -d -o NAME,SIZE -n | awk '{print $1}')
    PS3="Please select a disk to partition: "
    select disk in $available_disks; do
        if [ -n "$disk" ]; then
            echo "Selected disk: $disk"
            break
        else
            echo "Invalid selection. Please select again."
        fi
    done
}

# Confirmation before proceeding
confirm_proceed() {
    read -p "Do you want to proceed? (y/n): " confirmation
    if [ "$confirmation" != "y" ]; then
        echo "Operation cancelled."
        exit 1
    fi
}

# Create EFI partition
create_efi_partition() {
    echo "Please specify the size of the EFI system partition (e.g., 512M): "
    read efi_size

    if [[ "$disk" == nvme* ]]; then
        efi_partition_device="/dev/${disk}p1"
    else
        efi_partition_device="/dev/${disk}1"
    fi

    parted -s "/dev/$disk" mklabel gpt
    parted -s "/dev/$disk" mkpart primary fat32 1M "$efi_size"
    parted -s "/dev/$disk" mkpart primary btrfs "$efi_size" 100%

    mkfs.vfat -F 32 "$efi_partition_device"
}

# Mount partitions
mount_partitions() {
    echo "Mounting root partition..."
    mkdir -p /mnt/gentoo
    root_partition="/dev/${disk}${root_partition_suffix}"
    mount "$root_partition" /mnt/gentoo

    echo "Mounting EFI system partition..."
    mkdir -p /mnt/gentoo/efi
    mount "$efi_partition_device" /mnt/gentoo/efi

    if [ "$create_home_on_separate_disk" == "y" ]; then
        echo "Mounting home partition..."
        mkdir -p /mnt/gentoo/home
        if [ "$disk_type" == "nvme" ]; then
            home_partition="/dev/${home_disk}n${home_partition_number}p${home_partition_suffix}"
        else
            home_partition="/dev/${home_disk}${home_partition_number}${home_partition_suffix}"
        fi
        mount "$home_partition" /mnt/gentoo/home
    fi

    echo "Mounting completed."
}

# Execute script in chroot
chroot_script() {
    chroot /mnt/gentoo /bin/bash /chroot_script.sh
}

# Merge make.conf
merge_make_conf() {
    local base_conf="make.conf.base"
    local mode_conf="make.conf.${mode}"

    # Check if base make.conf exists
    if [ ! -e "$base_conf" ]; then
        echo "Error: $base_conf not found."
        exit 1
    fi

    # Check if mode make.conf exists
    if [ ! -e "$mode_conf" ]; then
        echo "Error: $mode_conf not found."
        exit 1
    fi

    # Create merged make.conf
    cat "$base_conf" "$mode_conf" > merged_make.conf

    # Copy to /mnt/gentoo
    cp merged_make.conf /mnt/gentoo/etc/portage/make.conf

    # Remove temporary file
    rm merged_make.conf
}

# Mode selection
select_mode

# Disk selection
select_disk

# Create EFI partition
create_efi_partition

# Check if /home partition should be created on a separate disk
read -p "Do you want to create a /home partition on a separate disk? (y/n): " create_home_on_separate_disk
if [ "$create_home_on_separate_disk" == "y" ]; then
    create_home_partition
fi

# Mount partitions
mount_partitions

# Copy make.conf to /mnt/gentoo
merge_make_conf

# Execute script in chroot
chroot_script

# Post-installation
echo "Installation completed."

# Prompt user to reboot
read -p "Installation completed. Do you want to reboot? (y/n): " reboot_choice
if [ "$reboot_choice" == "y" ]; then
    echo "Rebooting system..."
    reboot
else
    echo "Exiting without rebooting."
fi