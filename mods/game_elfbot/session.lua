-- Per-login session statistics. Never persist a total-XP baseline in settings.
ElfBotSession={}
local S=ElfBotSession
local MAX_EXACT=9007199254740991 -- Lua numbers cannot measure integer deltas above 2^53-1.
local function finite(value)
  local n=tonumber(value)
  return n and n==n and n~=math.huge and n~=-math.huge and n or nil
end
local function experience(value)
  local n=finite(value)
  if n and n>=0 and n<=MAX_EXACT then return math.floor(n) end
end
function S.formatNumber(value)
  local n=finite(value) or 0
  local text=string.format('%.0f',math.floor(math.max(0,n)))
  return (text:reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,',''))
end
function S.formatTime(seconds)
  local n=math.floor(math.max(0,finite(seconds) or 0))
  return string.format('%02.0f:%02.0f:%02.0f',math.floor(n/3600),math.floor(n/60)%60,n%60)
end
function S.new(now,name)
  local s={}
  function s.reset(time,playerName)
    s.startedAt=finite(time) or 0;s.lastTime=s.startedAt
    s.name=playerName or '';s.startExp=nil;s.currentExp=nil;s.ready=false
  end
  function s.update(time,total,playerName,level)
    time=finite(time) or s.lastTime
    if time<s.lastTime or (playerName and playerName~=s.name) then s.reset(time,playerName) end
    s.lastTime=time
    local xp=experience(total);local lvl=finite(level)
    s.ready=xp~=nil and lvl~=nil and lvl>0
    if s.ready then
      if s.startExp==nil then s.startExp=xp end
      s.currentExp=xp
    end
    local elapsed=math.max(0,time-s.startedAt)
    local gained=s.startExp and s.currentExp and math.max(0,s.currentExp-s.startExp) or 0
    local rate=s.ready and elapsed>=1000 and math.floor(gained*(3600000/elapsed)) or 0
    return {name=s.name,ready=s.ready,elapsedMs=elapsed,elapsed=math.floor(elapsed/1000),
      gained=gained,perHour=rate,timeText=S.formatTime(elapsed/1000)}
  end
  s.reset(now,name);return s
end
