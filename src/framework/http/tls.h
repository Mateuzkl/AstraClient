#pragma once

#ifndef __EMSCRIPTEN__

#include <framework/core/logger.h>

#include <curl/curl.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509err.h>
#include <openssl/pem.h>

#include <string>
#include <vector>

#ifdef WIN32
#include <windows.h>
#include <wincrypt.h>
#pragma comment(lib, "crypt32.lib")
#endif

#ifdef ANDROID
#include <dirent.h>
#include <cstdio>
#include <string>
#endif

namespace HttpTls {

inline std::string openSslError(const std::string& operation)
{
    const unsigned long error = ERR_get_error();
    if (error == 0)
        return operation;

    char buffer[256] = {};
    ERR_error_string_n(error, buffer, sizeof(buffer));
    return operation + ": " + buffer;
}

inline std::string addCertificate(X509_STORE* store, X509* certificate)
{
    ERR_clear_error();
    if (X509_STORE_add_cert(store, certificate) == 1)
        return {};

    const unsigned long error = ERR_peek_last_error();
    if (error != 0 && ERR_GET_LIB(error) == ERR_LIB_X509 &&
        ERR_GET_REASON(error) == X509_R_CERT_ALREADY_IN_HASH_TABLE) {
        ERR_clear_error();
        return {};
    }

    return openSslError("Failed to add a certificate to the TLS trust store");
}

#ifdef WIN32
inline std::string windowsError(const std::string& operation, DWORD error)
{
    return operation + " (Windows error " + std::to_string(error) + ")";
}

inline std::string importWindowsRootCertificates(
    SSL_CTX* context,
    bool defaultTrustStoreLoaded)
{
    HCERTSTORE rootStore = CertOpenSystemStoreW(0, L"ROOT");
    if (!rootStore)
        return windowsError("Failed to open the Windows ROOT certificate store", GetLastError());

    HCERTSTORE disallowedStore = CertOpenSystemStoreW(0, L"Disallowed");
    if (!disallowedStore) {
        const DWORD error = GetLastError();
        CertCloseStore(rootStore, 0);
        return windowsError("Failed to open the Windows Disallowed certificate store", error);
    }

    X509_STORE* store = SSL_CTX_get_cert_store(context);
    if (!store) {
        CertCloseStore(disallowedStore, 0);
        CertCloseStore(rootStore, 0);
        return "Failed to access the OpenSSL certificate store";
    }

    size_t importedCertificates = 0;
    size_t certificateIndex = 0;
    std::string lastCertificateError;
    PCCERT_CONTEXT rootCertificate = nullptr;
    const auto closeStoresAfterError = [&](const std::string& error) {
        if (rootCertificate) {
            CertFreeCertificateContext(rootCertificate);
            rootCertificate = nullptr;
        }
        CertCloseStore(disallowedStore, 0);
        CertCloseStore(rootStore, 0);
        return error;
    };

    while ((rootCertificate = CertEnumCertificatesInStore(rootStore, rootCertificate)) != nullptr) {
        ++certificateIndex;
        DWORD hashSize = 0;
        if (!CertGetCertificateContextProperty(rootCertificate, CERT_SHA1_HASH_PROP_ID, nullptr, &hashSize)) {
            return closeStoresAfterError(windowsError(
                "Failed to read a Windows root certificate hash", GetLastError()));
        }

        std::vector<BYTE> hash(hashSize);
        if (!CertGetCertificateContextProperty(rootCertificate, CERT_SHA1_HASH_PROP_ID, hash.data(), &hashSize)) {
            return closeStoresAfterError(windowsError(
                "Failed to read a Windows root certificate hash", GetLastError()));
        }

        CRYPT_HASH_BLOB hashBlob = { hashSize, hash.data() };
        PCCERT_CONTEXT disallowedCertificate = CertFindCertificateInStore(
            disallowedStore,
            X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
            0,
            CERT_FIND_SHA1_HASH,
            &hashBlob,
            nullptr);

        if (disallowedCertificate) {
            CertFreeCertificateContext(disallowedCertificate);
            continue;
        }

        const DWORD findError = GetLastError();
        if (findError != CRYPT_E_NOT_FOUND) {
            return closeStoresAfterError(windowsError(
                "Failed to query the Windows Disallowed certificate store", findError));
        }

        const unsigned char* encodedCertificate = rootCertificate->pbCertEncoded;
        ERR_clear_error();
        X509* certificate = d2i_X509(
            nullptr,
            &encodedCertificate,
            static_cast<long>(rootCertificate->cbCertEncoded));
        if (!certificate) {
            lastCertificateError = openSslError("Failed to decode a Windows root certificate");
            g_logger.warning(
                "Skipping Windows ROOT certificate " + std::to_string(certificateIndex) +
                ": " + lastCertificateError);
            continue;
        }

        const std::string error = addCertificate(store, certificate);
        X509_free(certificate);
        if (!error.empty()) {
            lastCertificateError = error;
            g_logger.warning(
                "Skipping Windows ROOT certificate " + std::to_string(certificateIndex) +
                ": " + lastCertificateError);
            continue;
        }

        ++importedCertificates;
    }

    const DWORD enumerationError = GetLastError();
    if (enumerationError != CRYPT_E_NOT_FOUND && enumerationError != ERROR_SUCCESS) {
        CertCloseStore(disallowedStore, 0);
        CertCloseStore(rootStore, 0);
        return windowsError("Failed to enumerate the Windows ROOT certificate store", enumerationError);
    }

    if (!CertCloseStore(disallowedStore, 0)) {
        const DWORD error = GetLastError();
        CertCloseStore(rootStore, 0);
        return windowsError("Failed to close the Windows Disallowed certificate store", error);
    }

    if (!CertCloseStore(rootStore, 0))
        return windowsError("Failed to close the Windows ROOT certificate store", GetLastError());

    if (importedCertificates == 0 && !defaultTrustStoreLoaded) {
        if (!lastCertificateError.empty())
            return lastCertificateError;
        return "No trusted Windows root certificates could be loaded";
    }

    return {};
}

inline bool isAllowedByWindowsDisallowedStore(X509_STORE_CTX* verifyContext)
{
    X509* certificate = X509_STORE_CTX_get_current_cert(verifyContext);
    if (!certificate)
        return false;

    const int encodedSize = i2d_X509(certificate, nullptr);
    if (encodedSize <= 0)
        return false;

    std::vector<BYTE> encodedCertificate(static_cast<size_t>(encodedSize));
    unsigned char* encodedCertificatePointer = encodedCertificate.data();
    if (i2d_X509(certificate, &encodedCertificatePointer) != encodedSize)
        return false;

    PCCERT_CONTEXT certificateContext = CertCreateCertificateContext(
        X509_ASN_ENCODING,
        encodedCertificate.data(),
        static_cast<DWORD>(encodedCertificate.size()));
    if (!certificateContext)
        return false;

    HCERTSTORE disallowedStore = CertOpenSystemStoreW(0, L"Disallowed");
    if (!disallowedStore) {
        CertFreeCertificateContext(certificateContext);
        return false;
    }

    PCCERT_CONTEXT disallowedCertificate = CertFindCertificateInStore(
        disallowedStore,
        X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
        0,
        CERT_FIND_EXISTING,
        certificateContext,
        nullptr);

    if (disallowedCertificate) {
        CertFreeCertificateContext(disallowedCertificate);
        CertCloseStore(disallowedStore, 0);
        CertFreeCertificateContext(certificateContext);
        return false;
    }

    const DWORD findError = GetLastError();
    const bool storeClosed = CertCloseStore(disallowedStore, 0) != FALSE;
    CertFreeCertificateContext(certificateContext);
    return findError == CRYPT_E_NOT_FOUND && storeClosed;
}
#endif

inline int certificateVerifier(int preverified, X509_STORE_CTX* context)
{
    if (!preverified) return 0;
#ifdef WIN32
    try {
        if (!isAllowedByWindowsDisallowedStore(context)) {
            X509_STORE_CTX_set_error(context, X509_V_ERR_CERT_REJECTED);
            return 0;
        }
    } catch (...) { return 0; } // Never unwind a C++ exception through OpenSSL.
#endif
    return 1; // Hostname/SAN verification is performed by libcurl independently.
}

inline std::string configureContext(SSL_CTX* context)
{
    SSL_CTX_set_options(context, SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3 | SSL_OP_NO_TLSv1 | SSL_OP_NO_TLSv1_1);
    SSL_CTX_set_verify(context, SSL_VERIFY_PEER, &certificateVerifier);
#if OPENSSL_VERSION_NUMBER >= 0x10100000L && !defined(LIBRESSL_VERSION_NUMBER)
    ERR_clear_error();
    if (SSL_CTX_set_min_proto_version(context, TLS1_2_VERSION) != 1) {
        return openSslError("Failed to require TLS 1.2 or newer");
    }
#endif

    const bool defaultTrustStoreLoaded = SSL_CTX_set_default_verify_paths(context) == 1;

#ifdef WIN32
    if (const std::string error = importWindowsRootCertificates(context, defaultTrustStoreLoaded); !error.empty())
        return error;
#else
#ifndef ANDROID
    if (!defaultTrustStoreLoaded)
        return "Failed to load the default TLS trust store: " + openSslError("Default trust store unavailable");
#endif
#endif

#ifdef ANDROID
    static const char* const androidCertDirs[] = {
        "/apex/com.android.conscrypt/cacerts",
        "/system/etc/security/cacerts"
    };

    bool trustStoreLoaded = defaultTrustStoreLoaded;
    std::string trustStoreError;
    X509_STORE* store = SSL_CTX_get_cert_store(context);
    if (!store)
        return "Failed to access the OpenSSL certificate store";

    for (const char* dirPath : androidCertDirs) {
        if (X509_STORE_load_locations(store, nullptr, dirPath) == 1)
            trustStoreLoaded = true;
        else
            trustStoreError = "Failed to load Android certificates from " + std::string(dirPath) + ": " + openSslError("Certificate directory unavailable");

        DIR* dir = opendir(dirPath);
        if (dir) {
            struct dirent* entry;
            while ((entry = readdir(dir)) != nullptr) {
                if (entry->d_name[0] == '.')
                    continue;
                std::string fullPath = std::string(dirPath) + "/" + entry->d_name;
                FILE* fp = fopen(fullPath.c_str(), "r");
                if (!fp) {
                    trustStoreError = "Failed to open Android certificate " + fullPath;
                    continue;
                }

                ERR_clear_error();
                X509* cert = PEM_read_X509(fp, nullptr, nullptr, nullptr);
                if (!cert) {
                    ERR_clear_error();
                    rewind(fp);
                    cert = d2i_X509_fp(fp, nullptr);
                }
                fclose(fp);
                if (!cert) {
                    trustStoreError = openSslError("Failed to decode Android certificate " + fullPath);
                    continue;
                }

                const std::string error = addCertificate(store, cert);
                X509_free(cert);
                if (!error.empty()) {
                    closedir(dir);
                    return error;
                }

                trustStoreLoaded = true;
            }
            closedir(dir);
        }
    }

    if (!trustStoreLoaded) {
        if (!trustStoreError.empty())
            return trustStoreError;
        return "Failed to load an Android TLS trust store: " + openSslError("Default trust store unavailable");
    }
#endif

    return {};
}

inline CURLcode configureOpenSsl(CURL*, void* nativeContext, void*)
{
    try {
        return configureContext(static_cast<SSL_CTX*>(nativeContext)).empty() ? CURLE_OK : CURLE_SSL_CACERT_BADFILE;
    } catch (...) { return CURLE_SSL_CACERT_BADFILE; }
}

inline CURLcode configure(CURL* handle)
{
    CURLcode code = curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 1L);
    if (code != CURLE_OK) return code;
    code = curl_easy_setopt(handle, CURLOPT_SSL_VERIFYHOST, 2L);
    if (code != CURLE_OK) return code;
    code = curl_easy_setopt(handle, CURLOPT_SSLVERSION, static_cast<long>(CURL_SSLVERSION_TLSv1_2));
    if (code != CURLE_OK) return code;
    // Schannel uses Windows trust/revocation policy natively. OpenSSL retains
    // Astra's root import + Disallowed checks, including Android certificate paths.
    const auto* version = curl_version_info(CURLVERSION_NOW);
    if (version && version->ssl_version && std::string(version->ssl_version).find("OpenSSL") == 0)
        return curl_easy_setopt(handle, CURLOPT_SSL_CTX_FUNCTION, &configureOpenSsl);
    return CURLE_OK;
}
}
#endif
