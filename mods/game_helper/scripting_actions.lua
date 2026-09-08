-- Restricted gameplay compatibility API for EloriaBot player scripts.
-- Every mutation below uses the normal game protocol. The server remains
-- authoritative; this module never exposes native objects or privileged state.
local actions = {}

_Helper = _Helper or {}
_Helper.ScriptingActions = actions

local actionBuckets = {}
local creatureRecords = setmetatable({}, { __mode = 'k' })
local containerRecords = setmetatable({}, { __mode = 'k' })
local inventoryRecords = setmetatable({}, { __mode = 'k' })

local ACTION_LIMITS = {
  movement = { rate = 20, burst = 8 },
  target = { rate = 10, burst = 4 },
  item = { rate = 12, burst = 6 },
  container = { rate = 10, burst = 5 },
  chat = { rate = 3, burst = 2 },
  look = { rate = 10, burst = 4 },
  mode = { rate = 5, burst = 3 },
  -- Panel commands are one-shot UI actions, not something a loop should spam.
  panel = { rate = 2, burst = 2 }
}

local SAFE_TALK_TYPES = { [1] = true, [2] = true, [3] = true, [11] = true }

local function integer(value, minimum, maximum)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
  value = math.floor(value)
  if value < minimum or value > maximum then return nil end
  return value
end

local function position(x, y, z)
  if type(x) == 'table' then
    z, y, x = x.z, x.y, x.x
  end
  x = integer(x, 0, 65534)
  y = integer(y, 0, 65534)
  z = integer(z, 0, 15)
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

local function copyPosition(pos)
  if not pos then return nil end
  return position(pos.x, pos.y, pos.z)
end

local function copyOutfit(outfit)
  if type(outfit) ~= 'table' then return nil end
  return {
    type = tonumber(outfit.type or outfit.lookType) or 0,
    typeEx = tonumber(outfit.auxType or outfit.typeEx or outfit.lookTypeEx) or 0,
    head = tonumber(outfit.head) or 0,
    body = tonumber(outfit.body) or 0,
    legs = tonumber(outfit.legs) or 0,
    feet = tonumber(outfit.feet) or 0,
    addons = tonumber(outfit.addons) or 0,
    mountId = tonumber(outfit.mount or outfit.mountId) or 0,
    mountHead = tonumber(outfit.mountHead) or 0,
    mountBody = tonumber(outfit.mountBody) or 0,
    mountLegs = tonumber(outfit.mountLegs) or 0,
    mountFeet = tonumber(outfit.mountFeet) or 0
  }
end

local function nativeCall(callback)
  local ok, value = pcall(callback)
  if not ok then return nil end
  return value
end

local function getLocalPlayer()
  if not g_game or not g_game.isOnline or not g_game.isOnline() then return nil end
  return g_game.getLocalPlayer()
end

local function consumeBudget(group)
  local limit = ACTION_LIMITS[group]
  if not limit then return false end
  local now = g_clock.millis()
  local bucket = actionBuckets[group]
  if not bucket or now < bucket.updated then
    bucket = { tokens = limit.burst, updated = now }
    actionBuckets[group] = bucket
  end
  local elapsed = math.max(0, now - bucket.updated)
  bucket.tokens = math.min(limit.burst, bucket.tokens + elapsed * limit.rate / 1000)
  bucket.updated = now
  if bucket.tokens < 1 then return false end
  bucket.tokens = bucket.tokens - 1
  return true
end

local function perform(group, callback)
  if not getLocalPlayer() or not consumeBudget(group) then return false end
  local ok, result = pcall(callback)
  if not ok or result == false then return false end
  return true
end

local function itemData(item, slot)
  if not item then return nil end
  local itemId = nativeCall(function() return item:getId() end)
  if not itemId then return nil end
  return {
    id = itemId,
    count = nativeCall(function() return item:getCount() end) or 1,
    subType = nativeCall(function() return item:getSubType() end) or 0,
    tier = nativeCall(function() return item:getTier() end) or 0,
    holdingCount = nativeCall(function() return item:getCount() end) or 1,
    slot = slot,
    position = copyPosition(nativeCall(function() return item:getPosition() end))
  }
end

local function creatureData(creature)
  if not creature then return nil end
  local creatureId = nativeCall(function() return creature:getId() end)
  if not creatureId then return nil end
  return {
    id = creatureId,
    name = nativeCall(function() return creature:getName() end),
    healthPercent = nativeCall(function() return creature:getHealthPercent() end) or 0,
    direction = nativeCall(function() return creature:getDirection() end) or 0,
    speed = nativeCall(function() return creature:getSpeed() end) or 0,
    position = copyPosition(nativeCall(function() return creature:getPosition() end)),
    isPlayer = nativeCall(function() return creature:isPlayer() end) == true,
    isMonster = nativeCall(function() return creature:isMonster() end) == true,
    isNpc = nativeCall(function() return creature:isNpc() end) == true
  }
end

local function getVisibleCreature(creatureId, multifloor)
  creatureId = integer(creatureId, 1, 0x7fffffff)
  local player = getLocalPlayer()
  if not creatureId or not player then return nil end
  local spectators = g_map.getSpectators(player:getPosition(), multifloor == true)
  for _, creature in ipairs(spectators or {}) do
    if creature:getId() == creatureId then return creature end
  end
  return nil
end

local function getTile(x, y, z)
  local pos = position(x, y, z)
  return pos and g_map.getTile(pos) or nil, pos
end

local function getInventoryItem(slot)
  slot = integer(slot, 1, 11)
  local player = getLocalPlayer()
  return player and slot and player:getInventoryItem(slot) or nil, slot
end

local function getContainer(index)
  index = integer(index, 0, 255)
  if not index or not getLocalPlayer() then return nil, index end
  return g_game.getContainer(index), index
end

local function getContainerItem(container, slot)
  slot = integer(slot, 0, 255)
  if not container or not slot then return nil, slot end
  local items = container:getItems() or {}
  return items[slot + 1], slot
end

local function countForMove(item, count)
  local maximum = nativeCall(function() return item:getCount() end) or 1
  return integer(count or maximum, 1, math.max(1, maximum))
end

local function moveItem(item, destination, count, group)
  if not item or not destination then return false end
  count = countForMove(item, count)
  if not count then return false end
  return perform(group or 'item', function()
    g_game.move(item, destination, count)
    return true
  end)
end

local CreatureMethods = {}
local CreatureMeta = { __index = CreatureMethods }

local function creatureFromHandle(self)
  local record = creatureRecords[self]
  return record and getVisibleCreature(record.id, true) or nil
end

function CreatureMethods:getId()
  local record = creatureRecords[self]
  return record and record.id or 0
end

function CreatureMethods:getName()
  local creature = creatureFromHandle(self)
  return creature and creature:getName() or nil
end

function CreatureMethods:getType()
  local creature = creatureFromHandle(self)
  return creature and creature:getType() or 0
end

function CreatureMethods:getGuildEmblem()
  local creature = creatureFromHandle(self)
  return creature and creature:getEmblem() or 0
end

function CreatureMethods:getPartyIcon()
  local creature = creatureFromHandle(self)
  return creature and creature:getShield() or 0
end

function CreatureMethods:getVocation()
  local creature = creatureFromHandle(self)
  return creature and creature:getVocation() or 0
end

function CreatureMethods:getPosition()
  local creature = creatureFromHandle(self)
  return creature and copyPosition(creature:getPosition()) or nil
end

function CreatureMethods:getHealthPercent()
  local creature = creatureFromHandle(self)
  return creature and creature:getHealthPercent() or 0
end

function CreatureMethods:getDirection()
  local creature = creatureFromHandle(self)
  return creature and creature:getDirection() or 0
end

function CreatureMethods:getSpeed()
  local creature = creatureFromHandle(self)
  return creature and creature:getSpeed() or 0
end

function CreatureMethods:getOutfit()
  local creature = creatureFromHandle(self)
  return creature and copyOutfit(creature:getOutfit()) or nil
end

function CreatureMethods:getSkull()
  local creature = creatureFromHandle(self)
  return creature and creature:getSkull() or 0
end

function CreatureMethods:getIcon()
  local creature = creatureFromHandle(self)
  return creature and creature:getIcon() or 0
end

function CreatureMethods:getIcons()
  local creature = creatureFromHandle(self)
  if not creature then return nil end
  local result = {}
  for _, icon in ipairs(nativeCall(function() return creature:getIcons() end) or {}) do
    if type(icon) == 'table' then
      table.insert(result, {
        type = tonumber(icon.type or icon.category or icon[2]) or 0,
        id = tonumber(icon.id or icon[1]) or 0,
        count = tonumber(icon.count or icon[3]) or 0
      })
    end
  end
  return result
end

function CreatureMethods:isPlayer()
  local creature = creatureFromHandle(self)
  return creature and creature:isPlayer() or false
end

function CreatureMethods:isMonster()
  local creature = creatureFromHandle(self)
  return creature and creature:isMonster() or false
end

function CreatureMethods:isNpc()
  local creature = creatureFromHandle(self)
  return creature and nativeCall(function() return creature:isNpc() end) == true or false
end

function CreatureMethods:isOnScreen()
  return creatureFromHandle(self) ~= nil
end

function CreatureMethods:attack()
  local record = creatureRecords[self]
  return record and actions.attack(record.id) or false
end

function CreatureMethods:follow()
  local record = creatureRecords[self]
  return record and actions.follow(record.id) or false
end

local function newCreature(creatureId)
  local creature = getVisibleCreature(creatureId, true)
  if not creature then return nil end
  local object = setmetatable({}, CreatureMeta)
  creatureRecords[object] = { id = creature:getId() }
  return object
end

local ContainerMethods = {}
local ContainerMeta = { __index = ContainerMethods }

local function containerFromHandle(self)
  local record = containerRecords[self]
  return record and getContainer(record.index) or nil
end

function ContainerMethods:getIndex()
  local record = containerRecords[self]
  return record and record.index or -1
end

function ContainerMethods:getName()
  local container = containerFromHandle(self)
  return container and container:getName() or nil
end

function ContainerMethods:getCapacity()
  local container = containerFromHandle(self)
  return container and container:getCapacity() or 0
end

function ContainerMethods:getItemsCount()
  local container = containerFromHandle(self)
  return container and container:getItemsCount() or 0
end

function ContainerMethods:getItemCount()
  return self:getItemsCount()
end

function ContainerMethods:getItemCountById(itemId)
  itemId = integer(itemId, 1, 65535)
  local container = containerFromHandle(self)
  if not container or not itemId then return 0 end
  local count = 0
  for _, item in ipairs(container:getItems() or {}) do
    if item:getId() == itemId then count = count + (item:getCount() or 1) end
  end
  return count
end

function ContainerMethods:getCurrentPage()
  local container = containerFromHandle(self)
  if not container or not container:hasPages() then return 0 end
  return 1 + math.floor(container:getFirstIndex() / math.max(1, container:getCapacity()))
end

function ContainerMethods:getTotalPages()
  local container = containerFromHandle(self)
  if not container or not container:hasPages() then return 0 end
  return math.ceil(container:getSize() / math.max(1, container:getCapacity()))
end

function ContainerMethods:goToPage(page)
  local container = containerFromHandle(self)
  page = integer(page, 1, 255)
  if not container or not page or not container:hasPages() or page > self:getTotalPages() then return false end
  return perform('container', function()
    g_game.seekInContainer(container:getId(), (page - 1) * container:getCapacity())
    return true
  end)
end

function ContainerMethods:getItems()
  local container = containerFromHandle(self)
  if not container then return {} end
  local result = {}
  for index, item in ipairs(container:getItems() or {}) do
    result[index] = itemData(item, index - 1)
  end
  return result
end

function ContainerMethods:getItem(slot)
  local container = containerFromHandle(self)
  local item, safeSlot = getContainerItem(container, slot)
  return itemData(item, safeSlot)
end

function ContainerMethods:moveItemToInventory(slot, inventorySlot, count)
  local container = containerFromHandle(self)
  local item = getContainerItem(container, slot)
  inventorySlot = integer(inventorySlot, 1, 11)
  if not item or not inventorySlot then return false end
  return moveItem(item, { x = 65535, y = inventorySlot, z = 0 }, count, 'container')
end

function ContainerMethods:moveItemToGround(slot, count, x, y, z)
  local item = getContainerItem(containerFromHandle(self), slot)
  return moveItem(item, position(x, y, z), count, 'container')
end

function ContainerMethods:moveItemToContainer(slot, count, targetIndex, targetSlot)
  local item = getContainerItem(containerFromHandle(self), slot)
  local target = getContainer(targetIndex)
  targetSlot = integer(targetSlot, 0, 255)
  if not target or not targetSlot then return false end
  return moveItem(item, target:getSlotPosition(targetSlot), count, 'container')
end

function ContainerMethods:useItem(slot, openNewWindow)
  local container = containerFromHandle(self)
  local item = getContainerItem(container, slot)
  if not item then return false end
  return perform('container', function()
    if nativeCall(function() return item:isContainer() end) == true then
      if openNewWindow == true then g_game.openContainer(item) else g_game.open(item, container) end
    else
      g_game.use(item)
    end
    return true
  end)
end

function ContainerMethods:useItemWithContainerItem(sourceSlot, targetIndex, targetSlot)
  local source = getContainerItem(containerFromHandle(self), sourceSlot)
  local targetContainer = getContainer(targetIndex)
  local target = getContainerItem(targetContainer, targetSlot)
  if not source or not target then return false end
  return perform('container', function() g_game.useWith(source, target); return true end)
end

function ContainerMethods:useItemWithCreature(slot, creatureId)
  local item = getContainerItem(containerFromHandle(self), slot)
  local creature = getVisibleCreature(creatureId, false)
  if not item or not creature then return false end
  return perform('container', function() g_game.useWith(item, creature); return true end)
end

function ContainerMethods:lookAt(slot)
  local item = getContainerItem(containerFromHandle(self), slot)
  if not item then return false end
  return perform('look', function() g_game.look(item); return true end)
end

function ContainerMethods:moveUp()
  local container = containerFromHandle(self)
  if not container then return false end
  return perform('container', function() g_game.openParent(container); return true end)
end

function ContainerMethods:close()
  local container = containerFromHandle(self)
  if not container then return false end
  return perform('container', function() g_game.close(container); return true end)
end

local function newContainer(index)
  local container, safeIndex = getContainer(index)
  if not container then return nil end
  local object = setmetatable({}, ContainerMeta)
  containerRecords[object] = { index = safeIndex }
  return object
end

local InventoryMethods = {}
local InventoryMeta = { __index = InventoryMethods }

local function inventoryFromHandle(self)
  local record = inventoryRecords[self]
  return record and getInventoryItem(record.slot) or nil
end

function InventoryMethods:getSlot()
  local record = inventoryRecords[self]
  return record and record.slot or 0
end

function InventoryMethods:getItem()
  local record = inventoryRecords[self]
  local item = inventoryFromHandle(self)
  return itemData(item, record and record.slot or nil)
end

function InventoryMethods:moveItemToGround(x, y, z, count)
  return moveItem(inventoryFromHandle(self), position(x, y, z), count, 'item')
end

function InventoryMethods:moveItemToContainer(containerIndex, containerSlot, count)
  local target = getContainer(containerIndex)
  containerSlot = integer(containerSlot, 0, 255)
  if not target or not containerSlot then return false end
  return moveItem(inventoryFromHandle(self), target:getSlotPosition(containerSlot), count, 'item')
end

function InventoryMethods:useItem()
  local item = inventoryFromHandle(self)
  if not item then return false end
  return perform('item', function() g_game.use(item); return true end)
end

function InventoryMethods:useItemWithCreature(creatureId)
  local item = inventoryFromHandle(self)
  local creature = getVisibleCreature(creatureId, false)
  if not item or not creature then return false end
  return perform('item', function() g_game.useWith(item, creature); return true end)
end

function InventoryMethods:lookAt()
  local item = inventoryFromHandle(self)
  if not item then return false end
  return perform('look', function() g_game.look(item); return true end)
end

local function newInventory(slot)
  local _, safeSlot = getInventoryItem(slot)
  if not safeSlot then return nil end
  local object = setmetatable({}, InventoryMeta)
  inventoryRecords[object] = { slot = safeSlot }
  return object
end

function actions.turn(direction)
  direction = integer(direction, 0, 3)
  if not direction then return false end
  return perform('movement', function() g_game.turn(direction); return true end)
end

function actions.walk(direction)
  direction = integer(direction, 0, 7)
  if not direction then return false end
  return perform('movement', function() return g_game.walk(direction, false) ~= false end)
end

function actions.goTo(x, y, z)
  local destination = position(x, y, z)
  local player = getLocalPlayer()
  if not destination or not player then return false end
  local current = player:getPosition()
  if destination.z ~= current.z or math.max(math.abs(destination.x - current.x), math.abs(destination.y - current.y)) > 50 then
    return false
  end
  return perform('movement', function() return player:autoWalk(destination, false) ~= false end)
end

function actions.attack(creatureId)
  creatureId = integer(creatureId or 0, 0, 0x7fffffff)
  if not creatureId then return false end
  if creatureId == 0 then
    return perform('target', function() g_game.cancelAttack(); return true end)
  end
  local creature = getVisibleCreature(creatureId, false)
  local player = getLocalPlayer()
  if not creature or creature == player then return false end
  return perform('target', function() g_game.attack(creature); return true end)
end

function actions.follow(creatureId)
  creatureId = integer(creatureId or 0, 0, 0x7fffffff)
  if not creatureId then return false end
  if creatureId == 0 then
    return perform('target', function() g_game.cancelFollow(); return true end)
  end
  local creature = getVisibleCreature(creatureId, false)
  local player = getLocalPlayer()
  if not creature or creature == player then return false end
  return perform('target', function() g_game.follow(creature); return true end)
end

local function safeText(value, maximum)
  if type(value) ~= 'string' then value = tostring(value or '') end
  if value:len() == 0 or value:len() > (maximum or 255) then return nil end
  return value
end

function actions.talk(message, talkType)
  message = safeText(message, 255)
  talkType = integer(talkType or 1, 1, 255)
  if not message or not talkType or not SAFE_TALK_TYPES[talkType] then return false end
  return perform('chat', function()
    if talkType == 1 then g_game.talk(message) else g_game.talkChannel(talkType, 0, message) end
    return true
  end)
end

function actions.talkChannel(message, channelId)
  message = safeText(message, 255)
  channelId = integer(channelId, 0, 65535)
  if not message or not channelId then return false end
  return perform('chat', function() g_game.talkChannel(7, channelId, message); return true end)
end

function actions.talkPrivate(message, receiver)
  message = safeText(message, 255)
  receiver = safeText(receiver, 40)
  if not message or not receiver then return false end
  return perform('chat', function() g_game.talkPrivate(5, receiver, message); return true end)
end

function actions.openChannel(channelId)
  channelId = integer(channelId, 0, 65535)
  if not channelId then return false end
  return perform('chat', function() g_game.joinChannel(channelId); return true end)
end

function actions.useItem(itemId)
  itemId = integer(itemId, 1, 65535)
  if not itemId then return false end
  return perform('item', function() g_game.useInventoryItem(itemId, 0); return true end)
end

function actions.equipItem(itemId, tier)
  itemId = integer(itemId, 1, 65535)
  tier = integer(tier or 0, 0, 10)
  if not itemId or not tier then return false end
  return perform('item', function() g_game.equipItemId(itemId, tier); return true end)
end

function actions.useItemWithCreature(itemId, creatureId)
  itemId = integer(itemId, 1, 65535)
  local creature = getVisibleCreature(creatureId, false)
  if not itemId or not creature then return false end
  return perform('item', function() g_game.useInventoryItemWith(itemId, creature, 0); return true end)
end

function actions.useItemOnGround(itemId, x, y, z)
  itemId = integer(itemId, 1, 65535)
  local tile = getTile(x, y, z)
  local target = tile and tile:getTopUseThing() or nil
  if not itemId or not target then return false end
  return perform('item', function() g_game.useInventoryItemWith(itemId, target, 0); return true end)
end

function actions.useItemOnInventory(itemId, slot)
  itemId = integer(itemId, 1, 65535)
  local target = getInventoryItem(slot)
  if not itemId or not target then return false end
  return perform('item', function() g_game.useInventoryItemWith(itemId, target, 0); return true end)
end

function actions.useItemFromGround(x, y, z)
  local tile = getTile(x, y, z)
  local target = tile and tile:getTopUseThing() or nil
  if not target then return false end
  return perform('item', function() g_game.use(target); return true end)
end

function actions.lootCorpse(x, y, z)
  local tile, pos = getTile(x, y, z)
  local target = tile and tile:getTopUseThing() or nil
  if not target or nativeCall(function() return target:isItem() end) ~= true then return false end
  return perform('item', function()
    g_game.quickLoot(pos, target:getId(), target:getStackPos(), false)
    return true
  end)
end

function actions.lookAt(x, y, z)
  local tile = getTile(x, y, z)
  local target = tile and tile:getTopLookThing() or nil
  if not target then return false end
  return perform('look', function() g_game.look(target); return true end)
end

function actions.setFightMode(mode)
  mode = integer(mode, 1, 3)
  if not mode then return false end
  return perform('mode', function() g_game.setFightMode(mode); return true end)
end

function actions.setChaseMode(mode)
  mode = integer(mode, 0, 1)
  if not mode then return false end
  return perform('mode', function() g_game.setChaseMode(mode); return true end)
end

local function installPlayer(environment)
  local playerApi = environment.Player
  playerApi.getMaxHealth = function() local p = getLocalPlayer(); return p and p:getMaxHealth() or 0 end
  playerApi.getMaxMana = function() local p = getLocalPlayer(); return p and p:getMaxMana() or 0 end
  -- This client has no magic-shield accessor; nativeCall keeps a ZeroBot script
  -- that reads them running instead of aborting on a nil method.
  playerApi.getMagicShield = function()
    local p = getLocalPlayer()
    return p and nativeCall(function() return p:getMagicShield() end) or 0
  end
  playerApi.getMaxMagicShield = function()
    local p = getLocalPlayer()
    return p and nativeCall(function() return p:getMaxMagicShield() end) or 0
  end
  playerApi.getMagicLevel = function() local p = getLocalPlayer(); return p and p:getMagicLevel() or 0 end
  playerApi.getLevelPercent = function() local p = getLocalPlayer(); return p and p:getLevelPercent() or 0 end
  playerApi.getDirection = function() local p = getLocalPlayer(); return p and p:getDirection() or 0 end
  playerApi.getSpeed = function() local p = getLocalPlayer(); return p and p:getSpeed() or 0 end
  playerApi.getVocation = function() local p = getLocalPlayer(); return p and p:getVocation() or 0 end
  playerApi.getPartyIcon = function() local p = getLocalPlayer(); return p and p:getShield() or 0 end
  playerApi.getStates = function() local p = getLocalPlayer(); return p and p:getStates() or 0 end
  playerApi.getInventoryItem = function(slot) local item, safeSlot = getInventoryItem(slot); return itemData(item, safeSlot) end
  playerApi.getInventorySlot = playerApi.getInventoryItem
  playerApi.getState = function(state)
    state = integer(state, 0, 0x7fffffff)
    local p = getLocalPlayer()
    if not p or not state then return false end
    return state ~= 0 and bit.band(p:getStates(), state) ~= 0 or false
  end
  playerApi.getSkills = function()
    local p = getLocalPlayer()
    if not p then return {} end
    local names = { 'fist', 'club', 'sword', 'axe', 'distance', 'shield', 'fishing' }
    local result = { magic = p:getMagicLevel(), magicPercent = p:getMagicLevelPercent() }
    for skillId, name in ipairs(names) do
      result[name] = p:getSkillLevel(skillId - 1)
      result[name .. 'Percent'] = p:getSkillLevelPercent(skillId - 1)
    end
    -- Present in ZeroBot's table; this server sends no client-side source for
    -- them, so they report 0 rather than being absent.
    for _, name in ipairs({
      'criticalChance', 'criticalDamage', 'lifeLeechChance', 'lifeLeechDamage',
      'manaLeechChance', 'manaLeechDamage'
    }) do
      result[name] = nativeCall(function() return p:getSkillLevel(name) end) or 0
    end
    return result
  end
  playerApi.getBlessingState = function() local p = getLocalPlayer(); return p and p:getBlessings() or 0 end
  playerApi.isPremium = function() local p = getLocalPlayer(); return p and p:isPremium() or false end
  playerApi.hasReceivedBasicData = function() return getLocalPlayer() ~= nil end
  playerApi.getContainers = function()
    local result = {}
    for index in pairs(g_game.getContainers() or {}) do table.insert(result, tonumber(index)) end
    table.sort(result)
    return result
  end
  local function partyTarget(targetId)
    local target = getVisibleCreature(targetId, false)
    return target and target:isPlayer() and target or nil
  end
  playerApi.joinParty = function(targetId)
    local target = partyTarget(targetId)
    return target and perform('target', function() g_game.partyJoin(target:getId()); return true end) or false
  end
  playerApi.inviteParty = function(targetId)
    local target = partyTarget(targetId)
    return target and perform('target', function() g_game.partyInvite(target:getId()); return true end) or false
  end
  playerApi.enableSharedExpParty = function(enabled)
    if type(enabled) ~= 'boolean' then return false end
    return perform('mode', function() g_game.partyShareExperience(enabled); return true end)
  end
  playerApi.passLeadershipParty = function(targetId)
    local target = partyTarget(targetId)
    return target and perform('target', function() g_game.partyPassLeadership(target:getId()); return true end) or false
  end
  playerApi.leaveParty = function()
    return perform('target', function() g_game.partyLeave(); return true end)
  end
end

-- Boss Sequence panel, extended opcode 153 (ExtendedIds.BossSequence).
--
-- Deliberately NOT a generic sendExtendedOpcode(). Exposing that would let any
-- script speak for every client module that owns an opcode -- the store, the
-- market, the forge -- which is precisely the authority this sandbox exists to
-- withhold. So the opcode id is fixed here and the command is assembled from
-- validated parts: a script can drive this one panel and nothing else.
--
-- This is also not a way to start a run from anywhere. The server
-- (boss_sequence_final.lua) only honours these while a statue menu session is
-- open AND the player is still within MENU_RANGE of it, so the panel has to have
-- been opened normally first -- the same contract the dungeon example follows.
local BOSS_SEQUENCE_OPCODE = 153
local BOSS_SEQUENCE_WAVE_SIZES = { [1] = true, [3] = true, [5] = true }

-- True only when the panel is open with a live snapshot. Refusing here is what
-- lets a script retry sensibly: the server silently drops commands sent without
-- a statue session, so without this check every attempt would report success
-- while nothing happened.
local function bossSequenceReady()
  local module = modules.game_bosssequence
  local api = module and module.BossSequence
  if not api or type(api.isPanelReady) ~= 'function' then return false end
  local ok, ready = pcall(api.isPanelReady)
  return ok and ready == true
end

local function sendBossSequence(command)
  if not bossSequenceReady() then return false end
  return perform('panel', function()
    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then return false end
    protocolGame:sendExtendedOpcode(BOSS_SEQUENCE_OPCODE, command)
    return true
  end)
end

-- Full Sequence: category is the Categories row (1 = Easy, 2 = Medium,
-- 3 = Hard), waveSize is the "Bosses per wave" button (1, 3 or 5).
function actions.bossSequenceStart(category, waveSize)
  category = integer(category, 1, 99)
  waveSize = integer(waveSize, 1, 5)
  if not category or not waveSize or not BOSS_SEQUENCE_WAVE_SIZES[waveSize] then return false end
  return sendBossSequence(string.format('start %d all %d', category, waveSize))
end

-- Single Boss mode. The name must match the panel entry exactly.
function actions.bossSequenceStartSingle(category, bossName)
  category = integer(category, 1, 99)
  if not category or type(bossName) ~= 'string' then return false end
  -- The command travels as a space-separated string, so a control character or
  -- newline in the name could forge a second command. One line, bounded length.
  if #bossName == 0 or #bossName > 64 or bossName:find('%c') then return false end
  return sendBossSequence(string.format('start %d single 1 %s', category, bossName))
end

function actions.bossSequenceRefresh()
  return sendBossSequence('refresh')
end

local function installGame(environment)
  local game = environment.Game
  game.bossSequenceStart = actions.bossSequenceStart
  game.bossSequenceStartSingle = actions.bossSequenceStartSingle
  game.bossSequenceRefresh = actions.bossSequenceRefresh
  game.turn = actions.turn
  game.walk = actions.walk
  game.attack = actions.attack
  game.follow = actions.follow
  game.talk = actions.talk
  game.talkChannel = actions.talkChannel
  game.talkPrivate = actions.talkPrivate
  game.openChannel = actions.openChannel
  game.useItem = actions.useItem
  game.equipItem = actions.equipItem
  game.useItemWithCreature = actions.useItemWithCreature
  game.useItemOnGround = actions.useItemOnGround
  game.useItemOnInventory = actions.useItemOnInventory
  game.useItemFromGround = actions.useItemFromGround
  game.lootCorpse = actions.lootCorpse
  game.setFightMode = actions.setFightMode
  game.getFightMode = function() return g_game.getFightMode() end
  game.setChaseMode = actions.setChaseMode
  game.getChaseMode = function() return g_game.getChaseMode() end
  game.getItemCount = function(itemId, itemTier)
    itemId = integer(itemId, 1, 65535)
    itemTier = integer(itemTier or 0, 0, 10)
    if not itemId or not itemTier or not getLocalPlayer() then return 0 end
    local count = 0
    local items = {}
    local player = getLocalPlayer()
    for slot = 1, 11 do
      local item = player:getInventoryItem(slot)
      if item then table.insert(items, item) end
    end
    for _, container in pairs(g_game.getContainers() or {}) do
      for _, item in ipairs(container:getItems() or {}) do table.insert(items, item) end
    end
    for _, item in ipairs(items) do
      local tier = nativeCall(function() return item:getTier() end) or 0
      if item:getId() == itemId and (itemTier == 0 or tier == itemTier) then
        count = count + (item:getCount() or 1)
      end
    end
    return count
  end
  game.getInventoryItems = function()
    local result = {}
    for slot = 1, 11 do
      local item = getInventoryItem(slot)
      if item then table.insert(result, itemData(item, slot)) end
    end
    return result
  end
end

local function installMap(environment)
  local map = {}
  map.getCameraPosition = function()
    local player = getLocalPlayer()
    return player and copyPosition(player:getPosition()) or nil
  end
  map.getCreatureIds = function(sameFloor, onlyPlayers)
    local player = getLocalPlayer()
    if not player then return {} end
    local result = {}
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), sameFloor == false) or {}) do
      if not onlyPlayers or creature:isPlayer() then table.insert(result, creature:getId()) end
    end
    return #result > 0 and result or nil
  end
  map.getCreatures = function(sameFloor, onlyPlayers)
    local result = {}
    for _, id in ipairs(map.getCreatureIds(sameFloor, onlyPlayers) or {}) do
      local data = creatureData(getVisibleCreature(id, sameFloor == false))
      if data then table.insert(result, data) end
    end
    return result
  end
  map.getPlayerOnScreen = function(value)
    local player = getLocalPlayer()
    if not player then return nil end
    local wantedId = type(value) == 'number' and integer(value, 1, 0x7fffffff) or nil
    local wantedName = type(value) == 'string' and value:lower() or nil
    if not wantedId and not wantedName then return nil end
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), true) or {}) do
      if creature:isPlayer() and
          ((wantedId and creature:getId() == wantedId) or (wantedName and creature:getName():lower() == wantedName)) then
        return newCreature(creature:getId())
      end
    end
    return nil
  end
  -- Bounds of the visible screen around the player, matching what ZeroBot
  -- means by "on screen".
  local function screenBounds()
    local player = getLocalPlayer()
    if not player then return nil end
    local center = player:getPosition()
    local range = nativeCall(function() return g_map.getAwareRange() end)
    local width = math.floor((tonumber(range and range.width) or 15) / 2)
    local height = math.floor((tonumber(range and range.height) or 11) / 2)
    return center, width, height
  end

  map.getTiles = function()
    local center, width, height = screenBounds()
    if not center then return {} end
    local result = {}
    for x = center.x - width, center.x + width do
      for y = center.y - height, center.y + height do
        local tile = getTile(x, y, center.z)
        if tile and tile:getThingCount() > 0 then
          table.insert(result, {
            position = { x = x, y = y, z = center.z },
            things = map.getThings(x, y, center.z)
          })
        end
      end
    end
    return result
  end
  map.getThings = function(x, y, z)
    local tile = getTile(x, y, z)
    if not tile then return {} end
    local result = {}
    for _, thing in ipairs(tile:getThings() or {}) do
      local creature = nativeCall(function() return thing:isCreature() end) and creatureData(thing) or nil
      table.insert(result, creature or itemData(thing))
    end
    return result
  end
  map.getThingsCount = function(x, y, z) local tile = getTile(x, y, z); return tile and tile:getThingCount() or 0 end
  map.getThingCount = map.getThingsCount
  map.getTopItemId = function(x, y, z)
    local tile = getTile(x, y, z)
    local item = tile and tile:getTopMoveThing() or nil
    return item and nativeCall(function() return item:isItem() end) and item:getId() or 0
  end
  map.getTopCreatureId = function(x, y, z)
    local tile = getTile(x, y, z)
    local creature = tile and tile:getTopCreature() or nil
    return creature and creature:getId() or 0
  end
  map.isTileWalkable = function(x, y, z, ignoreBlockPath, ignoreMagicField, ignoreMonsters, ignoreNpcs)
    local tile = getTile(x, y, z)
    if not tile then return false end
    if not ignoreBlockPath and not tile:isWalkable() then return false end
    if not (ignoreMonsters and ignoreNpcs) then
      local creature = nativeCall(function() return tile:getTopCreature() end)
      if creature then
        local isNpc = nativeCall(function() return creature:isNpc() end) == true
        local isMonster = nativeCall(function() return creature:isMonster() end) == true
        if (isNpc and not ignoreNpcs) or (isMonster and not ignoreMonsters) then return false end
        if not isNpc and not isMonster then return false end
      end
    end
    -- ignoreMagicField is accepted for signature compatibility but has no
    -- effect: this client exposes no magic-field predicate on Tile.
    return true
  end
  map.canWalk = map.isTileWalkable
  map.goTo = actions.goTo
  map.lookAt = actions.lookAt
  map.browseField = function(x, y, z)
    local _, pos = getTile(x, y, z)
    if not pos then return false end
    return perform('container', function() g_game.browseField(pos); return true end)
  end
  map.moveItemToGround = function(x, y, z, count, toX, toY, toZ)
    local tile = getTile(x, y, z)
    local item = tile and tile:getTopMoveThing() or nil
    if not item or nativeCall(function() return item:isItem() end) ~= true then return false end
    return moveItem(item, position(toX, toY, toZ), count, 'item')
  end
  map.moveItemToInventory = function(x, y, z, count, slot)
    local tile = getTile(x, y, z)
    local item = tile and tile:getTopMoveThing() or nil
    slot = integer(slot, 1, 11)
    if not item or not slot or nativeCall(function() return item:isItem() end) ~= true then return false end
    return moveItem(item, { x = 65535, y = slot, z = 0 }, count, 'item')
  end
  map.moveItemToContainer = function(x, y, z, count, containerIndex, containerSlot)
    local tile = getTile(x, y, z)
    local item = tile and tile:getTopMoveThing() or nil
    local target = getContainer(containerIndex)
    containerSlot = integer(containerSlot, 0, 255)
    if not item or not target or not containerSlot or nativeCall(function() return item:isItem() end) ~= true then return false end
    return moveItem(item, target:getSlotPosition(containerSlot), count, 'item')
  end
  map.moveCreatureToGround = function(x, y, z, toX, toY, toZ)
    local tile = getTile(x, y, z)
    local creature = tile and tile:getTopCreature() or nil
    local destination = position(toX, toY, toZ)
    if not creature or not destination then return false end
    return perform('movement', function() g_game.move(creature, destination, 1); return true end)
  end
  map.useItem = actions.useItemFromGround
  map.useItemWithInventory = function(x, y, z, slot)
    local tile = getTile(x, y, z)
    local source = tile and tile:getTopUseThing() or nil
    local target = getInventoryItem(slot)
    if not source or not target or nativeCall(function() return source:isItem() end) ~= true then return false end
    return perform('item', function() g_game.useWith(source, target); return true end)
  end
  map.useItemWithContainer = function(x, y, z, containerIndex, containerSlot)
    local tile = getTile(x, y, z)
    local source = tile and tile:getTopUseThing() or nil
    local targetContainer = getContainer(containerIndex)
    local target = getContainerItem(targetContainer, containerSlot)
    if not source or not target or nativeCall(function() return source:isItem() end) ~= true then return false end
    return perform('item', function() g_game.useWith(source, target); return true end)
  end
  map.useItemWithCreature = function(x, y, z, creatureId)
    local tile = getTile(x, y, z)
    local source = tile and tile:getTopUseThing() or nil
    local creature = getVisibleCreature(creatureId, false)
    if not source or not creature or nativeCall(function() return source:isItem() end) ~= true then return false end
    return perform('item', function() g_game.useWith(source, creature); return true end)
  end
  map.getAllPositionsWithTopItemId = function(itemId, sameFloor)
    itemId = integer(itemId, 1, 65535)
    local player = getLocalPlayer()
    if not itemId or not player then return {} end
    local center, width, height = screenBounds()
    if not center then return {} end
    local result = {}
    for x = center.x - width, center.x + width do
      for y = center.y - height, center.y + height do
        local tile = getTile(x, y, center.z)
        local item = tile and tile:getTopMoveThing() or nil
        if item and nativeCall(function() return item:isItem() end) == true and item:getId() == itemId then
          table.insert(result, { x = x, y = y, z = center.z })
        end
      end
    end
    return result
  end
  environment.Map = map
end

function actions.install(environment)
  installPlayer(environment)
  installGame(environment)
  installMap(environment)
  local creatureClass = { new = newCreature }
  local containerClass = { new = newContainer }
  local inventoryClass = { new = newInventory }
  containerClass.useItemOnAnotherItem = function(itemId, otherId)
    itemId = integer(itemId, 1, 65535)
    otherId = integer(otherId, 1, 65535)
    if not itemId or not otherId then return false end
    local source, target
    for _, container in pairs(g_game.getContainers() or {}) do
      for _, item in ipairs(container:getItems() or {}) do
        if not source and item:getId() == itemId then source = item end
        if not target and item:getId() == otherId then target = item end
      end
    end
    if not source or not target then return false end
    return perform('container', function() g_game.useWith(source, target); return true end)
  end
  inventoryClass.moveItemToGround = function(slot, count, x, y, z)
    local item = getInventoryItem(slot)
    return moveItem(item, position(x, y, z), count, 'item')
  end
  inventoryClass.moveItemToContainer = function(slot, count, containerIndex, containerSlot)
    local item = getInventoryItem(slot)
    local target = getContainer(containerIndex)
    containerSlot = integer(containerSlot, 0, 255)
    if not target or not containerSlot then return false end
    return moveItem(item, target:getSlotPosition(containerSlot), count, 'item')
  end
  inventoryClass.useItem = function(slot)
    local item = getInventoryItem(slot)
    if not item then return false end
    return perform('item', function() g_game.use(item); return true end)
  end
  inventoryClass.lookAt = function(slot)
    local item = getInventoryItem(slot)
    if not item then return false end
    return perform('look', function() g_game.look(item); return true end)
  end
  environment.Creature = setmetatable(creatureClass, { __call = function(_, ...) return newCreature(...) end })
  environment.Container = setmetatable(containerClass, { __call = function(_, ...) return newContainer(...) end })
  environment.Inventory = setmetatable(inventoryClass, { __call = function(_, ...) return newInventory(...) end })
end

function actions.reset()
  actionBuckets = {}
end

-- Shared helpers for the ZeroBot compatibility layer (scripting_compat.lua).
-- Exposing them keeps every compat action behind the same token buckets and the
-- same online check as the native API.
actions.perform = perform
actions.integer = integer
actions.position = position
actions.copyPosition = copyPosition
actions.itemData = itemData
actions.creatureData = creatureData
actions.getLocalPlayer = getLocalPlayer
actions.getVisibleCreature = getVisibleCreature
actions.getInventoryItem = getInventoryItem
actions.getContainer = getContainer
actions.nativeCall = nativeCall
