#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/common.sh"

setup_pixi_env

: "${PULSEVIEW_ENABLE_DECODE:=ON}"
: "${PULSEVIEW_ENABLE_TESTS:=ON}"
: "${PULSEVIEW_ENABLE_STACKTRACE:=OFF}"
: "${PULSEVIEW_BUILD_TYPE:=RelWithDebInfo}"

cmake \
    -S "${PULSEVIEW_ROOT}" \
    -B "${PULSEVIEW_BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE="${PULSEVIEW_BUILD_TYPE}" \
    -DCMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH}" \
    -DENABLE_DECODE="${PULSEVIEW_ENABLE_DECODE}" \
    -DENABLE_TESTS="${PULSEVIEW_ENABLE_TESTS}" \
    -DENABLE_STACKTRACE="${PULSEVIEW_ENABLE_STACKTRACE}"
