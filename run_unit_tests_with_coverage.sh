#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
kcov --include-path="${SCRIPT_DIR}/mai.sh" "${SCRIPT_DIR}/test_coverage" "${SCRIPT_DIR}/run_unit_tests.sh"
