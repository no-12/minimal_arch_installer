#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

oneTimeSetUp() {
    lsblk() {
        echo "disk /dev/sda   476.9G
part /dev/sda1   550M c12a7328-f81f-11d2-ba4b-00a0c93ec93b vfat
part /dev/sda2  15.4G 0fc63daf-8483-4772-8e79-3d69d8477de4 ext4"
    }
}

test_all_maps_are_initialized() { (
    init_partition_data

    assertEquals "/dev/sda1 /dev/sda2" "${PARTITIONS[*]}"

    assertEquals "550M" "${PARTITION_SIZES["/dev/sda1"]}"
    assertEquals "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" "${PARTITION_GUIDS["/dev/sda1"]}"
    assertEquals "vfat" "${PARTITION_FILESYSTEMS["/dev/sda1"]}"

    assertEquals "15.4G" "${PARTITION_SIZES["/dev/sda2"]}"
    assertEquals "0fc63daf-8483-4772-8e79-3d69d8477de4" "${PARTITION_GUIDS["/dev/sda2"]}"
    assertEquals "ext4" "${PARTITION_FILESYSTEMS["/dev/sda2"]}"
); }

test_does_nothing_if_CONFIG_FILESYSTEMS_already_initialized() { (
    PARTITIONS=("bla")

    init_partition_data

    assertEquals "bla" "${PARTITIONS[*]}"
); }

# shellcheck source=shunit2/shunit2
. "${SHUNIT2_PATH}"
