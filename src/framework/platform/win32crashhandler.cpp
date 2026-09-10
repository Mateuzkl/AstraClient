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

#if defined(WIN32) && defined(CRASH_HANDLER)

#include "crashhandler.h"
#include <framework/global.h>
#include <framework/core/application.h>
#include <framework/core/resourcemanager.h>

#include <winsock2.h>
#include <windows.h>
#include <process.h>

#ifdef _MSC_VER

#pragma warning (push)
#pragma warning (disable:4091) // warning C4091: 'typedef ': ignored on left of '' when no variable is declared
#include <imagehlp.h>
#pragma warning (pop)

#else

#include <imagehlp.h>

#endif

bool quiet_crash = false;

namespace {

constexpr int MAX_STACK_FRAMES = 64;

std::string formatAddress(const DWORD64 address, const int width = 16)
{
    std::ostringstream stream;
    stream << "0x" << std::uppercase << std::hex << std::setfill('0') << std::setw(width) << address;
    return stream.str();
}

DWORD64 getModuleBaseForAddress(const HANDLE process, const DWORD64 address, const bool symbolsInitialized)
{
    if(symbolsInitialized) {
        const DWORD64 moduleBase = SymGetModuleBase64(process, address);
        if(moduleBase != 0)
            return moduleBase;
    }

    MEMORY_BASIC_INFORMATION memoryInfo{};
    const auto pointer = reinterpret_cast<LPCVOID>(static_cast<ULONG_PTR>(address));
    if(VirtualQuery(pointer, &memoryInfo, sizeof(memoryInfo)) != 0)
        return static_cast<DWORD64>(reinterpret_cast<ULONG_PTR>(memoryInfo.AllocationBase));

    return 0;
}

std::string getModuleName(const DWORD64 moduleBase)
{
    if(moduleBase == 0)
        return "Unknown";

    char moduleName[MAX_PATH] = {};
    const DWORD length = GetModuleFileNameA(
        reinterpret_cast<HMODULE>(static_cast<ULONG_PTR>(moduleBase)), moduleName, MAX_PATH);
    if(length == 0)
        return "Unknown";

    moduleName[MAX_PATH - 1] = '\0';
    return moduleName;
}

bool writeMiniDump(const std::filesystem::path& path, const HANDLE process,
                   const PEXCEPTION_POINTERS exception, const MINIDUMP_TYPE flags)
{
    const HANDLE dumpFile = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                                        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if(dumpFile == INVALID_HANDLE_VALUE)
        return false;

    MINIDUMP_EXCEPTION_INFORMATION exceptionInformation{};
    exceptionInformation.ThreadId = GetCurrentThreadId();
    exceptionInformation.ExceptionPointers = exception;
    exceptionInformation.ClientPointers = FALSE;
    const bool written = MiniDumpWriteDump(process, GetProcessId(process), dumpFile, flags,
                                           exception ? &exceptionInformation : nullptr, nullptr, nullptr) == TRUE;
    const DWORD error = written ? ERROR_SUCCESS : GetLastError();
    CloseHandle(dumpFile);

    if(!written)
        SetLastError(error);
    return written;
}

} // namespace

const char *getExceptionName(DWORD exceptionCode)
{
    switch (exceptionCode) {
        case EXCEPTION_ACCESS_VIOLATION:         return "Access violation";
        case EXCEPTION_DATATYPE_MISALIGNMENT:    return "Datatype misalignment";
        case EXCEPTION_BREAKPOINT:               return "Breakpoint";
        case EXCEPTION_SINGLE_STEP:              return "Single step";
        case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:    return "Array bounds exceeded";
        case EXCEPTION_FLT_DENORMAL_OPERAND:     return "Float denormal operand";
        case EXCEPTION_FLT_DIVIDE_BY_ZERO:       return "Float divide by zero";
        case EXCEPTION_FLT_INEXACT_RESULT:       return "Float inexact result";
        case EXCEPTION_FLT_INVALID_OPERATION:    return "Float invalid operation";
        case EXCEPTION_FLT_OVERFLOW:             return "Float overflow";
        case EXCEPTION_FLT_STACK_CHECK:          return "Float stack check";
        case EXCEPTION_FLT_UNDERFLOW:            return "Float underflow";
        case EXCEPTION_INT_DIVIDE_BY_ZERO:       return "Integer divide by zero";
        case EXCEPTION_INT_OVERFLOW:             return "Integer overflow";
        case EXCEPTION_PRIV_INSTRUCTION:         return "Privileged instruction";
        case EXCEPTION_IN_PAGE_ERROR:            return "In page error";
        case EXCEPTION_ILLEGAL_INSTRUCTION:      return "Illegal instruction";
        case EXCEPTION_NONCONTINUABLE_EXCEPTION: return "Noncontinuable exception";
        case EXCEPTION_STACK_OVERFLOW:           return "Stack overflow";
        case EXCEPTION_INVALID_DISPOSITION:      return "Invalid disposition";
        case EXCEPTION_GUARD_PAGE:               return "Guard page";
        case EXCEPTION_INVALID_HANDLE:           return "Invalid handle";
    }
    return "Unknown exception";
}

void Stacktrace(LPEXCEPTION_POINTERS e, std::stringstream& ss)
{
    STACKFRAME64 frame{};
    DWORD machineType;
    CONTEXT context = *e->ContextRecord;
    alignas(SYMBOL_INFO) char symbolBuffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME] = {};
    auto* symbol = reinterpret_cast<PSYMBOL_INFO>(symbolBuffer);
    symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
    symbol->MaxNameLen = MAX_SYM_NAME;

#ifdef _WIN64
    frame.AddrPC.Offset = context.Rip;
    frame.AddrStack.Offset = context.Rsp;
    frame.AddrFrame.Offset = context.Rbp;
    machineType = IMAGE_FILE_MACHINE_AMD64;
#else
    frame.AddrPC.Offset = context.Eip;
    frame.AddrStack.Offset = context.Esp;
    frame.AddrFrame.Offset = context.Ebp;
    machineType = IMAGE_FILE_MACHINE_I386;
#endif

    frame.AddrPC.Mode = AddrModeFlat;
    frame.AddrStack.Mode = AddrModeFlat;
    frame.AddrFrame.Mode = AddrModeFlat;

    const HANDLE process = GetCurrentProcess();
    const HANDLE thread = GetCurrentThread();

    const auto logFrame = [&](const int count, const DWORD64 address) {
        const DWORD64 moduleBase = getModuleBaseForAddress(process, address, true);
        const std::string moduleName = getModuleName(moduleBase);
        DWORD64 displacement = 0;

        ss << "    " << count << ": " << moduleName;
        if(SymFromAddr(process, address, &displacement, symbol))
            ss << "(" << symbol->Name << "+" << formatAddress(displacement, 1) << ")";
        else if(moduleBase != 0)
            ss << "+" << formatAddress(address - moduleBase, 1);
        ss << " [" << formatAddress(address) << "]\n";

        IMAGEHLP_LINE64 line{};
        line.SizeOfStruct = sizeof(line);
        DWORD lineDisplacement = 0;
        if(SymGetLineFromAddr64(process, address, &lineDisplacement, &line))
            ss << "       at " << line.FileName << ":" << line.LineNumber
               << " (+" << formatAddress(lineDisplacement, 1) << ")\n";
    };

    int count = 0;
    DWORD64 previousAddress = frame.AddrPC.Offset;
    if(previousAddress != 0)
        logFrame(count++, previousAddress);

    while(count < MAX_STACK_FRAMES) {
        if(!StackWalk64(machineType, process, thread, &frame, &context, nullptr,
                        SymFunctionTableAccess64, SymGetModuleBase64, nullptr) || frame.AddrPC.Offset == 0)
            break;

        const DWORD64 address = frame.AddrPC.Offset;
        if(address == previousAddress)
            break;

        logFrame(count++, address);
        previousAddress = address;
    }
}

LONG CALLBACK ExceptionHandler(PEXCEPTION_POINTERS e)
{
    // generate crash report
    const HANDLE process = GetCurrentProcess();
    SymSetOptions(SymGetOptions() | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES | SYMOPT_UNDNAME);
    const bool symbolsInitialized = SymInitialize(process, nullptr, TRUE) == TRUE;
    const DWORD64 exceptionAddress = static_cast<DWORD64>(reinterpret_cast<ULONG_PTR>(e->ExceptionRecord->ExceptionAddress));
    const DWORD64 moduleBase = getModuleBaseForAddress(process, exceptionAddress, symbolsInitialized);

    std::stringstream ss;
    ss << "== application crashed\n";
    ss << stdext::format("app name: %s\n", g_app.getName());
    ss << stdext::format("app version: %s\n", g_app.getVersion());
    ss << stdext::format("build compiler: %s\n", BUILD_COMPILER);
    ss << stdext::format("build date: %s\n", __DATE__);
    ss << stdext::format("build type: %s\n", BUILD_TYPE);
    ss << stdext::format("build revision: %s (%s)\n", BUILD_REVISION, BUILD_COMMIT);
    ss << stdext::format("crash date: %s\n", stdext::date_time_string());
    ss << "exception: " << getExceptionName(e->ExceptionRecord->ExceptionCode)
       << " (" << formatAddress(e->ExceptionRecord->ExceptionCode, 8) << ")\n";
    ss << "exception address: " << formatAddress(exceptionAddress) << "\n";
    ss << "fault module: " << getModuleName(moduleBase) << "\n";
    ss << "fault module base: " << formatAddress(moduleBase) << "\n";
    ss << "fault rva: " << formatAddress(moduleBase != 0 ? exceptionAddress - moduleBase : exceptionAddress, 1) << "\n";

    if(e->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION &&
       e->ExceptionRecord->NumberParameters >= 2) {
        const ULONG_PTR operation = e->ExceptionRecord->ExceptionInformation[0];
        const char* operationName = operation == 0 ? "read" : operation == 1 ? "write" : operation == 8 ? "execute" : "access";
        ss << "access violation: " << operationName << " at "
           << formatAddress(static_cast<DWORD64>(e->ExceptionRecord->ExceptionInformation[1])) << "\n";
    }

    ss << "  backtrace:\n";
    if(symbolsInitialized)
        Stacktrace(e, ss);
    else
        ss << "    symbol initialization failed\n";
    ss << "\n";
    if(symbolsInitialized)
        SymCleanup(process);

    // print in stdout
    g_logger.info(ss.str());

    // write stacktrace to crashreport.log
    auto dumpFilePath = std::filesystem::path(g_resources.getWriteDir());
    dumpFilePath /= "crashreport.log";
    std::ofstream fout(dumpFilePath, std::ios::out | std::ios::app);
    if(fout.is_open() && fout.good()) {
        fout << ss.str();
        fout.close();
        g_logger.info(stdext::format("Crash report saved to file %s", dumpFilePath.string()));
    } else
        g_logger.error("Failed to save crash report!");

    // inform the user
    std::string msg = std::string(
        "The application has crashed.\n\n"
        "A crash report has been written to:\n") + dumpFilePath.string();
    if(!g_app.isStopping() && !quiet_crash) {
        MessageBoxA(NULL, msg.c_str(), "Application crashed", 0);
    }

    // this seems to silently close the application
    //return EXCEPTION_EXECUTE_HANDLER;

    // this triggers the microsoft "application has crashed" error dialog
    return EXCEPTION_CONTINUE_SEARCH;
}


#define TRACE_DUMP_NAME "exception.dmp"
#define TRACE_DUMP_NAME_QUIET "exception2.dmp"
#define TRACE_DUMP_NAME_FULL "exception_full.dmp"

LONG WINAPI UnhandledExceptionFilter2(PEXCEPTION_POINTERS exception)
{
    const HANDLE process = GetCurrentProcess();

    auto dumpFilePath = std::filesystem::path(g_resources.getWriteDir());
    if (quiet_crash) {
        dumpFilePath /= TRACE_DUMP_NAME_QUIET;
    } else {
        dumpFilePath /= TRACE_DUMP_NAME;
    }
    const auto normalDumpFlags = static_cast<MINIDUMP_TYPE>(MiniDumpWithIndirectlyReferencedMemory | MiniDumpScanMemory);
    if(!writeMiniDump(dumpFilePath, process, exception, normalDumpFlags)) {
        const DWORD error = GetLastError();
        DeleteFileW(dumpFilePath.c_str());
        g_logger.error(stdext::format("Failed to write minidump %s (Windows error %lu).",
                                     dumpFilePath.string(), error));
    }

    {
        dumpFilePath = std::filesystem::path(g_resources.getWriteDir());
        dumpFilePath /= TRACE_DUMP_NAME_FULL;
        const auto fullDumpFlags = static_cast<MINIDUMP_TYPE>(MiniDumpWithPrivateReadWriteMemory |
            MiniDumpWithDataSegs |
            MiniDumpWithHandleData |
            MiniDumpWithFullMemoryInfo |
            MiniDumpWithThreadInfo |
            MiniDumpWithUnloadedModules);
        if(!writeMiniDump(dumpFilePath, process, exception, fullDumpFlags)) {
            const DWORD error = GetLastError();
            DeleteFileW(dumpFilePath.c_str());
            g_logger.error(stdext::format("Failed to write minidump %s (Windows error %lu).",
                                         dumpFilePath.string(), error));
        }
    }

    if (quiet_crash) {
#ifdef _MSC_VER
        quick_exit(0);
#else
        exit(0);
#endif
    }

    Sleep(1000);
    ExceptionHandler(exception);

    return EXCEPTION_CONTINUE_SEARCH;
}

void installCrashHandler()
{
    SetUnhandledExceptionFilter(UnhandledExceptionFilter2);
}

void uninstallCrashHandler()
{
    quiet_crash = true;
}

#endif
