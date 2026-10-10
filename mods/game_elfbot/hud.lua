-- Classic map-aligned defaults, with dragging across the entire client window.
-- Use the existing ElfBot pulse, not another macro or scheduling chain.
function createElfBotHud(e,c,data,layer,mapPanel)
  local h=data.hud
  local dragging={}
  local function finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
  local function clamp(n,max) return math.max(0,math.min(n,math.max(0,max))) end
  local function position(key)
    local p=dragging[key] and dragging[key].position or type(h.dragPositions)=='table' and h.dragPositions[key]
    if type(p)=='table' and finite(p.x) and finite(p.y) then return {x=clamp(p.x,1),y=clamp(p.y,1),space=p.space} end
  end
  local function fitText(v,width,rows)
    local natural=1
    for _,row in ipairs(rows) do natural=math.max(natural,row:getTextSize().width+2) end
    width=math.min(width,natural);v:setWidth(width)
    for _,row in ipairs(rows) do row:setWidth(width) end
    return width
  end
  local function panel(id)
    local v=g_ui.createWidget('ElfBotHudPanel',layer)
    v:setId(id);v:addAnchor(AnchorLeft,'parent',AnchorLeft);v:addAnchor(AnchorTop,'parent',AnchorTop)
    v:setTooltip('Hold the left mouse button and drag to move this HUD.')
    -- Only the visible HUD blocks receive clicks; the full-window layer stays phantom.
    v.onMousePress=function() return true end
    v.onMouseRelease=function() return true end
    v.onDragEnter=function(self,mouse)
      if self:isDestroyed() or not self:isVisible() then return false end
      local rows={};for _,row in ipairs(self:getChildren()) do if row:isVisible() then rows[#rows+1]=row end end
      fitText(self,self:getSize().width,rows)
      local p=self:getPosition()
      dragging[id]={offset={x=mouse.x-p.x,y=mouse.y-p.y}}
      self:raise();layer:raise();return true
    end
    v.onDragMove=function(self,mouse)
      local drag=dragging[id]
      if not drag or self:isDestroyed() or not self:isVisible() then return false end
      local rect,size=layer:getPaddingRect(),self:getSize()
      local width,height=math.max(0,rect.width-size.width),math.max(0,rect.height-size.height)
      local x=clamp(mouse.x-drag.offset.x-rect.x,width)
      local y=clamp(mouse.y-drag.offset.y-rect.y,height)
      -- Window-relative coordinates allow crossing the map edge and side panels.
      drag.position={x=width>0 and x/width or 0,y=height>0 and y/height or 0,space='window'}
      self:setMarginLeft(math.floor(x));self:setMarginTop(math.floor(y));return true
    end
    v.onDragLeave=function(self)
      local drag=dragging[id];dragging[id]=nil
      if drag and drag.position and not self:isDestroyed() and layer:isVisible() and e.hudVisible~=false then
        if type(h.dragPositions)~='table' then h.dragPositions={} end
        h.dragPositions[id]=drag.position;data.awaitingLoad=nil;c.saveConfig()
      end
      -- Consume the release so moving the HUD cannot make the character walk.
      return true
    end
    return v
  end
  local stats,skills=panel('elfbotHudStats'),panel('elfbotHudSkills')
  local statsRows,skillRows={},{}
  local api={}
  local WHITE, GOLD, BLUE='#ffffff','#ffd479','#4fc3f7'
  local MAX_ROWS=32
  local function add(lines,text,color) lines[#lines+1]={text=tostring(text),color=color or WHITE} end
  local function sortedKeys(values)
    local keys={};for key in pairs(values) do keys[#keys+1]=key end;table.sort(keys);return keys
  end
  local function generalRows(session)
    local lines={}
    if h.general then
      add(lines,c.name()..' | Level '..c.level(),GOLD)
      add(lines,string.format('HP %s/%s (%s%%) | MP %s/%s (%s%%)',
        ElfBotSession.formatNumber(c.hp()),ElfBotSession.formatNumber(c.maxhp()),c.hppercent(),
        ElfBotSession.formatNumber(c.mana()),ElfBotSession.formatNumber(c.maxmana()),c.manapercent()))
      add(lines,'Session: '..session.timeText)
      if session.ready then
        add(lines,'XP gained: '..ElfBotSession.formatNumber(session.gained)..' | XP/hour: '..ElfBotSession.formatNumber(session.perHour))
      else add(lines,'XP: waiting for valid character statistics') end
    end
    if h.target then
      local target=c.g_game.getAttackingCreature()
      add(lines,'Target: '..(target and target:getName()..' ('..target:getHealthPercent()..'%)' or 'none'))
    end
    if h.active and data.botEnabled~=false and not e.paused then
      local count=0
      for _,job in ipairs(e.jobs) do
        local allowed=job.kind=='persistent' or (job.kind=='hotkey' and data.hotkeysEnabled) or
          (job.kind=='shortkey' and data.shortkeysEnabled) or (job.kind=='cave' and c.CaveBot and c.CaveBot.isOn())
        if allowed and job.active and job.row.enabled and not job.failed and not (job.env and job.env.hidden) then
          if count==0 then add(lines,'Active scripts',GOLD) end
          count=count+1
          if count<=8 then
            local text=(job.env and job.env.label) or job.iconName or (job.row.key and job.row.key~='' and job.row.key) or job.row.script or 'Script'
            add(lines,tostring(text):gsub('%s+',' '):sub(1,120))
          end
        end
      end
      if count>8 then add(lines,'... '..(count-8)..' more active scripts') end
    end
    if h.healing then
      local healing=data.healing or {}
      local enabled=data.botEnabled~=false and not e.paused and healing.enabled
      add(lines,enabled and 'Healing: ON' or 'Healing: OFF',enabled and '#99dd99' or '#bbbbbb')
      if enabled then
        local thresholds={}
        if healing.hiEnabled~=false then thresholds[#thresholds+1]='Hi '..(healing.hiHealth or 0)..'%' end
        if healing.loEnabled~=false then thresholds[#thresholds+1]='Lo '..(healing.loHealth or 0)..'%' end
        if healing.hpEnabled~=false then thresholds[#thresholds+1]='Potion '..(healing.hpHealth or 0)..'%' end
        if #thresholds>0 then add(lines,table.concat(thresholds,' | ')) end
      end
    end
    if h.damage then add(lines,'DPS (10 s): '..ElfBotSession.formatNumber(e.damagePerSecond())..' | Best hit: '..ElfBotSession.formatNumber(e.highestDamage or 0),GOLD) end
    if h.deathTimers then
      for i=math.max(1,#e.deaths-4),#e.deaths do
        local death=e.deaths[i];local age=c.now-death.time
        if age>=0 and age<=60000 then add(lines,death.name..' dead: '..math.floor(age/1000)..' s') end
      end
    end
    if h.wallTimers then
      for _,key in ipairs(sortedKeys(e.walls)) do
        local wall=e.walls[key];local remaining=wall.expires-c.now
        if remaining>0 then
          local p=wall.position
          add(lines,(wall.id==2130 and 'Wild growth' or 'Magic wall')..': '..math.ceil(remaining/1000)..' s ('..p.x..','..p.y..','..p.z..')')
        end
      end
    end
    if h.spellTimers then
      for _,key in ipairs(sortedKeys(e.spellTimers)) do
        local remaining=e.spellTimers[key]-c.now
        if remaining>0 then add(lines,key..': '..string.format('%.1f',remaining/1000)..' s') end
      end
    end
    if h.navigation then
      local origin=c.pos()
      for _,creature in ipairs(c.getSpectators()) do
        local p=creature:getPosition()
        if origin and p and creature~=c.player and creature:isPlayer() then
          local name=creature:getName()
          local friend=e.listContains('friends',name) or e.listContains('subfriends',name)
          local enemy=e.listContains('enemies',name) or e.listContains('subenemies',name)
          if friend or enemy then
            local rx,ry=p.x-origin.x,p.y-origin.y
            local relation=friend and 'Friend' or 'Enemy'
            if h.altNavigation then add(lines,string.format('%s %s: (%+d,%+d), floor %+d',relation,name,rx,ry,origin.z-p.z))
            else
              local direction=(ry<0 and 'north' or ry>0 and 'south' or '')..(rx<0 and 'west' or rx>0 and 'east' or '')
              if direction=='' then direction='here' end
              add(lines,relation..' '..name..': '..direction..' '..c.getDistanceBetween(origin,p)..' sq.')
            end
          end
        end
      end
      if e.exivaInfo and c.now-e.exivaInfo.time<=30000 then add(lines,e.exivaInfo.name..': '..e.exivaInfo.direction) end
    end
    return lines
  end
  local function skillLines()
    local lines={};if h.skills==false then return lines end
    local player=c.player
    local function read(method,id)
      if not player or type(player[method])~='function' then return end
      local n=player[method](player,id)
      if type(n)=='number' and n==n and n>=0 and n<math.huge then return n end
    end
    local function skill(name,value,percent,color,highlight)
      if value then
        color=color or WHITE;highlight=highlight or '#00ff00'
        local parts={'~ '..name..': ',color,tostring(value),highlight,percent and ' ('..percent..'%)' or '',color}
        add(lines,parts[1]..parts[3]..parts[5]);lines[#lines].colored=parts
      end
    end
    skill('Level',read('getLevel'),read('getLevelPercent'),'#ffff00','#ffff00')
    skill('Magic Level',read('getMagicLevel'),read('getMagicLevelPercent'),BLUE)
    -- Classic's selected 8.60 skills; no unsupported leech/critical placeholders.
    for _,entry in ipairs({{'Fist',0},{'Club',1},{'Distance',4},{'Shielding',5},{'Fishing',6}}) do
      skill(entry[1],read('getSkillLevel',entry[2]),read('getSkillLevelPercent',entry[2]))
    end
    local stamina=read('getStamina')
    if stamina then
      local value=string.format('%02d:%02d',math.floor(stamina/60),math.floor(stamina%60))
      local parts={'~ Stamina: ',WHITE,value,'#00ff00',' ('..math.floor(stamina*100/2520)..'%)',WHITE}
      add(lines,parts[1]..parts[3]..parts[5]);lines[#lines].colored=parts
    end
    return lines
  end
  -- Keep a small row pool. Wrap using actual font metrics without leaving the window.
  local function render(parent,pool,lines,x,y,width,height)
    parent:setMarginLeft(x);parent:setMarginTop(y);parent:setWidth(width)
    local used,visible=0,0
    for i=1,math.min(#lines,MAX_ROWS) do
      local row=pool[i]
      if not row then
        row=g_ui.createWidget('ElfBotHudText',parent)
        row:addAnchor(AnchorLeft,'parent',AnchorLeft);row:addAnchor(AnchorTop,'parent',AnchorTop)
        pool[i]=row
      end
      row:setWidth(width)
      local parts=lines[i].colored
      local signature=parts and table.concat(parts,'\0') or lines[i].text
      if row.elfHudSignature~=signature then
        if parts then row:setColoredText(parts) else row:setText(lines[i].text) end
        row.elfHudSignature=signature
      end
      row:setColor(parts and WHITE or lines[i].color)
      local size=math.max(14,row:getTextSize().height)
      if i<#lines and (i==MAX_ROWS or used+size+14>height) then
        row:setText('... '..(#lines-i+1)..' more');row.elfHudSignature=nil;size=math.max(14,row:getTextSize().height)
        if used+size>height then break end
        row:setMarginTop(used);row:setHeight(size);row:show();used=used+size;visible=i;break
      end
      if used+size>height then break end
      row:setMarginTop(used);row:setHeight(size);row:show();used=used+size;visible=i
    end
    for i=visible+1,#pool do pool[i]:hide() end
    parent:setHeight(math.max(1,used));parent:setVisible(used>0)
    return used,visible
  end
  function api.hide() dragging={};if not layer:isDestroyed() then layer:hide() end end
  function api.update(visible,session)
    if layer:isDestroyed() then return end
    if not visible or not h.enabled then api.hide();return end
    local rect=layer:getPaddingRect()
    if rect.width<48 or rect.height<28 then api.hide();return end
    local map=mapPanel:getPaddingRect()
    if map.width<48 or map.height<28 then map=rect end
    local general,sk=generalRows(session),skillLines()
    -- Use Classic positions until dragged; old numeric offset settings stay ignored.
    local mx,my=map.x-rect.x,map.y-rect.y
    local x,y=mx+8,my+8
    local width=math.min(380,map.width-16,rect.width-16)
    local skillWidth=math.min(230,map.width-16,rect.width-16)
    local sx=mx+math.max(8,map.width-100-skillWidth)
    local sy=my+5
    local statsPosition,skillsPosition=position('elfbotHudStats'),position('elfbotHudSkills')
    local beside=statsPosition or skillsPosition or #general==0 or sx>=x+width+12
    local available=map.height-16
    local reserve=not beside and #sk>0 and math.min(#sk*14+8,math.floor(available/2)) or 0
    local function draw(v,pool,lines,p,dx,dy,w,budget)
      if p and p.space=='window' then w=math.min(v==skills and 230 or 380,rect.width-16) end
      local used,visible=render(v,pool,lines,dx,dy,w,p and rect.height or math.max(0,budget))
      local rows={};for i=1,visible do rows[#rows+1]=pool[i] end
      w=fitText(v,w,rows)
      if p then
        -- Existing profiles used map-relative fractions; preserve their placement.
        local bounds=p.space=='window' and rect or map
        dx=bounds.x-rect.x+p.x*math.max(0,bounds.width-w)
        dy=bounds.y-rect.y+p.y*math.max(0,bounds.height-used)
      end
      v:setMarginLeft(math.floor(clamp(dx,rect.width-w)+0.5))
      v:setMarginTop(math.floor(clamp(dy,rect.height-used)+0.5))
      return used
    end
    local used=draw(stats,statsRows,general,statsPosition,x,y,width,available-reserve)
    if not beside then sx=x;sy=y+used+(used>0 and 8 or 0);skillWidth=math.min(skillWidth,width) end
    local skillUsed=draw(skills,skillRows,sk,skillsPosition,sx,sy,skillWidth,map.y+map.height-rect.y-sy-8)
    -- isVisible() includes HiddenState inherited from this still-hidden layer.
    -- Decide from rendered content instead, or the first show can never succeed.
    layer:setVisible(used>0 or skillUsed>0)
  end
  return api
end
