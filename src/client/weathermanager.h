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

#ifndef WEATHER_MANAGER_H
#define WEATHER_MANAGER_H

#include "global.h"

#include <array>

enum class WeatherType : uint8 {
    None = 0,
    Rain = 1,
    Snow = 2,
    Sand = 3
};

struct WeatherState {
    WeatherType type = WeatherType::None;
    uint8 intensity = 0;
    int8 windX = 0;
    int8 windY = 0;
    uint16 transitionMs = 0;
};

class WeatherManager final
{
public:
    static constexpr size_t MAX_PARTICLES = 256;

    WeatherManager();

    void setWeather(WeatherState state);
    void draw(const Rect& mapRect);
    void clear();

    size_t getParticleCapacity() const { return m_particles.size(); }

private:
    struct Particle {
        float x = 0.0f;
        float y = 0.0f;
        float speed = 0.0f;
        float drift = 0.0f;
        float size = 0.0f;
        float phase = 0.0f;
    };

    void initializeParticles();
    void beginIntensityTransition(float target, uint16 durationMs);
    void update(uint64 nowMs);
    void updateParticles(float deltaSeconds, size_t activeCount);
    void finishTypeTransitionIfNeeded();
    void resetView();

    std::array<Particle, MAX_PARTICLES> m_particles{};
    WeatherState m_activeState{};
    WeatherState m_pendingState{};
    bool m_hasPendingState = false;

    float m_currentIntensity = 0.0f;
    float m_transitionStartIntensity = 0.0f;
    float m_transitionTargetIntensity = 0.0f;
    uint64 m_transitionElapsedMs = 0;
    uint16 m_transitionDurationMs = 0;
    uint64 m_lastUpdateMs = 0;
};

extern WeatherManager g_weatherManager;

#endif // WEATHER_MANAGER_H
