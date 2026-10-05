#pragma once

#if defined(WIN32) && !defined(__EMSCRIPTEN__)
// Optional data/images/splash.png beside the executable, independent of the renderer.
void showNativeSplash();
void setNativeSplashProgress(int percent, const char* stage);
void finishNativeSplash();
void hideNativeSplash();
#endif
