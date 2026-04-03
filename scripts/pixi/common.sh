#!/usr/bin/env bash
set -euo pipefail

project_root() {
    if [[ -n "${PIXI_PROJECT_ROOT:-}" ]]; then
        printf '%s\n' "${PIXI_PROJECT_ROOT}"
        return
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "${script_dir}/../.." && pwd
}

num_jobs() {
    if [[ -n "${PIXI_JOBS:-}" ]]; then
        printf '%s\n' "${PIXI_JOBS}"
        return
    fi

    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN 2>/dev/null && return
    fi

    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null && return
    fi

    printf '4\n'
}

setup_pixi_env() {
    : "${CONDA_PREFIX:?Run this script via 'pixi run'.}"

    export PULSEVIEW_ROOT
    PULSEVIEW_ROOT="$(project_root)"

    export PIXI_ENV_NAME
    PIXI_ENV_NAME="${PIXI_ENVIRONMENT_NAME:-default}"

    export SIGROK_PREFIX
    SIGROK_PREFIX="${SIGROK_PREFIX:-${PULSEVIEW_ROOT}/.pixi/external/${PIXI_ENV_NAME}}"

    export SIGROK_SOURCE_ROOT
    SIGROK_SOURCE_ROOT="${SIGROK_SOURCE_ROOT:-${PULSEVIEW_ROOT}/.pixi/source-cache}"

    export SIGROK_BUILD_ROOT
    SIGROK_BUILD_ROOT="${SIGROK_BUILD_ROOT:-${PULSEVIEW_ROOT}/.pixi/build/sigrok}"

    export PULSEVIEW_BUILD_DIR
    PULSEVIEW_BUILD_DIR="${PULSEVIEW_BUILD_DIR:-build/debug}"
    if [[ "${PULSEVIEW_BUILD_DIR}" != /* ]]; then
        PULSEVIEW_BUILD_DIR="${PULSEVIEW_ROOT}/${PULSEVIEW_BUILD_DIR}"
    fi

    mkdir -p "${SIGROK_PREFIX}" "${SIGROK_SOURCE_ROOT}" "${SIGROK_BUILD_ROOT}" "${PULSEVIEW_BUILD_DIR}"

    local stale_glibmm_pc="${SIGROK_PREFIX}/lib/pkgconfig/glibmm-2.4.pc"
    if [[ -f "${stale_glibmm_pc}" ]] && grep -q "Compatibility shim mapping glibmm-2.4 to glibmm-2.68" "${stale_glibmm_pc}"; then
        rm -f "${stale_glibmm_pc}"
    fi

    export PATH="${SIGROK_PREFIX}/bin:${CONDA_PREFIX}/bin:${PATH}"
    export PKG_CONFIG_PATH="${SIGROK_PREFIX}/lib/pkgconfig:${CONDA_PREFIX}/lib/pkgconfig:${CONDA_PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    export CMAKE_PREFIX_PATH="${SIGROK_PREFIX}:${CONDA_PREFIX}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"

    if [[ -z "${lt_cv_sys_max_cmd_len:-}" ]] && command -v getconf >/dev/null 2>&1; then
        export lt_cv_sys_max_cmd_len
        lt_cv_sys_max_cmd_len="$(getconf ARG_MAX 2>/dev/null || true)"
    fi

    case "$(uname -s)" in
        Darwin)
            export DYLD_FALLBACK_LIBRARY_PATH="${SIGROK_PREFIX}/lib:${CONDA_PREFIX}/lib${DYLD_FALLBACK_LIBRARY_PATH:+:${DYLD_FALLBACK_LIBRARY_PATH}}"
            ;;
        *)
            export LD_LIBRARY_PATH="${SIGROK_PREFIX}/lib:${CONDA_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
            ;;
    esac
}

download_and_unpack() {
    local name="$1"
    local version="$2"
    local url="$3"
    local archive_name="${url##*/}"
    local archive_path="${SIGROK_SOURCE_ROOT}/${archive_name}"
    local source_dir="${SIGROK_SOURCE_ROOT}/${name}-${version}"

    if [[ ! -f "${archive_path}" ]]; then
        curl -fsSL "${url}" -o "${archive_path}"
    fi

    if [[ ! -d "${source_dir}" ]]; then
        tar -xf "${archive_path}" -C "${SIGROK_SOURCE_ROOT}"
    fi

    printf '%s\n' "${source_dir}"
}

sync_git_source() {
    local name="$1"
    local url="$2"
    local ref="$3"
    local source_dir="${SIGROK_SOURCE_ROOT}/${name}-git"

    if [[ ! -d "${source_dir}/.git" ]]; then
        git clone "${url}" "${source_dir}" >&2
    else
        git -C "${source_dir}" remote set-url origin "${url}"
    fi

    git -C "${source_dir}" fetch --tags origin >&2
    git -C "${source_dir}" checkout --force "${ref}" >&2
    git -C "${source_dir}" clean -fdx >&2

    printf '%s\n' "${source_dir}"
}

build_autotools_source() {
    local name="$1"
    local source_dir="$2"
    shift 2

    local build_dir="${SIGROK_BUILD_ROOT}/${name}"
    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"

    if command -v autoreconf >/dev/null 2>&1 && [[ -f "${source_dir}/configure.ac" || -f "${source_dir}/configure.in" ]]; then
        (
            cd "${source_dir}"
            autoreconf --force --install --verbose
        )
    elif [[ ! -x "${source_dir}/configure" && -x "${source_dir}/autogen.sh" ]]; then
        (
            cd "${source_dir}"
            ./autogen.sh
        )
    fi

    (
        cd "${build_dir}"
        "${source_dir}/configure" --prefix="${SIGROK_PREFIX}" "$@"
        make -j"$(num_jobs)"
        make install
    )
}

build_autotools_project() {
    local name="$1"
    local version="$2"
    local url="$3"
    shift 3

    local source_dir
    source_dir="$(download_and_unpack "${name}" "${version}" "${url}")"

    build_autotools_source "${name}" "${source_dir}" "$@"
}

build_autotools_git_project() {
    local name="$1"
    local url="$2"
    local ref="$3"
    shift 3

    local source_dir
    source_dir="$(sync_git_source "${name}" "${url}" "${ref}")"

    build_autotools_source "${name}" "${source_dir}" "$@"
}
