#!/usr/bin/env bash

declare -r INVALID_CONFIG_RETURN_CODE=64
declare -r DIALOG_SIZE="30 78"
declare -r BACK_BUTTON_TEXT=Back


declare -A config
config[DISK]=${DISK}
config[ARCH_HOSTNAME]=${ARCH_HOSTNAME}
config[USERNAME]=${USERNAME}
config[TIMEZONE]=${TIMEZONE:="Europe/Berlin"}
config[ADDITIONAL_PACKAGES]=${ADDITIONAL_PACKAGES:="git ansible"}

declare efi_part
declare swap_part
declare root_part

declare -A states
declare -i current_state=0
declare -i wizard_step_exit_code=0


print_h0() {
    echo -e "\e[42m==> $1\e[0m"
}


print_h1() {
    echo -e "\e[44m===> $1\e[0m"
}


generate_file() {
    local path=$1
    local content=$2
    print_h1 "Generate $path"
    echo -e $content | tee /mnt$path
}


check_config() {
    local return_code=0
    for key in "${!config[@]}"; do
        local value="${config[$key]}"
        if [[ -z $value ]]; then
            return_code=$INVALID_CONFIG_RETURN_CODE
            printf "%-20s --> *****NOT SET*****\n" $key
        else
            printf "%-20s --> %s\n" $key "$value"
        fi
    done
    return $return_code
}


check_and_init() {
    print_h0 "Check Config"
    check_config

    efi_part=/dev/${config[DISK]}1
    swap_part=/dev/${config[DISK]}2
    root_part=/dev/${config[DISK]}3
}


update_systemclock() {
    print_h0 "Update system clock"
    timedatectl set-ntp true
}


partition_disk() {
    print_h0 "Partition disk ${config[DISK]}"
    local efi_size=550
    local efi_end
    efi_end=$((efi_size + 1))

    local swap_size
    swap_size=$(awk '/^MemTotal:/ { print rshift($2, 10); } ' /proc/meminfo)
    local swap_end
    swap_end=$((efi_end + swap_size + 1))

    print_h1 "EFI size: $efi_size MiB"
    print_h1 "Swap size: $swap_size MiB"

    parted --script /dev/"${config[DISK]}" \
        mklabel gpt \
        mkpart primary fat32 1MiB ${efi_end}MiB \
        set 1 esp on \
        mkpart primary linux-swap ${efi_end}MiB ${swap_end}MiB \
        mkpart primary ext4 ${swap_end}MiB 100%
}


format_partitions() {
    print_h0 "Format partitions"
    mkfs.fat -F32 $efi_part
    mkfs.ext4 -F $root_part
}


mount_partitions() {
    print_h0 "Mount partitions"
    mount $root_part /mnt
    if [[ ! -d /mnt/boot ]]; then
        mkdir /mnt/boot
    fi
    mount $efi_part /mnt/boot
}


unmount_partitions() {
    print_h0 "Unmount partitions"
    umount $efi_part
    umount $root_part
}


create_swap() {
    print_h0 "Create swap partition"
    mkswap $swap_part
}


install_base_packages() {
    print_h0 "Install base packages"
    pacman -Sy --noconfirm reflector
    reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    pacstrap /mnt base linux linux-firmware sudo inetutils networkmanager $ADDITIONAL_PACKAGES
}


generate_fstab() {
    print_h0 "Generate fstab file"
    swapon $swap_part
    genfstab -U /mnt > /mnt/etc/fstab
    cat /mnt/etc/fstab
    swapoff $swap_part
}


generate_host_files() {
    print_h0 "Generate host files"
    generate_file /etc/hostname "${config[ARCH_HOSTNAME]}\n"
    generate_file /etc/hosts "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n"
}


enable_networkmanager_service() {
    print_h0 "Enable NetworkManager service"
    arch-chroot /mnt systemctl enable NetworkManager.service
}


set_timezone() {
    print_h0 "Set timezone to ${config[TIMEZONE]}"
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/${config[TIMEZONE]} /etc/localtime
    arch-chroot /mnt hwclock --systohc
}


set_locale() {
    print_h0 "Set locale"
    generate_file /etc/locale.gen "en_US.UTF-8 UTF-8\n"
    generate_file /etc/locale.conf "LANG=en_US.UTF-8\n"
    arch-chroot /mnt locale-gen
}


generate_sudoers_file() {
    print_h0 "Generate /etc/sudoers"
    tee << EOF /mnt/etc/sudoers
Defaults    env_reset
Defaults    secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

root    ALL=(ALL:ALL) ALL
%wheel  ALL=(ALL:ALL) ALL

EOF
}


install_bootloader() {
    print_h0 "Install bootloader"
    arch-chroot /mnt bootctl --path=/boot install

    local root_partuuid
    root_partuuid=$(blkid -s PARTUUID -o value $root_part)

    print_h1 "Generate /boot/loader/entries/arch.conf"
    tee << EOF /mnt/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=${root_partuuid} rw

EOF

    print_h1 "Generate /boot/loader/loader.conf"
    tee << EOF /mnt/boot/loader/loader.conf
default arch
timeout 0
console-mode max
editor no

EOF
}


create_user() {
    print_h0 "Create user: ${config[USERNAME]}"
    arch-chroot /mnt useradd -m -G wheel ${config[USERNAME]}
    print_h1 "Please enter password"
    arch-chroot /mnt passwd ${config[USERNAME]}
}


lock_root_login() {
    print_h0 "Lock root login"
    arch-chroot /mnt passwd -l root
}


install_arch() {
    set -e

    check_and_init

    update_systemclock
    partition_disk
    format_partitions
    mount_partitions
    create_swap

    install_base_packages

    generate_fstab
    generate_host_files
    enable_networkmanager_service
    set_timezone
    set_locale
    generate_sudoers_file
    install_bootloader
    create_user

    lock_root_login
    unmount_partitions
    print_h0 "Installation finished"
}


################################
# wizard stuff
################################


radiolist() {
    local title=$1
    local text=$2
    shift
    shift
    whiptail --radiolist "${text}" $DIALOG_SIZE 20 --title "${title}" --cancel-button $BACK_BUTTON_TEXT ${@}
}


inputbox() {
    local title=$1
    local text=$2
    local default_value=$3
    whiptail --inputbox "${text}" $DIALOG_SIZE "${default_value}" --title "${title}" --cancel-button $BACK_BUTTON_TEXT
}


dialog_wrapper() {
    wizard_step_exit_code=$?
    local parameter=$1
    local dialog_return_value="$2"
    if [[ ! -z $dialog_return_value ]]; then
        config[$parameter]="$dialog_return_value"
    fi
}


init_message() {
    whiptail --msgbox "Bash script to install Arch" $DIALOG_SIZE --title "Minimal Arch Installer"
    wizard_step_exit_code=$?
}


ask_disk() {
    local disks
    disks=($(lsblk | awk -v current="${config[DISK]}" '/disk/ {
        state="off";
        if ( $1 == current ) state="on";
        printf"%s %s %s\n", $1, $4, state
    }'))
    dialog_wrapper DISK $(radiolist "Disk" "The install script will create 3 partitions (efi, root and swap) on the seleceted disk. The swap partition will be the same size as RAM.\n\nAll data on the disk will be lost forever." "${disks[@]}" 3>&1 1>&2 2>&3)
}


ask_hostname() {
    dialog_wrapper ARCH_HOSTNAME $(inputbox "Hostname" "" "${config[ARCH_HOSTNAME]}" 3>&1 1>&2 2>&3)
}


ask_username() {
    dialog_wrapper USERNAME $(inputbox "Username" "User will be created and the password must be set at the end of the installation" "${config[USERNAME]}" 3>&1 1>&2 2>&3)
}


ask_timezone() {
    local timezones
    timezones=($(timedatectl list-timezones | awk -v current="${config[TIMEZONE]}" '{
        state="off";
        if ( $1 == current ) state="on";
        printf"%s | %s\n", $1, state
    }'))
    dialog_wrapper TIMEZONE $(radiolist "Timezone" "Select the local timezone" "${timezones[@]}" 3>&1 1>&2 2>&3)
}


ask_additional_packages() {
    dialog_wrapper ADDITIONAL_PACKAGES "$(inputbox "Additional packages" "Install additional packages" "${config[ADDITIONAL_PACKAGES]}" 3>&1 1>&2 2>&3)"
}


ask_confirm() {
    local config_list
    config_list=$(check_config)
    local config_check_return_code=$?
    whiptail --yesno "All parameters must be set\n\n$config_list" $DIALOG_SIZE --title "Confirm" --yes-button "Start installation" --no-button $BACK_BUTTON_TEXT
    wizard_step_exit_code=$?
    if (( $wizard_step_exit_code == 0 && $config_check_return_code == $INVALID_CONFIG_RETURN_CODE)); then
        ask_confirm
    fi
}


run() {
    ${states[$current_state]}
    if (( $wizard_step_exit_code == 0 )); then
        ((current_state++))
    elif (( $wizard_step_exit_code == 1 )); then
        ((current_state--))
    else
        exit
    fi
    run
}


states[0]=init_message
states[1]=ask_disk
states[2]=ask_hostname
states[3]=ask_username
states[4]=ask_timezone
states[5]=ask_additional_packages
states[6]=ask_confirm
states[7]=install_arch
states[8]=exit

run
