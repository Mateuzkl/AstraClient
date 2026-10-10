-- Data-only spatial index. Opening a map must not materialize a world-sized
-- catalog of UI widgets. Query memory stays bounded even at the widest zoom.
MapMarkerIndex = {}
MapMarkerIndex.__index = MapMarkerIndex
local sectorSize = 64

function MapMarkerIndex.create()
  return setmetatable({floors = {}, records = {}}, MapMarkerIndex)
end

function MapMarkerIndex:insert(record)
  if type(record) ~= 'table' or (type(record.id) ~= 'number' and type(record.id) ~= 'string') then return false end
  local p = record.position
  if not p or type(p.x) ~= 'number' or type(p.y) ~= 'number' or type(p.z) ~= 'number' or
      not (p.x >= 0 and p.x <= 65535 and p.y >= 0 and p.y <= 65535 and p.z >= 0 and p.z <= 15) or
      p.x ~= math.floor(p.x) or p.y ~= math.floor(p.y) or p.z ~= math.floor(p.z) then return false end
  self:remove(record.id)
  local x, y = math.floor(p.x / sectorSize), math.floor(p.y / sectorSize)
  local floor = self.floors[p.z] or {}; self.floors[p.z] = floor
  local row = floor[y] or {}; floor[y] = row
  local bucket = row[x] or {}; row[x] = bucket
  bucket[record.id], self.records[record.id] = record, record
  return true
end

function MapMarkerIndex:remove(id)
  local record = self.records[id]
  if not record then return end
  local p = record.position
  local floor = self.floors[p.z]
  local y, x = math.floor(p.y / sectorSize), math.floor(p.x / sectorSize)
  local row = floor[y]
  row[x][id] = nil
  if not next(row[x]) then row[x] = nil end
  if not next(row) then floor[y] = nil end
  if not next(floor) then self.floors[p.z] = nil end
  self.records[id] = nil
end

function MapMarkerIndex.sortAndTrim(candidates, limit)
  table.sort(candidates, function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return tostring(a.record.id) < tostring(b.record.id)
  end)
  for i = #candidates, limit + 1, -1 do candidates[i] = nil end
  return candidates
end

function MapMarkerIndex:query(bounds, floor, center, limit, ignored, hidden, excludedPositions)
  local candidates = {}
  local function better(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return tostring(a.record.id) < tostring(b.record.id)
  end
  local function admit(record)
    local p = record.position
    local priority = record.priority or 0
    local distance = (p.x - center.x)^2 + (p.y - center.y)^2
    local worst = candidates[1]
    if #candidates == limit and not (priority > worst.priority or
        (priority == worst.priority and (distance < worst.distance or
          (distance == worst.distance and tostring(record.id) < tostring(worst.record.id))))) then return end
    local candidate = {record = record, priority = priority, distance = distance}
    if #candidates < limit then
      local i = #candidates + 1
      candidates[i] = candidate
      while i > 1 do
        local parent = math.floor(i / 2)
        if not better(candidates[parent], candidate) then break end
        candidates[i], candidates[parent] = candidates[parent], candidate
        i = parent
      end
    else
      candidates[1] = candidate
      local i = 1
      while i * 2 <= #candidates do
        local child = i * 2
        if child < #candidates and better(candidates[child], candidates[child + 1]) then child = child + 1 end
        if not better(candidate, candidates[child]) then break end
        candidates[i], candidates[child] = candidates[child], candidate
        i = child
      end
    end
  end
  -- Iterate occupied sectors, not a potentially enormous empty zoom rectangle.
  for y, row in pairs(self.floors[floor] or {}) do
    if (y + 1) * sectorSize > bounds.top and y * sectorSize <= bounds.bottom then
      for x, bucket in pairs(row) do
        if (x + 1) * sectorSize > bounds.left and x * sectorSize <= bounds.right then
          for id, record in pairs(bucket) do
            local p = record.position
            if p.x >= bounds.left and p.x <= bounds.right and p.y >= bounds.top and p.y <= bounds.bottom and
                not (ignored or {})[record.imagePath] and not (hidden or {})[id] and
                not (record.positionKey and (excludedPositions or {})[record.positionKey]) then
              admit(record)
            end
          end
        end
      end
    end
  end
  return MapMarkerIndex.sortAndTrim(candidates, limit)
end
