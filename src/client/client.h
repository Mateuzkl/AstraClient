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

#ifndef CLIENT_H
#define CLIENT_H

#include "global.h"
#include <array>

class Client
{
public:
    void init(std::vector<std::string>& args);
    void terminate();
    void registerLuaFunctions();

    float getEffectAlpha(uint8_t source) const {
        if (source >= m_effectAlphas.size()) return 1.0f;
        return m_effectAlphas[source];
    }
    void setEffectAlpha(uint8_t source, float v) {
        if (source < m_effectAlphas.size())
            m_effectAlphas[source] = std::isfinite(v) ? std::max(0.0f, std::min(1.0f, v)) : 1.0f;
    }
    void setEffectAlpha(const float v) { setOwnSpellEffectAlpha(v); }
    float getEffectAlpha() const { return getEffectAlpha(Otc::ME_SOURCE_OWN); }
    float getOwnSpellEffectAlpha() const { return m_effectAlphas[Otc::ME_SOURCE_OWN]; }
    void setOwnSpellEffectAlpha(float v) { setEffectAlpha(Otc::ME_SOURCE_OWN, v); }
    float getOtherPlayerSpellEffectAlpha() const { return m_effectAlphas[Otc::ME_SOURCE_OTHER_PLAYER]; }
    void setOtherPlayerSpellEffectAlpha(float v) { setEffectAlpha(Otc::ME_SOURCE_OTHER_PLAYER, v); }
    float getCreatureSpellEffectAlpha() const { return m_effectAlphas[Otc::ME_SOURCE_MONSTER]; }
    void setCreatureSpellEffectAlpha(float v) { setEffectAlpha(Otc::ME_SOURCE_MONSTER, v); }
    float getBossAreaCreatureEffectAlpha() const { return m_effectAlphas[Otc::ME_SOURCE_BOSS]; }
    void setBossAreaCreatureEffectAlpha(float v) { setEffectAlpha(Otc::ME_SOURCE_BOSS, v); }

private:
    std::array<float, 5> m_effectAlphas{ 1.0f, 1.0f, 1.0f, 1.0f, 1.0f };
};

extern Client g_client;

#endif
