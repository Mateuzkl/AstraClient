/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#ifdef FW_RMLUI

#include "rmlimages.h"

#include "game.h"
#include "outfit.h"
#include "spritemanager.h"
#include "thingtype.h"
#include "thingtypemanager.h"

#include <framework/graphics/image.h>
#include <framework/rml/rmlmanager.h>
#include <framework/rml/rmlpixels.h>

namespace
{
    // The sprite file is shared with the map drawing thread: when it is busy the call reports
    // isLoading, so try again for a moment instead of giving up on the sprite.
    ImagePtr spriteImage(const uint32_t spriteId)
    {
        return g_sprites.getSpriteImage(static_cast<int>(spriteId));
    }

    // Same layout as ThingType::getSpriteIndex (classic .dat/.spr assets).
    uint32_t spriteIndex(const ThingTypePtr& type, const int w, const int h, const int l, const int x, const int y, const int z, const int a)
    {
        const int phases = std::max<int>(1, type->getAnimationPhases());
        return ((((((a % phases) * type->getNumPatternZ() + z) * type->getNumPatternY() + y)
                  * type->getNumPatternX() + x) * type->getLayers() + l)
                * type->getHeight() + h) * type->getWidth() + w;
    }

    ImagePtr drawLayer(const ThingTypePtr& type, const int layer, const int x, const int y, const int z)
    {
        const int spriteSize = g_sprites.spriteSize();
        if (type->getWidth() <= 0 || type->getHeight() <= 0 || spriteSize <= 0 ||
            type->getWidth() > 4096 / spriteSize || type->getHeight() > 4096 / spriteSize)
            throw std::runtime_error("RmlUi thing image dimensions are invalid");
        const auto& sprites = type->getSpriteIndices();
        auto image = std::make_shared<Image>(Size(spriteSize * type->getWidth(), spriteSize * type->getHeight()));

        for (int w = 0; w < type->getWidth(); ++w) {
            for (int h = 0; h < type->getHeight(); ++h) {
                const auto index = spriteIndex(type, w, h, layer, x, y, z, 0);
                if (index >= sprites.size())
                    continue;
                if (const auto sprite = spriteImage(sprites[index])) {
                    image->blit(Point(spriteSize * (type->getWidth() - w - 1), spriteSize * (type->getHeight() - h - 1)), sprite);
                }
            }
        }
        return image;
    }

    void blitOver(const ImagePtr& dest, const ImagePtr& source)
    {
        auto& out = dest->getPixels();
        const auto& in = source->getPixels();
        for (size_t i = 0; i + 3 < in.size() && i + 3 < out.size(); i += 4) {
            RmlPixels::over(&out[i], &in[i]);
        }
    }

    // Colors the outfit using its mask layer: yellow = head, red = body, green = legs, blue = feet.
    void colorize(const ImagePtr& image, const ImagePtr& mask, const int head, const int body, const int legs, const int feet)
    {
        const Color colors[4] = { Outfit::getColor(head), Outfit::getColor(body), Outfit::getColor(legs), Outfit::getColor(feet) };
        auto& pixels = image->getPixels();
        const auto& maskPixels = mask->getPixels();

        for (size_t i = 0; i + 3 < pixels.size() && i + 3 < maskPixels.size(); i += 4) {
            if (maskPixels[i + 3] == 0)
                continue;
            const bool r = maskPixels[i] > 0, g = maskPixels[i + 1] > 0, b = maskPixels[i + 2] > 0;
            int part = -1;
            if (r && g && !b) part = 0;
            else if (r && !g && !b) part = 1;
            else if (!r && g && !b) part = 2;
            else if (!r && !g && b) part = 3;
            if (part < 0)
                continue;
            const auto& color = colors[part];
            pixels[i + 0] = static_cast<uint8_t>(pixels[i + 0] * color.r() / 255);
            pixels[i + 1] = static_cast<uint8_t>(pixels[i + 1] * color.g() / 255);
            pixels[i + 2] = static_cast<uint8_t>(pixels[i + 2] * color.b() / 255);
        }
    }

    ImagePtr thingImage(const ThingCategory category, const int id)
    {
        if (id <= 0 || id > 65535 || !g_things.isValidDatId(static_cast<uint16_t>(id), category))
            return nullptr;
        const auto& type = g_things.getThingType(static_cast<uint16_t>(id), category);
        if (!type || type->isNull())
            return nullptr;

        auto image = drawLayer(type, 0, 0, 0, 0);
        for (int layer = 1; layer < type->getLayers(); ++layer)
            blitOver(image, drawLayer(type, layer, 0, 0, 0));
        return image;
    }

    ImagePtr outfitImage(const std::vector<int>& args)
    {
        const auto arg = [&](const size_t i, const int fallback) { return i < args.size() ? args[i] : fallback; };
        const int lookType = arg(0, 0);
        if (lookType <= 0 || lookType > 65535 || !g_things.isValidDatId(static_cast<uint16_t>(lookType), ThingCategoryCreature))
            return nullptr;

        const auto& type = g_things.getThingType(static_cast<uint16_t>(lookType), ThingCategoryCreature);
        if (!type || type->isNull())
            return nullptr;

        const int addons = arg(5, 0) & 3;
        const int direction = std::clamp(arg(6, 2), 0, std::max(0, type->getNumPatternX() - 1));

        ImagePtr image;
        for (int y = 0; y < std::min(3, type->getNumPatternY()); ++y) {
            // pattern y: 0 = base outfit, 1 = first addon, 2 = second addon
            if (y > 0 && !(addons & (1 << (y - 1))))
                continue;

            auto part = drawLayer(type, 0, direction, y, 0);
            if (type->getLayers() > 1)
                colorize(part, drawLayer(type, 1, direction, y, 0), arg(1, 0), arg(2, 0), arg(3, 0), arg(4, 0));

            if (!image)
                image = part;
            else
                blitOver(image, part);
        }
        return image;
    }
}

void registerRmlImageProvider()
{
    g_rml.setAssetsReadyCheck([] {
        return g_things.isDatLoaded() && g_sprites.isLoaded();
    });

    g_rml.setImageProvider([](const std::string_view kind, const std::vector<int>& args) -> ImagePtr {
        if (args.empty())
            return nullptr;

        if (kind == "item")
            return thingImage(ThingCategoryItem, args[0]);
        if (kind == "effect")
            return thingImage(ThingCategoryEffect, args[0]);
        if (kind == "outfit")
            return outfitImage(args);
        return nullptr;
    });
}

#endif
