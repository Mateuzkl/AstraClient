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
#include "attachedeffect.h"
#include "attachableobject.h"
#include "animator.h"
#include "effect.h"
#include "thingtypemanager.h"
#include "spritemanager.h"
#include "lightview.h"
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/animatedtexture.h>
#include <framework/graphics/drawqueue.h>
#include <framework/graphics/shadermanager.h>
#include <cmath>
#include <limits>

AttachedEffectPtr AttachedEffect::create(uint16_t thingId, ThingCategory category)
{
    if (!g_things.isValidDatId(thingId, category))
        return nullptr;
    auto effect = std::make_shared<AttachedEffect>();
    effect->m_thingId = thingId;
    effect->m_category = category;
    effect->resolveAnimation();
    return effect;
}

AttachedEffectPtr AttachedEffect::clone() { return cloneTree(0); }

AttachedEffectPtr AttachedEffect::cloneTree(unsigned depth)
{
    if (depth >= 16)
        return nullptr;
    auto result = std::make_shared<AttachedEffect>();
    result->m_config = m_config;
    result->m_id = m_id;
    result->m_thingId = m_thingId;
    result->m_category = m_category;
    result->m_texture = m_texture;
    for (const auto& child : m_children) {
        auto copy = child->cloneTree(depth + 1);
        if (!copy)
            return nullptr;
        result->m_children.push_back(std::move(copy));
    }
    result->resetAnimation();
    return result;
}

void AttachedEffect::attachEffect(const AttachedEffectPtr& effect)
{
    if (!effect || effect.get() == this || m_children.size() >= 32)
        return;
    // Deep copies prevent shared mutable children and parent/child cycles.
    if (auto copy = effect->cloneTree(1)) {
        copy->resetAnimation();
        m_children.push_back(std::move(copy));
    }
}

void AttachedEffect::setSpeed(float speed)
{
    if (std::isfinite(speed))
        m_config.speed = std::clamp(speed, 0.01f, 1000.f);
    scheduleExpiration();
}

void AttachedEffect::setOpacity(float opacity)
{
    if (std::isfinite(opacity))
        m_config.opacity = std::clamp(opacity, 0.f, 1.f);
}

void AttachedEffect::setSize(const Size& size)
{
    m_config.size = size.isValid() ? Size(std::min(size.width(), 4096), std::min(size.height(), 4096)) : Size();
}

void AttachedEffect::setDuration(uint32_t duration)
{
    m_config.duration = std::min(duration, static_cast<uint32_t>(std::numeric_limits<int>::max()));
    scheduleExpiration();
}

void AttachedEffect::setLoop(int loop)
{
    m_config.loop = std::clamp(loop, -1, 65535);
    scheduleExpiration();
}

void AttachedEffect::setDirection(Otc::Direction direction)
{
    if (direction >= Otc::North && direction <= Otc::NorthWest)
        m_config.direction = direction;
}

void AttachedEffect::setOffset(int x, int y)
{
    for (auto& control : m_config.directions)
        control.offset = Point(std::clamp(x, -32768, 32767), std::clamp(y, -32768, 32767));
}

void AttachedEffect::setOnTop(bool onTop)
{
    for (auto& control : m_config.directions)
        control.onTop = onTop;
}

void AttachedEffect::setOnTopByDir(Otc::Direction direction, bool onTop)
{
    if (direction >= Otc::North && direction <= Otc::NorthWest)
        m_config.directions[direction].onTop = onTop;
}

void AttachedEffect::setDirOffset(Otc::Direction direction, int x, int y, bool onTop)
{
    if (direction >= Otc::North && direction <= Otc::NorthWest)
        m_config.directions[direction] = {Point(std::clamp(x, -32768, 32767), std::clamp(y, -32768, 32767)), onTop};
}

void AttachedEffect::setShader(const std::string& name)
{
    m_config.shader = name.empty() ? nullptr : g_shaders.getShader(name);
    if (!name.empty() && !m_config.shader)
        g_logger.warning(stdext::format("Attached effect %u: shader '%s' unavailable; using unshaded rendering", m_id, name));
}

void AttachedEffect::setBounce(float minimum, float height, uint32_t period)
{
    if (std::isfinite(minimum) && std::isfinite(height))
        m_config.bounce = {std::clamp(minimum, 0.f, 4096.f), std::clamp(height, 0.f, 4096.f), period};
}

void AttachedEffect::setPulse(float minimum, float height, uint32_t period)
{
    if (std::isfinite(minimum) && std::isfinite(height))
        m_config.pulse = {std::clamp(minimum, 0.f, 400.f), std::clamp(height, 0.f, 400.f), period};
}

void AttachedEffect::setFade(float minimum, float maximum, uint32_t period)
{
    if (std::isfinite(minimum) && std::isfinite(maximum))
        m_config.fade = {std::clamp(minimum, 0.f, 100.f), std::clamp(maximum, 0.f, 100.f), period};
}

void AttachedEffect::setDrawOrder(int order) { m_config.drawOrder = std::clamp(order, 0, 5); }

const ThingTypePtr& AttachedEffect::getSourceThingType()
{
    if (m_category == ThingExternalTexture)
        return m_thingType;
    if (m_datGeneration != g_things.getDatGeneration()) {
        m_datGeneration = g_things.getDatGeneration();
        m_thingType = g_things.isDatLoaded() && g_things.isValidDatId(m_thingId, m_category)
            ? g_things.getThingType(m_thingId, m_category) : nullptr;
        resolveAnimation();
    }
    return m_thingType;
}

bool AttachedEffect::isValid()
{
    if (m_category == ThingExternalTexture)
        return m_texture != nullptr;
    return getSourceThingType() != nullptr;
}

void AttachedEffect::resolveAnimation()
{
    m_phaseEnds.clear();
    m_cycleDuration = 0;
    if (m_texture && m_texture->isAnimatedTexture()) {
        m_cycleDuration = std::static_pointer_cast<AnimatedTexture>(m_texture)->getAnimationDuration();
    } else if (m_thingType) {
        auto animator = m_thingType->getIdleAnimator();
        if (!animator)
            animator = m_thingType->getAnimator();
        const int phases = std::max(1, m_thingType->getAnimationPhases());
        for (int phase = 0; phase < phases; ++phase) {
            const int delay = animator && phase < animator->getAnimationPhases()
                ? animator->getPhaseDurationForSeed(phase, 0)
                : (m_category == ThingCategoryEffect ? Effect::EFFECT_TICKS_PER_FRAME : std::max(1, 1000 / phases));
            m_cycleDuration += std::max(1, delay);
            m_phaseEnds.push_back(m_cycleDuration);
        }
    }
    m_cycleDuration = std::max<uint64_t>(1, m_cycleDuration ? m_cycleDuration : 1000);
}

void AttachedEffect::resetAnimation()
{
    getSourceThingType();
    resolveAnimation();
    m_timer.restart();
    for (const auto& child : m_children)
        child->resetAnimation();
}

void AttachedEffect::start(const AttachableObjectPtr& owner)
{
    m_owner = owner;
    m_running = true;
    resetAnimation();
    scheduleExpiration();
}

void AttachedEffect::stop()
{
    m_owner.reset();
    m_running = false;
    if (m_expirationEvent) {
        m_expirationEvent->cancel();
        m_expirationEvent.reset();
    }
}

double AttachedEffect::elapsed() const { return std::max<double>(0, m_timer.ticksElapsed()); }

double AttachedEffect::lifetime() const
{
    double limit = m_config.duration ? m_config.duration : std::numeric_limits<double>::infinity();
    if (m_config.loop >= 0)
        limit = std::min(limit, m_cycleDuration * static_cast<double>(m_config.loop) / m_config.speed);
    return limit;
}

bool AttachedEffect::isExpired() const
{
    return (m_running || m_owner.expired()) && (m_config.loop == 0 || elapsed() >= lifetime());
}

void AttachedEffect::scheduleExpiration()
{
    if (m_expirationEvent) {
        m_expirationEvent->cancel();
        m_expirationEvent.reset();
    }
    if (!m_running || !std::isfinite(lifetime()))
        return;
    const auto delay = static_cast<int>(std::clamp(std::ceil(lifetime() - elapsed()), 1.0,
                                                  static_cast<double>(std::numeric_limits<int>::max())));
    std::weak_ptr<AttachedEffect> weakEffect = std::static_pointer_cast<AttachedEffect>(shared_from_this());
    const auto weakOwner = m_owner;
    m_expirationEvent = g_dispatcher.scheduleEvent([weakOwner, weakEffect] {
        const auto owner = weakOwner.lock();
        const auto effect = weakEffect.lock();
        if (!owner || !effect || effect->m_owner.lock() != owner)
            return;
        effect->m_expirationEvent.reset();
        if (effect->isExpired())
            owner->detachEffect(effect);
        else
            effect->scheduleExpiration();
    }, delay);
}

float AttachedEffect::oscillate(const Oscillation& value, double time)
{
    if (!value.period)
        return 0.f;
    const double fraction = std::fmod(time, value.period) / value.period;
    return value.minimum + value.maximum * static_cast<float>(1.0 - std::abs(2.0 * fraction - 1.0));
}

bool AttachedEffect::hidesOwnerTree(bool ui) const
{
    if (isExpired() || (ui && !m_config.drawOnUI))
        return false;
    if (m_config.hideOwner)
        return true;
    for (const auto& child : m_children)
        if (child->hidesOwnerTree(ui))
            return true;
    return false;
}

bool AttachedEffect::disablesWalkTree() const
{
    if (isExpired())
        return false;
    if (m_config.disableWalkAnimation)
        return true;
    for (const auto& child : m_children)
        if (child->disablesWalkTree())
            return true;
    return false;
}

bool AttachedEffect::isHidedOwner() const { return hidesOwnerTree(); }
bool AttachedEffect::isDisabledWalkAnimation() const { return disablesWalkTree(); }

void AttachedEffect::draw(const Point& originalDest, const Point& movingDest, Otc::Direction direction,
                           bool onTop, LightView* lightView, bool ui, bool animate)
{
    if (isExpired() || (ui && !m_config.drawOnUI))
        return;
    if (direction < Otc::North || direction > Otc::NorthWest)
        direction = m_config.direction;
    const auto& control = m_config.directions[direction];
    const Point anchor = m_config.followOwner ? movingDest : originalDest;
    if (control.onTop == onTop && !(m_config.transform && m_category == ThingCategoryCreature)) {
        const auto& type = getSourceThingType();
        if (m_texture || type) {
            const double time = animate ? elapsed() : 0;
            const double animationTime = time * m_config.speed;
            const uint64_t cycleTime = static_cast<uint64_t>(animationTime) % m_cycleDuration;
            int phase = m_phaseEnds.empty() ? 0
                : static_cast<int>(std::upper_bound(m_phaseEnds.begin(), m_phaseEnds.end(), cycleTime) - m_phaseEnds.begin());
            Point point = anchor - control.offset * g_sprites.getOffsetFactor();
            point.y -= static_cast<int>(oscillate(m_config.bounce, time) * g_sprites.getOffsetFactor());
            const size_t begin = g_drawQueue->size();
            Size naturalSize;
            if (m_texture) {
                const auto frame = m_texture->isAnimatedTexture()
                    ? std::static_pointer_cast<AnimatedTexture>(m_texture)->getFrameAt(static_cast<uint64_t>(animationTime)) : m_texture;
                if (frame) {
                    naturalSize = frame->getSize();
                    g_drawQueue->addTexturedRect(Rect(point, naturalSize), frame, Rect(Point(), naturalSize));
                }
            } else {
                naturalSize = type->getSize() * g_sprites.spriteSize();
                int x = 0, y = 0;
                if (m_category == ThingCategoryCreature) {
                    const auto cardinal = direction == Otc::NorthEast || direction == Otc::SouthEast ? Otc::East
                        : direction == Otc::NorthWest || direction == Otc::SouthWest ? Otc::West : direction;
                    x = static_cast<int>(cardinal) % std::max(1, type->getNumPatternX());
                } else if (m_category == ThingCategoryMissile) {
                    static constexpr int patterns[8][2] = {{1,0},{2,1},{1,2},{0,1},{2,0},{2,2},{0,2},{0,0}};
                    x = patterns[direction][0] % std::max(1, type->getNumPatternX());
                    y = patterns[direction][1] % std::max(1, type->getNumPatternY());
                }
                // Light uses the logical owner anchor, independent of displacement.
                type->draw(point, 0, x, y, 0, phase, Color::white, nullptr);
            }
            float scaleX = 1.f, scaleY = 1.f;
            if (m_config.size.isValid() && naturalSize.isValid()) {
                scaleX = static_cast<float>(m_config.size.width()) / naturalSize.width();
                scaleY = static_cast<float>(m_config.size.height()) / naturalSize.height();
            }
            const float pulse = 1.f + oscillate(m_config.pulse, time) / 100.f;
            float opacity = m_config.opacity;
            if (m_config.fade.period) {
                const double f = std::fmod(time, m_config.fade.period) / m_config.fade.period;
                opacity *= (m_config.fade.minimum + (m_config.fade.maximum - m_config.fade.minimum) *
                    static_cast<float>(1.0 - std::abs(2.0 * f - 1.0))) / 100.f;
            }
            g_drawQueue->setAttachedEffectParameters(begin, point, scaleX * pulse, scaleY * pulse,
                                                     opacity, m_config.shader);
            if (lightView) {
                const auto light = m_config.light.intensity ? m_config.light : (type ? type->getLight() : Light());
                if (light.intensity)
                    lightView->addLight(anchor + Point(g_sprites.spriteSize() / 2, g_sprites.spriteSize() / 2), light);
            }
        }
    }
    for (const auto& child : m_children)
        child->draw(originalDest, movingDest, direction, onTop, lightView, ui, animate);
}
