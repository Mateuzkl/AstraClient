-- Production Lua paths with a deterministic client API double; no server or graphics.
local function read(path)
  local file = assert(io.open(path, 'rb'))
  local text = file:read('*a');file:close();return text
end
local function loadProduction(path, env)
  local chunk = assert(loadfile(path));setfenv(chunk, env);chunk()
end
local function count(values)
  local n=0;for _ in pairs(values) do n=n+1 end;return n
end
local function equal(actual, expected, message)
  assert(actual==expected, (message or 'value')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local scripts={'language','session','history','icon_import','settings_import','telemetry','legacy','engine','autonomous','original_dialogs','hud','interface','runtime'}
for _,name in ipairs(scripts) do assert(loadfile('mods/game_elfbot/'..name..'.lua')) end
local styles='\n'..read('mods/game_elfbot/interface.otui'):gsub('\r\n','\n')
local function styleProperty(style,property)
  local block=styles:match('\n'..style..' <[^\n]+\n(.-)\n\n') or ''
  return ('\n'..block):match('\n  '..property:gsub('([^%w])','%%%1')..': ([^\n]+)')
end

local function fixture()
  local env=setmetatable({}, {__index=_G})
  local now, online, connected, events, widgets, files, warnings=10000,true,{}, {}, {}, {}, {}
  local methods={}
  function methods:destroy()
    assert(not self.destroyed, 'double widget destroy')
    self:destroyChildren();self.destroyed=true;widgets[self]=nil
    if self.parent then
      for i,child in ipairs(self.parent.children) do if child==self then table.remove(self.parent.children,i);break end end
    end
    if self.onDestroy then self.onDestroy(self) end
  end
  function methods:destroyChildren() while #self.children>0 do self.children[#self.children]:destroy() end end
  function methods:isDestroyed() return self.destroyed==true end
  function methods:hide() self.visible=false end
  function methods:show() self.visible=true end
  function methods:isVisible()
    -- Native HiddenState includes hidden ancestors, not just the explicit flag.
    return self.visible and (not self.parent or self.parent:isVisible())
  end
  function methods:raise()
    if self.parent then
      for i,child in ipairs(self.parent.children) do if child==self then table.remove(self.parent.children,i);break end end
      self.parent.children[#self.parent.children+1]=self
    end
  end
  function methods:focus() if self.parent then self.parent.focused=self end end
  function methods:focusChild(child) self.focused=child end
  function methods:getFocusedChild() return self.focused end
  function methods:getParent() return self.parent end
  function methods:getChildren() return self.children end
  function methods:getChildCount() return #self.children end
  function methods:getChildIndex(child) for i,v in ipairs(self.children) do if v==child then return i end end end
  function methods:getChildByIndex(i) return self.children[i] end
  function methods:getStyleName() return self.style end
  function methods:getClassName() return self.style:find('TextEdit') and 'UITextEdit' or 'UIWidget' end
  function methods:getPaddingRect()
    local p,size,padding=self:getPosition(),self:getSize(),self.padding or 0
    return {x=p.x+padding,y=p.y+padding,width=size.width-2*padding,height=size.height-2*padding}
  end
  function methods:getPosition()
    if self.parent and self.fill then
      local p=self.parent:getPaddingRect();return {x=p.x,y=p.y}
    elseif self.parent and self.anchored then
      local p=self.parent:getPaddingRect();return {x=p.x+(self.marginLeft or 0),y=p.y+(self.marginTop or 0)}
    elseif self.parent and self.parent.style=='ElfBotList' then
      local p=self.parent:getPaddingRect();return {x=p.x,y=p.y+(self.parent:getChildIndex(self)-1)*20}
    end
    return self.position or {x=0,y=0}
  end
  function methods:getSize()
    if self.parent and self.fill then local p=self.parent:getPaddingRect();return {width=p.width,height=p.height} end
    return self.size or {width=400,height=300}
  end
  function methods:getText() return self.text or '' end
  function methods:setText(text)
    text=tostring(text);local previous=self:getText();if text==previous then return end
    self.text=text;if self.onTextChange then self.onTextChange(self,text,previous) end
  end
  function methods:setColoredText(parts)
    self.colored=parts;local values={};for i=1,#parts,2 do values[#values+1]=parts[i] end
    self.text=table.concat(values)
  end
  function methods:setChecked(value)
    if self.checked==value then return end;self.checked=value
    if self.onCheckChange then self.onCheckChange(self,value) end
  end
  function methods:isChecked() return self.checked==true end
  function methods:setOn(value) self.on=value end
  function methods:isOn() return self.on==true end
  function methods:setVisible(value) self.visible=value end
  function methods:setPosition(value) self.position=value end
  function methods:setSize(value) self.size=value end
  function methods:setHeight(value) local size=self:getSize();self.size={width=size.width,height=value} end
  function methods:setWidth(value) local size=self:getSize();self.size={width=value,height=size.height} end
  function methods:setId(value) self.id=value end
  function methods:addAnchor() self.anchored=true end
  function methods:setMarginLeft(value) self.marginLeft=value end
  function methods:setPhantom(value) self.phantom=value end
  function methods:setEnabled(value) self.enabled=value end
  function methods:setEditable(value) self.editable=value end
  function methods:setTextWrap(value) self.textWrap=value end
  function methods:setItemId(value) self.itemId=value end
  function methods:setColor(value) self.color=value end
  function methods:setBackgroundColor(value) self.backgroundColor=value end
  function methods:setBorderColor(value) self.borderColor=value end
  function methods:setBorderWidth(value) self.borderWidth=value end
  function methods:setImageSource(value) self.imageSource=value end
  function methods:setClipping(value) self.clipping=value end
  function methods:getTextSize()
    local width,lines=0,0
    local limit=math.max(1,math.floor((self:getSize().width-(self.style=='ElfBotCheck' and 18 or 0))/7))
    for line in (self:getText()..'\n'):gmatch('(.-)\n') do
      width=math.max(width,#line*7);lines=lines+(self.textWrap and math.max(1,math.ceil(#line/limit)) or 1)
    end
    return {width=width,height=lines*14}
  end
  function methods:getMarginTop() return self.marginTop or 0 end
  function methods:getMarginBottom() return self.marginBottom or 0 end
  function methods:setMarginTop(value) self.marginTop=value end
  function methods:setMarginBottom(value) self.marginBottom=value end
  function methods:addOption(value) self.options=self.options or {};self.options[#self.options+1]=value;self.option=self.option or value end
  function methods:setCurrentOption(value)
    if self.option==value then return end;self.option=value
    if self.onOptionChange then self.onOptionChange(self,value) end
  end
  function methods:getCurrentOption() return {text=self.option} end
  function methods:setCurrentIndex(index) self.option=(self.options or {})[index] end
  function methods:clearOptions() self.options={};self.option=nil end
  function methods:setValue(value) self.value=value end
  function methods:getValue() return self.value or 0 end
  for _,name in ipairs({'setTooltip','setVerticalScrollBar','setVirtual','setMinimumAmbientLight','unlockVisibleFloor','setLimitVisibleRange','setup','setMinimum','setMaximum','setStep'}) do
    methods[name]=function() end
  end
  local function widget(style,parent)
    local w=setmetatable({style=style,children={},parent=parent,visible=true,
      size=style=='ElfBotRow' and {width=parent:getSize().width,height=20} or nil,
      padding=tonumber(styleProperty(style,'padding')) or (style=='ElfBotGroup' and 8 or 0),
      fill=styleProperty(style,'anchors.fill')=='parent',
      draggable=styleProperty(style,'draggable')=='true',
      phantom=styleProperty(style,'phantom')=='true' or (style:find('Label') or style=='ElfBotTitle' or style=='ElfBotRow') and styleProperty(style,'phantom')~='false',
      textWrap=styleProperty(style,'text-wrap')=='true'}, {__index=methods})
    if style=='ElfBotCheck' then w.onClick=function(self) self:setChecked(not self:isChecked()) end end
    widgets[w]=true;if parent then parent.children[#parent.children+1]=w end;return w
  end
  local root, map=widget('Root'),widget('Map')
  root:setSize({width=1280,height=800})
  local player={}
  function player:getPosition() return {x=100,y=100,z=7} end
  function player:getName() return 'Tester' end
  function player:getId() return 1 end
  function player:isLocalPlayer() return true end
  function player:isMonster() return false end
  function player:isPlayer() return true end
  function player:isAutoWalking() return false end
  function player:getExperience() return 1000 end
  function player:getLevel() return 10 end
  function player:getLevelPercent() return 40 end
  function player:getMagicLevel() return 5 end
  function player:getMagicLevelPercent() return 60 end
  function player:getSkillLevel(id) return 11+id end
  function player:getSkillLevelPercent() return 70 end
  function player:getStamina() return 2500 end
  function player:getHealthPercent() return 100 end
  function player:getHealth() return 100 end
  function player:getMaxHealth() return 100 end
  function player:getMana() return 100 end
  function player:getMaxMana() return 100 end
  function player:getDirection() return 2 end
  function player:getInventoryItem() end
  function player:getStates() return 0 end
  local spectators={player}
  local tileEnabled, tileChanges, attacked=false,0,nil
  env.G={}
  loadProduction('modules/corelib/table.lua',env)
  loadProduction('modules/corelib/string.lua',env)
  loadProduction('modules/corelib/json.lua',env)
  env.g_clock={millis=function() return now end,realMillis=function() return now end}
  env.g_game={isOnline=function() return online end,getLocalPlayer=function() return player end,
    getClientVersion=function() return 860 end,getPing=function() return 20 end,getContainers=function() return {} end,
    getAttackingCreature=function() return attacked end,
    attack=function(creature) attacked=creature end,cancelAttackAndFollow=function() attacked=nil end,
    stop=function() end,safeLogout=function() online=false end,
    enableTileThingLuaCallback=function(value) tileEnabled=value;tileChanges=tileChanges+1 end,
    setSafeFight=function() end,setFightMode=function() end}
  env.g_ui={createWidget=widget,getRootWidget=function() return root end,importStyle=function() end}
  env.g_map={getSpectators=function() return spectators end,getTile=function() end}
  env.g_app={isMobile=function() return false end,getVersion=function() return 310 end}
  env.g_logger={warning=function(text) warnings[#warnings+1]=text end}
  env.g_window={getClipboardText=function() return '' end,setClipboardText=function() end}
  env.g_platform={};env.g_mouse={};env.g_keyboard={};env.g_things={}
  env.SoundChannels={Bot=1};env.g_sounds={getChannel=function() return {play=function() end,setEnabled=function() end,stop=function() end} end}
  env.g_settings={getNode=function() return {} end,setNode=function() end}
  env.g_http={cancel=function() error('unexpected HTTP socket') end}
  env.HTTP={};env.Directions={};env.PlayerStates={};env.MessageModes={DamageDealt=22,PrivateFrom=4,Say=1}
  env.ChannelEvent={Join=0,Leave=1,Invite=2,Exclude=3};env.tr=function(text) return text end
  env.AnchorLeft=1;env.AnchorTop=2;env.MouseRightButton=2
  env.Creature={};env.LocalPlayer={};env.Tile={};env.Container={}
  env.g_resources={directoryExists=function() return true end,makeDir=function() return true end,
    listDirectoryFiles=function() return {} end,fileExists=function(path) return files[path]~=nil end,
    readFileContents=function(path) return assert(files[path], 'missing fixture file '..path) end,
    writeFileContents=function(path,text) files[path]=text;return true end}
  env.scheduleEvent=function(callback,delay)
    local event={callback=callback,due=now+delay};events[event]=true;return event
  end
  env.removeEvent=function(event) if event then events[event]=nil end end
  env.connect=function(object,handlers)
    local list=connected[object] or {};connected[object]=list;list[#list+1]=handlers
  end
  env.disconnect=function(object,handlers)
    for i,h in ipairs(connected[object] or {}) do if h==handlers then table.remove(connected[object],i);break end end
  end
  env.determineKeyComboDesc=function(key) return key end
  env.retranslateKeyComboDesc=function(key) return key end
  local communityStops, logins=0,0
  env.modules={game_interface={getMapPanel=function() return map end},
    client_options={getOption=function() return 50 end},
    client_topmenu={addRightGameToggleButton=function() return widget('Launcher',root) end},
    client_entergame={CharacterList={doLogin=function() logins=logins+1 end}}}
  local bot=setmetatable({}, {__index=env})
  loadProduction('modules/game_bot/bot.lua',bot)
  loadProduction('modules/game_bot/executor.lua',bot)
  bot.updateElfBotControls=function() end
  bot.disableCommunityBot=function() communityStops=communityStops+1 end
  env.modules.game_bot=bot
  env.modules.game_elfbot=env
  env.dofiles=function(directory)
    local names=directory=='functions' and {'callbacks','config','const','icon','main','map','npc','player','player_inventory','player_conditions','script_loader','server','sound','test','tools','ui','ui_elements','ui_legacy','ui_windows'}
      or {'attacking','basic','healing','looting','tools','war','waypoints'}
    for _,name in ipairs(names) do loadProduction('modules/game_bot/'..directory..'/'..name..'.lua',env) end
  end
  for _,name in ipairs(scripts) do loadProduction('mods/game_elfbot/'..name..'.lua',env) end
  local console=setmetatable({}, {__index=env})
  loadProduction('modules/game_console/console.lua',console);env.modules.game_console=console
  local state={env=env,bot=bot,events=events,widgets=widgets,warnings=warnings,root=root,map=map,player=player,files=files}
  function state.advance(milliseconds)
    now=now+milliseconds
    local due={};for event in pairs(events) do if event.due<=now then due[#due+1]=event end end
    table.sort(due,function(a,b) return a.due<b.due end)
    for _,event in ipairs(due) do if events[event] then events[event]=nil;event.callback() end end
  end
  function state.emit(object,signal,...)
    for _,handlers in ipairs(connected[object] or {}) do if handlers[signal] then handlers[signal](...) end end
  end
  function state.connectionCount()
    local total=0;for _,list in pairs(connected) do total=total+#list end;return total
  end
  function state.tileEnabled() return tileEnabled end
  function state.tileChanges() return tileChanges end
  function state.communityStops() return communityStops end
  function state.logins() return logins end
  function state.setOnline(value) online=value end
  function state.setSpectators(value) spectators=value end
  function state.attack() return attacked end
  function state.now() return now end
  function state.getWidget(text)
    for widget in pairs(widgets) do if widget:getText()==text then return widget end end
  end
  local function contains(rect,p)
    return p.x>=rect.x and p.y>=rect.y and p.x<rect.x+rect.width and p.y<rect.y+rect.height
  end
  local function hit(widget,p)
    if not widget.visible or widget.enabled==false then return nil end
    -- Match UIWidget::propagateOnMouseEvent: only search children inside padding.
    if contains(widget:getPaddingRect(),p) then
      for i=#widget.children,1,-1 do
        local child=widget.children[i];local pos,size=child:getPosition(),child:getSize()
        if contains({x=pos.x,y=pos.y,width=size.width,height=size.height},p) then
          local target=hit(child,p);if target then return target end
        end
      end
    end
    if not widget.phantom then return widget end
  end
  function state.click(widget)
    local p,size=widget:getPosition(),widget:getSize()
    local target=hit(root,{x=p.x+math.floor(size.width/2),y=p.y+math.floor(size.height/2)})
    equal(target,widget,'mouse hit must reach the visible control')
    if target.onMousePress then target.onMousePress(target) end
    if target.onClick then target.onClick(target) end
  end
  function state.hitHud(mouse)
    for _,v in ipairs(root:getChildren()) do if v:getStyleName()=='ElfBotHudLayer' then return hit(v,mouse) end end
  end
  function state.hitRoot(mouse) return hit(root,mouse) end
  function state.failWrites()
    env.g_resources.writeFileContents=function() return false end
  end
  function state.context(storage)
    local executor=bot.executeBot('ElfBot',storage or {elfbot={botEnabled=false}},nil,
      function(_,message) warnings[#warnings+1]=message end,function() end,function() end,{},nil,
      {standalone=true,prepare=function(c)
        c.setElfEnabled=env.setEnabled;c.isElfEnabled=env.isEnabled
        env.prepareStandaloneElfBot(c)
      end,attach=function(c) return {tick=function() c.ElfBot.tick() end,
        keyDown=function(key) return c.ElfBot.key(key,false) end,
        keyPress=function(key) return c.ElfBot.key(key,true) end,
        dispose=function() c.ElfBot.disposeControllers() end} end})
    return executor,executor.context
  end
  return state
end

-- Imports are data-only, disabled until explicitly enabled, and pending imports are cancellable.
do
  local s=fixture();local env=s.env;env.init();env.toggle()
  assert(env.loadElfText('say "exura"'));s.advance(1)
  assert(not env.isEnabled(),'import must not start automation automatically')
  assert(s.files['/elfbot/before-import.json'],'pre-import backup missing')
  env.saveSlot(1);assert(s.files['/elfbot/slot1.json'])
  local data=env.json.decode(s.files['/elfbot/slot1.json']);equal(#data.elfbot.hotkeys,1)
  data.elfbot.botEnabled=true;s.files['/elfbot/slot1.json']=env.json.encode(data)
  assert(env.loadSlot(1));assert(not env.isEnabled(),'saved enable flag must not start automation')
  s.files['/elfbot/slot2.json']=string.rep(' ',env.ElfBotSettingsImport.maxBytes+1)
  assert(not env.loadSlot(2),'oversized slot accepted')
  local writes=count(s.files);assert(env.loadElfText('say "later"'));env.terminate();s.advance(1)
  equal(count(s.events),0,'pending import cancelled');equal(count(s.files),writes,'cancelled import did not write')
  env.init();env.toggle();s.failWrites();assert(not env.saveSlot(1),'write failure was ignored')
  assert(not pcall(env.loadElfText,''),'empty input accepted')
  env.terminate()
end

-- Editing empty slots appends a real row; unchanged focus changes preserve running jobs.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  env.init();env.toggle();local c=latest.context;local e=c.ElfBot
  c.storage.elfbot.hotkeys={{key='F2',script='auto 200 say "test"',enabled=true}}
  e.reload();local reloads,saves=0,0;local reload=e.reload
  e.reload=function(...) reloads=reloads+1;return reload(...) end
  c.saveConfig=function() saves=saves+1 end
  local menu=s.getWidget('ElfBot OTC v.1');local button
  for _,child in ipairs(menu:getChildren()) do if child:getText()=='Hotkeys' then button=child end end
  s.click(assert(button));local panel=s.root:getFocusedChild();local rowsList
  for _,child in ipairs(panel:getChildren()) do if child:getStyleName()=='ElfBotList' then rowsList=child end end
  assert(rowsList);local first=rowsList:getChildren()[1]
  local fields=first:getChildren();local enabled,key,source=fields[1],fields[2],fields[3]
  local job=e.jobs[1];job.active=true;job.nextRun=c.now+500;job.thread=coroutine.create(function() end)
  source.onFocusChange(source,false);key:setText(' F2 ');key.onFocusChange(key,false)
  equal(reloads,0,'unchanged normalized binding must not reload');equal(saves,0,'unchanged row must not save')
  equal(e.jobs[1],job,'unchanged focus preserves job');assert(job.active and job.thread)
  equal(job.nextRun,c.now+500,'unchanged focus preserves timer')
  enabled:setChecked(false);equal(reloads,1);equal(saves,1)
  source.onFocusChange(source,false);equal(reloads,1,'unchanged disabled row must not reload')
  source:setText('auto 200 say "changed"');source.onFocusChange(source,false)
  equal(reloads,2);equal(saves,2);equal(c.storage.elfbot.hotkeys[1].script,'auto 200 say "changed"')
  source.onFocusChange(source,false);equal(reloads,2,'unchanged edited row must not reload')
  local empty=rowsList:getChildren()[50];empty.onFocusChange(empty,true)
  s.click(panel.originalControls[1047]);local editor=s.root:getFocusedChild()
  equal(editor:getText(),'Edit Hotkey');local command,editorKey,saveButton
  for _,child in ipairs(editor:getChildren()) do
    if child:getStyleName()=='ElfBotMultilineTextEdit' then command=child
    elseif child:getStyleName()=='ElfBotTextEdit' and not editorKey then editorKey=child
    elseif child:getText()=='Save' then saveButton=child end
  end
  assert(command and editorKey and saveButton);editorKey:setText('F3');command:setText('say "new"')
  s.click(saveButton);equal(#c.storage.elfbot.hotkeys,2,'empty slot must append, not create sparse index')
  equal(c.storage.elfbot.hotkeys[2].key,'F3');equal(c.storage.elfbot.hotkeys[2].script,'say "new"')
  c.storage.elfbot.persistent='auto 200 say "persistent"'
  panel.originalControls[1048]:setChecked(true);source=rowsList:getChildren()[1]:getChildren()[3]
  local beforeReloads,beforeSaves=reloads,saves
  source.onFocusChange(source,false);equal(reloads,beforeReloads,'unchanged persistent row must not reload');equal(saves,beforeSaves)
  env.terminate();equal(count(s.events),0);equal(s.connectionCount(),0)
end

-- Position-handling actions still delegate to the registered goto action.
do
  local s=fixture();local executor,c=s.context();local calls=0
  c.autoWalk=function(destination,maxDistance,options)
    calls=calls+1;equal(destination.x,105);equal(destination.y,100);equal(destination.z,7)
    equal(maxDistance,100);equal(options.precision,1);return true
  end
  equal(c.CaveBot.Actions.use.callback('105,100,7',0),'retry')
  equal(c.CaveBot.Actions.usewith.callback('3003,105,100,7',0),'retry')
  equal(c.CaveBot.Actions.tool.callback('rope,3003,105,100,7',0),'retry')
  equal(calls,3,'all position-handling actions use goto');executor.dispose()
end

-- Default potion commands are valid; bad/missing imported types cannot break healing.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  env.init();env.toggle();local c=latest.context;local e=c.ElfBot;local h=c.storage.elfbot.healing
  equal(h.hpType,'uhealth','valid default health type');equal(h.mpType,'gmana','valid default mana type')
  assert(type(e.commands[h.hpType])=='function' and type(e.commands[h.mpType])=='function')
  env.setEnabled(true)
  h.enabled=true;h.hpEnabled=true;h.mpEnabled=true;h.hpHealth=80;h.mpMana=80;h.potionWait=200;h.delay=200
  c.hppercent=function() return 20 end;c.manapercent=function() return 20 end
  local health,mana=0,0
  e.commands.uhealth=function() health=health+1 end;e.commands.gmana=function() mana=mana+1 end
  local function tick() c.now=c.now+1000;e.nextHeal=0;e.nextPotion=0;e.healTick() end
  tick();equal(health,1,'valid health command called');equal(mana,0,'health retains potion priority')
  h.hpType='';tick();equal(health,1);equal(mana,1,'bad health type does not block valid mana type')
  h.hpType=nil;h.mpType=nil;tick();equal(health,1);equal(mana,1,'missing types safely skipped')
  h.hpType='broken';h.mpType='missing';e.commands.broken={};tick()
  equal(health,1);equal(mana,1,'non-function and unknown commands safely skipped');equal(e.nextPotion,0,'skipped potion does not consume cooldown')
  assert(not e.paused,'invalid potion types must not stop automation')
  env.terminate();equal(count(s.events),0);equal(s.connectionCount(),0)
end

-- The collector remains bounded even when the DPS HUD is never opened.
do
  local env=setmetatable({}, {__index=_G});loadProduction('mods/game_elfbot/history.lua',env)
  local history=env.ElfBotHistory.new(10000,2048)
  for time=1,3600000 do history:add(time,1) end
  equal(history.size,2048,'bounded damage ring');equal(history.total,2048)
  equal(count(history.samples),2048);history:prune(3610001);equal(history.total,0);equal(count(history.samples),0)
  local map={old=1,future=20000,valid={updated=9000},invalid=true}
  env.ElfBotHistory.prune(map,10000,5000,256);equal(count(map),1);assert(map.valid)
end

-- Callbacks restore execution after errors/removal and do not disable another owner's tile events.
do
  local s=fixture();local first,c=s.context();local second,c2=s.context()
  equal(s.env.G.botContext,nil,'sandbox context restored')
  local other=c2.onAddThing(function() end)
  local handle=c.onAddThing(function() end)
  assert(s.tileEnabled());handle.remove();assert(s.tileEnabled(),'other tile owner lost')
  other.remove();assert(s.tileEnabled(),'telemetry tile subscriptions must remain until dispose')
  first.dispose();assert(s.tileEnabled());second.dispose();assert(not s.tileEnabled())
  local executor,ctx=s.context();local calls=0;local remove
  local previous={};ctx._currentExecution=previous
  remove=ctx.onTalk(function() remove.remove();error('expected callback error') end)
  ctx.onTalk(function() calls=calls+1 end)
  executor.callbacks.onTalk('Tester',10,1,'hi')
  equal(calls,1,'later listener survives error/self-removal');equal(ctx._currentExecution,previous)
  executor.callbacks.onTalk('Tester',10,1,'hi');equal(calls,2);assert(not remove.remove())
  local macro=ctx.macro(50,function() error('expected macro error') end)
  assert(not pcall(macro.callback,macro));equal(ctx._currentExecution,previous);assert(macro.delay>=ctx.now+1000)
  local hotkey=ctx.hotkey('F1',function() error('expected hotkey error') end)
  equal(hotkey.callback(),false);equal(ctx._currentExecution,previous)
  executor.dispose();executor.dispose();equal(ctx._disposed,true)
  executor.callbacks.onTalk('Tester',10,1,'hi');equal(calls,2,'disposed callbacks ignored')
end

-- Telemetry, command compilation, keyboard and target selection use the production engine.
do
  local s=fixture();local executor,c=s.context({elfbot={botEnabled=true,
    hotkeysEnabled=true,shortkeysEnabled=true,symbol='~',
    hotkeys={{key='F2',script='say "hello"',enabled=true}},
    shortkeys={{key='heal',script='say "exura"',enabled=true}},
    targeting={monsters={{name='rat',reachable=true,count=2,stance='Stand',range=1}},weights={proximity=5}}}})
  local e=c.ElfBot;local said={}
  c.saySpell=function(text) said[#said+1]=text end
  assert(e.key('F2',false));executor.script();equal(said[1],'hello')
  assert(e.shortkey('~heal'));executor.script();equal(said[2],'exura')
  c.storage.elfbot.botEnabled=false;assert(not e.key('F2',false));assert(not e.shortkey('~heal'))
  c.storage.elfbot.botEnabled=true;e.reload()
  local compiles=0;local compile=e.compile
  e.compile=function(text) compiles=compiles+1;return compile(text) end
  assert(e.runAttack('say "attack"'));equal(compiles,1,'attack compiled only once')
  for i=1,10000 do
    c.now=i*2;executor.callbacks.onTextMessage(s.env.MessageModes.DamageDealt,'You deal 1 damage')
  end
  equal(e.damageHistory.size,2048,'production telemetry bounded with HUD off')
  c.now=40001;e.telemetryTick();equal(e.damageHistory.size,0)
  local monsters={};local nameCalls,pathCalls=0,0
  for i=1,100 do
    local creature={}
    function creature:isMonster() return true end
    function creature:getId() return i end
    function creature:getName() nameCalls=nameCalls+1;return 'Rat' end
    function creature:getHealthPercent() return i==100 and 20 or i==99 and 30 or 100 end
    function creature:getPosition() return {x=100+(i-1)%10,y=100+math.floor((i-1)/10),z=7} end
    monsters[i]=creature
  end
  local checkedTargets={}
  s.setSpectators(monsters);c.findPath=function(_,destination)
    pathCalls=pathCalls+1;checkedTargets[pathCalls]=destination
    if destination.x==109 and destination.y==109 then return nil end
    return {}
  end
  c.TargetBot.setOn();c.now=50000;e.targetTick()
  equal(s.attack(),monsters[99],'next highest-ranked reachable target selected')
  equal(pathCalls,2,'stop pathfinding after the first reachable ranked candidate')
  equal(checkedTargets[1].x,109);equal(checkedTargets[1].y,109,'highest-ranked candidate checked first')
  equal(checkedTargets[2].x,108);equal(checkedTargets[2].y,109,'next-ranked candidate checked second')
  assert(nameCalls<600,'quadratic same-name target count')
  for i=1,1000 do e.monsterOwners[i]={name='Other',time=c.now-20000};e.ignoredTargets=e.ignoredTargets or {};e.ignoredTargets[i]=c.now-50000 end
  c.now=c.now+1001;e.tick();equal(count(e.monsterOwners),0);equal(count(e.ignoredTargets),0)
  c.TargetBot.setOff();equal(c.TargetBot.current,nil);equal(#c.TargetBot.Looting.list,0)
  executor.dispose()
end

-- A failed helper initialization releases tile ownership and restores the shared environment.
do
  local s=fixture();local previous={};s.env.G.botContext=previous
  local original=s.env.dofiles
  s.env.dofiles=function(directory)
    original(directory)
    if directory=='functions' then s.env.G.botContext.onAddThing(function() end);error('expected initialization error') end
  end
  local widgets=count(s.widgets)
  assert(not pcall(s.bot.executeBot,'ElfBot',{elfbot={}},nil,function() end,function() end,function() end,{},nil,{standalone=true}))
  equal(s.env.G.botContext,previous);assert(not s.tileEnabled());equal(count(s.widgets),widgets)
end

-- The existing eight-argument community executor still loads its own profile and fonts.
do
  local s=fixture();local env=s.env;local filename='/bot/Community/profile.lua'
  s.files[filename]='UI.Button("Community UI", function() end)\nonAddThing(function() end)'
  env.g_resources.listDirectoryFiles=function(path) equal(path,'/bot/Community');return {filename} end
  local panel=env.g_ui.createWidget('BotPanel')
  local tabs={addTab=function() return {tabPanel={content=panel}} end}
  local fonts=0
  local executor=s.bot.executeBot('Community',{},tabs,function() end,function() end,function() end,{},function() fonts=fonts+1 end)
  equal(executor.ui,nil,'community profile is not an ElfBot extension')
  equal(executor.context.configDir,'/bot/Community');equal(executor.context.mainTab,panel)
  equal(fonts,1,'eighth font callback retained');assert(s.tileEnabled())
  executor.script();executor.dispose();assert(not s.tileEnabled());panel:destroy()
end

-- Console filters are owned/removable and run before outgoing messages are sent.
do
  local s=fixture();local console=s.env.modules.game_console
  local calls=0;local filter=function(text) calls=calls+1;return text=='~heal' end
  console.addFilter(filter);console.addFilter(filter)
  assert(console.filterMessage('~heal'));equal(calls,1);assert(not console.filterMessage('hello'))
  console.removeFilter(filter);assert(not console.filterMessage('~heal'))
  console.addFilter(function() error('expected filter error') end);console.addFilter(filter)
  assert(console.filterMessage('~heal'),'filter errors must not break later filters')
  console.Chat={};loadProduction('modules/game_console/classes/Chat.lua',console)
  console.Chat.sendMessage({},'~heal') -- no tab/server required: intercepted before networking
end

-- Lazy OFF startup, one scheduling chain, exclusive automation and repeated cleanup.
do
  local s=fixture();local env=s.env;local initialWidgets=count(s.widgets)
  local realExecute=s.bot.executeBot;local latest
  s.bot.executeBot=function(...)
    latest=realExecute(...);return latest
  end
  for _=1,20 do
    env.init();assert(not env.isEnabled());assert(not env.isRunning());equal(count(s.events),0,'no OFF background polling')
    env.toggle();assert(env.isRunning());assert(latest.ui.isVisible());equal(count(s.events),1,'visible OFF UI updates')
    local positionCalls,healthCalls=0,0
    latest.context.onCreaturePositionChange(function() positionCalls=positionCalls+1 end)
    latest.context.onCreatureHealthPercentChange(function() healthCalls=healthCalls+1 end)
    s.emit(env.Creature,'onPositionChange',s.player,{},{});s.emit(env.LocalPlayer,'onPositionChange',s.player,{},{})
    s.emit(env.Creature,'onHealthPercentChange',s.player,99);s.emit(env.LocalPlayer,'onHealthPercentChange',s.player,99)
    equal(positionCalls,1,'one local position event');equal(healthCalls,1,'one inherited health event')
    env.setEnabled(true);assert(env.isEnabled());equal(count(s.events),1,'one enabled tick chain')
    local stopCount=s.communityStops();assert(stopCount>0,'community bot not disabled')
    s.advance(50);equal(count(s.events),1,'one tick successor')
    local executor=latest;local widgetCount=count(s.widgets)
    env.setEnabled(false);assert(not env.isEnabled());assert(env.isRunning());assert(latest.ui.isVisible())
    equal(latest,executor,'OFF must retain the runtime');equal(count(s.widgets),widgetCount,'OFF must not destroy the open UI')
    equal(count(s.events),1,'visible OFF keeps only the read-only pulse')
    latest.ui.hide();s.advance(500);equal(count(s.events),0,'hidden OFF must not poll')
    env.terminate();assert(not s.tileEnabled());equal(s.connectionCount(),0);equal(count(s.widgets),initialWidgets,'all ElfBot widgets released')
  end
  env.init();env.toggle()
  local c=latest.context;local executed=0;c.saySpell=function() executed=executed+1 end
  c.storage.elfbot.alerts={private={logout=true}}
  s.emit(env.g_game,'onTalk','Other',10,env.MessageModes.PrivateFrom,'hi')
  assert(env.g_game.isOnline(),'disabled ElfBot must not run logout alerts')
  c.storage.elfbot.botEnabled=true;c.storage.elfbot.shortkeysEnabled=true;c.storage.elfbot.symbol='~'
  c.storage.elfbot.shortkeys={{key='heal',script='say "exura"',enabled=true}};c.ElfBot.reload()
  assert(env.modules.game_console.filterMessage('~heal'));s.advance(500);equal(executed,1,'shortkey through real chat filter and runtime')
  env.terminate();assert(not env.modules.game_console.filterMessage('~heal'),'chat filter removed')
  equal(count(s.events),0);equal(s.connectionCount(),0);equal(count(s.widgets),initialWidgets)
end

-- Reload/termination cancels reconnect work instead of logging in after the module is gone.
do
  local s=fixture();local env=s.env
  local executor
  local execute=s.bot.executeBot
  s.bot.executeBot=function(...) executor=execute(...);return executor end
  env.init();env.setEnabled(true)
  executor.context.storage.elfbot.extras.reconnect=true
  s.setOnline(false);s.emit(env.g_game,'onGameEnd')
  equal(count(s.events),1,'one pending reconnect')
  env.terminate();s.advance(10000);equal(s.logins(),0);equal(count(s.events),0)
end

-- Construct every main panel using the current context, not the archive's old API.
do
  local s=fixture();local env=s.env;env.init();env.toggle()
  local menu
  for widget in pairs(s.widgets) do if widget:getText()=='ElfBot OTC v.1' then menu=widget end end
  assert(menu,'ElfBot menu missing')
  local initialWarnings=#s.warnings
  for _,name in ipairs({'Healing','Aimbot','Lists','HUD','Extras','Hotkeys','Shortkeys','Reconnect','Cavebot','Navigation','Creature Spy','Targeting','Icons','Custom'}) do
    local button
    for _,child in ipairs(menu:getChildren()) do if child:getText()==name then button=child end end
    assert(button, 'menu button missing: '..name);button.onClick()
    equal(#s.warnings,initialWarnings, name..' panel must construct without errors: '..table.concat(s.warnings,' | '))
  end
  env.terminate();equal(s.connectionCount(),0);equal(count(s.events),0)
end

-- Header buttons and list rows must receive real mouse hits, not just direct callbacks.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  env.init();env.toggle();local menu=s.getWidget('ElfBot OTC v.1');assert(menu)
  assert(not env.isEnabled(),'opening UI must not activate automation')
  latest.context.storage.elfbot.routes={['First route']={},['Second route']={}}
  local function open(name)
    menu:raise()
    local button
    for _,child in ipairs(menu:getChildren()) do if child:getText()==name then button=child end end
    assert(button,'menu button missing: '..name)
    assert(button:getTextSize().width<=button:getSize().width,'menu caption clipped: '..name)
    s.click(button)
    local panel=s.root:getFocusedChild();assert(panel~=menu and panel.closeButton,'panel missing: '..name)
    return panel
  end
  for _,name in ipairs({'Healing','Aimbot','Lists','HUD','Extras','Hotkeys','Shortkeys','Reconnect','Cavebot','Navigation','Creature Spy','Targeting','Icons','Custom'}) do
    local panel=open(name);assert(panel:isVisible())
    s.click(panel.closeButton);assert(not panel:isVisible(),'close must hide '..name)
    equal(open(name),panel,'closing/reopening reuses '..name)
    s.click(panel.closeButton)
  end
  local aim=open('Aimbot')
  for _,child in ipairs(aim:getChildren()) do if child:getStyleName()=='ElfBotCheck' then
    assert(child.textWrap,'Aimbot options must wrap')
    assert(child:getTextSize().height<=child:getSize().height,'wrapped option clipped: '..child:getText())
    local p,size=child:getPosition(),child:getSize();local bounds=aim:getPaddingRect()
    assert(p.x+size.width<=bounds.x+bounds.width and p.y+size.height<=bounds.y+bounds.height,'option outside Aimbot')
  end end
  s.click(aim.closeButton)
  local cave=open('Cavebot');local refs=cave.originalControls
  local rows=refs[1009]:getChildren();equal(#rows,2,'saved routes displayed')
  s.click(rows[1]);equal(refs[1041]:getText(),'First route','mouse selects first saved route')
  s.click(rows[2]);equal(refs[1041]:getText(),'Second route','mouse selects second saved route')
  assert(not env.isEnabled(),'UI interaction must not activate automation')
  s.click(cave.closeButton);menu:raise();s.click(menu.closeButton)
  assert(not latest.ui.isVisible(),'main close must hide all ElfBot panels')
  env.terminate();equal(count(s.events),0);equal(s.connectionCount(),0)
end

-- Compact Load dialog keeps its controls inside bounds and preserves loading behavior.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  s.files['/elfbot/settings.json']=env.json.encode({elfbot={}})
  s.files['/elfbot/imports/heal.txt']='auto 1000 say "exura"'
  s.files['/elfbot/before-import.json']=env.json.encode({elfbot={}})
  env.g_resources.listDirectoryFiles=function(dir)
    if dir=='/elfbot' then return {'settings.json','before-import.json'} end
    if dir=='/elfbot/imports' then return {'heal.txt'} end
    return {}
  end
  env.init();env.toggle();local c=latest.context;local menu=s.getWidget('ElfBot OTC v.1');local load
  for _,child in ipairs(menu:getChildren()) do if child:getText()=='Load' then load=child end end
  s.click(assert(load));local panel=s.root:getFocusedChild();local size=panel:getSize()
  assert(size.width<=540 and size.height<=360,'Load dialog must stay compact')
  local files,report,path;local buttons={};local bounds=panel:getPaddingRect()
  for _,child in ipairs(panel:getChildren()) do
    local p,dimensions=child:getPosition(),child:getSize()
    assert(p.x>=bounds.x and p.y>=bounds.y and p.x+dimensions.width<=bounds.x+bounds.width and p.y+dimensions.height<=bounds.y+bounds.height,'Load control outside window: '..child:getText())
    if child:getStyleName()=='ElfBotButton' then
      buttons[child:getText()]=child
      assert(child:getTextSize().width<=dimensions.width,'Load button caption clipped: '..child:getText())
    elseif child:getStyleName()=='ElfBotLabel' then
      assert(child:getTextSize().height<=dimensions.height,'Load label must fit wrapped text')
    end
    if child:getStyleName()=='ElfBotList' then files=child end
    if child:getStyleName()=='ElfBotMultilineTextEdit' then report=child end
    if child:getStyleName()=='ElfBotTextEdit' then path=child end
  end
  assert(files and report and path and report.editable==false)
  equal(#files:getChildren(),2,'list includes saves/imports but excludes recovery backup')
  s.click(files:getChildren()[2]);equal(path:getText(),'/elfbot/imports/heal.txt')
  assert(report:getText():find('1 hotkeys',1,true),'selecting a file populates the preview')
  assert(not env.isEnabled(),'preview cannot start automation')
  local loaded,slot,opened
  c.loadElfFile=function(value) loaded=value end;c.loadElfSlot=function(value) slot=value end
  env.g_resources.getWriteDir=function() return 'C:/fixture/AppData' end
  env.g_platform.openDir=function(value) opened=value end
  s.click(assert(buttons['Load file']));equal(loaded,'/elfbot/imports/heal.txt')
  s.click(assert(buttons['Load selected slot']));equal(slot,1)
  s.click(assert(buttons['Open saves folder']));equal(opened,'C:/fixture/AppData/elfbot')
  c.storage.elfbot.importWarnings={'Example import notice'}
  s.click(assert(buttons['Last import notices']));equal(report:getText(),'Example import notice')
  path:setText('/elfbot/imports/missing.txt');loaded=nil
  s.click(buttons['Load file']);assert(not loaded,'failed preview must not call Load')
  assert(report:getText():find('missing fixture file',1,true))
  s.click(assert(buttons['Refresh files']));equal(#files:getChildren(),2,'refresh replaces file rows without duplication')
  s.click(assert(buttons['Paste script']));local paste=s.root:getFocusedChild()
  assert(paste~=panel and paste.titleBar:getText()=='Load original ElfBot text')
  s.click(paste.closeButton);panel:raise();s.click(panel.closeButton);assert(not panel:isVisible())
  menu:raise();s.click(load);equal(s.root:getFocusedChild(),panel,'reopening Load reuses the same dialog')
  env.terminate();equal(count(s.events),0);equal(s.connectionCount(),0)
end

-- Valkor-style icons: visible defaults, click commands, dragging and master OFF.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  env.init();env.toggle();local c=latest.context;local e=c.ElfBot;local data=c.storage.elfbot
  local menu=s.getWidget('ElfBot OTC v.1');local iconsButton
  for _,child in ipairs(menu:getChildren()) do if child:getText()=='Icons' then iconsButton=child end end
  s.click(assert(iconsButton));local editor=s.root:getFocusedChild();local edits,on,enable,bkg={}
  for _,child in ipairs(editor:getChildren()) do
    if child:getStyleName()=='ElfBotTextEdit' then edits[#edits+1]=child end
    assert(child:getText()~='Apply','icon settings must not require Apply')
    if child:getText()=='On' then on=child end
    if child:getText()=='Enable Icons' then enable=child end
    if child:getText()=='Bkg Draw' then bkg=child end
  end
  assert(on:isChecked(),'new icons must be visible by default');assert(not enable:isChecked(),'custom icons stay empty until configured or loaded')
  local defaults=#data.icons
  edits[1]:setText('Heal');edits[2]:setText('auto 1000 say "exura"');edits[3]:setText('say "right"')
  equal(#data.icons,defaults+1,'editing the new icon name creates a single configured icon')
  assert(not data.iconsEnabled and not enable:isChecked(),'configuration cannot enable the icon layer implicitly')
  s.click(enable);assert(data.iconsEnabled and enable:isChecked())
  local row=data.icons[#data.icons];assert(row.enabled);editor:hide();menu:setPosition({x=500,y=500})
  local function icon()
    for v in pairs(s.widgets) do if v:getStyleName()=='ElfBotIcon' and v.iconRow==row then return v end end
    error('command icon missing')
  end
  local v=icon();assert(v.draggable and not v.phantom);equal(v.caption:getParent(),v,'caption belongs inside the clickable button')
  equal(v.caption:getText(),'Heal','empty sprite/text still has a visible name');equal(v.badge:getText(),'OFF')
  local calls={};c.saySpell=function(text) calls[#calls+1]=text end
  s.click(v);equal(#e.jobs,0,'OFF click must not queue a command for later')
  assert(e.status:find('Automation is OFF',1,true));assert(not row.running)
  local automation
  for _,child in ipairs(menu:getChildren()) do if child:getText()=='Automation: OFF' then automation=child end end
  editor:show();menu:raise();s.click(assert(automation));assert(editor:isVisible() and menu:isVisible())
  editor:hide();v=icon();local before=count(s.widgets);s.click(v)
  equal(icon(),v,'click updates in place, without destroying the pressed widget');equal(count(s.widgets),before,'caption/badge do not accumulate')
  assert(row.running);equal(v.badge:getText(),'ON');s.advance(50);equal(calls[1],'exura')
  local runningJob=e.jobs[#e.jobs];local jobsBefore=#e.jobs
  editor:show();editor:raise();edits[15]:setText('3003');s.click(bkg)
  assert(row.running and runningJob.active,'live appearance editing cannot cancel a repeating script')
  equal(e.jobs[#e.jobs],runningJob);equal(#e.jobs,jobsBefore,'appearance edits cannot restart or duplicate scripts')
  equal(#calls,1,'configuration edits must not execute icon commands');equal(icon().borderWidth,0)
  equal(icon().items:getChildren()[1].itemId,3003,'active appearance updates without an Apply button')
  editor:hide();v=icon()
  s.click(v);assert(not row.running);equal(v.badge:getText(),'OFF');s.advance(1500);equal(#calls,1,'second click cancels repeating script')
  v=icon();local p=v:getPosition();assert(v.onMousePress(v,p,2));assert(v.onMouseRelease(v,{x=p.x+5,y=p.y+5},2))
  s.advance(50);equal(calls[2],'right','right click runs its own command')
  -- Drag beyond the map, save both visual states once, and do not execute a click.
  v=icon();local saves=0;c.saveConfig=function() saves=saves+1 end;p=v:getPosition()
  assert(v.onDragEnter(v,{x=p.x+5,y=p.y+5}));assert(v.onDragMove(v,{x=1105,y=355}))
  s.advance(500);equal(icon(),v,'pulse cannot replace a dragging widget');equal(saves,0)
  assert(v.onDragLeave(v));equal(saves,1);equal(row.offState.x,1100);equal(row.onState.x,1100)
  equal(row.offState.y,350);equal(row.onState.y,350);equal(#calls,2,'drag does not execute the icon')
  s.advance(500);v=icon();equal(v:getPosition().x,1100);equal(v:getPosition().y,350)
  s.click(v);s.advance(50);assert(row.running);local executed=#calls
  local suspended=e.jobs[#e.jobs];suspended.thread=coroutine.create(function() error('OFF coroutine resumed') end)
  c._scheduler={{execution=s.now()+1,callback=function() error('OFF scheduled action ran') end}}
  editor:show();menu:raise();s.click(automation)
  assert(not env.isEnabled());assert(menu:isVisible() and editor:isVisible(),'OFF must not close any open editor')
  equal(latest.context,c,'OFF retains context');equal(#e.jobs,0,'OFF cancels suspended jobs');equal(#c._scheduler,0)
  assert(not suspended.thread and not suspended.active,'OFF releases suspended coroutine references')
  equal(automation:getText(),'Automation: OFF');equal(icon().badge:getText(),'OFF')
  s.advance(2000);equal(#calls,executed,'OFF cannot send icon actions')
  s.click(automation);assert(env.isEnabled());editor:hide();s.advance(50)
  assert(#calls>executed,'ON restarts the configured repeating icon')
  s.root:setSize({width=800,height=500});s.advance(500);v=icon();p=v:getPosition()
  assert(p.x+v:getSize().width<=800 and p.y+v:getSize().height<=500,'resized window keeps the icon visible')
  env.saveSlot(1);assert(env.loadSlot(1));local restored=latest.context.storage.elfbot.icons;row=restored[#restored];v=icon()
  equal(row.offState.x,1100,'drag position persists in saved profile');equal(v.badge:getText(),'OFF','load does not start automation')
  local lateClick=v.onClick;local lateMove=v.onDragMove
  env.terminate();lateClick();assert(not lateMove(v,{x=1,y=1}));equal(count(s.events),0);equal(s.connectionCount(),0)
end

-- Enable Icons is the single visibility gate for built-in and custom icons.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  local saved={elfbot={icons={{name='Saved icon',enabled=true,lclick='say "saved"',offState={},onState={}}},iconsEnabled=false,
    hotkeys={{key='F2',script='say "saved"',enabled=true}},targeting={monsters={{name='Rat',stance='No Movement',loot=false}}},
    waypoints={{'label','Saved route'}}}}
  s.files['/elfbot/settings.json']=env.json.encode(saved);s.files['/elfbot/slot1.json']=env.json.encode(saved)
  env.init();equal(count(s.events),0,'built-in controls must not eagerly start the runtime')
  env.toggle();local c=latest.context;local data=c.storage.elfbot;local e=c.ElfBot
  equal(#data.icons,0);equal(#data.hotkeys,0);equal(#data.waypoints,0);equal(#data.targeting.monsters,0)
  assert(not data.iconsEnabled,'opening ElfBot cannot apply existing personal settings')
  local function icon(key)
    for v in pairs(s.widgets) do if v:getStyleName()=='ElfBotIcon' and v.iconRow.controlKey==key then return v end end
  end
  assert(not icon('waypoint') and not icon('target'),'unchecked Enable Icons must hide built-in controls')
  local menu=s.getWidget('ElfBot OTC v.1');local open
  for _,child in ipairs(menu:getChildren()) do
    assert(not child:getText():match('^Cavebot: ') and not child:getText():match('^Target: '),'main menu must not contain redundant controller buttons')
    if child:getText()=='Icons' then open=child end
  end
  s.click(assert(open));local panel=s.root:getFocusedChild();local enable
  for _,child in ipairs(panel:getChildren()) do
    assert(not child:getText():match('^Cavebot: ') and not child:getText():match('^Target: '),'icon editor must not contain redundant controller buttons')
    if child:getText()=='Enable Icons' then enable=child end
    if child:getStyleName()=='ElfBotList' then
      local rows=child:getChildren();equal(#rows,3,'built-in controls remain configurable while hidden')
      equal(rows[1]:getText(),'<New Icon>');equal(rows[2]:getText(),'Cavebot');equal(rows[3]:getText(),'Target')
    end
  end
  assert(enable and not enable:isChecked());s.click(enable)
  for _,key in ipairs({'waypoint','target'}) do equal(icon(key).badge:getText(),'OFF') end
  assert(not c.CaveBot.isOn() and not c.TargetBot.isOn() and not env.isEnabled())
  equal(icon('waypoint').items:getChildren()[1].itemId,3116);equal(icon('target').items:getChildren()[1].itemId,3264)
  -- Click starts the existing controller directly, without a separate master ON click.
  c.CaveBot.addAction('label','Ready');data.targeting.monsters={{name='Rat',stance='No Movement',loot=false}}
  local rat={isMonster=function() return true end,isPlayer=function() return false end,
    getId=function() return 2 end,getName=function() return 'Rat' end,getHealthPercent=function() return 100 end,
    getPosition=function() return {x=101,y=100,z=7} end}
  s.setSpectators({s.player,rat})
  panel:hide();menu:setPosition({x=500,y=500})
  s.click(icon('waypoint'));assert(env.isEnabled() and c.CaveBot.isOn());equal(icon('waypoint').badge:getText(),'ON')
  assert(not c.TargetBot.isOn(),'Cavebot click cannot enable Target')
  s.click(icon('target'));assert(c.TargetBot.isOn());s.advance(500)
  equal(s.attack(),rat,'built-in Target uses the real targeting controller')
  assert(c.CaveBot.isOn() and c.TargetBot.isOn(),'controls must not repeatedly toggle themselves')
  -- Hide all icons without stopping controllers; stale clicks from hidden icons do nothing.
  local lateClick=icon('waypoint').onClick;panel:show();panel:raise();s.click(enable)
  assert(not icon('waypoint') and not icon('target'));lateClick()
  assert(c.CaveBot.isOn() and c.TargetBot.isOn(),'visibility is not an automation switch')
  s.advance(500);assert(not icon('waypoint') and not icon('target'),'a pulse cannot recreate unchecked icons')
  s.click(enable);equal(icon('waypoint').badge:getText(),'ON');equal(icon('target').badge:getText(),'ON');panel:hide()
  env.setEnabled(false);assert(not c.CaveBot.isOn() and not c.TargetBot.isOn());assert(menu:isVisible())
  s.click(icon('target'));assert(env.isEnabled() and c.TargetBot.isOn())
  assert(not c.CaveBot.isOn(),'direct Target click cannot resume the other paused controller')
  s.click(icon('target'));assert(not c.TargetBot.isOn());equal(s.attack(),nil)
  equal(#data.icons,0,'using built-ins never creates personal icon records')
  local lateChange=enable.onCheckChange;lateClick=icon('waypoint').onClick
  assert(env.loadSlot(1));c=latest.context;data=c.storage.elfbot
  equal(#data.icons,1);equal(data.icons[1].name,'Saved icon');equal(#data.hotkeys,1);equal(#data.waypoints,1)
  assert(not data.iconsEnabled and not env.isEnabled(),'only Load applies settings; it cannot enable automation')
  assert(not icon('waypoint') and not icon('target'),'loading a disabled layer cannot show built-ins')
  lateChange(enable,true);lateClick();assert(not env.isEnabled() and not data.iconsEnabled,'replaced UI callbacks cannot enable icons or automation')
  menu=s.getWidget('ElfBot OTC v.1');menu:raise()
  for _,child in ipairs(menu:getChildren()) do if child:getText()=='Icons' then open=child end end
  s.click(open);panel=s.root:getFocusedChild()
  for _,child in ipairs(panel:getChildren()) do if child:getText()=='Enable Icons' then enable=child end end
  s.click(enable);panel:hide();menu:setPosition({x=500,y=500})
  equal(icon('waypoint').badge:getText(),'OFF');equal(icon('target').badge:getText(),'OFF')
  s.click(icon('target'));assert(c.TargetBot.isOn());assert(not c.CaveBot.isOn())
  equal(#data.icons,1,'using built-ins cannot add or replace custom records')
  local v=icon('waypoint');local p=v:getPosition();local saves=0;c.saveConfig=function() saves=saves+1 end
  assert(v.onDragEnter(v,{x=p.x+5,y=p.y+5}));assert(v.onDragMove(v,{x=305,y=455}))
  s.advance(500);equal(icon('waypoint'),v,'built-in drag survives a pulse')
  assert(v.onDragLeave(v))
  equal(saves,1);equal(#data.icons,1);equal(data.controlIconPositions.waypoint.x,300)
  equal(data.controlIcons.waypoint.offState.x,300);equal(data.controlIcons.waypoint.onState.x,300)
  env.saveSlot(2);assert(env.loadSlot(2));equal(icon('waypoint'):getPosition().x,300)
  equal(latest.context.storage.elfbot.icons[1].name,'Saved icon','saving built-in position preserves custom records')
  env.terminate();lateClick();lateChange(enable,true);equal(count(s.events),0);equal(s.connectionCount(),0)
end

-- Built-in appearance is editable without custom scripts, loading or starting automation.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  local saved={elfbot={controlIcons={waypoint={name='Personal Cavebot',size='Large',offState={ids={3003,0,0,0},x=300,y=220}}}}}
  s.files['/elfbot/settings.json']=env.json.encode(saved)
  env.init();env.toggle();local c=latest.context;local data=c.storage.elfbot
  local function icon(key)
    for v in pairs(s.widgets) do if v:getStyleName()=='ElfBotIcon' and v.iconRow.controlKey==key then return v end end
  end
  assert(not icon('waypoint'),'opening the UI must not show unchecked icons')
  local menu=s.getWidget('ElfBot OTC v.1');local open
  for _,child in ipairs(menu:getChildren()) do if child:getText()=='Icons' then open=child end end
  s.click(assert(open));local panel=s.root:getFocusedChild();local names,on,enable,bkg;local edits,combos,colors={},{},{}
  for _,child in ipairs(panel:getChildren()) do
    if child:getStyleName()=='ElfBotList' then names=child end
    if child:getStyleName()=='ElfBotTextEdit' then edits[#edits+1]=child end
    if child:getStyleName()=='ElfBotCombo' then combos[#combos+1]=child end
    assert(child:getText()~='Apply','built-in settings must not require Apply')
    if child:getText()=='On' then on=child end
    if child:getText()=='Enable Icons' then enable=child end
    if child:getText()=='Bkg Draw' then bkg=child end
    if child.hexValue then colors[#colors+1]=child end
  end
  local function select(text)
    for _,row in ipairs(names:getChildren()) do if row:getText()==text then s.click(row);return end end
    error('missing editor row '..text)
  end
  local function editAppearance(name,offId,onId,x,y)
    edits[1]:setText(name);combos[1]:setCurrentOption('Medium')
    edits[4]:setText(offId);edits[15]:setText(onId)
    combos[4]:setCurrentOption('Absolute');combos[5]:setCurrentOption('Absolute')
    combos[8]:setCurrentOption('Absolute');combos[9]:setCurrentOption('Absolute')
    edits[12]:setText(x);edits[13]:setText(y);edits[23]:setText(x);edits[24]:setText(y)
    edits[14]:setText(name..' OFF');edits[25]:setText(name..' ON')
  end
  select('Cavebot');equal(edits[1]:getText(),'Cavebot');equal(edits[4]:getText(),'3116')
  equal(edits[2]:getText(),'Toggle ON/OFF');assert(not edits[2].editable and not edits[3].enabled,'fixed actions are not editable scripts')
  editAppearance('Route',3003,3457,240,200)
  equal(#data.icons,0);assert(not data.iconsEnabled and not enable:isChecked());assert(not env.isEnabled())
  assert(not icon('waypoint') and not icon('target'),'editing hidden icons cannot implicitly enable them')
  s.click(enable);assert(data.iconsEnabled and not env.isEnabled())
  equal(icon('waypoint'):getPosition().x,240);equal(icon('waypoint'):getPosition().y,200)
  equal(icon('waypoint'):getSize().width,76);equal(icon('waypoint').caption:getText(),'Route OFF')
  equal(icon('waypoint').items:getChildren()[1].itemId,3003);equal(names:getChildren()[2]:getText(),'Route')
  -- IDs and color changes take effect synchronously; transient invalid input is not saved.
  edits[4]:setText('');equal(icon('waypoint').items:getChildren()[1].itemId,3003)
  edits[4]:setText('3003.5');equal(data.controlIcons.waypoint.offState.ids[1],3003)
  edits[4]:setText('3004');equal(icon('waypoint').items:getChildren()[1].itemId,3004)
  edits[4]:setText('3003');colors[1]:setText('#123456');equal(icon('waypoint').caption.color,'#123456')
  edits[8]:setText('3031');equal(#icon('waypoint').items:getChildren(),2,'configured background layer is visible')
  bkg:setChecked(false);local bare=icon('waypoint');equal(bare.borderWidth,0);equal(bare.backgroundColor,'#00000000')
  equal(#bare.items:getChildren(),1,'Bkg Draw OFF removes background layers immediately')
  for _,item in ipairs(bare.items:getChildren()) do
    equal(item.imageSource,'');equal(item.borderWidth,0);assert(item.drawRarity==false and item.rarityDefaultImageSource=='','item rarity frames must not reintroduce a border')
  end
  bkg:setChecked(true);equal(icon('waypoint').borderWidth,1);equal(#icon('waypoint').items:getChildren(),2)
  bkg:setChecked(false)
  equal(icon('target').items:getChildren()[1].itemId,3264,'Cavebot edits cannot change Target')
  select('Target');editAppearance('Hunt',3031,3035,400,200)
  equal(#data.icons,0);assert(not c.CaveBot.isOn() and not c.TargetBot.isOn(),'appearance edits cannot toggle controllers')
  assert(env.saveSlot(1));assert(env.loadSlot(1));c=latest.context;data=c.storage.elfbot
  equal(icon('waypoint'):getPosition().x,240);equal(icon('waypoint').items:getChildren()[1].itemId,3003)
  equal(icon('waypoint').borderWidth,0);equal(icon('waypoint').caption.color,'#123456','live appearance changes persist in the saved slot')
  equal(icon('target'):getPosition().x,400);equal(icon('target').items:getChildren()[1].itemId,3031)
  assert(data.iconsEnabled and not env.isEnabled());equal(#data.icons,0)
  local loaded=env.json.decode(s.files['/elfbot/slot1.json']).elfbot.controlIcons
  assert(not loaded.waypoint.builtinController and not loaded.waypoint.lclick,'profiles save appearance, not executable/controller overrides')
  c.CaveBot.addAction('label','Ready');local targetBefore=icon('target'):getPosition()
  menu=s.getWidget('ElfBot OTC v.1');menu:setPosition({x=500,y=500});s.click(icon('waypoint'))
  assert(c.CaveBot.isOn() and not c.TargetBot.isOn());equal(icon('waypoint').items:getChildren()[1].itemId,3457)
  equal(icon('waypoint').borderWidth,0,'ON/OFF cannot restore a disabled frame')
  equal(icon('waypoint').caption:getText(),'Route ON');equal(icon('target'):getPosition().x,targetBefore.x)
  env.setEnabled(false);menu:raise()
  for _,child in ipairs(menu:getChildren()) do if child:getText()=='Icons' then open=child end end
  s.click(open);panel=s.root:getFocusedChild();edits={}
  for _,child in ipairs(panel:getChildren()) do
    if child:getStyleName()=='ElfBotList' then names=child end
    if child:getStyleName()=='ElfBotTextEdit' then edits[#edits+1]=child end
    if child:getText()=='On' then on=child end
  end
  select('Hunt');on:setChecked(false);assert(not icon('target'),'On controls visibility immediately, not automation')
  equal(#names:getChildren(),3,'hidden built-ins remain editable');assert(not env.isEnabled())
  on:setChecked(true);assert(icon('target'));equal(icon('target').items:getChildren()[1].itemId,3031)
  select('<New Icon>');assert(edits[2].editable and edits[3].enabled,'custom command fields become editable again')
  edits[1]:setText('Custom');edits[2]:setText('say "hello"');equal(#data.icons,1)
  select('Custom');edits[1]:setText('Custom edited');equal(#data.icons,1);equal(data.icons[1].name,'Custom edited','built-in rows cannot offset custom selection indexes')
  env.terminate();equal(count(s.events),0);equal(s.connectionCount(),0)
  local builtin=env.ElfBotIconImport.builtinControls(nil,{waypoint={builtinController='TargetBot',lclick='say "bad"',
    offState={ids={-1,70000,0/0,123},x=math.huge,y='bad',foreground='invalid'}}})[1]
  equal(builtin.builtinController,'CaveBot');assert(not builtin.lclick);equal(builtin.offState.ids[1],3116)
  equal(builtin.offState.ids[2],0);equal(builtin.offState.ids[3],0);equal(builtin.offState.ids[4],123)
  equal(builtin.offState.x,20);equal(builtin.offState.y,20);equal(builtin.offState.foreground,'#ff5a61')
end

-- Original [Icons] imports keep item layers and controller toggles truthful.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  env.init();env.toggle();env.setEnabled(true);local c=latest.context;local e=c.ElfBot
  e.caveTick=function() end -- isolate icon toggling from empty-route completion
  local menu=s.getWidget('ElfBot OTC v.1');local open
  for _,child in ipairs(menu:getChildren()) do if child:getText()=='Icons' then open=child end end
  s.click(assert(open));local panel=s.root:getFocusedChild()
  for _,child in ipairs(panel:getChildren()) do if child:getText()=='Enable Icons' then s.click(child) end end
  panel:hide();menu:setPosition({x=500,y=500})
  local source='[Icons]\nName: Cavebot\nLeftCommand: auto 50 listas "Cavebot" | setcolor 0 255 0 | setcavebot toggle\n'..
    'State: Inactive\nIconType: Resize\nIconIds: 3003,0,0,0\nText: Cavebot\nPositionX: 20\nPositionY: 250\n'..
    'State: Active\nIconType: Resize\nIconIds: 3457,0,0,0\nText: Cavebot\nPositionX: 20\nPositionY: 250\n'
  local imported,warnings=e.importIcons(source);equal(imported,1);equal(#warnings,0)
  local function icon(name)
    for v in pairs(s.widgets) do if v:getStyleName()=='ElfBotIcon' and not v.iconRow.builtinController and v.iconRow.name==(name or 'Cavebot') then return v end end
    error('imported icon missing')
  end
  local v=icon();equal(v.items:getChildren()[1].itemId,3003);equal(v.badge:getText(),'OFF')
  s.click(v);assert(c.CaveBot.isOn());equal(v.badge:getText(),'ON');equal(v.caption.color,'#00ff00')
  equal(v.items:getChildren()[1].itemId,3457,'active state swaps item without replacing the button')
  s.advance(500);assert(c.CaveBot.isOn(),'auto prefix must not repeatedly toggle the controller')
  v=icon();s.click(v);assert(not c.CaveBot.isOn());equal(v.badge:getText(),'OFF')
  c.CaveBot.setOn();s.advance(500);equal(icon().badge:getText(),'ON','external Follow switch updates icon')
  env.setEnabled(false);equal(icon().badge:getText(),'OFF');assert(latest.ui.isVisible())
  env.setEnabled(true);equal(icon().badge:getText(),'ON','master ON restores controller and its live badge')
  -- Imported Text icons are still usable without an item.
  e.replaceIcons('[Icons]\nName: Text only\nLeftCommand: say "text"\nState: Inactive\nIconType: Text\nPositionX: 20\nPositionY: 250\n')
  equal(icon('Text only').caption:getText(),'Text only');equal(#icon('Text only').items:getChildren(),0)
  local calls=0;c.saySpell=function(text) equal(text,'text');calls=calls+1 end
  s.click(icon('Text only'));s.advance(50);equal(calls,1)
  env.terminate();equal(count(s.events),0);equal(s.connectionCount(),0)
end

-- Classic HUD: map-aligned defaults, window-wide dragging, real stats and cleanup.
do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  s.map:setPosition({x=240,y=80});s.map:setSize({width=500,height=400})
  local sidebar=env.g_ui.createWidget('Sidebar',s.root)
  sidebar:setPosition({x=1040,y=80});sidebar:setSize({width=240,height=500})
  env.init();assert(env.showHud());local c=latest.context;local saves=0
  c.saveConfig=function() saves=saves+1 end
  local function panel(id)
    for v in pairs(s.widgets) do if v.id==id then return v end end
    error('missing HUD panel '..id)
  end
  local skills=panel('elfbotHudSkills')
  local function startDrag(v)
    local p=v:getPosition();local mouse={x=p.x+6,y=p.y+6}
    equal(s.hitHud(mouse),v,'clicking HUD text must hit its draggable block, not the game map')
    assert(v.draggable and not v.phantom,'HUD blocks must receive drag gestures')
    assert(v.onMousePress(v,mouse,1),'press consumed before map input')
    assert(v.onDragEnter(v,mouse),'plain left-button drag must not require Ctrl')
  end
  startDrag(skills)
  assert(skills.onDragMove(skills,{x=306,y=236}))
  equal(skills:getPosition().x,300);equal(skills:getPosition().y,230)
  s.advance(500);equal(skills:getPosition().x,300);equal(skills:getPosition().y,230,'HUD pulse must not snap the dragged block back')
  equal(saves,0,'do not schedule settings writes on each mouse move')
  assert(skills.onDragLeave(skills,nil,{x=306,y=236}),'drop consumed before map release')
  assert(skills.onMouseRelease(skills,{x=306,y=236},1))
  equal(saves,1,'save position once on drop');assert(not env.isEnabled(),'moving HUD must not start automation')
  local saved=c.storage.elfbot.hud.dragPositions.elfbotHudSkills
  assert(saved.x>=0 and saved.x<=1 and saved.y>=0 and saved.y<=1,'save window-relative positions')
  equal(saved.space,'window')
  -- The other block can be positioned independently.
  c.storage.elfbot.hud.general=true;s.advance(500)
  local stats=panel('elfbotHudStats');startDrag(stats)
  assert(stats.onDragMove(stats,{x=336,y=346}));assert(stats.onDragLeave(stats))
  equal(stats:getPosition().x,330);equal(stats:getPosition().y,340);equal(saves,2)
  equal(skills:getPosition().x,300);equal(skills:getPosition().y,230,'moving stats must not move skills')
  -- Move beyond the old map boundary, over the right-side inventory area.
  startDrag(skills);assert(skills.onDragMove(skills,{x=1206,y=166}))
  assert(skills:getPosition().x>s.map:getPaddingRect().x+s.map:getPaddingRect().width,'right-side dragging must not stop at the map edge')
  assert(skills:getSize().width<230,'moved skills block fits its text, not a wide empty margin')
  assert(skills.onDragLeave(skills));equal(saves,3)
  local right=skills:getPosition();s.advance(500)
  equal(skills:getPosition().x,right.x);equal(skills:getPosition().y,right.y,'pulse preserves placement outside the map')
  equal(s.hitRoot({x=right.x+6,y=right.y+6}),skills,'HUD remains clickable above the sidebar')
  equal(s.hitRoot({x=1046,y=400}),sidebar,'phantom overlay must not block other sidebar controls')
  s.map:setSize({width=700,height=200});s.advance(500)
  equal(skills:getPosition().x,right.x);equal(skills:getPosition().y,right.y,'map resize must not move window-positioned HUDs')
  local function inside(v)
    local rect,p,size=s.root:getPaddingRect(),v:getPosition(),v:getSize()
    assert(p.x>=rect.x and p.y>=rect.y and p.x+size.width<=rect.x+rect.width and p.y+size.height<=rect.y+rect.height,'drag/resize must keep the whole block visible')
  end
  inside(skills);inside(stats)
  s.root:setSize({width=900,height=600});s.advance(500);inside(skills);inside(stats)
  local before=skills:getPosition();env.saveSlot(1)
  assert(env.loadSlot(1),'saved HUD profile must load')
  local restored=panel('elfbotHudSkills');assert(restored~=skills,'load replaces owned HUD widgets')
  equal(restored:getPosition().x,before.x);equal(restored:getPosition().y,before.y,'saved drag position must be restored')
  local current=latest.context;current.saveConfig=function() saves=saves+1 end
  local previous=current.storage.elfbot.hud.dragPositions.elfbotHudSkills
  -- Cancellation and teardown cannot save a half-finished drag or recreate polling.
  startDrag(restored);restored.onDragMove(restored,{x=-1000,y=-1000});inside(restored)
  restored.onDragMove(restored,{x=100000,y=100000});inside(restored)
  latest.ui.hide();assert(restored.onDragLeave(restored));equal(saves,3)
  equal(current.storage.elfbot.hud.dragPositions.elfbotHudSkills,previous,'cancelled drag does not change saved position')
  local lateMove,lateLeave=restored.onDragMove,restored.onDragLeave
  env.terminate();assert(not lateMove(restored,{x=100,y=100}));assert(lateLeave(restored))
  equal(saves,3);equal(count(s.events),0);equal(s.connectionCount(),0)
end

do
  local s=fixture();local env=s.env
  s.map:setPosition({x=240,y=80});s.map:setSize({width=500,height=400})
  env.init();assert(not env.isRunning());equal(count(s.events),0,'HUD must not eagerly start an OFF bot')
  assert(env.showHud());assert(not env.isEnabled(),'showing the HUD must not enable automation')
  local layer,skills
  for v in pairs(s.widgets) do
    if v:getStyleName()=='ElfBotHudLayer' then layer=v end
    if v.id=='elfbotHudSkills' then skills=v end
  end
  assert(layer and layer:isVisible(),'Classic HUD must appear immediately, without extra checkboxes or a delayed tick')
  equal(skills:getPosition().x,410,'skills-only HUD remains top-right even on a smaller map')
  equal(skills:getPosition().y,85);equal(#skills:getChildren(),8)
  local values=skills:getChildren()
  equal(values[1].colored[2],'#ffff00','Level label is yellow')
  equal(values[1].colored[4],'#ffff00','Level value is yellow')
  equal(values[2].colored[2],'#4fc3f7','Magic Level label is blue')
  equal(values[2].colored[4],'#00ff00','Magic Level value is green')
  equal(values[3].colored[2],'#ffffff','skill labels are white')
  equal(values[3].colored[4],'#00ff00','skill values are green')
  equal(values[8].colored[4],'#00ff00','Stamina value is green')
  env.terminate();equal(count(s.events),0);equal(s.connectionCount(),0)
end

do
  local s=fixture();local env=s.env;local latest;local execute=s.bot.executeBot
  s.bot.executeBot=function(...) latest=execute(...);return latest end
  s.map:setPosition({x=250,y=100});s.map:setSize({width=950,height=500})
  env.init();env.toggle();local c=latest.context;local e=c.ElfBot;local h=c.storage.elfbot.hud
  h.enabled=true;h.general=true;h.damage=true;h.active=true;h.healing=true
  h.playerInfo=true;h.guild=true;h.vocation=true;h.mana=true
  local other={text='Previous label'}
  function other:getName() return 'Unknown player' end
  function other:getId() return 2 end
  function other:getPosition() return {x=101,y=100,z=7} end
  function other:getHealthPercent() return 85 end
  function other:getVocation() return 0 end
  function other:getManaPercent() return -1 end
  function other:isPlayer() return true end
  function other:getText() return self.text end
  function other:setText(text) self.text=text end
  s.setSpectators({s.player,other})
  e.status='ElfBot settings saved';c.exp=function() return 2000 end
  latest.callbacks.onTextMessage(env.MessageModes.DamageDealt,'You deal 350 damage')
  s.advance(2000)
  local layer,stats,skills
  for v in pairs(s.widgets) do
    if v:getStyleName()=='ElfBotHudLayer' then layer=v end
    if v.id=='elfbotHudStats' then stats=v elseif v.id=='elfbotHudSkills' then skills=v end
  end
  assert(layer and stats and skills,'HUD blocks missing')
  equal(layer:getParent(),s.root,'HUD must be able to cross the map edge and side panels')
  assert(layer.phantom,'HUD must not consume map clicks');assert(layer:isVisible())
  local function text(panel)
    local lines={};for _,row in ipairs(panel:getChildren()) do if row:isVisible() then lines[#lines+1]=row:getText() end end
    return table.concat(lines,'\n')
  end
  local function includes(panel,value) assert(text(panel):find(value,1,true),'missing HUD value: '..value..'\n'..text(panel)) end
  includes(stats,'Tester | Level 10');includes(stats,'HP 100/100 (100%) | MP 100/100 (100%)')
  includes(stats,'Session: 00:00:02');includes(stats,'XP gained: 1,000');includes(stats,'XP/hour: 1,800,000')
  includes(stats,'Best hit: 350');includes(stats,'Healing: OFF')
  assert(not text(stats):find('settings saved',1,true),'status notices are not running scripts')
  assert(not text(stats):find('Unknown player',1,true),'player labels must not be duplicated in the statistics block')
  equal(other.text,'\nHP 85%','unknown look data must not fabricate level, vocation, guild or mana')
  includes(skills,'~ Level: 10 (40%)');includes(skills,'~ Magic Level: 5 (60%)')
  includes(skills,'~ Fist: 11 (70%)');includes(skills,'~ Club: 12 (70%)')
  includes(skills,'~ Distance: 15 (70%)');includes(skills,'~ Shielding: 16 (70%)');includes(skills,'~ Fishing: 17 (70%)')
  includes(skills,'~ Stamina: 41:40 (99%)');equal(#skills:getChildren(),8,'only Classic 8.60 skills are rendered')
  equal(stats:getPosition().x,258);equal(stats:getPosition().y,108)
  equal(skills:getPosition().x,870,'Classic skills use the map top-right inset');equal(skills:getPosition().y,105)
  local function checkBounds()
    local bounds=s.map:getPaddingRect()
    for _,panel in ipairs({stats,skills}) do if panel:isVisible() then
      local p,size=panel:getPosition(),panel:getSize()
      assert(p.x>=bounds.x and p.y>=bounds.y and p.x+size.width<=bounds.x+bounds.width and p.y+size.height<=bounds.y+bounds.height,'HUD outside the map')
      for _,row in ipairs(panel:getChildren()) do if row:isVisible() then
        assert(row.phantom,'HUD text must not consume map clicks')
        assert(row.textWrap and row:getTextSize().height<=row:getSize().height,'HUD wrapping clipped: '..row:getText()..' / '..row:getTextSize().height..' > '..row:getSize().height)
        local rp,rs=row:getPosition(),row:getSize()
        assert(rp.y>=p.y and rp.y+rs.height<=p.y+size.height,'row outside its HUD block')
      end end
    end end
  end
  checkBounds()
  -- Repeated updates reuse widgets and the existing single pulse.
  local allocated=count(s.widgets)
  for _=1,120 do s.advance(500) end
  equal(count(s.widgets),allocated,'HUD refresh must not accumulate widgets');equal(count(s.events),1,'HUD must not create another timer chain')
  s.map:setPosition({x=300,y=80});s.advance(500);equal(stats:getPosition().x,308,'default HUD placement follows the map')
  s.map:setSize({width=500,height=400});s.advance(500)
  assert(skills:getPosition().y>=stats:getPosition().y+stats:getSize().height,'small maps stack without overlapping')
  checkBounds()
  h.x=9999;h.y=9999;h.skillRight=9999;h.skillTop=9999;s.advance(500);checkBounds()
  equal(stats:getPosition().x,308,'saved offsets must not change the standard placement')
  equal(stats:getPosition().y,88)
  h.x=nil;h.y=nil;h.general=false;h.damage=false;h.healing=false;h.skills=false;s.advance(500)
  assert(not layer:isVisible(),'empty HUD must be hidden')
  h.general=true;h.skills=true;h.enabled=false;s.advance(500);assert(not layer:isVisible(),'disabled HUD stays hidden')
  h.enabled=true;h.general=true;h.active=true
  c.storage.elfbot.hotkeys={{key='F2',script='auto 200 say "test"',enabled=true}}
  c.storage.elfbot.hotkeysEnabled=true;c.saySpell=function() end;e.reload();e.jobs[1].active=true
  c.storage.elfbot.botEnabled=true;e.paused=false;s.advance(500);includes(stats,'Active scripts');includes(stats,'F2')
  c.storage.elfbot.hotkeysEnabled=false;s.advance(500);assert(not text(stats):find('Active scripts',1,true),'disabled hotkey category must not be shown as active')
  c.storage.elfbot.healing.enabled=true;c.storage.elfbot.healing.hiEnabled=true;c.storage.elfbot.healing.hiHealth=90
  h.healing=true;s.advance(500);includes(stats,'Healing: ON');includes(stats,'Hi 90%')
  c.exp=function() return 1e30 end;s.advance(500);includes(stats,'XP: waiting for valid character statistics')
  -- A large timer list and long names still fit, with a bounded reusable row pool.
  h.spellTimers=true
  for i=1,100 do e.spellTimers[string.rep('Long spell name ',8)..i]=c.now+100000 end
  s.advance(500);checkBounds();assert(#stats:getChildren()<=32,'HUD row pool is bounded');includes(stats,'more')
  local menu=s.getWidget('ElfBot OTC v.1');local hudButton
  for _,v in ipairs(menu:getChildren()) do if v:getText()=='HUD' then hudButton=v end end
  hudButton.onClick();local config=s.root:getFocusedChild()
  for _,v in ipairs(config:getChildren()) do if v:getStyleName()=='ElfBotCheck' then
    assert(v.textWrap and v:getTextSize().height<=v:getSize().height,'HUD option clipped: '..v:getText())
  end end
  assert(not s.getWidget('HUD map offset X / Y:'),'Classic HUD must not require offset settings')
  assert(not s.getWidget('Reset positions'),'Classic positioning is automatic')
  h.skills=false;h.spellTimers=false;s.advance(500);assert(not skills:isVisible(),'skills option hides the block')
  latest.ui.hide();assert(not layer:isVisible());equal(other.text,'Previous label','hide restores owned creature text')
  s.advance(500);assert(not layer:isVisible(),'late tick cannot reopen a hidden HUD')
  latest.ui.show();assert(layer:isVisible(),'HUD must reopen after its hidden parent is shown again')
  env.terminate();equal(count(s.events),0);equal(s.connectionCount(),0)
  for v in pairs(s.widgets) do assert(not v.elfWidget and not v:getStyleName():find('ElfBotHud'),'HUD ownership cleaned up') end
end

print('ElfBot integration, bounded history, callbacks, Classic HUD and lifecycle: OK')
