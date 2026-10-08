#include <framework/stdext/listparser.h>
#include <framework/stdext/string.h>
#include <framework/util/uuid.h>
#include <framework/platform/process.h>
#include <cstdlib>
#include <iostream>

static void check(bool value)
{
    if (!value)
        std::abort();
}
int main()
{
    using stdext::parseList;
    check(parseList("").empty());
    check(parseList("a,,b,") == std::vector<std::string>({"a", "", "b", ""}));
    check(parseList("\"a,b\",c\\,d,\\\"quote\\\",\\n,\\\\") ==
          std::vector<std::string>({"a,b", "c,d", "\"quote\"", "\n", "\\"}));
    bool invalid = false;
    try
    {
        parseList("bad\\q");
    }
    catch (...)
    {
        invalid = true;
    }
    check(invalid);
    invalid = false;
    try
    {
        parseList("bad\\");
    }
    catch (...)
    {
        invalid = true;
    }
    check(invalid);
    std::string text = " \t test \r\n";
    stdext::trim(text);
    check(text == "test");
    text = " \t\r\n";
    stdext::trim(text);
    check(text.empty());
    check(stdext::split(",a,,b,", ",") == std::vector<std::string>({"", "a", "", "b", ""}));
    check(stdext::split("", ",") == std::vector<std::string>({""}));
    check(stdext::starts_with("abc", "") && stdext::ends_with("abc", ""));
    check(!stdext::starts_with("a", "ab") && !stdext::ends_with("a", "ab"));
    text = "aaa";
    stdext::replace_all(text, "a", "aa");
    check(text == "aaaaaa");
    stdext::replace_all(text, "", "b");
    check(text == "aaaaaa");
    stdext::replace_all(text, "a", "");
    check(text.empty());
    check(stdext::unhex("00AfFF") == std::string("\0\xaf\xff", 3));
    invalid = false;
    try
    {
        stdext::unhex("0");
    }
    catch (...)
    {
        invalid = true;
    }
    check(invalid);
    invalid = false;
    try
    {
        stdext::unhex("0x");
    }
    catch (...)
    {
        invalid = true;
    }
    check(invalid);
    const astra_uuid::Uuid dns = {0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
                                  0x80, 0xb4, 0,    0xc0, 0x4f, 0xd4, 0x30, 0xc8};
    check(astra_uuid::toString(astra_uuid::name(dns, "www.widgets.com")) == "21f7f8de-8051-5b89-8680-0195ef798b6a");
    check(astra_uuid::settingsHash(astra_uuid::Uuid{}) == 0);
    astra_uuid::Uuid oldSpace{};
    for (size_t j = 0; j < oldSpace.size(); ++j)
        oldSpace[j] = static_cast<unsigned char>(j * 17);
    const auto oldKey = astra_uuid::name(oldSpace, "Astra settings compatibility");
    // Golden vector generated with the previous pinned Boost UUID implementation.
    check(astra_uuid::toString(oldKey) == "c51f51e7-fefe-5d70-ba6e-478fbfdb78cb");
    check(astra_uuid::settingsHash(oldKey) == static_cast<size_t>(11813889962551506301ULL));
    check(astra_process::quoteArgument("") == "\"\"");
    check(astra_process::quoteArgument("a b") == "\"a b\"");
    check(astra_process::quoteArgument("a\"b") == "\"a\\\"b\"");
    check(astra_process::quoteArgument("C:\\folder\\") == "\"C:\\folder\\\\\"");
    std::cout << "Standalone utility compatibility PASS\n";
}
