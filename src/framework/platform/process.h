#pragma once
#if !defined(ANDROID) && !defined(__EMSCRIPTEN__)
#include <chrono>
#include <string>
#include <thread>
#include <vector>
#ifdef WIN32
#include <windows.h>
#include <framework/stdext/string.h>
#else
#include <cerrno>
#include <filesystem>
#include <spawn.h>
#include <sys/wait.h>
extern char** environ;
#endif

namespace astra_process
{
enum class Result
{
    Failed,
    Exited,
    Running
};

inline std::string quoteArgument(const std::string& value)
{
    std::string quoted = "\"";
    size_t slashes = 0;
    for (const char c : value)
    {
        if (c == '\\')
        {
            ++slashes;
            continue;
        }
        quoted.append(c == '"' ? slashes * 2 + 1 : slashes, '\\');
        quoted += c;
        slashes = 0;
    }
    quoted.append(slashes * 2, '\\');
    quoted += '"';
    return quoted;
}

inline Result launch(const std::string& executable, const std::vector<std::string>& arguments, unsigned timeoutMs,
                     int& exitCode)
{
#ifdef WIN32
    const auto file = stdext::utf8_to_utf16(executable);
    std::string command = quoteArgument(executable);
    for (const auto& argument : arguments)
        command += " " + quoteArgument(argument);
    auto commandLine = stdext::utf8_to_utf16(command);
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(file.c_str(), commandLine.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr,
                        &startup, &process))
        return Result::Failed;
    CloseHandle(process.hThread);
    const DWORD waited = WaitForSingleObject(process.hProcess, timeoutMs);
    Result result = Result::Running;
    if (waited == WAIT_OBJECT_0)
    {
        DWORD status = 0;
        result = GetExitCodeProcess(process.hProcess, &status) ? Result::Exited : Result::Failed;
        exitCode = static_cast<int>(status);
    }
    else if (waited == WAIT_FAILED)
        result = Result::Failed;
    CloseHandle(process.hProcess);
    return result;
#else
    std::error_code pathError;
    const auto path = std::filesystem::absolute(executable, pathError);
    if (pathError || !path.is_absolute())
        return Result::Failed;
    const auto file = path.string();
    std::vector<char*> args;
    args.push_back(const_cast<char*>(file.c_str()));
    for (const auto& argument : arguments)
        args.push_back(const_cast<char*>(argument.c_str()));
    args.push_back(nullptr);
    pid_t pid = 0;
    if (posix_spawn(&pid, file.c_str(), nullptr, nullptr, args.data(), environ) != 0)
        return Result::Failed;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    do
    {
        int status = 0;
        const auto waited = waitpid(pid, &status, WNOHANG);
        if (waited == pid)
        {
            exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
            return Result::Exited;
        }
        if (waited < 0 && errno != EINTR)
            return Result::Failed;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (std::chrono::steady_clock::now() < deadline);
    // Reap a detached updater process without blocking application shutdown.
    std::thread(
        [pid]
        {
            int status;
            while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
            {
            }
        })
        .detach();
    return Result::Running;
#endif
}
} // namespace astra_process
#endif
