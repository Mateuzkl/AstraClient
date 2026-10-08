#pragma once
#include <emscripten/emscripten.h>
#include <string>

// Public-key encryption only; padding is already present in Tibia's packet.
// BigInt operates locally on the application pthread, never on the UI thread.
// clang-format off
EM_JS(int, astraRsaSize, (const char* modulus, const char* exponent), {
    try {
        const n = BigInt(UTF8ToString(modulus)), e = BigInt(UTF8ToString(exponent));
        if (n <= 1n || e <= 1n || !(n & 1n) || !(e & 1n) || e >= n) return 0;
        return Math.ceil(n.toString(2).length / 8);
    } catch (_) { return 0; }
});
EM_JS(int, astraRsaEncrypt, (const char* modulus, const char* exponent, unsigned char* message, int length), {
    try {
        const n = BigInt(UTF8ToString(modulus));
        let e = BigInt(UTF8ToString(exponent)), value = 0n, result = 1n;
        for (let i = 0; i < length; ++i) value = (value << 8n) | BigInt(HEAPU8[message + i]);
        if (value >= n) return 0;
        while (e > 0n) {
            if (e & 1n) result = (result * value) % n;
            e >>= 1n;
            if (e) value = (value * value) % n;
        }
        // No writes until all validation/arithmetic succeeds.
        const output = new Uint8Array(length);
        for (let i = length - 1; i >= 0; --i) { output[i] = Number(result & 255n); result >>= 8n; }
        if (result) return 0;
        HEAPU8.set(output, message);
        return 1;
    } catch (_) { return 0; }
});
// clang-format on
namespace astra_browser
{
class RsaPublicKey
{
  public:
    bool set(const std::string& modulus, const std::string& exponent)
    {
        m_size = 0; // Invalid replacements never leave the previous key usable.
        if (!decimal(modulus) || !decimal(exponent))
            return false;
        m_size = astraRsaSize(modulus.c_str(), exponent.c_str());
        if (!m_size)
            return false;
        m_modulus = modulus;
        m_exponent = exponent;
        return true;
    }
    int size() const { return m_size; }
    bool encrypt(unsigned char* message, int length) const
    {
        return message && m_size && length == m_size &&
               astraRsaEncrypt(m_modulus.c_str(), m_exponent.c_str(), message, length) != 0;
    }

  private:
    static bool decimal(const std::string& text)
    {
        if (text.empty() || text.size() > 2467)
            return false;
        for (const char digit : text)
            if (digit < '0' || digit > '9')
                return false;
        return true;
    }
    std::string m_modulus, m_exponent;
    int m_size = 0;
};
} // namespace astra_browser
