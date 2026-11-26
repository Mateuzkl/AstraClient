/* Multi-signal platform detection, profile selection and mobile landscape/fullscreen controller. */
(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.AstraPlatform = api;
})(globalThis, () => {
  'use strict';

  const PROFILE_KEY_PREFIX = 'astra-web-profile:';
  const VALID_PROFILES = new Set(['desktop', 'mobile']);
  const VALID_PREFERENCES = new Set(['auto', 'desktop', 'mobile']);

  function safeMatchMedia(win, query) {
    try {
      return !!(win && typeof win.matchMedia === 'function' && win.matchMedia(query).matches);
    } catch (_) {
      return false;
    }
  }

  function profileStorageKey(pathname) {
    return `${PROFILE_KEY_PREFIX}${pathname || '/'}`;
  }

  function readSavedPreference(storage, pathname) {
    if (!storage) return 'auto';
    try {
      const value = storage.getItem(profileStorageKey(pathname));
      return VALID_PREFERENCES.has(value) ? value : 'auto';
    } catch (_) {
      return 'auto';
    }
  }

  function writeSavedPreference(storage, pathname, value) {
    if (!storage || !VALID_PREFERENCES.has(value)) return false;
    try {
      if (value === 'auto') storage.removeItem(profileStorageKey(pathname));
      else storage.setItem(profileStorageKey(pathname), value);
      return true;
    } catch (_) {
      return false;
    }
  }

  function collectSignals(env = {}) {
    const win = env.window || (typeof window !== 'undefined' ? window : {});
    const nav = env.navigator || win.navigator || {};
    const scr = env.screen || win.screen || {};
    const uaData = nav.userAgentData || null;
    const ua = String(nav.userAgent || '');
    const platform = String(nav.platform || '');
    const hintPlatform = uaData && typeof uaData.platform === 'string' ? uaData.platform : '';
    const hintMobile = uaData && typeof uaData.mobile === 'boolean' ? uaData.mobile : null;
    const maxTouchPoints = Number(nav.maxTouchPoints || 0);
    const hasTouchStart = 'ontouchstart' in win;
    const hasTouch = maxTouchPoints > 0 || hasTouchStart;

    const coarsePointer = safeMatchMedia(win, '(pointer: coarse)');
    const finePointer = safeMatchMedia(win, '(pointer: fine)');
    const anyCoarsePointer = safeMatchMedia(win, '(any-pointer: coarse)');
    const anyFinePointer = safeMatchMedia(win, '(any-pointer: fine)');
    const canHover = safeMatchMedia(win, '(hover: hover)');
    const noHover = safeMatchMedia(win, '(hover: none)');

    const width = Number(win.innerWidth || scr.width || 0);
    const height = Number(win.innerHeight || scr.height || 0);
    const screenShort = Math.min(Number(scr.width || width || 0), Number(scr.height || height || 0));
    const screenLong = Math.max(Number(scr.width || width || 0), Number(scr.height || height || 0));

    return {
      ua, platform, hintPlatform, hintMobile,
      maxTouchPoints, hasTouch,
      coarsePointer, finePointer, anyCoarsePointer, anyFinePointer,
      canHover, noHover,
      width, height, screenShort, screenLong
    };
  }

  function detectPlatform(env = {}) {
    const s = collectSignals(env);
    const ua = s.ua;
    const hintPlat = s.hintPlatform.toLowerCase();
    const plat = s.platform.toLowerCase();

    // 1. OS & form-factor classification using UA Client Hints, iPadOS heuristics, pointer/hover & UA.
    const isIPadOSDesktopUA =
      (plat === 'macintel' || /Macintosh/i.test(ua)) &&
      s.maxTouchPoints > 1 &&
      !(/Windows|Android|CrOS/i.test(ua));
    const isIPadUA = /\biPad\b/i.test(ua) || isIPadOSDesktopUA;
    const isIPhoneUA = /\b(?:iPhone|iPod)\b/i.test(ua);
    const isAndroid = hintPlat === 'android' || /\bAndroid\b/i.test(ua);
    const isWindows = hintPlat === 'windows' || /\bWindows\b/i.test(ua) || /^win/i.test(plat);
    const isMacOS = !isIPadOSDesktopUA && (hintPlat === 'macos' || /\bMacintosh\b|\bMac OS X\b/i.test(ua));
    const isChromeOS = hintPlat === 'chrome os' || /\bCrOS\b/i.test(ua);
    const isLinuxDesktop = !isAndroid && !isChromeOS && (hintPlat === 'linux' || /\bLinux\b|\bX11\b/i.test(ua) || /^linux/i.test(plat));
    const isSamsungBrowser = /\bSamsungBrowser\b/i.test(ua);
    const isIOS = isIPhoneUA || isIPadUA || hintPlat === 'ios';

    let os = 'unknown';
    if (isIOS) os = isIPadUA ? 'ipados' : 'ios';
    else if (isAndroid) os = 'android';
    else if (isWindows) os = 'windows';
    else if (isMacOS) os = 'macos';
    else if (isChromeOS) os = 'chromeos';
    else if (isLinuxDesktop) os = 'linux';

    const desktopOS = os === 'windows' || os === 'macos' || os === 'linux' || os === 'chromeos';
    const isHybridTouchDesktop = desktopOS && s.hasTouch && (s.finePointer || s.anyFinePointer || s.canHover);
    const isPhone = isIPhoneUA || (isAndroid && (s.hintMobile === true || /\bMobile\b/i.test(ua)));
    const isTablet = isIPadUA || (isAndroid && !isPhone) || (/\bTablet\b|\bPlayBook\b|\bSilk\b/i.test(ua));

    // 2. Determine recommended profile before downloading WASM/assets.
    let profile = 'desktop';
    let formFactor = 'desktop';
    let reason = 'desktop-os';

    if (isPhone) {
      profile = 'mobile';
      formFactor = 'phone';
      reason = isIOS ? 'ios-phone' : 'android-phone';
    } else if (isTablet) {
      profile = 'mobile';
      formFactor = 'tablet';
      reason = isIPadOSDesktopUA ? 'ipados-touch-macintel' : (isIPadUA ? 'ipad' : 'android-tablet');
    } else if (s.hintMobile === true && !isHybridTouchDesktop) {
      profile = 'mobile';
      formFactor = 'phone';
      reason = 'ua-ch-mobile';
    } else if (isHybridTouchDesktop) {
      profile = 'desktop';
      formFactor = 'hybrid';
      reason = 'desktop-touch-hybrid';
    } else if (!desktopOS && s.hasTouch && s.coarsePointer && !s.finePointer && s.noHover) {
      profile = 'mobile';
      formFactor = (s.screenShort > 0 && s.screenShort >= 600) ? 'tablet' : 'phone';
      reason = 'coarse-touch-no-hover';
    } else if (desktopOS && s.hasTouch && s.coarsePointer && !s.anyFinePointer && s.noHover) {
      // Pure tablet running desktop-class OS without attached mouse/trackpad.
      profile = 'mobile';
      formFactor = 'tablet';
      reason = 'touch-only-tablet';
    }

    return {
      profile,
      os,
      formFactor,
      reason,
      isTouch: s.hasTouch,
      isHybrid: isHybridTouchDesktop,
      isIOS,
      isAndroid,
      isSamsungBrowser,
      coarsePointer: s.coarsePointer,
      finePointer: s.finePointer,
      canHover: s.canHover,
      maxTouchPoints: s.maxTouchPoints
    };
  }

  function resolveProfile(env = {}, availableProfiles = ['desktop', 'mobile']) {
    const detected = detectPlatform(env);
    const win = env.window || (typeof window !== 'undefined' ? window : {});
    const pathname = env.pathname || (win.location && win.location.pathname) || '/';
    const storage = env.storage !== undefined ? env.storage : win.localStorage;
    const configDefault = env.configProfile || (win.ASTRA_CONFIG && win.ASTRA_CONFIG.profile) || 'auto';
    const saved = readSavedPreference(storage, pathname);

    let preference = saved;
    let source = 'detected';
    if (saved !== 'auto') {
      source = 'manual';
    } else if (VALID_PROFILES.has(configDefault)) {
      preference = configDefault;
      source = 'config';
    }

    let selected = VALID_PROFILES.has(preference) ? preference : detected.profile;
    const available = Array.isArray(availableProfiles) && availableProfiles.length
      ? availableProfiles.filter(p => VALID_PROFILES.has(p))
      : ['desktop'];
    let fallback = false;
    if (!available.includes(selected)) {
      selected = available[0] || 'desktop';
      fallback = true;
    }

    return {
      selected,
      detected: detected.profile,
      preference: saved,
      source,
      fallback,
      available,
      info: detected
    };
  }

  function isKeyboardShrunkLandscape(win) {
    try {
      const vv = win.visualViewport;
      const scr = win.screen;
      if (!vv) return false;
      const active = win.document && win.document.activeElement;
      const editor = win.document && win.document.getElementById && win.document.getElementById('astra-virtual-keyboard');
      const keyboardFocused = !!active && (active === editor || active.tagName === 'INPUT' || active.tagName === 'TEXTAREA');
      if (!keyboardFocused) return false;
      if (scr && scr.orientation && typeof scr.orientation.type === 'string') {
        return scr.orientation.type.startsWith('landscape');
      }
      return (win.innerWidth || 0) >= (win.innerHeight || 0) || vv.height < (win.innerHeight || vv.height) * 0.78;
    } catch (_) {
      return false;
    }
  }

  function isPortrait(win) {
    if (!win) return false;
    if (isKeyboardShrunkLandscape(win)) return false;
    try {
      const type = win.screen && win.screen.orientation && win.screen.orientation.type;
      if (typeof type === 'string') {
        if (type.startsWith('portrait')) return true;
        if (type.startsWith('landscape')) return false;
      }
    } catch (_) {}
    if (safeMatchMedia(win, '(orientation: portrait)')) return true;
    if (safeMatchMedia(win, '(orientation: landscape)')) return false;
    return Number(win.innerHeight || 0) > Number(win.innerWidth || 0);
  }

  function readSafeAreaInsets(win) {
    try {
      const doc = win && win.document;
      if (!doc || !doc.documentElement || typeof win.getComputedStyle !== 'function') {
        return { top: 0, right: 0, bottom: 0, left: 0 };
      }
      const style = win.getComputedStyle(doc.documentElement);
      const px = prop => Math.max(0, Math.round(parseFloat(style.getPropertyValue(prop)) || 0));
      return {
        top: px('--astra-safe-top'),
        right: px('--astra-safe-right'),
        bottom: px('--astra-safe-bottom'),
        left: px('--astra-safe-left')
      };
    } catch (_) {
      return { top: 0, right: 0, bottom: 0, left: 0 };
    }
  }

  function createMobileViewportController(env = {}) {
    const win = env.window || (typeof window !== 'undefined' ? window : {});
    const doc = env.document || win.document;
    const onViewportChange = typeof env.onViewportChange === 'function' ? env.onViewportChange : () => {};
    const onOrientationState = typeof env.onOrientationState === 'function' ? env.onOrientationState : () => {};
    let active = false;
    let dismissedPortraitPrompt = false;
    const listeners = [];

    const listen = (target, type, fn, options) => {
      if (!target || typeof target.addEventListener !== 'function') return;
      target.addEventListener(type, fn, options);
      listeners.push([target, type, fn, options]);
    };

    const syncState = () => {
      const portrait = isPortrait(win);
      if (!portrait) dismissedPortraitPrompt = false;
      const insets = readSafeAreaInsets(win);
      const vv = win.visualViewport;
      const keyboardHeight = vv && win.innerHeight ? Math.max(0, Math.round(win.innerHeight - vv.height)) : 0;
      const orientationType = (win.screen && win.screen.orientation && win.screen.orientation.type) ||
        (portrait ? 'portrait-primary' : 'landscape-primary');
      onOrientationState({
        active,
        portrait,
        showRotateOverlay: active && portrait && !dismissedPortraitPrompt,
        orientationType,
        insets,
        keyboardHeight
      });
      onViewportChange({ portrait, orientationType, insets, keyboardHeight });
    };

    const requestFullscreenAndLandscape = async () => {
      const result = { fullscreen: false, orientationLocked: false };
      try {
        const rootEl = doc && doc.documentElement;
        if (rootEl && !doc.fullscreenElement && !doc.webkitFullscreenElement) {
          const req = rootEl.requestFullscreen || rootEl.webkitRequestFullscreen;
          if (typeof req === 'function') {
            await Promise.resolve(req.call(rootEl, { navigationUI: 'hide' })).catch(() => Promise.resolve(req.call(rootEl)));
            result.fullscreen = true;
          }
        } else if (doc && (doc.fullscreenElement || doc.webkitFullscreenElement)) {
          result.fullscreen = true;
        }
      } catch (_) {
        result.fullscreen = false;
      }

      try {
        const orientation = win.screen && win.screen.orientation;
        if (orientation && typeof orientation.lock === 'function') {
          await orientation.lock('landscape');
          result.orientationLocked = true;
        }
      } catch (_) {
        // Safari iOS and some desktop/tablet browsers reject orientation.lock();
        // fall back cleanly to the non-blocking rotate-device prompt.
        result.orientationLocked = false;
      }

      syncState();
      return result;
    };

    const install = (canvasElement) => {
      if (listeners.length) return;
      listen(win, 'resize', syncState);
      listen(win, 'orientationchange', syncState);
      if (win.screen && win.screen.orientation) listen(win.screen.orientation, 'change', syncState);
      if (win.visualViewport) {
        listen(win.visualViewport, 'resize', syncState);
        listen(win.visualViewport, 'scroll', syncState);
      }
      if (doc) listen(doc, 'fullscreenchange', syncState);
      // Prevent iOS Safari pinch/gesture zoom & accidental double-tap zoom over the game canvas.
      if (canvasElement) {
        const block = event => { if (event && typeof event.preventDefault === 'function') event.preventDefault(); };
        listen(canvasElement, 'gesturestart', block, { passive: false });
        listen(canvasElement, 'gesturechange', block, { passive: false });
        listen(canvasElement, 'gestureend', block, { passive: false });
      }
      syncState();
    };

    return {
      install,
      activate() { active = true; syncState(); },
      deactivate() { active = false; dismissedPortraitPrompt = false; syncState(); },
      dismissRotatePrompt() { dismissedPortraitPrompt = true; syncState(); },
      requestFullscreenAndLandscape,
      syncState,
      readSafeAreaInsets: () => readSafeAreaInsets(win),
      dispose() {
        active = false;
        for (const [target, type, fn, options] of listeners) {
          if (typeof target.removeEventListener === 'function') target.removeEventListener(type, fn, options);
        }
        listeners.length = 0;
      }
    };
  }

  return {
    detectPlatform,
    resolveProfile,
    readSavedPreference,
    writeSavedPreference,
    profileStorageKey,
    isPortrait,
    readSafeAreaInsets,
    createMobileViewportController
  };
});
