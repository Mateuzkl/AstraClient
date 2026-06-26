ObjectPool = {}
ObjectPool.__index = ObjectPool

-- maxSize: cap pra evitar pool crescer infinito quando release >> get
--          (default 128 que cobre o caso comum sem segurar muito heap).
-- stats:   { gets=N, hits=N, releases=N } — N gets de cache hit / total
function ObjectPool.new(createFunc, resetFunc, maxSize)
    return setmetatable({
        create = createFunc,
        reset = resetFunc,
        pool = {},
        maxSize = maxSize or 128,
        stats = { gets = 0, hits = 0, releases = 0, dropped = 0 }
    }, ObjectPool)
end

function ObjectPool:get()
    self.stats.gets = self.stats.gets + 1
    local obj = table.remove(self.pool)
    if obj then
        self.stats.hits = self.stats.hits + 1
        return obj
    end
    return self.create()
end

function ObjectPool:release(obj)
    if obj == nil then return end
    self.stats.releases = self.stats.releases + 1
    if self.reset then
        self.reset(obj)
    end
    if #self.pool >= self.maxSize then
        -- pool full: drop instead of growing forever; the dropped instance
        -- becomes regular GC fodder, but we cap memory residency.
        self.stats.dropped = self.stats.dropped + 1
        return
    end
    table.insert(self.pool, obj)
end

function ObjectPool:clear()
    self.pool = {}
end

-- Hit rate >70% = pool is doing its job; <30% = misused (allocations are
-- not amortising because gets >> releases or pool is too small).
function ObjectPool:getHitRate()
    if self.stats.gets == 0 then return 0 end
    return self.stats.hits / self.stats.gets
end


-- =============================================================================
-- TablePool — convenience around ObjectPool for the two patterns that dominate
-- helper hot paths: empty arrays and {x, y, z} position tables.
--
-- Usage (caller MUST release after use):
--     local pos = TablePool.getPosition(); pos.x, pos.y, pos.z = 1, 2, 3
--     -- use pos
--     TablePool.releasePosition(pos)
--
-- Or auto-release wrapper:
--     TablePool.withArray(function(arr)
--         arr[#arr+1] = something
--         -- arr is released after the function returns
--     end)
-- =============================================================================

TablePool = {}

local _arrayPool = ObjectPool.new(
    function() return {} end,
    function(t)
        -- table.clear preferred when available (LuaJIT) — reuses backing
        -- storage. Falls back to manual nil-out loop.
        if table.clear then
            table.clear(t)
        else
            for i = #t, 1, -1 do t[i] = nil end
            for k, _ in pairs(t) do t[k] = nil end
        end
    end,
    256
)

local _positionPool = ObjectPool.new(
    function() return { x = 0, y = 0, z = 0 } end,
    function(t)
        t.x, t.y, t.z = 0, 0, 0
    end,
    512
)

function TablePool.getArray()
    return _arrayPool:get()
end

function TablePool.releaseArray(t)
    _arrayPool:release(t)
end

function TablePool.getPosition()
    return _positionPool:get()
end

function TablePool.releasePosition(t)
    _positionPool:release(t)
end

-- pcall-guarded helpers: caller can't leak the table even if the body errors.
function TablePool.withArray(fn)
    local t = _arrayPool:get()
    local ok, err = pcall(fn, t)
    _arrayPool:release(t)
    if not ok then error(err, 0) end
end

function TablePool.withPosition(fn)
    local t = _positionPool:get()
    local ok, err = pcall(fn, t)
    _positionPool:release(t)
    if not ok then error(err, 0) end
end

function TablePool.getStats()
    return {
        array = {
            size = #_arrayPool.pool,
            hitRate = _arrayPool:getHitRate(),
            gets = _arrayPool.stats.gets,
            releases = _arrayPool.stats.releases,
            dropped = _arrayPool.stats.dropped,
        },
        position = {
            size = #_positionPool.pool,
            hitRate = _positionPool:getHitRate(),
            gets = _positionPool.stats.gets,
            releases = _positionPool.stats.releases,
            dropped = _positionPool.stats.dropped,
        },
    }
end
