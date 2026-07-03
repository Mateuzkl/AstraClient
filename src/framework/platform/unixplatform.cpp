/*
 * Copyright (c) 2010-2016 OTClient <https://github.com/edubart/otclient>
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

#if !defined(WIN32) && !defined(__EMSCRIPTEN__)

#include <framework/global.h>
#include "platform.h"
#include <fstream>
#include <unistd.h>
#include <string.h>
#include <framework/stdext/stdext.h>
#include <framework/core/eventdispatcher.h>
#include <framework/util/crypt.h>

#include <sys/stat.h>
#include <execinfo.h>

void Platform::processArgs(std::vector<std::string>& args)
{
    //nothing todo, linux args are already utf8 encoded
}

bool Platform::spawnProcess(std::string process, const std::vector<std::string>& args)
{
    struct stat sts;
    if(stat(process.c_str(), &sts) == -1 && errno == ENOENT)
        return false;

    pid_t pid = fork();
    if(pid == -1)
        return false;

    if(pid == 0) {
        char* cargs[args.size()+2];
        cargs[0] = (char*)process.c_str();
        for(uint i=1;i<=args.size();++i)
            cargs[i] = (char*)args[i-1].c_str();
        cargs[args.size()+1] = 0;

        if(execv(process.c_str(), cargs) == -1)
            _exit(EXIT_FAILURE);
    }

    return true;
}

int Platform::getProcessId()
{
    return getpid();
}

bool Platform::isProcessRunning(const std::string& name)
{
    return false;
}

bool Platform::killProcess(const std::string& name)
{
    return false;
}

std::string Platform::getTempPath()
{
    return "/tmp/";
}

std::string Platform::getCurrentDir()
{
    std::string res;
    char cwd[2048];
    if(getcwd(cwd, sizeof(cwd)) != NULL) {
        res = cwd;
        res += "/";
    }
    return res;
}

bool Platform::copyFile(std::string from, std::string to)
{
    return system(stdext::format("/bin/cp '%s' '%s'", from, to).c_str()) == 0;
}

bool Platform::fileExists(std::string file)
{
    struct stat buffer;
    return (stat(file.c_str(), &buffer) == 0);
}

bool Platform::removeFile(std::string file)
{
    if(unlink(file.c_str()) == 0)
        return true;
    return false;
}

ticks_t Platform::getFileModificationTime(std::string file)
{
    struct stat attrib;
    if(stat(file.c_str(), &attrib) == 0)
        return attrib.st_mtime;
    return 0;
}

bool Platform::openUrl(std::string url, bool now)
{
    if(now) {
        return system(stdext::format("xdg-open %s", url).c_str()) == 0;
    } else {
        g_dispatcher.scheduleEvent([url] {
            system(stdext::format("xdg-open %s", url).c_str());
        }, 50);
    }
    return true;
}

bool Platform::openDir(std::string path, bool now)
{
    if(now) {
        return system(stdext::format("xdg-open %s", path).c_str()) == 0;
    } else {
        g_dispatcher.scheduleEvent([path] {
            system(stdext::format("xdg-open %s", path).c_str());
        }, 50);
    }
    return true;
}

std::string Platform::getCPUName()
{
    std::string line;
    std::ifstream in("/proc/cpuinfo");
    while(getline(in, line)) {
        auto strs = stdext::split(line, ":");
        std::string first = strs[0];
        std::string second = strs[1];
        stdext::trim(first);
        stdext::trim(second);
        if(strs.size() == 2 && first == "model name")
            return second;
    }
    return std::string();
}

double Platform::getTotalSystemMemory()
{
    std::string line;
    std::ifstream in("/proc/meminfo");
    while(getline(in, line)) {
        auto strs = stdext::split(line, ":");
        std::string first = strs[0];
        std::string second = strs[1];
        stdext::trim(first);
        stdext::trim(second);
        if(strs.size() == 2 && first == "MemTotal")
            return stdext::unsafe_cast<double>(second.substr(0, second.length() - 3)) * 1000.0;
    }
    return 0;
}

double Platform::getMemoryUsage()
{
    return 0;
}

std::string Platform::getOSName()
{
    std::string line;
    std::ifstream in("/etc/issue");
    if(getline(in, line)) {
        std::size_t end = line.find('\\');
        std::string res = line.substr(0, end);
        stdext::trim(res);
        return res;
    }
    return std::string();
}

std::string Platform::traceback(const std::string& where, int level, int maxDepth)
{
    std::stringstream ss;

    ss << "\nC++ stack traceback:";
    if(!where.empty())
        ss << "\n\t[C++]: " << where;

    void* buffer[maxDepth + level + 1];
    int numLevels = backtrace(buffer, maxDepth + level + 1);
    char **tracebackBuffer = backtrace_symbols(buffer, numLevels);
    if(tracebackBuffer) {
        for(int i = 1 + level; i < numLevels; i++) {
            std::string line = tracebackBuffer[i];
            if(line.find("__libc_start_main") != std::string::npos)
                break;
            std::size_t demanglePos = line.find("(_Z");
            if(demanglePos != std::string::npos) {
                demanglePos++;
                int len = std::min(line.find_first_of("+", demanglePos), line.find_first_of(")", demanglePos)) - demanglePos;
                std::string funcName = line.substr(demanglePos, len);
                line.replace(demanglePos, len, stdext::demangle_name(funcName.c_str()));
            }
            ss << "\n\t" << line;
        }
        free(tracebackBuffer);
    }

    return ss.str();
}

std::vector<std::string> Platform::getMacAddresses()
{
    return std::vector<std::string>();
}

std::string Platform::getUserName()
{
    char buffer[30];
    getlogin_r(buffer, sizeof(buffer) - 1);
    buffer[29] = 0; // just in case
    return std::string(buffer);
}

std::vector<std::string> Platform::getDlls()
{
    return std::vector<std::string>();
}

std::vector<std::string> Platform::getProcesses()
{
    return std::vector<std::string>();
}

std::vector<std::string> Platform::getWindows()
{
    return std::vector<std::string>();
}

// Reads a file's first line, trimmed of trailing whitespace. "" if unreadable.
static std::string readTrimmedLine(const char* path)
{
    std::ifstream f(path);
    std::string s;
    if (f.is_open())
        std::getline(f, s);
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' '))
        s.pop_back();
    return s;
}

// Stable, hashed hardware id, or "" if nothing usable is found. /etc/machine-id
// (a per-install id, world-readable and stable across reboots) is the reliable
// anchor, because the SMBIOS product_uuid is root-only (0400) on most distros and
// would otherwise be empty for normal users; the uuid is folded in as an extra
// signal when readable. Each source is consistently present or absent per machine,
// so the fingerprint is stable across sessions. Hashed so raw ids never hit Lua.
std::string Platform::getHardwareId()
{
    std::string fingerprint;
    const auto append = [&](const char* label, const std::string& value) {
        if (value.empty())
            return;
        if (!fingerprint.empty())
            fingerprint += ';';
        fingerprint += label;
        fingerprint += ':';
        fingerprint += value;
    };

    std::string machineId = readTrimmedLine("/etc/machine-id");
    if (machineId.empty())
        machineId = readTrimmedLine("/var/lib/dbus/machine-id");
    append("mid", machineId);
    append("uuid", readTrimmedLine("/sys/class/dmi/id/product_uuid"));

    if (fingerprint.empty())
        return std::string();
    return g_crypt.sha256Encode(fingerprint, false);
}

// True when the lower-cased string contains a vendor/product marker that only
// appears on virtual machines. Kept precise to avoid false-positives: bare
// "microsoft"/"google" are deliberately NOT markers (physical Surface / Chromebook
// report them), so Hyper-V / GCE are caught via their product strings instead.
static bool hasVmMarker(std::string s)
{
    for (char& c : s) {
        if (c >= 'A' && c <= 'Z')
            c += 32; // ASCII lower-case
    }
    static const char* markers[] = {
        "vmware", "virtualbox", "innotek", "qemu", "kvm", "xen",
        "parallels", "bochs", "bhyve", "virtual machine",
        "google compute engine", "amazon ec2", "openstack"
    };
    for (const char* m : markers) {
        if (s.find(m) != std::string::npos)
            return true;
    }
    return false;
}

// True when the client runs inside a virtual machine. The DMI vendor fields
// (bios/system/board) are world-readable (unlike product_uuid), so this works
// without root; a physical host keeps its real vendor there. Checking several
// fields makes it harder to hide a VM by spoofing a single one. Returns false when
// DMI is unavailable.
bool Platform::isVirtualMachine()
{
    return hasVmMarker(readTrimmedLine("/sys/class/dmi/id/bios_vendor"))
        || hasVmMarker(readTrimmedLine("/sys/class/dmi/id/sys_vendor"))
        || hasVmMarker(readTrimmedLine("/sys/class/dmi/id/product_name"))
        || hasVmMarker(readTrimmedLine("/sys/class/dmi/id/board_vendor"));
}


#endif
