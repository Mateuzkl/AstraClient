HotkeyShortcuts = {
  ["Ctrl+F1"] = "CF1",
  ["Ctrl+F2"] = "CF2",
  ["Ctrl+F3"] = "CF3",
  ["Ctrl+F4"] = "CF4",
  ["Ctrl+F5"] = "CF5",
  ["Ctrl+F6"] = "CF6",
  ["Ctrl+F7"] = "CF7",
  ["Ctrl+F8"] = "CF8",
  ["Ctrl+F9"] = "CF9",
  ["Ctrl+F10"] = "CF10",
  ["Ctrl+F11"] = "CF11",
  ["Ctrl+F12"] = "CF12",
  ["Ctrl+F13"] = "CF13",
  ["Ctrl+F14"] = "CF14",
  ["Ctrl+F15"] = "CF15",
  ["Ctrl+F16"] = "CF16",
  ["Ctrl+F17"] = "CF17",
  ["Ctrl+F18"] = "CF18",
  ["Ctrl+F19"] = "CF19",
  ["Ctrl+F20"] = "CF20",
  ["Ctrl+F21"] = "CF21",
  ["Ctrl+F22"] = "CF22",
  ["Ctrl+F23"] = "CF23",
  ["Ctrl+F24"] = "CF24",
  ["Shift+F1"] = "SF1",
  ["Shift+F2"] = "SF2",
  ["Shift+F3"] = "SF3",
  ["Shift+F4"] = "SF4",
  ["Shift+F5"] = "SF5",
  ["Shift+F6"] = "SF6",
  ["Shift+F7"] = "SF7",
  ["Shift+F8"] = "SF8",
  ["Shift+F9"] = "SF9",
  ["Shift+F10"] = "SF10",
  ["Shift+F11"] = "SF11",
  ["Shift+F12"] = "SF12",
  ["Shift+F13"] = "SF13",
  ["Shift+F14"] = "SF14",
  ["Shift+F15"] = "SF15",
  ["Shift+F16"] = "SF16",
  ["Shift+F17"] = "SF17",
  ["Shift+F18"] = "SF18",
  ["Shift+F19"] = "SF19",
  ["Shift+F20"] = "SF20",
  ["Shift+F21"] = "SF21",
  ["Shift+F22"] = "SF22",
  ["Shift+F23"] = "SF23",
  ["Shift+F24"] = "SF24",
  ["Ctrl+Alt+F1"] = "CAF1",
  ["Ctrl+Alt+F2"] = "CAF2",
  ["Ctrl+Alt+F3"] = "CAF3",
  ["Ctrl+Alt+F4"] = "CAF4",
  ["Ctrl+Alt+F5"] = "CAF5",
  ["Ctrl+Alt+F6"] = "CAF6",
  ["Ctrl+Alt+F7"] = "CAF7",
  ["Ctrl+Alt+F8"] = "CAF8",
  ["Ctrl+Alt+F9"] = "CAF9",
  ["Ctrl+Alt+F10"] = "CAF10",
  ["Ctrl+Alt+F11"] = "CAF11",
  ["Ctrl+Alt+F12"] = "CAF12",
  ["Ctrl+Alt+F13"] = "CAF13",
  ["Ctrl+Alt+F14"] = "CAF14",
  ["Ctrl+Alt+F15"] = "CAF15",
  ["Ctrl+Alt+F16"] = "CAF16",
  ["Ctrl+Alt+F17"] = "CAF17",
  ["Ctrl+Alt+F18"] = "CAF18",
  ["Ctrl+Alt+F19"] = "CAF19",
  ["Ctrl+Alt+F20"] = "CAF20",
  ["Ctrl+Alt+F21"] = "CAF21",
  ["Ctrl+Alt+F22"] = "CAF22",
  ["Ctrl+Alt+F23"] = "CAF23",
  ["Ctrl+Alt+F24"] = "CAF24",
  ["Escape"] = "Esc",
  ["Insert"] = "Ins",
  ["Delete"] = "Del",
  ["PageUp"] = "PgUp",
  ["Ctrl+PageUp"] = "CPgUp",
  ["Shift+PageUp"] = "SPgUp",
  ["Alt+PageUp"] = "APgUp",
  ["Num+Plus"] = "N+",
  ["Num+Enter"] = "NEnter",
  ["HalfQuote"] = "'",
  ["Num+/"] = "N/",
  ["Num+*"] = "N*",
  ["Num+-"] = "N-",
  ["Num+Enter"] = "NEnter",
  ["Num+,"] = "N,",
  ["Mouse4"] = "MB4",
  ["Mouse5"] = "MB5",
  ["MouseUp"] = "MUp",
  ["MouseDown"] = "MDown"
}

local gold = {
  [3031] = "gold coin",
  [3035] = "platinum coin",
  [3043] = "crystal coin"
}

function getItemNameById(itemId)
  if gold[itemId] then
    return gold[itemId]
  end

  local types = g_things.findThingTypeByAttr(ThingAttrMarket, 0)
	for _, itemType in pairs(types) do
    if itemType:getId() == itemId then
      local marketData = itemType:getMarketData()
			if not table.empty(marketData) then
        return marketData.name
      end
    end
	end
  return "Unkown item"
end

function postostring(pos)
  return pos.x .. " " .. pos.y .. " " .. pos.z
end

function dirtostring(dir)
	for k, v in pairs(Directions) do
		if v == dir then
			return k
		end
	end
end

function createTexturedBar(id, min, max, texWidth, texHeight, panel, step, pos)
	local clipY, posY, height = nil

	if step == nil and pos == nil then
		clipY = 0
		posY = 0
		height = texHeight
	else
		clipY = texHeight / step
		posY = clipY * pos
		height = clipY
	end

	local val = panel
	local bar = val:getChildById(id)
	local globalWidth = texWidth
	local percent = min * 100 / max
	local sizePercent = percent * globalWidth / 100
	local width = round(sizePercent, decimal)

	bar:setId(id)
	bar:setHeight(height)

	if max <= 0 then
		bar:setWidth(texWidth)
		bar:setImageClip("0 " .. posY .. " " .. texWidth .. " " .. height)
	else
		bar:setWidth(width)
		bar:setImageClip("0 " .. posY .. " " .. width .. " " .. height)
	end
	return bar
end

function round(val, decimal)
	if decimal then
		return math.floor(val * 10^decimal + 0.5) / 10^decimal
	else
		return math.floor(val + 0.5)
	end
end

function math.format(integer)
    for i = 1, math.floor((string.len(integer)-1) / 3) do
        integer = string.sub(integer, 1, -3*i-i) ..
                  ',' ..
                  string.sub(integer, -3*i-i+1)
    end
    return integer
end

function short_text(text, chars_limit)
  text = tostring(text or '')
  if #text > chars_limit then
    local newstring = ''
    for char in (text):gmatch(".") do
      newstring = string.format("%s%s", newstring, char)
      if #newstring >= chars_limit then
        break
      end
    end
    return newstring .. '...'
  else
    return text
  end
end

function newline_text_long(text, chars_limit)
  if #text > chars_limit then
    local breakPoint = chars_limit
    while breakPoint <= #text and text:sub(breakPoint, breakPoint) ~= " " do
        breakPoint = breakPoint + 1
    end
    return text:sub(1, breakPoint) .. "\n" .. text:sub(breakPoint + 1)
  else
    return text
  end
end

-- objeto a ser criado
local BIT ={}

-- criando a metatable
function BIT:new(number)
  return setmetatable({number = number}, { __index = self })
end

-- Simplificando a criacao da metatable
function NewBit(number)
  return BIT:new(number)
end

-- checa se a flag tem o valor
function hasBitSet( flag,  flags)
  return bit.band(flags, flag) ~= 0;
end

-- setando uma nova flag
function setFlag(bt, flag)
  return bit.bor(bt, flag)
end

-- checa se tem a flag
function BIT:hasFlag(flag)
  return hasBitSet( flag,  self.number)
end

-- adiciona uma nova flag
function BIT:updateFlag(flag)
  self.number = setFlag(self.number, flag)
end

-- atualiza o numero/flag por fora da metatable
function BIT:updateNumber(number)
  self.number = number
end

-- retorna o numero/flag
function BIT:getNumber()
  return self.number
end

ObjectCategory = {
  OBJECTCATEGORY_NONE = 0,
  OBJECTCATEGORY_ARMORS = 1,
  OBJECTCATEGORY_NECKLACES = 2,
  OBJECTCATEGORY_BOOTS = 3,
  OBJECTCATEGORY_CONTAINERS = 4,
  OBJECTCATEGORY_DECORATION = 5,
  OBJECTCATEGORY_FOOD = 6,
  OBJECTCATEGORY_HELMETS = 7,
  OBJECTCATEGORY_LEGS = 8,
  OBJECTCATEGORY_OTHERS = 9,
  OBJECTCATEGORY_POTIONS = 10,
  OBJECTCATEGORY_RINGS = 11,
  OBJECTCATEGORY_RUNES = 12,
  OBJECTCATEGORY_SHIELDS = 13,
  OBJECTCATEGORY_TOOLS = 14,
  OBJECTCATEGORY_VALUABLES = 15,
  OBJECTCATEGORY_AMMO = 16,
  OBJECTCATEGORY_AXES = 17,
  OBJECTCATEGORY_CLUBS = 18,
  OBJECTCATEGORY_DISTANCEWEAPONS = 19,
  OBJECTCATEGORY_SWORDS = 20,
  OBJECTCATEGORY_WANDS = 21,
  OBJECTCATEGORY_PREMIUMSCROLLS = 22,
  OBJECTCATEGORY_TIBIACOINS = 23,
  OBJECTCATEGORY_CREATUREPRODUCTS = 24,
  OBJECTCATEGORY_QUIVER = 25,
  OBJECTCATEGORY_FIST = 27,
  OBJECTCATEGORY_GOLD = 30,
  OBJECTCATEGORY_DEFAULT = 31,

  OBJECTCATEGORY_FIRST = 1,
  OBJECTCATEGORY_LAST = 31,
}

ObjectCategoryOrder = {
  ObjectCategory.OBJECTCATEGORY_DEFAULT, ObjectCategory.OBJECTCATEGORY_GOLD, 
  ObjectCategory.OBJECTCATEGORY_ARMORS, ObjectCategory.OBJECTCATEGORY_NECKLACES,
  ObjectCategory.OBJECTCATEGORY_BOOTS, ObjectCategory.OBJECTCATEGORY_CONTAINERS,
  ObjectCategory.OBJECTCATEGORY_CREATUREPRODUCTS, ObjectCategory.OBJECTCATEGORY_DECORATION,
  ObjectCategory.OBJECTCATEGORY_FOOD, ObjectCategory.OBJECTCATEGORY_HELMETS,
  ObjectCategory.OBJECTCATEGORY_LEGS, ObjectCategory.OBJECTCATEGORY_OTHERS,
  ObjectCategory.OBJECTCATEGORY_POTIONS, ObjectCategory.OBJECTCATEGORY_RINGS,
  ObjectCategory.OBJECTCATEGORY_RUNES, ObjectCategory.OBJECTCATEGORY_SHIELDS,
  ObjectCategory.OBJECTCATEGORY_TOOLS, ObjectCategory.OBJECTCATEGORY_VALUABLES,
  ObjectCategory.OBJECTCATEGORY_AMMO, ObjectCategory.OBJECTCATEGORY_AXES,
  ObjectCategory.OBJECTCATEGORY_CLUBS, ObjectCategory.OBJECTCATEGORY_DISTANCEWEAPONS,
  ObjectCategory.OBJECTCATEGORY_FIST, ObjectCategory.OBJECTCATEGORY_SWORDS,
  ObjectCategory.OBJECTCATEGORY_WANDS, ObjectCategory.OBJECTCATEGORY_QUIVER
}

function getObjectCategoryName(category)
  if (category == ObjectCategory.OBJECTCATEGORY_QUIVER) then
    return "Quivers"
  elseif (category == ObjectCategory.OBJECTCATEGORY_WANDS) then
    return "Weapons:\nWands"
  elseif (category == ObjectCategory.OBJECTCATEGORY_SWORDS) then
    return "Weapons:\nSwords"
  elseif (category == ObjectCategory.OBJECTCATEGORY_DISTANCEWEAPONS) then
    return "Weapons:\nDistance"
  elseif (category == ObjectCategory.OBJECTCATEGORY_CLUBS) then
    return "Weapons:\nClubs"
  elseif (category == ObjectCategory.OBJECTCATEGORY_AXES) then
    return "Weapons:\nAxes"
  elseif (category == ObjectCategory.OBJECTCATEGORY_AMMO) then
    return "Weapons:\nAmmo"
  elseif (category == ObjectCategory.OBJECTCATEGORY_FIST) then
    return "Weapons:\nFist"
  elseif (category == ObjectCategory.OBJECTCATEGORY_VALUABLES) then
    return "Valuables"
  elseif (category == ObjectCategory.OBJECTCATEGORY_TOOLS) then
    return "Tools"
  elseif (category == ObjectCategory.OBJECTCATEGORY_SHIELDS) then
    return "Shields"
  elseif (category == ObjectCategory.OBJECTCATEGORY_RUNES) then
    return "Runes"
  elseif (category == ObjectCategory.OBJECTCATEGORY_RINGS) then
    return "Rings"
  elseif (category == ObjectCategory.OBJECTCATEGORY_POTIONS) then
    return "Potions"
  elseif (category == ObjectCategory.OBJECTCATEGORY_OTHERS) then
    return "Others"
  elseif (category == ObjectCategory.OBJECTCATEGORY_LEGS) then
    return "Legs"
  elseif (category == ObjectCategory.OBJECTCATEGORY_HELMETS) then
    return "Helmets\nand Hats"
  elseif (category == ObjectCategory.OBJECTCATEGORY_FOOD) then
    return "Food"
  elseif (category == ObjectCategory.OBJECTCATEGORY_DECORATION) then
    return "Decoration"
  elseif (category == ObjectCategory.OBJECTCATEGORY_CREATUREPRODUCTS) then
    return "Creature\nProducts"
  elseif (category == ObjectCategory.OBJECTCATEGORY_CONTAINERS) then
    return "Containers"
  elseif (category == ObjectCategory.OBJECTCATEGORY_BOOTS) then
    return "Boots"
  elseif (category == ObjectCategory.OBJECTCATEGORY_NECKLACES) then
    return "Amulets"
  elseif (category == ObjectCategory.OBJECTCATEGORY_ARMORS) then
    return "Armors"
  elseif (category == ObjectCategory.OBJECTCATEGORY_GOLD) then
    return "Gold"
  elseif (category == ObjectCategory.OBJECTCATEGORY_DEFAULT) then
    return "Unassigned"
  else
    return ''
  end
end

function updateFlags(item, itemWidget)
  if not itemWidget then
    return
  end

  local widgetLoot = itemWidget.quicklootflags
  if widgetLoot then
    widgetLoot:setVisible(false)
  end

  if widgetLoot and item and item:isContainer() and (item:getQuickLootFlags() > 0 or item:getObtainFlags() > 0) then
    widgetLoot:setVisible(false)
    local text = "Loot container for:"
    for i = ObjectCategory.OBJECTCATEGORY_LAST, ObjectCategory.OBJECTCATEGORY_FIRST, -1 do
      if item:getQuickLootFlags() > 0 and hasBitSet(bit.lshift(1, i), item:getQuickLootFlags()) then
        text = text .. '\n' .. getObjectCategoryName(i)
      end
    end
    if item:getObtainFlags() > 0 then
      text = text .. "\n\nObtain container for:"
      for i = ObjectCategory.OBJECTCATEGORY_LAST, ObjectCategory.OBJECTCATEGORY_FIRST, -1 do
        if hasBitSet(bit.lshift(1, i), item:getObtainFlags()) then
          text = text .. '\n' .. getObjectCategoryName(i)
        end
      end
    end
    widgetLoot:setVisible(true)
    widgetLoot:setTooltip(text)
  end
end

function isStash(thing)
  return thing:getId() == 28750
end

function isGoldCoin(itemId)
  if gold[itemId] then
    return true
  end
  return false
end

--dofile('core/core.lua')
function dumpvar(data)
    -- cache of tables already printed, to avoid infinite recursive loops
    local tablecache = {}
    local buffer = ""
    local padder = "    "

    local function _dumpvar(d, depth)
        local t = type(d)
        local str = tostring(d)
        if (t == "table") then
            if (tablecache[str]) then
                -- table already dumped before, so we dont
                -- dump it again, just mention it
                buffer = buffer.."<"..str..">\n"
            else
                tablecache[str] = (tablecache[str] or 0) + 1
                buffer = buffer.."("..str..") {\n"
                for k, v in pairs(d) do
                    buffer = buffer..string.rep(padder, depth+1).."["..k.."] => "
                    _dumpvar(v, depth+1)
                end
                buffer = buffer..string.rep(padder, depth).."}\n"
            end
        elseif (t == "number") then
            buffer = buffer.."("..t..") "..str.."\n"
        else
            buffer = buffer.."("..t..") \""..str.."\"\n"
        end
    end
    _dumpvar(data, 0)
    return buffer
end

function formatMoney(amount, separator)
  local patternSeparator = string.format("%%1%s%%2", separator)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", patternSeparator)
    if (k==0) then
      break
    end
  end
  return formatted
end

function tokformat(amount)
  return math.floor(tonumber(amount) or 0)
end

function matchText(input, target)
    input = input:lower()
    target = target:lower()

    if input == target then
        return true
    end

    if #input >= 1 and target:find(input, 1, true) then
        return true
    end
    return false
end

function convertSkillPercent(percent, applyPercent)
    if applyPercent == nil then
      applyPercent = true
    end
    local whole = math.floor(percent / 100)
    local fractional = percent % 100

    if fractional == 0 then
        return tostring(whole) .. ""
    else
        if applyPercent then
          return string.format("%d.%02d%%", whole, fractional)
        else
          return string.format("%d.%02d", whole, fractional)
        end
    end
end

function formatPercentU16(value)
  local whole = math.floor(value / 100)
  local fractional = value % 100

  return string.format("%d.%02d%%", whole, fractional)
end

function formatTimeBySeconds(seconds)
    local hours = math.floor(seconds / 3600)
    local remainingSeconds = seconds % 3600
    local minutes = math.floor(remainingSeconds / 60)
    return string.format("%02d:%02d", hours, minutes)
end

function formatTimeBySecondsExtended(seconds)
    local hours = math.floor(seconds / 3600)
    local remainingSeconds = seconds % 3600
    local minutes = math.floor(remainingSeconds / 60)
    local secs = remainingSeconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

function formatTimeByMinutes(minutes)
	local seconds = minutes * 60
    local hours = math.floor(seconds / 3600)
    local remainingSeconds = seconds % 3600
    local remainingMinutes = math.floor(remainingSeconds / 60)
    return string.format("%02d:%02d", hours, remainingMinutes)
end

function math.cround(value, rd)
    local _round = math.floor(value / rd)
    return _round * rd
end

function getCombatName(combat)
	local names = {"Physical", "Fire", "Earth", "Energy", "Ice", "Holy", "Death", "Healing", "Drown", "Life Drain", "Mana Drain", "Agony"}
	return names[combat + 1]
end

-- servers may have different id's, change if not working properly (only for protocols 910+)
function getVocationId(name)
  if string.find(name:lower(), "knight") then
    return 8 -- ek
  elseif string.find(name:lower(), "paladin") then
    return 7 -- rp
  elseif string.find(name:lower(), "sorcerer") then
    return 5 -- ms
  elseif string.find(name:lower(), "druid") then
    return 6 -- ed
  elseif string.find(name:lower(), "monk") then
    return 9 -- em
  end

  return 0
end
-- servers may have different id's, change if not working properly (only for protocols 910+)
function getVocationSt(id)
  if id == 1 then
    return "K0"
  elseif id == 2 then
    return "P0"
  elseif id == 3 then
    return "S0"
  elseif id == 4 then
    return "D0"
  elseif id == 5 then
    return "M0"
  end
  return "N"
end

function getItemPriceColor(value)
	if value >= 1000000 then
		return 'item-gold'
	elseif value >= 100000 then
		return 'item-purple'
	elseif value >= 10000 then
		return 'item-blue'
	elseif value >= 1000 then
		return 'item-green'
	elseif value >= 1 then
		return 'item-gray'
	end
	return ''
end

function format_thousand(v)
    if not v then return 0 end
    local s = string.format("%d", math.floor(v))
    local pos = string.len(s) % 3
    if pos == 0 then pos = 3 end
    return string.sub(s, 1, pos)
    .. string.gsub(string.sub(s, pos+1), "(...)", ".%1")
end

function translateDisplayHotkey(text)
  if HotkeyShortcuts[text] then
    text = HotkeyShortcuts[text]
  elseif string.len(text) > 5 then
    text = "..." .. string.sub(text, string.len(text) - 2, string.len(text))
  end
  return text
end

function translateVocation(id)
  if not id or id == 0 then return 0 end
  if id == 4 or id == 8 then return 8 end     -- Knight / Elite Knight
  if id == 3 or id == 7 then return 7 end     -- Paladin / Royal Paladin
  if id == 1 or id == 5 then return 5 end     -- Sorcerer / Master Sorcerer
  if id == 2 or id == 6 then return 6 end     -- Druid / Elder Druid
  if id == 9 or id == 10 then return 10 end   -- Monk / Exalted Monk
  return 0
end

function translateWheelVocation(id)
  if not id or id == 0 then return 0 end
  if id == 4 or id == 8 then return 1 end     -- Knight / Elite Knight
  if id == 3 or id == 7 then return 2 end     -- Paladin / Royal Paladin
  if id == 1 or id == 5 then return 3 end     -- Sorcerer / Master Sorcerer
  if id == 2 or id == 6 then return 4 end     -- Druid / Elder Druid
  if id == 9 or id == 10 then return 5 end    -- Monk / Exalted Monk
  return 0
end

function translateVocationName(id)
  if not id or id == 0 then return "Rookie" end
  if id == 4 or id == 8 then return "Knight" end
  if id == 3 or id == 7 then return "Paladin" end
  if id == 1 or id == 5 then return "Sorcerer" end
  if id == 2 or id == 6 then return "Druid" end
  if id == 9 or id == 10 then return "Monk" end
  return "Rookie"
end



function hasLink(text)
  local domains =
      [[.ac.ad.ae.aero.af.ag.ai.al.am.an.ao.aq.ar.arpa.as.asia.at.au
 .aw.ax.az.ba.bb.bd.be.bf.bg.bh.bi.biz.bj.bm.bn.bo.br.bs.bt.bv.bw.by.bz.ca
 .cat.cc.cd.cf.cg.ch.ci.ck.cl.cm.cn.co.com.coop.cr.cs.cu.cv.cx.cy.cz.dd.de
 .dj.dk.dm.do.dz.ec.edu.ee.eg.eh.er.es.et.eu.fi.firm.fj.fk.fm.fo.fr.fx.ga
 .gb.gd.ge.gf.gh.gi.gl.gm.gn.gov.gp.gq.gr.gs.gt.gu.gw.gy.hk.hm.hn.hr.ht.hu
 .id.ie.il.im.in.info.int.io.iq.ir.is.it.je.jm.jo.jobs.jp.ke.kg.kh.ki.km.kn
 .kp.kr.kw.ky.kz.la.lb.lc.li.lk.lr.ls.lt.lu.lv.ly.ma.mc.md.me.mg.mh.mil.mk
 .ml.mm.mn.mo.mobi.mp.mq.mr.ms.mt.mu.museum.mv.mw.mx.my.mz.na.name.nato.nc
 .ne.net.nf.ng.ni.nl.no.nom.np.nr.nt.nu.nz.om.org.pa.pe.pf.pg.ph.pk.pl.pm
 .pn.post.pr.pro.ps.pt.pw.py.qa.re.ro.ru.rw.sa.sb.sc.sd.se.sg.sh.si.sj.sk
 .sl.sm.sn.so.sr.ss.st.store.su.sv.sy.sz.tc.td.tel.tf.tg.th.tj.tk.tl.tm.tn
 .to.tp.tr.travel.tt.tv.tw.tz.ua.ug.uk.um.us.uy.va.vc.ve.vg.vi.vn.vu.web.wf
 .ws.xxx.ye.yt.yu.za.zm.zr.zw]]

  local tlds = {}
  for tld in domains:gmatch "%w+" do
      tlds[tld] = true
  end
  local function max4(a, b, c, d)
      return math.max(a + 0, b + 0, c + 0, d + 0)
  end
  local protocols = {[""] = 0, ["http://"] = 0, ["https://"] = 0, ["ftp://"] = 0}
  local finished = {}

  for pos_start, url, prot, subd, tld, colon, port, slash, path in text:gmatch "()(([%w_.~!*:@&+$/?%%#-]-)(%w[-.%w]*%.)(%w+)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))" do
      if
          protocols[prot:lower()] == (1 - #slash) * #path and not subd:find "%W%W" and
              (colon == "" or port ~= "" and port + 0 < 65536) and
              (tlds[tld:lower()] or
                  tld:find "^%d+$" and subd:find "^%d+%.%d+%.%d+%.$" and
                      max4(tld, subd:match "^(%d+)%.(%d+)%.(%d+)%.$") < 256)
       then
          finished[pos_start] = true
          return true
      end
  end

  for pos_start, url, prot, dom, colon, port, slash, path in text:gmatch "()((%f[%w]%a+://)(%w[-.%w]*)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))" do
      if
          not finished[pos_start] and not (dom .. "."):find "%W%W" and protocols[prot:lower()] == (1 - #slash) * #path and
              (colon == "" or port ~= "" and port + 0 < 65536)
       then
          return true
      end
  end
  return false
end

function tryCatch(func, ...)
  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end

  local status, result = pcall(func, ...)
  if not status then
    -- Handle error
    print(desc .. ": " .. result)
    return nil, result
  end
  return result
end

function getNextDay(day, month, year)
  local function isLeapYear(year)
    if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
      return true
    else
      return false
    end
  end

  local daysInMonth = {
    31, -- January
    isLeapYear(year) and 29 or 28, -- February
    31, -- March
    30, -- April
    31, -- May
    30, -- June
    31, -- July
    31, -- August
    30, -- September
    31, -- October
    30, -- November
    31  -- December
  }

  day = day + 1

  if day > daysInMonth[month] then
    day = 1
    month = month + 1

    if month > 12 then
      month = 1
      year = year + 1
    end
  end
  return day, month, year
end

function onError(error)
  g_logger.error(error)
end

function normalize_value(value, default)
  if value == math.huge or value == -math.huge or value ~= value then
      return default or 0
  else
      return value
  end
end

function getFramePosition(id, frameWidth, frameHeight, fpr)
  local frameWidth = 64
  local frameHeight = 64
  local framesPerRow = 21
  
  if id == 0 then
      return "0 0"
  end

  local adjustedId = id - 1
  local row = math.floor(adjustedId / fpr) + 1
  local col = adjustedId % fpr
  return col * frameWidth .. " " .. row * frameHeight
end

function format_cnpj(cnpj)
  cnpj = string.gsub(cnpj, "%D", "")

  if #cnpj > 14 then
      cnpj = string.sub(cnpj, 1, 14)
  end

  if #cnpj == 14 then
      cnpj = string.sub(cnpj, 1, 2) .. "." ..
             string.sub(cnpj, 3, 5) .. "." ..
             string.sub(cnpj, 6, 8) .. "/" ..
             string.sub(cnpj, 9, 12) .. "-" ..
             string.sub(cnpj, 13, 14)
  end

  return cnpj
end

function format_cpf(cpf)
  cpf = string.gsub(cpf, "%D", "")
  if #cpf > 11 then
      cpf = string.sub(cpf, 1, 11)
  end

  if #cpf == 11 then
      cpf = string.sub(cpf, 1, 3) .. "." ..
            string.sub(cpf, 4, 6) .. "." ..
            string.sub(cpf, 7, 9) .. "-" ..
            string.sub(cpf, 10, 11)
  end
  return cpf
end

function getTimeInWords(secs)
  local hours = math.floor(secs / 3600)
  local minutes = math.floor((secs % 3600) / 60)
  local seconds = secs % 60

  local function pluralize(value, singular, plural)
      return value == 1 and singular or plural
  end

  local timeParts = {}

  if hours > 0 then
      table.insert(timeParts, hours .. "h")
  end
  if minutes > 0 then
      table.insert(timeParts, minutes .. "min")
  end
  if seconds > 0 or #timeParts == 0 then
      if minutes < 1 then
          table.insert(timeParts, seconds .. " " .. pluralize(seconds, "second", "seconds"))
      else 
        table.insert(timeParts, seconds .. "s")
      end
  end

  return table.concat(timeParts, " ")
end

function getTimeInShortWords(seconds)
    local minutes = math.floor(seconds / 60)
    local remainingSeconds = seconds % 60
    return string.format("%02d:%02d", minutes, remainingSeconds)
end

function wrapTextByWords(str, n)
	local result = {}
	local i = 1
	while i <= #str do
		local chunk = str:sub(i, i + n - 1)
		if #chunk < n then
			table.insert(result, chunk)
			break
		end

		-- find last space or punctuation within chunk
		local breakAt = chunk:match("^.*()[%s,%.;:!?%-]")
		if breakAt and breakAt > 1 then
      local chunk = str:sub(i, i + breakAt - 1)
      chunk = chunk:gsub("[%s,%.;:!?%-]+$", "")
      table.insert(result, chunk)
			i = i + breakAt
		else
			-- fallback if no space/punctuation is found
			table.insert(result, chunk)
			i = i + n
		end
	end
	return table.concat(result, "\n")
end

function getElementName(elementId)
	local elementNames = {
		[0]  = "Physical",
		[1]  = "Fire",
		[2]  = "Earth",
		[3]  = "Energy",
		[4]  = "Ice",
		[5]  = "Holy",
		[6]  = "Death",
		[7]  = "Healing",
		[8]  = "Drown",
		[9]  = "Life Drain",
		[10] = "Mana Drain",
		[11] = "Agony"
	}

	return elementNames[elementId] or "Unknown"
end

-- Reset fields called in onGameStart
function onFinishWatchBroadcast()
  if not g_game.isOnline() then
    return
  end

  -- Re-open current channels
  modules.game_console.g_chat:reopenChannels()

  -- Request imbuement tracker if needed
  modules.game_trackers.reopenImbuementPanel()

  -- Request quickloot whitelist
  modules.game_quickloot.reloadLootWhiteList()
end
