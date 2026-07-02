if not ImpactAnalyser then
	ImpactAnalyser = {
		launchTime = 0,
		session = 0,

		damageTotal = 0,
		dps = 0,
		maxDPS = 0,
		damageTicks = {},
		healingTicks = {},
		damageEffect = {},
		allTimeHightDps = 0,
		allTimeHightHps = 0,
		damageTypeVisible = true,

		healingTotal = 0,
		maxHPS = 0,

		-- private
		window = nil,
	}
	ImpactAnalyser.__index = ImpactAnalyser
end

local imageDir = '/images/game/cyclopedia/icons/monster-icon-%s-resist'

local effectsFiles = {
	[0] = 'physical',
	[1] = 'fire',
	[2] = 'earth',
	[3] = 'energy',
	[4] = 'ice',
	[5] = 'holy',
	[6] = 'death',
	[7] = 'healing',
	[8] = 'drowning',
	[9] = 'lifedrain',
	[10] = 'manadrain',
	[11] = 'agony',
	[12] = 'agony',
}

local valueInSeconds = function(t)
    local d = 0
    local time = 0
    local now = g_clock.millis()
    if #t > 0 then
		local itemsToBeRemoved = 0
        for i, v in ipairs(t) do
            if now - v.tick <= 10000 then
                if time == 0 then
                    time = v.tick
                end
                d = d + v.amount
            else
				itemsToBeRemoved = itemsToBeRemoved + 1
            end
        end

		-- items are added in order, so the expired entries are always a
		-- contiguous prefix. Compact survivors to the front once instead of
		-- calling table.remove(t, 1) per element (which shifts the whole
		-- array each time -> O(n^2)). Result is identical.
		if itemsToBeRemoved > 0 then
			local n = #t
			for i = itemsToBeRemoved + 1, n do
				t[i - itemsToBeRemoved] = t[i]
			end
			for i = n - itemsToBeRemoved + 1, n do
				t[i] = nil
			end
		end
    end
    return math.ceil(d/((now-time)/1000))
end

function ImpactAnalyser:create()
	ImpactAnalyser.launchTime = 0
	ImpactAnalyser.session = 0

	ImpactAnalyser.damageTotal = 0
	ImpactAnalyser.dps = 0
	ImpactAnalyser.maxDPS = 0
	ImpactAnalyser.damageTicks = {}
	ImpactAnalyser.healingTicks = {}
	ImpactAnalyser.damageEffect = {}
	ImpactAnalyser.allTimeHightDps = 0
	ImpactAnalyser.allTimeHightHps = 0
	ImpactAnalyser.damageTypeVisible = true

	ImpactAnalyser.healingTotal = 0
	ImpactAnalyser.maxHPS = 0

	-- private
	ImpactAnalyser.window = openedWindows['impactButton']
end

function ImpactAnalyser:reset(allTimeDps, allTimeHps)
	ImpactAnalyser.launchTime = g_clock.millis()
	ImpactAnalyser.session = 0

	ImpactAnalyser.damageTotal = 0
	ImpactAnalyser.dps = 0
	ImpactAnalyser.maxDPS = 0
	ImpactAnalyser.maxHPS = 0
	if allTimeDps then
		ImpactAnalyser.allTimeHightDps = 0
	end
	if allTimeHps then
		ImpactAnalyser.allTimeHightHps = 0
	end
	ImpactAnalyser.damageTicks = {}
	ImpactAnalyser.healingTicks = {}
	ImpactAnalyser.damageEffect = {}

	ImpactAnalyser.healingTotal = 0

	ImpactAnalyser:updateWindow()
end

function ImpactAnalyser:updateWindow(ignoreVisible)
	if not ImpactAnalyser.window:isVisible() and not ignoreVisible then
		return
	end
	ImpactAnalyser:checkAnchos()
	local contentsPanel = ImpactAnalyser.window.contentsPanel

	contentsPanel.dmg:setText(formatMoney(tokformat(ImpactAnalyser.damageTotal), ","))
	contentsPanel.allTimeHigh:setText(formatMoney(tokformat(ImpactAnalyser.allTimeHightDps), ","))
	local curHPS = valueInSeconds(ImpactAnalyser.damageTicks)
	if not curHPS then curHPS = 0 end
	ImpactAnalyser.maxDPS = ImpactAnalyser.maxDPS > curHPS and ImpactAnalyser.maxDPS or curHPS

	contentsPanel.maxDps:setText(formatMoney(tokformat(ImpactAnalyser.maxDPS), ","))
	contentsPanel.dps:setText(formatMoney(tokformat(curHPS), ","))

	----------------------- DAMAGE TYPE -----------------------------
	for _, child in pairs(contentsPanel.dmgTypes:getChildren()) do
		child.toBeRemoved = true
	end

	if table.empty(ImpactAnalyser.damageEffect) then
		if contentsPanel.dmgTypes:getChildCount() > 0 then
			contentsPanel.dmgTypes:destroyChildren()
		end

		g_ui.createWidget('NoDataLabel', contentsPanel.dmgTypes)
	else
		for effect, damage in pairs(ImpactAnalyser.damageEffect) do
			local widget = contentsPanel.dmgTypes:getChildById("DamageEffect_" .. effect)
			if not widget then
				widget = g_ui.createWidget('DamagePanel', contentsPanel.dmgTypes)
				widget:setId("DamageEffect_" .. effect)
				widget.icon:setImageSource(string.format(imageDir, effectsFiles[effect]))
				widget.icon:setTooltip(getCombatName(effect))
			end

			local percent = (damage * 100) / ImpactAnalyser.damageTotal
			widget.desc:setText(formatMoney(tokformat(damage), ",") .. " (" .. string.format("%.1f", percent) .. "%)")
			widget.toBeRemoved = false
		end
	end

	for _, child in pairs(contentsPanel.dmgTypes:getChildren()) do
		if child.toBeRemoved then
			child:destroy()
		end
	end

	---------------------------- Healing -------------------------------

	contentsPanel.hpsTotal:setText(formatMoney(tokformat(ImpactAnalyser.healingTotal), ","))
	contentsPanel.allTimeHighHealing:setText(formatMoney(tokformat(ImpactAnalyser.allTimeHightHps), ","))

	local curHPS = valueInSeconds(ImpactAnalyser.healingTicks)
	if not curHPS then curHPS = 0 end
	ImpactAnalyser.maxHPS = ImpactAnalyser.maxHPS > curHPS and ImpactAnalyser.maxHPS or curHPS

	contentsPanel.maxHps:setText(formatMoney(tokformat(ImpactAnalyser.maxHPS), ","))
	contentsPanel.hps:setText(formatMoney(tokformat(curHPS), ","))
end

function ImpactAnalyser:addDealDamage(amount, effect)
	if amount > ImpactAnalyser.allTimeHightDps then
		ImpactAnalyser.allTimeHightDps = amount
	end
	ImpactAnalyser.damageTotal = ImpactAnalyser.damageTotal + amount
	ImpactAnalyser.damageTicks[#ImpactAnalyser.damageTicks + 1] = {amount = amount, tick = g_clock.millis()}
	if not ImpactAnalyser.damageEffect[effect] then
		ImpactAnalyser.damageEffect[effect] = 0
	end

	ImpactAnalyser.damageEffect[effect] = ImpactAnalyser.damageEffect[effect] + amount
end

function ImpactAnalyser:addHealing(amount)
	if amount > ImpactAnalyser.allTimeHightHps then
		ImpactAnalyser.allTimeHightHps = amount
	end
	ImpactAnalyser.healingTotal = ImpactAnalyser.healingTotal + amount
	ImpactAnalyser.healingTicks[#ImpactAnalyser.healingTicks + 1] = {amount = amount, tick = g_clock.millis()}
end


function onImpactExtra(mousePosition)
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

	local menu = g_ui.createWidget('PopupMenu')
	menu:setGameMenu(true)
	menu:addOption(tr('Reset Data'), function() ImpactAnalyser:reset(false) return end)
	menu:addOption(tr('Reset All-Time High'), function() ImpactAnalyser:setAllTimeHightDps(0);ImpactAnalyser:setAllTimeHightHps(0) end)
	menu:addSeparator()
	menu:addCheckBoxOption(tr('Damage Types'), function()
		ImpactAnalyser:setDamageType(not ImpactAnalyser.window.contentsPanel.damageTypeLabel:isVisible(), true)
	end, "", ImpactAnalyser.window.contentsPanel.damageTypeLabel:isVisible())
	menu:display(mousePosition)
  return true
end

function ImpactAnalyser:setDamageType(value, check)
	ImpactAnalyser.window.contentsPanel.damageTypeLabel:setVisible(value)
	ImpactAnalyser.window.contentsPanel.dmgTypes:setVisible(value)
	ImpactAnalyser.window.contentsPanel.separatorDmgType:setVisible(value)


	ImpactAnalyser.damageTypeVisible = value

	if check then
		ImpactAnalyser:checkAnchos()
	end
end

function ImpactAnalyser:checkAnchos()
	-- Damage Types pode ser ocultado pelo menu; quando some, o bloco de Healing
	-- precisa reancorar no separador do DPS ao vivo (ver impact.otui).
	if ImpactAnalyser.window.contentsPanel.damageTypeLabel:isVisible() then
		ImpactAnalyser.window.contentsPanel.healingLabel:addAnchor(AnchorTop, 'separatorDmgType', AnchorBottom)
	else
		ImpactAnalyser.window.contentsPanel.healingLabel:addAnchor(AnchorTop, 'separatorDps', AnchorBottom)
	end
end

-- getters
function ImpactAnalyser:getAllTimeHightDps() return ImpactAnalyser.allTimeHightDps end
function ImpactAnalyser:damageTypeIsVisible() return ImpactAnalyser.damageTypeVisible end

-- setters
function ImpactAnalyser:setAllTimeHightDps(value) ImpactAnalyser.allTimeHightDps = value end
function ImpactAnalyser:setAllTimeHightHps(value) ImpactAnalyser.allTimeHightHps = value end

function ImpactAnalyser:loadConfigJson()
	local config = {
		desiredDamageTypesVisible = true,
		maxDamageImpact = 0,
		maxHealingImpact = 0,
		showSessionValues = true,
	}

	local player = g_game.getLocalPlayer()
	local file = "/characterdata/" .. player:getId() .. "/impactanalyser.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return g_logger.error("Error while reading characterdata file. Details: " .. result)
		end

		config = result
	end

	ImpactAnalyser:setDamageType(config.desiredDamageTypesVisible, false)
	ImpactAnalyser.allTimeHightDps = config.maxDamageImpact
	ImpactAnalyser.allTimeHightHps = config.maxHealingImpact

	ImpactAnalyser:checkAnchos()
end

function ImpactAnalyser:saveConfigJson()
	local function checkFinite(value)
		if value == math.huge or value == -math.huge or type(value) ~= "number" then
			return 0
		end
		return value
	end

	local config = {
		desiredDamageTypesVisible = ImpactAnalyser:damageTypeIsVisible(),
		maxDamageImpact = checkFinite(ImpactAnalyser.allTimeHightDps),
		maxHealingImpact = checkFinite(ImpactAnalyser.allTimeHightHps),
		showSessionValues = true,
	}

	if not LoadedPlayer:isLoaded() then return end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/impactanalyser.json"
	local status, result = pcall(function() return json.encode(config, 2) end)
	if not status then
		return g_logger.error("Error while saving profile ImpactAnalyzer data. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
		return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
	end
	
	g_resources.writeFileContents(file, result)
end

