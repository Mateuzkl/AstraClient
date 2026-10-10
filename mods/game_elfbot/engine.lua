-- All client interaction is through the current game_bot execution context.
function createElfBotEngine(c, data)
  local L=ElfBotLanguage
  local e={context=c,data=data,commands={},jobs={},variables={},status='Ready',actionJobs={}}
  e.session=c.elfSession or ElfBotSession.new(c.now,c.name())
  function e.getSessionStats() return e.session.update(c.now,c.exp(),c.name(),c.level()) end
  e.getSessionStats()
  data.hotkeys=data.hotkeys or {};data.shortkeys=data.shortkeys or {};data.persistent=data.persistent or ''
  if data.hotkeysEnabled==nil then data.hotkeysEnabled=true end
  if data.shortkeysEnabled==nil then data.shortkeysEnabled=true end
  data.symbol=data.symbol or '~';data.routes=data.routes or {};data.profiles=data.profiles or {}
  data.items=data.items or {mana=268,smana=237,gmana=238,gsmana=7642,health=266,shealth=236,ghealth=239,uhealth=7643,gshealth=7642,uh=3160,sd=3155,hmm=3198,lmm=3174,icicle=3158,paralyze=3165,explo=3200}
  data.rope=data.rope or 3003;data.shovel=data.shovel or 3457
  local function join(a,first) local out={};for i=first or 1,#a do out[#out+1]=tostring(a[i]) end;return table.concat(out,' ') end
  local function number(v) local n=assert(tonumber(v),'Expected a number, received '..tostring(v));return n end
  local function boolean(v) if v=='on' then return true elseif v=='off' then return false end;return L.truth(v) end
  local function player() return assert(c.g_game.getLocalPlayer(),'Not connected') end
  local function target(value)
    if e.getCreature then return e.getCreature(value) end
    if value==nil or tostring(value):lower()=='target' then return assert(c.g_game.getAttackingCreature(),'No current target') end
    if tostring(value):lower()=='self' then return player() end
    return assert(tonumber(value) and c.getCreatureById(tonumber(value)) or c.getCreatureByName(tostring(value)),'Creature not found: '..tostring(value))
  end
  local function bot(name)
    local b=c[name]
    assert(type(b)=='table' and type(b.setOn)=='function' and type(b.setOff)=='function',name..' controller is unavailable')
    return b
  end
  local function say(text) return c.saySpell(text,1000) end
  local itemNames={['gold coin']=3031,['platinum coin']=3035,['crystal coin']=3043,
    ['ultimate healing rune']=data.items.uh,['sudden death rune']=data.items.sd,
    ['mana potion']=data.items.mana,['strong mana potion']=data.items.smana,['great mana potion']=data.items.gmana,
    ['health potion']=data.items.health,['strong health potion']=data.items.shealth,['great health potion']=data.items.ghealth,
    ['ultimate health potion']=data.items.uhealth,['great spirit potion']=data.items.gsmana}
  function e.itemId(value)
    local id=tonumber(value)
    if not id then
      local name=tostring(value):lower()
      -- NPC offers provide server-specific names/IDs; retain them after trade closes.
      if not itemNames[name] then
        for _,method in ipairs({'getBuyItems','getSellItems'}) do
          for _,offer in ipairs(c.NPC[method]()) do if type(offer.name)=='string' then itemNames[offer.name:lower()]=offer.id end end
        end
      end
      id=itemNames[name]
    end
    assert(id and id%1==0 and id>0 and id<=65535,'Unknown item name or invalid ID: '..tostring(value))
    return id
  end
  local function countItem(value)
    local id=e.itemId(value)
    local count=0
    for _,container in pairs(c.getContainers()) do
      for _,item in ipairs(container:getItems()) do if item:getId()==id then count=count+item:getCount() end end
    end
    for slot=1,10 do local item=player():getInventoryItem(slot);if item and item:getId()==id then count=count+item:getCount() end end
    return count
  end
  local scalar={hp='hp',maxhp='maxhp',hppc='hppercent',mp='mana',maxmp='maxmana',mppc='manapercent',cap='freecap',level='level',mlevel='mlevel',exp='exp',soul='soul',stamina='stamina',posx='posx',posy='posy',posz='posz',ping='ping',name='name'}
  local flags={hasted='hasHaste',paralyzed='isParalyzed',inpz='isInPz',manashielded='hasManaShield',battlesign='hasSwords',pzlocked='isPzLocked'}
  local slots={headslot=1,ammySlot=2,ammyslot=2,neckslot=2,bpslot=3,bodyslot=4,rhandslot=5,lhandslot=6,legsslot=7,bootsslot=8,ringslot=9,beltslot=10}
  function e.resolve(name)
    if e.variables[name]~=nil then return e.variables[name] end
    local key=name:lower()
    local aliases={hppercent='hppc',manapercent='mppc',mana='mp',maxmana='maxmp',hpmax='maxhp',manamax='maxmp',isattacking='attacking'}
    key=aliases[key] or key
    if key=='deltatime' or key=='deltatimems' or key=='expgained' or key=='exph' then
      local stats=e.getSessionStats()
      if key=='deltatime' then return stats.elapsed elseif key=='deltatimems' then return stats.elapsedMs
      elseif key=='expgained' then return stats.gained else return stats.perHour end
    end
    if key=='hpmissing' then return c.maxhp()-c.hp() end
    if key=='mpmissing' then return c.maxmana()-c.mana() end
    if scalar[key] then return c[scalar[key]]() end
    if flags[key] then return c[flags[key]]() and 1 or 0 end
    if key=='connected' then return c.g_game.isOnline() and 1 or 0 end
    if key=='attacking' then return c.g_game.getAttackingCreature() and 1 or 0 end
    if key=='targetingon' then return c.TargetBot and c.TargetBot.isOn() and 1 or 0 end
    if key=='caveboton' or key=='waypointson' then return c.CaveBot and c.CaveBot.isOn() and 1 or 0 end
    local kind,member=key:match('^([%w_]+)%.(.+)$')
    if kind=='itemcount' then return countItem(member) end
    if kind=='playersaround' or kind=='monstersaround' then
      local distance=number(member);local n=0;local origin=c.pos()
      for _,spec in ipairs(c.getSpectators()) do
        if spec~=player() and spec:getPosition().z==origin.z and c.getDistanceBetween(origin,spec:getPosition())<=distance and ((kind=='playersaround' and spec:isPlayer()) or (kind=='monstersaround' and spec:isMonster())) then n=n+1 end
      end
      return n
    end
    if kind=='self' or kind=='target' then
      local creature=kind=='self' and player() or c.g_game.getAttackingCreature()
      if not creature then return member=='name' and '' or 0 end
      if member=='id' then return creature:getId() elseif member=='name' then return creature:getName()
      elseif member=='hppc' then return creature:getHealthPercent() elseif member=='skull' then return creature:getSkull()
      elseif member=='distance' then return c.getDistanceBetween(c.pos(),creature:getPosition())
      elseif member=='isshootable' then return creature:canShoot() and 1 or 0
      elseif member=='posx' or member=='posy' or member=='posz' then return creature:getPosition()[member:sub(4)] end
    end
    if slots[kind] then
      local item=player():getInventoryItem(slots[kind]);if not item then return 0 end
      if member=='id' then return item:getId() elseif member=='count' then return item:getCount() end
    end
    if kind=='skill' then
      local skills={fist=0,club=1,sword=2,axe=3,distance=4,shielding=5,fishing=6};assert(skills[member],'Unknown skill');return player():getSkillLevel(skills[member])
    end
    -- User variables start at zero, as in ElfBot.
    return 0
  end
  local function assign(name,value) e.variables[name]=value end
  local commands=e.commands
  commands.say=function(a) return say(join(a)) end
  commands.npcsay=function(a) c.NPC.say(join(a)) end
  commands.gamesay=function(a) c.talkChannel(7,join(a)) end
  commands.guildsay=function(a) c.talkChannel(0,join(a)) end
  commands.tradesay=function(a) c.talkChannel(5,join(a)) end
  commands.statusmessage=function(a) e.status=join(a);c.info(e.status) end
  commands.log=commands.statusmessage
  commands.setcaption=function(a) local text=join(a);e.caption=text~='' and text or nil end
  commands.displaytext=function(a,env) env.text=join(a);e.displays=e.displays or {};local p=env.position or {8,130};e.displays[env.job or env]={text=env.text,x=p[1],y=p[2],color=env.color,expires=c.now+2000} end
  commands.listas=function(a,env) env.label=join(a) end
  commands.dontlist=function(a,env) env.hidden=true end
  commands.setcolor=function(a,env) local color={};for i=1,3 do local n=number(a[i]);assert(n>=0 and n<=255,'Color channels must be 0..255');color[i]=math.floor(n) end;env.color=color end
  commands.setpos=function(a,env) env.position={number(a[1]),number(a[2])} end
  commands.haste=function() if not c.hasHaste() or c.isParalyzed() then say('utani hur') end end
  commands.stronghaste=function() if not c.hasHaste() or c.isParalyzed() then say('utani gran hur') end end
  commands.manashield=function() if not c.hasManaShield() then say('utamo vita') end end
  commands.goinvisible=function() if not player():isInvisible() then say('utana vid') end end
  commands.healparalysis=function(a) if c.isParalyzed() then say(#a>0 and join(a) or 'exura') end end
  commands.attack=function(a) local t=target(#a>0 and a[1] or 'target');if t then c.attack(t) end end
  commands.follow=function(a) local t=target(#a>0 and a[1] or 'target');if t then c.follow(t) end end
  commands.stopattack=function() c.cancelAttackAndFollow() end
  commands.logout=function() c.safeLogout() end
  commands.settargeting=function(a) local b=bot('TargetBot');if boolean(a[1]) then b.setOn() else b.setOff() end end
  commands.setcavebot=function(a) local b=bot('CaveBot');if boolean(a[1]) then b.setOn() else b.setOff();e.actionJobs={} end end
  commands.setfollowwaypoints=commands.setcavebot
  commands.gotolabel=function(a,env) assert(bot('CaveBot').gotoLabel(join(a)),'Waypoint label not found: '..join(a));env.stop=true end
  commands.skip=function(_,env) env.stop=true end
  commands.loadcavebot=function(a) local b=bot('CaveBot');assert(b.setCurrentProfile,'Profile switching is unavailable');b.setCurrentProfile(join(a)) end
  commands.countitems=function(a) e.variables.count=countItem(a[1]) end
  commands.countitemsvisible=commands.countitems
  commands.useitem=function(a) c.use(number(a[1])) end
  commands.useoncreature=function(a) local t=target(a[2]);if t then c.useWith(number(a[1]),t) end end
  commands.openbpitem=function() local item=player():getInventoryItem(3);if item then c.g_game.open(item) end end
  commands.openbeltitem=function() local item=player():getInventoryItem(10);if item then c.g_game.open(item) end end
  commands.usegroundxyz=function(a) local tile=c.g_map.getTile({x=number(a[1]),y=number(a[2]),z=number(a[3])});assert(tile and tile:getTopUseThing(),'Ground tile unavailable');c.use(tile:getTopUseThing()) end
  commands.useongroundxyz=function(a) local tile=c.g_map.getTile({x=number(a[2]),y=number(a[3]),z=number(a[4])});assert(tile and tile:getTopUseThing(),'Ground tile unavailable');c.useWith(number(a[1]),tile:getTopUseThing()) end
  commands.useoninventoryitem=function(a) local item=c.findItem(number(a[2]));assert(item,'Inventory item not found');c.useWith(number(a[1]),item) end
  commands.buyitems=function(a) c.NPC.buy(e.itemId(a[1]),number(a[2]),false,true) end
  commands.buyitemsupto=function(a)
    local id=e.itemId(a[1]);local wanted=number(a[2]);assert(wanted>=0 and wanted%1==0 and wanted<=1000000,'Invalid purchase target')
    local owned=a[3]~=nil and number(a[3]) or countItem(id)
    assert(owned>=0 and owned%1==0,'Invalid owned item count')
    local missing=wanted-owned
    if missing>0 then c.NPC.buy(id,math.min(100,missing),false,true) end
  end
  commands.sellitems=function(a) c.g_game.sellItem(Item.create(number(a[1])),number(a[2]),0,true) end
  commands.setattackmode=function(a) c.g_game.setFightMode(number(a[1]));if a[2] then c.g_game.setChaseMode(number(a[2])) end end
  local directions={turnn=0,turne=1,turns=2,turnw=3,walkn=0,walke=1,walks=2,walkw=3,walkne=4,walkse=5,walksw=6,walknw=7}
  for name,direction in pairs(directions) do local dir=direction;local turn=name:sub(1,4)=='turn';commands[name]=function() if turn then c.turn(dir) else c.walk(dir) end end end
  local equips={equiphead=1,equiphelm=1,equipammy=2,equipamulet=2,equipbody=4,equiprhand=5,equiplhand=6,equiplegs=7,equipboots=8,equipring=9,equipbelt=10}
  for name,slot in pairs(equips) do local destination=slot;commands[name]=function(a)
    local id=number(a[1]);local current=player():getInventoryItem(destination)
    if not current or current:getId()~=id then local item=c.findItem(id);if item then c.moveToSlot(item,destination) end end
  end end
  commands.fastequipammy=commands.equipammy;commands.fastequipring=commands.equipring
  for _,name in ipairs({'mana','smana','gmana','gsmana'}) do local key=name;commands[key]=function(a) local t=target(a[1] or 'self');if t then c.useWith(number(data.items[key]),t) end end end
  for _,name in ipairs({'health','shealth','ghealth','uhealth','gshealth','uhpc'}) do local key=name;commands[key]=function(a)
    local creature=target(a[2] or 'self');if creature and creature:getHealthPercent()<=number(a[1]) then c.useWith(number(data.items[key=='uhpc' and 'uh' or key]),creature) end
  end end
  for _,name in ipairs({'uh','sd','hmm','lmm','icicle','paralyze','explo'}) do local key=name;commands[key]=function(a) local t=target(a[1] or 'target');if t then c.useWith(number(data.items[key]),t) end end end
  commands.sio=function(a) local creature=target(a[2]);if creature and creature:getHealthPercent()<=number(a[1]) then say('exura sio "'..creature:getName()) end end
  commands.eatfood=function()
    for _,id in ipairs({3600,3577,3582,3583,3584,3585,3586,3587,3588,3589,3590,3591,3592,3593,3594,3595}) do local item=c.findItem(id);if item then c.use(item);return end end
  end
  commands.playsound=function(a) local name=join(a);assert(not name:find('..',1,true),'Invalid sound path');if name:sub(1,1)~='/' then name=name:gsub('%.wav$','.ogg');if not name:find('%.') then name=name..'.ogg' end end;local path=name:sub(1,1)=='/' and name or '/game_elfbot/sounds/'..name;c.playSound(path) end
  commands.flash=function() if g_window.flash then g_window.flash() end end
  commands.exivatarget=function() say('exiva "'..target('target'):getName()) end
  commands.cast=commands.say
  commands.exiva=function(a) say('exiva "'..join(a)) end
  commands.cancelattack=commands.stopattack
  commands.stopfollow=commands.stopattack
  commands.stopwalking=function() c.g_game.stop() end
  commands.look=function(a) local t=target(a[1]);if t then c.g_game.look(t) end end
  commands.closewindows=function() for _,box in pairs(c.getContainers()) do c.g_game.close(box) end end
  commands.setsafe=function(a) c.g_game.setSafeFight(boolean(a[1])) end
  commands.dropitems=function(a)
    local item=assert(c.findItem(number(a[1])),'Item not found');c.g_game.move(item,c.pos(),math.min(item:getCount(),a[2] and number(a[2]) or item:getCount()))
  end
  commands.moveitems=function(a)
    local item=assert(c.findItem(number(a[1])),'Item not found');local box=assert(c.getContainers()[number(a[2])],'Container not open')
    c.g_game.move(item,box:getSlotPosition(box:getItemsCount()),math.min(item:getCount(),a[3] and number(a[3]) or item:getCount()))
  end
  commands.inviteparty=function(a) local t=target(a[1]);if t then c.g_game.partyInvite(t:getId()) end end
  commands.leaveparty=function() c.g_game.partyLeave() end
  commands.setsharedexp=function(a) c.g_game.partyShareExperience(boolean(a[1])) end
  commands.setaimbot=function(a) data.aimbot.enabled=boolean(a[1]) end
  commands.sethud=function(a) data.hud.enabled=boolean(a[1]) end
  commands.seticons=function(a) data.iconsEnabled=boolean(a[1]) end
  commands.seticonactive=function(a)
    assert(a[1]~=nil and a[2]~=nil,'Expected seticonactive "icon name" on/off (or 1/0)')
    local name=tostring(a[1]):lower()
    for _,row in ipairs(data.icons or {}) do
      if tostring(row.name):lower()==name then
        -- Visual state is independent of the icon's repeating click script.
        row.active=boolean(a[2]);e.iconsDirty=true;return
      end
    end
    error('Icon not found: '..tostring(a[1]))
  end
  function e.compile(source) return L.compile(source,commands) end
  function e.environment(job)
    local env={commands=commands,locals={},label=job and job.label,job=job,iterate=e.iterate,predicate=e.predicate}
    env.resolve=function(name)
      if env.locals[name]~=nil then return env.locals[name] end
      local kind,member=name:match('^([^%.]+)%.(.+)$')
      if kind and env.locals[kind]~=nil then return e.creatureField(env.locals[kind],member) end
      return e.resolve(name)
    end
    env.assign=function(name,value) if env.locals[name]~=nil then env.locals[name]=value else assign(name,value) end end
    return env
  end
  function e.start(job)
    job.env=e.environment(job);job.thread=L.start(job.program,job.env);job.wake=c.now
  end
  function e.advance(job)
    if not job.thread then e.start(job) end
    if c.now<(job.wake or 0) then return false end
    local done,detail=L.resume(job.thread)
    if done==nil then job.thread=nil;job.failed=true;job.error=tostring(detail);e.status=job.error;c.warn('ElfBot: '..job.error);return nil end
    if done then job.thread=nil;job.nextRun=c.now+(job.program.interval or 0);return true end
    job.wake=c.now+detail;return false
  end
  function e.reload()
    e.paused=false
    e.jobs={};e.actionJobs={}
    local function add(row,kind)
      local ok,program=pcall(e.compile,row.script or '')
      local job={row=row,kind=kind,program=ok and program or nil,failed=not ok,error=not ok and tostring(program) or nil,active=kind=='persistent' or (row.enabled and not row.key)}
      if row.key=='' then job.active=kind~='shortkey' and row.enabled end
      if kind=='shortkey' then job.active=false end
      e.jobs[#e.jobs+1]=job
      if not ok then e.status=job.error end
    end
    for _,row in ipairs(data.hotkeys) do add(row,'hotkey') end
    for _,row in ipairs(data.shortkeys) do add(row,'shortkey') end
    for line in data.persistent:gmatch('[^\r\n]+') do if line:match('%S') then add({script=line,enabled=true},'persistent') end end
    for line in (data.caveKeys or ''):gmatch('[^\r\n]+') do if line:match('%S') then add({script=line,enabled=true},'cave');e.jobs[#e.jobs].active=true end end
    if e.onReload then e.onReload() end
  end
  function e.tick()
    if data.botEnabled==false then e.paused=true;return end
    if e.paused then return end
    for _,job in ipairs(e.jobs) do
      local allowed=job.kind=='persistent' or (job.kind=='hotkey' and data.hotkeysEnabled) or (job.kind=='shortkey' and data.shortkeysEnabled) or (job.kind=='cave' and c.CaveBot and c.CaveBot.isOn())
      if not allowed or not job.row.enabled then job.thread=nil;job.nextRun=0
      elseif not job.failed and job.active and c.now>=(job.nextRun or 0) then
        local done=e.advance(job)
        if done and not job.program.interval then job.active=false end
      end
    end
  end
    -- One-shot actions must not accumulate indefinitely during targeting/combo ticks.
  local rawJobTick=e.tick
  e.tick=function()
    rawJobTick()
    for index=#e.jobs,1,-1 do local job=e.jobs[index];if job.transient and (job.failed or not job.active) and not job.thread then table.remove(e.jobs,index) end end
  end
  function e.key(key,held)
    if data.botEnabled==false or e.paused or type(key)~='string' or key=='' then return false end
    local matched=false
    for _,job in ipairs(e.jobs) do
      -- An optional toggle is an additional shortcut, not a replacement for the
      -- primary key displayed (and captured) in the hotkey list.
      local binding=job.kind=='hotkey' and job.row.key
      local toggle=job.row.toggleKey
      local matches=type(binding)=='string' and binding:lower()==key:lower() or type(toggle)=='string' and toggle:lower()==key:lower()
      if ((job.kind=='hotkey' and data.hotkeysEnabled) or (job.kind=='shortkey' and data.shortkeysEnabled)) and job.row.enabled and not job.failed and matches then
        matched=true
        if job.program.interval then if not held then job.active=not job.active;job.thread=nil;job.nextRun=0;e.status=(job.row.key or key)..(job.active and ' enabled' or ' cancelled') end
        elseif not job.thread then job.active=true;job.nextRun=0 end
      end
    end
    return matched
  end
  function e.shortkey(text)
    if data.botEnabled==false or e.paused then return false end
    if not data.shortkeysEnabled or data.symbol=='' or text:sub(1,#data.symbol)~=data.symbol then return false end
    local command=text:sub(#data.symbol+1):lower():match('^%s*(.-)%s*$')
    for _,job in ipairs(e.jobs) do
      if job.kind=='shortkey' and tostring(job.row.key):lower()==command then
        if not job.row.enabled or job.failed then e.status=job.error or 'Shortkey disabled';return true end
        if job.program.interval then job.active=not job.active;job.thread=nil else job.active=true end
        job.nextRun=0;e.status=tostring(job.row.key)..(job.active and ' enabled' or ' cancelled');return true
      end
    end
    return false
  end
  function e.runProgram(program)
    if #e.jobs>=512 then return nil,'Too many active ElfBot scripts' end
    local job={program=program,row={enabled=true},kind='persistent',active=true,transient=true};e.jobs[#e.jobs+1]=job;return job
  end
  function e.run(source)
    local ok,program=pcall(e.compile,source);if not ok then return nil,program end
    return e.runProgram(program)
  end
  function e.route()
    local b=bot('CaveBot');assert(b.actionList and b.registerAction,'This CaveBot does not support action extensions')
    if b.getCurrentProfile and not b.getCurrentProfile() then
      assert(c.Config and c.Config.save,'Create a CaveBot profile first')
      local name='ElfBot_OTC_v1'
      c.Config.save('cavebot_configs',name,{},'cfg')
      c.storage._configs.cavebot_configs.selected=name
      b.setOn();b.setOff()
    end
    return b
  end
  function e.registerCaveActions()
    if not c.CaveBot or not c.CaveBot.registerAction then return end
    local b=c.CaveBot
    local function delegate(name,value,retries,previous) local a=assert(b.Actions[name],'CaveBot action unavailable: '..name);return a.callback(value,retries,previous) end
    for _,name in ipairs({'stand','node','walk','lure'}) do local kind=name
      b.registerAction('elf'..kind,'#87c99e',function(value,retries,previous)
        local precision=kind=='node' and (tonumber(data.nodeRadius) or 1) or 0
        local result=delegate('goto',value..','..precision,retries,previous)
        if kind=='lure' and result==true and c.g_game.getAttackingCreature() then return 'retry' end
        return result
      end)
    end
    b.registerAction('elfrope','#d9b57c',function(value,retries,previous) if b.Actions.tool then return delegate('tool','rope,'..data.rope..','..value,retries,previous) end;return delegate('usewith',data.rope..','..value,retries,previous) end)
    b.registerAction('elfshovel','#d9b57c',function(value,retries,previous) if b.Actions.tool then return delegate('tool','shovel,'..data.shovel..','..value,retries,previous) end;return delegate('usewith',data.shovel..','..value,retries,previous) end)
    b.registerAction('elfladder','#d9b57c',function(value,retries,previous) return delegate('use',value,retries,previous) end)
    b.registerAction('elfaction','#e7a0cc',function(value,retries)
      local widget=b.actionList:getFocusedChild()
      if widget and widget.actionPosition then
        local p=widget.actionPosition;local current=c.pos()
        if current.z~=p.z or current.x~=p.x or current.y~=p.y then return delegate('goto',p.x..','..p.y..','..p.z..',0',retries,true) end
      end
      local job=e.actionJobs[widget]
      if not job or retries==0 or job.source~=value then
        local ok,program=pcall(e.compile,value)
        if not ok then e.status=tostring(program);c.warn('ElfBot Action: '..e.status);b.setOff();return false end
        -- A positioned action runs one pass, including commands written with auto.
        program.interval=nil
        job={program=program,source=value};e.actionJobs[widget]=job
      end
      local done=e.advance(job)
      if done==nil then b.setOff();e.actionJobs[widget]=nil;return false end
      if done then e.actionJobs[widget]=nil;return true end
      return 'retry'
    end)
  end
  prepareElfBotTelemetry(e,c,data);prepareElfBotLegacy(e,c,data)
  e.registerCaveActions();e.reload()
  return e
end
