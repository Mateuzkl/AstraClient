// Windows-only test. Build with nativesplash.cpp, apngloader.cpp, GDI+ and zlib.
#include "../../src/framework/graphics/apngloader.h"
#include "../../src/framework/platform/nativesplash.h"
// clang-format off
#include <winsock2.h>
#include <windows.h>
// clang-format on

#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace nativeSplashDetail
{
bool splashFrameCacheFits(unsigned width, unsigned height, unsigned frames);
bool validateSplashPng(const std::string& bytes, unsigned& frameCount);
} // namespace nativeSplashDetail

void check(bool condition, const char* message)
{
    if (!condition)
        throw std::runtime_error(message);
}

struct DecodedPng
{
    apng_data data{};
    ~DecodedPng() { free_apng(&data); }
    void load(const std::filesystem::path& path)
    {
        std::ifstream file(path, std::ios::binary);
        check(bool(file), "PNG fixture missing");
        std::stringstream bytes;
        bytes << file.rdbuf();
        check(load_apng(bytes, &data) == 0 && data.pdata && data.bpp == 4, "PNG decode failed");
    }
};

uint64_t pngHash(const std::filesystem::path& path)
{
    DecodedPng decoded;
    decoded.load(path);
    const auto& png = decoded.data;
    const size_t frameBytes = size_t(png.width) * png.height * 4;
    uint64_t hash = 14695981039346656037ull;
    for (size_t i = size_t(png.first_frame) * frameBytes; i < size_t(png.last_frame + 1) * frameBytes; ++i)
        hash = (hash ^ png.pdata[i]) * 1099511628211ull;
    return hash;
}

void checkAnimation(const std::filesystem::path& path)
{
    DecodedPng decoded;
    decoded.load(path);
    const auto& png = decoded.data;
    check(png.num_frames > 1 && png.last_frame > png.first_frame && png.frames_delay, "splash must be animated");
    const size_t frameBytes = size_t(png.width) * png.height * 4;
    const auto* first = png.pdata + png.first_frame * frameBytes;
    bool changed = false;
    for (unsigned frame = 1; frame < png.num_frames; ++frame)
    {
        check(png.frames_delay[frame] > 0, "APNG frame delay missing");
        changed |= std::memcmp(first, first + frame * frameBytes, frameBytes) != 0;
    }
    check(changed, "APNG frames must change");
    std::cout << "Animated artwork: " << png.num_frames << " frames decoded.\n";
}

HWND splashWindow()
{
    HWND window = nullptr;
    while ((window = FindWindowExW(nullptr, window, L"AstraClientNativeSplash", nullptr)))
    {
        DWORD owner = 0;
        GetWindowThreadProcessId(window, &owner);
        if (owner == GetCurrentProcessId())
            return window;
    }
    return nullptr;
}

HWND waitForSplash()
{
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < deadline)
    {
        const HWND window = splashWindow();
        if (window && IsWindowVisible(window))
            return window;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    throw std::runtime_error("splash did not become visible");
}

void waitForStatus(const wchar_t* expected)
{
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < deadline)
    {
        wchar_t title[256]{};
        GetWindowTextW(splashWindow(), title, 256);
        if (std::wstring(title).find(expected) != std::wstring::npos)
            return;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    throw std::runtime_error("splash progress did not update");
}

int main(int argc, char** argv)
{
    try
    {
        for (unsigned size : {400u, 500u, 600u, 800u, 1200u})
            check(nativeSplashDetail::splashFrameCacheFits(size, size, 5), "real APNG exceeds DPI frame budget");
        check(!nativeSplashDetail::splashFrameCacheFits(1200, 1200, 64), "high-DPI frame cache must be bounded");
        check(!nativeSplashDetail::splashFrameCacheFits(0, 400, 5), "empty frame cache must be rejected");
        wchar_t executable[32768]{};
        check(GetModuleFileNameW(nullptr, executable, 32768), "test executable path");
        const auto image = std::filesystem::path(executable).parent_path() / L"data" / L"images" / L"splash.png";
        {
            std::ifstream file(image, std::ios::binary);
            std::stringstream stream;
            stream << file.rdbuf();
            const std::string png = stream.str();
            unsigned frames = 0;
            check(nativeSplashDetail::validateSplashPng(png, frames) && frames > 1, "real APNG preflight");
            check(!nativeSplashDetail::validateSplashPng(png.substr(0, png.size() / 2), frames),
                  "truncated APNG accepted");
            auto corrupt = png;
            const auto control = corrupt.find("acTL");
            check(control != std::string::npos, "animation control fixture");
            corrupt.replace(control, 4, "zzzz");
            check(!nativeSplashDetail::validateSplashPng(corrupt, frames),
                  "frame controls without allocation accepted");
            corrupt = png;
            corrupt[25] = 1;
            check(!nativeSplashDetail::validateSplashPng(corrupt, frames), "unsupported color layout accepted");
        }
        checkAnimation(image);
        const auto cursor = std::filesystem::path(argc > 1 ? argv[1] : "data/cursors") / "cip-default.png";
        const auto transparent = cursor.parent_path() / "cursor-walk.png";
        const auto staticImage = cursor.parent_path() / "textcursor.png";
        const uint64_t expectedCursor = pngHash(cursor);
        const uint64_t expectedTransparent = pngHash(transparent), expectedStatic = pngHash(staticImage);
        setNativeSplashEnabled(false);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        check(!splashWindow(), "disabled startup must never show a splash");
        setNativeSplashEnabled(true);
        // Paletted client textures must remain correct while the splash decoder runs.
        for (int i = 0; i < 100; ++i)
        {
            check(pngHash(cursor) == expectedCursor, "concurrent PNG decoding corrupted the client texture");
            check(pngHash(transparent) == expectedTransparent, "concurrent tRNS decoding corrupted the client texture");
            check(pngHash(staticImage) == expectedStatic, "concurrent static decoding corrupted the client texture");
        }
        const HWND window = waitForSplash();
        waitForStatus(L"0%");
        setNativeSplashProgress(50, "Loading modules...");
        waitForStatus(L"50%");
        setNativeSplashProgress(50, "Carregando m\xc3\xb3"
                                    "dulos...");
        waitForStatus(L"Carregando m\u00f3dulos... 50%");
        setNativeSplashProgress(50, "Loading modules...");
        setNativeSplashProgress(10, "Old stage");
        waitForStatus(L"Loading modules... 50%");
        setNativeSplashProgress(500, "Waiting for the first frame...");
        waitForStatus(L"99%");
        const auto styles = GetWindowLongPtrW(window, GWL_EXSTYLE);
        check((styles & (WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW)) ==
                  (WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW),
              "splash transparency/focus styles");
        RECT rect{};
        check(GetWindowRect(window, &rect), "splash bounds");
        check(rect.right > rect.left && rect.bottom > rect.top, "splash must have a visible size");
        showNativeSplash();
        check(splashWindow() == window, "duplicate show must not replace the window");
        setNativeSplashEnabled(false);
        hideNativeSplash();

        showNativeSplash();
        finishNativeSplash(); // Client is ready before the worker prepares its first window.
        const auto lateDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(1);
        while (std::chrono::steady_clock::now() < lateDeadline)
        {
            check(!splashWindow() || !IsWindowVisible(splashWindow()), "first-frame completion allowed a late splash");
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        hideNativeSplash();
        check(!splashWindow(), "hide must synchronously destroy the window");
        showNativeSplash();
        waitForSplash();
        finishNativeSplash();
        waitForStatus(L"100%");
        finishNativeSplash();
        setNativeSplashProgress(20, "Late stage");
        waitForStatus(L"Ready to play 100%");
        std::this_thread::sleep_for(std::chrono::milliseconds(400));
        check(!splashWindow(), "first-frame completion must dismiss the splash");
        hideNativeSplash();

        const DWORD gdi = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
        const DWORD user = GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS);
        DWORD handles = 0;
        check(GetProcessHandleCount(GetCurrentProcess(), &handles), "baseline handle count");
        for (int i = 0; i < 20; ++i)
        {
            showNativeSplash();
            waitForSplash();
            hideNativeSplash();
            showNativeSplash();
            hideNativeSplash(); // Stop may arrive before decoding/window creation.
            check(!splashWindow(), "an early stop must never leave a late splash");
        }
        const auto toggle = []
        {
            for (int i = 0; i < 20; ++i)
            {
                showNativeSplash();
                setNativeSplashProgress(50, "Concurrent startup");
                hideNativeSplash();
            }
        };
        std::thread first(toggle), second(toggle);
        first.join();
        second.join();
        hideNativeSplash();
        check(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == gdi, "leaked GDI resources");
        check(GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS) == user, "leaked USER resources");
        DWORD remainingHandles = 0;
        check(GetProcessHandleCount(GetCurrentProcess(), &remainingHandles), "final handle count");
        check(remainingHandles == handles, "leaked thread/event handles");

        // Only change the copied fixture beside this isolated test executable.
        const auto saved = image.parent_path() / L"splash.fixture.png";
        check(!std::filesystem::exists(saved), "fixture backup already exists");
        std::filesystem::rename(image, saved);
        try
        {
            showNativeSplash();
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            check(!splashWindow(), "missing artwork must skip the splash");
            // An ended missing-artwork worker must be reaped by a retry, without hide().
            std::filesystem::copy_file(saved, image);
            showNativeSplash();
            waitForSplash();
            hideNativeSplash();
            std::filesystem::remove(image);
            {
                std::ofstream invalid(image, std::ios::binary);
                invalid << "not a PNG";
            }
            showNativeSplash();
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            check(!splashWindow(), "invalid artwork must skip the splash");
            hideNativeSplash();
        }
        catch (...)
        {
            hideNativeSplash();
            std::filesystem::remove(image);
            std::filesystem::rename(saved, image);
            throw;
        }
        std::filesystem::remove(image);
        std::filesystem::rename(saved, image);
        std::cout << "Native splash: concurrent decoding, progress, visibility, lifetime, missing/invalid artwork "
                     "and 20 resource cycles passed.\n";
    }
    catch (const std::exception& error)
    {
        hideNativeSplash();
        std::cerr << error.what() << '\n';
        return 1;
    }
}
