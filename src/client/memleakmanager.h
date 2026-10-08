#ifndef ASTRACLIENT_MEMLEAKMANAGER_H
#define ASTRACLIENT_MEMLEAKMANAGER_H

// Adapted from the supplied Draconia game_memleak monitor for AstraClient.
#include "memleakhistory.h"
#include <deque>
#include <framework/ui/declarations.h>
#include <memory>
#include <string>
#include <unordered_map>

class MemLeakManager
{
  public:
    void uiInit(const UIWidgetPtr &window);
    void uiTerminate();
    void toggle();
    void hide();
    bool isWindowVisible();
    void updateMemoryDisplay();
    void updateObjectCounts();
    void updateEventDisplay();
    void updateMemoryBreakdown();
    void addLog(const std::string &message);
    std::string getLogText();
    void clearLog();
    void takeSnapshot();
    std::string computeDiff();
    void clearAlerts();
    void forceGC();
    void resetMonitoring();
    void setAlertThreshold(int64_t bytes) { m_history.setThreshold(bytes); }
    int64_t getAlertThreshold() { return m_history.threshold(); }
    void setAlertCooldown(int milliseconds) { m_history.setCooldown(milliseconds); }
    int getAlertCooldown() { return m_history.cooldown(); }

  private:
    struct Snapshot
    {
        std::string widgets;
        std::optional<int64_t> privateCommit;
        int64_t lua, timestamp;
    };
    void text(const std::string &id, const std::string &value);
    void alert(const std::string &message);
    UIWidgetPtr m_window;
    std::unordered_map<std::string, UIWidgetPtr> m_labels;
    MemLeakHistory m_history;
    std::unique_ptr<Snapshot> m_snapshot;
    std::deque<std::string> m_log;
    unsigned m_alertCount = 0;
};
extern MemLeakManager g_memLeak;
#endif
