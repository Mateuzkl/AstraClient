#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
ndk=${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to NDK r28c}
out=${1:?Pass an output directory outside the source tree}
mkdir -p "$out"
for triple in aarch64-linux-android24 armv7a-linux-androideabi24; do
    for source in cpp23/standard rendering/command_pool; do
        object="$out/$triple-${source##*/}.o"
        "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/$triple-clang++" \
            -std=c++23 -I"$repo/src" -c "$repo/tests/$source.cpp" -o "$object"
        "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf" -h "$object" | grep -E 'Class:|Machine:'
    done
done
