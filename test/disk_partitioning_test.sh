#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

set +e

test_get_root_partition_device_match() { (
    local -a partition_strings=(
        "device=/dev/test1;mountpoint=/boot;guid=c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
        "device=/dev/test2;mountpoint=[SWAP];guid=0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
        "device=/dev/test3;mountpoint=/;guid=4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
        "device=/dev/test4;mountpoint=/home;guid=933ac7e1-2eb4-4f13-b844-0e14e2aef915"
    )
    local result
    result=$(get_root_partition_device "${partition_strings[@]}")

    assertEquals "/dev/test3" "$result"
); }

test_get_root_partition_device_no_match() { (
    local -a partition_strings=(
        "number=1;mountpoint=/boot;guid=c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
        "number=2;mountpoint=[SWAP];guid=0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"
    )
    get_root_partition_device "${partition_strings[@]}"
    assertFalse $?
); }

test_get_partition_device_without_number_non_nvm() { (
    local result
    result=$(get_partition_device_without_number /dev/test)
    assertEquals /dev/test "$result"
); }

test_get_partition_device_without_number_nvm() { (
    local result
    result=$(get_partition_device_without_number /dev/nvmtest)
    assertEquals /dev/nvmtestp "$result"
); }

test_get_physical_sector_size_in_KiB() { (
    lsblk() {
        echo "    42"
    }

    local result
    result=$(get_physical_sector_size_in_KiB /dev/test)

    assertEquals 42 "$result"
); }

test_get_ram_size_in_KiB() { (
    local mock_meminfo="${SHUNIT_TMPDIR}/meminfo"
    echo "MemTotal:       16156404 kB" >"$mock_meminfo"

    local result
    result=$(get_ram_size_in_KiB "$mock_meminfo")

    assertEquals 16156404 "$result"
); }

test_create_default_partition_strings() { (
    get_physical_sector_size_in_KiB() {
        echo "1024"
    }
    get_ram_size_in_KiB() {
        echo "4194304"
    }

    local -a result
    mapfile -t result < <(create_default_partition_strings /dev/test /dummy/meminfo)

    assertEquals 4 "${#result[@]}"
    assertEquals "number=1;device=/dev/test1;size=524288;filesystem=vfat;format=true;mountpoint=/boot;guid=c12a7328-f81f-11d2-ba4b-00a0c93ec93b" "${result[0]}"
    assertEquals "number=2;device=/dev/test2;size=4194304;filesystem=swap;format=true;mountpoint=[SWAP];guid=0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" "${result[1]}"
    assertEquals "number=3;device=/dev/test3;size=52428800;filesystem=ext4;format=true;mountpoint=/;guid=4f68bce3-e8cd-4db1-96e7-fbcaf984b709" "${result[2]}"
    assertEquals "number=4;device=/dev/test4;size=0;filesystem=ext4;format=true;mountpoint=/home;guid=933ac7e1-2eb4-4f13-b844-0e14e2aef915" "${result[3]}"
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
