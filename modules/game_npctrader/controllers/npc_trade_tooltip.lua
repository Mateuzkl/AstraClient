--[[
  Tooltip do comercio NPC: pocoes, runas, itens de EXP boost.
  Textos em portugues simples sem acentos (evita problema de fonte).
  Constantes de tempo/restricao alinhadas ao servidor (EXP %, item 63515, pocoes especiais, flask potions).
]]

local root
local delayEvent

--- Alinhado ao helper e tabelas de EXP do shard (on look / itens).
local EXP_BOOST_ITEM_PCT = {
  [63166] = 5, [63167] = 10, [63168] = 15, [63169] = 20, [63185] = 25, [63179] = 30,
  [63187] = 40, [63186] = 60, [63190] = 80, [63189] = 100, [63191] = 110, [63192] = 120,
  [63193] = 130, [63194] = 140, [63195] = 150, [63239] = 200, [63240] = 300,
}

--- Max character level allowed to use this boost (level must be < cap). Absent = no cap.
local LEVEL_CAP_BY_PCT = {
  [300] = 5000, [200] = 10000, [150] = 15000, [140] = 18000, [130] = 20000, [120] = 22000,
  [110] = 25000, [100] = 27500, [80] = 30000, [60] = 32500, [40] = 35000, [30] = 37500,
  [25] = 40000, [20] = 42500, [15] = 45000, [10] = 50000,
}

--- Percent values that cannot be used with 5+ resets (mesma regra do servidor).
local EXP_PCT_RESTRICTED_BY_RESETS = {
  [200] = true, [150] = true, [140] = true, [130] = true, [120] = true,
  [110] = true, [100] = true, [80] = true, [60] = true, [40] = true,
}

local EXP_BOOST_MIN_RESETS_FOR_RESTRICTION = 5

--- Bonus EXP por %% (lista EXP_BOOST_ITEM_PCT): efeito 2h, CD compartilhado 3h.
local EXP_BONUS_PERCENT_BUFF_DURATION_SEC = 7200 -- 2h
local EXP_BONUS_PERCENT_SHARED_COOLDOWN_SEC = 10800 -- 3h

--- Item 63515: efeito 4h, 24h entre usos.
local XP_BOOST_SINGLE_ITEM_DURATION_SEC = 4 * 60 * 60 -- BOOST_DURATION
local XP_BOOST_SINGLE_ITEM_COOLDOWN_SEC = 24 * 60 * 60 -- COOLDOWN_DURATION

--- @param itemId number
--- @return number effectSec, number cooldownSec
local function getExpBoostEffectAndCooldownSec(itemId)
  if itemId == 63515 then
    return XP_BOOST_SINGLE_ITEM_DURATION_SEC, XP_BOOST_SINGLE_ITEM_COOLDOWN_SEC
  end
  return EXP_BONUS_PERCENT_BUFF_DURATION_SEC, EXP_BONUS_PERCENT_SHARED_COOLDOWN_SEC
end

--- Pocoes especiais (Transcendencia, Reflect, Fatal, Dodge/Ruse, Critical).
--- Pocoes especiais 63202-63206: duracao/cooldown do shard.
--- BUFF_DURATION_MS = 30*60*1000, SHARED_COOLDOWN_SECONDS = 2*60*60 (mesmo CD para os 5 itens).
local CUSTOM_POTION_BUFF_DURATION_SEC = 30 * 60
local CUSTOM_POTION_SHARED_COOLDOWN_SEC = 2 * 60 * 60
local CUSTOM_POTION_IDS = {
  [63202] = true, -- transcendence
  [63203] = true, -- reflect
  [63204] = true, -- fatal
  [63205] = true, -- dodge / ruse
  [63206] = true, -- critical
}

--- Bonus numericos iguais ao servidor (custom potions). Critical: 1000 no core ~ +10% se 100 = 1%.
local CUSTOM_POTION_EFFECT_DESC = {
  [63202] = "Melhora: +2.35 na Transcendence",
  [63203] = "Melhora: +24.05 no Reflect",
  [63204] = "Melhora: +9.05 no Fatal (Onslaught)",
  [63205] = "Melhora: +10 no Ruse; +7.51% no Dodge",
  [63206] = "Melhora: +10% chance de Critical Hit",
}

--- Nivel/vocacao por ID (VOCATION.BASE_ID no servidor).
--- vocations = nil: sem restricao de vocacao no uso (qualquer base).
local CANARY_FLASK_POTION = {
  [236] = { level = 50, vocations = { 3, 4, 9 } },
  [237] = { level = 50, vocations = nil },
  [238] = { level = 80, vocations = { 1, 2, 3, 9 } },
  [239] = { level = 80, vocations = { 4 } },
  [7439] = { level = nil, vocations = { 4, 9 } },
  [7440] = { level = nil, vocations = { 1, 2 } },
  [7443] = { level = nil, vocations = { 3 } },
  [7642] = { level = 80, vocations = { 3, 9 } },
  [7643] = { level = 130, vocations = { 4 } },
  [23373] = { level = 130, vocations = { 1, 2 } },
  [23374] = { level = 130, vocations = { 3, 9 } },
  [23375] = { level = 200, vocations = { 4 } },
  [35563] = { level = 14, vocations = { 1, 2 } },
  [41193] = { level = 500, vocations = { 1, 2, 3, 4, 9 } },
  [41194] = { level = 500, vocations = { 3, 9 } },
  [41195] = { level = 500, vocations = { 4 } },
  [62847] = { level = 5000, vocations = { 3, 9 } },
  [62889] = { level = 10000, vocations = { 3, 9 } },
  [62845] = { level = 5000, vocations = { 4 } },
  [62890] = { level = 10000, vocations = { 4 } },
  [62846] = { level = 5000, vocations = { 1, 2 } },
  [62888] = { level = 10000, vocations = { 1, 2 } },
  [49271] = { level = nil, vocations = nil },
  [63181] = { level = 20000, vocations = { 4 } },
  [63182] = { level = 20000, vocations = { 1, 2 } },
  [63183] = { level = 20000, vocations = { 3, 9 } },
}

--- Mesmos dados indexados pelo nome do item (ThingType / items.xml), para quando o ID do cliente divergir do servidor.
local CANARY_FLASK_POTION_BY_NAME = {
  ["strong health potion"] = { level = 50, vocations = { 3, 4, 9 } },
  ["strong mana potion"] = { level = 50, vocations = nil },
  ["great mana potion"] = { level = 80, vocations = { 1, 2, 3, 9 } },
  ["great health potion"] = { level = 80, vocations = { 4 } },
  ["great spirit potion"] = { level = 80, vocations = { 3, 9 } },
  ["ultimate health potion"] = { level = 130, vocations = { 4 } },
  ["ultimate mana potion"] = { level = 130, vocations = { 1, 2 } },
  ["ultimate spirit potion"] = { level = 130, vocations = { 3, 9 } },
  ["supreme health potion"] = { level = 200, vocations = { 4 } },
  ["magic shield potion"] = { level = 14, vocations = { 1, 2 } },
  ["powerfull mana potion"] = { level = 500, vocations = { 1, 2, 3, 4, 9 } },
  ["powerfull spirit potion"] = { level = 500, vocations = { 3, 9 } },
  ["powerfull health potion"] = { level = 500, vocations = { 4 } },
  ["mega spirit potion"] = { level = 5000, vocations = { 3, 9 } },
  ["mega health potion"] = { level = 5000, vocations = { 4 } },
  ["mega mana potion"] = { level = 5000, vocations = { 1, 2 } },
  ["divine spirit potion"] = { level = 10000, vocations = { 3, 9 } },
  ["divine mana potion"] = { level = 10000, vocations = { 1, 2 } },
  ["divine health potion"] = { level = 10000, vocations = { 4 } },
  ["extreme health potion"] = { level = 20000, vocations = { 4 } },
  ["extreme mana potion"] = { level = 20000, vocations = { 1, 2 } },
  ["extreme spirit potion"] = { level = 20000, vocations = { 3, 9 } },
}

--- @param s string|nil
--- @return string
local function normalizeItemName(s)
  if not s or s == "" then
    return ""
  end
  return s:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

--- @param id number
--- @param thingName string|nil
--- @param displayName string|nil
--- @return table|nil
local function resolveCanaryFlaskPotion(id, thingName, displayName)
  local p = CANARY_FLASK_POTION[id]
  if p then
    return p
  end
  local n = normalizeItemName(thingName)
  if n ~= "" and CANARY_FLASK_POTION_BY_NAME[n] then
    return CANARY_FLASK_POTION_BY_NAME[n]
  end
  n = normalizeItemName(displayName)
  if n ~= "" and CANARY_FLASK_POTION_BY_NAME[n] then
    return CANARY_FLASK_POTION_BY_NAME[n]
  end
  return nil
end

--- Base vocation IDs (VOCATION.BASE_ID): display names in English for tooltips.
local VOCACAO_NOME = {
  [0] = "any",
  [1] = "Sorcerer",
  [2] = "Druid",
  [3] = "Paladin",
  [4] = "Knight",
  [5] = "Master Sorcerer",
  [6] = "Elder Druid",
  [7] = "Royal Paladin",
  [8] = "Elite Knight",
  [9] = "Monk",
  [10] = "Exalted Monk",
}

local function cancelDelay()
  if delayEvent then
    removeEvent(delayEvent)
    delayEvent = nil
  end
end

local function hidePanel()
  cancelDelay()
  if root and not root:isDestroyed() then
    root:setVisible(false)
  end
end

--- Replace common UTF-8 sequences with ASCII (tooltip font often breaks on accents).
--- @param s string|nil
--- @return string
local function toAscii(s)
  if not s or s == "" then
    return ""
  end
  local r = s
  local pairs = {
    { "\195\161", "a" }, { "\195\160", "a" }, { "\195\162", "a" }, { "\195\163", "a" }, { "\195\164", "a" }, { "\195\165", "a" },
    { "\195\169", "e" }, { "\195\168", "e" }, { "\195\170", "e" }, { "\195\171", "e" },
    { "\195\173", "i" }, { "\195\174", "i" }, { "\195\175", "i" },
    { "\195\179", "o" }, { "\195\178", "o" }, { "\195\180", "o" }, { "\195\181", "o" }, { "\195\182", "o" },
    { "\195\186", "u" }, { "\195\187", "u" }, { "\195\188", "u" },
    { "\195\167", "c" }, { "\195\177", "n" },
    { "\195\129", "A" }, { "\195\130", "A" }, { "\195\131", "A" }, { "\195\132", "A" }, { "\195\133", "A" },
    { "\195\137", "E" }, { "\195\138", "E" }, { "\195\139", "E" },
    { "\195\141", "I" }, { "\195\142", "I" },
    { "\195\147", "O" }, { "\195\148", "O" }, { "\195\149", "O" },
    { "\195\154", "U" }, { "\195\155", "U" },
    { "\195\135", "C" }, { "\195\145", "N" },
  }
  for _, p in ipairs(pairs) do
    r = r:gsub(p[1], p[2])
  end
  -- em dash / en dash -> hyphen
  r = r:gsub("\226\128\148", "-")
  r = r:gsub("\226\128\150", "-")
  return r
end

--- @param desc string|nil
--- @return number|nil
local function parseRequiredLevelFromDescription(desc)
  if not desc or desc == "" then
    return nil
  end
  local patterns = {
    "[Ll]evel%s+of%s+(%d+)%s+or%s+higher",
    "of%s+level%s+(%d+)%s+or%s+higher",
    "level%s+(%d+)%s+or%s+higher",
    "[Ll]evel%s*:?%s*(%d+)",
    "[Nn]ivel%s*:?%s*(%d+)",
    "[Rr]equired%s+[Ll]evel%s*:?%s*(%d+)",
    "(%d+)%s*[Ll]evel",
  }
  for _, p in ipairs(patterns) do
    local n = desc:match(p)
    if n then
      return tonumber(n)
    end
  end
  return nil
end

--- @param desc string|nil
--- @return number|nil
local function parseMagicLevelFromDescription(desc)
  if not desc or desc == "" then
    return nil
  end
  local m = desc:match("[Mm]agic%s+[Ll]evel%s*:?%s*(%d+)")
  if m then
    return tonumber(m)
  end
  return nil
end

--- Cap de level para itens EXP (fragmentos PT/EN na descricao).
--- @param desc string|nil
--- @return number|nil
local function parseMaxLevelCapFromDescription(desc)
  if not desc or desc == "" then
    return nil
  end
  local patterns = {
    "menor%s+que%s+(%d+)",
    "lower%s+than%s+(%d+)",
    "below%s+(%d+)",
    "max%s*[Ll]evel%s*:?%s*(%d+)",
  }
  for _, p in ipairs(patterns) do
    local n = desc:match(p)
    if n then
      return tonumber(n)
    end
  end
  return nil
end

--- @param desc string|nil
--- @return string
local function extractVocationLine(desc)
  if not desc or desc == "" then
    return ""
  end
  local m = desc:match("[Cc]an only be used by ([^%.%:\n]+)")
  if m then
    return toAscii(m:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  m = desc:match("[Ss]omente%s+para%s+([^%.%:\n]+)")
  if m then
    return toAscii(m:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  m = desc:match("[Aa]penas%s+([^%.%:\n]+)")
  if m then
    return toAscii(m:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  return ""
end

--- @param vocationIds number[]
--- @return string
local function formatVocationList(vocationIds)
  if not vocationIds or #vocationIds == 0 then
    return ""
  end
  local seen = {}
  local names = {}
  for _, vid in ipairs(vocationIds) do
    if not seen[vid] then
      seen[vid] = true
      names[#names + 1] = VOCACAO_NOME[vid] or ("id " .. tostring(vid))
    end
  end
  table.sort(names)
  return table.concat(names, ", ")
end

--- @param spell table|nil
--- @param runeMeta table|nil
--- @return number[]
local function resolveVocationIds(spell, runeMeta)
  if runeMeta and runeMeta.vocations then
    return runeMeta.vocations
  end
  if spell and spell.vocations then
    return spell.vocations
  end
  return {}
end

--- @param nameLower string
--- @return boolean
local function isExpBoostName(nameLower)
  if nameLower:find("xp boost", 1, true) or nameLower:find("experience boost", 1, true) then
    return true
  end
  if nameLower:find("boost", 1, true) and (nameLower:find("exp", 1, true) or nameLower:find("experi", 1, true)) then
    return true
  end
  return false
end

--- @param item Item|nil
--- @param thingType ThingType
--- @param displayName string|nil
--- @param itemId number|nil
--- @return string|nil  'potion'|'rune'|'exp_boost'
local function classify(item, thingType, displayName, itemId)
  if not thingType then
    return nil
  end

  if itemId and EXP_BOOST_ITEM_PCT[itemId] then
    return "exp_boost"
  end

  local displayLower = type(displayName) == "string" and displayName:lower() or ""
  local typeName = thingType:getName() or ""
  local typeLower = typeName:lower()

  if isExpBoostName(displayLower) or isExpBoostName(typeLower) then
    return "exp_boost"
  end
  if displayLower:find("rune", 1, true) then
    return "rune"
  end
  if displayLower:find("potion", 1, true) then
    return "potion"
  end

  if thingType:isFluidContainer() and not thingType:isSplash() then
    return "potion"
  end

  if thingType:isChargeable() and thingType:isStackable() and not thingType:isFluidContainer() then
    return "rune"
  end

  return nil
end

local function formatDurationSeconds(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec <= 0 then
    return nil
  end
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then
    if m == 0 then
      return string.format("%dh", h)
    end
    return string.format("%dh %dm", h, m)
  end
  if m > 0 then
    if s == 0 then
      return string.format("%dm", m)
    end
    return string.format("%dm %ds", m, s)
  end
  return string.format("%ds", s)
end

--- @param name string
--- @return number|nil percent
local function parsePercentFromName(name)
  if not name then
    return nil
  end
  local p = name:match("(%d+)%%")
  return tonumber(p)
end

--- @param name string
--- @return string|nil
local function parseDurationHintFromName(name)
  if not name then
    return nil
  end
  local nl = name:lower()
  local h = nl:match("(%d+)%s*h")
  if h then
    return string.format("%sh", h)
  end
  local m = nl:match("(%d+)%s*min")
  if m then
    return string.format("%s min", m)
  end
  return nil
end

--- @param itemId number
--- @return table|nil, table|nil  spell, runeMeta
local function getRuneSpellFromItem(itemId)
  if not SpellRunesData then
    return nil, nil
  end
  local runeMeta = SpellRunesData[itemId]
  if not runeMeta then
    return nil, nil
  end
  if not Spells or not Spells.getSpellDataById then
    return nil, runeMeta
  end
  local spell = Spells.getSpellDataById(runeMeta.id)
  return spell, runeMeta
end

--- Casa o nome da poção (lista do NPC / .dat) com magias instantaneas em SpellInfo (ex.: "magic shield potion" -> Magic Shield).
--- @param nameLower string
--- @return table|nil spell
local function findInstantSpellForPotionName(nameLower)
  if not nameLower or nameLower == "" then
    return nil
  end
  nameLower = nameLower:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if not SpellInfo or not SpellInfo["Default"] then
    return nil
  end
  local bestSpell, bestLen = nil, 0
  for spellName, spell in pairs(SpellInfo["Default"]) do
    if spell.type == "Instant" and spell.vocations and #spell.vocations > 0 then
      local sn = spellName:lower()
      if nameLower:find(sn, 1, true) and #sn > bestLen then
        bestSpell, bestLen = spell, #sn
      end
    end
  end
  return bestSpell
end

--- Altura do painel: encaixa ao conteudo. O root nao pode ficar alto antes de medir: getChildrenRect()
--- no cliente forca altura >= padding interno do pai, entao um tooltip longo anterior deixa o painel enorme.
local function fitTooltipRoot()
  if not root or root:isDestroyed() then
    return
  end
  local function rw(id)
    if root.recursiveGetChildById then
      return root:recursiveGetChildById(id)
    end
    return root:getChildById(id)
  end

  -- Colapsa o pai para o layout dos filhos nao herdar area "vazia" gigante.
  if root.setHeight then
    root:setHeight(1)
  end

  local nameW = rw("npcTradeTooltipName")
  if nameW and nameW:isVisible() and nameW.resizeToText then
    nameW:resizeToText()
  end
  local lvlW = rw("npcTradeTooltipLevel")
  if lvlW and lvlW:isVisible() and lvlW.resizeToText then
    lvlW:resizeToText()
  end
  local bodyW = rw("npcTradeTooltipBody")
  if bodyW and bodyW.resizeToText then
    bodyW:resizeToText()
  end
  if root.updateLayout then
    pcall(function()
      root:updateLayout()
    end)
  end
  -- Segundo passe: o body as vezes so encolhe depois do layout com pai colapsado.
  if bodyW and bodyW.resizeToText then
    bodyW:resizeToText()
  end
  if lvlW and lvlW:isVisible() and lvlW.resizeToText then
    lvlW:resizeToText()
  end
  if nameW and nameW:isVisible() and nameW.resizeToText then
    nameW:resizeToText()
  end
  if root.updateLayout then
    pcall(function()
      root:updateLayout()
    end)
  end

  local rootY = root:getY() or 0

  local function bottomOfWidget(w)
    if not w or w:isDestroyed() or not w:isVisible() then
      return 0
    end
    if w.getRect then
      local r = w:getRect()
      if r and r.height then
        local relY = (r.y or 0) - rootY
        return relY + (r.height or 0)
      end
    end
    local relY = (w:getY() or 0) - rootY
    return relY + (w:getHeight() or 0)
  end

  local function bottomOf(id)
    return bottomOfWidget(rw(id))
  end

  -- O Label do body pode reportar altura maior que o texto (layout com pai alto).
  -- A altura do painel deve seguir o ultimo filho visivel: icone + margem inferior.
  local iconBottomMargin = 4
  local bottomPad = 2

  local iconB = rw("npcTradeTooltipIconBorder")
  local maxBottom = bottomOfWidget(iconB)
  if maxBottom <= 0 then
    for _, wid in ipairs({
      "npcTradeTooltipName",
      "npcTradeTooltipVocation",
      "npcTradeTooltipLevel",
      "npcTradeTooltipSep",
      "npcTradeTooltipBody",
      "npcTradeTooltipIconBorder",
    }) do
      maxBottom = math.max(maxBottom, bottomOf(wid))
    end
  end

  maxBottom = maxBottom + iconBottomMargin + bottomPad
  if root.setHeight and maxBottom > 0 then
    root:setHeight(math.max(maxBottom, 24))
  end
  if root.updateLayout then
    pcall(function()
      root:updateLayout()
    end)
  end
end

local function positionNearMouse()
  if not root or root:isDestroyed() then
    return
  end
  local mousePos = g_window.getMousePosition()
  local sz = root:getSize()
  local ws = g_window.getSize()
  local x = mousePos.x + 14
  local y = mousePos.y + 8
  if x + sz.width > ws.width then
    x = mousePos.x - sz.width - 8
  end
  if y + sz.height > ws.height then
    y = mousePos.y - sz.height - 8
  end
  root:setPosition({ x = x, y = y })
end

--- @param hoverData Item|table
--- @return boolean
local function fillAndShow(hoverData)
  if not root or root:isDestroyed() or not hoverData then
    return false
  end

  local item = hoverData
  local displayName = nil
  local description = nil

  if type(hoverData) == "table" and hoverData.item then
    item = hoverData.item
    displayName = hoverData.name
    description = hoverData.description
  end
  if not item or not item.getId then
    return false
  end

  local id = item:getId()
  local tt = g_things.getThingType(id, ThingCategoryItem)
  if not tt then
    return false
  end

  local kind = classify(item, tt, displayName, id)
  if not kind then
    return false
  end

  local function rw(id)
    if root.recursiveGetChildById then
      return root:recursiveGetChildById(id)
    end
    return root:getChildById(id)
  end
  local nameW = rw("npcTradeTooltipName")
  local vocW = rw("npcTradeTooltipVocation")
  local lvlW = rw("npcTradeTooltipLevel")
  local bodyW = rw("npcTradeTooltipBody")
  local iconW = rw("npcTradeTooltipIcon")
  if not nameW or not vocW or not lvlW or not bodyW or not iconW then
    return false
  end

  local dispName = (displayName and displayName ~= "") and displayName or (tt:getName() or "")
  dispName = toAscii(dispName)
  local desc = (description and description ~= "") and description or (tt:getDescription() or "")
  local descAscii = toAscii(desc)

  local p = g_game.getLocalPlayer()
  local pLevel = p and p:getLevel() or 0

  nameW:setText(dispName)
  vocW:setVisible(false)
  if vocW.setHeight then
    vocW:setHeight(0)
  end

  local bodyLines = {}

  if kind == "exp_boost" then
    -- Tabelas alinhadas ao on look / servidor.
    local pct = EXP_BOOST_ITEM_PCT[id] or parsePercentFromName(dispName)
    local maxCap = nil
    if pct then
      maxCap = LEVEL_CAP_BY_PCT[pct]
    end
    if not maxCap then
      maxCap = parseMaxLevelCapFromDescription(desc)
    end

    lvlW:setVisible(true)
    if maxCap then
      lvlW:setText(string.format("Nivel maximo: abaixo de %d (voce: %d)", maxCap, pLevel))
      if pLevel >= maxCap then
        lvlW:setColor("#ff3333")
      else
        lvlW:setColor("#ffffff")
      end
    else
      lvlW:setText(string.format("Nivel maximo: nenhum (voce: %d)", pLevel))
      lvlW:setColor("#cccccc")
    end

    local effectSec, cdSec = getExpBoostEffectAndCooldownSec(id)
    local durStr = nil
    if item.getDurationTime then
      local ds = item:getDurationTime() or 0
      if ds > 0 then
        durStr = formatDurationSeconds(ds)
      end
    end
    if not durStr then
      durStr = formatDurationSeconds(effectSec)
    end
    if durStr then
      bodyLines[#bodyLines + 1] = "Duracao do efeito: " .. durStr
    end

    bodyLines[#bodyLines + 1] = string.format(
      "Cooldown (entre usos): %s",
      formatDurationSeconds(cdSec) or (tostring(math.floor(cdSec / 3600)) .. "h")
    )

    if pct then
      bodyLines[#bodyLines + 1] = string.format("Bonus: +%d%% EXP", pct)
    else
      bodyLines[#bodyLines + 1] = "Bonus: (veja o nome do item)"
    end

    if pct and EXP_PCT_RESTRICTED_BY_RESETS[pct] then
      bodyLines[#bodyLines + 1] = string.format(
        "Reset: nao use com %d+ resets.",
        EXP_BOOST_MIN_RESETS_FOR_RESTRICTION
      )
    end

    bodyLines[#bodyLines + 1] =
      "Obs: aumenta EXP ao matar monstros. Quando houver cap, seu nivel precisa ficar abaixo do limite."
  else
    local reqLevel = parseRequiredLevelFromDescription(desc)
    local vocFromDesc = extractVocationLine(desc)

    if kind == "rune" then
      local spell, runeMeta = getRuneSpellFromItem(id)
      if spell then
        reqLevel = spell.level
        local vids = resolveVocationIds(spell, runeMeta)
        local vlist = formatVocationList(vids)
        bodyLines[#bodyLines + 1] = string.format("Nivel de magia: %d", spell.maglevel or 0)
        if vlist ~= "" then
          bodyLines[#bodyLines + 1] = "Vocacao: " .. vlist
        else
          bodyLines[#bodyLines + 1] = "Vocacao: any"
        end
      else
        local reqMagFallback = parseMagicLevelFromDescription(desc)
        bodyLines[#bodyLines + 1] = string.format("Nivel de magia: %s", reqMagFallback and tostring(reqMagFallback) or "-")
        if vocFromDesc ~= "" then
          bodyLines[#bodyLines + 1] = "Vocacao: " .. vocFromDesc
        else
          bodyLines[#bodyLines + 1] = "Vocacao: (sem dados da runa)"
        end
      end

      if reqLevel and reqLevel > 0 then
        lvlW:setVisible(true)
        lvlW:setText(string.format("Nivel: %d", reqLevel))
        if pLevel < reqLevel then
          lvlW:setColor("#ff3333")
        else
          lvlW:setColor("#ffffff")
        end
      else
        lvlW:setVisible(true)
        lvlW:setText("Nivel: -")
        lvlW:setColor("#cccccc")
      end
    else
      -- potion: nivel + vocacao; 63202-63206 = pocoes especiais.
      if CUSTOM_POTION_IDS[id] then
        lvlW:setVisible(true)
        lvlW:setText("Nivel: -")
        lvlW:setColor("#aaaaaa")
        bodyLines[#bodyLines + 1] = string.format(
          "Duracao do efeito: %s",
          formatDurationSeconds(CUSTOM_POTION_BUFF_DURATION_SEC) or "30 min"
        )
        local fx = CUSTOM_POTION_EFFECT_DESC[id]
        if fx then
          bodyLines[#bodyLines + 1] = fx
        end
        bodyLines[#bodyLines + 1] = string.format(
          "Cooldown: %s",
          formatDurationSeconds(CUSTOM_POTION_SHARED_COOLDOWN_SEC) or "2h"
        )
        bodyLines[#bodyLines + 1] = "Vocation: all"
      else
        local nameForSpell = (displayName and displayName ~= "") and displayName or (tt:getName() or "")
        local canaryP = resolveCanaryFlaskPotion(id, tt:getName(), displayName)
        if canaryP then
          reqLevel = canaryP.level
          if canaryP.vocations and #canaryP.vocations > 0 then
            vocFromDesc = formatVocationList(canaryP.vocations)
          else
            vocFromDesc = "all"
          end
        else
          local spellPotion = findInstantSpellForPotionName(nameForSpell:lower())
          if not spellPotion and tt:getName() then
            spellPotion = findInstantSpellForPotionName((tt:getName() or ""):lower())
          end
          if spellPotion then
            reqLevel = spellPotion.level
            vocFromDesc = formatVocationList(spellPotion.vocations)
          else
            if not reqLevel then
              reqLevel = parseRequiredLevelFromDescription(desc)
            end
            if not reqLevel then
              reqLevel = parseRequiredLevelFromDescription(descAscii)
            end
            if vocFromDesc == "" then
              vocFromDesc = extractVocationLine(desc)
            end
            if vocFromDesc == "" then
              vocFromDesc = extractVocationLine(descAscii)
            end
          end
        end

        if vocFromDesc ~= "" then
          bodyLines[#bodyLines + 1] = "Vocacao: " .. vocFromDesc
        else
          bodyLines[#bodyLines + 1] = "Vocacao: (sem dados na descricao)"
        end

        if reqLevel and reqLevel > 0 then
          lvlW:setVisible(true)
          lvlW:setText(string.format("Nivel: %d", reqLevel))
          if pLevel < reqLevel then
            lvlW:setColor("#ff3333")
          else
            lvlW:setColor("#ffffff")
          end
        else
          lvlW:setVisible(true)
          lvlW:setText("Nivel: -")
          lvlW:setColor("#cccccc")
        end
      end
    end
  end

  bodyW:setText(table.concat(bodyLines, "\n"))

  if iconW then
    iconW:setItemId(id)
    iconW:setItemCount(math.max(1, item:getCount() or 1))
  end

  fitTooltipRoot()
  scheduleEvent(function()
    if root and not root:isDestroyed() then
      fitTooltipRoot()
    end
  end, 1)
  scheduleEvent(function()
    if root and not root:isDestroyed() then
      fitTooltipRoot()
      positionNearMouse()
    end
  end, 10)

  root:setVisible(true)
  root:raise()
  positionNearMouse()
  return true
end

local NpcTradeTooltip = {}

function NpcTradeTooltip.init()
  if root and not root:isDestroyed() then
    return
  end
  root = g_ui.loadUI("/game_npctrader/npc_trade_tooltip", g_ui.getRootWidget())
  if not root then
    root = g_ui.loadUI("npc_trade_tooltip", g_ui.getRootWidget())
  end
  if not root then
    return
  end
  root:setVisible(false)
end

function NpcTradeTooltip.terminate()
  cancelDelay()
  if root and not root:isDestroyed() then
    root:destroy()
  end
  root = nil
end

--- hoverData: Item OU { item = Item, name = string?, description = string? }
function NpcTradeTooltip.onHoverItem(hoverData, hovered)
  if not hovered then
    hidePanel()
    return
  end
  if not hoverData then
    return
  end
  cancelDelay()
  local ms = controllerNpcTrader.NPC_TRADE_TOOLTIP_HOVER_DELAY or 380
  delayEvent = scheduleEvent(function()
    delayEvent = nil
    fillAndShow(hoverData)
  end, ms)
end

NpcTradeTooltip.onGameEnd = function()
  hidePanel()
end

if modules and modules.game_npctrader then
  modules.game_npctrader.NpcTradeTooltip = NpcTradeTooltip
end
