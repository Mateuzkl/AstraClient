-- Observable combat/HUD state, using client events and optional server look data.
function prepareElfBotTelemetry(e,c,d)
  d.hud=d.hud or {enabled=false,general=true,active=true}
  local h=d.hud
  e.playerCache=h.cachePlayers and (d.playerCache or {}) or {};d.playerCache=h.cachePlayers and e.playerCache or nil
  e.clearWallTimers=function() for _,wall in pairs(e.walls or {}) do local tile=c.g_map.getTile(wall.position);if wall.drawn and tile and tile.setTimer then tile:setTimer(0,'#ffffff');wall.drawn=false end end end
  e.damageHistory=ElfBotHistory.new(10000,2048)
  e.damageSamples=e.damageHistory.samples;e.deaths={};e.walls={};e.spellTimers={};e.listboxes={};e.messageSerial=0
  e.currentMessage={content='',sender='',isprivate=0,isbotlook=0}
  e.lastMove=c.now;e.lastReceived=c.now;e.lastPosition=c.pos();e.pendingLook=nil
  local function listen(name,fn) if type(c[name])=='function' then c[name](fn) end end
  function e.playerInfo(creature)
    local info=e.playerCache[creature:getName():lower()] or {}
    local result={};for k,v in pairs(info) do result[k]=v end
    result.name=creature:getName();result.hp=creature:getHealthPercent()
    if creature.getVocation then local v=creature:getVocation();if v and v>0 then result.vocation=v end end
    if creature==c.player then result.level=c.level();result.mana=c.mana();result.maxMana=c.maxmana();result.manaPercent=c.manapercent()
    elseif creature.getManaPercent then local mp=creature:getManaPercent();if mp and mp>=0 and mp<=100 then result.manaPercent=mp end end
    if not result.maxMana and result.level and result.vocation then
      local base=((result.vocation-1)%4)+1;local growth=base<=2 and 30 or base==3 and 15 or 5
      result.maxMana=35+math.max(0,result.level-8)*growth;result.estimated=true
      if result.manaPercent then result.mana=math.floor(result.maxMana*result.manaPercent/100) end
    end
    return result
  end
  function e.parseLook(text)
    local name,level=text:match('You see (.-) %(Level (%d+)%)')
    if not name then name,level=text:match('You see (.-) %(level (%d+)%)') end
    if not name then return false end
    local info=e.playerCache[name:lower()] or {};info.level=tonumber(level);info.name=name
    local lower=text:lower();local vocs={{'elder druid',6},{'master sorcerer',5},{'royal paladin',7},{'elite knight',8},{'druid',2},{'sorcerer',1},{'paladin',3},{'knight',4}}
    for _,pair in ipairs(vocs) do if lower:find(pair[1],1,true) then info.vocation=pair[2];break end end
    local guild=text:match(' of the ([^%.%(]+)')
    if guild then info.guild=guild:gsub(',.*$',''):gsub('%s+$','') end
    info.updated=c.now;info.haslookinfo=true;e.playerCache[name:lower()]=info
    ElfBotHistory.prune(e.playerCache,c.now,300000,256)
    if h.cachePlayers then d.playerCache=e.playerCache end
    return true
  end
  listen('onTextMessage',function(mode,text)
    e.lastReceived=c.now
    local botLook=e.pendingLook and text:find(e.pendingLook.name,1,true)~=nil
    e.parseLook(text)
    if botLook then e.currentMessage={content=text,sender='',isprivate=0,isbotlook=1,serial=e.messageSerial};e.pendingLook=nil end
    local damage=text:match('loses (%d+) hitpoints') or text:match('loses (%d+) hit points') or text:match('You deal (%d+) damage')
    if damage and (text:find('your attack',1,true) or text:find('your critical attack',1,true) or text:find('your spell',1,true) or text:find('You deal',1,true) or (MessageModes.DamageDealt and mode==MessageModes.DamageDealt)) then
      e.damageHistory:add(c.now,tonumber(damage));e.firstDamage=e.firstDamage or c.now;e.lastAttackAt=c.now
    end
    if text:lower():find('you lose') and text:lower():find('attack by') then e.lastPlayerAttack=c.now end
    if h.navigation then
      local name,direction=text:match('(.+) is ([^%.]+)%.')
      if name and (direction:find('north') or direction:find('south') or direction:find('east') or direction:find('west') or direction:find('above') or direction:find('below')) then e.exivaInfo={name=name,direction=direction,time=c.now} end
    end
  end)
  listen('onTalk',function(name,level,mode,text)
    e.lastReceived=c.now;e.messageSerial=e.messageSerial+1
    e.currentMessage={sender=name,content=text,isprivate=mode==MessageModes.PrivateFrom and 1 or 0,isbotlook=0,serial=e.messageSerial}
    if mode==MessageModes.PrivateFrom then e.lastPrivate=c.now elseif mode==MessageModes.Say then e.lastDefault=c.now end
  end)
  listen('onCreatureHealthPercentChange',function(creature,hp)
    e.lastReceived=c.now
    if hp<=0 and creature:getPosition() then
      local key=creature.getId and creature:getId() or creature:getName()
      if not e.deadIds then e.deadIds={} end
      if not e.deadIds[key] or c.now-e.deadIds[key]>3000 then
        e.deadIds[key]=c.now;e.deaths[#e.deaths+1]={name=creature:getName(),time=c.now,position=creature:getPosition()}
        if #e.deaths>30 then table.remove(e.deaths,1) end
      end
    end
  end)
  listen('onAddThing',function(tile,thing)
    if not thing.isItem or not thing:isItem() then return end
    local id=thing:getId();local duration=(h.wallDurations or {})[tostring(id)] or ((id==2128 or id==2129) and 20000 or id==2130 and 45000)
    if duration then local p=tile:getPosition();local key=p.x..','..p.y..','..p.z;local old=e.walls[key];e.walls[key]={position=p,id=id,expires=old and old.expires>c.now and old.expires or c.now+duration} end
  end)
  listen('onRemoveThing',function(tile,thing)
    if thing and thing.getId and (thing:getId()==2128 or thing:getId()==2129 or thing:getId()==2130) then local p=tile:getPosition();local key=p.x..','..p.y..','..p.z;local wall=e.walls[key];if wall and wall.drawn and tile.setTimer then tile:setTimer(0,'#ffffff') end;e.walls[key]=nil end
  end)
  listen('onSpellCooldown',function(id,duration) e.spellTimers['Spell '..id]=c.now+duration end)
  listen('onGroupSpellCooldown',function(id,duration) e.spellTimers['Group '..id]=c.now+duration end)
  listen('onUseWith',function(pos,id,target)
    if id==3180 or id==3156 then e.lastWallPosition=target end
  end)
  -- Same native creature labels used by vBot's Check Players, with ownership-safe cleanup.
  e.playerLabels={}
  function e.clearPlayerLabels()
    for id,label in pairs(e.playerLabels) do
      local creature=c.getCreatureById(id)
      if creature and creature:getName()==label.name and creature.getText and creature.setText and creature:getText()==label.text then creature:setText(label.previous,'#ffffff') end
    end
    e.playerLabels={}
  end
  function e.updatePlayerLabels(visible)
    if not visible or not h.playerInfo then e.clearPlayerLabels();return end
    local seen={};local vocs={[1]='S',[2]='D',[3]='P',[4]='K',[5]='MS',[6]='ED',[7]='RP',[8]='EK'}
    for _,creature in ipairs(c.getSpectators()) do if creature~=c.player and creature:isPlayer() and creature.setText and creature.getText then
      local id=creature:getId();seen[id]=true;local info=e.playerInfo(creature);local lines={}
      if h.vocation then lines[#lines+1]=(info.level and tostring(info.level) or '?')..(vocs[info.vocation] or '')..' | '..info.hp..'%' end
      if h.guild and info.guild and info.guild~='' then lines[#lines+1]=info.guild end
      if h.mana and info.mana then lines[#lines+1]='MP '..(info.estimated and '~' or '')..info.mana..'/'..info.maxMana end
      local text=#lines>0 and '\n'..table.concat(lines,'\n') or ''
      local label=e.playerLabels[id]
      if not label or label.name~=creature:getName() then label={name=creature:getName(),previous=creature:getText() or ''};e.playerLabels[id]=label end
      -- Preserve a concurrent vBot/user edit as the value to restore later.
      local current=creature:getText() or '';if label.text and current~=label.text then label.previous=current end
      label.text=text;if current~=text then creature:setText(text,'#ffff00') end
    end end
    for id,label in pairs(e.playerLabels) do if not seen[id] then
      local creature=c.getCreatureById(id)
      if creature and creature:getName()==label.name and creature:getText()==label.text then creature:setText(label.previous,'#ffffff') end;e.playerLabels[id]=nil
    end end
  end
  function e.damagePerSecond()
    e.damageHistory:prune(c.now)
    local total=e.damageHistory.total
    return math.floor(total/math.max(1,math.min(10,(c.now-(e.firstDamage or c.now))/1000)))
  end
  function e.telemetryTick()
    if e.pendingLook and c.now-e.pendingLook.time>5000 then e.pendingLook=nil end
    e.damageHistory:prune(c.now)
    if c.now<(e.nextTelemetry or 0) then return end;e.nextTelemetry=c.now+250
    ElfBotHistory.prune(e.playerCache,c.now,300000,256)
    for id,time in pairs(e.deadIds or {}) do if c.now-time>10000 then e.deadIds[id]=nil end end
    local p=c.pos();if not p then return end;local old=e.lastPosition
    if not old or p.x~=old.x or p.y~=old.y or p.z~=old.z then e.lastMove=c.now;e.lastPosition=p end
    for key,wall in pairs(e.walls) do
      local remaining=wall.expires-c.now
      local tile=c.g_map.getTile(wall.position)
      if tile and tile.setTimer then
        if h.wallTimers and remaining>0 then tile:setTimer(remaining,'#ffff00');wall.drawn=true
        elseif wall.drawn then tile:setTimer(0,'#ffffff');wall.drawn=false end
      end
      if remaining<=0 then e.walls[key]=nil end
    end
    for key,expires in pairs(e.spellTimers) do if expires<=c.now then e.spellTimers[key]=nil end end
    for _,box in pairs(e.listboxes) do for i=#box.lines,1,-1 do if c.now-box.lines[i].time>box.lifetime then table.remove(box.lines,i) end end end
    if d.botEnabled~=false and not e.paused and h.playerInfo and h.autoLook and c.now>=(e.nextLook or 0) then
      e.nextLook=c.now+1000
      local players=c.getSpectators()
      for _,creature in ipairs(players) do if creature~=c.player and creature:isPlayer() then
        local info=e.playerCache[creature:getName():lower()]
        if not info or (h.updateCache and c.now-(info.updated or 0)>30000) then
          if c.g_game.look then c.g_game.look(creature);e.pendingLook={name=creature:getName(),time=c.now} end;break
        end
      end end
    end
  end
end
