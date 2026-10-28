-- Execute the production tracker/protocol Lua with deterministic window and event fixtures.
local root = arg[1] or '.'
local function loadSource(path) assert(loadfile(root .. '/' .. path))() end
local events, created, sent, opcodes = {}, 0, {}, {}
local barWrites = 0
function scheduleEvent(callback)
  local event = {callback = callback}
  events[#events + 1] = event
  return event
end
function removeEvent(event) if event then event.cancelled = true end end
function cycleEvent(callback) return scheduleEvent(callback) end
local function flush()
  local count = 0
  while #events > 0 do
    count = count + 1
    assert(count < 1000, 'tracker work did not settle')
    local event = table.remove(events, 1)
    if not event.cancelled then event.callback() end
  end
end
function signalcall(callback, ...)
  if type(callback) == 'table' then
    for _, entry in ipairs(callback) do entry(...) end
  elseif callback then callback(...) end
end
function connect(object, handlers)
  for name, callback in pairs(handlers) do
    local previous = object[name]
    if not previous then object[name] = callback
    elseif type(previous) == 'table' then previous[#previous + 1] = callback
    else object[name] = {previous, callback} end
  end
end
function disconnect(object, handlers)
  for name, callback in pairs(handlers) do
    if object[name] == callback then object[name] = nil
    elseif type(object[name]) == 'table' then
      for i = #object[name], 1, -1 do
        if object[name][i] == callback then table.remove(object[name], i) end
      end
    end
  end
end
function tr(text, ...) return select('#', ...) > 0 and string.format(text, ...) or text end
function comma_value(value) return tostring(value) end
function short_text(value, length) return value:sub(1, length) end
function string.capitalize(value) return value:gsub('^%l', string.upper) end
function string.empty(value) return not value or value == '' end
consoleln = function() end
g_clock = {millis = function() return 0 end}
g_logger = {warning = function(message) error(message) end}
local monsters = {}
for i = 1, 5 do monsters[i] = {'Creature ' .. i, 100 + i, 0, 0, 0, 0, 0, 0} end
g_things = {getMonsterList = function() return monsters end}

local Node = {}
Node.__index = Node
local function node(parent)
  local result = setmetatable({children = {}, visible = true, parent = parent, id = ''}, Node)
  if parent then parent.children[#parent.children + 1] = result end
  return result
end
function Node:isDestroyed() return self.destroyed == true end
function Node:isVisible() return self.visible and (not self.parent or self.parent:isVisible()) end
function Node:getChildren()
  local copy = {}
  for i, child in ipairs(self.children) do
    if self.aliasChildren then
      -- Native lookups may return a different Lua userdata for the same widget.
      local target = child
      copy[i] = setmetatable({getId = function() return target:getId() end,
                             destroy = function() target:destroy() end}, {__index = target})
    else copy[i] = child end
  end
  return copy
end
function Node:getChildCount() return #self.children end
function Node:getChildById(id)
  for _, child in ipairs(self.children) do if child.id == tostring(id) then return child end end
end
Node.recursiveGetChildById = Node.getChildById
function Node:setId(id) self.id = tostring(id) end
function Node:getId() return self.id end
function Node:setText(value) self.text = value end
function Node:setTooltip(value) self.tooltip = value end
function Node:getTooltip() return self.tooltip end
function Node:setPercent(value) self.percent = value; barWrites = barWrites + 1 end
function Node:setImageSource(value) self.image = value end
function Node:setOutfit(value) self.outfit = value end
function Node:setAnimate() end
function Node:insertLuaCall() self.destroyHooks = (self.destroyHooks or 0) + 1 end
function Node:destroy()
  if self.destroyed then return end
  self:destroyChildren()
  signalcall(self.onDestroy, self)
  self.destroyed = true
  if self.parent then
    for i, child in ipairs(self.parent.children) do
      if child == self then table.remove(self.parent.children, i); break end
    end
    self.parent = nil
  end
end
function Node:destroyChildren() for _, child in ipairs(self:getChildren()) do child:destroy() end end
function Node:moveChildToIndex(child, index)
  for i, entry in ipairs(self.children) do
    if entry == child then table.remove(self.children, i); break end
  end
  table.insert(self.children, math.min(index, #self.children + 1), child)
end
function Node:setVisible(value)
  if self.visible == value then return end
  self.visible = value
  for _, child in ipairs(self.children) do
    signalcall(child.onVisibilityChange, child, child:isVisible())
  end
  signalcall(self.onVisibilityChange, self, self:isVisible())
end
function Node:show() self:setVisible(true) end
function Node:hide() self:setVisible(false) end
Node.open, Node.close = Node.show, Node.hide
function Node:minimize() self.contentsPanel:hide() end
function Node:maximize() self.contentsPanel:show() end
function Node:setParent(parent) self.parent = parent end
function Node:getParent() return self.parent end
function Node:setHeight(height) self.height = height end
function Node:getHeight() return self.height or 150 end
function Node:setup() end
function Node:mergeStyle() end
function Node:getRedirectButton() return node() end
function Node:getExtraButton() return node() end
function Node:getLayout() return {disableUpdates = function() end, enableUpdates = function() end} end
local panel = node()
local function trackerWindow()
  local window = node(panel)
  window.contentsPanel = node(window)
  local scrollbar = node(window); scrollbar:setId('miniwindowScrollBar')
  window.onVisibilityChange = function() window.nativeVisibilityCalls = (window.nativeVisibilityCalls or 0) + 1 end
  return window
end
g_ui = {
  loadUI = trackerWindow,
  createWidget = function(_, parent)
    created = created + 1
    local widget = node(parent)
    widget.creature, widget.bossName, widget.redirect, widget.cooldown = node(widget), node(widget), node(widget), node(widget)
    widget.cooldown.visible = false
    widget.trackerContainer, widget.trackerContainer1, widget.trackerContainer2 = node(widget), node(widget), node(widget)
    widget.trackerContainer.killsBar = node(widget.trackerContainer)
    widget.trackerContainer1.killsBar1, widget.trackerContainer1.countLabel = node(widget.trackerContainer1), node(widget.trackerContainer1)
    widget.trackerContainer2.killsBar2 = node(widget.trackerContainer2)
    return widget
  end,
}
m_interface = {getRightPanel = function() return panel end, addToPanels = function() return false end}
ImbuementTracker = {onReceiveData = function() end, online = function() end, offline = function() end}
local cooldowns = {}
modules = {
  game_cyclopedia = {getCyclopediaMonsterList = function() return monsters end},
  game_analyser = {BossCooldown = {hasCooldown = function(_, race)
    if cooldowns[race] then return monsters[race][1], cooldowns[race] end
    return '', -1
  end}},
  game_sidebuttons = {setButtonVisible = function() end},
}
modules.game_trackers = setmetatable({}, {__index = _G, __newindex = function(_, key, value) _G[key] = value end})
g_game = {isOnline = function() return false end}
g_game.getProtocolGame = function()
  return {send = function(_, message)
    assert(opcodes[0x39] or message.values[1] ~= 0x3F, 'Bestiary request preceded opcode registration')
    assert(opcodes[0x73] or message.values[1] ~= 0xAE, 'Bosstiary request preceded opcode registration')
    sent[#sent + 1] = message.values
  end}
end
ProtocolGame = {
  registerOpcode = function(opcode, callback) opcodes[opcode] = callback end,
  unregisterOpcode = function(opcode) opcodes[opcode] = nil end,
}
OutputMessage = {create = function()
  return {values = {}, addU8 = function(self, value) self.values[#self.values + 1] = value end,
          addU16 = function(self, value) self.values[#self.values + 1] = value end}
end}

loadSource('mods/game_trackers/classes/bestiary_tracker.lua')
loadSource('mods/game_trackers/classes/boss_tracker.lua')
loadSource('mods/game_trackers/game_trackers.lua')
init()
bestiaryTrackerWindow.nativeVisibilityCalls = 0
bossTrackerWindow.nativeVisibilityCalls = 0
BestiaryTracker.initSortFields()
BossTracker.initSortFields()
local function data(...) local list = {}; for _, id in ipairs({...}) do list[#list + 1] = {id, 2, 5, 10, 20} end; return list end
Trackers.onMonsterTrackerData(0, data(1, 2)); flush()
assert(created == 0, 'hidden Bestiary allocated widgets')
moveTracker('bestiaryTracker', panel, 150, false); flush()
assert(bestiaryTrackerWindow.contentsPanel:getChildCount() == 2, 'restored Bestiary stayed empty')
local kept = bestiaryTrackerWindow.contentsPanel:getChildById(2)
local function progress(kills, first, second, third)
  Trackers.onMonsterTrackerData(0, {{1, 2, 5, 10, 20}, {2, kills, first or 5, second or 10, third or 20}})
  flush()
  assert(bestiaryTrackerWindow.contentsPanel:getChildById(2) == kept, 'progress refresh recreated the row')
end
progress(20)
assert(kept.trackerContainer2.killsBar2.percent == 100 and
       kept.trackerContainer.killsBar.image:find('green', 1, true), 'completed Bestiary progress missing')
progress(2)
assert(kept.trackerContainer1.killsBar1.percent == 0 and kept.trackerContainer2.killsBar2.percent == 0,
       'Bestiary kept later bars after lower progress')
for _, bar in ipairs({kept.trackerContainer.killsBar, kept.trackerContainer1.killsBar1, kept.trackerContainer2.killsBar2}) do
  assert(bar.image == '/game_cyclopedia/images/ui/mosnter-bar' and not bar.tooltip:find('fully unlocked', 1, true),
         'Bestiary retained completion image or tooltip')
end
progress(15)
progress(15, 20, 30, 40)
assert(kept.trackerContainer.killsBar.percent == 75 and kept.trackerContainer1.killsBar1.percent == 0 and
       kept.trackerContainer2.killsBar2.percent == 0, 'increased Bestiary thresholds retained old progress')
local oldCreated = created
Trackers.onMonsterTrackerData(0, data(2, 3)); flush()
assert(created == oldCreated + 1 and bestiaryTrackerWindow.contentsPanel:getChildById(2) == kept, 'Bestiary recreated unchanged rows')
assert(not bestiaryTrackerWindow.contentsPanel:getChildById(1), 'Bestiary removal was delayed')
Trackers.onMonsterTrackerData(0, data(2, 4))
local firstBatch = table.remove(events, 1)
assert(firstBatch and not firstBatch.cancelled, 'first snapshot did not schedule a batch')
firstBatch.callback()
local staleBatch = table.remove(events, 1)
assert(staleBatch and not staleBatch.cancelled, 'first snapshot did not schedule its continuation')
Trackers.onMonsterTrackerData(0, data(2, 5))
assert(staleBatch.cancelled, 'pending Bestiary batch was not cancelled')
local beforeStale = barWrites
staleBatch.callback() -- Model an old callback already dequeued when cancellation happened.
assert(barWrites == beforeStale, 'stale Bestiary callback rendered after replacement')
flush()
assert(not bestiaryTrackerWindow.contentsPanel:getChildById(4), 'cancelled batch rendered stale data')
assert(bestiaryTrackerWindow.contentsPanel:getChildById(5), 'latest rapid update was lost')
bestiaryTrackerWindow:close()
oldCreated = created
Trackers.onMonsterTrackerData(0, data(1)); flush()
assert(created == oldCreated, 'closed Bestiary rendered')
bestiaryTrackerWindow:open(); flush()
assert(bestiaryTrackerWindow.contentsPanel:getChildCount() == 1 and bestiaryTrackerWindow.contentsPanel:getChildById(1), 'open did not refresh cached Bestiary')
bestiaryTrackerWindow:minimize()
oldCreated = created
Trackers.onMonsterTrackerData(0, data(3)); flush()
assert(created == oldCreated, 'minimized Bestiary rendered')
bestiaryTrackerWindow:maximize(); flush()
assert(bestiaryTrackerWindow.contentsPanel:getChildById(3), 'maximize did not refresh Bestiary')
assert(bestiaryTrackerWindow.nativeVisibilityCalls > 0, 'native visibility handler was replaced')

loadSource('mods/game_cyclopedia/classes/bosstiary.lua')
local function bosses(...) local list = {}; for _, id in ipairs({...}) do list[#list + 1] = {id, 0, 2, 1} end; return list end
bossTrackerWindow.contentsPanel.aliasChildren = true
Bosstiary.onBosstiaryBaseData({{5, 10, 20}, {5, 10, 20}, {5, 10, 20}}, {})
Bosstiary.onBosstiaryWindowData(bosses(1, 2))
Bosstiary.cancelPendingEvents()
assert(#BossTrackerList == 2, 'tab cancellation discarded Boss Tracker state')
moveTracker('bosstiaryTracker', panel, 150, false)
assert(bossTrackerWindow.contentsPanel:getChildCount() == 2, 'restored Boss Tracker stayed empty')
assert(bossTrackerWindow.nativeVisibilityCalls > 0, 'native Boss visibility handler was replaced')
local keptBoss = bossTrackerWindow.contentsPanel:getChildById('Creature 2')
oldCreated = created
Bosstiary.onBosstiaryWindowData(bosses(2, 3)); Bosstiary.cancelPendingEvents()
assert(created == oldCreated + 1 and bossTrackerWindow.contentsPanel:getChildById('Creature 2') == keptBoss, 'Boss Tracker recreated unchanged rows')
assert(keptBoss.cooldown.destroyHooks == 1, 'Boss Tracker accumulated destroy callbacks')
assert(not bossTrackerWindow.contentsPanel:getChildById('Creature 1'), 'Boss Tracker removal was delayed')
local function refreshBossCooldown(value)
  cooldowns[2] = value
  Bosstiary.onBosstiaryWindowData(bosses(2, 3)); Bosstiary.cancelPendingEvents()
  assert(bossTrackerWindow.contentsPanel:getChildById('Creature 2') == keptBoss, 'cooldown refresh recreated the row')
end
refreshBossCooldown(os.time() + 60)
local activeTimer = assert(keptBoss.cooldown.eventCooldown)
assert(keptBoss.cooldown:isVisible(), 'active boss cooldown is hidden')
activeTimer.callback()
refreshBossCooldown(os.time() - 1)
assert(activeTimer.cancelled and not keptBoss.cooldown.eventCooldown, 'expired replacement retained the old cooldown timer')
assert(keptBoss.cooldown.image == '/images/icons/icon-cooldown-finished', 'expired cooldown state missing')
refreshBossCooldown(os.time() + 120)
local removedTimer = assert(keptBoss.cooldown.eventCooldown)
removedTimer.callback()
refreshBossCooldown(nil)
assert(removedTimer.cancelled and not keptBoss.cooldown.eventCooldown, 'removed boss cooldown retained its timer')
assert(not keptBoss.cooldown:isVisible() and not keptBoss.cooldown:getTooltip(), 'removed boss cooldown remains visible')
bossTrackerWindow:minimize()
oldCreated = created
Bosstiary.onBosstiaryWindowData(bosses(4)); Bosstiary.cancelPendingEvents()
assert(created == oldCreated, 'minimized Boss Tracker rendered')
bossTrackerWindow:maximize()
assert(bossTrackerWindow.contentsPanel:getChildById('Creature 4'), 'maximize did not refresh Boss Tracker')
cooldowns[4] = os.time() + 60
BossTracker.showTrackerData()
local removedBoss = bossTrackerWindow.contentsPanel:getChildById('Creature 4')
local rowTimer = assert(removedBoss.cooldown.eventCooldown)
bossTrackerWindow:close()
Bosstiary.onBosstiaryWindowData(bosses(5)); Bosstiary.cancelPendingEvents()
bossTrackerWindow:open()
assert(bossTrackerWindow.contentsPanel:getChildById('Creature 5'), 'open did not refresh cached Boss Tracker')
assert(removedBoss:isDestroyed() and rowTimer.cancelled and not removedBoss.cooldown.eventCooldown,
       'removed Boss row retained its cooldown timer')
Bosstiary.onBosstiaryWindowData({}); Bosstiary.cancelPendingEvents()
assert(bossTrackerWindow.contentsPanel:getChildCount() == 0, 'empty Boss snapshot did not clear rows')
panel:hide()
oldCreated = created
Trackers.onMonsterTrackerData(0, data(1, 2))
Bosstiary.onBosstiaryWindowData(bosses(1, 2)); Bosstiary.cancelPendingEvents(); flush()
assert(created == oldCreated, 'hidden sidebar allocated tracker rows')
panel:show(); flush()
assert(bestiaryTrackerWindow.contentsPanel:getChildCount() == 2 and
       bossTrackerWindow.contentsPanel:getChildCount() == 2, 'restoring the sidebar did not refresh both trackers')

loadSource('mods/game_cyclopedia/cyclopediaprotocol.lua')
loadSource('mods/game_cyclopedia/bosstiaryprotocol.lua')
initCyclopediaProtocol(); initBosstiaryProtocol()
assert(#sent == 0, 'tracker synchronization ran offline')
g_game.isOnline = function() return true end
signalcall(g_game.onGameStart)
assert(#sent == 2 and sent[1][1] == 0x3F and sent[1][2] == 0 and sent[2][1] == 0xAE, 'login did not request both tracker snapshots exactly once')
signalcall(g_game.onGameEnd)
Bosstiary.reset()
assert(#BestiaryTrackerList == 0 and #BossTrackerList == 0, 'logout retained previous character tracker lists')
signalcall(g_game.onGameStart)
assert(#sent == 4 and sent[3][2] == 0, 'relogin did not resynchronize trackers')
local bestiaryWindow, bossWindow = bestiaryTrackerWindow, bossTrackerWindow
terminateCyclopediaProtocol(); terminateBosstiaryProtocol(); terminate()
flush()
assert(not bestiaryTrackerWindow and not bossTrackerWindow, 'tracker teardown retained windows')
for _, window in ipairs({bestiaryWindow, bossWindow}) do
  assert(window:isDestroyed() and window:getParent() == nil, 'tracker teardown did not destroy and detach its window')
  for _, child in ipairs(panel:getChildren()) do assert(child ~= window, 'destroyed tracker remains attached to sidebar') end
end
print('PASS: tracker progress/cooldown resets, stale callback cancellation, native handlers, teardown, login and row reuse')
