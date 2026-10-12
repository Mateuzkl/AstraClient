#include <framework/stdext/cxx23.h>
#include <framework/stdext/filesystem.h>
#include <cstdio>

int main()
{
    const std::u8string utf8 = u8"Astra/ação/日本/🌍.zip";
    const auto result = stdext::path_to_utf8(std::filesystem::path(utf8));
    const std::string expected(utf8.begin(), utf8.end());
    if (result != expected || stdext::path_to_utf8({}) != "") return 1;
    std::puts("C++23 UTF-8 filesystem/C API byte preservation: PASS");
    return 0;
}
