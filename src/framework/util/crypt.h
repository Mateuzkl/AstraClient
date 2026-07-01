/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#ifndef CRYPT_H
#define CRYPT_H

#include "../stdext/types.h"
#include <string>

#include <boost/uuid/uuid.hpp>

#ifndef __EMSCRIPTEN__
typedef struct rsa_st RSA;
#endif

class Crypt
{
public:
    Crypt();
    ~Crypt();

    std::string base64Encode(const std::string& decoded_string);
    std::string base64Decode(const std::string& encoded_string);
    std::string xorCrypt(const std::string& buffer, const std::string& key);
    std::string encrypt(const std::string& decrypted_string) { return _encrypt(decrypted_string, true); }
    std::string decrypt(const std::string& encrypted_string) { return _decrypt(encrypted_string, true); }
    std::string genUUID();
    bool setMachineUUID(std::string uuidstr);
    std::string getMachineUUID();
    std::string md5Encode(const std::string& decoded_string, bool upperCase);
    std::string sha1Encode(const std::string& decoded_string, bool upperCase);
    std::string sha256Encode(const std::string& decoded_string, bool upperCase);
    std::string sha512Encode(const std::string& decoded_string, bool upperCase);
    std::string crc32(const std::string& decoded_string, bool upperCase);
    // Raw DEFLATE inflate (zlib windowBits -15, no zlib/gzip header). Returns the
    // decompressed bytes, or an empty string on failure. Used to decode CIP Wheel
    // of Destiny planner preset codes (same raw stream as the game protocol).
    std::string inflateData(const std::string& compressed);

    void rsaGenerateKey(int bits, int e);
    void rsaSetPublicKey(const std::string& n, const std::string& e);
    void rsaSetPrivateKey(const std::string &p, const std::string &q, const std::string &d);
    bool rsaCheckKey();
    bool rsaEncrypt(unsigned char *msg, int size);
    bool rsaDecrypt(unsigned char *msg, int size);
    int rsaGetSize();
#ifdef WITH_ENCRYPTION
    void bencrypt(uint8_t * buffer, int len, uint64_t k);
#endif
    void bdecrypt(uint8_t * buffer, int len, uint64_t k);

    // --- Asset protection (Fase 1): authenticated encryption + KDF ---------
    // AES-256-GCM. key = 32 bytes, nonce = 12 bytes, tag = 16 bytes.
    // The key is NEVER stored alongside the ciphertext (unlike the old ENC3).
    // Returns false on any OpenSSL failure; decrypt also returns false when the
    // authentication tag does not verify (tamper / wrong key).
    bool aesGcmEncrypt(const uint8_t* plain, size_t plainLen,
                       const uint8_t key[32], const uint8_t nonce[12],
                       const uint8_t* aad, size_t aadLen,
                       std::string& outCipher, uint8_t outTag[16]);
    bool aesGcmDecrypt(const uint8_t* cipher, size_t cipherLen,
                       const uint8_t key[32], const uint8_t nonce[12],
                       const uint8_t* aad, size_t aadLen,
                       const uint8_t tag[16], std::string& outPlain);
    // HKDF-SHA256 (RFC 5869). Derives outLen bytes from input keying material.
    void hkdfSha256(const uint8_t* ikm, size_t ikmLen,
                    const uint8_t* salt, size_t saltLen,
                    const uint8_t* info, size_t infoLen,
                    uint8_t* out, size_t outLen);
    // Cryptographically secure random bytes (CSPRNG).
    bool randomBytes(uint8_t* out, size_t len);

private:
    std::string _encrypt(const std::string& decrypted_string, bool useMachineUUID);
    std::string _decrypt(const std::string& encrypted_string, bool useMachineUUID);
    std::string getCryptKey(bool useMachineUUID);
    boost::uuids::uuid m_machineUUID;
#ifndef __EMSCRIPTEN__
    RSA *m_rsa;
#endif
};

extern Crypt g_crypt;

#endif
