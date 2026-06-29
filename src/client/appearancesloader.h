/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
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

#ifndef APPEARANCESLOADER_H
#define APPEARANCESLOADER_H

// Phase 1 P1.2: protobuf parser for Tibia 15.24 appearances.dat.
// Converts Crystal::protobuf::appearances::Appearance entries into ThingType
// objects, writing the result into g_things' per-category vectors using the
// same shape the legacy ThingType::unserialize produces.
//
// The loader is intentionally self-contained: it does not touch the legacy
// loadDat path. P1.4 swaps the call site; P1.2 leaves both paths coexisting.

#include "thingtype.h"

#include <memory>
#include <string>
#include <vector>

// Forward-declare the protobuf types so consumers don't need the generated
// header (which is large) just to talk to the loader.
namespace Crystal {
namespace protobuf {
namespace appearances {
class Appearance;
class AppearanceFlags;
class Appearances;
class FrameGroup;
class SpriteAnimation;
class SpriteInfo;
} // namespace appearances
} // namespace protobuf
} // namespace Crystal

class AppearancesLoader
{
public:
    AppearancesLoader();
    // Destructor declared (not =default-in-class) so the std::unique_ptr<Appearances>
    // can use a forward-declared protobuf type in this header. Defined in the .cpp
    // where appearances.pb.h is in scope.
    ~AppearancesLoader();

    // Load and parse the appearances.dat file. Returns true on success.
    // Writes parsed thingtypes into the per-category vectors of g_things
    // (ThingTypeManager) — same convention as the legacy loader.
    bool load(const std::string& file);

    // Per-category counts, useful for debug/logging.
    int getCategoryCount(ThingCategory category) const;

private:
    // Per-frame-group layout recorded by applyFrameGroup. buildThingType uses it
    // to re-layout m_spritesIndex when an outfit's groups disagree on dims:
    // ThingType::getSpriteIndex indexes ALL phases with a single stride taken
    // from the last group, so divergent groups would scramble sprites otherwise.
    struct FrameGroupLayout
    {
        int layers;
        int patternX;
        int patternY;
        int patternZ;
        int phases;
        int spriteOffset; // first index of this group's block in m_spritesIndex
        int cellW;
        int cellH;
        int realSize;
    };

    bool buildThingType(const Crystal::protobuf::appearances::Appearance& app,
                        ThingCategory category,
                        ThingTypePtr& out);

    void applyFlags(const Crystal::protobuf::appearances::AppearanceFlags& flags,
                    const std::string& name,
                    ThingType& out);

    void applyFrameGroup(const Crystal::protobuf::appearances::FrameGroup& fg,
                         ThingCategory category,
                         ThingType& out,
                         int& totalSpritesCount,
                         std::vector<FrameGroupLayout>& groupLayouts);

    AnimatorPtr buildAnimator(const Crystal::protobuf::appearances::SpriteAnimation& anim,
                              int phases);

    std::unique_ptr<Crystal::protobuf::appearances::Appearances> m_appearances;
    int m_categoryCounts[ThingLastCategory] = { 0, 0, 0, 0 };
};

#endif
