#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Shared env wiring for pixi-driven source builds.
source "${script_dir}/common.sh"

setup_pixi_env

export PYTHON="${CONDA_PREFIX}/bin/python"
export PYTHON3="${CONDA_PREFIX}/bin/python3"

LIBSERIALPORT_VERSION="${LIBSERIALPORT_VERSION:-0.1.1}"
LIBSIGROKDECODE_REF="${LIBSIGROKDECODE_REF:-71f4514}"
LIBSIGROKDECODE_GIT_URL="${LIBSIGROKDECODE_GIT_URL:-git://sigrok.org/libsigrokdecode}"
LIBSIGROK_VERSION="${LIBSIGROK_VERSION:-0.5.2}"
SIGROK_FIRMWARE_FX2LAFW_VERSION="${SIGROK_FIRMWARE_FX2LAFW_VERSION:-0.1.7}"

install_fx2lafw_firmware() {
    local firmware_dir="${SIGROK_PREFIX}/share/sigrok-firmware"
    local bundle_dir

    bundle_dir="$(download_and_unpack \
        "sigrok-firmware-fx2lafw-bin" \
        "${SIGROK_FIRMWARE_FX2LAFW_VERSION}" \
        "https://sigrok.org/download/binary/sigrok-firmware-fx2lafw/sigrok-firmware-fx2lafw-bin-${SIGROK_FIRMWARE_FX2LAFW_VERSION}.tar.gz")"

    mkdir -p "${firmware_dir}"
    cp -f "${bundle_dir}"/*.fw "${firmware_dir}/"
}

prune_stale_libsigrokdecode_decoders() {
    local source_decoders_dir="${SIGROK_SOURCE_ROOT}/libsigrokdecode-git/decoders"
    local installed_decoders_dir="${SIGROK_PREFIX}/share/libsigrokdecode/decoders"
    local installed_decoder_dir
    local decoder_name

    [[ -d "${source_decoders_dir}" && -d "${installed_decoders_dir}" ]] || return

    while IFS= read -r -d '' installed_decoder_dir; do
        decoder_name="${installed_decoder_dir##*/}"
        if [[ ! -d "${source_decoders_dir}/${decoder_name}" ]]; then
            rm -rf "${installed_decoder_dir}"
        fi
    done < <(find "${installed_decoders_dir}" -mindepth 1 -maxdepth 1 -type d -print0)
}

libsigrokdecode_supports_logic_output() {
    local header="${SIGROK_PREFIX}/include/libsigrokdecode/libsigrokdecode.h"
    [[ -f "${header}" ]] && grep -q "SRD_OUTPUT_LOGIC" "${header}"
}

if ! pkg-config --exists libserialport; then
    build_autotools_project \
        "libserialport" \
        "${LIBSERIALPORT_VERSION}" \
        "https://sigrok.org/download/source/libserialport/libserialport-${LIBSERIALPORT_VERSION}.tar.gz"
fi

if [[ ! -f "${SIGROK_PREFIX}/share/sigrok-firmware/fx2lafw-saleae-logic.fw" ]]; then
    install_fx2lafw_firmware
fi

if ! pkg-config --exists libsigrokdecode || ! libsigrokdecode_supports_logic_output; then
    # PulseView expects the newer logic-output API from libsigrokdecode master,
    # and libsigrokdecode still does not probe python3-embed.pc correctly on
    # pixi/conda, so we pin a known-good upstream snapshot and inject the embed
    # linker flags explicitly.
    export LIBSIGROKDECODE_CFLAGS
    LIBSIGROKDECODE_CFLAGS="$(pkg-config --cflags 'glib-2.0 python3-embed')"

    export LIBSIGROKDECODE_LIBS
    LIBSIGROKDECODE_LIBS="$(pkg-config --libs 'glib-2.0 python3-embed')"

    build_autotools_git_project \
        "libsigrokdecode" \
        "${LIBSIGROKDECODE_GIT_URL}" \
        "${LIBSIGROKDECODE_REF}"

    unset LIBSIGROKDECODE_CFLAGS
    unset LIBSIGROKDECODE_LIBS
fi

prune_stale_libsigrokdecode_decoders

if ! pkg-config --exists libsigrokcxx; then
    build_autotools_project \
        "libsigrok" \
        "${LIBSIGROK_VERSION}" \
        "https://sigrok.org/download/source/libsigrok/libsigrok-${LIBSIGROK_VERSION}.tar.gz" \
        --disable-java \
        --disable-ruby
fi

pkg-config --modversion libserialport
pkg-config --modversion libsigrokdecode
pkg-config --modversion libsigrokcxx
