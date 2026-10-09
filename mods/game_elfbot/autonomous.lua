-- Independent controllers. Only client game APIs are used; no profile is loaded.
function prepareStandaloneElfBot(c)
  local d=c.storage.elfbot or {};c.storage.elfbot=d
  d.waypoints=d.waypoints or {};d.targeting=d.targeting or {monsters={},weights={danger=10,proximity=5,health=1,order=3},stick=true}
  d.targeting.monsters=d.targeting.monsters or {};d.targeting.weights=d.targeting.weights or {danger=10,proximity=5,health=1,order=3}
  d.loot=d.loot or {};d.lists=d.lists or {friends='',subfriends='',enemies='',subenemies='',leaders=''}
  d.aimbot=d.aimbot or {enabled=false,command='',enemiesOnly=true,skulledOnly=true,frequency=1000,triggers={}}
  d.hud=d.hud or {enabled=false,general=true,active=true};d.extras=d.extras or {};d.icons=d.icons or {};d.navigation=d.navigation or {}
  local b={Actions={},actionList=g_ui.createWidget('UIWidget'),enabled=false,index=1,retries=0};b.actionList:hide();c.CaveBot=b
  local t={enabled=false,Looting={list={}}};c.TargetBot=t
  local function distance(p,q) if not p or not q or p.z~=q.z then return 1000 end;return c.getDistanceBetween(p,q) end
  local function position(s)
    local x,y,z=s:match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)');assert(x,'Expected x,y,z');return {x=tonumber(x),y=tonumber(y),z=tonumber(z)}
  end
  function b.isOn() return b.enabled end
  function b.setOn() if c.ElfBot then c.ElfBot.paused=false end;b.enabled=true;if b.Recorder then b.Recorder.enabled=false end;b.retries=0;b.nextRun=0 end
  function b.setOff() local wasOn=b.enabled;b.enabled=false;b.toolState=nil;if wasOn and c.player and c.player:isAutoWalking() then c.g_game.stop() end end
  function b.getCurrentProfile() return d.routeName or 'ElfBot route' end
  function b.registerAction(name,color,callback) b.Actions[name]={callback=callback} end
  function b.addAction(name,value,focus,actionPosition)
    assert(b.Actions[name],'Unknown waypoint: '..name)
    local row=g_ui.createWidget('UIWidget',b.actionList);row.action=name;row.value=value;row.actionPosition=actionPosition
    if focus then b.actionList:focusChild(row);b.index=b.actionList:getChildIndex(row) end
    return row
  end
  function b.editAction(row,name,value) assert(b.Actions[name],'Unknown waypoint');row.action=name;row.value=value end
  function b.save()
    d.waypoints={};for _,row in ipairs(b.actionList:getChildren()) do d.waypoints[#d.waypoints+1]={row.action,row.value,row.actionPosition} end;c.saveConfig()
  end
  function b.gotoLabel(name)
    for i,row in ipairs(b.actionList:getChildren()) do if row.action=='label' and row.value==name then b.index=i;b.jumped=true;b.retries=0;return true end end;return false
  end
  function b.setCurrentProfile(name)
    local rows=assert(d.routes[name],'Unknown ElfBot route: '..name);b.setOff();if c.ElfBot then c.ElfBot.actionJobs={} end;b.actionList:destroyChildren()
    for _,row in ipairs(rows) do b.addAction(row[1],row[2],false,row[3]) end;b.index=1;d.routeName=name;b.save()
  end
  b.registerAction('label','',function(value) b.label=value;return true end)
  b.registerAction('goto','',function(value,retries)
    local p=position(value);local precision=tonumber(value:match(',(%d+)%s*$')) or 0
    if distance(c.pos(),p)<=precision then return true end
    if retries>80 then error('Waypoint unreachable: '..value) end
    if not c.player:isAutoWalking() then assert(c.autoWalk(p,100,{precision=precision,ignoreNonPathable=false}),'No path to '..value) end
    return 'retry'
  end)
  b.registerAction('use','',function(value,retries)
    local p=position(value);if distance(c.pos(),p)>1 then return b.Actions.goto.callback(value..',1',retries) end
    local tile=c.g_map.getTile(p);assert(tile and tile:getTopUseThing(),'Waypoint tile unavailable');c.use(tile:getTopUseThing());b.nextRun=c.now+math.max(200,d.useDelay or 500);return true
  end)
  b.registerAction('usewith','',function(value,retries)
    local id,coords=value:match('^(%d+),(.+)$');local p=position(assert(coords,'Expected item,x,y,z'))
    if distance(c.pos(),p)>1 then return b.Actions.goto.callback(coords..',1',retries) end
    local tile=c.g_map.getTile(p);assert(tile and tile:getTopUseThing(),'Waypoint tile unavailable');assert(tonumber(id) and tonumber(id)>0 and tonumber(id)<=65535,'Invalid tool item ID');c.useWith(tonumber(id),tile:getTopUseThing());b.nextRun=c.now+math.max(200,d.useDelay or 500);return true
  end)
  function t.isOn() return t.enabled end
  function t.setOn() if c.ElfBot then c.ElfBot.paused=false end;t.enabled=true end
  function t.setOff() t.enabled=false;t.current=nil;t.Looting.list={};if t.clearLootState then t.clearLootState() end;c.cancelAttackAndFollow() end
  function t.save() c.saveConfig() end
  function t.Looting.save(value) value.items={};for _,row in ipairs(d.loot) do value.items[#value.items+1]={id=row.id,count=1} end end
  function t.Looting.update() end
  -- Tools must use a real inventory item and the ground tile, not a creature
  -- or loose item covering the rope spot. Wait for the server's tile/floor change.
  b.registerAction('tool','',function(value,retries)
    local kind,id,coords=value:match('^(%a+),(%d+),(.+)$');id=tonumber(id)
    assert(id and id>0 and id<=65535,'Invalid tool item ID')
    local p=position(coords);local current=c.pos();local key=value
    local state=b.toolState
    if state and state.key==key then
      if current.z~=state.floor then b.toolState=nil;return true end
      local tile=c.g_map.getTile(p);local ground=tile and tile.getGround and tile:getGround()
      if ground and ground:getId()~=state.groundId then b.toolState=nil;return true end
      if c.now<state.nextUse then return 'retry' end
      assert(state.attempts<4,'Tool '..kind..' did not change the tile/floor; check item ID and waypoint position')
    else state=nil end
    assert(current.z==p.z,'Tool waypoint is on another floor')
    if distance(current,p)>1 then return b.Actions.goto.callback(coords..',1',retries) end
    local tile=c.g_map.getTile(p);assert(tile,'Tool waypoint tile unavailable')
    local target=tile.getGround and tile:getGround() or tile:getTopUseThing()
    assert(target and (not target.isItem or target:isItem()),'Tool waypoint has no usable ground item')
    local item=c.findItem(id)
    if not item and c.player.getInventoryItem then
      for slot=1,10 do local equipped=c.player:getInventoryItem(slot);if equipped and equipped:getId()==id then item=equipped;break end end
    end
    assert(item,'Open the backpack containing '..kind..' item '..id)
    c.useWith(item,target)
    b.toolState={key=key,floor=current.z,groundId=target:getId(),attempts=(state and state.attempts or 0)+1,nextUse=c.now+math.max(500,d.useDelay or 700)}
    return 'retry'
  end)
  b.Recorder={enabled=false,lastPosition=nil}
  local recorder=b.Recorder
  local function validPos(p) return p and type(p.x)=='number' and type(p.y)=='number' and type(p.z)=='number' and p.x~=65535 end
  local function recordWaypoint(name,value,p)
    b.addAction(name,value,false);recorder.lastPosition={x=p.x,y=p.y,z=p.z};b.save()
    if recorder.onChange then recorder.onChange() end
  end
  function recorder.isOn() return recorder.enabled end
  function recorder.enable() b.setOff();recorder.enabled=true;recorder.lastPosition=nil end
  function recorder.disable() recorder.enabled=false;recorder.lastPosition=nil;b.save() end
  if c.onPlayerPositionChange then c.onPlayerPositionChange(function(newPos,oldPos)
    if not recorder.enabled or b.isOn() or not validPos(newPos) or not validPos(oldPos) then return end
    local function add(p,kind) recordWaypoint(kind,p.x..','..p.y..','..p.z,p) end
    if not recorder.lastPosition then add(oldPos,'elfnode') end
    if newPos.z~=oldPos.z or math.abs(newPos.x-oldPos.x)>1 or math.abs(newPos.y-oldPos.y)>1 then add(oldPos,'elfstand');recorder.lastPosition=nil
    elseif math.max(math.abs(newPos.x-recorder.lastPosition.x),math.abs(newPos.y-recorder.lastPosition.y))>5 then add(newPos,'elfnode') end
  end) end
  if c.onUse then c.onUse(function(p)
    if recorder.enabled and not b.isOn() and validPos(p) then recordWaypoint('use',p.x..','..p.y..','..p.z,p) end
  end) end
  if c.onUseWith then c.onUseWith(function(_,id,target)
    if not recorder.enabled or b.isOn() or not target or not target:isItem() then return end
    local p=target:getPosition();if validPos(p) then recordWaypoint('usewith',id..','..p.x..','..p.y..','..p.z,p) end
  end) end
  local e=createElfBotEngine(c,d);c.ElfBot=e;e.registerCaveActions()
  for _,row in ipairs(d.waypoints) do if b.Actions[row[1]] then b.addAction(row[1],row[2],false,row[3]) else e.status='Unknown saved waypoint: '..tostring(row[1]) end end
  function e.listContains(kind,name)
    for line in (d.lists[kind] or ''):gmatch('[^\r\n,;]+') do if line:match('^%s*(.-)%s*$'):lower()==name:lower() then return true end end;return false
  end
  e.monsterOwners={}
  function e.setMonsterOwner(id,name) e.monsterOwners[id]={name=name,time=c.now} end
  function e.monsterRule(creature)
    for i,rule in ipairs(d.targeting.monsters) do
      if rule.enabled~=false and (rule.name=='*' or rule.name:lower()==creature:getName():lower()) then
        local hp=creature:getHealthPercent()
        for _,setting in ipairs(rule.settings or {rule}) do if hp>=(setting.hpMin or 0) and hp<=(setting.hpMax or 100) then
          if d.targeting.ignoreAntiBot and (rule.categories or ''):lower():find('anti%-bot') then return nil end
          local effective={range=d.targeting.range or 1,frequency=d.targeting.frequency or 1000,diagonal=d.targeting.diagonal~=false,shootable=d.targeting.shootable,reachable=d.targeting.reachable,onlyLabel=d.targeting.onlyLabel}
          for key,value in pairs(setting) do effective[key]=value end
          if d.targeting.range~=nil then effective.range=d.targeting.range end;if d.targeting.frequency~=nil then effective.frequency=d.targeting.frequency end
          return effective,i,rule
        end end
      end
    end
  end
  local function walkTo(destination,maxDistance,params)
    local path=c.findPath(c.pos(),destination,maxDistance,params);if not path then return false end
    local origin=c.pos();local x,y=origin.x,origin.y
    local offsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
    local blocked={};if not d.targeting.blockedLabel or d.targeting.blockedLabel=='' or d.targeting.blockedLabel==b.label then for line in (d.targeting.blocked or ''):gmatch('[^\r\n]+') do blocked[line]=true end end
    for _,direction in ipairs(path) do local delta=offsets[direction+1];if delta then x=x+delta[1];y=y+delta[2];if blocked[x..','..y..','..origin.z] then return false end;if d.targeting.diagonal==false and direction>=4 then return false end end end
    return c.autoWalk(path)
  end
  function e.targetTick()
    if not t.enabled or c.now<(t.nextRun or 0) then return end;t.nextRun=c.now+200
    local origin=c.pos();local best,bestRule
    local candidates={}
    local spectators=c.getSpectators();local current=c.g_game.getAttackingCreature();local weights=d.targeting.weights
    local countByName={}
    for _,other in ipairs(spectators) do if other:isMonster() then local name=other:getName():lower();countByName[name]=(countByName[name] or 0)+1 end end
    for _,spec in ipairs(spectators) do if spec:isMonster() and not (e.ignoredTargets or {})[spec:getId()] and spec:getHealthPercent()>0 and distance(origin,spec:getPosition())<=9 then
      local rule,index,parent=e.monsterRule(spec)
      if rule then
        local count=countByName[spec:getName():lower()] or 0
        local allowed=count>=(parent.count or 1) and (not rule.shootable or spec:canShoot()) and (not rule.onlyLabel or rule.onlyLabel=='' or rule.onlyLabel==b.label)
        local owner=e.monsterOwners[spec:getId()];local ignore=d.targeting.ignoreOthers
        if allowed and owner and c.now-owner.time<10000 and owner.name:lower()~=c.name():lower() and ignore and ignore~="Don't" then
          local friend=e.listContains('friends',owner.name) or e.listContains('subfriends',owner.name)
          if ignore=='All' or ignore=='Friends' and friend or ignore=='Enemies' and (e.listContains('enemies',owner.name) or e.listContains('subenemies',owner.name)) then allowed=false end
        end
        if allowed then
          local rank=(rule.danger or 1)*(weights.danger or 10)-distance(origin,spec:getPosition())*(weights.proximity or 5)+(100-spec:getHealthPercent())*(weights.health or 1)-index*(weights.order or 3)
          if d.targeting.stick and spec==current then rank=rank+(d.targeting.stickWeight and d.targeting.stickWeight*100 or 100000) end
          rank=rank+math.random(0,math.floor(weights.random or 0))
          candidates[#candidates+1]={creature=spec,rule=rule,rank=rank,order=#candidates+1}
        end
      end
    end end
    -- Check highest scores first; do not pathfind every lower-ranked monster
    -- after a reachable winner has already been found.
    table.sort(candidates,function(a,b) return a.rank>b.rank or a.rank==b.rank and a.order<b.order end)
    for _,candidate in ipairs(candidates) do
      if not candidate.rule.reachable or c.findPath(origin,candidate.creature:getPosition(),40,{ignoreLastCreature=true})~=nil then
        best,bestRule=candidate.creature,candidate.rule;break
      end
    end
    local old=t.current;t.current=best
    if not best then if old and current==old then c.cancelAttackAndFollow() end;t.targetId=nil;return end
    local previous=t.targetId;t.targetId=best:getId()
    if current~=best and c.now>=(t.nextAttack or 0) then c.attack(best);t.nextAttack=c.now+math.max(200,bestRule.frequency or 500) end
    if previous~=t.targetId then t.nextAction=0 end
    if previous~=t.targetId and bestRule.alarm then c.playSound('/game_elfbot/sounds/monster.ogg') end
    if bestRule.fightMode then c.g_game.setFightMode(bestRule.fightMode) end
    if bestRule.ring and bestRule.ring>0 then e.commands.equipring({bestRule.ring}) end
    local avoid=bestRule.avoid
    if avoid and avoid~="Don't avoid" and best.getDirection and not c.player:isAutoWalking() then
      local p=best:getPosition();local dirs={{0,-1},{1,0},{0,1},{-1,0}};local dir=dirs[best:getDirection()+1]
      if dir then local ox,oy=origin.x-p.x,origin.y-p.y;local forward=ox*dir[1]+oy*dir[2];local sideways=math.abs(ox*dir[2]-oy*dir[1]);local width=avoid=='Avoid beams' and 0 or 1
        if forward>0 and forward<=5 and sideways<=width then
          for _,sign in ipairs({-1,1}) do local q={x=origin.x+dir[2]*sign,y=origin.y-dir[1]*sign,z=origin.z};if walkTo(q,3,{ignoreNonPathable=false}) then return end end
        end
      end
    end
    local stance=bestRule.stance or 'Approach';local range=bestRule.range or 1;local delta=distance(origin,best:getPosition())
    if stance=='Follow' then c.follow(best)
    elseif stance=='Approach' and delta>range then walkTo(best:getPosition(),30,{precision=range,ignoreLastCreature=true})
    elseif (stance=='Keep distance' or stance=='Lure') and delta<range and not c.player:isAutoWalking() then
      local p=best:getPosition();local options={}
      for dx=-1,1 do for dy=-1,1 do if (dx~=0 or dy~=0) and (bestRule.diagonal~=false or dx==0 or dy==0) then
        local q={x=origin.x+dx,y=origin.y+dy,z=origin.z};if distance(q,p)>delta then options[#options+1]=q end
      end end end
      for _,q in ipairs(options) do if walkTo(q,5,{ignoreNonPathable=false}) then break end end
    end
    if bestRule.action and bestRule.action~='' and c.now>=(t.nextAction or 0) and (not d.targeting.syncSpell or e.lastAttackAt and e.lastAttackAt~=(e.syncedAttackAt or -1)) then
      local job,err=e.runAttack(bestRule.action);assert(job,err);t.nextAction=c.now+math.max(200,bestRule.frequency or 1000);e.syncedAttackAt=e.lastAttackAt
    end
    t.lastPosition=best:getPosition();local _,_,parent=e.monsterRule(best);t.lootCurrent=parent and parent.loot~=false
  end
  function e.caveTick()
    if not b.enabled or c.now<(b.nextRun or 0) then return end;b.nextRun=c.now+200
    if t.current or #t.Looting.list>0 then return end
    for _,box in pairs(c.getContainers()) do if box.elfLoot then return end end
    local rows=b.actionList:getChildren();if #rows==0 then b.setOff();e.status='Add waypoints before following';return end
    b.index=math.max(1,math.min(b.index,#rows));local row=rows[b.index];b.actionList:focusChild(row)
    local action=assert(b.Actions[row.action],'Unknown waypoint action')
    b.jumped=false;local ok,result=pcall(action.callback,row.value,b.retries,true)
    if not ok or result==false then b.setOff();e.status='Cavebot stopped: '..tostring(result);c.warn(e.status);return end
    if result=='retry' then b.retries=b.retries+1
    else b.retries=0;if not b.jumped then b.index=b.index%#rows+1 end end
  end
  local killed={};local pendingOpen
  t.clearLootState=function() killed={};pendingOpen=nil end
  c.onCreatureHealthPercentChange(function(creature,hp)
    if t.enabled and creature:isMonster() and hp<=0 then local _,_,rule=e.monsterRule(creature);local p=creature:getPosition();if rule and rule.loot~=false and p then killed[p.x..','..p.y..','..p.z]=c.now end end
  end)
  c.onCreatureDisappear(function(creature)
    local id=creature:getId();e.monsterOwners[id]=nil;if e.ignoredTargets then e.ignoredTargets[id]=nil end
    if t.current==creature then t.current=nil end
    if t.enabled and creature:isMonster() and creature:getHealthPercent()<=0 then
      local _,_,rule=e.monsterRule(creature)
      if rule and rule.loot~=false then local p=creature:getPosition();if p then killed[p.x..','..p.y..','..p.z]=c.now end end
    end
  end)
  c.onAddThing(function(tile,thing)
    if not t.enabled or not thing:isItem() or not thing:isContainer() then return end
    local p=tile:getPosition();local key=p.x..','..p.y..','..p.z
    if not killed[key] and t.lastPosition and distance(p,t.lastPosition)==0 and t.lootCurrent and (not c.g_game.getAttackingCreature() or c.g_game.getAttackingCreature():getHealthPercent()<=0) then killed[key]=c.now end
    if killed[key] and c.now-killed[key]<5000 then
      if #t.Looting.list<128 then t.Looting.list[#t.Looting.list+1]={itemId=thing:getId(),position=p,added=c.now} end
      killed[key]=nil
    end
  end)
  c.onContainerOpen(function(container)
    if pendingOpen and c.now-pendingOpen.time<2000 then
      local item=container:getContainerItem()
      if container:getId()==pendingOpen.id and item and item:getId()==pendingOpen.itemId then container.elfLoot=true;pendingOpen=nil;table.remove(t.Looting.list,1) end
    end
  end)
  function e.collectTick()
    if not t.enabled or c.now<(t.nextLoot or 0) then return end;t.nextLoot=c.now+300
    local containers=c.getContainers()
    if pendingOpen then if c.now-pendingOpen.time<2000 then return end;pendingOpen=nil end
    for _,source in pairs(containers) do if source.elfLoot then
      for _,item in ipairs(source:getItems()) do
        for _,rule in ipairs(d.loot) do if item:getId()==rule.id then
          if rule.destination=='G' then c.g_game.move(item,c.pos(),item:getCount());return end
          local destination=containers[tonumber(rule.destination)]
          if rule.destination=='E' or rule.destination=='E1' then
            local ordered={};for id,box in pairs(containers) do if not box.elfLoot and (rule.destination~='E1' or id~=0) and box:getItemsCount()<box:getCapacity() then ordered[#ordered+1]={id=id,box=box} end end
            table.sort(ordered,function(a,b) return a.id<b.id end);destination=ordered[1] and ordered[1].box
          end
          if destination and destination~=source and destination:getItemsCount()<destination:getCapacity() then
            c.g_game.move(item,destination:getSlotPosition(destination:getItemsCount()),item:getCount());return
          end
          if destination and d.extras.openNextBp then
            for _,inside in ipairs(destination:getItems()) do if inside:isContainer() then c.g_game.open(inside,destination);return end end
          end
          e.status='Loot destination is full or unavailable';return
        end end
      end
      c.g_game.close(source);source.elfLoot=false;return
    end end
    local entry=t.Looting.list[1];if not entry then return end
    if c.now-entry.added>10000 then table.remove(t.Looting.list,1);return end
    if distance(c.pos(),entry.position)>1 then
      if d.extras.lootDistant==false then table.remove(t.Looting.list,1);return end
      if not t.current then c.autoWalk(entry.position,30,{precision=1}) end;return
    end
    if d.extras.lootNearby==false then table.remove(t.Looting.list,1);return end
    local tile=c.g_map.getTile(entry.position);local corpse
    if tile then for _,thing in ipairs(tile:getThings()) do if thing:isItem() and thing:isContainer() and thing:getId()==entry.itemId then corpse=thing;break end end end
    if not corpse then table.remove(t.Looting.list,1);return end
    pendingOpen={time=c.now,position=entry.position,itemId=entry.itemId};pendingOpen.id=c.g_game.open(corpse)
    if not pendingOpen.id or pendingOpen.id<0 then pendingOpen=nil;e.status='Unable to open corpse' end
  end
  function e.aimTick(force)
    local a=d.aimbot;if not (a.enabled or force) or c.now<(e.nextAim or 0) then return end;e.nextAim=c.now+math.max(200,a.frequency or 1000)
    local best,score
    for _,spec in ipairs(c.getSpectators()) do if spec:isPlayer() and spec~=c.player and not (e.ignoredTargets or {})[spec:getId()] and not e.listContains('friends',spec:getName()) and not e.listContains('subfriends',spec:getName()) then
      local enemy=e.listContains('enemies',spec:getName()) or e.listContains('subenemies',spec:getName())
      -- Reuse the battle module's visibility/range check without using its UI filters.
      local battle=modules.game_battle
      local visible=not battle or not battle.canBeSeen or battle.canBeSeen(spec)
      if visible and (not a.enemiesOnly or enemy) and (not a.skulledOnly or spec:getSkull()>0) and spec:canShoot() then
        local rank=((d.relationPriorities or {})[spec:getName():lower()] or 0)*1000-(a.lowestHealth~=false and spec:getHealthPercent() or 0);if not score or rank>score then best,score=spec,rank end
      end
    end end
    if best then if c.g_game.getAttackingCreature()~=best then c.attack(best) end;local job,err=e.runAttack(a.command);assert(job,err) end
  end
  c.onTalk(function(name,level,mode,text)
    if d.botEnabled==false or e.paused then return end
    if name==c.name() then return end
    local a=d.aimbot;if a.wordTriggers and e.listContains('leaders',name) then
      for _,trigger in ipairs(a.triggers or {}) do if text:lower()==trigger.word:lower() then e.run(trigger.command) end end
    end
  end)
  function e.extraTick()
    if d.awaitingLoad then return end
    local map=modules.game_interface.getMapPanel()
    if d.extras.fullLight~=e.lightApplied then map:setMinimumAmbientLight(d.extras.fullLight and 1 or (modules.client_options.getOption('ambientLight') or 0)/100);e.lightApplied=d.extras.fullLight end
    if d.extras.nonPvp~=e.safeApplied then c.g_game.setSafeFight(d.extras.nonPvp~=false);e.safeApplied=d.extras.nonPvp end
  end
  local raw=e.tick
  e.tick=function()
    e.telemetryTick();e.compatTick();raw()
    if c.now>=(e.nextStateCleanup or 0) then
      e.nextStateCleanup=c.now+1000
      ElfBotHistory.prune(killed,c.now,5000,256)
      ElfBotHistory.prune(e.monsterOwners,c.now,10000,256)
      ElfBotHistory.prune(e.ignoredTargets or {},c.now,30000,256)
    end
    if e.heldTargetUntil and c.now>e.heldTargetUntil then e.heldTargetUntil=nil;if not t.enabled then if t.current and c.g_game.getAttackingCreature()==t.current then c.cancelAttackAndFollow() end;t.current=nil end end
    if e.paused then return end;e.targetTick();e.collectTick();e.caveTick();e.aimTick();e.extraTick()
  end
  e.disposeControllers=function() b.setOff();t.enabled=false;t.current=nil;t.Looting.list={};t.clearLootState();b.actionList:destroy() end
  return e
end
