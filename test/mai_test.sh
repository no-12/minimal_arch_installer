#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

set +e

oneTimeSetUp() {
    log() {
        return
    }
}

test_generate_file() { (
    filepath="${SHUNIT_TMPDIR}/test_generate_file"

    local result
    result=$(generate_file "$filepath" "test content")

    assertEquals "test content" "$result"
    assertEquals "test content" "$(cat "$filepath")"
); }

test_is_device_mounted_not_mounted_device() { (
    is_device_mounted /not_mounted_device
    assertFalse $?
); }

test_is_device_mounted_mounted_device() { (
    is_device_mounted proc
    assertTrue $?
); }

test_get_default_filesystem_type_all_known_guid() { (
    for guid in "${!GUID_DEFAULT_FILESYSTEM[@]}"; do
        assertContains "GUID: $guid" "(vfat swap)" "$(get_default_filesystem_type "$guid")"
    done
); }

test_get_default_filesystem_type_unknown_guid() { (
    assertEquals "ext4" "$(get_default_filesystem_type "unkown_guid")"
); }

test_init_partition_data() { (
    lsblk() {
        echo "disk /dev/sda   476.9G
part /dev/sda1   550M c12a7328-f81f-11d2-ba4b-00a0c93ec93b vfat
part /dev/sda2  15.4G 0fc63daf-8483-4772-8e79-3d69d8477de4 ext4"
    }

    init_partition_data

    assertEquals "/dev/sda1 /dev/sda2" "${PARTITIONS[*]}"

    assertEquals "550M" "${PARTITION_SIZES["/dev/sda1"]}"
    assertEquals "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" "${PARTITION_GUIDS["/dev/sda1"]}"
    assertEquals "vfat" "${PARTITION_FILESYSTEMS["/dev/sda1"]}"

    assertEquals "15.4G" "${PARTITION_SIZES["/dev/sda2"]}"
    assertEquals "0fc63daf-8483-4772-8e79-3d69d8477de4" "${PARTITION_GUIDS["/dev/sda2"]}"
    assertEquals "ext4" "${PARTITION_FILESYSTEMS["/dev/sda2"]}"
); }

test_init_partition_data_does_nothing_if_CONFIG_FILESYSTEMS_already_initialized() { (
    lsblk() {
        echo "disk /dev/sda   476.9G
part /dev/sda1   550M c12a7328-f81f-11d2-ba4b-00a0c93ec93b vfat
part /dev/sda2  15.4G 0fc63daf-8483-4772-8e79-3d69d8477de4 ext4"
    }
    PARTITIONS=("bla")

    init_partition_data

    assertEquals "bla" "${PARTITIONS[*]}"
    assertNull "${PARTITION_SIZES[*]}"
    assertNull "${PARTITION_GUIDS[*]}"
    assertNull "${PARTITION_FILESYSTEMS[*]}"
); }

test_init_config_filesystems_does_nothing_if_CONFIG_FILESYSTEMS_already_initialized() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    PARTITION_FILESYSTEMS["/dev/sda1"]="vfat"
    CONFIG_FILESYSTEMS["bla"]=blub

    init_config_filesystems

    assertEquals "bla" "${!CONFIG_FILESYSTEMS[@]}"
); }

test_init_config_filesystems_CONFIG_FILESYSTEMS_is_empty_if_partition_already_has_a_filesystem() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    PARTITION_FILESYSTEMS["/dev/sda1"]="vfat"

    init_config_filesystems

    assertEquals "/dev/sda1" "${!CONFIG_FILESYSTEMS[@]}"
    assertNull "${CONFIG_FILESYSTEMS["/dev/sda1"]}"
); }

test_init_config_filesystems_CONFIG_FILESYSTEMS_is_set_to_default_if_partition_has_no_filesystem() { (
    PARTITIONS=("/dev/sda1")
    PARTITION_GUIDS["/dev/sda1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    PARTITION_FILESYSTEMS["/dev/sda1"]=""

    init_config_filesystems

    assertEquals "/dev/sda1" "${!CONFIG_FILESYSTEMS[@]}"
    assertEquals "vfat" "${CONFIG_FILESYSTEMS["/dev/sda1"]}"
); }

test_get_root_partition_device() { (
    CONFIG_MOUNTPOINTS["/dev/test1"]="/boot"
    CONFIG_MOUNTPOINTS["/dev/test2"]="SWAP"
    CONFIG_MOUNTPOINTS["/dev/test3"]="/"
    CONFIG_MOUNTPOINTS["/dev/test4"]="/home"

    local result
    result=$(get_root_partition_device)

    assertEquals "/dev/test3" "$result"
); }

test_get_root_partition_device_no_root_partition() { (
    CONFIG_MOUNTPOINTS["/dev/test1"]="/boot"
    CONFIG_MOUNTPOINTS["/dev/test2"]="SWAP"
    CONFIG_MOUNTPOINTS["/dev/test3"]="/home"

    local result
    result=$(get_root_partition_device)

    assertEquals 1 "$?"
    assertEquals "" "$result"
); }

test_get_ram_size_in_KiB() { (
    local mock_meminfo_file="${SHUNIT_TMPDIR}/meminfo"
    echo "MemTotal:       16156404 kB" >"$mock_meminfo_file"

    local result
    result=$(get_ram_size_in_KiB "$mock_meminfo_file")

    assertEquals 16156404KiB "$result"
); }

# shellcheck source=shunit2/shunit2
. "${SHUNIT2_PATH}"
