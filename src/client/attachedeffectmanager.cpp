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
#include "attachedeffectmanager.h"
#include "thingtypemanager.h"
#include <framework/graphics/texturemanager.h>
#include <framework/core/resourcemanager.h>

AttachedEffectManager g_attachedEffects;

AttachedEffectPtr AttachedEffectManager::registerByThing(uint16_t id, const std::string& name,
                                                        uint16_t thingId, ThingCategory category)
{
    if (!id || !thingId || category >= ThingLastCategory || m_prototypes.count(id)) {
        g_logger.warning(stdext::format("Cannot register attached effect %u: duplicate/invalid ID or DAT category", id));
        return nullptr;
    }
    // Modules register before a DAT is selected. Runtime clones validate against
    // the currently loaded DAT, not against startup's empty thing table.
    auto effect = std::make_shared<AttachedEffect>();
    effect->m_prototype = true;
    effect->m_id = id;
    effect->m_thingId = thingId;
    effect->m_category = category;
    effect->setName(name);
    m_prototypes.emplace(id, effect);
    return effect;
}

AttachedEffectPtr AttachedEffectManager::registerByImage(uint16_t id, const std::string& name,
                                                        const std::string& path, bool smooth)
{
    if (!id || path.empty() || m_prototypes.count(id))
        return nullptr;
    const auto texture = g_textures.getTexture(path);
    if (!texture) {
        g_logger.warning(stdext::format("Attached effect %u: missing image %s", id, g_resources.resolvePath(path)));
        return nullptr;
    }
    // Texture manager owns/cache-shares PNG/APNG; playback is instance-local.
    auto effect = std::make_shared<AttachedEffect>();
    effect->m_prototype = true;
    effect->m_id = id;
    effect->m_category = ThingExternalTexture;
    effect->m_texture = texture;
    effect->m_config.smooth = smooth;
    effect->setName(name);
    m_prototypes.emplace(id, effect);
    return effect;
}

AttachedEffectPtr AttachedEffectManager::getById(uint16_t id)
{
    const auto it = m_prototypes.find(id);
    if (it == m_prototypes.end() || !it->second->isValid()) {
        g_logger.warning(stdext::format("Unknown/unavailable attached effect %u for the loaded assets", id));
        return nullptr;
    }
    return it->second->clone();
}

void AttachedEffectManager::remove(uint16_t id) { m_prototypes.erase(id); }
void AttachedEffectManager::clear() { m_prototypes.clear(); }
