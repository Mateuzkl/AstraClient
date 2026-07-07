-- ============================================================================
-- test_helper_cleanup.lua
-- Valida em RUNTIME (dentro do cliente) a limpeza do game_helper (Fases A/B/C):
--   A) codigo morto removido (sistema cavebotState, keybind morto)
--   B) estado consistente (markCavebotDisabled, Recorder intacto)
--   C) API de scripting: simbolos publicados em _G (senao a API vira no-op)
--
-- COMO RODAR:
--   Abra o terminal do cliente (Ctrl+T) e execute:
--     dofile('/mods/game_helper/tests/test_helper_cleanup.lua')
--   Cada linha sai como [PASS]/[FAIL]; no fim vem o total.
--
-- Rode DEPOIS do helper inicializar (as publicacoes _G sao feitas no init()).
-- Nao tem efeito colateral: so le estado e chama markCavebotDisabled uma vez
-- (no-op se o cavebot ja estiver desligado).
-- ============================================================================

local pass, fail, fails = 0, 0, {}
local function check(name, cond)
    if cond then
        pass = pass + 1
        print("[PASS] " .. name)
    else
        fail = fail + 1
        fails[#fails + 1] = name
        print("[FAIL] " .. name)
    end
end

local gh = modules and modules.game_helper
local hr = gh and gh.hunting_recorderModule

print("========================================")
print(" Teste de limpeza do game_helper (A/B/C)")
print("========================================")

-- ---------------------------------------------------------------------------
-- FASE C: a API de scripting (scripting/api/*) le tudo via _G.X. Sem publicacao
-- _G.X e nil e a funcao da API vira no-op. Aqui checamos que estao publicados.
-- ---------------------------------------------------------------------------
print("-- Fase C: publicacoes _G (API de scripting) --")
local pubFns = {
    "saveSettings", "toggleAutoTarget", "toggleMagicShooter", "toggleCavebotHelper",
    "botStatus", "getModulePresetSlotName", "getModulePresetSlotIndex",
    "getModulePresetUiName", "activateModulePresetBySlot", "captureModulePresetData",
    "applyModulePresetData", "ensureModulePresetConfig", "refreshModulePresetUi",
    "getShooterProfile", "loadShooterProfileByName", "onLoadHelperData", "deepCopy",
}
for _, n in ipairs(pubFns) do
    check("_G." .. n .. " (funcao)", type(_G[n]) == "function")
end
check("_G.CaveBot (tabela)", type(_G.CaveBot) == "table")
check("_G.CaveBot.gotoLabel (funcao)", type(_G.CaveBot) == "table" and type(_G.CaveBot.gotoLabel) == "function")
check("_G.cavebotWalker (tabela)", type(_G.cavebotWalker) == "table")
check("_G.helper (nao-nil)", _G.helper ~= nil)
check("_G.modulePresetFields (nao-nil)", _G.modulePresetFields ~= nil)
check("_G.modulePresetMeta (nao-nil)", _G.modulePresetMeta ~= nil)
-- ja publicados antes desta limpeza (sanity):
check("_G.hunting_recorderModule (tabela)", type(_G.hunting_recorderModule) == "table")
check("_G.helperConfig (nao-nil)", _G.helperConfig ~= nil)

-- ---------------------------------------------------------------------------
-- FASE B: estado consistente
-- ---------------------------------------------------------------------------
print("-- Fase B: estado consistente --")
check("hunting_recorderModule.markCavebotDisabled existe", hr and type(hr.markCavebotDisabled) == "function")
check("CaveBot.Recorder.enable intacto", _G.CaveBot and _G.CaveBot.Recorder and type(_G.CaveBot.Recorder.enable) == "function")
if hr and type(hr.markCavebotDisabled) == "function" then
    check("markCavebotDisabled executa sem erro", pcall(hr.markCavebotDisabled))
end

-- ---------------------------------------------------------------------------
-- FASE A: codigo morto removido. Globais "bare"/module do sandbox vivem em
-- modules.game_helper (== env do modulo), entao removidos => campo == nil.
-- ---------------------------------------------------------------------------
print("-- Fase A: codigo morto removido --")
local deadFns = {
    "toggleCavebot", "toggleCavebotRecording", "startCavebotRecording",
    "stopCavebotRecording", "toggleCavebotPlaying", "stopCavebotPlaying",
    "pauseCavebot", "stopCavebot", "clearCavebot", "newCavebotSession",
    "loadCavebotSession", "saveCavebotSession", "deleteCavebotSession",
    "startCavebotPlaying", "executeCavebotStep", "updateCavebotInterface",
    "onCavebotPositionChange", "addWaypoint", "updateSessionsList",
}
for _, n in ipairs(deadFns) do
    check("morto removido: " .. n, gh and gh[n] == nil and _G[n] == nil)
end
check("styles/cavebot.otui removido do disco", g_resources ~= nil and not g_resources.fileExists("/mods/game_helper/styles/cavebot.otui"))

-- ---------------------------------------------------------------------------
-- SANITY: o cavebot REAL e as funcoes vivas nao foram afetadas
-- ---------------------------------------------------------------------------
print("-- Sanity: cavebot real intacto --")
check("hunting_recorderModule.startWalk", hr and type(hr.startWalk) == "function")
check("hunting_recorderModule.stopWalk", hr and type(hr.stopWalk) == "function")
check("hunting_recorderModule.onDeathSignal", hr and type(hr.onDeathSignal) == "function")
check("hunting_recorderModule.onRespawnSignal", hr and type(hr.onRespawnSignal) == "function")
check("hunting_recorderModule.EnableCavebotReal", hr and type(hr.EnableCavebotReal) == "function")
check("toggleCavebotHelper (real) existe", type(_G.toggleCavebotHelper) == "function")

print("----------------------------------------")
if fail == 0 then
    print(string.format(" RESULTADO: OK -- %d/%d testes passaram", pass, pass))
else
    print(string.format(" RESULTADO: %d PASS, %d FAIL", pass, fail))
    for _, n in ipairs(fails) do print("   -> FALHOU: " .. n) end
end
print("========================================")
return fail == 0
