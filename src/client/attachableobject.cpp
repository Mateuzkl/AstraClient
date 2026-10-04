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
#include "attachableobject.h"
#include "attachedeffect.h"
#include <framework/luaengine/luainterface.h>

AttachableObject& AttachableObject::operator=(const AttachableObject& other)
{
    if (this != &other)
        clearAttachedEffects(true);
    return *this;
}

AttachableObject::~AttachableObject()
{
    // No shared_from_this or Lua callbacks during destruction.
    clearAttachedEffects(true);
}

const std::vector<AttachedEffectPtr>& AttachableObject::getAttachedEffects() const
{
    static const std::vector<AttachedEffectPtr> empty;
    return m_attachmentData ? m_attachmentData->effects : empty;
}

bool AttachableObject::hasAttachedEffects() const
{
    return m_attachmentData && !m_attachmentData->effects.empty();
}

void AttachableObject::attachEffect(const AttachedEffectPtr& requested)
{
    if (!requested || m_clearingAttachments)
        return;
    // Prototypes never become runtime owners; bound instances cannot couple owners.
    auto effect = !requested->m_prototype && requested->m_owner.expired() ? requested : requested->clone();
    if (!effect || !effect->isValid())
        return;
    // Only registered protocol IDs are idempotent; ad-hoc effects have ID zero.
    if (effect->getId() != 0 && getAttachedEffectById(effect->getId()))
        return;
    if (!m_attachmentData)
        m_attachmentData = std::make_unique<Data>();
    m_attachmentData->effects.push_back(effect);
    effect->start(std::static_pointer_cast<AttachableObject>(shared_from_this()));
    onAttachedEffectsChanged();
    effect->callLuaField("onAttach", asLuaObject());
}

bool AttachableObject::detachEffect(const AttachedEffectPtr& effect)
{
    if (!effect || !hasAttachedEffects())
        return false;
    auto& effects = m_attachmentData->effects;
    const auto it = std::find(effects.begin(), effects.end(), effect);
    if (it == effects.end())
        return false;
    // Keep the argument alive even if it aliases an element of the vector.
    const auto detached = *it;
    effects.erase(it);
    detached->stop();
    onAttachedEffectsChanged();
    detached->callLuaField("onDetach", asLuaObject());
    return true;
}

bool AttachableObject::detachEffectById(uint16_t id)
{
    return detachEffect(getAttachedEffectById(id));
}

AttachedEffectPtr AttachableObject::getAttachedEffectById(uint16_t id)
{
    for (const auto& effect : getAttachedEffects())
        if (effect->getId() == id)
            return effect;
    return nullptr;
}

void AttachableObject::clearAttachedEffects(bool ignoreLuaEvent)
{
    if (!hasAttachedEffects())
        return;
    const bool wasClearing = m_clearingAttachments;
    m_clearingAttachments = true;
    auto effects = std::move(m_attachmentData->effects);
    m_attachmentData->effects.clear();
    for (const auto& effect : effects)
        effect->stop();
    onAttachedEffectsChanged();
    if (!ignoreLuaEvent)
        for (const auto& effect : effects)
            effect->callLuaField("onDetach", asLuaObject());
    m_clearingAttachments = wasClearing;
}

void AttachableObject::clearTemporaryAttachedEffects()
{
    const auto effects = getAttachedEffects(); // snapshot: callbacks can mutate owner
    for (const auto& effect : effects)
        if (!effect->isPermanent())
            detachEffect(effect);
}

void AttachableObject::clearPermanentAttachedEffects()
{
    const auto effects = getAttachedEffects();
    for (const auto& effect : effects)
        if (effect->isPermanent())
            detachEffect(effect);
}

bool AttachableObject::isOwnerHidden() const
{
    return isAttachedOwnerHidden(false);
}

bool AttachableObject::isAttachedOwnerHidden(bool ui) const
{
    for (const auto& effect : getAttachedEffects())
        if (effect->hidesOwnerTree(ui))
            return true;
    return false;
}

bool AttachableObject::isAttachedWalkAnimationDisabled() const
{
    for (const auto& effect : getAttachedEffects())
        if (!effect->isExpired() && effect->isDisabledWalkAnimation())
            return true;
    return false;
}

AttachedEffectPtr AttachableObject::getAttachedTransformation(bool ui) const
{
    for (auto it = getAttachedEffects().rbegin(); it != getAttachedEffects().rend(); ++it)
        if ((*it)->isTransform() && !(*it)->isExpired() &&
            (!ui || (*it)->canDrawOnUI()) && (*it)->getThingCategory() == ThingCategoryCreature &&
            (*it)->getSourceThingType())
            return *it;
    return nullptr;
}

void AttachableObject::drawAttachedEffects(const Point& originalDest, const Point& movingDest,
                                           Otc::Direction direction, bool onTop,
                                           LightView* lightView, bool ui, bool animate)
{
    // No Lua or callbacks from draw; expiration is a single cancellable event.
    if (!hasAttachedEffects())
        return;
    // Six owner-local draw orders; never reorder effects across map tiles.
    for (int order = 0; order <= 5; ++order)
        for (const auto& effect : getAttachedEffects())
            if (effect->getDrawOrder() == order)
                effect->draw(originalDest, movingDest, direction, onTop, lightView, ui, animate);
}
