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

#ifndef EVENTDISPATCHER_H
#define EVENTDISPATCHER_H

#include "clock.h"
#include "scheduledevent.h"
#include "scheduledeventqueue.h"

#include <queue>

// @bindsingleton g_dispatcher
class EventDispatcher
{
public:
    void shutdown();
    void poll();

    EventPtr addEventEx(const std::string& function, const std::function<void()>& callback, bool pushFront = false);
    ScheduledEventPtr scheduleEventEx(const std::string& function, const std::function<void()>& callback, int delay);
    ScheduledEventPtr cycleEventEx(const std::string& function, const std::function<void()>& callback, int delay);

    bool isBotSafe() { return m_botSafe; }
    size_t getPendingEventCount() {
        std::lock_guard<std::recursive_mutex> lock(m_mutex);
        return m_eventList.size();
    }
    size_t getScheduledEventCount() {
        std::lock_guard<std::recursive_mutex> lock(m_mutex);
        // Queue entries, not active callbacks: cancellation is removed by poll().
        return m_scheduledEventList.size();
    }
    std::string getScheduledEventDiagnostics(size_t limit = 5);

private:
    std::list<EventPtr> m_eventList;
    int m_pollEventsSize = 0;
    bool m_disabled = false;
    bool m_botSafe = false;
    std::recursive_mutex m_mutex;
    ScheduledEventQueue<ScheduledEventPtr, lessScheduledEvent> m_scheduledEventList;
};

extern EventDispatcher g_dispatcher;
extern EventDispatcher g_graphicsDispatcher;
extern std::thread::id g_mainThreadId;
extern std::thread::id g_dispatcherThreadId;
extern std::thread::id g_graphicsThreadId;

#define addEvent(...) addEventEx(__FUNCTION__, __VA_ARGS__)
#define scheduleEvent(...) scheduleEventEx(__FUNCTION__, __VA_ARGS__)
#define cycleEvent(...) cycleEventEx(__FUNCTION__, __VA_ARGS__)

#define VALIDATE_GRAPHICS_THREAD() VALIDATE(std::this_thread::get_id() == g_graphicsThreadId)
#define VALIDATE_DISPATCHER_THREAD() VALIDATE(std::this_thread::get_id() == g_dispatcherThreadId)

#endif
