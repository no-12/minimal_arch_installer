#!/usr/bin/env bash
set -eu -o pipefail

declare -r INVALID_CONFIG_RETURN_CODE=64
declare -ra DIALOG_SIZE=(30 78)
declare -r BACK_BUTTON_TEXT=Back

declare -r SKIP_WIZARD=${MAI_SKIP_WIZARD:-false}

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
        local value="${CONFIG[$key]}"
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

get_first_free_disk_sector() {
    sgdisk -F "${CONFIG[DISK]}"
}

create_partition() {
    local partition_string="$1"
    local -A partition
    convert_string_to_map "$partition_string" partition

    if ((partition[size] > 0)); then
        print_h1 "Create partition #${partition[number]} with ${partition[size]} sectors"
        local first_free_disk_sector
        first_free_disk_sector="$(get_first_free_disk_sector)"
        local last_sector=$((first_free_disk_sector + "${partition[size]}" - 1))
        sgdisk --new="${partition[number]}:${first_free_disk_sector}:${last_sector}" "${CONFIG[DISK]}"
    else
        print_h1 "Create partition #${partition[number]} with largest available size"
        sgdisk --largest-new="${partition[number]}" "${CONFIG[DISK]}"
    fi

    print_h1 "Set partition #${partition[number]} guid to ${partition[guid]}"
    sgdisk --typecode="${partition[number]}:${partition[guid]}" "${CONFIG[DISK]}"
}

partition_disk() {
    print_h0 "Partition disk ${CONFIG[DISK]}"

    print_h1 "Create new GPT for ${CONFIG[DISK]}"
    sgdisk -o "${CONFIG[DISK]}"
    partprobe

    for partition_string in "${PARTITION_STRINGS[@]}"; do
        create_partition "$partition_string"
    done
}

format_partition() {
    local partition_string="$1"
    local -A partition
    convert_string_to_map "$partition_string" partition

    if [[ "${partition[format]}" == false ]]; then
        print_h1 "Skip format ${partition[device]}"
        return
    fi

    if [[ "${partition[filesystem]}" = "swap" ]]; then
        print_h1 "Set up a Linux swap area on device ${partition[device]}"
        mkswap "${partition[device]}"
        return
    fi

    local mkfs_parameter="-F"
    if [[ "${partition[filesystem]}" == *"fat"* ]]; then
        mkfs_parameter="-F32"
    fi
    print_h1 "Create filesystem ${partition[filesystem]} ${mkfs_parameter} on device ${partition[device]}"
    eval "mkfs.${partition[filesystem]} ${mkfs_parameter} ${partition[device]}"
}

format_partitions() {
    print_h0 "Format partitions ${CONFIG[DISK]}"
    for partition_string in "${PARTITION_STRINGS[@]}"; do
        format_partition "$partition_string"
    done
}

get_root_partition_device() {
    local -a partition_strings=("$@")
    local root_partition_string
    root_partition_string=$(printf -- '%s\n' "${partition_strings[@]}" | grep 'mountpoint=/;')
    [ -z "$root_partition_string" ] && return 1
    local -A root_partition
    convert_string_to_map "$root_partition_string" root_partition
    echo "${root_partition[device]}"
}

get_swap_partition_device() {
    local -a partition_strings=("$@")
    local root_partition_string
    root_partition_string=$(printf -- '%s\n' "${partition_strings[@]}" | grep 'filesystem=swap;')
    [ -z "$root_partition_string" ] && return 1
    local -A root_partition
    convert_string_to_map "$root_partition_string" root_partition
    echo "${root_partition[device]}"
}

mount_additional_partition() {
    local partition_string="$1"
    local -A partition
    convert_string_to_map "$partition_string" partition

    if [[ "${partition[mountpoint]}" = / ]]; then
        echo "Skipping root partition" 1>&2
        return 0
    fi

    if [[ "${partition[mountpoint]}" != "/"* ]]; then
        echo "Skipping ${partition[mountpoint]} no valid mountpoint" 1>&2
        return 0
    fi

    if [[ ! -d "/mnt${partition[mountpoint]}" ]]; then
        mkdir "/mnt${partition[mountpoint]}"
    fi
    mount "${partition[device]}" "/mnt${partition[mountpoint]}"
}

mount_partitions() {
    print_h0 "Mount partitions"

    local root_partition_device
    root_partition_device="$(get_root_partition_device "${PARTITION_STRINGS[@]}")"
    print_h1 "Mount $root_partition_device as root partition"
    mount "$root_partition_device" /mnt

    for partition_string in "${PARTITION_STRINGS[@]}"; do
        mount_additional_partition "$partition_string"
    done
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
# disk partitioning
################################

get_physical_sector_size_in_KiB() {
    local disk="$1"
    lsblk -dno LOG-SeC "$disk" | awk '{$1=$1;print}'
}

get_ram_size_in_KiB() {
    local meminfo_file="$1"
    awk '/^MemTotal:/ { print $2; }' "$meminfo_file"
}

get_partition_device_without_number() {
    local disk="$1"
    local number_prefix=""
    if [[ "$disk" == *nvm* ]]; then
        number_prefix="p"
    fi
    echo "${disk}${number_prefix}"
}

new_partition_string() {
    local device_without_number="$1"
    local number="$2"
    local size="$3"
    local filesystem="$4"
    local format="$5"
    local mountpoint="$6"
    local guid="$7"
    echo "number=${number};device=${device_without_number}${number};size=${size};filesystem=${filesystem};format=${format};mountpoint=${mountpoint};guid=${guid}"
}

convert_string_to_map() {
    local string="$1"
    local -n map_ref="$2"
    while IFS="=" read -r key value; do
        # shellcheck disable=SC2034
        map_ref["$key"]="$value"
    done < <(echo -e "${string//;/'\n'}")
}

create_default_partition_strings() {
    local disk="$1"
    local meminfo_file="$2"
    local device_without_number
    local sector_size_in_KiB
    local ram_size_in_KiB
    device_without_number=$(get_partition_device_without_number "$disk")
    sector_size_in_KiB=$(get_physical_sector_size_in_KiB "$disk")
    ram_size_in_KiB="$(get_ram_size_in_KiB "$meminfo_file")"

    local boot_size=$((512 * 1024 ** 2 / sector_size_in_KiB))
    local swap_size=$((ram_size_in_KiB * 1024 / sector_size_in_KiB))
    local root_size=$((50 * 1024 ** 3 / sector_size_in_KiB))

    new_partition_string "$device_without_number" 1 $boot_size vfat true /boot "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    new_partition_string "$device_without_number" 2 $swap_size swap true [SWAP] "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
    new_partition_string "$device_without_number" 3 $root_size ext4 true / "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
    new_partition_string "$device_without_number" 4 0 ext4 true /home "933ac7e1-2eb4-4f13-b844-0e14e2aef915"
}

# print_partition() {
#     printf "%-16s %-8s %-8s %-12s %-37s\n" "$1" "$2" "$3" "$4" "$5"
# }

# print_partition_layout() {
#     print_partition "Partition" "Size" "Type" "Mountpoint" "GUID"
#     for ((i = 0; i < "${#partition_devices[@]}"; i++)); do
#         print_partition "${partition_devices[i]}" "${partition_sizes[i]}" "${partition_types[i]}" "${partition_mountpoints[i]}" "${PARTITION_GUIDS[${partition_mountpoints[i]}]}"
#     done
# }

# get_existing_partitions() {
#     partitions=$(lsblk -flnp -o NAME,SIZE,FSTYPE,MOUNTPOINT,PARTTYPE "${CONFIG[DISK]}")
#     mapfile -t partition_devices < <(echo "$partitions" | awk 'NR>1 { print $1 }')
#     mapfile -t partition_sizes < <(echo "$partitions" | awk 'NR>1 { print $2 }')
#     mapfile -t partition_types < <(echo "$partitions" | awk 'NR>1 { print $3 }')
#     mapfile -t partition_mountpoints < <(echo "$partitions" | awk 'NR>1 { print $4 }')
# }

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
