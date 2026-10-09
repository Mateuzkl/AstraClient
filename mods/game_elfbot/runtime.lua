local runtime, tickEvent, launcher, reconnectEvent, session
local reconnectOnce=false
local terminating=false
local bindings={}
local storage={elfbot={}}
local slot=1
local saveEvent
local lastSaved
local settingsInvalid=false
local pendingImportEvent
local readinessEvent
local function worldReady()
  local player=g_game.getLocalPlayer()
  local p=player and player:getPosition()
  return type(p)=='table' and type(p.x)=='number' and type(p.y)=='number' and type(p.z)=='number' and p.x>=0 and p.x<65535 and p.y>=0 and p.y<65535 and p.z>=0 and p.z<=15
end
local function report(kind,text) if kind=='error' or kind=='warn' then g_logger.warning('[ElfBot] '..text) end end
local function encodeSettings()
  local encoded=json.encode(storage,2)
  assert(type(encoded)=='string' and #encoded<=ElfBotSettingsImport.maxBytes,'ElfBot settings exceed 8 MB')
  return encoded
end
local function flushSettings()
  removeEvent(saveEvent);saveEvent=nil
  if storage.elfbot.awaitingLoad then return true end
  local ok,err=pcall(function()
    local encoded=encodeSettings()
    if encoded==lastSaved then return end
    if not g_resources.directoryExists('/elfbot') then assert(g_resources.makeDir('/elfbot'),'Cannot create ElfBot settings directory') end
    assert(g_resources.writeFileContents(settingsInvalid and '/elfbot/settings.recovered.json' or '/elfbot/settings.json',encoded)~=false,'Cannot save ElfBot settings')
    lastSaved=encoded
  end)
  if not ok then report('error','Settings were not saved: '..tostring(err)) end
  return ok
end
function saveSettings()
  if storage.elfbot.awaitingLoad then return end
  removeEvent(saveEvent)
  saveEvent=scheduleEvent(function() saveEvent=nil;flushSettings() end,500)
end
local function dispatch(name,...)
  if not runtime or not runtime.callbacks[name] then return false end
  if not isEnabled() and not runtime.ui.isVisible() then return false end
  runtime.context.now=g_clock.millis();runtime.context.time=runtime.context.now
  local ok,result=pcall(runtime.callbacks[name],...)
  if not ok then runtime.context.ElfBot.status=tostring(result);report('error',tostring(result));return false end
  return result
end
local function stop()
  removeEvent(reconnectEvent);reconnectEvent=nil
  removeEvent(pendingImportEvent);pendingImportEvent=nil
  removeEvent(readinessEvent);readinessEvent=nil
  removeEvent(tickEvent);tickEvent=nil
  flushSettings()
  if runtime then
    if not g_game.isOnline() then pcall(runtime.ui.disconnected) end
    local old=runtime;runtime=nil
    local ok,err=pcall(old.dispose);if not ok then report('error','Cleanup failed: '..tostring(err)) end
  end
  if launcher then launcher:setOn(false) end
  if not terminating and not g_game.isOnline() and (reconnectOnce or isEnabled() and storage.elfbot.extras and storage.elfbot.extras.reconnect) then
    reconnectOnce=false;removeEvent(reconnectEvent);reconnectEvent=scheduleEvent(function() if not g_game.isOnline() then modules.client_entergame.CharacterList.doLogin() end end,math.max(3,storage.elfbot.extras.reconnectDelay or 5)*1000)
  end
  if not g_game.isOnline() then session=nil end
end
local function pulse()
  tickEvent=nil
  if not runtime then return end
  if not worldReady() then tickEvent=scheduleEvent(pulse,100);return end
  local ok,err=pcall(runtime.script)
  if not ok then
    local e=runtime.context.ElfBot;e.status=tostring(err);runtime.context.CaveBot.setOff();runtime.context.TargetBot.setOff();e.jobs={};e.paused=true;report('error',tostring(err))
  end
  if launcher then launcher:setOn(runtime.ui.isVisible()) end
  if isEnabled() or runtime.ui.isVisible() then tickEvent=scheduleEvent(pulse,isEnabled() and 50 or 500) end
end
local function wake()
  removeEvent(tickEvent);tickEvent=nil
  pulse()
end
local function settingsNotice(text)
  if runtime then runtime.context.ElfBot.status=text end
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(text)
  end
end
function loadSlot(index)
  index=tonumber(index)
  if not index or index%1~=0 or index<1 or index>5 then return false end
  local path='/elfbot/slot'..index..'.json'
  if not g_resources.fileExists(path) then
    settingsNotice('Slot '..index..' is empty. Click Save to create it.')
    return false
  end
  local ok,decoded=pcall(function()
    local source=g_resources.readFileContents(path)
    assert(type(source)=='string' and #source<=ElfBotSettingsImport.maxBytes,'ElfBot slot exceeds 8 MB')
    return json.decode(source)
  end)
  if not ok or type(decoded)~='table' or type(decoded.elfbot)~='table' then
    settingsNotice('Unable to load slot '..index..': invalid settings')
    return false
  end
  local previous,previousSlot=storage,slot
  stop();storage=decoded;storage.elfbot.botEnabled=false;storage.elfbot.lastImport=nil;storage.elfbot.selectedImportPath=nil;storage.elfbot.awaitingLoad=nil;slot=index
  if start() then runtime.ui.show();wake();return true end
  storage=previous;slot=previousSlot
  if start() then runtime.ui.show();wake();settingsNotice('Unable to load slot '..index..'; previous settings restored') end
  return false
end
-- Build and validate a replacement before stopping the current bot.
function previewElfFile(path)
  assert(runtime,'Open ElfBot while logged in first')
  local source=ElfBotSettingsImport.read(path,g_resources)
  local converted,result=ElfBotSettingsImport.translate(source,runtime.context.ElfBot.compile,path)
  if result.format:find('Original NG binary',1,true) then result.originalBinary=source;result.converted=converted end
  return result
end
local function queueImport(result,name)
  assert(runtime,'Open ElfBot while logged in first')
  removeEvent(pendingImportEvent)
  -- Command-triggered loads run after the current script/tick stack unwinds.
  pendingImportEvent=scheduleEvent(function()
    pendingImportEvent=nil;if not runtime then return end
    local previous=storage
    local nextData=ElfBotSettingsImport.apply(storage.elfbot,result)
    nextData.botEnabled=false;nextData.awaitingLoad=nil;nextData.lastImport=nil;nextData.selectedImportPath=nil;nextData.slot=slot
    local ok,err=pcall(function()
      if not g_resources.directoryExists('/elfbot') then g_resources.makeDir('/elfbot') end
      assert(g_resources.writeFileContents('/elfbot/before-import.json',json.encode(previous,2))~=false,'Cannot back up existing settings')
      if result.originalBinary then
        assert(g_resources.writeFileContents('/elfbot/original-last.bin',result.originalBinary)~=false,'Cannot preserve original binary')
        assert(g_resources.writeFileContents('/elfbot/translated-last.json',json.encode(result.converted,2))~=false,'Cannot save translated settings')
      end
    end)
    if not ok then settingsNotice('Import stopped: '..tostring(err));return end
    stop();storage={elfbot=nextData}
    if start() then
      runtime.ui.show();wake();if result.format:find('partial',1,true) then report('warn',table.concat(result.warnings,' | ')) end;settingsNotice((result.format:find('partial',1,true) and 'Partially imported ' or 'Loaded ')..name..'. '..ElfBotSettingsImport.summary(result));saveSettings()
    else
      storage=previous
      if start() then runtime.ui.show();wake();settingsNotice('Import failed; previous settings restored') end
    end
  end,1)
  return true
end
function loadElfFile(path)
  local result=previewElfFile(path);return queueImport(result,path)
end
function loadElfText(text)
  assert(runtime,'Open ElfBot while logged in first')
  return queueImport(ElfBotSettingsImport.parse(text,runtime.context.ElfBot.compile),'Pasted ElfBot script')
end
function saveSlot(index)
  index=tonumber(index)
  if not index or index%1~=0 or index<1 or index>5 then return false end
  storage.elfbot.awaitingLoad=nil
  local ok,err=pcall(function() assert(g_resources.writeFileContents('/elfbot/slot'..index..'.json',encodeSettings())~=false,'Cannot save ElfBot slot') end)
  if not ok then settingsNotice('Slot was not saved: '..tostring(err));return false end
  flushSettings();slot=index
  if runtime then runtime.context.ElfBot.status='Saved settings slot '..index end
  return true
end
function start()
  if runtime then return true end
  if not g_game.isOnline() then return false end
  if not worldReady() then
    removeEvent(readinessEvent);readinessEvent=scheduleEvent(function() readinessEvent=nil;start() end,100)
    return false
  end
  removeEvent(readinessEvent);readinessEvent=nil
  removeEvent(reconnectEvent);reconnectEvent=nil
  local prepared
  local ok,result=pcall(modules.game_bot.executeBot,'ElfBot',storage,nil,report,saveSettings,function() stop();start() end,{}, nil, {
    standalone=true,
    prepare=function(c)
      prepared=c
      if not session or session.name~=c.name() then session=ElfBotSession.new(c.now,c.name()) end
      c.elfSession=session
      c.UI.createWindow=function(style)
        local window=g_ui.createWidget(style,g_ui.getRootWidget());window.elfWidget=true;return window
      end
      c.requestElfReconnect=function() reconnectOnce=true;g_game.safeLogout() end
      c.saveElfSlot=saveSlot;c.loadElfSlot=loadSlot;c.currentElfSlot=function() return slot end
      c.setElfEnabled=setEnabled;c.isElfEnabled=isEnabled
      c.previewElfFile=previewElfFile;c.loadElfFile=loadElfFile;c.loadElfText=loadElfText
      prepareStandaloneElfBot(c)
    end,
    attach=attachElfBot
  })
  if not ok then
    if prepared then
      prepared._disposed=true;prepared.updateTileCallbacks()
      local e=prepared.ElfBot
      if e and e.disposeInterface then pcall(e.disposeInterface) end
      if e and e.disposeControllers then pcall(e.disposeControllers)
      elseif prepared.CaveBot and prepared.CaveBot.actionList then prepared.CaveBot.actionList:destroy() end
      prepared.mainTab:destroy()
    end
    report('error','Unable to start: '..tostring(result));return false
  end
  runtime=result
  if modules.game_bot.updateElfBotControls then modules.game_bot.updateElfBotControls() end
  pulse();return true
end
function isEnabled() return storage.elfbot.botEnabled~=false end
function setEnabled(value)
  value=value==true
  local changed=isEnabled()~=value
  if value and modules.game_bot.disableCommunityBot then modules.game_bot.disableCommunityBot() end
  storage.elfbot.botEnabled=value
  if value then start() end
  if runtime then
    local c=runtime.context
    if not value then
      if changed then storage.elfbot.masterResume={cave=c.CaveBot.isOn(),target=c.TargetBot.isOn()} end
      c.ElfBot.paused=true;c.CaveBot.setOff();c.TargetBot.setOff()
    else
      c.ElfBot.reload();local resume=storage.elfbot.masterResume or {}
      if resume.cave then c.CaveBot.setOn() end;if resume.target then c.TargetBot.setOn() end
      storage.elfbot.masterResume=nil
    end
    if value then runtime.ui.show();wake() else runtime.ui.hide() end
    settingsNotice(value and 'ElfBot automation enabled' or 'ElfBot automation disabled')
  end
  saveSettings()
  if not value then stop() end
  if modules.game_bot.updateElfBotControls then modules.game_bot.updateElfBotControls() end
end
function hide() if runtime then runtime.ui.hide() end end
function isRunning() return runtime~=nil end
function isAutomationActive()
  if not runtime then return false end
  local c=runtime.context;if storage.elfbot.botEnabled==false or c.ElfBot.paused then return false end;local data=c.storage.elfbot
  if c.ElfBot.heldTargetUntil and c.now<=c.ElfBot.heldTargetUntil then return true end
  if c.CaveBot.isOn() or c.TargetBot.isOn() or data.aimbot.enabled or (data.healing and data.healing.enabled) then return true end
  for _,job in ipairs(c.ElfBot.jobs) do if job.active and job.row.enabled and not job.failed then return true end end
  return false
end
function toggle()
  if not g_game.isOnline() then return end
  if start() then
    runtime.ui.toggle()
    if launcher then launcher:setOn(runtime.ui.isVisible()) end
    wake()
  end
end
function init()
  terminating=false
  g_ui.importStyle('interface.otui')
  if not g_resources.directoryExists('/elfbot') then g_resources.makeDir('/elfbot') end
  if not g_resources.directoryExists('/elfbot/scripts') then g_resources.makeDir('/elfbot/scripts') end
  -- Each client launch starts empty; saved files remain available through Custom/Load.
  storage={elfbot={awaitingLoad=true,botEnabled=false,hotkeysEnabled=false,shortkeysEnabled=false,
    symbol='',hotkeys={},shortkeys={},persistent='',icons={},iconsEnabled=false,routes={},waypoints={},loot={},
    targeting={monsters={},weights={danger=0,proximity=0,health=0,order=0},stick=false},
    aimbot={enabled=false,command='',enemiesOnly=false,skulledOnly=false,triggers={}},
    hud={enabled=false,general=false,active=false},lists={friends='',subfriends='',enemies='',subenemies='',leaders=''},
    extras={nonPvp=false},healing={enabled=false,hiEnabled=false,loEnabled=false,uhEnabled=false,hpEnabled=false,mpEnabled=false,
      hiSpell='',loSpell='',hiHealth=0,loHealth=0,hiMana=0,loMana=0,uhHealth=0,hpHealth=0,mpMana=0,hpType='',mpType='',delay=0}}}
  launcher=modules.client_topmenu.addRightGameToggleButton('elfbotButton','ElfBot OTC (Ctrl+Shift+F11)','/game_elfbot/launcher',toggle,false,99998)
  launcher:setOn(false)
  local game={onGameStart=function() if isEnabled() then start() end end,onGameEnd=stop}
  local specs={
    {g_game,game},
    {g_ui.getRootWidget(),{
      onKeyDown=function(_,key,mods)
        if determineKeyComboDesc(key,mods)=='Ctrl+Shift+F11' then toggle();return true end
        return dispatch('onKeyDown',key,mods)
      end,
      onKeyUp=function(_,key,mods) return dispatch('onKeyUp',key,mods) end,
      onKeyPress=function(_,key,mods,ticks) return dispatch('onKeyPress',key,mods,ticks) end
    }},
    {Creature,{onAppear='onCreatureAppear',onDisappear='onCreatureDisappear',onPositionChange=function(creature,...)
      if not creature:isLocalPlayer() then return dispatch('onCreaturePositionChange',creature,...) end
    end,onHealthPercentChange='onCreatureHealthPercentChange',onTurn='onTurn',onWalk='onWalk'}},
    {LocalPlayer,{onPositionChange='onCreaturePositionChange',onManaChange='onManaChange',onStatesChange='onStatesChange',onInventoryChange='onInventoryChange'}},
    {Tile,{onAddThing='onAddThing',onRemoveThing='onRemoveThing'}},
    {Container,{onOpen='onContainerOpen',onClose='onContainerClose',onUpdateItem='onContainerUpdateItem',onAddItem='onAddItem',onRemoveItem='onRemoveItem'}},
    {g_map,{onMissle='onMissle',onAnimatedText='onAnimatedText',onStaticText='onStaticText'}}
  }
  for _,name in ipairs({'onTalk','onTextMessage','onLoginAdvice','onUse','onUseWith','onChannelList','onOpenChannel','onCloseChannel','onChannelEvent','onImbuementWindow','onModalDialog','onAttackingCreatureChange','onGameEditText','onSpellCooldown'}) do game[name]=name end
  game.onSpellGroupCooldown='onGroupSpellCooldown'
  for _,spec in ipairs(specs) do
    local handlers={}
    for signal,callback in pairs(spec[2]) do
      if type(callback)=='string' then local name=callback;handlers[signal]=function(...) return dispatch(name,...) end else handlers[signal]=callback end
    end
    connect(spec[1],handlers);bindings[#bindings+1]={spec[1],handlers}
  end
  if isEnabled() then start() end
  if modules.game_bot.updateElfBotControls then modules.game_bot.updateElfBotControls() end
end
function terminate()
  reconnectOnce=false;terminating=true;removeEvent(pendingImportEvent);pendingImportEvent=nil
  stop();session=nil;removeEvent(reconnectEvent);reconnectEvent=nil;for _,binding in ipairs(bindings) do disconnect(binding[1],binding[2]) end;bindings={}
  if launcher then launcher:destroy();launcher=nil end
  lastSaved=nil
end
