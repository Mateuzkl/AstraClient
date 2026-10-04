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
#include "thingtype.h"
#include <framework/core/timer.h>
#include <framework/luaengine/luaobject.h>

// Adapted from Mehah/OpenTibiaBR to Astra's draw queue. Configuration is separate
// from per-instance animation and ownership; clones never copy timers/owners.
class AttachedEffect final : public LuaObject
{
public:
    static AttachedEffectPtr create(uint16_t thingId, ThingCategory category);
    AttachedEffectPtr clone();

    uint16_t getId() const { return m_id; }
    uint16_t getThingId() const { return m_thingId; }
    ThingCategory getThingCategory() const { return m_category; }
    const std::string& getName() const { return m_config.name; }
    void setName(const std::string& name) { m_config.name = name; }
    float getSpeed() const { return m_config.speed; }
    void setSpeed(float speed);
    float getOpacity() const { return m_config.opacity; }
    void setOpacity(float opacity);
    Size getSize() const { return m_config.size; }
    void setSize(const Size& size);
    bool isHidedOwner() const;
    void setHideOwner(bool value) { m_config.hideOwner = value; }
    bool isTransform() const { return m_config.transform; }
    void setTransform(bool value) { m_config.transform = value; }
    bool isDisabledWalkAnimation() const;
    void setDisableWalkAnimation(bool value) { m_config.disableWalkAnimation = value; }
    bool isPermanent() const { return m_config.permanent; }
    void setPermanent(bool value) { m_config.permanent = value; }
    bool isFollowingOwner() const { return m_config.followOwner; }
    void setFollowOwner(bool value) { m_config.followOwner = value; }
    uint32_t getDuration() const { return m_config.duration; }
    void setDuration(uint32_t duration);
    int getLoop() const { return m_config.loop; }
    void setLoop(int loop);
    Otc::Direction getDirection() const { return m_config.direction; }
    void setDirection(Otc::Direction direction);
    void setOffset(int x, int y);
    void setOnTop(bool onTop);
    void setOnTopByDir(Otc::Direction direction, bool onTop);
    void setDirOffset(Otc::Direction direction, int x, int y, bool onTop = false);
    void setShader(const std::string& name);
    void setCanDrawOnUI(bool value) { m_config.drawOnUI = value; }
    bool canDrawOnUI() const { return m_config.drawOnUI; }
    void setBounce(float minimum, float height, uint32_t period);
    void setPulse(float minimum, float height, uint32_t period);
    void setFade(float minimum, float maximum, uint32_t period);
    void setDrawOrder(int order);
    int getDrawOrder() const { return m_config.drawOrder; }
    void setLight(const Light& light) { m_config.light = light; }
    Light getLight() const { return m_config.light; }
    void attachEffect(const AttachedEffectPtr& effect);
    bool isValid();
    bool isExpired() const;
    const ThingTypePtr& getSourceThingType();
    void draw(const Point& originalDest, const Point& movingDest, Otc::Direction direction,
              bool onTop, LightView* lightView, bool ui, bool animate);

private:
    struct DirectionControl { Point offset; bool onTop = false; };
    struct Oscillation { float minimum = 0; float maximum = 0; uint32_t period = 0; };
    struct Config {
        std::string name;
        Size size;
        float speed = 1.f;
        float opacity = 1.f;
        bool hideOwner = false;
        bool transform = false;
        bool disableWalkAnimation = false;
        bool permanent = false;
        bool followOwner = true;
        bool drawOnUI = true;
        uint32_t duration = 0;
        int loop = -1;
        int drawOrder = 2;
        Otc::Direction direction = Otc::South;
        std::array<DirectionControl, 8> directions;
        Oscillation bounce, pulse, fade;
        Light light;
        PainterShaderProgramPtr shader;
    };

    AttachedEffectPtr cloneTree(unsigned depth);
    void start(const AttachableObjectPtr& owner);
    void stop();
    void scheduleExpiration();
    void resetAnimation();
    void resolveAnimation();
    double elapsed() const;
    double lifetime() const;
    static float oscillate(const Oscillation& value, double elapsed);
    bool hidesOwnerTree(bool ui = false) const;
    bool disablesWalkTree() const;

    Config m_config;
    uint16_t m_id = 0;
    uint16_t m_thingId = 0;
    ThingCategory m_category = ThingInvalidCategory;
    TexturePtr m_texture;
    ThingTypePtr m_thingType;
    uint64_t m_datGeneration = 0;
    std::vector<uint64_t> m_phaseEnds;
    uint64_t m_cycleDuration = 1000;
    std::vector<AttachedEffectPtr> m_children;
    std::weak_ptr<AttachableObject> m_owner;
    ScheduledEventPtr m_expirationEvent;
    mutable Timer m_timer;
    bool m_running = false;
    bool m_prototype = false; // Registration only; runtime clones keep the default.

    friend class AttachedEffectManager;
    friend class AttachableObject;
};
