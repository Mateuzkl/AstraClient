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

-- Controlado pelo checkbox "DEBUG POS" do cavebot (per-cavebot via config.debugPos).
-- Default desligado; o hunting_recorder chama setEnabled() ao carregar a config e
-- ao alternar o checkbox. Preserva o estado atual em hot-reload.
CaveBot.WaypointHud.enabled = (CaveBot.WaypointHud.enabled == true)

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

-- Label string cache: labels are pure functions of (index, type, label) and
-- only change when the route changes. Re-concatenating "i. type[:label]" for
-- every in-range waypoint every 250ms is wasted string churn, so cache per
-- index and invalidate when the underlying waypoints table is swapped.
local labelCache = {}
local labelCacheRoute = nil

local function resetLabelCache(routeRef)
    labelCache = {}
    labelCacheRoute = routeRef
end

local function labelFor(index, wp, t)
    local cached = labelCache[index]
    if cached and cached.t == t and cached.label == wp.label then
        return cached.str
    end
    local str
    if (t == "label" or t == "goto") and wp.label and wp.label ~= "" then
        str = index .. ". " .. t .. ":" .. wp.label
    else
        str = index .. ". " .. t
    end
    labelCache[index] = { str = str, t = t, label = wp.label }
    return str
end

-- Memoization: skip the clear + re-add when the drawn set is identical to last
-- tick. Marks are tile-anchored in the engine (stored as absolute positions in
-- m_cavebotMarks and re-projected each frame by MapView::drawMapForeground), so
-- leaving them untouched keeps them correct as the map scrolls — verified they
-- persist between refreshes and are only cleared by an explicit
-- clearCavebotMarks(). The signature encodes exactly what would be drawn
-- (player floor/pos gating, per-waypoint pos+color+label), so ANY visible
-- change (player move, current-waypoint highlight, waypoint edit/insert/remove,
-- route swap) produces a different signature and forces a rebuild.
local lastSig = nil
local sigParts = {}

-- Clear marks and drop the memo so the next good refresh rebuilds from scratch.
local function clearAndReset()
    g_map.clearCavebotMarks()
    lastSig = nil
end

local function refresh()
    if not g_map or not g_map.clearCavebotMarks or not g_map.addCavebotMark then
        return
    end

    -- Estados "nada para mostrar": limpa e zera o memo (garante que nada fica
    -- "preso" na tela quando desliga, sai do jogo, ou troca de rota).
    if not CaveBot.WaypointHud.enabled then return clearAndReset() end
    if not g_game.isOnline() then return clearAndReset() end

    local player = g_game.getLocalPlayer()
    if not player then return clearAndReset() end
    local ppos = player:getPosition()
    if not ppos then return clearAndReset() end

    local recorder = modules.game_helper and modules.game_helper.hunting_recorderModule
    if not recorder or not recorder.getCurrentCavebotData then return clearAndReset() end
    local data = recorder.getCurrentCavebotData()
    if not data or not data.waypoints or #data.waypoints == 0 then return clearAndReset() end

    -- Route swapped wholesale -> drop the per-index label cache.
    if data.waypoints ~= labelCacheRoute then
        resetLabelCache(data.waypoints)
    end

    local cavebotOn = CaveBot.isOn and CaveBot.isOn() or false
    local currentIdx = cavebotOn and (CaveBot.getCurrentIndex and CaveBot.getCurrentIndex()) or 0

    -- Pass 1 (always): build a signature of exactly what we'd draw. The original
    -- code already iterated every waypoint to test range, so this adds only light
    -- string work and keeps the hot (unchanged) path allocation-free. Computing
    -- color/label here is cheap (labels are cached) and lets the signature track
    -- the highlight + label, so any visible change forces a rebuild.
    sigParts[1] = ppos.x; sigParts[2] = ppos.y; sigParts[3] = ppos.z
    sigParts[4] = currentIdx
    local sigCount = 4
    for i, wp in ipairs(data.waypoints) do
        local pos = wp.position
        if pos and pos.z == ppos.z
           and math.abs(pos.x - ppos.x) <= RANGE_X
           and math.abs(pos.y - ppos.y) <= RANGE_Y then
            local t = normType(wp)
            local color = (i == currentIdx) and NEXT_COLOR or (TYPE_COLORS[t] or DEFAULT_COLOR)
            sigCount = sigCount + 1; sigParts[sigCount] = i
            sigCount = sigCount + 1; sigParts[sigCount] = pos.x
            sigCount = sigCount + 1; sigParts[sigCount] = pos.y
            sigCount = sigCount + 1; sigParts[sigCount] = color
            sigCount = sigCount + 1; sigParts[sigCount] = labelFor(i, wp, t)
        end
    end
    -- Trim any leftovers from a longer previous tick so concat is exact.
    for k = sigCount + 1, #sigParts do sigParts[k] = nil end

    local sig = table.concat(sigParts, "|")
    if sig == lastSig then
        -- Nothing the HUD draws has changed; leave the existing tile-anchored
        -- marks in place (they follow the scroll on the engine side). No clear,
        -- no re-add, no allocation — this is the common idle/standing tick.
        return
    end

    -- Pass 2 (only when something changed): rebuild the engine marks.
    g_map.clearCavebotMarks()
    for i, wp in ipairs(data.waypoints) do
        local pos = wp.position
        if pos and pos.z == ppos.z
           and math.abs(pos.x - ppos.x) <= RANGE_X
           and math.abs(pos.y - ppos.y) <= RANGE_Y then
            local t = normType(wp)
            local color = (i == currentIdx) and NEXT_COLOR or (TYPE_COLORS[t] or DEFAULT_COLOR)
            g_map.addCavebotMark(pos, color, labelFor(i, wp, t), 0)
        end
    end
    lastSig = sig
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
    -- We cleared the engine marks outside refresh(); drop the memo so a later
    -- start() rebuilds them even if pos/idx/route are unchanged.
    lastSig = nil
end

CaveBot.WaypointHud.refresh = refresh

-- Auto-start (cancela evento antigo em caso de reload)
CaveBot.WaypointHud.start()

return CaveBot.WaypointHud
