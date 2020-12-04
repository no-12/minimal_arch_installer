#!/usr/bin/env bash
set -eu -o pipefail

declare -r TITLE="Minimal Arch Installer"
declare -ra DIALOG_SIZE=(30 78)
declare -r BACK_BUTTON_TEXT=Back
declare -rA "GUID_MOINTPOINTS=(
    [c12a7328-f81f-11d2-ba4b-00a0c93ec93b]=/boot
    [0657fd6d-a4ab-43c4-84e5-0933c84b4f4f]=SWAP
    [4f68bce3-e8cd-4db1-96e7-fbcaf984b709]=/
    [933ac7e1-2eb4-4f13-b844-0e14e2aef915]=/home
)"
declare -rA "MKFSCOMMANDS=(
    [vfat]='mkfs.fat -F32'
    [swap]='mkswap'
    [ext4]='mkfs.ext4 -F'
)"

declare -a PARTITIONS
declare -A PARTITION_SIZES
declare -A PARTITION_GUIDS
declare -A PARTITION_FILESYSTEMS

declare -A "CONFIG=(
    [HOSTNAME]=
    [USERNAME]=
    [TIMEZONE]='Europe/Berlin'
    [ADDITIONAL_PACKAGES]='git ansible'
)"
declare -A CONFIG_FILESYSTEMS
declare -A CONFIG_MOUNTPOINTS
declare NEXT_WIZARD_STEP=dialog_partition_disk_menu

print_h0() {
    echo -e "\\e[42m==> $1\\e[0m" 1>&2
}

print_h1() {
    echo -e "\\e[44m===> $1\\e[0m" 1>&2
}

log() {
    echo -e "$1" 1>&2
}

log_error() {
    echo -e "\\e[31mError: $1\e[0m" 1>&2
}

generate_file() {
    local path=$1
    local content=$2
    print_h1 "Generate $path"
    echo -e "$content" | tee /mnt"$path"
}

check_if_device_is_mounted() {
    local disk="$1"
    if grep -qs "$disk" /proc/mounts; then
        log_error "$disk is mounted"
        exit 1
    fi
}

get_default_filesystem_type() {
    local guid=$1
    case $guid in
    "c12a7328-f81f-11d2-ba4b-00a0c93ec93b") echo "vfat" ;;
    "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f") echo "swap" ;;
    *) echo "ext4" ;;
    esac
}

init_partition_data() {
    [[ -v PARTITIONS[@] ]] && return 0
    eval "$(lsblk -lnpo TYPE,PATH,SIZE,PARTTYPE,FSTYPE | awk '/part/ {
        printf "PARTITIONS+=(%s)\n", $2;
        printf "PARTITION_SIZES[%s]=%s\n", $2, $3;
        printf "PARTITION_GUIDS[%s]=%s\n", $2, $4;
        printf "PARTITION_FILESYSTEMS[%s]=%s\n", $2, $5;
    }')"
}

init_config_filesystems() {
    [[ -v CONFIG_FILESYSTEMS[@] ]] && return 0
    for partition in "${PARTITIONS[@]}"; do
        if [[ -z ${PARTITION_FILESYSTEMS["$partition"]} ]]; then
            local guid="${PARTITION_GUIDS["$partition"]}"
            CONFIG_FILESYSTEMS["$partition"]=$(get_default_filesystem_type "$guid")
        else
            CONFIG_FILESYSTEMS["$partition"]=""
        fi
    done
}

init_config_mountpoints() {
    [[ -v CONFIG_MOUNTPOINTS[@] ]] && return 0
    for partition in "${PARTITIONS[@]}"; do
        local guid="${PARTITION_GUIDS["$partition"]}"
        local mointpoint="${GUID_MOINTPOINTS["$guid"]:-}"
        CONFIG_MOUNTPOINTS["$partition"]="$mointpoint"
    done
}

print_data_lose_warning() {
    printf "
                    +---------------------------------+
                    | WARNING: All data on %-10s |
                    |          will be lost forever   |
                    +---------------------------------+" \
        "${1:-"this disk"}"
}

print_config() {
    local horizontal_bar="+------------------+------------+----------+----------+------------------+"
    echo "$horizontal_bar"
    printf "| %-16s | %-10s | %-8s | %-8s | %-16s |\\n" "partition" "size" "curr. FS" "new FS" "mountpoint"
    echo "$horizontal_bar"
    for partition in "${PARTITIONS[@]}"; do
        printf "| %-16s | %-10s | %-8s | %-8s | %-16s |\\n" "$partition" "${PARTITION_SIZES["$partition"]}" "${PARTITION_FILESYSTEMS["$partition"]}" "${CONFIG_FILESYSTEMS["$partition"]}" "${CONFIG_MOUNTPOINTS["$partition"]}"
    done
    echo "$horizontal_bar"

    echo -e "\n\nConfig:\n"
    for key in "${!CONFIG[@]}"; do
        local value="${CONFIG["$key"]}"
        if [[ -z $value ]]; then
            printf "%-20s --> *****NOT SET*****\\n" "$key"
        else
            printf "%-20s --> %s\\n" "$key" "$value"
        fi
    done
}

is_config_valid() {
    for key in "${!CONFIG[@]}"; do
        if [[ -z "${CONFIG["$key"]}" && "$key" != "ADDITIONAL_PACKAGES" ]]; then
            return 1
        fi
    done
}

validate_config() {
    print_h0 "Validate config"
    print_config
    is_config_valid
}

update_systemclock() {
    print_h0 "Update system clock"
    timedatectl set-ntp true
}

format_partitions() {
    print_h0 "Format partitions"
    for device in "${!FILESYSTEMS[@]}"; do
        local filesystem="${FILESYSTEMS["$device"]}"
        print_h1 "Format device: ${MKFSCOMMANDS["$filesystem"]} $device"
        eval "${MKFSCOMMANDS["$filesystem"]} $device"
    done
    PARTITIONS=()
}

mount_additional_partition() {
    local device="$1"
    local mountpoint="$2"

    if [[ "${mountpoint}" = / ]]; then
        log "Skipping root partition" 1>&2
        return 0
    fi

    if [[ "${mountpoint}" != "/"* ]]; then
        log "Skipping ${mountpoint} no valid mountpoint" 1>&2
        return 0
    fi

    if [[ ! -d "/mnt${mountpoint}" ]]; then
        mkdir "/mnt${mountpoint}"
    fi
    print_h1 "Mount ${device} as /mnt${mountpoint}"
    mount "${device}" "/mnt${mountpoint}"
}

get_root_partition_device() {
    for device in "${!CONFIG_MOUNTPOINTS[@]}"; do
        local mountpoint="${CONFIG_MOUNTPOINTS["$device"]}"
        if [[ "$mountpoint" = "/" ]]; then
            echo "$device"
            return 0
        fi
    done
    return 1
}

mount_partitions() {
    print_h0 "Mount partitions"

    local root_partition_device
    root_partition_device=$(get_root_partition_device)
    print_h1 "Mount $root_partition_device as root partition"
    mount "$root_partition_device" /mnt

    for device in "${!CONFIG_MOUNTPOINTS[@]}"; do
        mount_additional_partition "$device" "${CONFIG_MOUNTPOINTS["$device"]}"
    done
}

install_base_packages() {
    print_h0 "Install base packages"
    pacman -Sy --noconfirm reflector
    reflector --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    eval "pacstrap /mnt base linux linux-firmware sudo inetutils networkmanager ${CONFIG[ADDITIONAL_PACKAGES]}"
}

swapon_all_swap_partitions() {
    for device in "${!CONFIG_MOUNTPOINTS[@]}"; do
        local mountpoint="${CONFIG_MOUNTPOINTS["$device"]}"
        if [[ "$mountpoint" = "SWAP" ]]; then
            print_h1 "swapon ${device}"
            swapon "$device"
        fi
    done
}

generate_fstab() {
    print_h0 "Generate fstab file"
    swapon_all_swap_partitions
    genfstab -U /mnt >/mnt/etc/fstab
    cat /mnt/etc/fstab
    swapoff -a
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
    root_partition_device=$(get_root_partition_device)
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
# generic dialogs
################################

menu() {
    local text=$1
    shift 1
    whiptail --menu "$text" "${DIALOG_SIZE[@]}" 20 --title "$TITLE" --cancel-button "$BACK_BUTTON_TEXT" --notags "$@" 3>&1 1>&2 2>&3
}

radiolist() {
    local text=$1
    local height=$2
    shift 2
    whiptail --radiolist "$text" "${DIALOG_SIZE[@]}" "$height" --title "$TITLE" --cancel-button "$BACK_BUTTON_TEXT" "$@" 3>&1 1>&2 2>&3
}

inputbox() {
    local text=$1
    local default_value=$2
    whiptail --inputbox "$text" "${DIALOG_SIZE[@]}" "$default_value" --title "$TITLE" --cancel-button "$BACK_BUTTON_TEXT" 3>&1 1>&2 2>&3
}

confirm() {
    local text=$1
    whiptail --yesno "$text" "${DIALOG_SIZE[@]}" --title "$TITLE" --yes-button "Ok" --no-button "$BACK_BUTTON_TEXT"
}

################################
# wizard
################################

dialog_partition_disk_menu() {
    local -a menu_entries=(
        "dialog_edit_partitions_menu" "Use existing partition layout"
        "dialog_select_disk" "Select a disk and create a new GPT with default partition layout"
    )
    NEXT_WIZARD_STEP=$(menu "Disk Partitioning" "${menu_entries[@]}") || exit 1
}

dialog_select_disk() {
    local -a disks
    mapfile -t disks < <(lsblk -dno TYPE,PATH,SIZE | awk 'BEGIN{OFS="\n";} /disk/ {print $2,$2 $3,"off";}')
    local disk
    NEXT_WIZARD_STEP=dialog_partition_disk_menu
    local text
    text="Select a disk on which the default partition layout will be created\\n$(print_data_lose_warning)"
    if disk=$(radiolist "$text" 18 "${disks[@]}"); then
        NEXT_WIZARD_STEP="dialog_ask_root_size ${disk}"
        if [ -z "$disk" ]; then
            NEXT_WIZARD_STEP=dialog_select_disk
        fi
    fi
}

dialog_ask_root_size() {
    local disk="$1"
    local root_size
    NEXT_WIZARD_STEP="dialog_select_disk ${disk}"
    if root_size=$(inputbox "Enter the root partition size" "50GiB"); then
        NEXT_WIZARD_STEP="dialog_confirm_disk ${disk} ${root_size}"
        if [ -z "$root_size" ]; then
            NEXT_WIZARD_STEP="dialog_ask_root_size ${disk}"
        fi
    fi
}

get_ram_size_in_KiB() {
    local meminfo_file="$1"
    awk '/^MemTotal:/ { print $2"KiB"; }' "$meminfo_file"
}

dialog_confirm_disk() {
    local disk="$1"
    local root_size="$2"

    local efi_size="550MiB"
    local swap_size
    swap_size="$(get_ram_size_in_KiB /proc/meminfo)"

    local text
    read -r -d '' text <<-EOM || true
The following partitions will be created:
 * efi  --> $efi_size
 * swap --> $swap_size (same as RAM size)
 * root --> $root_size
 * home --> remaining disk space

$(print_data_lose_warning "$disk")
EOM
    confirm "$text" &&
        NEXT_WIZARD_STEP="dialog_create_default_partition_layout $disk $efi_size $swap_size $root_size" ||
        NEXT_WIZARD_STEP="dialog_ask_root_size ${disk}"
}

dialog_create_default_partition_layout() {
    local disk=$1
    local efi_size=$2
    local swap_size=$3
    local root_size=$4

    check_if_device_is_mounted "$disk"

    {
        echo -e "XXX\n0\nCreate new GPT on $disk\nXXX"
        sgdisk -Z "$disk"

        echo -e "XXX\n20\nCreate efi partition on $disk\nXXX"
        sgdisk --new=0:0:+"$efi_size" --typecode=0:c12a7328-f81f-11d2-ba4b-00a0c93ec93b "$disk"

        echo -e "XXX\n40\nCreate swap partition on $disk\nXXX"
        sgdisk --new=0:0:+"$swap_size" --typecode=0:0657fd6d-a4ab-43c4-84e5-0933c84b4f4f "$disk"

        echo -e "XXX\n60\nCreate root partition on $disk\nXXX"
        sgdisk --new=0:0:+"$root_size" --typecode=0:4f68bce3-e8cd-4db1-96e7-fbcaf984b709 "$disk"

        echo -e "XXX\n80\nCreate home partition on $disk\nXXX"
        sgdisk --new=0:0:0 --typecode=0:933ac7e1-2eb4-4f13-b844-0e14e2aef915 "$disk"

        echo -e "XXX\n100\nFinished\nXXX"
        sleep 1
    } | whiptail --gauge "Create new GPT" 6 78 0 --title "$TITLE"

    NEXT_WIZARD_STEP=dialog_edit_partitions_menu
}

get_partition_menu_entries() {
    for partition in "${PARTITIONS[@]}"; do
        echo "dialog_edit_partition_menu $partition"
        printf "%-17s %-10s %-17s %-10s ---> %-10s\n" "$partition" "${PARTITION_SIZES["$partition"]}" "${CONFIG_MOUNTPOINTS["$partition"]}" \
            "${PARTITION_FILESYSTEMS["$partition"]}" "${CONFIG_FILESYSTEMS["$partition"]}"
    done
}

dialog_edit_partitions_menu() {
    init_partition_data
    init_config_filesystems
    init_config_mountpoints

    local header
    header=$(printf "%-17s %-10s %-17s %-10s ---> %-10s" "Partition" "Size" "Mountpoint" "current FS" "format FS")
    local -a partition_menu_entries
    mapfile -t partition_menu_entries < <(get_partition_menu_entries)
    local proceed_menu_entry="                            ===> Proceed ===>                            "
    NEXT_WIZARD_STEP=$(menu "$header" "${partition_menu_entries[@]}" "dialog_ask_hostname" "$proceed_menu_entry") ||
        NEXT_WIZARD_STEP=dialog_partition_disk_menu
}

dialog_edit_partition_menu() {
    local partition="$1"
    local -a menut_entires=(
        "dialog_ask_mountpoint $partition" "mountpoint [${CONFIG_MOUNTPOINTS["$partition"]}]"
        "dialog_ask_new_filesystem_type $partition" "filesystem [current: '${PARTITION_FILESYSTEMS["$partition"]}' will be formated to '${CONFIG_FILESYSTEMS["$partition"]}']"
    )
    NEXT_WIZARD_STEP=$(menu "$partition" "${menut_entires[@]}") || NEXT_WIZARD_STEP=dialog_edit_partitions_menu
}

generate_mountpoint_entires() {
    echo ""
    echo "DO NOT MOUNT"
    if [[ ${CONFIG_MOUNTPOINTS["$partition"]} == "" ]]; then
        echo "ON"
    else
        echo "OFF"
    fi
    for mountpoint in "${GUID_MOINTPOINTS[@]}"; do
        echo "$mountpoint"
        echo "$mountpoint"
        if [[ ${CONFIG_MOUNTPOINTS["$partition"]} == "$mountpoint" ]]; then
            echo "ON"
        else
            echo "OFF"
        fi
    done
}

dialog_ask_mountpoint() {
    local partition="$1"
    NEXT_WIZARD_STEP="dialog_edit_partition_menu $partition"
    local -a mountpoints_entries
    mapfile -t mountpoints_entries < <(generate_mountpoint_entires)
    CONFIG_MOUNTPOINTS["$partition"]="$(radiolist "Select a mountpoint for $partition" 22 "--notags" "${mountpoints_entries[@]}")"
}

generate_filesystem_type_entires() {
    echo ""
    echo "DO NOT FORMAT"
    if [[ ${CONFIG_FILESYSTEMS["$partition"]} == "" ]]; then
        echo "ON"
    else
        echo "OFF"
    fi
    for filesystem_type in "${!MKFSCOMMANDS[@]}"; do
        echo "$filesystem_type"
        echo "$filesystem_type"
        if [[ ${CONFIG_FILESYSTEMS["$partition"]} == "$filesystem_type" ]]; then
            echo "ON"
        else
            echo "OFF"
        fi
    done
}

dialog_ask_new_filesystem_type() {
    local partition="$1"
    NEXT_WIZARD_STEP="dialog_edit_partition_menu $partition"
    local -a filesystem_type_entires
    mapfile -t filesystem_type_entires < <(generate_filesystem_type_entires)
    CONFIG_FILESYSTEMS["$partition"]="$(radiolist "Select a filesystem for $partition [current filesystem: ${PARTITION_FILESYSTEMS["$partition"]}]" 22 "--notags" "${filesystem_type_entires[@]}")"
}

dialog_ask_hostname() {
    NEXT_WIZARD_STEP=dialog_ask_username
    CONFIG[HOSTNAME]="$(inputbox "Hostname" "${CONFIG[HOSTNAME]}")" ||
        NEXT_WIZARD_STEP=dialog_edit_partitions_menu
}

dialog_ask_username() {
    NEXT_WIZARD_STEP=dialog_ask_timezone
    local text="Enter a user that will be created. The password must be set at the end of the installation"
    CONFIG[USERNAME]="$(inputbox "$text" "${CONFIG[USERNAME]}")" ||
        NEXT_WIZARD_STEP=dialog_ask_hostname
}

dialog_ask_timezone() {
    local -a timezones
    mapfile -t timezones < <(timedatectl list-timezones | awk -v current="${CONFIG[TIMEZONE]}" 'BEGIN{OFS="\n";} {
        state="off";
        if ( $1 == current ) state="on";
        print $1,"|",state;
    }')
    NEXT_WIZARD_STEP=dialog_ask_additional_packages
    CONFIG[TIMEZONE]="$(radiolist "Select the local timezone" 22 "${timezones[@]}")" ||
        NEXT_WIZARD_STEP=dialog_ask_username
}

dialog_ask_additional_packages() {
    NEXT_WIZARD_STEP=dialog_ask_confirm
    CONFIG[ADDITIONAL_PACKAGES]="$(inputbox "Additional packages that will be installed" "${CONFIG[ADDITIONAL_PACKAGES]}")" || NEXT_WIZARD_STEP=dialog_ask_timezone
}

dialog_ask_confirm() {
    NEXT_WIZARD_STEP=dialog_ask_additional_packages

    local config
    config=$(print_config)
    if confirm "Installation will start after confirmation.\\n\\n$config"; then
        if is_config_valid; then
            install_arch
            exit 0
        fi
        NEXT_WIZARD_STEP=dialog_ask_confirm
    fi
}

run_wizard() {
    local current_step
    while [ -n "$NEXT_WIZARD_STEP" ]; do
        current_step="$NEXT_WIZARD_STEP"
        NEXT_WIZARD_STEP=""
        eval "$current_step"
    done
    echo "Error: No next step specified in '${current_step}'"
    exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_wizard
fi
