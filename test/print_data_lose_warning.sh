#!/usr/bin/env bash
# shellcheck source=mai.sh
. "${PROJECT_DIR}/mai.sh"

test_default_message() { (
    local expected="
                     +-------------------------------+
                     | WARNING: All data on          |
                     |          this disk            |
                     |          will be lost forever |
                     +-------------------------------+"
    assertEquals "$expected" "$(print_data_lose_warning)"
); }

test_long_message() { (
    local expected="
                     +-------------------------------+
                     | WARNING: All data on          |
                     |          blub-blub-blub-blub- |
                     |          will be lost forever |
                     +-------------------------------+"
    assertEquals "$expected" "$(print_data_lose_warning blub-blub-blub-blub-blub)"
); }

# shellcheck source=shunit2/shunit2
. "${SHUNIT2_PATH}"
