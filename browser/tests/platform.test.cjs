'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const api = require('../platform.js');

function mockEnv({
  ua = '',
  platform = '',
  userAgentData = null,
  maxTouchPoints = 0,
  ontouchstart = false,
  media = {},
  innerWidth = 1920,
  innerHeight = 1080,
  screenWidth = innerWidth,
  screenHeight = innerHeight,
  orientationType = null,
  saved = null,
  pathname = '/astraclient.html'
} = {}) {
  const storageMap = new Map();
  if (saved !== null) storageMap.set(api.profileStorageKey(pathname), saved);
  const storage = {
    getItem: k => storageMap.has(k) ? storageMap.get(k) : null,
    setItem: (k, v) => storageMap.set(k, String(v)),
    removeItem: k => storageMap.delete(k)
  };
  const win = {
    innerWidth,
    innerHeight,
    screen: {
      width: screenWidth,
      height: screenHeight,
      orientation: orientationType ? { type: orientationType } : undefined
    },
    location: { pathname },
    localStorage: storage,
    matchMedia: q => ({ matches: !!media[q] }),
    navigator: { userAgent: ua, platform, userAgentData, maxTouchPoints }
  };
  if (ontouchstart) win.ontouchstart = null;
  return { window: win, storage, storageMap };
}

test('detects Windows, Linux, macOS desktops and Windows touch hybrids as desktop', () => {
  const cases = [
    ['Windows desktop', {
      ua: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/134.0.0.0 Safari/537.36',
      platform: 'Win32', userAgentData: { platform: 'Windows', mobile: false },
      media: { '(pointer: fine)': true, '(any-pointer: fine)': true, '(hover: hover)': true }
    }, 'windows', 'desktop'],
    ['Windows touchscreen laptop (hybrid)', {
      ua: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Edg/134.0.0.0',
      platform: 'Win32', userAgentData: { platform: 'Windows', mobile: false },
      maxTouchPoints: 10, ontouchstart: true,
      media: { '(pointer: fine)': true, '(any-pointer: fine)': true, '(any-pointer: coarse)': true, '(hover: hover)': true }
    }, 'windows', 'hybrid'],
    ['Linux desktop', {
      ua: 'Mozilla/5.0 (X11; Linux x86_64; rv:136.0) Gecko/20100101 Firefox/136.0',
      platform: 'Linux x86_64',
      media: { '(pointer: fine)': true, '(hover: hover)': true }
    }, 'linux', 'desktop'],
    ['macOS desktop', {
      ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.3 Safari/605.1.15',
      platform: 'MacIntel', maxTouchPoints: 0,
      media: { '(pointer: fine)': true, '(hover: hover)': true }
    }, 'macos', 'desktop']
  ];
  for (const [label, spec, expectedOs, expectedForm] of cases) {
    const res = api.detectPlatform(mockEnv(spec));
    assert.equal(res.profile, 'desktop', label);
    assert.equal(res.os, expectedOs, label);
    assert.equal(res.formFactor, expectedForm, label);
  }
});

test('detects Android phone, Android tablet, Samsung Internet, iPhone and iPadOS Safari as mobile', () => {
  const cases = [
    ['Android Chrome phone', {
      ua: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134.0.0.0 Mobile Safari/537.36',
      platform: 'Linux armv8l', userAgentData: { platform: 'Android', mobile: true },
      maxTouchPoints: 5, ontouchstart: true, innerWidth: 412, innerHeight: 915,
      media: { '(pointer: coarse)': true, '(hover: none)': true }
    }, 'android', 'phone'],
    ['Samsung Internet phone', {
      ua: 'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 SamsungBrowser/25.0 Chrome/121.0.0.0 Mobile Safari/537.36',
      platform: 'Linux armv8l', maxTouchPoints: 5, ontouchstart: true, innerWidth: 384, innerHeight: 854,
      media: { '(pointer: coarse)': true, '(hover: none)': true }
    }, 'android', 'phone'],
    ['Android tablet (no Mobile token)', {
      ua: 'Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 Chrome/134.0.0.0 Safari/537.36',
      platform: 'Linux armv8l', userAgentData: { platform: 'Android', mobile: false },
      maxTouchPoints: 10, ontouchstart: true, innerWidth: 1280, innerHeight: 800,
      media: { '(pointer: coarse)': true, '(hover: none)': true }
    }, 'android', 'tablet'],
    ['iPhone Safari', {
      ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 Version/18.3 Mobile/15E148 Safari/604.1',
      platform: 'iPhone', maxTouchPoints: 5, ontouchstart: true, innerWidth: 393, innerHeight: 852,
      media: { '(pointer: coarse)': true, '(hover: none)': true }
    }, 'ios', 'phone'],
    ['iPadOS Safari masquerading as MacIntel', {
      ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.3 Safari/605.1.15',
      platform: 'MacIntel', maxTouchPoints: 5, ontouchstart: true, innerWidth: 1180, innerHeight: 820,
      media: { '(pointer: coarse)': true, '(hover: none)': true }
    }, 'ipados', 'tablet']
  ];
  for (const [label, spec, expectedOs, expectedForm] of cases) {
    const res = api.detectPlatform(mockEnv(spec));
    assert.equal(res.profile, 'mobile', label);
    assert.equal(res.os, expectedOs, label);
    assert.equal(res.formFactor, expectedForm, label);
  }
});

test('narrow desktop window never triggers mobile profile without mobile signals', () => {
  const res = api.detectPlatform(mockEnv({
    ua: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/134.0.0.0 Safari/537.36',
    platform: 'Win32', innerWidth: 480, innerHeight: 700,
    media: { '(pointer: fine)': true, '(hover: hover)': true }
  }));
  assert.equal(res.profile, 'desktop');
});

test('manual override persists per pathname and falls back cleanly if target bundle is absent', () => {
  const env = mockEnv({
    ua: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/134.0.0.0',
    platform: 'Win32', media: { '(pointer: fine)': true, '(hover: hover)': true }
  });
  assert.equal(api.resolveProfile(env, ['desktop', 'mobile']).selected, 'desktop');
  assert.equal(api.writeSavedPreference(env.storage, '/astraclient.html', 'mobile'), true);
  const forced = api.resolveProfile(env, ['desktop', 'mobile']);
  assert.equal(forced.selected, 'mobile');
  assert.equal(forced.source, 'manual');
  assert.equal(forced.detected, 'desktop');

  // If mobile bundle is not deployed, gracefully falls back to desktop.
  const desktopOnly = api.resolveProfile(env, ['desktop']);
  assert.equal(desktopOnly.selected, 'desktop');
  assert.equal(desktopOnly.fallback, true);

  // Resetting to auto clears override.
  assert.equal(api.writeSavedPreference(env.storage, '/astraclient.html', 'auto'), true);
  assert.equal(api.resolveProfile(env, ['desktop', 'mobile']).selected, 'desktop');
});

test('mobile viewport controller handles fullscreen/orientation lock failures and virtual keyboard safely', async () => {
  const listeners = new Map();
  const states = [];
  const editor = { tagName: 'TEXTAREA' };
  const doc = {
    activeElement: null,
    fullscreenElement: null,
    getElementById: id => id === 'astra-virtual-keyboard' ? editor : null,
    documentElement: {
      requestFullscreen: async () => { throw new Error('blocked'); }
    },
    addEventListener: () => {},
    removeEventListener: () => {}
  };
  const win = {
    innerWidth: 390,
    innerHeight: 844,
    document: doc,
    screen: {
      orientation: {
        type: 'portrait-primary',
        lock: async () => { throw new Error('NotSupportedError'); },
        addEventListener: () => {},
        removeEventListener: () => {}
      }
    },
    visualViewport: {
      height: 844,
      addEventListener: () => {},
      removeEventListener: () => {}
    },
    matchMedia: q => ({ matches: q === '(orientation: portrait)' }),
    addEventListener(type, fn) { listeners.set(type, fn); },
    removeEventListener(type) { listeners.delete(type); }
  };

  const controller = api.createMobileViewportController({
    window: win, document: doc,
    onOrientationState: st => states.push(st)
  });
  controller.install();
  controller.activate();
  const attempt = await controller.requestFullscreenAndLandscape();
  assert.equal(attempt.fullscreen, false);
  assert.equal(attempt.orientationLocked, false);
  assert.equal(states.at(-1).showRotateOverlay, true);

  // Rotate to landscape-secondary (landscape-right)
  win.innerWidth = 844; win.innerHeight = 390;
  win.screen.orientation.type = 'landscape-secondary';
  win.matchMedia = q => ({ matches: q === '(orientation: landscape)' });
  win.visualViewport.height = 390;
  listeners.get('orientationchange')();
  assert.equal(states.at(-1).portrait, false);
  assert.equal(states.at(-1).showRotateOverlay, false);

  // Opening virtual keyboard shrinks visualViewport in landscape; must NOT trigger rotate overlay.
  doc.activeElement = editor;
  win.visualViewport.height = 170;
  controller.syncState();
  assert.equal(states.at(-1).portrait, false);
  assert.equal(states.at(-1).showRotateOverlay, false);
  assert.equal(states.at(-1).keyboardHeight, 220);

  controller.dispose();
  assert.equal(listeners.size, 0);
});
