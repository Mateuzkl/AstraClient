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

#include "animatedtexture.h"
#include "graphics.h"

#include <framework/core/eventdispatcher.h>

AnimatedTexture::AnimatedTexture(const Size& size, std::vector<ImagePtr> frames, std::vector<int> framesDelay, bool buildMipmaps, bool compress) :
    Texture(size)
{
    for (const auto& frame : frames) {
        m_frames.emplace_back(std::make_shared<Texture>(frame, buildMipmaps, compress));
    }

    m_framesDelay = framesDelay;
    m_hasMipmaps = buildMipmaps;
    m_uniqueId = 0;
    m_currentFrame = 0;
    m_animTimer.restart();
    setupTranformMatrix();
}

AnimatedTexture::~AnimatedTexture()
{

}

bool AnimatedTexture::buildHardwareMipmaps()
{
    for(const TexturePtr& frame : m_frames)
        frame->buildHardwareMipmaps();
    m_hasMipmaps = true;
    return true;
}

void AnimatedTexture::setSmooth(bool smooth)
{
    for(const TexturePtr& frame : m_frames)
        frame->setSmooth(smooth);
    m_smooth = smooth;
}

void AnimatedTexture::setRepeat(bool repeat)
{
    for(const TexturePtr& frame : m_frames)
        frame->setRepeat(repeat);
    m_repeat = repeat;
}

void AnimatedTexture::update()
{
    if (m_animTimer.ticksElapsed() >= m_framesDelay[m_currentFrame]) {
        m_animTimer.restart();
        m_currentFrame = (m_currentFrame + 1) % m_frames.size();
    }

    m_frames[m_currentFrame]->update();
    m_id = m_frames[m_currentFrame]->getId();
    m_uniqueId = m_frames[m_currentFrame]->getUniqueId();
}

uint64_t AnimatedTexture::getAnimationDuration() const
{
    uint64_t duration = 0;
    for (const int delay : m_framesDelay)
        duration += std::max(1, delay);
    return std::max<uint64_t>(1, duration);
}

TexturePtr AnimatedTexture::getFrameAt(uint64_t elapsed) const
{
    if (m_frames.empty())
        return nullptr;
    elapsed %= getAnimationDuration();
    for (size_t i = 0; i < m_frames.size(); ++i) {
        const auto delay = static_cast<uint64_t>(std::max(1, m_framesDelay[i]));
        if (elapsed < delay)
            return m_frames[i];
        elapsed -= delay;
    }
    return m_frames.front();
}
