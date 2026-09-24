#pragma once

#ifndef __EMSCRIPTEN__

#include <boost/asio/ssl/context.hpp>
#include <boost/asio/ssl/host_name_verification.hpp>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/pem.h>

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

inline bool configureContext(boost::asio::ssl::context& context)
{
    boost::system::error_code ec;
    context.set_default_verify_paths(ec);

    context.set_options(
        boost::asio::ssl::context::default_workarounds |
        boost::asio::ssl::context::no_sslv2 |
        boost::asio::ssl::context::no_sslv3 |
        boost::asio::ssl::context::no_tlsv1 |
        boost::asio::ssl::context::no_tlsv1_1,
        ec);

    if (SSL_CTX_set_min_proto_version(context.native_handle(), TLS1_2_VERSION) != 1) {
        return false;
    }

#ifdef WIN32
    HCERTSTORE hStore = CertOpenSystemStoreW(0, L"ROOT");
    if (hStore) {
        X509_STORE* store = SSL_CTX_get_cert_store(context.native_handle());
        if (store) {
            PCCERT_CONTEXT pContext = nullptr;
            while ((pContext = CertEnumCertificatesInStore(hStore, pContext)) != nullptr) {
                const unsigned char* pb = pContext->pbCertEncoded;
                X509* x509 = d2i_X509(nullptr, &pb, static_cast<long>(pContext->cbCertEncoded));
                if (x509) {
                    if (X509_STORE_add_cert(store, x509) != 1) {
                        ERR_clear_error();
                    }
                    X509_free(x509);
                }
            }
        }
        CertCloseStore(hStore, 0);
    }
#endif

#ifdef ANDROID
    static const char* const androidCertDirs[] = {
        "/apex/com.android.conscrypt/cacerts",
        "/system/etc/security/cacerts"
    };

    X509_STORE* store = SSL_CTX_get_cert_store(context.native_handle());
    for (const char* dirPath : androidCertDirs) {
        boost::system::error_code ecDir;
        context.add_verify_path(dirPath, ecDir);

        if (store) {
            DIR* dir = opendir(dirPath);
            if (dir) {
                struct dirent* entry;
                while ((entry = readdir(dir)) != nullptr) {
                    if (entry->d_name[0] == '.')
                        continue;
                    std::string fullPath = std::string(dirPath) + "/" + entry->d_name;
                    FILE* fp = fopen(fullPath.c_str(), "r");
                    if (fp) {
                        X509* cert = PEM_read_X509(fp, nullptr, nullptr, nullptr);
                        if (cert) {
                            if (X509_STORE_add_cert(store, cert) != 1) {
                                ERR_clear_error();
                            }
                            X509_free(cert);
                        }
                        fclose(fp);
                    }
                }
                closedir(dir);
            }
        }
    }
#endif

    return true;
}

}

#endif
