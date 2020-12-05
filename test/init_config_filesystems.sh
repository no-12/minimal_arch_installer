#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

test_CONFIG_FILESYSTEMS_is_empty_if_partition_already_has_a_filesystem() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    PARTITION_FILESYSTEMS["/dev/sda1"]="vfat"

    init_config_filesystems

    assertEquals "/dev/sda1" "${!CONFIG_FILESYSTEMS[@]}"
    assertEquals "" "${CONFIG_FILESYSTEMS["/dev/sda1"]}"
); }

test_CONFIG_FILESYSTEMS_is_set_to_default_if_partition_has_no_filesystem() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    PARTITION_FILESYSTEMS["/dev/sda1"]=""

    init_config_filesystems

    assertEquals "/dev/sda1" "${!CONFIG_FILESYSTEMS[@]}"
    assertEquals "vfat" "${CONFIG_FILESYSTEMS["/dev/sda1"]}"
); }

test_does_nothing_if_CONFIG_FILESYSTEMS_already_initialized() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    PARTITION_FILESYSTEMS["/dev/sda1"]="vfat"
    CONFIG_FILESYSTEMS["bla"]=blub

    init_config_filesystems

    assertEquals "bla" "${!CONFIG_FILESYSTEMS[@]}"
); }

# shellcheck source=shunit2/shunit2
. "${SHUNIT2_PATH}"
