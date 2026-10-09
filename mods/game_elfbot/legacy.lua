-- Compatibility for combat, HUD and the supplied original icon commands.
function prepareElfBotLegacy(e,c,d)
  local cmd=e.commands
  local function num(v) local n=assert(tonumber(v),'Expected a numeric argument');return n end
  local function join(a,n) local out={};for i=n or 1,#a do out[#out+1]=tostring(a[i]) end;return table.concat(out,' ') end
  local function listed(kind,name)
    if e.listContains then return e.listContains(kind,name) end
    for line in ((d.lists or {})[kind] or ''):gmatch('[^\r\n,;]+') do if line:match('^%s*(.-)%s*$'):lower()==name:lower() then return true end end
    return false
  end
  local function creature(v)
    if (type(v)=='table' or type(v)=='userdata') and v.getName then return v end
    local name=tostring(v or 'target'):lower()
    if name=='self' then return c.player elseif name=='target' then return c.g_game.getAttackingCreature() end
    if name=='friend' or name=='subfriend' then
      local best
      for _,s in ipairs(c.getSpectators()) do if s:isPlayer() and s~=c.player and listed(name=='friend' and 'friends' or 'subfriends',s:getName()) and s:canShoot() then
        if not best or s:getHealthPercent()<best:getHealthPercent() then best=s end
      end end
      return best
    end
    return tonumber(v) and c.getCreatureById(tonumber(v)) or c.getCreatureByName(tostring(v))
  end
  e.getCreature=creature
  function e.creatureField(s,member)
    if not s then return (member=='name' or member=='guild') and '' or 0 end
    local p=s:getPosition();local self=c.pos();local info=e.playerInfo and e.playerInfo(s) or {}
    if member=='id' then return s:getId() elseif member=='name' then return s:getName()
    elseif member=='hppc' then return s:getHealthPercent() elseif member=='distance' then return c.getDistanceBetween(self,p)
    elseif member=='posx' or member=='posy' or member=='posz' then return p[member:sub(4)]
    elseif member=='distx' then return math.abs(p.x-self.x) elseif member=='disty' then return math.abs(p.y-self.y)
    elseif member=='isenemy' then return listed('enemies',s:getName()) and 1 or 0
    elseif member=='issubenemy' then return listed('subenemies',s:getName()) and 1 or 0
    elseif member=='isfriend' then return listed('friends',s:getName()) and 1 or 0
    elseif member=='issubfriend' then return listed('subfriends',s:getName()) and 1 or 0
    elseif member=='isleader' then return listed('leaders',s:getName()) and 1 or 0
    elseif member=='isshootable' or member=='canshoot' then return s:canShoot() and 1 or 0
    elseif member=='isonscreen' then return p and p.z==self.z and c.getDistanceBetween(self,p)<=9 and 1 or 0
    elseif member=='isplayer' then return s:isPlayer() and 1 or 0 elseif member=='ismonster' then return s:isMonster() and 1 or 0
    elseif member=='isnpc' then return s.isNpc and s:isNpc() and 1 or 0
    elseif member=='speed' then return s.getSpeed and s:getSpeed() or 0 elseif member=='dir' then return s.getDirection and s:getDirection() or 0
    elseif member=='skull' then return s:getSkull() elseif member=='party' then return s.getShield and s:getShield() or 0
    elseif member=='outfit' then return s.getOutfit and s:getOutfit().type or 0
    elseif member=='hp' then return s==c.player and c.hp() or 0 elseif member=='maxhp' then return s==c.player and c.maxhp() or 0
    elseif member=='mp' then return info.mana or 0 elseif member=='maxmp' then return info.maxMana or 0
    elseif member=='mppc' then return info.manaPercent or 0 elseif member=='level' then return info.level or 0
    elseif member=='guild' then return info.guild or '' elseif member=='voc' or member=='vocation' then return info.vocation or 0
    elseif member=='priority' then return (d.relationPriorities or {})[s:getName():lower()] or 0
    elseif member=='haslookinfo' then return info.haslookinfo and 1 or 0
    elseif member=='ismage' or member=='isknight' or member=='ispaladin' or member=='issorcerer' or member=='isdruid' then
      local v=info.vocation and ((info.vocation-1)%4)+1 or 0
      return ((member=='ismage' and (v==1 or v==2)) or member=='isknight' and v==4 or member=='ispaladin' and v==3 or member=='issorcerer' and v==1 or member=='isdruid' and v==2) and 1 or 0
    end
    return 0
  end
  function e.iterate(kind)
    kind=tostring(kind):match('^%s*(.-)%s*$'):lower();local out={}
    for _,s in ipairs(c.getSpectators()) do if s~=c.player then
      local player=s:isPlayer();local enemy=listed('enemies',s:getName()) or listed('subenemies',s:getName())
      if kind=='screencreatures' or kind=='screenplayers' and player or kind=='shootableplayers' and player and s:canShoot() or kind=='screenenemies' and player and enemy or kind=='screenmonsters' and s:isMonster() then out[#out+1]=s end
    end end;return out
  end
  local rawResolve=e.resolve
  function e.resolve(name)
    if e.variables[name]~=nil then return e.variables[name] end
    local key=name:lower();local kind,member=key:match('^([^%.]+)%.(.+)$')
    if key=='self' or key=='target' or key=='friend' or key=='subfriend' then return creature(key) or 0 end
    if kind and (kind=='self' or kind=='target' or kind=='friend' or kind=='subfriend' or (type(e.variables[kind])=='table' or type(e.variables[kind])=='userdata')) then return e.creatureField(creature(e.variables[kind] or kind),member) end
    if kind=='formattime' or kind=='formatnum' then
      local v=member:sub(1,1)=='$' and e.resolve(member:sub(2)) or tonumber(member) or 0
      return kind=='formattime' and ElfBotSession.formatTime(v) or ElfBotSession.formatNumber(v)
    end
    if kind=='topitem' then
      local coords={};for value in member:gmatch('[^%.]+') do coords[#coords+1]=value:sub(1,1)=='$' and e.resolve(value:sub(2)) or tonumber(value) end
      local tile=c.g_map.getTile({x=coords[1],y=coords[2],z=coords[3]});local item=tile and tile:getTopUseThing();return item and item:getId() or 0
    end
    if kind=='curmsg' then return (e.currentMessage or {})[member] or 0 end
    if kind=='winitemcount' then local total=0;for _,box in pairs(c.getContainers()) do for _,item in ipairs(box:getItems()) do if item:getId()==tonumber(member) then total=total+item:getCount() end end end;return total end
    if kind=='key' then
      local vk=tonumber(member);local keys={[37]='Left',[38]='Up',[39]='Right',[40]='Down',[16]='Shift',[17]='Ctrl',[18]='Alt'}
      local keyName=keys[vk] or (vk and vk>=96 and vk<=105 and 'Numpad'..(vk-96)) or (vk and vk>=65 and vk<=90 and string.char(vk))
      return keyName and c.g_keyboard and c.g_keyboard.isKeyPressed(keyName) and 1 or 0
    end
    if key=='ctrl' or key=='alt' then local f=c.g_keyboard and c.g_keyboard[key=='ctrl' and 'isCtrlPressed' or 'isAltPressed'];return f and f() and 1 or 0 end
    if key=='drunk' then return c.isDrunk and c.isDrunk() and 1 or 0 elseif key=='poisoned' then return c.isPoisioned and c.isPoisioned() and 1 or 0 end
    if key=='followed' then return c.g_game.getFollowingCreature and c.g_game.getFollowingCreature() and 1 or 0 end
    if key=='safetoact' then
      local h=d.healing;return (not h or not h.enabled or c.hppercent()>(h.hiHealth or 90)) and c.now>=(e.healingBusyUntil or 0) and 1 or 0
    end
    if key=='mshieldtime' then return math.max(0,((e.buffExpires or {})['utamo vita'] or 0)-c.now) end
    if key=='standtime' then return c.now-(e.lastMove or c.now) elseif key=='idlerecvtime' then return c.now-(e.lastReceived or c.now) end
    if key=='systime' then return os.date('%H:%M:%S') elseif key=='sysdate' then return os.date('%A, %B %d %Y') end
    if key=='time' then return math.floor(c.now/1000) elseif key=='timems' then return c.now end
    if key=='screenleft' or key=='screenright' or key=='screentop' or key=='screenbottom' then local r=g_ui.getRootWidget():getPaddingRect();return key=='screenleft' and r.x or key=='screentop' and r.y or key=='screenright' and r.x+r.width or r.y+r.height end
    if key=='playersaround' or key=='pcount' then return rawResolve('playersaround.9') elseif key=='monstersaround' or key=='mcount' then return rawResolve('monstersaround.9') elseif key=='screencount' then return #c.getSpectators() end
    if kind=='friendcount' then local total=0;for _,s in ipairs(c.getSpectators()) do if s~=c.player and s:isPlayer() and (listed('friends',s:getName()) or listed('subfriends',s:getName())) and c.getDistanceBetween(c.pos(),s:getPosition())<=(tonumber(member) or 9) then total=total+1 end end;return total end
    local alerts={defaultmessage='lastDefault',privatemessage='lastPrivate',playerattacking='lastPlayerAttack'}
    if alerts[key] then local t=e[alerts[key]];return t and c.now-t<2000 and 1 or 0 end
    if key=='gm' then for _,s in ipairs(c.getSpectators()) do if s:getName():lower():match('^gm[%s_]') or s:getName():lower():match('^cm[%s_]') then return 1 end end;return 0 end
    if key=='hotkeys' then return d.hotkeysEnabled and 1 or 0 end
    local aliases={amuletslot='ammyslot',rigslot='ringslot'}
    if aliases[kind] then return rawResolve(aliases[kind]..'.'..member) end
    return rawResolve(name)
  end
  function e.predicate(name,args)
    local s=creature(args[1])
    if name=='isonscreen' then return s~=nil elseif name=='isnotonscreen' then return s==nil
    elseif name=='isattackedname' or name=='istargetname' then local t=name=='istargetname' and c.TargetBot.current or c.g_game.getAttackingCreature();return t and t:getName():lower()==tostring(args[1]):lower() end
    if name=='isdistance' or name=='isnotdistance' or name=='islocation' or name=='isnotlocation' then
      local b=c.CaveBot;local row=b and b.actionList:getChildByIndex(b.index);local x,y,z;if row then x,y,z=row.value:match('^(%d+),(%d+),(%d+)') end
      if not x then return name=='isnotdistance' or name=='isnotlocation' end
      local p={x=tonumber(x),y=tonumber(y),z=tonumber(z)};local near=p.z==c.posz() and c.getDistanceBetween(c.pos(),p)<=(tonumber(args[1]) or 0)
      return (name=='isnotdistance' or name=='isnotlocation') and not near or (name=='isdistance' or name=='islocation') and near
    end
    return false
  end
  function e.compileAttack(text)
    text=text:match('^%s*(.-)%s*$');local first=text:match('^(%S+)')
    if not first or cmd[first:lower()] or first=='auto' or first=='if' or first=='ifnot' or first=='safe' or first=='foreach' or text:find('[|{}]') then return e.compile(text) end
    -- An unrecognized plain phrase in the attack field is a user-entered spell.
    return e.compile('say '..string.format('%q',text))
  end
  function e.runAttack(text)
    local program=e.compileAttack(text);assert(not program.interval,'Attack action cannot contain auto')
    return e.runProgram(program)
  end
  for _,entry in ipairs({{'setcavebot','CaveBot'},{'setfollowwaypoints','CaveBot'},{'settargeting','TargetBot'}}) do local controller=entry[2];cmd[entry[1]]=function(a) local b=c[controller];local on=a[1]=='toggle' and not b.isOn() or a[1]=='on' or a[1]==1 or a[1]==true;if on then b.setOn() else b.setOff() end end end
  cmd.setaimbot=function(a) d.aimbot.enabled=a[1]=='toggle' and not d.aimbot.enabled or a[1]=='on' or a[1]==1 or a[1]==true end
  cmd.setautocombo=cmd.setaimbot
  cmd.uh=function(a) local s=creature(a[1]);if s and s:getHealthPercent()<95 then c.useWith(d.items.uh,s) end end
  cmd.autoheal=function() if c.hppercent()<95 then if e.healTick and d.healing and d.healing.enabled then e.nextHeal=0;e.healTick() else c.saySpell('exura',1000) end end end
  cmd.refillhealth=function(a) for _,s in ipairs(c.getSpectators()) do if s:isPlayer() and s~=c.player and (listed('friends',s:getName()) or listed('subfriends',s:getName())) and c.getDistanceBetween(c.pos(),s:getPosition())<=num(a[2]) then local info=e.playerInfo(s);if info.haslookinfo and s:getHealthPercent()<=num(a[1]) then c.useWith(d.items.uh,s);return end end end end
  cmd.refillmana=function(a) for _,s in ipairs(c.getSpectators()) do if s:isPlayer() and s~=c.player and (listed('friends',s:getName()) or listed('subfriends',s:getName())) and c.getDistanceBetween(c.pos(),s:getPosition())<=num(a[2]) then local info=e.playerInfo(s);if info.mana and info.mana<num(a[1]) then c.useWith(d.items.mana,s);return end end end end
  cmd.changestance=function(a) for _,rule in ipairs(d.targeting.monsters) do if rule.name:lower()==tostring(a[1]):lower() then local index=tonumber(a[3]) or 1;local setting=(rule.settings or {rule})[index];assert(setting,'Setting not found');local types={[0]='No Movement',[1]='Approach',[2]='Follow',[3]='Keep distance',[4]='Lure'};setting.stance=types[tonumber(a[2])] or tostring(a[2]);if a[4] then rule.count=num(a[4]) end;return end end;error('Monster rule not found') end
  cmd.setrelation=function(a)
    local relations={friend='friends',subfriend='subfriends',enemy='enemies',subenemy='subenemies',leader='leaders'};local name=tostring(a[1]);local kind=relations[tostring(a[2]):lower()];assert(kind,'Use friend/subfriend/enemy/subenemy/leader')
    for _,key in pairs(relations) do local rows={};for line in (d.lists[key] or ''):gmatch('[^\r\n]+') do if line:lower()~=name:lower() then rows[#rows+1]=line end end;d.lists[key]=table.concat(rows,'\n') end
    d.lists[kind]=(d.lists[kind] or '')..'\n'..name;d.relationPriorities=d.relationPriorities or {};d.relationPriorities[name:lower()]=a[3] and num(a[3]) or 0
  end
  cmd.exec=function(a,env) local p=e.compile(join(a));assert(not p.interval,'exec cannot contain auto');return env.exec(p) end
  cmd.turnoff=function(_,env) if env.job then env.job.active=false end;env.stop=true end
  for _,pair in ipairs({{'moven','walkn'},{'moves','walks'},{'movee','walke'},{'movew','walkw'},{'movene','walkne'},{'movenw','walknw'},{'movese','walkse'},{'movesw','walksw'}}) do cmd[pair[1]]=cmd[pair[2]] end
  cmd.moveto=function(a) c.autoWalk({x=num(a[1]),y=num(a[2]),z=num(a[3])},100,{precision=0}) end
  cmd.dashchase=function(a) local s=creature(a[1]);if s then c.autoWalk(s:getPosition(),30,{precision=1,ignoreLastCreature=true}) end end
  cmd.charge=function() if not c.hasHaste() then c.saySpell('utani tempo hur',1000) end end
  cmd.swiftfoot=function() if not c.hasHaste() then c.saySpell('utamo tempo san',1000) end end
  cmd.spyup=function() local map=modules.game_interface.getMapPanel();e.spyFloor=math.max(0,(e.spyFloor or c.posz())-1);map:lockVisibleFloor(e.spyFloor) end
  cmd.spydown=function() local map=modules.game_interface.getMapPanel();e.spyFloor=math.min(15,(e.spyFloor or c.posz())+1);map:lockVisibleFloor(e.spyFloor) end
  cmd.scrollview=function() local map=modules.game_interface.getMapPanel();if e.originalVisibleRange==nil then e.originalVisibleRange=not map.isLimitVisibleRangeEnabled or map:isLimitVisibleRangeEnabled() end;e.scrollView=not e.scrollView;if map.setLimitVisibleRange then map:setLimitVisibleRange(not e.scrollView) end end
  cmd.crosshair=function(a) local id=num(a[1]);local item=c.findItem(id)
    if not item then
      e.status='Crosshair: open the backpack containing item '..id
      if c.now>=(e.nextCrosshairNotice or 0) then e.nextCrosshairNotice=c.now+3000;c.info(e.status) end
      return
    end
    modules.game_interface.startUseWith(item) end
  cmd.pm=function(a) assert(a[1] and a[2],'pm needs player and message');c.g_game.talkPrivate(5,tostring(a[1]),join(a,2)) end
  cmd.exivalast=function() if e.lastExiva then c.saySpell('exiva "'..e.lastExiva,1000) end end
  cmd.exiva=function(a) e.lastExiva=join(a);c.saySpell('exiva "'..e.lastExiva,1000) end
  cmd.exivatarget=function() local s=creature('target');if s then cmd.exiva({s:getName()}) end end
  cmd.statusmessage=function(a) e.status=join(a);if modules.game_textmessage then modules.game_textmessage.displayStatusMessage(e.status) else c.info(e.status) end end
  cmd.listboxsetup=function(a)
    local id=num(a[1]);local b=e.listboxes[id] or {lines={}};b.x=num(a[2]);b.y=num(a[3]);b.maxLines=math.max(1,math.min(100,num(a[4])));b.lifetime=num(a[5]);b.direction=a[6];e.listboxes[id]=b
  end
  cmd.listboxaddline=function(a,env)
    local b=assert(e.listboxes[num(a[1])],'Create the listbox first');local serial=e.messageSerial or 0
    local messageBased=env and env.job and env.job.program.source:find('%$curmsg%.')
    if messageBased and b.lastSerial==serial then return end;if messageBased then b.lastSerial=serial end
    local color={};for i=1,3 do local n=num(a[i+1]);assert(n>=0 and n<=255,'Color channels must be 0..255');color[i]=math.floor(n) end
    b.lines[#b.lines+1]={text=join(a,5),color=color,time=c.now}
    while #b.lines>b.maxLines do table.remove(b.lines,1) end
  end
  cmd.seticontext=function(a) for _,row in ipairs(d.icons or {}) do if row.name:lower()==tostring(a[1]):lower() then row.extraText=join(a,2);e.iconsDirty=true;return end end;error('Icon not found: '..tostring(a[1])) end
  cmd.seticonactive=function(a)
    local duration=tonumber(a[2]);for _,row in ipairs(d.icons or {}) do if row.name:lower()==tostring(a[1]):lower() then
      e.iconFlashes=e.iconFlashes or {};local previous=row.active;local old=e.iconFlashes[row];if old then previous=old.previous end;e.iconFlashes[row]=duration and duration>1 and {expires=c.now+duration,previous=previous} or nil
      row.active=a[2]~='off' and a[2]~=0 and a[2]~='0' and a[2]~=false;e.iconsDirty=true;return
    end end;error('Icon not found: '..tostring(a[1]))
  end
  local function nearby(ids,distance)
    for dx=-distance,distance do for dy=-distance,distance do
      local p=c.pos();local tile=c.g_map.getTile({x=p.x+dx,y=p.y+dy,z=p.z})
      if tile and tile.getItems then for _,item in ipairs(tile:getItems()) do if ids[item:getId()] then return item,tile end end end
    end end
  end
  cmd.usegrounditem=function(a) local ids={};for _,id in ipairs(a) do ids[num(id)]=true end;local item=nearby(ids,1);if item then c.use(item) end end
  cmd.useongrounditem=function(a) local ids={};for i=2,#a do ids[num(a[i])]=true end;local item=nearby(ids,1);if item then c.useWith(num(a[1]),item) end end
  cmd.useongroundxyz=cmd.useongroundxyz
  cmd.opengrounditem=function(a) local item=nearby({[num(a[1])]=true},1);if item then c.g_game.open(item) end end
  cmd.opengroundxyz=function(a) local tile=c.g_map.getTile({x=num(a[1]),y=num(a[2]),z=num(a[3])});if tile then c.g_game.open(tile:getTopUseThing()) end end
  cmd.moveitemonground=function(a) local tile=c.g_map.getTile({x=num(a[1]),y=num(a[2]),z=num(a[3])});local item=tile and tile:getTopMoveThing();if item and item.getCount and (not item.isItem or item:isItem()) then c.g_game.move(item,{x=num(a[4]),y=num(a[5]),z=num(a[6])},item:getCount()) end end
  cmd.dropitems=function(a) for _,id in ipairs(a) do local item=c.findItem(num(id));if item then c.g_game.move(item,c.pos(),item:getCount());return end end end
  cmd.dropitemsxyzamount=function(a) local item=c.findItem(num(a[4]));if item then c.g_game.move(item,{x=num(a[1]),y=num(a[2]),z=num(a[3])},math.min(item:getCount(),num(a[5]))) end end
  cmd.dropitemsxyz=function(a) for i=4,#a do local item=c.findItem(num(a[i]));if item then c.g_game.move(item,{x=num(a[1]),y=num(a[2]),z=num(a[3])},item:getCount());return end end end
  local function destination(value)
    local boxes=c.getContainers();local index=tonumber(value);if index and boxes[index] then return boxes[index] end
    for _,box in pairs(boxes) do if not box.elfLoot and box:getItemsCount()<box:getCapacity() and (value=='empty' or index and box:getContainerItem():getId()==index or box.getName and box:getName():lower()==tostring(value):lower()) then return box end end
  end
  cmd.collectitems=function(a) local box=destination(a[1]);if not box then return end;local ids={};for i=2,#a do ids[num(a[i])]=true end;local item=nearby(ids,1);if item then c.g_game.move(item,box:getSlotPosition(box:getItemsCount()),item:getCount()) end end
  cmd.pickupitems=function(a) local box=destination(a[1]);local tile=c.g_map.getTile(c.pos());local item=tile and tile:getTopMoveThing();if box and item and item.getCount and (not item.isItem or item:isItem()) then c.g_game.move(item,box:getSlotPosition(box:getItemsCount()),item:getCount()) end end
  cmd.moveitems=function(a) local item=c.findItem(num(a[1]));local box=destination(a[2]);if item and box then c.g_game.move(item,box:getSlotPosition(box:getItemsCount()),math.min(item:getCount(),a[3] and num(a[3]) or item:getCount())) end end
  local function open(a,new)
    local which=num(a[2] or 1);local n=0
    for _,box in pairs(c.getContainers()) do for _,item in ipairs(box:getItems()) do if item:getId()==num(a[1]) then n=n+1;if n==which then if new then c.g_game.open(item) else c.g_game.open(item,box) end;return end end end end
  end
  cmd.openitem=function(a) open(a,false) end;cmd.openitemnew=function(a) open(a,true) end
  cmd.equipchest=cmd.equipbody
  cmd.equipback=function(a) local item=c.player:getInventoryItem(3);if not item or item:getId()~=num(a[1]) then local replacement=c.findItem(num(a[1]));if replacement then c.moveToSlot(replacement,3) end end end
  cmd.equipsring=function(a) local item=c.player:getInventoryItem(9);if item and (item:getId()==num(a[1]) or item:getId()==num(a[2])) then return end;cmd.equipring({a[1]}) end
  local slotNames={head=1,helm=1,helmet=1,neck=2,ammy=2,amulet=2,back=3,backpack=3,body=4,chest=4,rhand=5,righthand=5,lhand=6,lefthand=6,legs=7,boots=8,feet=8,ring=9,finger=9,belt=10,ammo=10}
  local function inventorySlot(value) return tonumber(value) or assert(slotNames[tostring(value):lower()],'Unknown inventory slot') end
  cmd.swapequip=function(a) local source=c.player:getInventoryItem(inventorySlot(a[1]));if source then c.moveToSlot(source,inventorySlot(a[2])) end end
  cmd.unequip=function(a) local item=c.player:getInventoryItem(inventorySlot(a[1]));local box=destination(a[2]);if item and box and box:getItemsCount()<box:getCapacity() then c.g_game.move(item,box:getSlotPosition(box:getItemsCount()),item:getCount()) end end
  cmd.movenitems=function(a) cmd.moveitems({a[1],a[3],a[2]}) end
  d.ammoSlots=d.ammoSlots or {}
  local function rememberAmmo(player,slot,item)
    if player==c.player and (slot==5 or slot==6 or slot==10) and item and item:isStackable() then d.ammoSlots[tostring(slot)]=item:getId() end
  end
  if c.onInventoryChange then c.onInventoryChange(rememberAmmo) end
  cmd.refillammo=function()
    for _,slot in ipairs({5,6,10}) do local current=c.player:getInventoryItem(slot);rememberAmmo(c.player,slot,current)
      local id=d.ammoSlots[tostring(slot)];local count=current and current:getCount() or 0
      if id and count<100 and (not current or current:getId()==id and current:isStackable()) then
        for _,box in pairs(c.getContainers()) do for _,item in ipairs(box:getItems()) do if item~=current and item:getId()==id then c.moveToSlot(item,slot,math.min(100-count,item:getCount()));return end end end
      end
    end
  end
  cmd.closeallwindows=cmd.closewindows
  cmd.lootitems=function() if e.collectTick then e.collectTick() end end
  cmd.xlog=function() if c.g_game.forceLogout then c.g_game.forceLogout() else c.safeLogout() end end
  cmd.reconnect=function() if c.requestElfReconnect then c.requestElfReconnect() end end
  cmd.loadsetting=function(a) assert(c.loadElfFile,'File loading is unavailable');return c.loadElfFile(join(a)) end
  cmd.loadscript=cmd.loadsetting
  cmd.loadtargeting=function(a) local profile=(d.targetProfiles or {})[join(a)];assert(profile,'Unknown targeting profile');c.TargetBot.setOff();d.targeting=json.decode(json.encode(profile)) end
  local function groundRune(position,id) local tile=c.g_map.getTile(position);if tile and tile:getTopUseThing() then c.useWith(id,tile:getTopUseThing()) end end
  cmd.magwall=function(a)
    local s=creature(a[1] or 'target');if not s then return end;local p=s:getPosition();local self=c.pos()
    local dirs={{0,-1},{1,0},{0,1},{-1,0}};local dir=s.getDirection and dirs[s:getDirection()+1];local dx=dir and dir[1] or (p.x>self.x and 1 or p.x<self.x and -1 or 0);local dy=dir and dir[2] or (p.y>self.y and 1 or p.y<self.y and -1 or 0)
    e.lastWallPosition={x=p.x+dx*2,y=p.y+dy*2,z=p.z};groundRune(e.lastWallPosition,3180)
  end
  cmd.keepmagwall=function() if e.lastWallPosition then local p=e.lastWallPosition;if not e.walls[p.x..','..p.y..','..p.z] then groundRune(p,3180) end end end
  function e.aimArea(id)
    local specs=c.getSpectators();local origin=c.pos();local best,score
    local function hit(p,q) local dx,dy=math.abs(p.x-q.x),math.abs(p.y-q.y);return p.z==q.z and dx<=3 and dy<=3 and dx+dy<=4 end
    for _,target in ipairs(specs) do if target~=c.player and (target:isMonster() or listed('enemies',target:getName()) or listed('subenemies',target:getName())) then
      local p=target:getPosition()
      for dx=-2,2 do for dy=-2,2 do
        local q={x=p.x+dx,y=p.y+dy,z=p.z};local hits=0;local safe=q.z==origin.z and c.getDistanceBetween(origin,q)<=7
        for _,s in ipairs(specs) do if s~=c.player and hit(q,s:getPosition()) then
          if s:isPlayer() and not listed('enemies',s:getName()) and not listed('subenemies',s:getName()) then safe=false end
          if s:isMonster() or listed('enemies',s:getName()) or listed('subenemies',s:getName()) then hits=hits+1 end
        end end
        local tile=safe and c.g_map.getTile(q);if tile and (not tile.canShoot or tile:canShoot()) and hits>0 and (not score or hits>score) then best,score=q,hits end
      end end
    end end
    if best then groundRune(best,id) end;return best
  end
  for name,id in pairs({aimgfb=3191,aimavalanche=3161,aimthunderstorm=3202,aimstoneshower=3175}) do local rune=id;cmd[name]=function() e.aimArea(rune) end end
  for name,id in pairs({soulf=3195,stalagmite=3179,ihpc=3152}) do local rune,command=id,name;cmd[name]=function(a) local s=creature(a[command=='ihpc' and 2 or 1] or 'target');if s and (command~='ihpc' or s:getHealthPercent()<=num(a[1])) then c.useWith(rune,s) end end end
  cmd.wave=function(a) local s=creature('target');if not s then return end;local p=s:getPosition();local self=c.pos();local dx,dy=p.x-self.x,p.y-self.y
    if self.z==p.z and math.max(math.abs(dx),math.abs(dy))<=4 and (math.abs(dx)<=1 or math.abs(dy)<=1) and s:canShoot() then
      c.turn(math.abs(dx)>math.abs(dy) and (dx>0 and 1 or 3) or (dy>0 and 2 or 0));c.saySpell(join(a),1000)
    end
  end
  cmd.ewave=function() cmd.wave({'exevo vis hur'}) end
  for name,spell in pairs({exoricon='exori con',exorihur='exori hur',exorigran='exori gran'}) do local word=spell;local close=name=='exorigran';cmd[name]=function(a) local s=creature('target');if s and s:getHealthPercent()<=num(a[1]) and c.getDistanceBetween(c.pos(),s:getPosition())<=(close and 1 or 3) and s:canShoot() then c.saySpell(word,1000) end end end
  cmd.ignoretarget=function(a) local s=creature(a[1]);if s then e.ignoredTargets=e.ignoredTargets or {};e.ignoredTargets[s:getId()]=c.now;if c.g_game.getAttackingCreature()==s then c.cancelAttackAndFollow() end end end
  cmd.makerune=function(a) if c.mana()>=num(a[1]) then c.saySpell(join(a,2),1000) end end
  -- Pick an empty square crossed by the most visible attackers' projectile lines.
  function e.coverWithWall(protected,allPlayers)
    if not protected then return end;local origin=c.pos();local p=protected:getPosition();if p.z~=origin.z then return end
    local rays={};for _,s in ipairs(c.getSpectators()) do if s~=protected and s~=c.player and (s:isMonster() or s:isPlayer() and (allPlayers or listed('enemies',s:getName()) or listed('subenemies',s:getName()))) then
      local start=s:getPosition();if start.z==p.z then
        local cells={};local x,y=start.x,start.y;local dx,dy=math.abs(p.x-x),math.abs(p.y-y);local sx,sy=x<p.x and 1 or -1,y<p.y and 1 or -1;local err=dx-dy
        for step=1,32 do if x==p.x and y==p.y then break end;local twice=2*err;if twice>-dy then err=err-dy;x=x+sx end;if twice<dx then err=err+dx;y=y+sy end;cells[x..','..y]=true end
        rays[#rays+1]=cells
      end
    end end
    local best,score
    for dx=-2,2 do for dy=-2,2 do if dx~=0 or dy~=0 then
      local q={x=p.x+dx,y=p.y+dy,z=p.z};local tile=c.g_map.getTile(q)
      if c.getDistanceBetween(origin,q)<=7 and tile and (not tile.isWalkable or tile:isWalkable()) and (not tile.hasCreatures or not tile:hasCreatures()) and (not tile.canShoot or tile:canShoot()) then
        local count=0;for _,ray in ipairs(rays) do if ray[q.x..','..q.y] then count=count+1 end end
        local rank=count*100-c.getDistanceBetween(p,q);if count>0 and (not score or rank>score) then best,score=q,rank end
      end
    end end end
    if best then e.lastWallPosition=best;groundRune(best,3180) end;return best
  end
  cmd.mwallshield=function() e.coverWithWall(c.player,false) end
  cmd.mwallcover=function(a) e.coverWithWall(creature(a[1]),true) end
  cmd.displaymap=function() assert(modules.game_minimap and modules.game_minimap.toggleFullMap,'Minimap module unavailable');modules.game_minimap.toggleFullMap() end
  cmd.altnavdisplay=function() d.hud.altNavigation=not d.hud.altNavigation;d.hud.navigation=true end
  cmd.setalarm=function(a)
    local keys={playeronscreen='player',playerattacking='attack',privatemessage='private',defaultmessage='default',gmdetected='gm',disconnected='disconnected'};local key=keys[tostring(a[1]):lower()] or tostring(a[1]):lower()
    assert(key=='player' or key=='attack' or key=='private' or key=='default' or key=='gm' or key=='disconnected','Unknown alarm')
    d.alerts=d.alerts or {};d.alerts[key]=d.alerts[key] or {};for i,field in ipairs({'sound','pause','logout'}) do local value=a[i+1];if value~=nil then d.alerts[key][field]=value=='on' or value==1 or value==true end end
  end
  cmd.aimtype=function(a) local s=creature(a[1]);if s then if c.g_game.getAttackingCreature()~=s then c.attack(s) end;local job,err=e.runAttack(d.aimbot.command or '');assert(job,err) end end
  cmd.autoaim=function() if e.aimTick then e.aimTick(true) end end;cmd.aimbot=cmd.autoaim
  cmd.runtargeting=function() if c.TargetBot then e.heldTargetUntil=c.now+250;local on=c.TargetBot.isOn();c.TargetBot.enabled=true;local ok,err=pcall(e.targetTick);c.TargetBot.enabled=on;assert(ok,err) end end
  cmd.setopennextbp=function(a) d.extras.openNextBp=a[1]=='toggle' and not d.extras.openNextBp or a[1]=='on' or a[1]==1 or a[1]==true end
  function e.compatTick()
    for row,flash in pairs(e.iconFlashes or {}) do if c.now>=flash.expires then row.active=flash.previous;e.iconFlashes[row]=nil;e.iconsDirty=true end end
  end
  local originalSay=cmd.say
  cmd.say=function(a,env) local result=originalSay(a,env);local text=join(a):lower();if result~=false and text=='utamo vita' then e.buffExpires=e.buffExpires or {};e.buffExpires[text]=c.now+((d.hud.buffDurations or {})[text] or 200000) end;return result end
end
