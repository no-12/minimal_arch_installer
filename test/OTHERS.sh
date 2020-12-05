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
