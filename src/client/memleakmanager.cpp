#include "memleakmanager.h"
#include "map.h"
#include "spritemanager.h"
#include <array>
#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/texturemanager.h>
#include <framework/luaengine/luainterface.h>
#include <framework/platform/platform.h>
#include <framework/ui/uiwidget.h>
#include <framework/util/stats.h>
#include <iomanip>
#include <sstream>
#if defined(WIN32) && !defined(__EMSCRIPTEN__)
#include <psapi.h>
#include <windows.h>
#include <winsock2.h>
#endif

MemLeakManager g_memLeak;
namespace
{
constexpr double mib = 1024.0 * 1024.0;
std::string memory(int64_t bytes)
{
    std::ostringstream out;
    out << std::fixed << std::setprecision(1) << bytes / mib << " MiB";
    return out.str();
}
// Only counts are copied: snapshots must not keep widgets alive.
std::array<int64_t, 4> widgetCounts(const std::string &info)
{
    std::array<int64_t, 4> counts{};
    std::istringstream line(info.substr(0, info.find('\n')));
    char separator;
    if (!(line >> counts[0] >> separator) || separator != '|' || !(line >> counts[1] >> separator) ||
        separator != '|' || !(line >> counts[2] >> separator) || separator != '|' || !(line >> counts[3]))
        return {};
    return counts;
}
} // namespace

void MemLeakManager::uiInit(const UIWidgetPtr &window)
{
    uiTerminate();
    if (!window || window->isDestroyed())
        return;
    m_window = window;
    for (const char *id : {"memProcess", "memLua", "memTrend", "objWidgets", "objTextures", "objThings", "objCreatures",
                           "objSprites", "objBreakdown", "widgetLeak", "eventInfo", "alerts", "logText"})
        m_labels.emplace(id, window->recursiveGetChildById(id));
    window->hide();
    resetMonitoring();
}

void MemLeakManager::uiTerminate()
{
    auto window = std::move(m_window);
    m_labels.clear();
    m_snapshot.reset();
    m_history.clear();
    m_log.clear();
    m_alertCount = 0;
    if (window && !window->isDestroyed())
        window->destroy();
}

bool MemLeakManager::isWindowVisible() { return m_window && !m_window->isDestroyed() && m_window->isVisible(); }

void MemLeakManager::text(const std::string &id, const std::string &value)
{
    const auto it = m_labels.find(id);
    if (it != m_labels.end() && it->second && !it->second->isDestroyed() && it->second->getText() != value)
        it->second->setText(value);
}

void MemLeakManager::toggle()
{
    if (!m_window || m_window->isDestroyed())
        return;
    if (isWindowVisible())
    {
        hide();
        return;
    }
    resetMonitoring();
    m_window->show();
    m_window->raise();
    m_window->focus();
}

void MemLeakManager::hide()
{
    if (m_window && !m_window->isDestroyed())
        m_window->hide();
    resetMonitoring();
}

void MemLeakManager::resetMonitoring()
{
    m_history.clear();
    m_log.clear();
    m_snapshot.reset();
    m_alertCount = 0;
    for (const auto &entry : m_labels)
        text(entry.first, "-");
    text("widgetLeak", "No snapshot taken. Growth/orphan counts are diagnostics, not proof of leaks.");
    text("alerts", "No alerts.");
    text("logText", "");
}

void MemLeakManager::addLog(const std::string &message)
{
    if (!isWindowVisible())
        return;
    // Cap both history length and entry size, including messages supplied from Lua.
    const auto seconds = g_clock.seconds();
    std::ostringstream line;
    line << '[' << seconds << "s] " << message.substr(0, 2048);
    m_log.push_back(line.str());
    if (m_log.size() > 200)
        m_log.pop_front();
    text("logText", getLogText());
}

std::string MemLeakManager::getLogText()
{
    std::string result;
    for (const auto &line : m_log)
    {
        if (!result.empty())
            result += '\n';
        result += line;
    }
    return result;
}

void MemLeakManager::clearLog()
{
    m_log.clear();
    text("logText", "");
}

void MemLeakManager::alert(const std::string &message)
{
    ++m_alertCount;
    addLog(message);
    text("alerts", message + " (#" + std::to_string(m_alertCount) + ")\nGrowth is not a confirmed memory leak.");
}

void MemLeakManager::updateMemoryDisplay()
{
    if (!isWindowVisible())
        return;
    const int64_t process = static_cast<int64_t>(g_platform.getMemoryUsage());
    const int64_t lua = static_cast<int64_t>(g_lua.getMemoryUsage());
#ifdef __EMSCRIPTEN__
    text("memProcess", "WASM heap capacity (not live allocations): " + memory(process));
#elif defined(WIN32)
    text("memProcess", "Process working set: " + memory(process));
#else
    text("memProcess", "Process working set: unavailable on this platform");
#endif
    text("memLua", "Lua heap: " + memory(lua));
    if (process <= 0)
        return;
    m_history.add(process, lua, static_cast<int64_t>(g_clock.millis()));
    std::ostringstream trend;
    trend << std::fixed << std::setprecision(1) << "Trend: " << std::showpos << m_history.bytesPerSecond() / 1024
          << " KiB/s over " << std::noshowpos << m_history.span() / 1000.0 << "s (" << m_history.size()
          << "/120 samples)";
    text("memTrend", trend.str());
    if (m_history.checkAlert())
        alert("Memory grew " + memory(m_history.delta()) + " in the observation window.");
}

void MemLeakManager::updateObjectCounts()
{
    if (!isWindowVisible())
        return;
    std::istringstream input(g_stats.getWidgetsInfo(8, false));
    std::string line;
    const char *ids[] = {"objWidgets", "objTextures", "objCreatures", "objThings"};
    const char *names[] = {"Widgets", "Textures", "Creatures", "Things"};
    for (size_t i = 0; i < 4 && std::getline(input, line); ++i)
    {
        std::istringstream fields(line);
        int64_t alive = 0, destroyed = 0, created = 0, unused = 0;
        char separator;
        if (!(fields >> alive >> separator >> destroyed >> separator >> created))
            continue;
        std::string value = std::string(names[i]) + ": " + std::to_string(alive) + " alive (" +
                            std::to_string(created) + " created / " + std::to_string(destroyed) + " destroyed)";
        if (i == 0 && fields >> separator >> unused)
            value += " / " + std::to_string(unused) + " detached";
        text(ids[i], value);
    }
    text("objSprites", "Sprite cache: " + std::to_string(g_sprites.getImageCacheSize()) +
                           " entries | Known creatures: " + std::to_string(g_map.getKnownCreatureCount()));
}

void MemLeakManager::updateMemoryBreakdown()
{
    if (!isWindowVisible())
        return;
    std::ostringstream out;
#if defined(WIN32) && !defined(__EMSCRIPTEN__)
    PROCESS_MEMORY_COUNTERS_EX counters{};
    counters.cb = sizeof(counters);
    if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&counters),
                             sizeof(counters)))
        out << "Private committed bytes (not live heap): " << memory(counters.PrivateUsage) << '\n';
#endif
    out << "Lua heap: " << memory(g_lua.getMemoryUsage()) << '\n'
        << "Sprite CPU pixel cache: " << memory(g_sprites.getImageCacheBytes()) << '\n'
        << "HD cached blob payload: " << memory(g_sprites.getCachedDataBytes()) << " ("
        << g_sprites.getCachedDataCount() << " entries)\n"
        << "Named texture-cache entries: " << g_textures.getTextureCount() << '\n'
        << "Dispatcher queued: " << g_dispatcher.getPendingEventCount() << " immediate / "
        << g_dispatcher.getScheduledEventCount() << " scheduled\n"
        << "Counts/payload sizes are not total RAM. GPU memory is separate.\n"
        << "Full heap, file, minimap and sound allocation breakdown is not instrumented in Astra.";
    text("objBreakdown", out.str());
}

void MemLeakManager::updateEventDisplay()
{
    if (!isWindowVisible())
        return;
    std::string info = g_stats.get(STATS_DISPATCHER, 8, true);
    if (info.empty())
        info = "No dispatcher timing samples yet.\n";
    info += "\nRecent slow callbacks (>5ms):\n" + g_stats.getSlow(STATS_DISPATCHER, 8, 5, true);
    text("eventInfo", info);
}

void MemLeakManager::takeSnapshot()
{
    if (!isWindowVisible())
        return;
    m_snapshot = std::make_unique<Snapshot>(
        Snapshot{g_stats.getWidgetsInfo(15, false), static_cast<int64_t>(g_platform.getMemoryUsage()),
                 static_cast<int64_t>(g_lua.getMemoryUsage()), static_cast<int64_t>(g_clock.millis())});
    text("widgetLeak", "Snapshot taken. Use Diff after opening/closing the UI or repeating an action.");
    addLog("Snapshot taken.");
}

std::string MemLeakManager::computeDiff()
{
    if (!isWindowVisible())
        return {};
    if (!m_snapshot)
    {
        text("widgetLeak", "Take a Snapshot first.");
        return {};
    }
    const std::string current = g_stats.getWidgetsInfo(15, false);
    const auto before = widgetCounts(m_snapshot->widgets), after = widgetCounts(current);
    const auto process = static_cast<int64_t>(g_platform.getMemoryUsage()) - m_snapshot->process;
    const auto lua = static_cast<int64_t>(g_lua.getMemoryUsage()) - m_snapshot->lua;
    std::ostringstream out;
    out << "Diff over " << std::fixed << std::setprecision(1) << (g_clock.millis() - m_snapshot->timestamp) / 1000.0
        << "s:\n"
        << "Process delta: " << std::showpos << process / mib << " MiB / Lua delta: " << lua / 1024.0 << " KiB\n"
        << "Widgets: alive " << after[0] - before[0] << ", created " << after[2] - before[2] << ", destroyed "
        << after[1] - before[1] << ", detached " << after[3] - before[3] << '\n';
    const auto unused = current.find("UnusedWidgets|");
    const auto sources = unused == std::string::npos ? std::string::npos : current.find('\n', unused);
    if (sources != std::string::npos)
        out << "Detached widget sources (may include intentional cached widgets):\n" << current.substr(sources + 1);
    out << "This comparison does not prove a leak; repeat the same workload and compare trends.";
    text("widgetLeak", out.str());
    addLog("Snapshot diff computed.");
    return out.str();
}

void MemLeakManager::clearAlerts()
{
    m_alertCount = 0;
    m_history.clearAlert();
    text("alerts", "No alerts.");
}

void MemLeakManager::forceGC()
{
    if (!isWindowVisible())
        return;
    const auto before = g_lua.getMemoryUsage();
    g_lua.collectGarbage();
    const auto after = g_lua.getMemoryUsage();
    addLog("Lua GC: " + memory(before) + " -> " + memory(after));
    updateMemoryDisplay();
}
