// Real C++ -> main-thread JS -> UTF-8/heap bridge, without server credentials.
#include <cassert>
#include <iostream>
#include "../../src/framework/platform/platform.cpp"

int main()
{
    assert(g_platform.canRememberWebPassword());
    assert(g_platform.getWebCredentials("127.0.0.1:7171:860") == "{\"account\":\"fixture\",\"password\":\"synthetic\"}");
    for (int i = 0; i < 200; ++i)
        assert(!g_platform.getWebCredentials("127.0.0.1:7171:860").empty());
    assert(g_platform.saveWebCredentials("127.0.0.1:7171:860", "fixture", "synthetic"));
    g_platform.forgetWebCredentials();
    assert(g_platform.getWebCredentials("127.0.0.1:7171:860").empty());
    g_platform.allowWebPasswordStorage();
    assert(g_platform.saveWebCredentials("127.0.0.1:7171:860", "fixture", "synthetic"));
    std::cout << "Web credential bridge: main-thread ownership and UTF-8 allocation PASS\n";
}
