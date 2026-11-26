/* Browser-only endpoint, cursor and persistence helpers, shared with regression tests. */
(() => {
  'use strict';
  const supplied = window.ASTRA_CONFIG || {};
  const config = {
    title: 'Astra Web',
    loginUrl: '',
    ...supplied,
    game: { scheme: 'auto', host: '', port: null, path: '', ...(supplied.game || {}) },
    httpOverrides: { ...(supplied.httpOverrides || {}) },
    websocketOverrides: { ...(supplied.websocketOverrides || {}) }
  };
  window.ASTRA_CONFIG = config;
  document.title = config.title;
  const assertSecurePage = () => {
    const host = location.hostname.toLowerCase();
    if (location.protocol !== 'https:' && !(location.protocol === 'http:' &&
        ['localhost', '127.0.0.1', '[::1]'].includes(host)))
      throw new Error('Astra Web requires HTTPS in production. HTTP is allowed only on loopback.');
  };

  // Opening a crafted link must not change where passwords are sent.
  const query = new URLSearchParams(location.search);
  if (['gameHost', 'gamePort', 'gamePath', 'gameScheme', 'loginUrl'].some(key => query.has(key)))
    console.warn('AstraClient ignores endpoint query parameters. Configure trusted destinations in config.js.');

  const websocketBase = () => {
    const url = new URL(document.baseURI);
    url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    return url;
  };
  const validate = (value, websocket, routingSource = false) => {
    assertSecurePage();
    const url = new URL(value, websocket ? websocketBase() : document.baseURI);
    const protocols = websocket ? ['ws:', 'wss:'] : ['http:', 'https:'];
    if (!protocols.includes(url.protocol) || url.username || url.password || url.hash)
      throw new Error('Invalid AstraClient endpoint (scheme, credentials or fragment).');
    if (!routingSource && (location.protocol === 'https:' || !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) &&
        (url.protocol === 'http:' || url.protocol === 'ws:'))
      throw new Error('Mixed content blocked: HTTPS pages require HTTPS/WSS endpoints.');
    return url;
  };
  const setPort = (url, value) => {
    if (value == null || value === '') return;
    const port = Number(value);
    if (!Number.isInteger(port) || port < 1 || port > 65535)
      throw new Error('Invalid AstraClient endpoint port.');
    url.port = String(port);
  };
  const hostUrl = (host, port, scheme) => {
    const value = String(host);
    if (/^wss?:\/\//i.test(value)) return validate(value, true, true);
    // Reject user-info, paths and malformed schemes in a bare hostname.
    if (!value || /[\s\/@?#]/.test(value) || value.includes('://'))
      throw new Error('Invalid AstraClient endpoint hostname.');
    const authority = value.includes(':') && !value.startsWith('[') ? `[${value}]` : value;
    const url = validate(`${scheme}://${authority}/`, true, true);
    setPort(url, port);
    return url;
  };

  window.AstraBrowser = {
    assertSecurePage,
    ownsKeyboardFocus() {
      const focused = document.activeElement;
      const canvas = document.getElementById('canvas');
      const vkb = document.getElementById('astra-virtual-keyboard');
      const mobileInput = document.getElementById('astra-mobile-input');
      const mobileTextarea = document.getElementById('astra-mobile-textarea');
      return !!focused && (focused === canvas || focused === vkb || focused === mobileInput || focused === mobileTextarea);
    },

    keyboardPolicy(event, mapped) {
      if (!this.ownsKeyboardFocus()) return 0; // HTML controls keep their keys.
      const vkb = document.getElementById('astra-virtual-keyboard');
      const canvas = document.getElementById('canvas');
      const mobileInput = document.getElementById('astra-mobile-input');
      const mobileTextarea = document.getElementById('astra-mobile-textarea');
      if ((mobileInput && mobileInput !== vkb && mobileInput !== canvas && document.activeElement === mobileInput) ||
          (mobileTextarea && mobileTextarea !== vkb && mobileTextarea !== canvas && document.activeElement === mobileTextarea))
        return 0; // Native mobile input/textarea handles all keys/IME/paste.
      const printable = [...(event.key || '')].length === 1;
      if (!mapped && !printable) return 0;
      const clipboard = (event.ctrlKey || event.metaKey) && !event.altKey;
      if (clipboard && event.code === 'KeyV') return 0; // The paste bridge owns it.
      if (document.activeElement === vkb &&
          !event.ctrlKey && !event.altKey && !event.metaKey &&
          (printable || event.code === 'Backspace' || event.code === 'Enter' || event.code === 'NumpadEnter'))
        return 0; // Native editing/IME produces input/beforeinput, not duplicate text.
      return clipboard && event.code === 'KeyC' ? 1 : 3; // Dispatch + optional consume.
    },

    createCursorManager() {
      const cursors = new Map();
      let active = null;
      const apply = cursor => {
        const canvas = document.getElementById('canvas');
        if (!canvas) return;
        // Clear a stale/hidden cursor even when the replacement is rejected.
        canvas.style.cursor = 'auto';
        if (cursor && cursor !== 'none') canvas.style.cursor = cursor;
      };
      const aliases = {
        arrow: 'default', native: 'default', hand: 'pointer', link: 'pointer',
        cross: 'crosshair', target: 'crosshair', precision: 'crosshair',
        horizontal: 'ew-resize', sizewe: 'ew-resize', vertical: 'ns-resize', sizens: 'ns-resize',
        diagonal1: 'nwse-resize', sizenwse: 'nwse-resize', diagonal2: 'nesw-resize', sizenesw: 'nesw-resize',
        sizeall: 'move', ibeam: 'text', hourglass: 'wait', no: 'not-allowed', forbidden: 'not-allowed',
        appstarting: 'progress', uparrow: 'default'
      };
      const keywords = new Set(('auto default pointer text crosshair ew-resize ns-resize nwse-resize nesw-resize ' +
        'n-resize s-resize e-resize w-resize ne-resize nw-resize se-resize sw-resize col-resize row-resize ' +
        'move wait help progress not-allowed context-menu cell vertical-text alias copy no-drop ' +
        'all-scroll zoom-in zoom-out grab grabbing').split(' '));
      return {
        setSystemCursor(name) {
          active = null; // A late image load must not replace a widget's newer cursor.
          const requested = String(name || '').trim().toLowerCase();
          const cursor = aliases[requested] || requested;
          apply(keywords.has(cursor) ? cursor : 'auto');
        },
        createCursor(id, pixels, width, height, hotX, hotY) {
          const previous = cursors.get(id);
          cursors.delete(id);
          if (previous && active === previous) { active = null; apply('auto'); }
          if (!Number.isInteger(id) || id < 0 || !Number.isInteger(width) || !Number.isInteger(height) ||
              width < 1 || height < 1 || width > 128 || height > 128 ||
              !Number.isInteger(hotX) || !Number.isInteger(hotY) || hotX < 0 || hotY < 0 ||
              hotX >= width || hotY >= height || !pixels || pixels.length !== width * height * 4)
            return false;
          let visible = false;
          for (let i = 3; i < pixels.length; i += 4) {
            if (pixels[i] !== 0) { visible = true; break; }
          }
          if (!visible) return false;
          try {
            const surface = document.createElement('canvas');
            surface.width = width;
            surface.height = height;
            const context = surface.getContext('2d');
            if (!context) return false;
            // Copy out of WASM's shared heap; ImageData requires a normal buffer.
            context.putImageData(new ImageData(new Uint8ClampedArray(pixels), width, height), 0, 0);
            const url = surface.toDataURL('image/png');
            if (!url.startsWith('data:image/png;base64,') || url.length <= 22) return false;
            const image = new Image();
            const entry = { css: `url("${url}") ${hotX} ${hotY}, auto`, ready: false, image };
            cursors.set(id, entry);
            image.onload = () => {
              if (cursors.get(id) !== entry) return;
              entry.ready = true;
              if (active === entry) apply(entry.css);
            };
            image.onerror = () => {
              if (cursors.get(id) === entry) cursors.delete(id);
              if (active === entry) { active = null; apply('auto'); }
            };
            image.src = url;
            return true;
          } catch (_) {
            cursors.delete(id);
            return false;
          }
        },
        useCursor(id) {
          active = cursors.get(id) || null;
          apply(active && active.ready ? active.css : 'auto');
        },
        dispose() {
          for (const entry of cursors.values()) {
            entry.image.onload = null;
            entry.image.onerror = null;
          }
          cursors.clear();
          active = null;
          apply('auto');
        }
      };
    },

    installTextBridge(module) {
      let active = true;
      let textInputRects = [];
      let currentMeta = null;
      let composing = false;
      let touchTapStart = null;
      let lastUserInputAt = 0;
      let awaitingTabFocus = false;
      let tabFocusTimer = null;
      const clearTabFocusWait = () => {
        awaitingTabFocus = false;
        if (tabFocusTimer && typeof window.clearTimeout === 'function') {
          window.clearTimeout(tabFocusTimer);
        }
        tabFocusTimer = null;
      };
      const beginTabFocusWait = () => {
        clearTabFocusWait();
        awaitingTabFocus = true;
        if (typeof window.setTimeout === 'function') {
          tabFocusTimer = window.setTimeout(() => {
            tabFocusTimer = null;
            awaitingTabFocus = false;
          }, 350);
        }
      };
      const listeners = [];
      const listen = (target, type, callback, options) => {
        if (!target || typeof target.addEventListener !== 'function') return;
        target.addEventListener(type, callback, options);
        listeners.push([target, type, callback, options]);
      };
      const isMobileContext = () => {
        const bodyProfile = document.body && document.body.getAttribute && document.body.getAttribute('data-profile');
        if (bodyProfile === 'mobile') return true;
        return !!(window.navigator && Number(window.navigator.maxTouchPoints || 0) > 0 &&
          window.matchMedia && window.matchMedia('(pointer: coarse)').matches);
      };
      const editor = document.getElementById('astra-virtual-keyboard');
      const rawCanvas = document.getElementById('canvas');
      const canvas = rawCanvas && rawCanvas !== editor ? rawCanvas : null;
      const rawBar = document.getElementById('astra-mobile-keyboard-bar');
      const bar = rawBar && rawBar !== editor && rawBar !== canvas ? rawBar : null;
      const rawMobileInput = document.getElementById('astra-mobile-input');
      const mobileInput = rawMobileInput && rawMobileInput !== editor && rawMobileInput !== canvas ? rawMobileInput : null;
      const rawMobileTextarea = document.getElementById('astra-mobile-textarea');
      const mobileTextarea = rawMobileTextarea && rawMobileTextarea !== editor && rawMobileTextarea !== canvas && rawMobileTextarea !== mobileInput ? rawMobileTextarea : null;
      const rawNextBtn = document.getElementById('astra-mobile-input-next');
      const nextBtn = rawNextBtn && rawNextBtn !== editor && rawNextBtn !== canvas ? rawNextBtn : null;
      const rawDoneBtn = document.getElementById('astra-mobile-input-done');
      const doneBtn = rawDoneBtn && rawDoneBtn !== editor && rawDoneBtn !== canvas ? rawDoneBtn : null;

      const getActiveControl = (meta) => {
        const useMultiline = !!(meta && meta.multiline && mobileTextarea);
        return useMultiline ? mobileTextarea : mobileInput;
      };
      const isMobileControlFocused = () => {
        const ae = document.activeElement;
        return !!(ae && (ae === mobileInput || ae === mobileTextarea));
      };

      const positionBar = () => {
        if (!bar || bar.hidden) return;
        const vv = window.visualViewport;
        if (vv && typeof vv.height === 'number' && vv.height > 0) {
          const bottomOffset = Math.max(0, Math.round(window.innerHeight - (vv.height + (vv.offsetTop || 0))));
          bar.style.bottom = `${bottomOffset}px`;
        } else {
          bar.style.bottom = '0px';
        }
      };

      const configureMobileInput = (meta, preserveIfFocused) => {
        const ctrl = getActiveControl(meta);
        if (!ctrl || !meta) return null;
        const prevId = currentMeta && currentMeta.id ? currentMeta.id : '';
        const nextId = meta.id || '';
        const sameWidget = !!(prevId && nextId && prevId === nextId);
        if (!sameWidget) {
          clearTabFocusWait();
          lastUserInputAt = 0;
          composing = false;
        }
        currentMeta = meta;

        if (mobileInput && mobileTextarea) {
          const useMulti = !!(meta.multiline);
          mobileInput.hidden = useMulti;
          mobileTextarea.hidden = !useMulti;
        }
        if (ctrl === mobileInput) {
          const desiredType = meta.password ? 'password' : 'text';
          if (ctrl.type !== desiredType) {
            try { ctrl.type = desiredType; } catch (_) {}
          }
          ctrl.inputMode = meta.numeric ? 'numeric' : (meta.email ? 'email' : 'text');
        }
        ctrl.placeholder = meta.placeholder || (meta.password ? 'Password' : (meta.email ? 'Email' : (meta.numeric ? 'Token' : 'Type here…')));
        // Enforce maxLen consistently in UTF-8 bytes on the engine side to avoid UTF-16 vs UTF-8 mismatch.
        if (typeof ctrl.removeAttribute === 'function') ctrl.removeAttribute('maxlength');

        const nextVal = typeof meta.text === 'string' ? meta.text : '';
        const forceNormalized = !!(meta.normalized && sameWidget && (Date.now() - lastUserInputAt) < 120);
        const skipSync = !forceNormalized && (composing || (preserveIfFocused && sameWidget && document.activeElement === ctrl));
        if (!skipSync) {
          if (ctrl.value !== nextVal) {
            ctrl.value = nextVal;
          }
          try {
            const s = typeof meta.selStart === 'number' ? meta.selStart : nextVal.length;
            const e = typeof meta.selEnd === 'number' ? meta.selEnd : s;
            if (ctrl.selectionStart !== s || ctrl.selectionEnd !== e) {
              ctrl.setSelectionRange(s, e);
            }
          } catch (_) {}
        }
        return ctrl;
      };

      const pushMobileTextToEngine = (ctrlOverride) => {
        if (!active || awaitingTabFocus) return;
        const ctrl = ctrlOverride || getActiveControl(currentMeta);
        if (!ctrl) return;
        const expectedId = currentMeta && typeof currentMeta.id === 'string' ? currentMeta.id : '';
        const value = ctrl.value;
        const selStart = typeof ctrl.selectionStart === 'number' ? ctrl.selectionStart : value.length;
        const selEnd = typeof ctrl.selectionEnd === 'number' ? ctrl.selectionEnd : selStart;
        if (typeof module.ccall === 'function') {
          try {
            module.ccall('astra_browser_set_text', null, ['string', 'string', 'number', 'number'], [expectedId, value, selStart, selEnd]);
            return;
          } catch (_) {}
        }
        if (value) module.ccall('astra_browser_text_input', null, ['string'], [value]);
      };

      const openMobileBar = (meta, syncFocus) => {
        const targetMeta = meta || currentMeta || { text: '' };
        const ctrl = getActiveControl(targetMeta);
        if (!bar || !ctrl) {
          const fallback = document.getElementById('astra-virtual-keyboard');
          if (fallback) {
            if (targetMeta && typeof targetMeta.text === 'string') fallback.value = targetMeta.text;
            fallback.focus({ preventScroll: true });
          }
          return;
        }
        const sameFocusedWidget = !bar.hidden && currentMeta && targetMeta &&
          currentMeta.id && targetMeta.id && currentMeta.id === targetMeta.id &&
          document.activeElement === ctrl;
        configureMobileInput(targetMeta, sameFocusedWidget);
        bar.hidden = false;
        positionBar();
        if (syncFocus) {
          try { ctrl.focus({ preventScroll: true }); } catch (_) { ctrl.focus(); }
          if (!sameFocusedWidget) {
            try {
              const s = typeof targetMeta.selStart === 'number' ? targetMeta.selStart : ctrl.value.length;
              const e = typeof targetMeta.selEnd === 'number' ? targetMeta.selEnd : s;
              ctrl.setSelectionRange(s, e);
            } catch (_) {}
          }
          if (typeof navigator !== 'undefined' && navigator.virtualKeyboard && typeof navigator.virtualKeyboard.show === 'function') {
            try { navigator.virtualKeyboard.show(); } catch (_) {}
          }
        }
      };

      const closeMobileBar = (refocusCanvas) => {
        clearTabFocusWait();
        composing = false;
        if (!bar || bar.hidden) return;
        bar.hidden = true;
        if (mobileInput && document.activeElement === mobileInput) {
          try { mobileInput.blur(); } catch (_) {}
        }
        if (mobileTextarea && document.activeElement === mobileTextarea) {
          try { mobileTextarea.blur(); } catch (_) {}
        }
        if (refocusCanvas && canvas && typeof canvas.focus === 'function') {
          try { canvas.focus({ preventScroll: true }); } catch (_) {}
        }
      };

      const findHitTextRect = (cssX, cssY) => {
        const pad = 12;
        for (let i = textInputRects.length - 1; i >= 0; --i) {
          const r = textInputRects[i];
          if (cssX >= r.x - pad && cssX <= r.x + r.w + pad && cssY >= r.y - pad && cssY <= r.y + r.h + pad) {
            return r;
          }
        }
        return null;
      };

      window.AstraBrowser.updateTextInputRects = (json) => {
        if (!active) return;
        try {
          const parsed = typeof json === 'string' ? JSON.parse(json) : json;
          if (Array.isArray(parsed)) textInputRects = parsed;
        } catch (_) {}
      };
      window.AstraBrowser.getTextInputRects = () => textInputRects.slice();
      window.AstraBrowser.showMobileKeyboard = (json) => {
        if (!active) return;
        let meta = null;
        try { meta = typeof json === 'string' ? JSON.parse(json) : json; } catch (_) { meta = { text: String(json || '') }; }
        openMobileBar(meta, true);
      };
      window.AstraBrowser.syncFocusedTextInput = (json) => {
        if (!active) return;
        let meta = null;
        try { meta = typeof json === 'string' ? JSON.parse(json) : json; } catch (_) { return; }
        const prevId = currentMeta && currentMeta.id ? currentMeta.id : '';
        const switchedWidget = !!(meta && meta.id && prevId && meta.id !== prevId);
        const recentlyTyped = !switchedWidget && !meta.normalized && (Date.now() - lastUserInputAt) < 250;
        const ctrl = configureMobileInput(meta, recentlyTyped);
        if (bar && !bar.hidden) {
          positionBar();
          if (switchedWidget && ctrl && document.activeElement !== ctrl) {
            try { ctrl.focus({ preventScroll: true }); } catch (_) {}
          }
        }
      };
      window.AstraBrowser.onVirtualTabProcessed = (json) => {
        if (!active) return;
        clearTabFocusWait();
        if (!json) return;
        let meta = null;
        try { meta = typeof json === 'string' ? JSON.parse(json) : json; } catch (_) { return; }
        if (!meta || typeof meta !== 'object') return;
        const ctrl = configureMobileInput(meta, false);
        if (bar && !bar.hidden && ctrl && document.activeElement !== ctrl) {
          try { ctrl.focus({ preventScroll: true }); } catch (_) {}
        }
      };
      window.AstraBrowser.hideMobileKeyboard = () => {
        if (!active) return;
        closeMobileBar(false);
      };

      listen(document, 'paste', event => {
        if (!active || !this.ownsKeyboardFocus()) return;
        if (isMobileControlFocused()) return; // Native paste fires input on mobile control.
        const text = event.clipboardData ? event.clipboardData.getData('text/plain') : '';
        if (text) {
          module.ccall('astra_browser_paste', null, ['string'], [text]);
          event.preventDefault();
        }
      });

      if (canvas) {
        // Capture-phase touch tracking so focusing the native mobile input runs
        // synchronously inside the trusted touchend user gesture (required by iOS Safari & Android Chrome).
        listen(canvas, 'touchstart', event => {
          if (!active || !isMobileContext()) return;
          const t = event.changedTouches && event.changedTouches[0];
          if (!t) return;
          const rect = typeof canvas.getBoundingClientRect === 'function' ? canvas.getBoundingClientRect() : { left: 0, top: 0 };
          touchTapStart = { id: t.identifier, x: t.clientX - rect.left, y: t.clientY - rect.top };
        }, { capture: true, passive: true });

        listen(canvas, 'mousedown', event => {
          if (active && isMobileContext() && bar && !bar.hidden && isMobileControlFocused()) {
            event.preventDefault();
          }
        }, { capture: true });

        listen(canvas, 'touchend', event => {
          if (!active || !isMobileContext() || !touchTapStart) return;
          let matched = null;
          if (event.changedTouches) {
            for (let i = 0; i < event.changedTouches.length; ++i) {
              if (event.changedTouches[i].identifier === touchTapStart.id) {
                matched = event.changedTouches[i];
                break;
              }
            }
          }
          const start = touchTapStart;
          touchTapStart = null;
          if (!matched) return;
          const rect = typeof canvas.getBoundingClientRect === 'function' ? canvas.getBoundingClientRect() : { left: 0, top: 0 };
          const cssX = matched.clientX - rect.left;
          const cssY = matched.clientY - rect.top;
          if (Math.max(Math.abs(cssX - start.x), Math.abs(cssY - start.y)) > 20) return;
          const hit = findHitTextRect(cssX, cssY);
          if (hit) {
            // Prevent the browser from synthesizing compatibility mousedown on <canvas tabindex="0">,
            // which would otherwise steal DOM focus back from mobileInput and dismiss the native keyboard.
            if (typeof event.preventDefault === 'function') event.preventDefault();
            if (hit.id && typeof module.ccall === 'function') {
              try { module.ccall('astra_browser_focus_text_edit', null, ['string'], [hit.id]); } catch (_) {}
            }
            openMobileBar(hit, true);
          } else if (bar && !bar.hidden) {
            closeMobileBar(false);
          }
        }, { capture: true, passive: false });
      }

      const wireMobileControl = (ctrl, isMultiline) => {
        if (!ctrl) return;
        listen(ctrl, 'compositionstart', () => { composing = true; });
        listen(ctrl, 'compositionend', () => {
          composing = false;
          lastUserInputAt = Date.now();
          pushMobileTextToEngine(ctrl);
        });
        listen(ctrl, 'input', () => {
          if (!active) return;
          // Push live value even while Android IME composition (e.g. Gboard underline) is active:
          // astra_browser_set_text replaces text idempotently without duplicating characters.
          lastUserInputAt = Date.now();
          pushMobileTextToEngine(ctrl);
        });
        listen(ctrl, 'keydown', event => {
          if (!active) return;
          if (event.isComposing || event.keyCode === 229) return;
          if (event.key === 'Enter') {
            if (isMultiline) return; // Preserve native newline insertion in multiline textarea.
            composing = false;
            pushMobileTextToEngine(ctrl);
            module.ccall('astra_browser_virtual_key', null, ['number'], [13]);
            event.preventDefault();
            closeMobileBar(true);
            return;
          }
          if (composing) return;
          if (event.key === 'Tab') {
            pushMobileTextToEngine(ctrl);
            if (!isMultiline) beginTabFocusWait();
            module.ccall('astra_browser_virtual_key', null, ['number'], [9]);
            event.preventDefault();
          } else if (event.key === 'Escape') {
            module.ccall('astra_browser_virtual_key', null, ['number'], [27]);
            event.preventDefault();
            closeMobileBar(true);
          }
        });
      };
      wireMobileControl(mobileInput, false);
      wireMobileControl(mobileTextarea, true);

      if (nextBtn) {
        let lastTouchNextMs = 0;
        const triggerNext = () => {
          if (!active) return;
          const isMulti = !!(currentMeta && currentMeta.multiline);
          const fromId = currentMeta && typeof currentMeta.id === 'string' ? currentMeta.id : '';
          composing = false;
          pushMobileTextToEngine();
          if (!isMulti) beginTabFocusWait();
          let switchedViaDirectApi = false;
          if (!isMulti && typeof module.ccall === 'function') {
            try {
              module.ccall('astra_browser_next_text_edit', null, ['string'], [fromId]);
              switchedViaDirectApi = true;
            } catch (_) {}
          }
          if (!switchedViaDirectApi) {
            module.ccall('astra_browser_virtual_key', null, ['number'], [9]);
          }
          const ctrl = getActiveControl(currentMeta);
          if (ctrl) {
            try { ctrl.focus({ preventScroll: true }); } catch (_) {}
          }
        };
        listen(nextBtn, 'mousedown', event => event.preventDefault());
        listen(nextBtn, 'touchend', event => {
          event.preventDefault();
          lastTouchNextMs = Date.now();
          triggerNext();
        }, { passive: false });
        listen(nextBtn, 'click', () => {
          if (Date.now() - lastTouchNextMs < 400) return;
          triggerNext();
        });
      }
      if (doneBtn) {
        listen(doneBtn, 'click', () => {
          if (!active) return;
          pushMobileTextToEngine();
          closeMobileBar(true);
        });
      }
      if (window.visualViewport) {
        listen(window.visualViewport, 'resize', positionBar);
        listen(window.visualViewport, 'scroll', positionBar);
      }

      if (editor) {
        listen(editor, 'beforeinput', event => {
          if (active && event.inputType === 'deleteContentBackward') {
            module.ccall('astra_browser_virtual_key', null, ['number'], [8]);
            event.preventDefault();
          }
        });
        listen(editor, 'input', event => {
          if (!active) return;
          if (event.data) module.ccall('astra_browser_text_input', null, ['string'], [event.data]);
          editor.value = '';
        });
        listen(editor, 'keydown', event => {
          if (active && event.key === 'Enter') {
            module.ccall('astra_browser_virtual_key', null, ['number'], [13]);
            event.preventDefault();
          }
        });
      }
      return () => {
        active = false;
        closeMobileBar(false);
        for (const [target, type, callback, options] of listeners) target.removeEventListener(type, callback, options);
        listeners.length = 0;
      };
    },

    resolveWebSocketUrl(originalHost, originalPort) {
      const explicit = /^wss?:\/\//i.test(String(originalHost));
      if (originalPort != null) {
        const port = Number(originalPort);
        if (originalPort === '' || !Number.isInteger(port) || port < 1 || port > 65535)
          throw new Error('Invalid AstraClient endpoint port.');
      } else if (!explicit) {
        throw new Error('A bare AstraClient hostname requires a port.');
      }
      const source = hostUrl(originalHost, originalPort, location.protocol === 'https:' ? 'wss' : 'ws');
      const port = originalPort ?? (source.port || (source.protocol === 'wss:' ? 443 : 80));
      const key = `${source.hostname.toLowerCase()}:${port}`;
      if (Object.prototype.hasOwnProperty.call(config.websocketOverrides, key))
        return validate(config.websocketOverrides[key], true).href;

      const game = config.game;
      const scheme = game.scheme === 'auto'
        ? (location.protocol === 'https:' ? 'wss' : 'ws') : String(game.scheme).replace(/:$/, '');
      if (scheme !== 'ws' && scheme !== 'wss')
        throw new Error('Invalid AstraClient WebSocket scheme.');
      const url = game.host ? hostUrl(game.host, originalPort, scheme) : source;
      if (!/^wss?:\/\//i.test(game.host || originalHost)) url.protocol = `${scheme}:`;
      setPort(url, game.port);
      if (game.path) url.pathname = game.path.startsWith('/') ? game.path : `/${game.path}`;
      return validate(url.href, true).href;
    },

    resolveHttpUrl(original) {
      const source = new URL(original, document.baseURI);
      if (config.loginUrl && /(^|\/)login(?:\.[a-z0-9]+)?\/?$/i.test(source.pathname))
        return validate(config.loginUrl, false).href;
      // Keys match the exact URL supplied by the client, not the resolved URL:
      // relative requests need relative keys. Keep longest-prefix matching.
      const prefix = Object.keys(config.httpOverrides)
        .filter(key => original.startsWith(key)).sort((a, b) => b.length - a.length)[0];
      return validate(prefix ? `${config.httpOverrides[prefix]}${original.slice(prefix.length)}` : original, false).href;
    },

    resolveGenericWebSocketUrl(original) { return validate(original, true).href; },

    createPersistence(fs, reload) {
      let running = false;
      let pending = false;
      let reloadRequested = false;
      const sync = () => {
        if (running) {
          // A reload requested during a periodic flush must include newer writes.
          pending = true;
          return;
        }
        running = true;
        let completed = false;
        const finish = error => {
          if (completed) return;
          completed = true;
          running = false;
          if (error) console.error('Unable to persist AstraClient data:', error);
          if (pending) {
            pending = false;
            sync();
          } else if (reloadRequested) {
            reloadRequested = false;
            reload();
          }
        };
        try {
          if (window.AstraSecurity && fs.analyzePath) AstraSecurity.purgeSettings(fs);
          fs.syncfs(false, finish);
        }
        catch (error) { finish(error); }
      };
      return {
        sync,
        reload() {
          if (reloadRequested) return;
          reloadRequested = true;
          sync();
        }
      };
    },

    restorePersistence(fs, ready) {
      let completed = false;
      let delivered = false;
      const deliver = error => { if (!delivered) { delivered = true; ready(error); } };
      const finish = error => {
        if (completed) return;
        completed = true;
        if (error) console.error('Unable to restore AstraClient data:', error);
        if (!error && window.AstraSecurity && fs.analyzePath) {
          try {
            if (AstraSecurity.purgeSettings(fs)) {
              fs.syncfs(false, deliver);
              return;
            }
          } catch (cleanupError) { deliver(cleanupError); return; }
        }
        deliver(error);
      };
      try { fs.syncfs(true, finish); }
      catch (error) { finish(error); }
    },

    installPersistenceHooks(sync) {
      let active = true;
      const flush = () => { if (active) sync(); };
      const visibility = () => { if (document.visibilityState === 'hidden') flush(); };
      const interval = window.setInterval(flush, 15000);
      window.addEventListener('pagehide', flush);
      document.addEventListener('visibilitychange', visibility);
      return () => {
        active = false;
        window.clearInterval(interval);
        window.removeEventListener('pagehide', flush);
        document.removeEventListener('visibilitychange', visibility);
      };
    }
  };
})();
