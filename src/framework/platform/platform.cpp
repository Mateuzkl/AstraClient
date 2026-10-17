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

#include "platform.h"
#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#include <emscripten/em_js.h>
#include <cstdlib>
#include <memory>
EM_JS_DEPS(astra_credential_helpers, "$stringToNewUTF8");
#endif

Platform g_platform;

bool Platform::canRememberWebPassword()
{
#ifdef __EMSCRIPTEN__
    return MAIN_THREAD_EM_ASM_INT({ return Module.astraCredentials && Module.astraCredentials.available() ? 1 : 0; }) != 0;
#else
    return false;
#endif
}

std::string Platform::getWebCredentials(const std::string& scope)
{
#ifdef __EMSCRIPTEN__
    if (scope.size() > 2048 || scope.find('\0') != std::string::npos) return {};
    const std::unique_ptr<char, decltype(&std::free)> value(static_cast<char*>(MAIN_THREAD_EM_ASM_PTR({
        return stringToNewUTF8(Module.astraCredentials ? Module.astraCredentials.get(UTF8ToString($0)) : "");
    }, scope.c_str())), &std::free);
    return value ? value.get() : "";
#else
    return {};
#endif
}

bool Platform::saveWebCredentials(const std::string& scope, const std::string& account, const std::string& password)
{
#ifdef __EMSCRIPTEN__
    if (scope.size() > 2048 || account.size() > 2048 || password.size() > 4096 ||
        scope.find('\0') != std::string::npos || account.find('\0') != std::string::npos ||
        password.find('\0') != std::string::npos) return false;
    return MAIN_THREAD_EM_ASM_INT({
        return Module.astraCredentials && Module.astraCredentials.save(UTF8ToString($0), UTF8ToString($1), UTF8ToString($2)) ? 1 : 0;
    }, scope.c_str(), account.c_str(), password.c_str()) != 0;
#else
    return false;
#endif
}

void Platform::forgetWebCredentials()
{
#ifdef __EMSCRIPTEN__
    MAIN_THREAD_EM_ASM({ if (Module.astraCredentials) Module.astraCredentials.forget(); });
#endif
}

void Platform::allowWebPasswordStorage()
{
#ifdef __EMSCRIPTEN__
    MAIN_THREAD_EM_ASM({ if (Module.astraCredentials) Module.astraCredentials.allowSaving(); });
#endif
}
