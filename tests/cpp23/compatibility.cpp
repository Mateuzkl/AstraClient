#include <framework/stdext/cxx23.h>
#include <framework/global.h>
#include <framework/xml/tinyxml.h>
#include <framework/stdext/packed_storage.h>
#include <cstdio>

#ifndef NDEBUG
// TinyXML uses the production VALIDATE contract. Keep it fatal in this
// isolated test rather than linking the entire application or disabling it.
void fatalError(const char* error, const char* file, int line)
{
    std::fprintf(stderr, "%s:%d: %s\n", file, line, error);
    std::abort();
}
#endif

int main()
{
    TiXmlDocument document;
    document.Parse("<root existing=\"2.5\"/>");
    if (document.Error() || !document.RootElement()) return 1;
    double value = 9.0;
    const auto missing = document.RootElement()->Attribute(std::string("missing"), &value);
    if (!missing.empty() || value != 9.0) return 2;
    if (document.RootElement()->Attribute(std::string("existing"), &value) != "2.5" || value != 2.5) return 3;
    std::puts("C++23 TinyXML missing-string attribute preserves value/empty string: PASS");
    // Multiple keys expose misalignment hidden by a single packed entry.
    stdext::packed_storage<uint8> attributes;
    for (uint8 key = 0; key < 8; ++key) {
        attributes.set(key, std::string("value") + std::to_string(key));
    }
    auto copy = attributes;
    copy.remove(2);
    copy.set(3, std::string("updated"));
    auto moved = std::move(copy);
    if (moved.get<std::string>(3) != "updated" || attributes.get<std::string>(3) != "value3") return 4;
    std::puts("Runtime attribute copy/move/replace/remove alignment: PASS");
    return 0;
}
