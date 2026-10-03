#pragma once

#include <boost/multiprecision/cpp_int.hpp>
#include <algorithm>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

namespace astra_browser
{
// Public-key operation only. Tibia's protocol already pads the login block;
// this must match OpenSSL RSA_public_encrypt(..., RSA_NO_PADDING) exactly.
class RsaPublicKey
{
  public:
    bool set(const std::string &modulus, const std::string &exponent)
    {
        m_size = 0; // An invalid replacement must not leave the old key usable.
        Integer n, e;
        if (!decimal(modulus, n) || !decimal(exponent, e) || n <= 1 || e <= 1 || (n & 1) == 0 || (e & 1) == 0 || e >= n)
            return false;
        m_modulus = std::move(n);
        m_exponent = std::move(e);
        m_size = static_cast<int>((boost::multiprecision::msb(m_modulus) + 8) / 8);
        return true;
    }

    int size() const { return m_size; }

    bool encrypt(unsigned char *message, int length) const
    {
        if (!message || !m_size || length != m_size)
            return false;
        Integer value = 0;
        boost::multiprecision::import_bits(value, message, message + length, 8, true);
        if (value >= m_modulus)
            return false;
        const Integer encrypted = boost::multiprecision::powm(value, m_exponent, m_modulus);
        std::vector<unsigned char> bytes;
        boost::multiprecision::export_bits(encrypted, std::back_inserter(bytes), 8, true);
        if (bytes.size() > static_cast<size_t>(length))
            return false;
        std::fill(message, message + length, 0);
        std::copy(bytes.begin(), bytes.end(), message + length - bytes.size());
        return true;
    }

  private:
    using Integer = boost::multiprecision::cpp_int;
    static bool decimal(const std::string &text, Integer &value)
    {
        // Covers keys up to 8192 bits without accepting unbounded input.
        if (text.empty() || text.size() > 2467)
            return false;
        value = 0;
        for (const char digit : text) {
            if (digit < '0' || digit > '9')
                return false;
            value *= 10;
            value += digit - '0';
        }
        return true;
    }

    Integer m_modulus;
    Integer m_exponent;
    int m_size = 0;
};
} // namespace astra_browser
