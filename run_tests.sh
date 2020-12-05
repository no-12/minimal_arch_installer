#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
declare -r PROJECT_DIR
declare -r SHUNIT2_BASE_PATH="${PROJECT_DIR}/shunit2"
declare -r SHUNIT2_PATH="${SHUNIT2_BASE_PATH}/shunit2"
declare -r shunit2_version="2.1.8"
declare -r shunit2_url="https://github.com/kward/shunit2/archive/v${shunit2_version}.tar.gz"

if [ ! -d "$SHUNIT2_BASE_PATH" ]; then
    wget -c "$shunit2_url" -O - | tar -xz -C /tmp
    mv "/tmp/shunit2-${shunit2_version}" "$SHUNIT2_BASE_PATH"
fi

export PROJECT_DIR
export SHUNIT2_PATH

for testfile in "${PROJECT_DIR}"/test/*_test.sh; do
    bash "$testfile"
done
