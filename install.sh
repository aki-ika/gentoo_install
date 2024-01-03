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

    local available_disks
    available_disks=$(lsblk -d -o NAME,SIZE -n | awk '{print $1}')
    PS3="Please select a disk for EFI: "
    select disk in $available_disks; do
        if [ -n "$disk" ]; then
            echo "Selected disk: $disk"
            break
        else
            echo "Invalid selection. Please select again."
        fi
    done

    parted -s "/dev/$disk" mklabel gpt
    parted -s "/dev/$disk" mkpart primary fat32 1M "$efi_size"

    # Get the partition number of the newly created partition
    local partition_number
    partition_number=$(parted -s "/dev/$disk" print | awk '/^ [1-9]+/{print $1}' | tail -n 1)

    # Check if the disk is an NVMe device
    if [[ $disk == nvme* ]]; then
        mkfs.vfat -F 32 "/dev/${disk}p${partition_number}"
    else
        mkfs.vfat -F 32 "/dev/${disk}${partition_number}"
    fi
}

# Create root partition
create_root_partition() {
    echo "Please specify the size of the root partition (e.g., 20G, or 100% to use all remaining space): "
    read root_size
    parted -s "/dev/$disk" mkpart primary btrfs "$efi_size" 100%
}

# Mount partitions
mount_partitions() {
    echo "Create mount points..."
    mkdir -p /mnt/gentoo
    echo "Mounting root partition..."
    if [[ "$disk" == nvme* ]]; then
        root_partition="/dev/${disk}p${root_partition_suffix}"
    else
        root_partition="/dev/${disk}${root_partition_suffix}"
    fi
    mount "$root_partition" /mnt/gentoo

    echo "Creating mount points for EFI system partition"
    mkdir -p /mnt/gentoo/efi
    echo "Mounting EFI system partition..."
    mount "$efi_partition_device" /mnt/gentoo/efi

    if [ "$create_home_on_separate_disk" == "y" ]; then
        echo "Creating mount points for home partition"
        mkdir -p /mnt/gentoo/home
        echo "Mounting home partition..."
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
    # Copy the chroot script to the /mnt/gentoo directory
    cp chroot_script.sh /mnt/gentoo/chroot_script.sh

    # Run the script inside the chroot
    chroot /mnt/gentoo /bin/bash /chroot_script.sh
    rm /mnt/gentoo/chroot_script.sh
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

umount_partitions() {
    echo "Unmounting partitions..."
    umount -R /mnt/gentoo
    echo "Unmounting completed."
}

# Mode selection
select_mode

# Disk selection
select_disk

# Create EFI partition
create_efi_partition

# Create ROOT partition
create_root_partition

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

# Unmount partitions
umount_partitions
# Prompt user to reboot
read -p "Installation completed. Do you want to reboot? (y/n): " reboot_choice
if [ "$reboot_choice" == "y" ]; then
    echo "Rebooting system..."
    reboot
else
    echo "Exiting without rebooting."
fi