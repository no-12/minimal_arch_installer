#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

test_all_fields_empty() { (
    CONFIG[ADDITIONAL_PACKAGES]=""
    CONFIG[TIMEZONE]=""

    local expected="+------------------+------------+----------+----------+------------------+
| partition        | size       | curr. FS | new FS   | mountpoint       |
+------------------+------------+----------+----------+------------------+
+------------------+------------+----------+----------+------------------+


Config:

ADDITIONAL_PACKAGES  --> *****NOT SET*****
HOSTNAME             --> *****NOT SET*****
TIMEZONE             --> *****NOT SET*****
USERNAME             --> *****NOT SET*****"
    assertEquals "$expected" "$(print_config)"
); }

test_all_fields_set() { (
    local partition1="/dev/sda1"
    local partition2="/dev/sda123456789"
    PARTITIONS=("$partition1" "$partition2")

    PARTITION_SIZES["$partition1"]="550 MB"
    PARTITION_FILESYSTEMS["$partition1"]="vfat"
    CONFIG_FILESYSTEMS["$partition1"]=""
    CONFIG_MOUNTPOINTS["$partition1"]=""

    PARTITION_SIZES["$partition2"]="123456789 GB"
    PARTITION_FILESYSTEMS["$partition2"]="ext123456789"
    CONFIG_FILESYSTEMS["$partition2"]="ext123456789"
    CONFIG_MOUNTPOINTS["$partition2"]="/123456789123456789"

    CONFIG[ADDITIONAL_PACKAGES]="vim"
    CONFIG[HOSTNAME]="hostname"
    CONFIG[TIMEZONE]="timezone"
    CONFIG[USERNAME]="user"

    local expected="+------------------+------------+----------+----------+------------------+
| partition        | size       | curr. FS | new FS   | mountpoint       |
+------------------+------------+----------+----------+------------------+
| /dev/sda1        | 550 MB     | vfat     |          |                  |
| /dev/sda12345678 | 123456789  | ext12345 | ext12345 | /123456789123456 |
+------------------+------------+----------+----------+------------------+


Config:

ADDITIONAL_PACKAGES  --> vim
HOSTNAME             --> hostname
TIMEZONE             --> timezone
USERNAME             --> user"
    assertEquals "$expected" "$(print_config)"
); }

# shellcheck source=shunit2/shunit2
. "${SHUNIT2_PATH}"
