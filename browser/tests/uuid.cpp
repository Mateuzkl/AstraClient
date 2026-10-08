#include <framework/util/uuid.h>
#include <cstdlib>

static void check(bool value)
{
    if (!value)
        std::abort();
}

int main()
{
    const astra_uuid::Uuid dns = {0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
                                  0x80, 0xb4, 0,    0xc0, 0x4f, 0xd4, 0x30, 0xc8};
    check(astra_uuid::toString(astra_uuid::name(dns, "www.widgets.com")) == "21f7f8de-8051-5b89-8680-0195ef798b6a");
    astra_uuid::Uuid space{};
    for (size_t j = 0; j < space.size(); ++j)
        space[j] = static_cast<unsigned char>(j * 17);
    const auto key = astra_uuid::name(space, "Astra settings compatibility");
    check(astra_uuid::toString(key) == "c51f51e7-fefe-5d70-ba6e-478fbfdb78cb");
    // Golden wasm32 vector from the previously used Emscripten Boost 1.83 port.
    check(astra_uuid::settingsHash(key) == 3204894813U);
}
