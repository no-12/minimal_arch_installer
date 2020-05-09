#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

set +e

test_get_device_guids() { (
    lsblk() {
        echo "disk /dev/test                                      "
        echo "part /dev/test1 c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
        echo "part /dev/test2 0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
        echo "part /dev/test3 4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
        echo "part /dev/test4 933ac7e1-2eb4-4f13-b844-0e14e2aef915"
    }
    local -A result
    get_device_guids /dev/test result

    assertEquals 4 "${#result[@]}"
    assertEquals "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" "${result["/dev/test1"]}"
    assertEquals "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" "${result["/dev/test2"]}"
    assertEquals "4f68bce3-e8cd-4db1-96e7-fbcaf984b709" "${result["/dev/test3"]}"
    assertEquals "933ac7e1-2eb4-4f13-b844-0e14e2aef915" "${result["/dev/test4"]}"
); }

test_map_disk_guids_to_default_mkfscommands() { (
    get_device_guids() {
        local -n device_guids_mkfscommands_mock="$2"
        device_guids_mkfscommands_mock["/dev/test1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
        # shellcheck disable=SC2034
        device_guids_mkfscommands_mock["/dev/test2"]="0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
    }

    map_disk_guids_to_default_mkfscommands

    assertEquals 2 "${#MKFSCOMMANDS[@]}"
    assertEquals "mkfs.fat -F32" "${MKFSCOMMANDS["/dev/test1"]}"
    assertEquals "mkswap" "${MKFSCOMMANDS["/dev/test2"]}"
); }

test_map_disk_guids_to_default_mointpoints() { (
    get_device_guids() {
        local -n device_guids_mointpoints_mock="$2"
        device_guids_mointpoints_mock["/dev/test1"]="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
        # shellcheck disable=SC2034
        device_guids_mointpoints_mock["/dev/test2"]="0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
    }

    map_disk_guids_to_default_mointpoints

    assertEquals 2 "${#MOUNTPOINTS[@]}"
    assertEquals "/boot" "${MOUNTPOINTS["/dev/test1"]}"
    assertEquals "SWAP" "${MOUNTPOINTS["/dev/test2"]}"
); }

test_get_root_partition_device() { (
    MOUNTPOINTS["/dev/test1"]="/boot"
    MOUNTPOINTS["/dev/test2"]="SWAP"
    MOUNTPOINTS["/dev/test3"]="/"
    MOUNTPOINTS["/dev/test4"]="/home"

    local result
    result=$(get_root_partition_device)

    assertEquals "/dev/test3" "$result"
); }

test_get_root_partition_device_no_root_partition() { (
    MOUNTPOINTS["/dev/test1"]="/boot"
    MOUNTPOINTS["/dev/test2"]="SWAP"
    MOUNTPOINTS["/dev/test3"]="/home"

    local result
    result=$(get_root_partition_device)

    assertEquals 1 "$?"
    assertEquals "" "$result"
); }

test_get_ram_size_in_KiB() { (
    local mock_meminfo="${SHUNIT_TMPDIR}/meminfo"
    echo "MemTotal:       16156404 kB" >"$mock_meminfo"

    local result
    result=$(get_ram_size_in_KiB "$mock_meminfo")

    assertEquals 16156404KiB "$result"
); }

# shellcheck source=shunit2/shunit2
. "${PROJECT_DIR}/shunit2/shunit2"
