#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

test_CONFIG_MOUNTPOINTS_is_empty_if_there_is_no_mountpoint_mapping_for_the_partitions_guid() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="unkown"

    init_config_mountpoints

    assertEquals "/dev/sda1" "${!CONFIG_MOUNTPOINTS[@]}"
    assertEquals "" "${CONFIG_MOUNTPOINTS["/dev/sda1"]}"
); }

test_CONFIG_MOUNTPOINTS_is_set_to_default_if_partition_has_no_filesystem() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"

    init_config_mountpoints

    assertEquals "/dev/sda1" "${!CONFIG_MOUNTPOINTS[@]}"
    assertEquals "/boot" "${CONFIG_MOUNTPOINTS["/dev/sda1"]}"
); }

test_does_nothing_if_CONFIG_MOUNTPOINTS_already_initialized() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    CONFIG_MOUNTPOINTS["bla"]=blub

    init_config_mountpoints

    assertEquals "bla" "${!CONFIG_MOUNTPOINTS[@]}"
); }

# shellcheck source=shunit2/shunit2
. "${SHUNIT2_PATH}"
