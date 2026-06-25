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

#include "logger.h"
#include "eventdispatcher.h"

#include <framework/core/resourcemanager.h>
#include <framework/core/graphicalapplication.h>

#ifdef FW_GRAPHICS
#include <framework/platform/platformwindow.h>
#include <framework/platform/platform.h>
#include <framework/luaengine/luainterface.h>
#endif

Logger g_logger;

void Logger::log(Fw::LogLevel level, const std::string& message)
{
    std::unique_lock<std::recursive_mutex> lock(m_mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
        return;
    }

#ifdef NDEBUG
    if(level == Fw::LogDebug)
        return;
#endif

    static bool ignoreLogs = false;
    if(ignoreLogs)
        return;

    const static std::string logPrefixes[] = { "", "", "WARNING: ", "ERROR: ", "FATAL ERROR: " };
    std::string outmsg = logPrefixes[level] + message;
    std::cout << outmsg << std::endl;

    if(m_outFile.good()) {
        m_outFile << outmsg << std::endl;
        m_outFile.flush();
    }

    std::size_t now = std::time(NULL);
    m_logMessages.push_back(LogMessage(level, outmsg, now));
    if(m_logMessages.size() > MAX_LOG_HISTORY)
        m_logMessages.pop_front();

    if(m_onLog) {
        // schedule log callback, because this callback can run lua code that may affect the current state
        g_dispatcher.addEvent([=] {
            if(m_onLog)
                m_onLog(level, outmsg, now);
        });
    }

    if(level == Fw::LogFatal || (m_testingMode && level == Fw::LogError)) {
#ifdef FW_GRAPHICS
        if (!m_testingMode) {
            g_window.displayFatalError(message);
        }
#endif
        ignoreLogs = true;
#ifdef _MSC_VER
        ::quick_exit(-1);
#else
        exit(-1);
#endif
    }
}

void Logger::logFunc(Fw::LogLevel level, const std::string& message, std::string prettyFunction)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);

    prettyFunction = prettyFunction.substr(0, prettyFunction.find_first_of('('));
    if(prettyFunction.find_last_of(' ') != std::string::npos)
        prettyFunction = prettyFunction.substr(prettyFunction.find_last_of(' ') + 1);


    std::stringstream ss;
    ss << message;

    if(!prettyFunction.empty()) {
        if(g_lua.isInCppCallback())
            ss << g_lua.traceback("", 1);
        ss << g_platform.traceback(prettyFunction, 1, 8);
    }

    log(level, ss.str());
}

void Logger::fireOldMessages()
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);

    if(m_onLog) {
        auto backup = m_logMessages;
        for(const LogMessage& logMessage : backup) {
            m_onLog(logMessage.level, logMessage.message, logMessage.when);
        }
    }
}

// The on-disk log is kept across runs (so a crash report can ship the full
// context from the run that crashed) and only reset once it grows past this
// cap, to keep it from growing without bound. getLastLog() captures up to this
// much of the previous contents for the crash reporter.
static const int MAX_LOG_FILE_SIZE = 1024 * 1024; // 1 MB

void Logger::setLogFile(const std::string& file)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);

    int fileSize = 0;
    m_outFile.open(stdext::utf8_to_latin1(file.c_str()).c_str(), std::ios::in | std::ios::binary);
    if (m_outFile.is_open()) {
        m_outFile.seekg(0, m_outFile.end);
        fileSize = m_outFile.tellg();
        // Keep up to MAX_LOG_FILE_SIZE of the existing contents around so the
        // crash reporter (g_logger.getLastLog()) can attach the previous run's
        // full log even when we are about to reset the file just below.
        int offset = std::max<int>(0, fileSize - MAX_LOG_FILE_SIZE);
        int length = fileSize - offset;
        m_outFile.seekg(offset, m_outFile.beg);
        if (length > 0) {
            m_lastLog.resize(length);
            m_outFile.read(&m_lastLog[0], length);
            m_lastLog.resize(m_outFile.gcount());
        }
        m_outFile.close();
    }

    // Do NOT wipe the log on every start: append so the crashed run's log
    // survives into the next boot, where the crash reporter ships it. Only once
    // the file has grown past MAX_LOG_FILE_SIZE do we reset it (std::ios::trunc).
    const bool reset = fileSize > MAX_LOG_FILE_SIZE;
    m_outFile.open(stdext::utf8_to_latin1(file.c_str()).c_str(),
                   std::ios::out | (reset ? std::ios::trunc : std::ios::app));
    if(!m_outFile.is_open() || !m_outFile.good()) {
        g_logger.error(stdext::format("Unable to save log to '%s'", file));
        return;
    }

    // Mark the start of each run so the accumulated (multi-run) log stays readable.
    m_outFile << "\n==== log session started: " << stdext::date_time_string() << " ====\n";
    m_outFile.flush();
}

std::string Logger::getRecentLog()
{
    // try_to_lock: never block (let alone deadlock) when called from the crash
    // handler while another thread may hold the mutex. Returns "" if it can't
    // safely read, and the crash reporter falls back to getLastLog().
    std::unique_lock<std::recursive_mutex> lock(m_mutex, std::try_to_lock);
    if(!lock.owns_lock())
        return std::string();
    std::string out;
    for(const LogMessage& msg : m_logMessages) {
        out += msg.message;
        out += '\n';
    }
    return out;
}

void fatalError(const char* error, const char* file, int line)
{
    g_logger.fatal(stdext::format("Fatal error: %s\nIn: %s:%i", error, file, line));
}
