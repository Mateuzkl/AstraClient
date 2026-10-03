// Deployment-owned configuration. Never derive credential destinations from
// query parameters. Edit this file next to astraclient.html; no rebuild needed.
window.ASTRA_CONFIG = window.ASTRA_CONFIG || {};
// Set performance: true in this trusted config to show local startup, download,
// cache verification and frame/heap-capacity diagnostics. Disabled by default;
// nothing is transmitted to a telemetry service.

// Example for a same-origin nginx deployment with TWO WebSocket bridges:
// window.ASTRA_CONFIG = {
//   websocketOverrides: {
//     '127.0.0.1:7171': '/login', // bridge -> TFS TCP login port 7171
//     '127.0.0.1:7172': '/game'   // bridge -> TFS TCP game port 7172
//   }
// };
// Keys must match the host/port configured in init.lua and advertised by TFS.
