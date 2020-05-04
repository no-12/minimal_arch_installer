#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

set +e

test_get_partition_guids() { (
    lsblk() {
        echo "disk /dev/test                                      "
        echo "part /dev/test1 c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
        echo "part /dev/test2 0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
        echo "part /dev/test3 4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
        echo "part /dev/test4 933ac7e1-2eb4-4f13-b844-0e14e2aef915"
    }
    local -a result
    mapfile -t result < <(get_partition_guids /dev/test)

    assertEquals 4 "${#result[@]}"
    assertEquals "device=/dev/test1;guid=c12a7328-f81f-11d2-ba4b-00a0c93ec93b" "${result[0]}"
    assertEquals "device=/dev/test2;guid=0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" "${result[1]}"
    assertEquals "device=/dev/test3;guid=4f68bce3-e8cd-4db1-96e7-fbcaf984b709" "${result[2]}"
    assertEquals "device=/dev/test4;guid=933ac7e1-2eb4-4f13-b844-0e14e2aef915" "${result[3]}"
); }

test_map_mointpoints_to_devices() { (
    get_partition_guids() {
        echo "device=/dev/test1;guid=c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
        echo "device=/dev/test2;guid=0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
        echo "device=/dev/test3;guid=4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
        echo "device=/dev/test4;guid=933ac7e1-2eb4-4f13-b844-0e14e2aef915"
    }
    local result
    result=$(map_mointpoints_to_devices /dev/test)

    assertEquals "/boot=/dev/test1;SWAP=/dev/test2;/=/dev/test3;/home=/dev/test4;" "$result"
); }

test_get_ram_size_in_KiB() { (
    local mock_meminfo="${SHUNIT_TMPDIR}/meminfo"
    echo "MemTotal:       16156404 kB" >"$mock_meminfo"

    local result
    result=$(get_ram_size_in_KiB "$mock_meminfo")

    assertEquals 16156404KiB "$result"
); }

test_convert_string_to_map() { (
    local -A result
    convert_string_to_map "device=/dev/test1;size=524288;filesystem=vfat;mountpoint=/boot;guid=c12a7328-f81f-11d2-ba4b-00a0c93ec93b" result

    assertEquals 5 "${#result[@]}"
    assertEquals /dev/test1 "${result[device]}"
    assertEquals 524288 "${result[size]}"
    assertEquals vfat "${result[filesystem]}"
    assertEquals /boot "${result[mountpoint]}"
    assertEquals c12a7328-f81f-11d2-ba4b-00a0c93ec93b "${result[guid]}"
); }

# shellcheck source=shunit2/shunit2
. "${PROJECT_DIR}/shunit2/shunit2"
