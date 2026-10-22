-- Dedicated profile: never load production init.lua, user mods or login credentials.
APP_NAME = "astra_rmlui_smoke"
g_modules.discoverModules()
g_modules.ensureModuleLoaded('corelib')
rootWidget = g_ui.getRootWidget()
g_window.resize({width = 800, height = 600})
