#!/usr/bin/env bash
set -euo pipefail

EXPECTED_EMSCRIPTEN="6.0.8"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILE="flat"
BUILD_TYPE="Release"
BUILD_DIR=""
THINGS_DIR=""
JOBS=""
EXTRA_CMAKE_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  browser/build-wasm.sh [Release|Debug|RelWithDebInfo] [build-dir] [extra-cmake-args...]
  browser/build-wasm.sh --profile <flat|desktop|mobile|all> [--type <Release|Debug|RelWithDebInfo>] [--build-dir <dir>] [--things-dir <dir>] [--jobs <N>] [-- extra-cmake-args...]

Profiles:
  flat     Legacy single-profile Desktop Full in <build-dir>/dist (default for CI compatibility)
  desktop  Dual-profile Desktop Full in <build-dir>/dist/desktop (+ shared launcher)
  mobile   Dual-profile Mobile Lite in <build-dir>/dist/mobile (+ shared launcher & paged Tibia.spr)
  all      Unified dual-profile build: Desktop Full + Mobile Lite under <build-dir>/dist
EOF
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"; shift 2 ;;
    --type|--build-type)
      BUILD_TYPE="${2:-}"; shift 2 ;;
    --build-dir)
      BUILD_DIR="${2:-}"; shift 2 ;;
    --things-dir)
      THINGS_DIR="${2:-}"; shift 2 ;;
    --jobs|-j)
      JOBS="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; EXTRA_CMAKE_ARGS+=("$@"); break ;;
    -D*)
      EXTRA_CMAKE_ARGS+=("$1"); shift ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -ge 1 ]]; then
  BUILD_TYPE="${POSITIONAL[0]}"
fi
if [[ ${#POSITIONAL[@]} -ge 2 ]]; then
  BUILD_DIR="${POSITIONAL[1]}"
fi
if [[ ${#POSITIONAL[@]} -ge 3 ]]; then
  EXTRA_CMAKE_ARGS+=("${POSITIONAL[@]:2}")
fi

case "${PROFILE}" in
  flat|desktop|mobile|all) ;;
  *)
    echo "Invalid --profile '${PROFILE}'. Expected flat, desktop, mobile, or all." >&2
    exit 1 ;;
esac

if [[ -z "${BUILD_DIR}" ]]; then
  if [[ "${PROFILE}" == "flat" ]]; then
    BUILD_DIR="${ROOT_DIR}/build-wasm-${BUILD_TYPE,,}"
  else
    BUILD_DIR="${ROOT_DIR}/build-wasm-${PROFILE}-${BUILD_TYPE,,}"
  fi
fi

if [[ -z "${EMSDK:-}" ]]; then
  echo "EMSDK is not set. Activate the pinned Emscripten SDK first." >&2
  exit 1
fi
for command_name in emcc emcmake cmake ninja python3 node; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
done

EMCC_VERSION="$(emcc --version | head -n 1)"
if [[ "${EMCC_VERSION}" != *"${EXPECTED_EMSCRIPTEN}"* ]]; then
  echo "Expected Emscripten ${EXPECTED_EMSCRIPTEN}, got: ${EMCC_VERSION}" >&2
  exit 1
fi

# Auto-enable ccache when installed (preserves existing EM_COMPILER_WRAPPER if set).
if [[ -z "${EM_COMPILER_WRAPPER:-}" ]] && command -v ccache >/dev/null 2>&1; then
  export EM_COMPILER_WRAPPER=ccache
fi

# Resource-safe bounded parallelism (especially on WSL2).
IS_WSL=0
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
  IS_WSL=1
fi
if [[ -z "${JOBS}" ]]; then
  TOTAL_CPUS="$(nproc 2>/dev/null || echo 4)"
  if [[ "${IS_WSL}" -eq 1 ]]; then
    JOBS=$(( TOTAL_CPUS / 2 ))
    [[ "${JOBS}" -lt 2 ]] && JOBS=2
    [[ "${JOBS}" -gt 4 ]] && JOBS=4
  else
    JOBS="${TOTAL_CPUS}"
  fi
fi

run_build_cmd() {
  if [[ "${IS_WSL}" -eq 1 ]] && command -v nice >/dev/null 2>&1; then
    nice -n 10 "$@"
  else
    "$@"
  fi
}

build_one() {
  local prof="$1"
  local bdir="$2"
  local dist_root="$3"
  local subdir="$4"
  local args=(
    "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
    "-DASTRA_WASM_PROFILE=${prof}"
    "-DASTRA_WASM_DIST_DIR=${dist_root}"
    "-DASTRA_WASM_OUTPUT_SUBDIR=${subdir}"
  )
  if [[ -n "${THINGS_DIR}" ]]; then
    args+=("-DASTRA_WASM_THINGS_DIR=${THINGS_DIR}")
  fi
  if [[ ${#EXTRA_CMAKE_ARGS[@]} -gt 0 ]]; then
    args+=("${EXTRA_CMAKE_ARGS[@]}")
  fi

  echo "==> Configuring AstraClient Web (${prof}, subdir='${subdir:-flat}', jobs=${JOBS}) in ${bdir}"
  if [[ -f "${bdir}/CMakeCache.txt" ]]; then
    emcmake cmake -S "${ROOT_DIR}" -B "${bdir}" -G Ninja "${args[@]}"
  else
    emcmake cmake --fresh -S "${ROOT_DIR}" -B "${bdir}" -G Ninja "${args[@]}"
  fi
  run_build_cmd cmake --build "${bdir}" --parallel "${JOBS}"
}

DIST_ROOT="${BUILD_DIR}/dist"
if [[ "${PROFILE}" == "flat" ]]; then
  build_one "desktop" "${BUILD_DIR}" "${DIST_ROOT}" ""
elif [[ "${PROFILE}" == "desktop" ]]; then
  build_one "desktop" "${BUILD_DIR}/desktop-obj" "${DIST_ROOT}" "desktop"
elif [[ "${PROFILE}" == "mobile" ]]; then
  build_one "mobile" "${BUILD_DIR}/mobile-obj" "${DIST_ROOT}" "mobile"
elif [[ "${PROFILE}" == "all" ]]; then
  build_one "desktop" "${BUILD_DIR}/desktop-obj" "${DIST_ROOT}" "desktop"
  build_one "mobile" "${BUILD_DIR}/mobile-obj" "${DIST_ROOT}" "mobile"
fi

python3 "${ROOT_DIR}/tools/check_browser_assets.py"

echo "AstraClient browser artifacts (${PROFILE}): ${DIST_ROOT}"
