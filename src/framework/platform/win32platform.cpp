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

#ifdef WIN32

#include "platform.h"
#include <winsock2.h>
#include <windows.h>
#include <framework/global.h>
#include <framework/stdext/stdext.h>
#include <framework/core/eventdispatcher.h>
#include <boost/algorithm/string.hpp>
#include <tchar.h>
#include <Psapi.h>
#include <iphlpapi.h>
#include <tlhelp32.h>
#include <intrin.h>
#include <cstring>
#include <framework/util/crypt.h>

void Platform::processArgs(std::vector<std::string>& args)
{
    int nargs;
    wchar_t** wchar_argv = CommandLineToArgvW(GetCommandLineW(), &nargs);
    if (!wchar_argv)
        return;

    args.clear();
    if (wchar_argv) {
        for (int i = 0; i < nargs; ++i)
            args.push_back(stdext::utf16_to_utf8(wchar_argv[i]));
    }
}

bool Platform::spawnProcess(std::string process, const std::vector<std::string>& args)
{
    std::string commandLine;
    for (uint i = 0; i < args.size(); ++i)
        commandLine += stdext::format(" \"%s\"", args[i]);

    boost::replace_all(process, "/", "\\");
    if (!boost::ends_with(process, ".exe"))
        process += ".exe";

    std::wstring wfile = stdext::utf8_to_utf16(process);
    std::wstring wcommandLine = stdext::utf8_to_utf16(commandLine);

    if ((size_t)ShellExecuteW(NULL, L"open", wfile.c_str(), wcommandLine.c_str(), NULL, SW_SHOWNORMAL) > 32)
        return true;
    return false;
}

int Platform::getProcessId()
{
    return GetCurrentProcessId();
}

bool Platform::isProcessRunning(const std::string& name)
{
    if (FindWindowA(name.c_str(), NULL) != NULL)
        return true;
    return false;
}

bool Platform::killProcess(const std::string& name)
{
    HWND window = FindWindowA(name.c_str(), NULL);
    if (window == NULL)
        return false;
    DWORD pid = GetProcessId(window);
    HANDLE handle = OpenProcess(PROCESS_ALL_ACCESS, false, pid);
    if (handle == NULL)
        return false;
    bool ok = TerminateProcess(handle, 1) != 0;
    CloseHandle(handle);
    return ok;
}

std::string Platform::getTempPath()
{
    std::string ret;
    wchar_t path[MAX_PATH];
    GetTempPathW(MAX_PATH, path);
    ret = stdext::utf16_to_utf8(path);
    boost::replace_all(ret, "\\", "/");
    return ret;
}

std::string Platform::getCurrentDir()
{
    std::string ret;
    wchar_t path[MAX_PATH];
    GetCurrentDirectoryW(MAX_PATH, path);
    ret = stdext::utf16_to_utf8(path);
    boost::replace_all(ret, "\\", "/");
    ret += "/";
    return ret;
}

bool Platform::fileExists(std::string file)
{
    boost::replace_all(file, "/", "\\");
    std::wstring wfile = stdext::utf8_to_utf16(file);
    DWORD dwAttrib = GetFileAttributesW(wfile.c_str());
    return (dwAttrib != INVALID_FILE_ATTRIBUTES && !(dwAttrib & FILE_ATTRIBUTE_DIRECTORY));
}

bool Platform::copyFile(std::string from, std::string to)
{
    boost::replace_all(from, "/", "\\");
    boost::replace_all(to, "/", "\\");
    if (CopyFileW(stdext::utf8_to_utf16(from).c_str(), stdext::utf8_to_utf16(to).c_str(), FALSE) == 0)
        return false;
    return true;
}

bool Platform::removeFile(std::string file)
{
    boost::replace_all(file, "/", "\\");
    if (DeleteFileW(stdext::utf8_to_utf16(file).c_str()) == 0)
        return false;
    return true;
}

ticks_t Platform::getFileModificationTime(std::string file)
{
    boost::replace_all(file, "/", "\\");
    std::wstring wfile = stdext::utf8_to_utf16(file);
    WIN32_FILE_ATTRIBUTE_DATA fileAttrData;
    memset(&fileAttrData, 0, sizeof(fileAttrData));
    GetFileAttributesExW(wfile.c_str(), GetFileExInfoStandard, &fileAttrData);
    ULARGE_INTEGER uli;
    uli.LowPart = fileAttrData.ftLastWriteTime.dwLowDateTime;
    uli.HighPart = fileAttrData.ftLastWriteTime.dwHighDateTime;
    return uli.QuadPart;
}

bool Platform::openUrl(std::string url, bool now)
{
    if (now) {
        return (size_t)ShellExecuteW(NULL, L"open", stdext::utf8_to_utf16(url).c_str(), NULL, NULL, SW_SHOWNORMAL) >= 32;
    } else {
        g_dispatcher.scheduleEvent([url] {
            ShellExecuteW(NULL, L"open", stdext::utf8_to_utf16(url).c_str(), NULL, NULL, SW_SHOWNORMAL);
        }, 50);
    }
    return true;
}

bool Platform::openDir(std::string path, bool now)
{
    if (now) {
        return (size_t)ShellExecuteW(NULL, L"open", L"explorer.exe", stdext::utf8_to_utf16(path).c_str(), NULL, SW_SHOWNORMAL) >= 32;
    } else {
        g_dispatcher.scheduleEvent([path] {
            ShellExecuteW(NULL, L"open", L"explorer.exe", stdext::utf8_to_utf16(path).c_str(), NULL, SW_SHOWNORMAL);
        }, 50);
    }
    return true;
}

std::string Platform::getCPUName()
{
    char buf[1024];
    memset(buf, 0, sizeof(buf));
    DWORD bufSize = sizeof(buf);
    HKEY hKey;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", 0, KEY_READ, &hKey) != ERROR_SUCCESS)
        return "";
    RegQueryValueExA(hKey, "ProcessorNameString", NULL, NULL, (LPBYTE)buf, (LPDWORD)&bufSize);
    return buf;
}

double Platform::getTotalSystemMemory()
{
    MEMORYSTATUSEX status;
    status.dwLength = sizeof(status);
    GlobalMemoryStatusEx(&status);
    return status.ullTotalPhys;
}

double Platform::getMemoryUsage()
{
    PROCESS_MEMORY_COUNTERS pmc;
    GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc));
    return pmc.WorkingSetSize;
}

std::string Platform::getOSName()
{
    typedef LONG(WINAPI* RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);

    RTL_OSVERSIONINFOEXW osInfo = { 0 };
    osInfo.dwOSVersionInfoSize = sizeof(osInfo);

    HMODULE hNtDll = GetModuleHandleA("ntdll.dll");
    if (hNtDll == NULL)
        return std::string();

    RtlGetVersionPtr RtlGetVersion = (RtlGetVersionPtr)GetProcAddress(hNtDll, "RtlGetVersion");
    if (RtlGetVersion == NULL)
        return std::string();

    if (RtlGetVersion((PRTL_OSVERSIONINFOW)&osInfo) != 0)
        return std::string();

    DWORD productType = 0;
    typedef BOOL(WINAPI* GetProductInfoPtr)(DWORD, DWORD, DWORD, DWORD, PDWORD);
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    if (hKernel32 == NULL)
        return std::string();

    GetProductInfoPtr GetProductInfo = (GetProductInfoPtr)GetProcAddress(hKernel32, "GetProductInfo");

    if (GetProductInfo)
        GetProductInfo(osInfo.dwMajorVersion, osInfo.dwMinorVersion, 0, 0, &productType);

    std::string osName = "Windows ";
    if (osInfo.dwMajorVersion == 10) {
        if (osInfo.dwBuildNumber >= 22000)
            osName += "11";
        else
            osName += "10";
    }
    else if (osInfo.dwMajorVersion == 6) {
        if (osInfo.dwMinorVersion == 3)
            osName += "8.1";
        else if (osInfo.dwMinorVersion == 2)
            osName += "8";
        else if (osInfo.dwMinorVersion == 1)
            osName += "7";
        else if (osInfo.dwMinorVersion == 0) {
            if (osInfo.wProductType == VER_NT_WORKSTATION)
                osName += "Vista";
            else {
                osName += "Server 2008";
                switch (productType) {
                case PRODUCT_STANDARD_SERVER: osName += " Standard"; break;
                case PRODUCT_ENTERPRISE_SERVER: osName += " Enterprise"; break;
                case PRODUCT_DATACENTER_SERVER: osName += " Datacenter"; break;
                case PRODUCT_WEB_SERVER: osName += " Web Edition"; break;
                default: osName += " Edition";
                }
            }
        }
    }
    else if (osInfo.dwMajorVersion == 5) {
        if (osInfo.dwMinorVersion == 2)
            osName += "Server 2003/XP x64";
        else if (osInfo.dwMinorVersion == 1)
            osName += "XP";
        else
            osName += "2000";
    }
    else {
        osName += "Unknown";
    }

    SYSTEM_INFO si;
    GetNativeSystemInfo(&si);

    switch (si.wProcessorArchitecture) {
    case PROCESSOR_ARCHITECTURE_AMD64: {
        osName += ", 64-bit";
        break;
    }
    case PROCESSOR_ARCHITECTURE_INTEL: {
        osName += ", 32-bit";
        break;
    }
    case PROCESSOR_ARCHITECTURE_ARM64: {
        osName += ", ARM64";
        break;
    }
    case PROCESSOR_ARCHITECTURE_ARM: {
        osName += ", ARM";
        break;
    }
    default: {
        osName += ", Unknown Architecture";
        break;
    }
    }

    return osName;
}

std::string Platform::traceback(const std::string& where, int level, int maxDepth)
{
    std::stringstream ss;
    ss << "\nat:";
    ss << "\n\t[C++]: " << where;
    return ss.str();
}

std::vector<std::string> Platform::getMacAddresses()
{
    std::vector<std::string> ret;
    IP_ADAPTER_INFO AdapterInfo[32];
    DWORD dwBufLen = sizeof(AdapterInfo);

    DWORD dwStatus = GetAdaptersInfo(AdapterInfo, &dwBufLen);
    if (dwStatus != ERROR_SUCCESS) {
        return ret;
    }

    PIP_ADAPTER_INFO pAdapterInfo = AdapterInfo; // Contains pointer to  current adapter info
    do {
        char buffer[20];
        sprintf_s(buffer, sizeof(buffer), "%02x%02x%02x%02x%02x%02x%02x%02x", pAdapterInfo->Address[0], pAdapterInfo->Address[1], pAdapterInfo->Address[2],
                  pAdapterInfo->Address[3], pAdapterInfo->Address[4], pAdapterInfo->Address[5], pAdapterInfo->Address[6], pAdapterInfo->Address[7]);
        ret.push_back(std::string(buffer));
        pAdapterInfo = pAdapterInfo->Next;    // Progress through linked list
    } while (pAdapterInfo);                    // Terminate if last adapter
    std::sort(ret.begin(), ret.end());
    return ret;
}


std::string Platform::getUserName()
{
    char buffer[30];
    DWORD length = sizeof(buffer) - 1;
    GetUserNameA(buffer, &length);
    buffer[29] = 0; // just in case
    return std::string(buffer);
}

std::vector<std::string> Platform::getDlls()
{
    HMODULE hMods[1024];
    DWORD cbNeeded;

    std::vector<std::string> ret;
    HANDLE hProcess = GetCurrentProcess();
    if (!hProcess) 
        return ret;

    if (EnumProcessModules(hProcess, hMods, sizeof(hMods), &cbNeeded)) {
        for (unsigned int i = 0; i < (cbNeeded / sizeof(HMODULE)); i++) {
            char szModName[MAX_PATH];
            if (GetModuleFileNameExA(hProcess, hMods[i], szModName,
                                    sizeof(szModName) / sizeof(TCHAR))) {
                ret.push_back(szModName);
            }
        }
    }

    return ret;
}

std::vector<std::string> Platform::getProcesses()
{
    std::vector<std::string> ret;

    HANDLE hProcessSnap;
    PROCESSENTRY32 pe32;
    hProcessSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

    if (hProcessSnap == INVALID_HANDLE_VALUE) {
        return ret;
    }

    pe32.dwSize = sizeof(PROCESSENTRY32);
    if (!Process32First(hProcessSnap, &pe32)) {
        CloseHandle(hProcessSnap);
        return ret;
    }

    do {
        ret.push_back(pe32.szExeFile);
    } while (Process32Next(hProcessSnap, &pe32));
    CloseHandle(hProcessSnap);

    return ret;
}

std::vector<std::string> windows;
BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lParam)
{
    char title[50];
    GetWindowText(hwnd, title, sizeof(title));
    title[sizeof(title) - 1] = 0;
    std::string window_title(title);
    if (window_title.size() >= 2) {
        windows.push_back(window_title);
    }
    return TRUE;
}

std::vector<std::string> Platform::getWindows()
{
    windows.clear();
    EnumWindows(EnumWindowsProc, NULL);
    return windows;
}

// Parsed SMBIOS records used for the hardware id and VM detection: type-0 BIOS
// vendor, type-1 "System Information" (firmware UUID + manufacturer/product), and
// type-2 "Baseboard" (manufacturer + serial). More fields = more VM tells to catch
// and a harder-to-spoof physical fingerprint.
struct SmbiosInfo {
    std::string uuid;              // canonical text, "" if absent / not-set sentinel
    std::string biosVendor;       // e.g. "American Megatrends", "innotek GmbH", "SeaBIOS"
    std::string manufacturer;     // e.g. "ASUS", "VMware, Inc.", "Microsoft Corporation"
    std::string product;          // e.g. "ROG STRIX", "VirtualBox", "Virtual Machine"
    std::string boardManufacturer;// e.g. "ASUSTeK", "Oracle Corporation", "QEMU"
    std::string boardSerial;      // motherboard serial (SMBIOS type 2), "" if absent
};

// Returns the index-th (1-based) string from an SMBIOS structure's trailing
// string-set. Index 0 means "no string".
static std::string smbiosStringAt(const uint8_t* strStart, const uint8_t* end, uint8_t index)
{
    if (index == 0)
        return std::string();
    const uint8_t* s = strStart;
    uint8_t cur = 1;
    while (s < end && *s != 0) {
        const uint8_t* begin = s;
        while (s < end && *s != 0)
            ++s;
        if (cur == index)
            return std::string(reinterpret_cast<const char*>(begin), s - begin);
        ++s; // skip the terminating NUL
        ++cur;
    }
    return std::string();
}

// Reads the SMBIOS type-0 (BIOS), type-1 (system) and type-2 (baseboard) records
// via GetSystemFirmwareTable. No admin, no WMI.
static SmbiosInfo getSmbiosInfo()
{
    SmbiosInfo info;
    const DWORD RSMB = ('R' << 24) | ('S' << 16) | ('M' << 8) | 'B';

    DWORD size = GetSystemFirmwareTable(RSMB, 0, nullptr, 0);
    if (size == 0)
        return info;

    std::vector<uint8_t> buffer(size);
    DWORD written = GetSystemFirmwareTable(RSMB, 0, buffer.data(), size);
    if (written == 0 || written > size || written <= 8)
        return info;

    // RawSMBIOSData header is 8 bytes; the packed SMBIOS structures follow.
    const uint8_t* p = buffer.data() + 8;
    const uint8_t* const end = buffer.data() + written;

    while (p + 4 <= end) {
        const uint8_t type = p[0];
        const uint8_t headerLen = p[1];
        if (headerLen < 4 || p + headerLen > end)
            break; // malformed

        const uint8_t* strStart = p + headerLen;

        if (type == 0 && headerLen >= 0x05) {
            // BIOS Information: vendor string index at offset 0x04.
            info.biosVendor = smbiosStringAt(strStart, end, p[0x04]);
        } else if (type == 1 && headerLen >= 0x08) {
            info.manufacturer = smbiosStringAt(strStart, end, p[0x04]);
            info.product = smbiosStringAt(strStart, end, p[0x05]);

            if (headerLen >= 0x18) {
                const uint8_t* u = p + 0x08; // UUID: 16 bytes at offset 0x08
                bool allZero = true, allFF = true;
                for (int i = 0; i < 16; ++i) {
                    if (u[i] != 0x00) allZero = false;
                    if (u[i] != 0xFF) allFF = false;
                }
                if (!allZero && !allFF) {
                    // SMBIOS 2.6+ stores the first three groups little-endian;
                    // print it like "wmic csproduct get uuid" for easy checking.
                    char out[37];
                    sprintf_s(out, sizeof(out),
                              "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                              u[3], u[2], u[1], u[0], u[5], u[4], u[7], u[6],
                              u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]);
                    info.uuid = out;
                }
            }
        } else if (type == 2 && headerLen >= 0x08) {
            // Baseboard: manufacturer at offset 0x04, serial number at 0x07.
            info.boardManufacturer = smbiosStringAt(strStart, end, p[0x04]);
            info.boardSerial = smbiosStringAt(strStart, end, p[0x07]);
        } else if (type == 127) {
            break; // end-of-table marker
        }

        // Skip the formatted area, then the trailing string-set (ends at 0x0000).
        const uint8_t* s = p + headerLen;
        while (s + 1 < end && !(s[0] == 0 && s[1] == 0))
            ++s;
        p = s + 2; // step past the double-NUL terminator
    }
    return info;
}

// True only when running under a hypervisor we can positively identify as a
// *guest*. Deliberately excludes "Microsoft Hv": a physical Win11 host with VBS /
// Hyper-V / WSL2 enabled also reports it, so it is not a reliable guest signal (a
// genuine Hyper-V guest is caught by its SMBIOS "Virtual Machine" product name).
static bool cpuidHypervisorIsGuest()
{
    int regs[4] = { 0 };
    __cpuid(regs, 1);
    if ((regs[2] & (1 << 31)) == 0)
        return false; // hypervisor-present bit clear -> bare metal

    __cpuid(regs, 0x40000000);
    char brand[13] = { 0 };
    std::memcpy(brand + 0, &regs[1], 4); // EBX
    std::memcpy(brand + 4, &regs[2], 4); // ECX
    std::memcpy(brand + 8, &regs[3], 4); // EDX
    const std::string b(brand);

    static const char* guestBrands[] = {
        "VMwareVMware", "VBoxVBoxVBox", "KVMKVMKVM", "XenVMMXenVMM",
        "prl hyperv", "TCGTCGTCGTCG", "bhyve bhyve"
    };
    for (const char* gb : guestBrands) {
        if (b.find(gb) != std::string::npos)
            return true;
    }
    return false;
}

// Windows per-install identifier from the registry. Generated at OS setup, stable
// across reboots/hardware swaps, present on every Windows (and provided by Wine),
// and readable without admin -- the reliable anchor when SMBIOS is zeroed/absent.
static std::string getRegistryMachineGuid()
{
    HKEY hKey;
    // Force the 64-bit view so a 32-bit client reads the real key, not the
    // WOW6432Node redirect.
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Cryptography",
                      0, KEY_READ | KEY_WOW64_64KEY, &hKey) != ERROR_SUCCESS)
        return std::string();

    char buffer[128] = { 0 };
    DWORD size = sizeof(buffer) - 1;
    DWORD type = 0;
    const LONG res = RegQueryValueExA(hKey, "MachineGuid", nullptr, &type,
                                      reinterpret_cast<LPBYTE>(buffer), &size);
    RegCloseKey(hKey);
    if (res != ERROR_SUCCESS || type != REG_SZ)
        return std::string();
    return std::string(buffer); // NUL-terminated REG_SZ
}

// Stable, hashed hardware id for this machine, or "" if nothing usable is found.
// Combines every strong per-machine identifier available (registry MachineGuid,
// SMBIOS system UUID, motherboard serial) into one labeled fingerprint, then
// hashes it. Combining (a) keeps the id non-empty when any single source is
// missing -- e.g. privacy firmware zeroing the SMBIOS UUID, or a locked-down
// machine -- and (b) makes two machines that share one weak id (cloned images,
// spoofed SMBIOS) still differ on the others, so they don't collide. Each source
// is consistently present or absent per machine, so the fingerprint is stable
// across sessions. Hashing keeps the raw ids inside C++ (never exposed to Lua).
std::string Platform::getHardwareId()
{
    const SmbiosInfo info = getSmbiosInfo();

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
    append("mguid", getRegistryMachineGuid());
    append("uuid", info.uuid);
    append("board", info.boardSerial);

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

// True when the client runs inside a virtual machine. Checks every SMBIOS vendor
// field (BIOS, system, baseboard) -- a physical host keeps its real vendor there
// even with WSL2 / Hyper-V / VBS active -- and falls back to the CPUID hypervisor
// guest brand. Multiple fields make it harder for a multiboxer to hide a VM by
// spoofing a single string, without adding false positives on physical machines.
bool Platform::isVirtualMachine()
{
    const SmbiosInfo info = getSmbiosInfo();
    if (hasVmMarker(info.biosVendor) || hasVmMarker(info.manufacturer)
        || hasVmMarker(info.product) || hasVmMarker(info.boardManufacturer))
        return true;
    return cpuidHypervisorIsGuest();
}

#endif
