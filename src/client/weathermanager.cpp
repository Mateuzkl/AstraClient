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
 */

#include "weathermanager.h"

#include <framework/core/clock.h>
#include <framework/graphics/drawqueue.h>

#include <algorithm>
#include <cmath>
#include <vector>

WeatherManager g_weatherManager;

namespace {

constexpr uint8 MAX_INTENSITY = 100;
constexpr float MIN_VISIBLE_INTENSITY = 0.01f;
constexpr uint64 MAX_FRAME_DELTA_MS = 250;

float wrapUnit(float value)
{
    value -= std::floor(value);
    return value < 0.0f ? value + 1.0f : value;
}

float randomUnit(uint32& state)
{
    state = state * 1664525u + 1013904223u;
    return static_cast<float>(state & 0x00FFFFFFu) / static_cast<float>(0x01000000u);
}

} // namespace

WeatherManager::WeatherManager()
{
    initializeParticles();
}

void WeatherManager::initializeParticles()
{
    uint32 randomState = 0xA57A860u;
    for (Particle& particle : m_particles) {
        particle.x = randomUnit(randomState);
        particle.y = randomUnit(randomState);
        particle.speed = 0.35f + randomUnit(randomState) * 0.75f;
        particle.drift = randomUnit(randomState) * 2.0f - 1.0f;
        particle.size = 1.0f + randomUnit(randomState) * 2.0f;
        particle.phase = randomUnit(randomState) * 6.28318530718f;
    }
}

void WeatherManager::beginIntensityTransition(float target, uint16 durationMs)
{
    m_transitionStartIntensity = m_currentIntensity;
    m_transitionTargetIntensity = std::clamp(target, 0.0f, static_cast<float>(MAX_INTENSITY));
    m_transitionElapsedMs = 0;
    m_transitionDurationMs = durationMs;

    if (durationMs == 0) {
        m_currentIntensity = m_transitionTargetIntensity;
        finishTypeTransitionIfNeeded();
    }
}

void WeatherManager::setWeather(WeatherState state)
{
    if (state.type > WeatherType::Sand) {
        state = {};
    }
    state.intensity = std::min<uint8>(state.intensity, MAX_INTENSITY);
    if (state.type == WeatherType::None) {
        state.intensity = 0;
        state.windX = 0;
        state.windY = 0;
    }

    if (m_activeState.type == WeatherType::None || m_currentIntensity <= MIN_VISIBLE_INTENSITY ||
        state.type == m_activeState.type) {
        m_activeState = state;
        m_hasPendingState = false;
        beginIntensityTransition(static_cast<float>(state.intensity), state.transitionMs);
        return;
    }

    // Fade the active type to zero first. Only the latest requested state is
    // retained, so rapid changes never accumulate multiple particle pools.
    m_pendingState = state;
    m_hasPendingState = true;
    beginIntensityTransition(0.0f, state.transitionMs);
}

void WeatherManager::finishTypeTransitionIfNeeded()
{
    if (!m_hasPendingState || m_currentIntensity > MIN_VISIBLE_INTENSITY) {
        return;
    }

    m_activeState = m_pendingState;
    m_hasPendingState = false;
    m_currentIntensity = 0.0f;
    beginIntensityTransition(static_cast<float>(m_activeState.intensity), m_activeState.transitionMs);
}

void WeatherManager::update(uint64 nowMs)
{
    if (m_lastUpdateMs == 0) {
        m_lastUpdateMs = nowMs;
        return;
    }

    const uint64 elapsedMs = nowMs >= m_lastUpdateMs ? nowMs - m_lastUpdateMs : 0;
    const uint64 deltaMs = std::min<uint64>(elapsedMs, MAX_FRAME_DELTA_MS);
    m_lastUpdateMs = nowMs;

    if (m_currentIntensity != m_transitionTargetIntensity) {
        if (m_transitionDurationMs == 0) {
            m_currentIntensity = m_transitionTargetIntensity;
        } else {
            m_transitionElapsedMs = std::min<uint64>(m_transitionElapsedMs + deltaMs, m_transitionDurationMs);
            const float progress = static_cast<float>(m_transitionElapsedMs) / m_transitionDurationMs;
            m_currentIntensity = m_transitionStartIntensity +
                (m_transitionTargetIntensity - m_transitionStartIntensity) * progress;
        }

        if (m_transitionElapsedMs >= m_transitionDurationMs || m_transitionDurationMs == 0) {
            m_currentIntensity = m_transitionTargetIntensity;
            finishTypeTransitionIfNeeded();
        }
    }

    const size_t activeCount = std::min<size_t>(m_particles.size(), static_cast<size_t>(std::lround(
        m_currentIntensity * static_cast<float>(m_particles.size()) / MAX_INTENSITY)));
    updateParticles(static_cast<float>(deltaMs) / 1000.0f, activeCount);
}

void WeatherManager::updateParticles(float deltaSeconds, size_t activeCount)
{
    if (deltaSeconds <= 0.0f || activeCount == 0 || m_activeState.type == WeatherType::None) {
        return;
    }

    const float windX = static_cast<float>(m_activeState.windX) / 127.0f;
    const float windY = static_cast<float>(m_activeState.windY) / 127.0f;
    for (size_t index = 0; index < activeCount; ++index) {
        Particle& particle = m_particles[index];
        switch (m_activeState.type) {
            case WeatherType::Rain:
                particle.x = wrapUnit(particle.x + windX * deltaSeconds * 0.20f);
                particle.y = wrapUnit(particle.y + (0.55f + particle.speed + windY * 0.12f) * deltaSeconds);
                break;
            case WeatherType::Snow:
                particle.phase += deltaSeconds * (0.8f + particle.speed);
                particle.x = wrapUnit(particle.x + (windX * 0.08f + std::sin(particle.phase) * 0.015f) * deltaSeconds);
                particle.y = wrapUnit(particle.y + (0.08f + particle.speed * 0.14f + windY * 0.025f) * deltaSeconds);
                break;
            case WeatherType::Sand: {
                const float direction = std::abs(windX) < 0.01f ? 1.0f : windX;
                particle.x = wrapUnit(particle.x + (direction * (0.32f + particle.speed * 0.24f)) * deltaSeconds);
                particle.y = wrapUnit(particle.y + (particle.drift * 0.015f + windY * 0.025f) * deltaSeconds);
                break;
            }
            case WeatherType::None:
                break;
        }
    }
}

void WeatherManager::draw(const Rect& mapRect)
{
    update(g_clock.millis());
    if (mapRect.isEmpty() || m_activeState.type == WeatherType::None ||
        m_currentIntensity <= MIN_VISIBLE_INTENSITY) {
        return;
    }

    const size_t activeCount = std::min<size_t>(m_particles.size(), static_cast<size_t>(std::lround(
        m_currentIntensity * static_cast<float>(m_particles.size()) / MAX_INTENSITY)));
    if (activeCount == 0) {
        return;
    }

    const size_t drawQueueStart = g_drawQueue->size();
    const int left = mapRect.left();
    const int top = mapRect.top();
    const int width = std::max(1, mapRect.width());
    const int height = std::max(1, mapRect.height());

    for (size_t index = 0; index < activeCount; ++index) {
        const Particle& particle = m_particles[index];
        const int x = left + static_cast<int>(particle.x * width);
        const int y = top + static_cast<int>(particle.y * height);

        switch (m_activeState.type) {
            case WeatherType::Rain: {
                const int slant = static_cast<int>(m_activeState.windX / 18);
                const int length = 6 + static_cast<int>(particle.size * 2.0f);
                g_drawQueue->addLine({ Point(x, y), Point(x + slant, y + length) }, 1, Color(150, 195, 255, 185));
                break;
            }
            case WeatherType::Snow: {
                const int size = std::clamp(static_cast<int>(std::lround(particle.size)), 1, 3);
                g_drawQueue->addFilledRect(Rect(Point(x, y), Size(size, size)), Color(235, 245, 255, 205));
                break;
            }
            case WeatherType::Sand: {
                const int length = 3 + static_cast<int>(particle.size * 2.0f);
                g_drawQueue->addFilledRect(Rect(Point(x, y), Size(length, 1)), Color(205, 169, 96, 145));
                break;
            }
            case WeatherType::None:
                break;
        }
    }

    g_drawQueue->setClip(drawQueueStart, mapRect);
}

void WeatherManager::clear()
{
    m_activeState = {};
    m_pendingState = {};
    m_hasPendingState = false;
    m_currentIntensity = 0.0f;
    m_transitionStartIntensity = 0.0f;
    m_transitionTargetIntensity = 0.0f;
    m_transitionElapsedMs = 0;
    m_transitionDurationMs = 0;
    resetView();
}

void WeatherManager::resetView()
{
    m_lastUpdateMs = 0;
    initializeParticles();
}
