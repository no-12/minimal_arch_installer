#!/usr/bin/env bash

set -eu -o pipefail

declare -r INVALID_CONFIG_RETURN_CODE=64
declare -ar DIALOG_SIZE=(30 78)
declare -r BACK_BUTTON_TEXT=Back

declare -r SKIP_WIZARD=${MAI_SKIP_WIZARD:-false}

declare -A config
config[DISK]=${MAI_DISK:-}
config[HOSTNAME]=${MAI_HOSTNAME:-}
config[USERNAME]=${MAI_USERNAME:-}
config[TIMEZONE]=${MAI_TIMEZONE:-"Europe/Berlin"}
config[ADDITIONAL_PACKAGES]=${MAI_ADDITIONAL_PACKAGES:-"git ansible"}

declare efi_part
declare swap_part
declare root_part

print_h0() {
    echo -e "\\e[42m==> $1\\e[0m" 1>&2
}

print_h1() {
    echo -e "\\e[44m===> $1\\e[0m" 1>&2
}

generate_file() {
    local path=$1
    local content=$2
    print_h1 "Generate $path"
    echo -e "$content" | tee /mnt"$path"
}

check_config() {
    local return_code=0
    for key in "${!config[@]}"; do
        local value="${config[$key]}"
        if [[ -z $value ]]; then
            return_code=$INVALID_CONFIG_RETURN_CODE
            printf "%-20s --> *****NOT SET*****\\n" "$key"
        else
            printf "%-20s --> %s\\n" "$key" "$value"
        fi
    done
    return $return_code
}

check_and_init() {
    print_h0 "Check Config"
    check_config

    if [[ "${config[DISK]}" == nvm* ]]; then
        efi_part=/dev/${config[DISK]}p1
        swap_part=/dev/${config[DISK]}p2
        root_part=/dev/${config[DISK]}p3
    else
        efi_part=/dev/${config[DISK]}1
        swap_part=/dev/${config[DISK]}2
        root_part=/dev/${config[DISK]}3
    fi
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
    mkfs.fat -F32 "$efi_part"
    mkfs.ext4 -F "$root_part"
}

mount_partitions() {
    print_h0 "Mount partitions"
    mount "$root_part" /mnt
    if [[ ! -d /mnt/boot ]]; then
        mkdir /mnt/boot
    fi
    mount "$efi_part" /mnt/boot
}

create_swap() {
    print_h0 "Create swap partition"
    mkswap "$swap_part"
}

install_base_packages() {
    print_h0 "Install base packages"
    pacman -Sy --noconfirm reflector
    reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    eval "pacstrap /mnt base linux linux-firmware sudo inetutils networkmanager ${config[ADDITIONAL_PACKAGES]}"
}

generate_fstab() {
    print_h0 "Generate fstab file"
    swapon "$swap_part"
    genfstab -U /mnt >/mnt/etc/fstab
    cat /mnt/etc/fstab
    swapoff "$swap_part"
}

generate_host_files() {
    print_h0 "Generate host files"
    generate_file /etc/hostname "${config[HOSTNAME]}\\n"
    generate_file /etc/hosts "127.0.0.1\\tlocalhost\\n::1\\t\\tlocalhost\\n"
}

enable_networkmanager_service() {
    print_h0 "Enable NetworkManager service"
    arch-chroot /mnt systemctl enable NetworkManager.service
}

set_timezone() {
    print_h0 "Set timezone to ${config[TIMEZONE]}"
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${config[TIMEZONE]}" /etc/localtime
    arch-chroot /mnt hwclock --systohc
}

set_locale() {
    print_h0 "Set locale"
    generate_file /etc/locale.gen "en_US.UTF-8 UTF-8\\n"
    generate_file /etc/locale.conf "LANG=en_US.UTF-8\\n"
    arch-chroot /mnt locale-gen
}

generate_sudoers_file() {
    print_h0 "Generate /etc/sudoers"
    tee /mnt/etc/sudoers <<EOF
#includedir /etc/sudoers.d

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
    root_partuuid=$(blkid -s PARTUUID -o value "$root_part")

    print_h1 "Generate /boot/loader/entries/arch.conf"
    tee /mnt/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=${root_partuuid} rw

EOF

    print_h1 "Generate /boot/loader/loader.conf"
    tee /mnt/boot/loader/loader.conf <<EOF
default arch
timeout 0
console-mode max
editor no

EOF
}

create_user() {
    print_h0 "Create user: ${config[USERNAME]}"
    arch-chroot /mnt useradd -m -G wheel "${config[USERNAME]}"
}

set_user_password() {
    print_h0 "Please enter password for ${config[USERNAME]}"
    set +e
    local -i password_is_set=1
    until [ $password_is_set -eq 0 ]; do
        arch-chroot /mnt passwd "${config[USERNAME]}"
        password_is_set=$?
    done
    set -e
}

finalize_installation() {
    print_h0 "Finalize installation"

    print_h1 "Lock root login"
    arch-chroot /mnt passwd -l root

    print_h1 "Unmount partitions"
    umount -R /mnt

    print_h0 "Installation finished"
}

install_arch() {
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
    set_user_password

    finalize_installation
}

################################
# wizard stuff
################################

radiolist() {
    local title=$1
    local text=$2
    local -a entries
    IFS=';' read -r -a entries <<<"$3"
    whiptail --radiolist "${text}" "${DIALOG_SIZE[@]}" 20 --title "${title}" --cancel-button $BACK_BUTTON_TEXT "${entries[@]}" 3>&1 1>&2 2>&3
}

inputbox() {
    local title=$1
    local text=$2
    local default_value=$3
    whiptail --inputbox "${text}" "${DIALOG_SIZE[@]}" "${default_value}" --title "${title}" --cancel-button $BACK_BUTTON_TEXT 3>&1 1>&2 2>&3
}

start_wizard() {
    local text="Bash script to install Arch"
    whiptail --yesno "$text" "${DIALOG_SIZE[@]}" --title "Minimal Arch Installer" --yes-button "Ok" --no-button "Cancel" || exit 1
    ask_disk
}

ask_disk() {
    local disks
    disks=$(lsblk | awk -v current="${config[DISK]}" 'BEGIN{OFS=";";ORS=";";} /disk/ {
        state="off";
        if ( $1 == current ) state="on";
        print $1,$4,state;
    }')
    local text="The install script will create 3 partitions (efi, root and swap) on the seleceted disk. The swap partition will be the same size as RAM.\\n\\nAll data on the disk will be lost forever."
    config[DISK]="$(radiolist "Disk" "$text" "$disks")" || start_wizard
    ask_hostname
}

ask_hostname() {
    config[HOSTNAME]="$(inputbox "Hostname" "" "${config[HOSTNAME]}")" || ask_disk
    ask_username
}

ask_username() {
    local text="User will be created and the password must be set at the end of the installation"
    config[USERNAME]="$(inputbox "Username" "$text" "${config[USERNAME]}")" || ask_hostname
    ask_timezone
}

ask_timezone() {
    local timezones
    timezones=$(timedatectl list-timezones | awk -v current="${config[TIMEZONE]}" 'BEGIN{OFS=";";ORS=";";} {
        state="off";
        if ( $1 == current ) state="on";
        print $1,"|",state;
    }')
    local text="Select the local timezone"
    config[TIMEZONE]="$(radiolist "Timezone" "$text" "$timezones")" || ask_username
    ask_additional_packages
}

ask_additional_packages() {
    local text="Install additional packages"
    config[ADDITIONAL_PACKAGES]="$(inputbox "Additional packages" "$text" "${config[ADDITIONAL_PACKAGES]}")" || ask_timezone
    ask_confirm
}

ask_confirm() {
    local config_list
    config_list=$(check_config)
    local config_check_return_code=$?

    local text="All parameters must be set\\n\\n$config_list"
    whiptail --yesno "$text" "${DIALOG_SIZE[@]}" --title "Confirm" --defaultno --yes-button "Start installation" --no-button $BACK_BUTTON_TEXT || exit 1

    if ((config_check_return_code == INVALID_CONFIG_RETURN_CODE)); then
        ask_confirm
    fi

    install_arch
}

if [[ $SKIP_WIZARD == true ]]; then
    install_arch
else
    start_wizard
fi
