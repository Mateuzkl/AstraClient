/*
    Copyright 2020 Morgan McGuire & Mara Gagiu.
    Available under the MIT license.
    https://casual-effects.com/research/McGuire2021PixelArt/index.html

    Vendored (MIT) from https://github.com/ITotalJustice/mmpx (c99 port of the
    official C++ benchmark). Header guarded with extern "C" so the C99 .c TU can
    be called from C++ (image.cpp). Pixels are 0xAARRGGBB (ARGB) uint32; dst must
    be exactly (2*srcWidth) x (2*srcHeight).
*/

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void mmpx_scale2x(const uint32_t* srcBuffer, uint32_t* dst, int srcWidth, int srcHeight);

#ifdef __cplusplus
}
#endif
