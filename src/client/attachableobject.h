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
#pragma once

#include "declarations.h"
#include <framework/luaengine/luaobject.h>

// One LuaObject/shared_from_this base, shared by Thing and Tile.
class AttachableObject : public LuaObject
{
public:
    ~AttachableObject() override;
    // Ownership/timers are never assigned. Item::clone recreates attachments
    // only after a shared_ptr owns the new item.
    AttachableObject& operator=(const AttachableObject& other);
    void attachEffect(const AttachedEffectPtr& effect);
    bool detachEffect(const AttachedEffectPtr& effect);
    bool detachEffectById(uint16_t id);
    void clearAttachedEffects(bool ignoreLuaEvent = false);
    void clearTemporaryAttachedEffects();
    void clearPermanentAttachedEffects();
    AttachedEffectPtr getAttachedEffectById(uint16_t id);
    const std::vector<AttachedEffectPtr>& getAttachedEffects() const;
    bool hasAttachedEffects() const;
    bool isOwnerHidden() const;
    bool isAttachedWalkAnimationDisabled() const;

protected:
    void copyAttachedEffectsFrom(const AttachableObject& other);
    virtual void onAttachedEffectsChanged() {}
    bool isAttachedOwnerHidden(bool ui) const;
    void drawAttachedEffects(const Point& originalDest, const Point& movingDest,
                             Otc::Direction direction, bool onTop, LightView* lightView = nullptr,
                             bool ui = false, bool animate = true);
    AttachedEffectPtr getAttachedTransformation(bool ui = false) const;

private:
    void attachEffectInternal(const AttachedEffectPtr& effect, bool invokeLua);
    struct Data { std::vector<AttachedEffectPtr> effects; };
    std::unique_ptr<Data> m_attachmentData;
    bool m_clearingAttachments = false;
};
