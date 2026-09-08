if not _Helper then _Helper = {} end
_Helper.ParalyzeCure = {}
local api = _Helper.ParalyzeCure
local loadingUI, lastCast, checkEvent = false, 0, nil
local function config()
  local root = _Helper.getHelperConfig and _Helper.getHelperConfig()
  return root and root.paralyzeCure and root.paralyzeCure[1]
end
local function panel()
  if _Helper.getToolsPanelContainer then return _Helper.getToolsPanelContainer() end
  return _Helper.getToolsPanel and _Helper.getToolsPanel()
end

function api.toggle(checked)
  if loadingUI then return end
  local cfg = config(); if not cfg then return end
  if checked and (tonumber(cfg.id) or 0) == 0 then
    modules.game_textmessage.displayFailureMessage(tr('Select a cure spell first!'))
    local root = panel(); local checkbox = root and root:recursiveGetChildById('enableParalyzeCure0')
    if checkbox then loadingUI = true; checkbox:setChecked(false); loadingUI = false end
    return
  end
  cfg.enabled = checked == true
  if _Helper.saveSettings then _Helper.saveSettings() end
end

function api.check()
  if not (_Helper.isHelperAutomaticFunctionsEnabled and _Helper.isHelperAutomaticFunctionsEnabled()) then return end
  local cfg, player = config(), g_game.getLocalPlayer()
  if not cfg or not cfg.enabled or not player or not player:hasState(PlayerStates.Paralyze) then return end
  local spell = _Helper.getSpellDataById and _Helper.getSpellDataById(cfg.id)
  if not spell or not spell.words then return end
  local now = g_clock.millis(); local cooldown = _Helper.getSpellCooldown and _Helper.getSpellCooldown(cfg.id) or 0
  if now < cooldown or now - lastCast < 500 or (spell.mana and player:getMana() < spell.mana) then return end
  if _Helper.safeDoThing then _Helper.safeDoThing(false) end
  g_game.talk(spell.words, true)
  if _Helper.safeDoThing then _Helper.safeDoThing(true) end
  lastCast = now
end

function api.loadToUI()
  local cfg, root = config(), panel(); if not cfg or not root then return end
  loadingUI = true
  local button = root:recursiveGetChildById('paralyzeCureButton0')
  if button and cfg.id ~= 0 then
    local spell = _Helper.getSpellDataById and _Helper.getSpellDataById(cfg.id)
    if spell then _Helper.setSpellIcon(button, spell.id); button:setBorderWidth(1); button:setTooltip('Spell: ' .. (spell.name or spell.words) .. '\nWords: ' .. spell.words) end
  end
  local checkbox = root:recursiveGetChildById('enableParalyzeCure0')
  if checkbox then checkbox:setChecked(cfg.enabled == true) end
  loadingUI = false
  if not checkEvent then checkEvent = cycleEvent(api.check, 250) end
end
function api.removeAction()
  local cfg = config(); if cfg then cfg.id = 0; cfg.enabled = false end
  api.resetButton(); if _Helper.saveSettings then _Helper.saveSettings() end
end
function api.resetButton()
  loadingUI = true
  local root = panel(); local button = root and root:recursiveGetChildById('paralyzeCureButton0')
  if button then button:setImageSource('/images/game/actionbar/actionbarslot'); button:setImageClip('0 0 34 34'); button:setBorderWidth(0); button:setTooltip(tr('Click to select a spell')) end
  local checkbox = root and root:recursiveGetChildById('enableParalyzeCure0')
  if checkbox then checkbox:setChecked(false) end
  loadingUI = false
end

function api.terminate()
  if checkEvent then removeEvent(checkEvent); checkEvent = nil end
end
