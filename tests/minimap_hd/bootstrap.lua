-- Isolated smoke-test profile. Never use the normal client write directory.
APP_NAME = "astra_hd_minimap_smoke"
assert(loadstring(g_resources.readFileContents('/production-init.lua'), '@production-init.lua'))()
-- Start each run in classic mode even if a previous interrupted smoke test
-- saved HD in this dedicated (non-user) profile.
g_settings.set('minimapHD', false)
modules.client_settings.setOption('minimapHD', false)
