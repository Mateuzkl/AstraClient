// The calls inside assertions are part of the test, including in Release.
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <array>
#include <cassert>
#include <cstdio>
#include <framework/util/browserrsa.h>

int main()
{
    astra_browser::RsaPublicKey key;
    std::array<unsigned char, 128> block { };
    assert(key.size() == 0);
    assert(!key.encrypt(block.data(), block.size()));
    const char* modulus = "1091201329673994292788609605089955415282375029027981291234687579"
                          "3726629149257644633073969600111060390723088861007265581882535850"
                          "3429057592827629436413108566029093628212635953836686562675849720"
                          "6207862794310902180176810615217550567108238764764442605581471797"
                          "07119674283982419152118103759076030616683978566631413";
    assert(key.set(modulus, "65537"));
    assert(key.size() == 128);
    for (size_t i = 0; i < block.size(); ++i)
        block[i] = static_cast<unsigned char>(i);
    const auto original = block;
    assert(!key.encrypt(block.data(), 127));
    assert(block == original);
    assert(!key.encrypt(nullptr, 128));
    assert(key.encrypt(block.data(), block.size()));
    // Independent Python pow(int.from_bytes(bytes(range(128)), 'big'), 65537, n).
    const char* expected = "6deee571cee50312881746969dfe68d7d9440e6c35307c8f728d8eeaac8e2161"
                           "55c7b3215cefe29024a6cae2d49941d414251120651fb3d0bd9129ad8a2b3007"
                           "274f027a25b81feac2940a34817715b8e1f772b30e5bb83103faeee7eee347c42"
                           "15b5df6c56acb2238954af01011856281b32a777c62b62440ebf7dbf5f7ea2e";
    const char* digits = "0123456789abcdef";
    for (size_t i = 0; i < block.size(); ++i) {
        assert(digits[block[i] >> 4] == expected[i * 2]);
        assert(digits[block[i] & 15] == expected[i * 2 + 1]);
    }
    block.fill(0);
    block.back() = 1;
    const auto leadingZeros = block;
    assert(key.encrypt(block.data(), block.size()));
    assert(block == leadingZeros); // Preserve the full fixed-width block.
    block.fill(0xff);
    const auto outsideModulus = block;
    assert(!key.encrypt(block.data(), block.size()));
    assert(block == outsideModulus);
    assert(!key.set("invalid", "65537"));
    assert(key.size() == 0);
    assert(!key.set(std::string(2468, '9'), "65537"));
    assert(!key.encrypt(block.data(), block.size()));
    assert(!key.set("0", "65537"));
    assert(!key.set(modulus, "-1"));
    assert(!key.set(modulus, "1"));
    assert(!key.set(modulus, "65536"));
    assert(key.set("3233", "17")); // Textbook RSA, key replacement and byte order.
    std::array<unsigned char, 2> small { 0, 65 };
    assert(key.size() == 2);
    assert(key.encrypt(small.data(), small.size()));
    assert(small[0] == 0x0a && small[1] == 0xe6); // 65^17 mod 3233 == 2790.
    std::puts("Browser RSA: known vectors, byte order, padding, key replacement and invalid input PASS");
}
