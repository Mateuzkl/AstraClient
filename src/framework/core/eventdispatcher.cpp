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

#include "eventdispatcher.h"

#include <framework/core/clock.h>
#include <framework/core/graphicalapplication.h>
#include <framework/graphics/graph.h>
#include <framework/util/stats.h>
#include "timer.h"

EventDispatcher g_dispatcher;
EventDispatcher g_graphicsDispatcher;
std::thread::id g_mainThreadId = std::this_thread::get_id();
std::thread::id g_graphicsThreadId = std::this_thread::get_id();
std::thread::id g_dispatcherThreadId = std::this_thread::get_id();

void EventDispatcher::shutdown()
{
    m_disabled = true;

    mergeEvents();

    while(!m_eventList.empty())
        poll();

    while(!m_scheduledEventList.empty()) {
        ScheduledEventPtr scheduledEvent = m_scheduledEventList.top();
        scheduledEvent->cancel();
        m_scheduledEventList.pop();
    }

    std::lock_guard<std::mutex> lock(m_mutex);
    m_incomingEvents.clear();
    m_incomingScheduledEvents.clear();
}

void EventDispatcher::mergeEvents()
{
    std::vector<IncomingEvent> incomingEvents;
    std::vector<ScheduledEventPtr> incomingScheduledEvents;

    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if(!m_incomingEvents.empty()) {
            incomingEvents.swap(m_incomingEvents);
        }
        if(!m_incomingScheduledEvents.empty()) {
            incomingScheduledEvents.swap(m_incomingScheduledEvents);
        }
    }

    for(auto& incoming : incomingEvents) {
        if(incoming.pushFront) {
            m_eventList.push_front(incoming.event);
            m_pollEventsSize++;
        } else {
            m_eventList.push_back(incoming.event);
        }
    }

    for(auto& schedEvent : incomingScheduledEvents) {
        m_scheduledEventList.push(schedEvent);
    }
}

void EventDispatcher::poll()
{
    AutoStat s(this == &g_dispatcher ? STATS_MAIN : STATS_RENDER, "PollDispatcher");

    mergeEvents();

    int events = 0;
    int loops = 0;
    
    size_t scheduledCount = m_scheduledEventList.size();
    for(size_t count = 0; count < scheduledCount && !m_scheduledEventList.empty(); ++count) {
        ScheduledEventPtr scheduledEvent = m_scheduledEventList.top();
        if(scheduledEvent->remainingTicks() > 0)
            break;
        m_scheduledEventList.pop();
        {
            AutoStat s2(STATS_DISPATCHER, scheduledEvent->getFunction());
            m_botSafe = scheduledEvent->isBotSafe();
            scheduledEvent->execute();
            events += 1;
        }

        if(scheduledEvent->nextCycle())
            m_scheduledEventList.push(scheduledEvent);
    }

    // execute events list until all events are out, this is needed because some events can schedule new events that would
    // change the UIWidgets layout, in this case we must execute these new events before we continue rendering,
    m_pollEventsSize = m_eventList.size();
    loops = 0;
    while(m_pollEventsSize > 0) {
        if(loops > 100) {
            static Timer reportTimer;
            if(reportTimer.running() && reportTimer.ticksElapsed() > 500) {
                std::stringstream ss;
                ss << "ATTENTION the event list is not getting empty, this could be caused by some bad code.\nLog:\n";
                for (auto& event : m_eventList) {
                    ss << event->getFunction() << "\n";
                    if (ss.str().size() > 512) break;
                }
                g_logger.error(ss.str());                
                reportTimer.restart();
            }
            break;
        }

        for(int i=0;i<m_pollEventsSize;++i) {
            EventPtr event = m_eventList.front();
            m_eventList.pop_front();
            {
                AutoStat s2(STATS_DISPATCHER, event->getFunction());
                m_botSafe = event->isBotSafe();
                event->execute();
                events += 1;
            }
        }
        
        mergeEvents();
        m_pollEventsSize = m_eventList.size();
        
        loops++;
    }

    g_graphs[this == &g_dispatcher ? GRAPH_DISPATCHER_EVENTS : GRAPH_GRAPHICS_EVENTS].addValue(events, true);

    m_botSafe = false;
}

ScheduledEventPtr EventDispatcher::scheduleEventEx(const std::string& function, const std::function<void()>& callback, int delay)
{
    if(m_disabled)
        return std::make_shared<ScheduledEvent>("", nullptr, delay, 1);

    VALIDATE(delay >= 0);
    auto scheduledEvent = std::make_shared<ScheduledEvent>(function, callback, delay, 1, g_app.isOnInputEvent());

    std::lock_guard<std::mutex> lock(m_mutex);
    m_incomingScheduledEvents.push_back(scheduledEvent);
    return scheduledEvent;
}

ScheduledEventPtr EventDispatcher::cycleEventEx(const std::string& function, const std::function<void()>& callback, int delay)
{
    if(m_disabled)
        return std::make_shared<ScheduledEvent>("", nullptr, delay, 0);

    VALIDATE(delay > 0);
    auto scheduledEvent = std::make_shared<ScheduledEvent>(function, callback, delay, 0, g_app.isOnInputEvent());

    std::lock_guard<std::mutex> lock(m_mutex);
    m_incomingScheduledEvents.push_back(scheduledEvent);
    return scheduledEvent;
}

EventPtr EventDispatcher::addEventEx(const std::string& function, const std::function<void()>& callback, bool pushFront)
{
    if(m_disabled)
        return std::make_shared<Event>("", nullptr);

    auto event = std::make_shared<Event>(function, callback, g_app.isOnInputEvent());

    std::lock_guard<std::mutex> lock(m_mutex);
    m_incomingEvents.push_back({event, pushFront});
    return event;
}

