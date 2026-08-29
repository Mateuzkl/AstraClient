#!/usr/bin/env bash
set -euo pipefail

EXPECTED_EMSCRIPTEN="6.0.8"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_TYPE="${1:-Release}"
BUILD_DIR="${2:-${ROOT_DIR}/build-wasm-${BUILD_TYPE,,}}"

if [[ -z "${EMSDK:-}" ]]; then
  echo "EMSDK is not set. Activate the pinned Emscripten SDK first." >&2
  exit 1
fi
for command_name in emcc emcmake cmake ninja; do
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

emcmake cmake --fresh -S "${ROOT_DIR}" -B "${BUILD_DIR}" -G Ninja \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
cmake --build "${BUILD_DIR}" --parallel
python3 "${ROOT_DIR}/tools/check_browser_assets.py"

echo "AstraClient browser artifacts: ${BUILD_DIR}/dist"
