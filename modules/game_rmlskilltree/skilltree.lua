-- UI-only demo. All allocation rules live in model.lua; no gameplay APIs are called.
local M = {}
local SHORTCUT = 'Ctrl+Shift+K'
local fallbackIcons = {berserk=21,trainparty=120,protector=122,frontsweep=20,woundcleansing=3,
  protectparty=123,haste=101,whirlwindthrow=19,avatarofsteel=149,magicshield=124,brutalstrike=23,
  fierceberserk=22,ultimatehealing=1,soulfire=67,annihilation=24,energystrike=29,bloodrage=96,
  knightsummon=143,charge=98,divinehealing=2,magicwall=72,divineempowerment=159,challenge=97,
  salvation=60,avataroflight=151,stalagmite=66,healfriend=8,lighthealing=6,greatlight=116,
  intensehealing=7,healparty=126,avatarofnature=150,masshealing=9,wildgrowth=61,curepoison=10,
  levitate=125,ultimatehealingrune=62,druidsummon=144,energywave=43,flamestrike=26,
  enchantparty=113,energybeam=41,avatarofstorm=152,greatfireball=78,rageoftheskies=52,
  eternalwinter=50,food=99,hellscore=49,suddendeath=64,thunderstorm=63,energybomb=86,
  sorcerersummon=146,stronghaste=102,swiftfoot=119,paladinsummon=145}

local function icon(key)
  local entry=SpellIcons and SpellIcons[key]
  local frame=entry and tonumber(entry[1]) or fallbackIcons[key] or 21
  if frame < 1 or frame > 200 or frame ~= math.floor(frame) then frame=21 end
  return 'image(st-spell-' .. frame .. ' contain)'
end
local function text(value) return Rml.text(value) end
local function effects(node, rank)
  if rank == 0 then return 'Ainda não desbloqueado.' end
  local tree=SkillTreeDemo.categories[M.state.category]
  local power,secondary=M.state:bonuses(node,rank)
  return string.format('%s: +%d%%   •   %s: +%d%%', tree.primary, power, tree.secondary, secondary)
end

local function links(nodes,path)
  local result={}
  local function segment(x,y,w,h,color,active,onPath)
    result[#result+1]={left=x .. 'dp',top=y .. 'dp',width=math.max(2,w) .. 'dp',height=math.max(2,h) .. 'dp',color=color,active=active,onPath=onPath}
  end
  for _, child in ipairs(nodes) do
    for _, req in ipairs(child.requires) do
      local parent=nodes[req[1]]
      local ready=parent.rank >= req[2]
      local active=ready and child.rank > 0
      local onPath=path[child.id] == true and path[parent.id] == true
      local color=(active or onPath) and child.branch or 'dim'
      local radius=SkillTreeDemo.nodeSize/2
      if parent.y == child.y then
        segment(math.min(parent.x,child.x)+radius,parent.y,math.abs(parent.x-child.x)-2*radius,2,color,active,onPath)
      else
        local x1,y1,x2,y2=parent.x,parent.y+radius+7,child.x,child.y-radius-3
        -- Wrap long cross-branch prerequisites at a common tier, behind the nodes.
        local bend=math.floor((y1+y2)/2)
        segment(x1,math.min(y1,bend),2,math.abs(bend-y1),color,active,onPath)
        segment(math.min(x1,x2),bend,math.abs(x2-x1)+2,2,color,active,onPath)
        segment(x2,math.min(bend,y2),2,math.abs(y2-bend),color,active,onPath)
      end
    end
  end
  return result
end

local function refresh(message)
  if not M.window or M.window:isDestroyed() or not M.model then return end
  local state,model=M.state,M.model
  local category=SkillTreeDemo.categories[state.category]
  local nodes=state:nodes()
  local path=state:path()
  local view={}
  for _, node in ipairs(nodes) do
    local allowed=state:canUpgrade(node.id)
    view[#view+1]={id=node.id,name=text(node.name),left=(node.x-SkillTreeDemo.nodeSize/2) .. 'dp',top=(node.y-SkillTreeDemo.nodeSize/2) .. 'dp',
      rank=node.rank,max=node.max,icon=icon(node.icon),selected=node.id == state.selected,
      owned=node.rank > 0,locked=node.rank == 0 and not allowed,available=allowed,
      onPath=path[node.id] == true,
      keystone=node.keystone,green=node.branch == 'green',blue=node.branch == 'blue',gold=node.branch == 'gold'}
  end
  local selected=nodes[state.selected]
  local allowed,reason=state:canUpgrade()
  local reqs={}
  for _, req in ipairs(selected.requires) do
    local parent=nodes[req[1]]
    reqs[#reqs+1]={name=text(parent.name),rank=parent.rank,required=req[2],met=parent.rank >= req[2],icon=icon(parent.icon)}
  end
  local power,secondary=state:bonuses(selected,1)
  local build=state:build()
  model.nodes,model.links=view,links(nodes,path)
  model.category,model.categoryName,model.role=state.category,text(category.name),text(category.role)
  model.summary=text(category.summary)
  model.points,model.budget,model.spent,model.level=state.points,state.budget,state.budget-state.points,state.level
  model.categorySpent=state:spent(state.category)
  model.capacity,model.buildCount=build.capacity,build.count
  model.progress=math.floor(build.spent/build.capacity*100) .. '%'
  model.selectedName,model.selectedIcon=text(selected.name),icon(selected.icon)
  model.description=text(string.format('Aprimora %s em %d%% e concede %d%% de %s a cada nível.', category.primary:lower(),power,secondary,category.secondary:lower()))
  model.rank,model.max,model.minLevel,model.cost=selected.rank,selected.max,selected.minLevel,selected.cost
  model.currentEffect=text(effects(selected,selected.rank))
  model.nextEffect=text(effects(selected,math.min(selected.max,selected.rank+1)))
  model.requirements,model.hasRequirements=reqs,#reqs > 0
  model.levelMet,model.pointsMet=state.level >= selected.minLevel,state.points >= selected.cost
  model.canUpgrade,model.maxed=allowed,selected.rank == selected.max
  model.reason=text(reason)
  local required,requiredRank=state:nextRequired()
  model.hasMissing=required ~= nil
  model.nextRequired=required and text(string.format('Primeiro: %s (%d/%d)',nodes[required].name,nodes[required].rank,requiredRank)) or ''
  model.upgradeLabel=selected.rank == selected.max and 'Nível máximo' or (selected.rank > 0 and 'Evoluir talento' or 'Desbloquear')
  if model.showBuild then
    local trees,skills={},{}
    for _,entry in ipairs(build.trees) do
      trees[#trees+1]={name=text(entry.name),spent=entry.spent,count=entry.count,
        effects=text(string.format('%s +%d%% / %s +%d%%',entry.primary,entry.power,entry.secondary,entry.bonus))}
    end
    for _,entry in ipairs(build.skills) do
      skills[#skills+1]={name=text(entry.name),category=text(entry.category),rank=entry.rank,max=entry.max,icon=icon(entry.icon)}
    end
    model.buildTrees,model.buildSkills=trees,skills
  end
  if message then model.status=text(message) end
end

local function fit(window)
  if not M.model or window:isDestroyed() then return end
  local body=Rml.element(window,'skill-body')
  if body then
    local height=window:getWidth() <= 800 and math.max(180,math.floor(body.client_height)-95) .. 'dp' or '100%'
    if M.model.panelHeight ~= height then M.model.panelHeight=height end
  end
  local viewport=Rml.element(window,'tree-viewport')
  if not viewport then return end
  local w,h=math.floor(viewport.client_width),math.floor(viewport.client_height)
  if w <= 0 or h <= 0 or (M.fitWidth == w and M.fitHeight == h) then return end
  M.fitWidth,M.fitHeight=w,h
  -- Keep nodes readable: narrow viewports scroll instead of shrinking icons away.
  local scale=math.max(0.9,math.min(1,w/SkillTreeDemo.width,h/SkillTreeDemo.height))
  M.model.treeTransform=string.format('scale(%.4f)',scale)
  M.model.treeLeft=math.max(0,(w-SkillTreeDemo.width*scale)/2) .. 'dp'
  M.model.treeTop=math.max(0,(h-SkillTreeDemo.height*scale)/2) .. 'dp'
  M.model.treeWidth=math.max(w,math.ceil(SkillTreeDemo.width*scale)) .. 'dp'
  M.model.treeHeight=math.max(h,math.ceil(SkillTreeDemo.height*scale)) .. 'dp'
end

local function availableSize()
  local root,screen=rootWidget:getSize(),g_window.getSize()
  return math.max(1,math.min(root.width,screen.width)-24),math.max(1,math.min(root.height,screen.height)-24)
end
local function resizeToRoot()
  if not M.window or M.window:isDestroyed() then return end
  local w,h=availableSize()
  M.window:setSize({width=math.min(M.compact and 960 or 1100,w),height=math.min(M.compact and 640 or 720,h)})
end
local function toggleSize()
  if not M.window or M.window:isDestroyed() then return end
  M.compact=not M.compact
  local w,h=availableSize()
  M.window:setSize({width=math.min(M.compact and 960 or 1100,w),height=math.min(M.compact and 640 or 720,h)})
end

local function open()
  if not Rml.isAvailable() then return nil end
  M.state=M.state or SkillTreeDemo.new()
  local categories={}
  for _, category in ipairs(SkillTreeDemo.categories) do categories[#categories+1]={id=category.id,name=text(category.name),icon=icon(category.icon)} end
  local availableWidth,availableHeight=availableSize()
  local width,height=math.min(1100,availableWidth),math.min(720,availableHeight)
  local window,model=Rml.createWindow{
    id='rmlSkillTreeDemo',document='/modules/game_rmlskilltree/skilltree.rml',model='skilltree',width=width,height=height,
    data={categories=categories,nodes={},links={},category=1,categoryName='',role='',summary='',points=0,budget=0,capacity=0,buildCount=0,
      spent=0,categorySpent=0,level=100,progress='0%',selectedName='',selectedIcon=icon('brutalstrike'),description='',rank=0,max=3,
      minLevel=20,cost=1,currentEffect='',nextEffect='',requirements={},hasRequirements=false,canUpgrade=false,maxed=false,
      levelMet=true,pointsMet=true,reason='',upgradeLabel='Desbloquear',showHelp=false,showReset=false,
      showBuild=false,buildTrees={},buildSkills={},hasMissing=false,nextRequired='',
      treeTransform='scale(1)',treeLeft='0dp',treeTop='0dp',treeWidth='550dp',treeHeight='506dp',panelHeight='100%',status=text('Demonstração local. Nenhuma habilidade real será alterada.'),
      Resize=toggleSize,
      Select=function(_,id)
        if M.state:select(tonumber(id)) then
          local _,reason=M.state:canUpgrade()
          refresh(reason .. ' O caminho deste talento está destacado na árvore.')
        end
      end,
      Category=function(_,id) if M.state:selectCategory(tonumber(id)) then refresh('Comece no talento do topo e siga as conexões iluminadas.') end end,
      Upgrade=function() local _,message=M.state:upgrade(); refresh(message) end,
      Refill=function() M.state:refill();refresh('Saldo reposto: 9.999 pontos fictícios. Seus talentos foram preservados.') end,
      NextRequired=function()
        local id=M.state:nextRequired()
        if id then M.state:select(id);refresh('Este é o próximo passo do caminho. Use Desbloquear / Evoluir para investir.') end
      end,
      Build=function() M.model.showBuild=not M.model.showBuild;refresh() end,
      Reset=function() M.model.showReset=true end,
      CancelReset=function() M.model.showReset=false end,
      ConfirmReset=function()
        M.model.showReset=false
        local refunded=M.state:reset()
        refresh(string.format('%d pontos devolvidos. Somente a categoria atual foi reiniciada.',refunded))
      end,
      Help=function() M.model.showHelp=not M.model.showHelp end,
    },
    onClose=function() M.window=nil;M.model=nil;M.fitWidth=nil;M.fitHeight=nil end,
  }
  if not window then return nil end
  M.window,M.model=window,model
  M.compact=false
  connect(rootWidget,{onGeometryChange=resizeToRoot})
  connect(window,{onDestroy=function()
    disconnect(rootWidget,{onGeometryChange=resizeToRoot})
    if M.window == window then M.window=nil;M.model=nil;M.fitWidth=nil;M.fitHeight=nil end
  end,onRmlLayout=fit})
  refresh()
  return window
end

function toggle() Rml.toggle(M,'window',open) end
function init()
  if not Rml.isAvailable() then return end
  g_keyboard.bindKeyDown(SHORTCUT,toggle)
  if modules.client_topmenu then
    M.button=modules.client_topmenu.addLeftButton('rmlSkillTreeDemoButton',text('Árvore de Skills • demonstração (Ctrl+Shift+K)'),'/images/topbuttons/skillWheelDialog',toggle)
  end
end
function terminate()
  g_keyboard.unbindKeyDown(SHORTCUT,toggle)
  if M.window and not M.window:isDestroyed() then M.window:destroy() end
  if M.button then M.button:destroy();M.button=nil end
  M.window,M.model,M.state=nil,nil,nil
end
