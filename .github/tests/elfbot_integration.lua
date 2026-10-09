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
local scripts={'language','session','history','icon_import','settings_import','telemetry','legacy','engine','autonomous','original_dialogs','interface','runtime'}
for _,name in ipairs(scripts) do assert(loadfile('mods/game_elfbot/'..name..'.lua')) end
local styles='\n'..read('mods/game_elfbot/interface.otui'):gsub('\r\n','\n')
local function styleProperty(style,property)
  local block=styles:match('\n'..style..' <[^\n]+\n(.-)\n\n') or ''
  return block:match('\n  '..property..': ([^\n]+)')
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
  function methods:isVisible() return self.visible end
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
    if self.parent and self.anchored then
      local p=self.parent:getPaddingRect();return {x=p.x+(self.marginLeft or 0),y=p.y+(self.marginTop or 0)}
    elseif self.parent and self.parent.style=='ElfBotList' then
      local p=self.parent:getPaddingRect();return {x=p.x,y=p.y+(self.parent:getChildIndex(self)-1)*20}
    end
    return self.position or {x=0,y=0}
  end
  function methods:getSize() return self.size or {width=400,height=300} end
  function methods:getText() return self.text or '' end
  function methods:setText(text) self.text=tostring(text) end
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
  function methods:addAnchor() self.anchored=true end
  function methods:setMarginLeft(value) self.marginLeft=value end
  function methods:setPhantom(value) self.phantom=value end
  function methods:setEnabled(value) self.enabled=value end
  function methods:setTextWrap(value) self.textWrap=value end
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
  function methods:setCurrentOption(value) self.option=value end
  function methods:getCurrentOption() return {text=self.option} end
  function methods:setCurrentIndex(index) self.option=(self.options or {})[index] end
  function methods:clearOptions() self.options={};self.option=nil end
  function methods:setValue(value) self.value=value end
  function methods:getValue() return self.value or 0 end
  for _,name in ipairs({'setTooltip','setColor','setBackgroundColor','setVerticalScrollBar','setId','setBorderWidth','setVirtual','setItemId','setMinimumAmbientLight','unlockVisibleFloor','setLimitVisibleRange','setup','setMinimum','setMaximum','setStep'}) do
    methods[name]=function() end
  end
  local function widget(style,parent)
    local w=setmetatable({style=style,children={},parent=parent,visible=true,
      size=style=='ElfBotRow' and {width=parent:getSize().width,height=20} or nil,
      padding=tonumber(styleProperty(style,'padding')) or (style=='ElfBotGroup' and 8 or 0),
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
  function player:isLocalPlayer() return true end
  function player:isAutoWalking() return false end
  function player:getExperience() return 1000 end
  function player:getLevel() return 10 end
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
  local state={env=env,bot=bot,events=events,widgets=widgets,warnings=warnings,root=root,player=player,files=files}
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
    env.setEnabled(false);assert(not env.isRunning());assert(not s.tileEnabled());equal(count(s.events),0)
    env.terminate();equal(s.connectionCount(),0);equal(count(s.widgets),initialWidgets,'all ElfBot widgets released')
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
  local s=fixture();local env=s.env;env.init();env.setEnabled(true)
  local executor
  local execute=s.bot.executeBot
  s.bot.executeBot=function(...) executor=execute(...);return executor end
  env.setEnabled(false);env.setEnabled(true)
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

print('ElfBot integration, bounded history, callbacks and lifecycle: OK')
