if not World then
  World = {
    pvptype = 3,
    location = "BRA",
    restrictedstore = false,
    previewstate = 0,
    name = "Bellum",
    id = 17,
    anticheatprotection = false,
    currenttournamentphase = 0,
    externalportunprotected = 7172,
    externalportprotected = 7172,
    externaladdress = "127.0.0.1",
    istournamentworld = false,
    externaladdressunprotected = "127.0.0.1",
    externaladdressprotected = "127.0.0.1",
    externalport = 7172,
    grandopening = 0
  }
end

function World:new(data)
    data = type(data) == "table" and data or {}
    local instance = setmetatable({}, { __index = self })
    instance.pvptype = data.pvptype or self.pvptype
    instance.location = data.location or self.location
    instance.restrictedstore = data.restrictedstore or self.restrictedstore
    instance.previewstate = data.previewstate or self.previewstate
    instance.name = data.name or self.name
    instance.id = data.id or self.id
    instance.anticheatprotection = data.anticheatprotection or self.anticheatprotection
    instance.currenttournamentphase = data.currenttournamentphase or self.currenttournamentphase
    instance.externalportunprotected = data.externalportunprotected or self.externalportunprotected
    instance.externalportprotected = data.externalportprotected or self.externalportprotected
    instance.externaladdress = data.externaladdress or self.externaladdress
    instance.istournamentworld = data.istournamentworld or self.istournamentworld
    instance.externaladdressunprotected = data.externaladdressunprotected or self.externaladdressunprotected
    instance.externaladdressprotected = data.externaladdressprotected or self.externaladdressprotected
    instance.externalport = data.externalport or self.externalport
    instance.grandopening = data.grandopening or self.grandopening
    return instance
end

function World:getProtectedPort()
  if self.externalportprotected and self.externalportprotected > 0 then
    return self.externalportprotected
  end
  return self.externalport
end

function World:getPvPType()
    return self.pvptype
end

function World:getLocation()
    return self.location
end

function World:isRestrictedStore()
    return self.restrictedstore
end

function World:getPreviewState()
    return self.previewstate
end

function World:getName()
    return self.name
end

function World:getId()
    return self.id
end

function World:getGrandOpening()
    return self.grandopening
end

function World:isAnticheatProtectionEnabled()
    return self.anticheatprotection
end

function World:getCurrentTournamentPhase()
    return self.currenttournamentphase
end

function World:getExternalPortUnprotected()
    return self.externalportunprotected
end

function World:getExternalAddress()
    return self.externaladdress
end

function World:isTournamentWorld()
    return self.istournamentworld
end

function World:getExternalAddressUnprotected()
    return self.externaladdressunprotected
end

function World:getExternalAddressProtected()
    return self.externaladdressprotected
end

function World:getExternalPort()
    return self.externalport
end

function World:getExternalPortProtected()
    return self.externalportprotected
end

if not Worlds then
  Worlds = {
    list = {},
  }
end

function Worlds:loadWorlds(playerData)
    self.list = {}
    if type(playerData) ~= "table" or type(playerData["worlds"]) ~= "table" then
        return
    end
    for _, worldData in pairs(playerData["worlds"]) do
        local world = World:new(worldData)
        self.list[world:getId()] = world
    end
end

function Worlds:getProtectedPort(worldId)
    local world = self.list[worldId]
    if world then
        return world:getProtectedPort()
    end
    return 0
end

function Worlds:getWorldByName(worldName)
    for _, world in pairs(self.list) do
        if world:getName() == worldName then
            return world
        end
    end
    return nil
end

function Worlds:getWorldById(worldId)
    return self.list[worldId] or nil
end
