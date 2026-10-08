const statusElement = document.getElementById('astra-status');
const setAstraStatus = (message) => {
  statusElement.textContent = message || '';
  if (window.AstraLauncher) AstraLauncher.status(message);
};

var Module = {
  canvas: document.getElementById('canvas'),
  arguments: /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) ? ['-mobile'] : [],
  locateFile: (path) => new URL(path, self.location.href).href,
  print: (...values) => console.log(...values),
  printErr: (...values) => console.error(...values),
  setStatus: setAstraStatus,
  onAbort: (reason) => { setAstraStatus(`AstraClient stopped: ${reason}`); AstraLauncher.failed(String(reason)); },
  monitorRunDependencies: (left) => setAstraStatus(left ? `Loading resources (${left} remaining)…` : ''),

  astraResolveWebSocketUrl: AstraBrowser.resolveWebSocketUrl,
  astraResolveHttpUrl: AstraBrowser.resolveHttpUrl,
  astraResolveGenericWebSocketUrl: AstraBrowser.resolveGenericWebSocketUrl,
  astraShowError: (message) => { setAstraStatus(message); AstraLauncher.failed(message); },
  astraClientReady: () => { setAstraStatus(''); AstraLauncher.ready(); },
  astraFrameStats: (stats) => AstraLauncher.frameStats(stats),
  astraStartupStage: (stage) => AstraLauncher.status(stage),
  astraStartupPhase: (name, milliseconds) => AstraLauncher.phase(name, milliseconds),

  preRun: [() => {
    const fail = (message) => {
      setAstraStatus(message);
      throw new Error(message);
    };
    AstraBrowser.assertSecurePage();
    if (!self.crossOriginIsolated)
      fail('Cross-origin isolation is required. Serve with COOP: same-origin and COEP: require-corp.');
    if (!document.createElement('canvas').getContext('webgl2'))
      fail('This browser or GPU does not provide WebGL 2.');

    if (!FS.analyzePath('/user').exists) FS.mkdir('/user');
    FS.mount(IDBFS, {}, '/user');
    addRunDependency('astra-idbfs');
    const restoreStarted = performance.now();
    AstraLauncher.status('Restoring saved settings…');
    AstraBrowser.restorePersistence(FS, error => {
      if (error) fail('Unable to securely restore browser settings. Clear this site\'s saved settings and retry.');
      AstraLauncher.phase('idbfsRestore', performance.now() - restoreStarted);
      removeRunDependency('astra-idbfs');
    });
  }],

  onRuntimeInitialized: () => {
    AstraLauncher.runtimeInitialized();
    setAstraStatus('');
    Module.canvas.focus();
    const persistence = AstraBrowser.createPersistence(FS, () => window.location.reload());
    Module.astraSyncUserData = persistence.sync;
    Module.astraReload = persistence.reload;
    if (Module.astraStopPersistence) Module.astraStopPersistence();
    Module.astraStopPersistence = AstraBrowser.installPersistenceHooks(persistence.sync);
  }
};

Module.canvas.addEventListener('webglcontextlost', (event) => {
  event.preventDefault();
  setAstraStatus('WebGL context lost. Reload the page to continue.');
});
Module.canvas.addEventListener('contextmenu', event => event.preventDefault());
