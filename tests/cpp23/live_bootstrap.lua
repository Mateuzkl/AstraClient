APP_NAME = "astra_cpp23_live"
assert(loadstring(g_resources.readFileContents('/production-init.lua'), '@production-init.lua'))()
g_settings.set('minimapHD', false)
modules.client_settings.setOption('minimapHD', false)
