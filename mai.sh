#!/usr/bin/env bash
set -eu -o pipefail

declare -r INVALID_CONFIG_RETURN_CODE=64
declare -ra DIALOG_SIZE=(30 78)
declare -r BACK_BUTTON_TEXT=Back

declare -r SKIP_WIZARD=${MAI_SKIP_WIZARD:-false}

declare -rA "GUID_MOINTPOINTS=(
    [c12a7328-f81f-11d2-ba4b-00a0c93ec93b]=/boot
    [0657fd6d-a4ab-43c4-84e5-0933c84b4f4f]=SWAP
    [4f68bce3-e8cd-4db1-96e7-fbcaf984b709]=/
    [933ac7e1-2eb4-4f13-b844-0e14e2aef915]=/home
)"

declare -A "CONFIG=(
    [DISK]=${MAI_DISK:-}
    [HOSTNAME]=${MAI_HOSTNAME:-}
    [USERNAME]=${MAI_USERNAME:-}
    [TIMEZONE]=${MAI_TIMEZONE:-'Europe/Berlin'}
    [ADDITIONAL_PACKAGES]=${MAI_ADDITIONAL_PACKAGES:-'git ansible'}
)"

declare -a PARTITION_STRINGS

print_h0() {
    echo -e "\\e[42m==> $1\\e[0m" 1>&2
}

print_h1() {
    echo -e "\\e[44m===> $1\\e[0m" 1>&2
}

convert_string_to_map() {
    local string="$1"
    local -n map_ref="$2"
    while IFS="=" read -r key value; do
        # shellcheck disable=SC2034
        map_ref["$key"]="$value"
    done < <(echo -e "${string//;/'\n'}")
}

generate_file() {
    local path=$1
    local content=$2
    print_h1 "Generate $path"
    echo -e "$content" | tee /mnt"$path"
}

validate_config() {
    print_h0 "Validate Config"
    local return_code=0
    for key in "${!CONFIG[@]}"; do
        local value="${CONFIG["$key"]}"
        if [[ -z $value ]]; then
            return_code=$INVALID_CONFIG_RETURN_CODE
            printf "%-20s --> *****NOT SET*****\\n" "$key"
        else
            printf "%-20s --> %s\\n" "$key" "$value"
        fi
    done
    return $return_code
}

update_systemclock() {
    print_h0 "Update system clock"
    timedatectl set-ntp true
}

get_ram_size_in_KiB() {
    local meminfo_file="$1"
    awk '/^MemTotal:/ { print $2"KiB"; }' "$meminfo_file"
}

partition_disk() {
    print_h0 "Partition disk ${CONFIG[DISK]}"

    print_h1 "Create new GPT for ${CONFIG[DISK]}"
    sgdisk -Z "${CONFIG[DISK]}"

    local efi_size="550MiB"
    local swap_size
    swap_size="$(get_ram_size_in_KiB /proc/meminfo)"
    local root_size="50GiB"

    print_h1 "Create $efi_size efi partition"
    sgdisk --new=0:0:+${efi_size} --typecode=0:c12a7328-f81f-11d2-ba4b-00a0c93ec93b "${CONFIG[DISK]}"
    print_h1 "Create $swap_size swap partition"
    sgdisk --new=0:0:+"$swap_size" --typecode=0:0657fd6d-a4ab-43c4-84e5-0933c84b4f4f "${CONFIG[DISK]}"
    print_h1 "Create $root_size root partition"
    sgdisk --new=0:0:+"$root_size" --typecode=0:4f68bce3-e8cd-4db1-96e7-fbcaf984b709 "${CONFIG[DISK]}"
    print_h1 "Create home partition"
    sgdisk --new=0:0:0 --typecode=0:933ac7e1-2eb4-4f13-b844-0e14e2aef915 "${CONFIG[DISK]}"

    # TODO mkfs
}

# format_partition() {
#     local partition_string="$1"
#     local -A partition
#     convert_string_to_map "$partition_string" partition

#     if [[ "${partition[format]}" == false ]]; then
#         print_h1 "Skip format ${partition[device]}"
#         return
#     fi

#     if [[ "${partition[filesystem]}" = "swap" ]]; then
#         print_h1 "Set up a Linux swap area on device ${partition[device]}"
#         mkswap "${partition[device]}"
#         return
#     fi

#     local mkfs_parameter="-F"
#     if [[ "${partition[filesystem]}" == *"fat"* ]]; then
#         mkfs_parameter="-F32"
#     fi
#     print_h1 "Create filesystem ${partition[filesystem]} ${mkfs_parameter} on device ${partition[device]}"
#     eval "mkfs.${partition[filesystem]} ${mkfs_parameter} ${partition[device]}"
# }

format_partitions() {
    print_h0 "Format partitions ${CONFIG[DISK]}"

    # TODO: rename to format_existing_partitions and run only if no default partition layout is created

    # for partition_string in "${PARTITION_STRINGS[@]}"; do
    #     format_partition "$partition_string"
    # done
}

get_partition_guids() {
    local disk="$1"
    lsblk -lnpo TYPE,NAME,PARTTYPE "$disk" | awk '/part/ {print "device="$2";guid="$3;}'
}

map_mointpoint_to_device() {
    local device_guid_string="$1"

    local -A device_guid_map
    convert_string_to_map "$device_guid_string" device_guid_map
    local guid="${device_guid_map[guid]}"
    for know_guid in "${!GUID_MOINTPOINTS[@]}"; do
        if [[ "$know_guid" = "$guid" ]]; then
            echo -n "${GUID_MOINTPOINTS["$guid"]}=${device_guid_map[device]};"
            return
        fi
    done
}

map_mointpoints_to_devices() {
    local disk="$1"

    local -a device_guid_strings
    mapfile -t device_guid_strings < <(get_partition_guids "$disk")
    for device_guid_string in "${device_guid_strings[@]}"; do
        map_mointpoint_to_device "$device_guid_string"
    done
    echo
}

# mount_additional_partition() {
#     local partition_string="$1"
#     local -A partition
#     convert_string_to_map "$partition_string" partition

#     if [[ "${partition[mountpoint]}" = / ]]; then
#         echo "Skipping root partition" 1>&2
#         return 0
#     fi

#     if [[ "${partition[mountpoint]}" != "/"* ]]; then
#         echo "Skipping ${partition[mountpoint]} no valid mountpoint" 1>&2
#         return 0
#     fi

#     if [[ ! -d "/mnt${partition[mountpoint]}" ]]; then
#         mkdir "/mnt${partition[mountpoint]}"
#     fi
#     mount "${partition[device]}" "/mnt${partition[mountpoint]}"
# }

mount_partitions() {
    print_h0 "Mount partitions"

    # TODO: use map_mointpoints_to_devices

    # local root_partition_device
    # root_partition_device="$(get_root_partition_device "${PARTITION_STRINGS[@]}")"
    # print_h1 "Mount $root_partition_device as root partition"
    # mount "$root_partition_device" /mnt

    # for partition_string in "${PARTITION_STRINGS[@]}"; do
    #     mount_additional_partition "$partition_string"
    # done
}

install_base_packages() {
    print_h0 "Install base packages"
    pacman -Sy --noconfirm reflector
    reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    eval "pacstrap /mnt base linux linux-firmware sudo inetutils networkmanager ${CONFIG[ADDITIONAL_PACKAGES]}"
}

generate_fstab() {
    print_h0 "Generate fstab file"
    local swap_partition_device
    swap_partition_device=$(get_swap_partition_device "${PARTITION_STRINGS[@]}")
    swapon "$swap_partition_device"
    genfstab -U /mnt >/mnt/etc/fstab
    cat /mnt/etc/fstab
    swapoff "$swap_partition_device"
}

generate_host_files() {
    print_h0 "Generate host files"
    generate_file /etc/hostname "${CONFIG[HOSTNAME]}\\n"
    generate_file /etc/hosts "127.0.0.1\\tlocalhost\\n::1\\t\\tlocalhost\\n"
}

enable_networkmanager_service() {
    print_h0 "Enable NetworkManager service"
    arch-chroot /mnt systemctl enable NetworkManager.service
}

set_timezone() {
    print_h0 "Set timezone to ${CONFIG[TIMEZONE]}"
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${CONFIG[TIMEZONE]}" /etc/localtime
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

    local root_partition_device
    root_partition_device=$(get_root_partition_device "${PARTITION_STRINGS[@]}")
    local root_partition_uuid
    root_partition_uuid=$(blkid -s PARTUUID -o value "$root_partition_device")

    print_h1 "Generate /boot/loader/entries/arch.conf"
    tee /mnt/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=${root_partition_uuid} rw

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
    print_h0 "Create user: ${CONFIG[USERNAME]}"
    arch-chroot /mnt useradd -m -G wheel "${CONFIG[USERNAME]}"
}

set_user_password() {
    print_h0 "Please enter password for ${CONFIG[USERNAME]}"
    set +e
    local -i password_is_set=1
    until [ $password_is_set -eq 0 ]; do
        arch-chroot /mnt passwd "${CONFIG[USERNAME]}"
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
    validate_config

    update_systemclock

    mapfile -t PARTITION_STRINGS < <(create_default_partition_strings "${CONFIG[DISK]}" /proc/meminfo)
    partition_disk
    # TODO: rename to format_existing_partitions and run only if no default partition layout is created
    format_partitions
    mount_partitions

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
    disks=$(lsblk -dno TYPE,PATH,SIZE | awk -v current="${CONFIG[DISK]}" 'BEGIN{OFS=";";ORS=";";} /disk/ {
        state="off";
        if ( $1 == current ) state="on";
        print $2,$3,state;
    }')
    local text="The install script will create 3 partitions (efi, root and swap) on the seleceted disk. The swap partition will be the same size as RAM.\\n\\nAll data on the disk will be lost forever."
    CONFIG[DISK]="$(radiolist "Disk" "$text" "$disks")" || start_wizard
    ask_hostname
}

ask_hostname() {
    CONFIG[HOSTNAME]="$(inputbox "Hostname" "" "${CONFIG[HOSTNAME]}")" || ask_disk
    ask_username
}

ask_username() {
    local text="User will be created and the password must be set at the end of the installation"
    CONFIG[USERNAME]="$(inputbox "Username" "$text" "${CONFIG[USERNAME]}")" || ask_hostname
    ask_timezone
}

ask_timezone() {
    local timezones
    timezones=$(timedatectl list-timezones | awk -v current="${CONFIG[TIMEZONE]}" 'BEGIN{OFS=";";ORS=";";} {
        state="off";
        if ( $1 == current ) state="on";
        print $1,"|",state;
    }')
    local text="Select the local timezone"
    CONFIG[TIMEZONE]="$(radiolist "Timezone" "$text" "$timezones")" || ask_username
    ask_additional_packages
}

ask_additional_packages() {
    local text="Install additional packages"
    CONFIG[ADDITIONAL_PACKAGES]="$(inputbox "Additional packages" "$text" "${CONFIG[ADDITIONAL_PACKAGES]}")" || ask_timezone
    ask_confirm
}

ask_confirm() {
    local config_list
    config_list=$(validate_config)
    local config_check_return_code=$?

    local text="All parameters must be set\\n\\n$config_list"
    whiptail --yesno "$text" "${DIALOG_SIZE[@]}" --title "Confirm" --defaultno --yes-button "Start installation" --no-button $BACK_BUTTON_TEXT || exit 1

    if ((config_check_return_code == INVALID_CONFIG_RETURN_CODE)); then
        ask_confirm
    fi

    install_arch
}

main() {
    if [[ $SKIP_WIZARD == true ]]; then
        install_arch
    else
        start_wizard
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
