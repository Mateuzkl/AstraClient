#ifdef __EMSCRIPTEN__

#include "platform.h"

#include <emscripten/emscripten.h>
#include <emscripten/heap.h>
#include <filesystem>
#include <sys/stat.h>
#include <unistd.h>

void Platform::processArgs(std::vector<std::string>&) {}

bool Platform::spawnProcess(std::string, const std::vector<std::string>&) { return false; }

int Platform::getProcessId() { return static_cast<int>(getpid()); }

bool Platform::isProcessRunning(const std::string&) { return false; }

bool Platform::killProcess(const std::string&) { return false; }

std::string Platform::getTempPath() { return "/tmp"; }

std::string Platform::getCurrentDir() { return "/"; }

bool Platform::copyFile(std::string from, std::string to)
{
    std::error_code error;
    return std::filesystem::copy_file(from, to, std::filesystem::copy_options::overwrite_existing, error);
}

bool Platform::fileExists(std::string file) { return std::filesystem::exists(file); }

bool Platform::removeFile(std::string file)
{
    std::error_code error;
    return std::filesystem::remove(file, error);
}

ticks_t Platform::getFileModificationTime(std::string file)
{
    struct stat info{};
    return stat(file.c_str(), &info) == 0 ? static_cast<ticks_t>(info.st_mtime) : 0;
}

bool Platform::openUrl(std::string url, bool)
{
    return MAIN_THREAD_EM_ASM_INT({
        const url = UTF8ToString($0);
        try {
            const parsed = new URL(url, window.location.href);
            if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:')
                return 0;
            window.open(parsed.href, '_blank', 'noopener,noreferrer');
            return 1;
        } catch (_) {
            return 0;
        }
    }, url.c_str()) != 0;
}

bool Platform::openDir(std::string, bool) { return false; }

std::string Platform::getCPUName() { return "WebAssembly"; }

double Platform::getTotalSystemMemory()
{
    return MAIN_THREAD_EM_ASM_DOUBLE({ return (navigator.deviceMemory || 0) * 1024.0 * 1024.0 * 1024.0; });
}

double Platform::getMemoryUsage() { return static_cast<double>(emscripten_get_heap_size()); }

std::string Platform::getOSName() { return "Browser/WebAssembly"; }

std::string Platform::traceback(const std::string& where, int, int) { return where; }

std::vector<std::string> Platform::getMacAddresses() { return {}; }

std::string Platform::getUserName() { return "browser"; }

std::vector<std::string> Platform::getDlls() { return {}; }

std::vector<std::string> Platform::getProcesses() { return {}; }

std::vector<std::string> Platform::getWindows() { return {}; }

#endif
