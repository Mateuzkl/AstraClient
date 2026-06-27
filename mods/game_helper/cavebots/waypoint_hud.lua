-- CaveBot Waypoint HUD
-- Desenha os waypoints da rota atual sobre a janela do jogo (game window),
-- alimentando o overlay nativo do engine via g_map.addCavebotMark (desenhado em
-- C++ por MapView::drawMapForeground -> fill + borda + rotulo no tile, com
-- scroll suave e clipping). Tudo aqui e Lua; o desenho pesado e do engine.
--
-- A cada tick: limpa as marcas e re-popula apenas os waypoints proximos da tela
-- (o engine ja limita a 96). O proximo waypoint (alvo do cavebot) fica verde.

CaveBot = CaveBot or {}
CaveBot.WaypointHud = CaveBot.WaypointHud or {}

local HUD_INTERVAL = 250  -- ms entre atualizacoes
local RANGE_X = 10        -- tiles do player no eixo X (cobre a viewport + margem)
local RANGE_Y = 8         -- tiles do player no eixo Y

CaveBot.WaypointHud.enabled = (CaveBot.WaypointHud.enabled ~= false)

-- Cor por tipo de waypoint (string hex; Color aceita string no luabind)
local TYPE_COLORS = {
    node       = "#3aa0ff",  -- azul (andar)
    stand      = "#00e5e5",  -- ciano (acoes parado)
    use        = "#00e5e5",
    rope       = "#00e5e5",
    hole       = "#00e5e5",
    lever      = "#00e5e5",
    door       = "#00e5e5",
    levitate   = "#00e5e5",
    label      = "#ffcc00",  -- amarelo (fluxo)
    ["goto"]   = "#ffcc00",
    stop_to_kill = "#ff5555", -- vermelho (combate)
    stop_cavebot = "#ff5555",
    start_lure = "#c77dff",  -- roxo (lure)
    stop_lure  = "#c77dff",
    deposit    = "#ffa033",  -- laranja (cidade)
    bank       = "#ffa033",
    travel     = "#ffa033",
    buy_refill = "#ffa033",
    wait_delay = "#9aa0a6",  -- cinza (espera)
}
local DEFAULT_COLOR = "#9aa0a6"
local NEXT_COLOR     = "#28e05a"  -- verde: proximo waypoint (alvo atual)

local function normType(wp)
    local t = wp.type
    if CavebotUtils and CavebotUtils.waypointTypeToString then
        return CavebotUtils.waypointTypeToString(t)
    end
    if type(t) == "string" then return t:lower() end
    return "node"
end

local function labelFor(index, wp, t)
    if (t == "label" or t == "goto") and wp.label and wp.label ~= "" then
        return index .. ". " .. t .. ":" .. wp.label
    end
    return index .. ". " .. t
end

local function refresh()
    if not g_map or not g_map.clearCavebotMarks or not g_map.addCavebotMark then
        return
    end

    -- Sempre comeca limpando: garante que nada fica "preso" na tela quando
    -- desliga, sai do jogo, ou troca de rota.
    g_map.clearCavebotMarks()

    if not CaveBot.WaypointHud.enabled then return end
    if not g_game.isOnline() then return end

    local player = g_game.getLocalPlayer()
    if not player then return end
    local ppos = player:getPosition()
    if not ppos then return end

    local recorder = modules.game_helper and modules.game_helper.hunting_recorderModule
    if not recorder or not recorder.getCurrentCavebotData then return end
    local data = recorder.getCurrentCavebotData()
    if not data or not data.waypoints or #data.waypoints == 0 then return end

    local cavebotOn = CaveBot.isOn and CaveBot.isOn() or false
    local currentIdx = cavebotOn and (CaveBot.getCurrentIndex and CaveBot.getCurrentIndex()) or 0

    for i, wp in ipairs(data.waypoints) do
        local pos = wp.position
        if pos and pos.z == ppos.z
           and math.abs(pos.x - ppos.x) <= RANGE_X
           and math.abs(pos.y - ppos.y) <= RANGE_Y then
            local t = normType(wp)
            local isNext = (i == currentIdx)
            local color = isNext and NEXT_COLOR or (TYPE_COLORS[t] or DEFAULT_COLOR)
            g_map.addCavebotMark(pos, color, labelFor(i, wp, t), 0)
        end
    end
end

function CaveBot.WaypointHud.setEnabled(enabled)
    CaveBot.WaypointHud.enabled = enabled and true or false
    refresh()
end

function CaveBot.WaypointHud.start()
    if CaveBot.WaypointHud._event then
        CaveBot.WaypointHud._event:cancel()
    end
    -- pcall p/ um erro transitorio (ex: rota antiga com formato inesperado) nao
    -- matar o cycleEvent; loga uma unica vez p/ nao floodar.
    CaveBot.WaypointHud._event = cycleEvent(function()
        local ok, err = pcall(refresh)
        if not ok and not CaveBot.WaypointHud._errLogged then
            CaveBot.WaypointHud._errLogged = true
            g_logger.warning("[WaypointHud] erro no refresh: " .. tostring(err))
        end
    end, HUD_INTERVAL)
end

function CaveBot.WaypointHud.stop()
    if CaveBot.WaypointHud._event then
        CaveBot.WaypointHud._event:cancel()
        CaveBot.WaypointHud._event = nil
    end
    if g_map and g_map.clearCavebotMarks then
        g_map.clearCavebotMarks()
    end
end

CaveBot.WaypointHud.refresh = refresh

-- Auto-start (cancela evento antigo em caso de reload)
CaveBot.WaypointHud.start()

return CaveBot.WaypointHud
