#include "nativesplash.h"

#if defined(WIN32) && !defined(__EMSCRIPTEN__)
#ifndef NOMINMAX
#define NOMINMAX
#endif
// clang-format off: WinSock must precede Windows, and GDI+ must follow it.
#include <winsock2.h>
#include <windows.h>
#include <gdiplus.h>
// clang-format on

#include "../graphics/apngloader.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace nativeSplashDetail
{
constexpr wchar_t windowClassName[] = L"AstraClientNativeSplash";
constexpr uint64_t maxScaledFrameBytes = 32ull * 1024 * 1024;

bool splashFrameCacheFits(unsigned width, unsigned height, unsigned frames)
{
    return width && height && frames && uint64_t(width) * height <= maxScaledFrameBytes / 4 / frames;
}

struct SplashAnimation
{
    std::vector<std::unique_ptr<Gdiplus::Bitmap>> frames;
    std::vector<unsigned> delays;
};

// Bound the legacy decoder's allocations before it reads animation control chunks.
bool validateSplashPng(const std::string& bytes, unsigned& frameCount)
{
    constexpr unsigned char signature[] = {137, 80, 78, 71, 13, 10, 26, 10};
    if (bytes.size() < 33 || memcmp(bytes.data(), signature, 8) != 0)
        return false;
    const auto read = [&](size_t pos)
    {
        const auto* p = reinterpret_cast<const unsigned char*>(bytes.data() + pos);
        return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3];
    };
    if (read(8) != 13 || bytes.compare(12, 4, "IHDR") != 0)
        return false;
    const uint64_t width = read(16), height = read(20);
    if (!width || !height || width > 4096 || height > 4096)
        return false;
    const unsigned depth = BYTE(bytes[24]), color = BYTE(bytes[25]);
    const bool validDepth = (color == 0 && (depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16)) ||
                            (color == 3 && (depth == 1 || depth == 2 || depth == 4 || depth == 8)) ||
                            ((color == 2 || color == 4 || color == 6) && (depth == 8 || depth == 16));
    if (!validDepth || bytes[26] || bytes[27] || bytes[28]) // Legacy decoder accepts only non-interlaced PNG.
        return false;
    const unsigned channels = color == 6 ? 4 : color == 2 ? 3 : color == 4 ? 2 : 1;
    const uint64_t imageBytes = ((width * depth * channels + 7) / 8 + 1) * height;
    const uint64_t compressedCapacity = imageBytes + ((imageBytes + 7) >> 3) + ((imageBytes + 63) >> 6) + 11;
    uint64_t compressedBytes = 0;
    bool animated = false;
    uint32_t frames = 1, controls = 0;
    for (size_t pos = 8; pos + 12 <= bytes.size();)
    {
        const size_t length = read(pos);
        if (length > bytes.size() - pos - 12)
            return false;
        if (bytes.compare(pos + 4, 4, "acTL") == 0)
        {
            if (length != 8 || animated || controls || compressedBytes)
                return false;
            animated = true;
            frames = read(pos + 8);
            if (!frames || frames > 64)
                return false;
        }
        else if (bytes.compare(pos + 4, 4, "fcTL") == 0)
        {
            if (length != 26 || !animated || ++controls > frames || BYTE(bytes[pos + 32]) > 2 ||
                BYTE(bytes[pos + 33]) > 1)
                return false;
            const uint64_t w = read(pos + 12), h = read(pos + 16);
            if (!w || !h || w + read(pos + 20) > width || h + read(pos + 24) > height)
                return false;
            compressedBytes = 0;
        }
        else if (bytes.compare(pos + 4, 4, "IDAT") == 0 || bytes.compare(pos + 4, 4, "fdAT") == 0)
        {
            const bool frameData = bytes.compare(pos + 4, 4, "fdAT") == 0;
            if (frameData && (length < 4 || !controls))
                return false;
            compressedBytes += length - (frameData ? 4 : 0);
            if (compressedBytes > compressedCapacity)
                return false; // The legacy compressed scratch buffer has fixed capacity.
        }
        else if ((bytes.compare(pos + 4, 4, "IHDR") == 0 && pos != 8) ||
                 (bytes.compare(pos + 4, 4, "PLTE") == 0 && (length > 768 || length % 3)) ||
                 (bytes.compare(pos + 4, 4, "tRNS") == 0 && length > 256))
        {
            return false;
        }
        else if (bytes.compare(pos + 4, 4, "IEND") == 0)
        {
            frameCount = frames;
            return length == 0 && compressedBytes && (!animated || controls == frames) &&
                   width * height * 4 * (frames + 1) <= 64 * 1024 * 1024;
        }
        pos += length + 12;
    }
    return false;
}

SplashAnimation loadSplashAnimation(const std::wstring& path, int width, int height, HANDLE stop)
{
    std::ifstream input(std::filesystem::path(path), std::ios::binary | std::ios::ate);
    if (!input)
        return {};
    const auto length = input.tellg();
    if (length <= 0 || length > 32 * 1024 * 1024)
        return {};
    std::string bytes(static_cast<size_t>(length), '\0');
    input.seekg(0);
    unsigned frameCount = 0;
    if (!input.read(bytes.data(), length) || !validateSplashPng(bytes, frameCount) ||
        !splashFrameCacheFits(width, height, frameCount) || WaitForSingleObject(stop, 0) != WAIT_TIMEOUT)
        return {};
    struct Decoded
    {
        apng_data data{};
        ~Decoded() { free_apng(&data); }
    } decoded;
    std::stringstream stream(std::move(bytes));
    std::string{}.swap(bytes); // C++17 stringstream copies its source; release that extra compressed buffer.
    if (load_apng(stream, &decoded.data) != 0 || !decoded.data.pdata || decoded.data.bpp != 4)
        return {};
    if (WaitForSingleObject(stop, 0) != WAIT_TIMEOUT)
        return {};
    auto& data = decoded.data;
    if (data.last_frame < data.first_frame)
        return {};
    const unsigned count = std::min(data.num_frames, data.last_frame - data.first_frame + 1);
    const size_t frameBytes = size_t(data.width) * data.height * 4;
    std::vector<BYTE> bgra(frameBytes);
    SplashAnimation result;
    for (unsigned frame = 0; frame < count; ++frame)
    {
        if (WaitForSingleObject(stop, 0) != WAIT_TIMEOUT)
            return {};
        const auto* rgba = data.pdata + (data.first_frame + frame) * frameBytes;
        for (size_t i = 0; i < frameBytes; i += 4)
        {
            if (i % 16384 == 0 && WaitForSingleObject(stop, 0) != WAIT_TIMEOUT)
                return {};
            const unsigned alpha = rgba[i + 3];
            bgra[i] = BYTE((rgba[i + 2] * alpha + 127) / 255);
            bgra[i + 1] = BYTE((rgba[i + 1] * alpha + 127) / 255);
            bgra[i + 2] = BYTE((rgba[i] * alpha + 127) / 255);
            bgra[i + 3] = BYTE(alpha);
        }
        Gdiplus::Bitmap original(data.width, data.height, data.width * 4, PixelFormat32bppPARGB, bgra.data());
        auto scaled = std::make_unique<Gdiplus::Bitmap>(width, height, PixelFormat32bppPARGB);
        Gdiplus::Graphics graphics(scaled.get());
        graphics.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
        graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
        if (graphics.DrawImage(&original, 0, 0, width, height) != Gdiplus::Ok)
            return {};
        result.frames.push_back(std::move(scaled));
        result.delays.push_back(data.frames_delay ? std::max(16u, unsigned(data.frames_delay[frame])) : 100u);
    }
    return result; // Full-resolution decoded frames and compressed bytes are released here.
}

struct GdiPlusRuntime
{
    ULONG_PTR token = 0;
    GdiPlusRuntime()
    {
        Gdiplus::GdiplusStartupInput input;
        if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok)
            token = 0;
    }
    ~GdiPlusRuntime()
    {
        if (token)
            Gdiplus::GdiplusShutdown(token);
    }
};

struct SplashSurface
{
    HDC screen = GetDC(nullptr);
    HDC memory = screen ? CreateCompatibleDC(screen) : nullptr;
    HBITMAP bitmap = nullptr;
    HGDIOBJ previous = nullptr;
    void* pixels = nullptr;

    bool create(int width, int height)
    {
        if (!memory)
            return false;
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = width;
        info.bmiHeader.biHeight = -height;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
        if (!bitmap || !pixels)
            return false;
        previous = SelectObject(memory, bitmap);
        return previous && previous != HGDI_ERROR;
    }

    ~SplashSurface()
    {
        if (previous && previous != HGDI_ERROR)
            SelectObject(memory, previous);
        if (bitmap)
            DeleteObject(bitmap);
        if (memory)
            DeleteDC(memory);
        if (screen)
            ReleaseDC(nullptr, screen);
    }
};

struct SplashWindowClass
{
    HINSTANCE instance = GetModuleHandleW(nullptr);
    ATOM atom = 0;
    ~SplashWindowClass()
    {
        if (atom)
            UnregisterClassW(windowClassName, instance);
    }
};

struct SplashWindow
{
    HWND handle = nullptr;
    ~SplashWindow()
    {
        if (handle && IsWindow(handle))
            DestroyWindow(handle);
    }
};

LRESULT CALLBACK splashWindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    if (message == WM_MOUSEACTIVATE)
        return MA_NOACTIVATE;
    return DefWindowProcW(window, message, wparam, lparam);
}

class NativeSplash
{
  public:
    ~NativeSplash() { hide(); }

    void show()
    {
        std::lock_guard<std::mutex> lifecycle(m_lifecycleMutex);
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (m_active || m_finished)
                return;
        }
        // A failed optional load can be retried without leaking an ended worker.
        if (m_thread.joinable())
        {
            m_thread.join();
            CloseHandle(m_stop);
            CloseHandle(m_changed);
            m_stop = m_changed = nullptr;
        }
        m_stop = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!m_stop)
            return;
        m_changed = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (!m_changed)
        {
            CloseHandle(m_stop);
            m_stop = nullptr;
            return;
        }
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_active = true;
            m_finished = false;
            m_visible = false;
            m_progress = 0;
            m_stage = L"Opening Astra Client...";
        }
        try
        {
            m_thread = std::thread(
                [this]
                {
                    try
                    {
                        run();
                    }
                    catch (...)
                    {
                        OutputDebugStringA("AstraClient: optional native splash preparation failed.\n");
                    } // Optional artwork must never prevent startup.
                    std::lock_guard<std::mutex> lock(m_mutex);
                    m_active = false;
                    m_visible = false;
                });
        }
        catch (...)
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_active = false;
            CloseHandle(m_changed);
            m_changed = nullptr;
            CloseHandle(m_stop);
            m_stop = nullptr;
        }
    }

    void progress(int percent, const char* stage, bool finished = false)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (!m_active || m_finished || !stage)
            return;
        percent = std::clamp(percent, 0, finished ? 100 : 99);
        if (percent < m_progress)
            return;
        const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, stage, -1, nullptr, 0);
        if (count <= 0 || count > 4096)
            return;
        std::wstring nextStage(count, L'\0');
        if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, stage, -1, nextStage.data(), count))
            return;
        nextStage.pop_back();
        if (percent == m_progress && nextStage == m_stage && !finished)
            return;
        m_progress = percent;
        m_stage = std::move(nextStage);
        m_finished = finished;
        if (finished && !m_visible)
            SetEvent(m_stop); // Never create a late splash after the first frame.
        SetEvent(m_changed);
    }

    void hide()
    {
        std::lock_guard<std::mutex> lifecycle(m_lifecycleMutex);
        if (!m_thread.joinable())
            return;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_active = false;
            SetEvent(m_stop);
        }
        m_thread.join(); // The window and every GDI resource are destroyed by their
                         // owning thread.
        std::lock_guard<std::mutex> lock(m_mutex);
        CloseHandle(m_stop);
        m_stop = nullptr;
        CloseHandle(m_changed);
        m_changed = nullptr;
        m_finished = false;
        m_visible = false;
    }

  private:
    bool stopped() const { return WaitForSingleObject(m_stop, 0) != WAIT_TIMEOUT; }

    void run()
    {
        std::array<wchar_t, 32768> executable{};
        const DWORD length = GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size()));
        if (!length || length >= executable.size() || stopped())
            return;
        const std::wstring path(executable.data(), length);
        const auto separator = path.find_last_of(L"\\/");
        if (separator == std::wstring::npos)
            return;
        const auto imagePath = path.substr(0, separator + 1) + L"data\\images\\splash.png";
        if (GetFileAttributesW(imagePath.c_str()) == INVALID_FILE_ATTRIBUTES)
            return;

        GdiPlusRuntime runtime;
        if (!runtime.token || stopped())
            return;
        std::unique_ptr<Gdiplus::Bitmap> image(Gdiplus::Bitmap::FromFile(imagePath.c_str()));
        if (!image || image->GetLastStatus() != Gdiplus::Ok || stopped())
            return;
        const UINT imageWidth = image->GetWidth(), imageHeight = image->GetHeight();
        if (!imageWidth || !imageHeight || imageWidth > 4096 || imageHeight > 4096)
            return;

        POINT cursor{};
        GetCursorPos(&cursor);
        MONITORINFO monitor{};
        monitor.cbSize = sizeof(monitor);
        if (!GetMonitorInfoW(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST), &monitor))
            return;
        const RECT work = monitor.rcWork;
        SplashSurface surface;
        if (!surface.screen)
            return;
        const double density = std::max(1, GetDeviceCaps(surface.screen, LOGPIXELSX)) / 96.0;
        const double scale = std::min({density, std::min(400.0 * density, (work.right - work.left) / 2.0) / imageWidth,
                                       std::min(400.0 * density, (work.bottom - work.top) / 2.0) / imageHeight});
        const int imageDisplayWidth = std::max(1, static_cast<int>(imageWidth * scale));
        const int imageDisplayHeight = std::max(1, static_cast<int>(imageHeight * scale));
        const int width = std::max(imageDisplayWidth, static_cast<int>(320 * density));
        const int height = imageDisplayHeight + static_cast<int>(80 * density);
        image.reset();
        auto animation = loadSplashAnimation(imagePath, imageDisplayWidth, imageDisplayHeight, m_stop);
        if (animation.frames.empty() || stopped() || !surface.create(width, height))
            return;

        SplashWindowClass registration;
        WNDCLASSW windowClass{};
        windowClass.lpfnWndProc = splashWindowProc;
        windowClass.hInstance = registration.instance;
        windowClass.lpszClassName = windowClassName;
        registration.atom = RegisterClassW(&windowClass);
        if (!registration.atom || stopped())
            return;
        POINT position{work.left + (work.right - work.left - width) / 2,
                       work.top + (work.bottom - work.top - height) / 2};
        SplashWindow window;
        window.handle = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST,
                                        windowClassName, L"AstraClient", WS_POPUP, position.x, position.y, width,
                                        height, nullptr, nullptr, registration.instance, nullptr);
        if (!window.handle || stopped())
            return;
        SIZE size{width, height};
        POINT origin{};
        BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
        Gdiplus::Bitmap target(width, height, width * 4, PixelFormat32bppPARGB, static_cast<BYTE*>(surface.pixels));
        Gdiplus::Graphics graphics(&target);
        Gdiplus::Font font(L"Segoe UI", Gdiplus::REAL(12 * density));
        Gdiplus::SolidBrush panel(Gdiplus::Color(245, 8, 15, 28)), text(Gdiplus::Color(255, 223, 235, 250));
        Gdiplus::SolidBrush track(Gdiplus::Color(255, 36, 52, 74)), fill(Gdiplus::Color(255, 84, 172, 248));
        Gdiplus::StringFormat labelFormat;
        labelFormat.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
        labelFormat.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
        const Gdiplus::REAL padding = Gdiplus::REAL(18 * density);
        const Gdiplus::REAL barTop = Gdiplus::REAL(imageDisplayHeight + 49 * density);
        const Gdiplus::REAL barWidth = width - 2 * padding;
        size_t frame = 0;
        using Clock = std::chrono::steady_clock;
        auto nextFrame = Clock::now() + std::chrono::milliseconds(animation.delays[0]);
        Clock::time_point fadeStart{};
        bool shown = false;
        const HANDLE events[] = {m_stop, m_changed};
        // Only animation/fade use deadlines. Progress comes exclusively from completed startup work.
        while (!stopped() && IsWindow(window.handle))
        {
            int percent;
            std::wstring stage;
            bool finished;
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                percent = m_progress;
                stage = m_stage;
                finished = m_finished;
            }
            const auto now = Clock::now();
            if (finished && fadeStart == Clock::time_point{})
                fadeStart = now;
            if (now >= nextFrame)
            {
                frame = (frame + 1) % animation.frames.size();
                nextFrame = now + std::chrono::milliseconds(animation.delays[frame]);
            }
            if (finished)
            {
                const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - fadeStart).count();
                if (elapsed >= 300)
                    break;
                blend.SourceConstantAlpha = BYTE(255 * (300 - elapsed) / 300);
            }
            graphics.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
            graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
            graphics.DrawImage(animation.frames[frame].get(), (width - imageDisplayWidth) / 2, 0);
            graphics.FillRectangle(&panel, 0, imageDisplayHeight, width, height - imageDisplayHeight);
            graphics.SetCompositingMode(Gdiplus::CompositingModeSourceOver);
            const auto number = std::to_wstring(percent) + L"%";
            graphics.DrawString(stage.c_str(), -1, &font,
                                Gdiplus::RectF(padding, Gdiplus::REAL(imageDisplayHeight + 15 * density),
                                               barWidth - Gdiplus::REAL(55 * density), Gdiplus::REAL(24 * density)),
                                &labelFormat, &text);
            graphics.DrawString(
                number.c_str(), -1, &font,
                Gdiplus::PointF(width - Gdiplus::REAL(58 * density), Gdiplus::REAL(imageDisplayHeight + 15 * density)),
                &text);
            graphics.FillRectangle(&track, padding, barTop, barWidth, Gdiplus::REAL(5 * density));
            if (percent)
                graphics.FillRectangle(&fill, padding, barTop, barWidth * percent / 100, Gdiplus::REAL(5 * density));
            graphics.Flush(Gdiplus::FlushIntentionSync);
            SetWindowTextW(window.handle, (stage + L" " + number).c_str());
            if (!UpdateLayeredWindow(window.handle, surface.screen, &position, &size, surface.memory, &origin, 0,
                                     &blend, ULW_ALPHA))
                break;
            if (!shown)
            {
                // Serialize first visibility with first-frame completion.
                std::lock_guard<std::mutex> lock(m_mutex);
                if (m_finished || !m_active || stopped())
                    break;
                ShowWindow(window.handle, SW_SHOWNOACTIVATE);
                m_visible = true;
                shown = true;
            }
            const auto remaining =
                std::chrono::duration_cast<std::chrono::milliseconds>(nextFrame - Clock::now()).count();
            const DWORD timeout = finished                      ? 16
                                  : animation.frames.size() > 1 ? DWORD(std::max<int64_t>(1, remaining))
                                                                : INFINITE;
            const DWORD wake = MsgWaitForMultipleObjects(2, events, FALSE, timeout, QS_ALLINPUT);
            if (wake == WAIT_OBJECT_0 || wake == WAIT_FAILED)
                break;
            MSG message;
            while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE))
            {
                if (message.message == WM_QUIT)
                    return;
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
        }
    }

    HANDLE m_stop = nullptr;
    HANDLE m_changed = nullptr;
    std::thread m_thread;
    std::mutex m_lifecycleMutex;
    std::mutex m_mutex;
    bool m_active = false, m_finished = false, m_visible = false;
    int m_progress = 0;
    std::wstring m_stage;
};

NativeSplash& instance()
{
    static NativeSplash splash;
    return splash;
}
} // namespace nativeSplashDetail

void showNativeSplash() { nativeSplashDetail::instance().show(); }
void setNativeSplashEnabled(bool enabled)
{
    if (enabled)
        showNativeSplash();
    else
        hideNativeSplash();
}
void setNativeSplashProgress(int percent, const char* stage)
{
    nativeSplashDetail::instance().progress(percent, stage);
}
void finishNativeSplash() { nativeSplashDetail::instance().progress(100, "Ready to play", true); }
void hideNativeSplash() { nativeSplashDetail::instance().hide(); }
#endif
