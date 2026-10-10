-- Separate write directory: never alter the user's login/profile/world data.
APP_NAME = "astra_hd_minimap_export"
assert(loadstring(g_resources.readFileContents('/production-init.lua'), '@production-init.lua'))()
g_settings.set('minimapHD', false)
modules.client_settings.setOption('minimapHD', false)
