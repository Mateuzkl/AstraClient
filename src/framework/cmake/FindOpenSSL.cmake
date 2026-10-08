# Keep legacy path variables while exposing OpenSSL::SSL/OpenSSL::Crypto for
# libcurl builds using OpenSSL. Schannel builds still use OpenSSL for native RSA.
set(OPENSSL_USE_STATIC_LIBS ${USE_STATIC_LIBS})
if(MSVC AND USE_STATIC_LIBS)
    set(OPENSSL_MSVC_STATIC_RT TRUE)
endif()
include("${CMAKE_ROOT}/Modules/FindOpenSSL.cmake")
