#pragma once

#ifndef __EMSCRIPTEN__

#include <boost/asio/ssl/context.hpp>
#include <boost/asio/ssl/verify_context.hpp>
#include <boost/version.hpp>
#if BOOST_VERSION >= 107300
#include <boost/asio/ssl/host_name_verification.hpp>
#else
#include <boost/asio/ssl/rfc2818_verification.hpp>
#endif
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

inline std::string importWindowsRootCertificates(boost::asio::ssl::context& context)
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

    X509_STORE* store = SSL_CTX_get_cert_store(context.native_handle());
    if (!store) {
        CertCloseStore(disallowedStore, 0);
        CertCloseStore(rootStore, 0);
        return "Failed to access the OpenSSL certificate store";
    }

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
            return closeStoresAfterError(openSslError("Failed to decode a Windows root certificate"));
        }

        const std::string error = addCertificate(store, certificate);
        X509_free(certificate);
        if (!error.empty())
            return closeStoresAfterError(error);
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

#if BOOST_VERSION >= 107300
inline boost::asio::ssl::host_name_verification hostNameVerifier(const std::string& hostName)
{
    return boost::asio::ssl::host_name_verification(hostName);
}
#else
inline boost::asio::ssl::rfc2818_verification hostNameVerifier(const std::string& hostName)
{
    return boost::asio::ssl::rfc2818_verification(hostName);
}
#endif

inline auto certificateVerifier(const std::string& hostName)
{
    auto verifier = hostNameVerifier(hostName);
    return [verifier](bool preverified, boost::asio::ssl::verify_context& verifyContext) mutable {
        if (!preverified)
            return false;

#ifdef WIN32
        if (!isAllowedByWindowsDisallowedStore(verifyContext.native_handle()))
            return false;
#endif

        return verifier(preverified, verifyContext);
    };
}

inline std::string configureContext(boost::asio::ssl::context& context)
{
    boost::system::error_code ec;

    context.set_options(
        boost::asio::ssl::context::default_workarounds |
        boost::asio::ssl::context::no_sslv2 |
        boost::asio::ssl::context::no_sslv3 |
        boost::asio::ssl::context::no_tlsv1 |
        boost::asio::ssl::context::no_tlsv1_1,
        ec);
    if (ec)
        return "Failed to configure TLS protocol options: " + ec.message();

#if OPENSSL_VERSION_NUMBER >= 0x10100000L && !defined(LIBRESSL_VERSION_NUMBER)
    ERR_clear_error();
    if (SSL_CTX_set_min_proto_version(context.native_handle(), TLS1_2_VERSION) != 1) {
        return openSslError("Failed to require TLS 1.2 or newer");
    }
#endif

#ifdef WIN32
    if (const std::string error = importWindowsRootCertificates(context); !error.empty())
        return error;
#else
    boost::system::error_code defaultTrustStoreError;
    context.set_default_verify_paths(defaultTrustStoreError);
#ifndef ANDROID
    if (defaultTrustStoreError)
        return "Failed to load the default TLS trust store: " + defaultTrustStoreError.message();
#endif
#endif

#ifdef ANDROID
    static const char* const androidCertDirs[] = {
        "/apex/com.android.conscrypt/cacerts",
        "/system/etc/security/cacerts"
    };

    bool trustStoreLoaded = !defaultTrustStoreError;
    std::string trustStoreError;
    X509_STORE* store = SSL_CTX_get_cert_store(context.native_handle());
    if (!store)
        return "Failed to access the OpenSSL certificate store";

    for (const char* dirPath : androidCertDirs) {
        boost::system::error_code ecDir;
        context.add_verify_path(dirPath, ecDir);
        if (!ecDir)
            trustStoreLoaded = true;
        else
            trustStoreError = "Failed to load Android certificates from " + std::string(dirPath) + ": " + ecDir.message();

        DIR* dir = opendir(dirPath);
        if (dir) {
            struct dirent* entry;
            while ((entry = readdir(dir)) != nullptr) {
                if (entry->d_name[0] == '.')
                    continue;
                std::string fullPath = std::string(dirPath) + "/" + entry->d_name;
                FILE* fp = fopen(fullPath.c_str(), "r");
                if (!fp) {
                    closedir(dir);
                    return "Failed to open Android certificate " + fullPath;
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
                    closedir(dir);
                    return openSslError("Failed to decode Android certificate " + fullPath);
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
        return "Failed to load an Android TLS trust store: " + defaultTrustStoreError.message();
    }
#endif

    return {};
}

}

#endif
