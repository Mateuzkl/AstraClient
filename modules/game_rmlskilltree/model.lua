-- A local-only UI laboratory. No game state, settings, packets or server APIs.
SkillTreeDemo = {}
local Demo = SkillTreeDemo
local State = {}
State.__index = State

Demo.width, Demo.height = 550, 506
Demo.nodeSize = 56
Demo.startingPoints = 9999
Demo.categories = {
  {id=1, name='Combate', role='GUERREIRO', icon='berserk', color='green',
    summary='Força, disciplina e experiência moldam guerreiros capazes de superar qualquer desafio.', primary='Dano físico', secondary='Chance crítica',
    names={'Vocação da Lâmina','Punhos de Aço','Instinto de Batalha','Lâmina Afiada','Vigor de Guerra','Postura Inabalável','Passos Ligeiros','Investida Precisa','Coração do Guerreiro','Guarda de Aço','Golpe Brutal','Fúria das Lâminas','Bastião','Segundo Fôlego','Chama Interior','Execução','Avatar de Aço','Tempestade de Golpes','Alma Indomável','Última Resistência','Lenda da Guerra','Determinação'},
    icons={'berserk','trainparty','protector','frontsweep','woundcleansing','protectparty','haste','whirlwindthrow','avatarofsteel','magicshield','brutalstrike','fierceberserk','protector','ultimatehealing','soulfire','annihilation','avatarofsteel','energystrike','bloodrage','protector','knightsummon','charge'}},
  {id=2, name='Defesa', role='GUARDIÃO', icon='protector', color='blue',
    summary='Uma muralha viva. Resista ao impossível e proteja aqueles que lutam ao seu lado.', primary='Resistência física', secondary='Bloqueio',
    names={'Juramento do Guardião','Pele de Pedra','Vigilância','Armadura Viva','Vitalidade','Escudo Sagrado','Passo Seguro','Muralha de Ferro','Coração de Titã','Proteção Coletiva','Contra-ataque','Reflexos de Aço','Fortaleza','Renovação','Selo Protetor','Provocação','Avatar da Guarda','Égide Arcana','Alma de Pedra','Resistência Final','Guardião Eterno','Inabalável'},
    icons={'protector','protectparty','magicshield','trainparty','woundcleansing','divinehealing','haste','magicwall','avatarofsteel','protectparty','brutalstrike','charge','protector','ultimatehealing','divineempowerment','challenge','avataroflight','magicshield','stalagmite','salvation','knightsummon','protector'}},
  {id=3, name='Suporte', role='ORÁCULO', icon='healfriend', color='blue',
    summary='Cada vida importa. Cure, inspire e transforme uma batalha perdida em uma nova chance.', primary='Poder de cura', secondary='Recuperação',
    names={'Chamado da Vida','Mãos Curadoras','Visão Serena','Bênção Vital','Rejuvenescimento','Santuário','Brisa Leve','Elo da Vida','Coração da Natureza','Aura de Proteção','Cura Profunda','Restauração','Refúgio','Esperança','Chama Vital','Purificação','Avatar da Vida','Maré Curativa','Espírito Livre','Última Bênção','Luz Eterna','Renascimento'},
    icons={'healfriend','lighthealing','greatlight','intensehealing','woundcleansing','protectparty','haste','healparty','avatarofnature','magicshield','ultimatehealing','masshealing','wildgrowth','salvation','divinehealing','curepoison','avatarofnature','healparty','levitate','ultimatehealingrune','druidsummon','healfriend'}},
  {id=4, name='Magia', role='ARCANISTA', icon='energywave', color='violet',
    summary='Domine as forças elementais. Conhecimento, foco e poder abrem caminhos onde não havia nenhum.', primary='Poder mágico', secondary='Eficiência de mana',
    names={'Despertar Arcano','Foco Elemental','Mente Cristalina','Lança de Fogo','Reservatório Arcano','Barreira Mística','Fluxo Etéreo','Pulso Arcano','Coração da Tempestade','Égide de Mana','Explosão Arcana','Ruptura Elemental','Prisão de Gelo','Fonte de Mana','Fogo Eterno','Toque Sombrio','Avatar da Tempestade','Relâmpago','Asas do Éter','Último Feitiço','Ascensão Arcana','Vontade Infinita'},
    icons={'energywave','energystrike','magicshield','flamestrike','enchantparty','magicwall','haste','energybeam','avatarofstorm','magicshield','greatfireball','rageoftheskies','eternalwinter','food','hellscore','suddendeath','avatarofstorm','thunderstorm','levitate','energybomb','sorcerersummon','stronghaste'}},
  {id=5, name='Especial', role='LENDÁRIO', icon='avatarofsteel', color='gold',
    summary='Talentos raros para um destino extraordinário. Escreva uma história que mereça ser lembrada.', primary='Poder lendário', secondary='Maestria',
    names={'Sinal do Destino','Instinto Heróico','Olhar do Campeão','Corte do Destino','Vontade Heroica','Pacto de Honra','Passo do Vento','Ímpeto do Herói','Coração do Dragão','Juramento Sagrado','Golpe do Campeão','Duelo Perfeito','Escudo do Destino','Sopro da Vida','Fogo do Dragão','Marca da Vitória','Avatar Lendário','Raio Celeste','Espírito do Herói','Último Juramento','Legado Imortal','Eternidade'},
    icons={'avatarofsteel','trainparty','challenge','frontsweep','bloodrage','protectparty','swiftfoot','charge','avataroflight','magicshield','annihilation','fierceberserk','protector','divinehealing','hellscore','suddendeath','avatarofsteel','thunderstorm','divineempowerment','salvation','paladinsummon','avatarofnature'}},
}

-- x/y are centers. Prerequisites form an acyclic graph; the last keystone joins both branches.
local layout = {
  {275,42,3,1,{}}, {174,112,3,10,{{1,1}}}, {376,112,3,10,{{1,1}}},
  {72,182,3,15,{{2,1}}}, {174,182,3,15,{{2,1}}}, {376,182,3,20,{{3,3}}}, {478,182,3,15,{{3,1}}},
  {123,252,3,20,{{4,2}}}, {275,252,1,40,{{5,2},{7,3}}}, {427,252,3,20,{{7,2}}},
  {72,322,3,20,{{8,3}}}, {174,322,3,30,{{8,2}}}, {376,322,3,30,{{10,3}}}, {478,322,3,25,{{10,1}}},
  {72,392,3,40,{{11,2}}}, {174,392,3,45,{{12,2}}}, {275,392,1,60,{{9,1},{11,3},{13,2}}},
  {376,392,3,45,{{13,2}}}, {478,392,3,40,{{14,2}}},
  {174,462,3,70,{{15,3},{16,2}}}, {275,462,1,100,{{17,1},{20,1},{22,1}}}, {376,462,3,70,{{18,2},{19,3}}},
}
local seeded = {[1]=3,[2]=3,[3]=2,[4]=2,[5]=1,[7]=3,[8]=3,[10]=2,[11]=1,[14]=1}
local function validIndex(value, count)
  return type(value) == 'number' and value == math.floor(value) and value >= 1 and value <= count
end

function Demo.new()
  local self = setmetatable({category=1, selected=11, level=100, points=Demo.startingPoints, ranks={}}, State)
  for category=1,#Demo.categories do
    self.ranks[category]={}
    for id=1,#layout do self.ranks[category][id] = category == 1 and (seeded[id] or 0) or 0 end
  end
  self.budget=self.points+self:spent(1)
  return self
end

function State:node(id, category)
  category = category or self.category
  if not validIndex(category, #Demo.categories) or not validIndex(id, #layout) then return nil end
  local spec, tree = layout[id], Demo.categories[category]
  return {id=id, name=tree.names[id], icon=tree.icons[id], x=spec[1], y=spec[2], max=spec[3],
    minLevel=spec[4], requires=spec[5], cost=spec[3] == 1 and 2 or 1,
    rank=self.ranks[category][id], keystone=spec[3] == 1,
    branch=(spec[3] == 1 or id == 1) and 'gold' or (spec[1] < Demo.width/2 and 'green' or 'blue')}
end

function State:selectCategory(id)
  if not validIndex(id, #Demo.categories) then return false end
  self.category, self.selected = id, 1
  return true
end
function State:select(id)
  if not validIndex(id, #layout) then return false end
  self.selected=id
  return true
end
function State:canUpgrade(id)
  local node=self:node(id or self.selected)
  if not node then return false, 'Talento inválido.' end
  if node.rank >= node.max then return false, 'Talento no nível máximo.' end
  if self.level < node.minLevel then return false, 'Nível de demonstração insuficiente.' end
  for _, req in ipairs(node.requires) do
    if self.ranks[self.category][req[1]] < req[2] then
      return false, string.format('Requer %s (%d/%d).', Demo.categories[self.category].names[req[1]], self.ranks[self.category][req[1]], req[2])
    end
  end
  if self.points < node.cost then return false, 'Pontos insuficientes. Use Repor para receber 9.999 pontos de teste.' end
  return true, 'Pronto para evoluir.'
end
function State:upgrade()
  local allowed, reason=self:canUpgrade()
  if not allowed then return false, reason end
  local node=self:node(self.selected)
  self.ranks[self.category][node.id]=node.rank+1
  self.points=self.points-node.cost
  return true, string.format('%s evoluiu para %d/%d. Apenas nesta demonstração.', node.name, node.rank+1, node.max)
end
function State:spent(category)
  local points=0
  for id=1,#layout do local n=self:node(id, category); points=points+n.rank*n.cost end
  return points
end
function State:reset()
  local refund=self:spent(self.category)
  for id=1,#layout do self.ranks[self.category][id]=0 end
  self.points=self.points+refund
  return refund
end
function State:refill()
  -- Reset the available demo budget, rather than growing it on repeated clicks.
  local spent=0
  for category=1,#Demo.categories do spent=spent+self:spent(category) end
  self.points=Demo.startingPoints
  self.budget=spent+self.points
end
function State:path(id)
  local result={}
  local function visit(current)
    if result[current] then return end
    local node=self:node(current)
    if not node then return end
    result[current]=true
    for _,req in ipairs(node.requires) do visit(req[1]) end
  end
  visit(id or self.selected)
  return result
end
function State:nextRequired(id)
  local node=self:node(id or self.selected)
  if not node then return nil end
  for _,req in ipairs(node.requires) do
    if self.ranks[self.category][req[1]] < req[2] then
      local earlier,rank=self:nextRequired(req[1])
      return earlier or req[1],rank or req[2]
    end
  end
end
function State:bonuses(node,rank)
  rank=rank or node.rank
  return (node.keystone and 20 or (node.id == 11 and 8 or 4))*rank,(node.id == 11 and 3 or 2)*rank
end
function State:build()
  local result={points=self.points,spent=0,count=0,capacity=0,trees={},skills={}}
  for category,tree in ipairs(Demo.categories) do
    local entry={name=tree.name,primary=tree.primary,secondary=tree.secondary,spent=0,count=0,power=0,bonus=0}
    for id=1,#layout do
      local node=self:node(id,category)
      result.capacity=result.capacity+node.max*node.cost
      if node.rank > 0 then
        local power,bonus=self:bonuses(node)
        entry.spent=entry.spent+node.rank*node.cost
        entry.count,entry.power,entry.bonus=entry.count+1,entry.power+power,entry.bonus+bonus
        result.skills[#result.skills+1]={category=tree.name,name=node.name,icon=node.icon,rank=node.rank,max=node.max}
      end
    end
    result.trees[#result.trees+1]=entry
    result.spent,result.count=result.spent+entry.spent,result.count+entry.count
  end
  return result
end
function State:nodes()
  local result={}
  for id=1,#layout do result[id]=self:node(id) end
  return result
end
