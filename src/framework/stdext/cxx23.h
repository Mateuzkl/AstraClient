#ifndef ASTRA_CXX23_H
#define ASTRA_CXX23_H

// Earlier MSVC preview modes report 202004; newer ones report 202302.
// GCC 13 reports 202100; require the compiler's real post-C++20 mode rather
// than pretending every C++23 library facility is fully implemented.
#if defined(_MSVC_LANG)
#if _MSVC_LANG <= 202002L
#error "AstraClient requires C++23 mode (/std:c++23preview), not C++20 or older."
#endif
#elif !defined(__cplusplus) || __cplusplus < 202100L
#error "AstraClient requires C++23 mode (-std=c++23), not C++20 or older."
#endif

#endif
