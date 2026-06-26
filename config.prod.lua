-- Server client config. Shipped as config.lua by:
--   .\tools\make_release.ps1 -ConfigFile config.prod.lua -Encrypt
--
-- Only public endpoints live here (no AUTO_LOGIN, no localhost), so this file is
-- safe to track in git. init.lua reads the returned { Services, Servers } table;
-- it takes precedence over the env-specific defaults baked into init.lua.

-- Base host for the Koliseu web API (login + account pages + status + crash).
local HOST = "https://game.koliseuot.com.br"

return {
  Services = {
    website          = HOST,
    -- Auto-update is handled by the external Launcher (testServer/otc channel),
    -- so the in-client updater stays off here. Point this at a test updater
    -- endpoint only if you wire one up (and ship in data.zip mode).
    updater          = "",
    stats            = "",
    crash            = HOST .. "/api/client/crash",
    feedback         = "",
    -- Players-online: client_topmenu POSTs {type="cacheinfo"} to each url. Must be a LIST.
    status           = { HOST .. "/api/status" },
    -- Forgot-password / create-account links on the login modal.
    createAccount    = HOST .. "/account/register",
    recoveryPassword = HOST .. "/account/recover",
    -- "Get Coins" (store + market) opens this. Read as Services.Coins in the code.
    Coins            = HOST .. "/donate",
  },
  Servers = {
    -- Table form (not a bare string) so clientServicesLink is explicit. Boosted
    -- creature/boss: client_background POSTs {type="boostedcreature"} here.
    Koliseu = {
      name               = "Koliseu",
      loginLink          = HOST .. "/api/login",
      clientServicesLink = HOST .. "/api/status",
    },
  },
}
