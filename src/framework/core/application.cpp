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

#include "application.h"
#include <csignal>
#include <filesystem>
#include <framework/core/clock.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/modulemanager.h>
#include <framework/core/eventdispatcher.h>
#include <framework/core/configmanager.h>
#include "asyncdispatcher.h"
#include <framework/luaengine/luainterface.h>
#include <framework/platform/crashhandler.h>
#include <framework/platform/platform.h>
#include <framework/http/http.h>

#include <locale>

#include <framework/net/connection.h>
#include <framework/proxy/proxy.h>

void exitSignalHandler(int sig)
{
    static bool signaled = false;
    switch(sig) {
        case SIGTERM:
        case SIGINT:
            if(!signaled && !g_app.isStopping() && !g_app.isTerminated()) {
                signaled = true;
                g_dispatcher.addEvent(std::bind(&Application::close, &g_app));
            }
            break;
    }
}

Application::Application()
{
    m_appName = "application";
    m_appCompactName = "app";
    m_appVersion = "none";
    m_charset = "cp1252";
    m_stopping = false;
}

void Application::init(std::vector<std::string>& args)
{
    // capture exit signals
    signal(SIGTERM, exitSignalHandler);
    signal(SIGINT, exitSignalHandler);

    // setup locale
    std::locale::global(std::locale());

    // process args encoding
    g_platform.processArgs(args);

    g_asyncDispatcher.init();

    std::string startupOptions;
    for(uint i=1;i<args.size();++i) {
        const std::string& arg = args[i];
        startupOptions += " ";
        startupOptions += arg;
    }
    if(startupOptions.length() > 0)
        g_logger.info(stdext::format("Startup options: %s", startupOptions));

    m_startupOptions = startupOptions;

    // initialize configs
    g_configs.init();

    // initialize lua
    g_lua.init();
    registerLuaFunctions();

    // initalize proxy
    g_proxy.init();
}

void Application::deinit()
{
    g_lua.callGlobalField("g_app", "onTerminate");

    // run modules unload events
    g_modules.unloadModules();
    g_modules.clear();

    // terminate proxy before garbage collection to ensure
    // Protocol objects are properly released
    g_proxy.terminate();

    // poll remaining events after proxy termination
    poll();

    // release remaining lua object references
    g_lua.collectGarbage();

    // poll remaining events
    poll();

    // disable dispatcher events
    g_dispatcher.shutdown();
}

void Application::terminate()
{
    // terminate network
    Connection::terminate();

    // release configs
    g_configs.terminate();

    // release resources
    g_resources.terminate();

    // terminate script environment
    g_lua.terminate();

    m_terminated = true;

    signal(SIGTERM, SIG_DFL);
    signal(SIGINT, SIG_DFL);
}

void Application::poll()
{
    Connection::poll();

    g_dispatcher.poll();

    // poll connection again to flush pending write
    Connection::poll();
}

void Application::exit()
{
    g_lua.callGlobalField<bool>("g_app", "onExit");
    m_stopping = true;
}

void Application::quick_exit()
{
#ifdef _MSC_VER
    ::quick_exit(0);
#else
    ::exit(0);
#endif
}

void Application::close()
{
    if(!g_lua.callGlobalField<bool>("g_app", "onClose"))
        exit();
}

// Boost.Process v2 dropped child/wait_for/detach. Restart helpers use
// CreateProcessA directly — same fire-and-forget semantics, no dep.
static void spawnAndDetach(const std::string& binary, const std::string& cmdTail = "")
{
    STARTUPINFOA si{}; si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    std::string cmdLine = binary;
    if (!cmdTail.empty()) { cmdLine += " "; cmdLine += cmdTail; }
    std::vector<char> cmdMutable(cmdLine.begin(), cmdLine.end());
    cmdMutable.push_back('\0');
    if (CreateProcessA(nullptr, cmdMutable.data(), nullptr, nullptr, FALSE,
                       0, nullptr, nullptr, &si, &pi)) {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
}

void Application::restart()
{
    spawnAndDetach(g_resources.getBinaryName());
    quick_exit();
}

void Application::restartArgs(const std::vector<std::string>& args)
{
    std::string tail;
    for (const auto& a : args) {
        if (!tail.empty()) tail += " ";
        tail += a;
    }
    spawnAndDetach(g_resources.getBinaryName(), tail);
    quick_exit();
}

bool Application::launchBinary(const std::string& binaryName, const std::string& args)
{
    // Resolve relative to the working dir (= the client's folder, same convention restart()
    // uses with getBinaryName). If the sibling binary isn't installed, don't close.
    if (binaryName.empty() || !std::filesystem::exists(binaryName)) {
        g_logger.error(stdext::format("launchBinary: '%s' not found next to the client", binaryName));
        return false;
    }
    spawnAndDetach(binaryName, args);
    quick_exit();
    return true;
}

std::string Application::getOs()
{
#if defined(WIN32)
    return "windows";
#elif defined(__APPLE__)
    return "mac";
#elif __linux
    return "linux";
#else
    return "unknown";
#endif
}

