-- Local-only allocation model: conservation, graph safety and every category.
dofile('modules/game_rmlskilltree/model.lua')
local D=SkillTreeDemo
local function conserved(s)
  local spent=0
  for category=1,#D.categories do spent=spent+s:spent(category) end
  assert(s.points+spent == s.budget and s.points >= 0 and s.points <= s.budget)
end
local s=D.new()
assert(s.points == 9999 and s:spent(1) == 21 and s.selected == 11)
assert(#D.categories == 5 and #s:nodes() == 22)
local expected={'','1:1','1:1','2:1','2:1','3:3','3:1','4:2','5:2,7:3','7:2','8:3','8:2','10:3','10:1','11:2','12:2','9:1,11:3,13:2','13:2','14:2','15:3,16:2','17:1,20:1,22:1','18:2,19:3'}
for category=1,5 do
  for id=1,22 do
    local n=s:node(id,category)
    local req={}
    for _,r in ipairs(n.requires) do req[#req+1]=r[1] .. ':' .. r[2] end
    assert(table.concat(req,',') == expected[id], 'compact layout changed prerequisite identity')
    assert(n.x-30 >= 0 and n.x+30 <= D.width and n.y-33 >= 0 and n.y+36 <= D.height)
    for other=id+1,22 do
      local b=s:node(other,category)
      assert(math.abs(n.x-b.x) >= 64 or math.abs(n.y-b.y) >= 68, 'overlapping nodes/rank badges')
    end
  end
end
local build=s:build()
assert(build.count == 10 and build.spent == 21 and #build.skills == 10 and #build.trees == 5)
assert(build.trees[1].power == 88 and build.trees[1].bonus == 43)
local path=s:path()
for _,id in ipairs({1,2,4,8,11}) do assert(path[id], 'missing connected ancestor ' .. id) end
assert(not path[3] and not s:nextRequired())
conserved(s)
local before=s.points
assert(s:upgrade() and s.points == before-1 and s:node(11).rank == 2)
assert(s:select(6))
local allowed,reason=s:canUpgrade()
assert(not allowed and reason:find('Requer',1,true))
local required,rank=s:nextRequired()
assert(required == 3 and rank == 3)
before=s.points
assert(not s:upgrade() and before == s.points)
assert(not s:select(-1) and not s:select(1.5) and not s:selectCategory(6))
local root,visited,visiting=1,{},{}
local function visit(id)
  assert(not visiting[id], 'cyclic prerequisite graph')
  if visited[id] then return end
  visiting[id]=true
  for _,req in ipairs(s:node(id).requires) do assert(s:node(req[1])); visit(req[1]) end
  visiting[id]=nil; visited[id]=true
end
for id=1,22 do visit(id) end
assert(s:reset() == 22 and s.points == s.budget)
assert(s:select(21))
required,rank=s:nextRequired()
assert(required == 1 and rank == 1, 'guide skipped an earlier locked prerequisite')
for id in pairs(s:path()) do assert(s:node(id), 'invalid ancestor in highlighted path') end
assert(s:select(1) and s:upgrade())
assert(s:reset() == 1)
for category=1,5 do
  assert(s:selectCategory(category))
  for _,node in ipairs(s:nodes()) do assert(node.name ~= '' and node.icon ~= '' and type(node.branch) == 'string') end
  s.level=0
  assert(not s:canUpgrade(root))
  s.level=100
  for round=1,30 do
    local changed=false
    for id=1,22 do s:select(id); if s:canUpgrade() then assert(s:upgrade()); changed=true end end
    conserved(s)
    if not changed then break end
  end
  for id=1,22 do assert(s:node(id).rank == s:node(id).max, 'unreachable talent ' .. id) end
  assert(not s:nextRequired())
  assert(s:build().count == 22)
  assert(not s:upgrade())
  assert(s:reset() > 0)
  conserved(s)
end
assert(s.points == s.budget)
for i=1,200 do s:refill();conserved(s) end
assert(s.points == 9999 and s.budget == 9999, 'refill inflated the budget')
s:select(1);assert(s:upgrade());s:refill()
assert(s.points == 9999 and s.budget == 10000 and s:node(1).rank == 1)
s:refill();assert(s.budget == 10000)
local empty=s:path(-1);assert(not next(empty) and not s:nextRequired(-1))
-- The module must never reach gameplay/settings APIs, even when all buttons are used.
local source=assert(io.open('modules/game_rmlskilltree/skilltree.lua','rb'))
local code=source:read('*a'); source:close()
for _,forbidden in ipairs({'g_game%.','g_settings%.','sendExtendedOpcode','sendOpcode','castSpell','setOutfit'}) do
  assert(not code:find(forbidden), 'demo reached a game/persistence API: ' .. forbidden)
end
assert(not code:find('loadFontFace',1,true), 'opening a skill tree reloaded startup fonts')
print('RmlUi skill tree: PASS (9999 points, 110 talents, connected paths, build summary, refunds and local-only boundary)')
