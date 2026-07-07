-- Addon/Mount Bonus System dialog.
-- Side-button window. Main tabs: Addons, Mounts, Bonuses. Addons/Mounts each render every
-- entry (owned dimmed with an "Owned" tag) plus a "Hide Owned" toggle and Total/Owned
-- counters; store-obtainable outfits/mounts show a small Store button that opens the Store.
-- Each card has a wrapped name, the looktype preview, a scrollable bonus box and two
-- buttons: Details (info panel) and Obtain/Owned. Bonuses shows two side-by-side boxes
-- (addon + mount) with the cumulative totals first, then per-item.
-- Talks to data-koliseu/scripts/custom/addon_mount_otc_bridge.lua over CommandBridge
-- (extended opcode 211, action namespace addonmount.*).

window = nil

local mainTab = 'addons'  -- 'addons' | 'mounts' | 'bonuses'
local hideOwned = false
local pendingObtain = false
local lastEntries = nil   -- full entry list for the current grid view (server response)
local PAGE_SIZE = 24
local currentPage = 1
local searchText = ""
local onlyCoins = false
local buyAllPrice = 0
local buyAllCount = 0
local coinBalance = 0

local TAB_DESC = {
	addons = "All addons. Owned ones are dimmed; store outfits show a blue price button - click it to buy with coins. 'Buy all' unlocks every missing one at a discount.",
	mounts = "All mounts. Owned ones are dimmed; store mounts show a blue price button - click it to buy with coins. 'Buy all' unlocks every missing one at a discount.",
}
local BONUS_DESC = "Your cumulative bonuses. All are passive and ALWAYS active - you don't need to wear the outfit or ride the mount. Totals first, then each item's contribution."

-- ============================================================
-- helpers
-- ============================================================
local function w(id)
	if not window then
		return nil
	end
	return window:recursiveGetChildById(id)
end

local function fmtNum(n)
	n = n or 0
	if n == math.floor(n) then
		return string.format("%d", n)
	end
	local s = string.format("%.2f", n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s
end

local function baseColors()
	local player = g_game.getLocalPlayer()
	local o = player and player:getOutfit() or {}
	return o.head or 0, o.body or 0, o.legs or 0, o.feet or 0
end

local function mountDrawOffset(clientId)
	local tt = g_things.getThingType(tonumber(clientId) or 0, ThingCategoryCreature)
	if not tt then
		return 0, 0
	end
	local off = tt.getDrawOffset and tt:getDrawOffset()
	if off and ((off.x or 0) ~= 0 or (off.y or 0) ~= 0) then
		return off.x, off.y
	end
	if tt:getWidth() == 4 and tt:getHeight() == 4 then
		return 32, 32
	end
	return 0, 0
end

-- Returns the "+X label" lines for a bonus table (indented), or "" when empty.
local function formatBonus(bonus, indent)
	indent = indent or ""
	if not bonus then
		return ""
	end
	local parts = {}
	local function add(value, suffix)
		if value and value ~= 0 then
			parts[#parts + 1] = indent .. "+" .. fmtNum(value) .. suffix
		end
	end
	add(bonus.maxHealthPercent, "% HP")
	add(bonus.maxManaPercent, "% MP")
	add(bonus.capacity, " cap")
	add(bonus.magicLevel, " magic level")
	add(bonus.speed, " speed")
	if bonus.skills then
		for label, value in pairs(bonus.skills) do
			add(value, " " .. label)
		end
	end
	add(bonus.criticalChance, "% crit chance")
	add(bonus.criticalDamage, "% crit damage")
	add(bonus.lifeLeechChance, "% life leech chance")
	add(bonus.lifeLeechAmount, "% life leech")
	add(bonus.manaLeechChance, "% mana leech chance")
	add(bonus.manaLeechAmount, "% mana leech")
	add(bonus.experiencePercent, "% experience")
	add(bonus.mitigation, "% mitigation")
	if bonus.damage then
		for element, value in pairs(bonus.damage) do
			add(value, "% " .. element .. " dmg")
		end
	end
	if bonus.defense then
		for element, value in pairs(bonus.defense) do
			add(value, "% " .. element .. " absorb")
		end
	end
	if (bonus.regeneration or 0) ~= 0 then
		parts[#parts + 1] = indent .. "regeneration"
	end
	if (bonus.manaShield or 0) ~= 0 then
		parts[#parts + 1] = indent .. "mana shield"
	end
	if (bonus.invisible or 0) ~= 0 then
		parts[#parts + 1] = indent .. "invisibility"
	end
	return table.concat(parts, "\n")
end

-- Trim a bonus string to at most maxLines visible lines (full list is in Details) so a
-- card's fixed bonus area never overflows onto the rest of the window.
local function clipBonus(s, maxLines)
	local out, n = {}, 0
	for line in (s .. "\n"):gmatch("(.-)\n") do
		n = n + 1
		if n > maxLines then
			out[maxLines] = "..."
			break
		end
		out[n] = line
	end
	return table.concat(out, "\n")
end

local function setStatusCounts(total, owned)
	local label = w('statusLabel')
	if label then
		label:setText(string.format("Total: %d\nOwned: %d", total, owned))
	end
end

local function setHint(text)
	local label = w('hintLabel')
	if label then
		label:setText(text or "")
	end
end

local function setDesc(text)
	local label = w('descLabel')
	if label then
		label:setText(text or "")
	end
end

local function applyPreviewWidget(preview, entry, hr, bo, le, fe)
	if not preview then
		return
	end
	-- Static preview: an animating creature re-composes its outfit every frame; with a grid
	-- of previews that is real per-frame CPU, so keep them still.
	if preview.setAnimate then preview:setAnimate(false) end
	if preview.setIdleAnimate then preview:setIdleAnimate(false) end
	if entry.kind == 'addons' then
		preview:setOutfit({ type = entry.lookType or 0, addons = entry.addons or 3, mount = 0, head = hr, body = bo, legs = le, feet = fe })
	else
		local clientId = entry.clientId or entry.mountId or 0
		preview:setOutfit({ type = clientId })
		preview:setCenter(true)
		preview:setDrawOffset(mountDrawOffset(clientId))
	end
end

-- ============================================================
-- Details overlay
-- ============================================================
function openDetails(entry)
	if not window then
		return
	end
	local hr, bo, le, fe = baseColors()
	applyPreviewWidget(w('detailsPreview'), entry, hr, bo, le, fe)
	w('detailsName'):setText(entry.name)

	local lines = {}
	lines[#lines + 1] = "How to obtain:"
	local howTo
	if entry.obtainable then
		howTo = (entry.obtain and entry.obtain ~= "") and entry.obtain or "-"
	elseif entry.store then
		howTo = (entry.obtain and entry.obtain ~= "") and entry.obtain or "Available in the Store"
	else
		howTo = (entry.obtain and entry.obtain ~= "") and entry.obtain or "Unknown"
	end
	lines[#lines + 1] = howTo
	if entry.details and entry.details ~= "" and (entry.obtainable or entry.store) then
		lines[#lines + 1] = ""
		lines[#lines + 1] = entry.details
	end
	if entry.owned then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "You already own this."
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Bonuses:"
	local bt = formatBonus(entry.bonus)
	lines[#lines + 1] = bt ~= "" and bt or "No bonus"

	w('detailsText'):setText(table.concat(lines, "\n"))
	local panel = w('detailsPanel')
	panel:setVisible(true)
	panel:raise()
end

function closeDetails()
	local panel = w('detailsPanel')
	if panel then
		panel:setVisible(false)
	end
end

-- ============================================================
-- card rendering (grid)
-- ============================================================
-- Reusable Yes/No confirm modal (corelib displayGeneralBox; it does NOT auto-close, so
-- the callbacks destroy it themselves).
local function confirm(message, onYes)
	local box
	local function close()
		if box then
			box:destroy()
			box = nil
		end
	end
	local function yes()
		close()
		if onYes then
			onYes()
		end
	end
	box = displayGeneralBox(tr('Confirmation'), message, {
		{ text = tr('Yes'), callback = yes },
		{ text = tr('No'), callback = close },
	}, yes, close)
	return box
end

local function buildCard(grid, entry, hr, bo, le, fe)
	local card = g_ui.createWidget('AmCard', grid)
	-- Card children are nested (bonus in bonusScroll, buttons in buttonRow), so use
	-- recursiveGetChildById -- dotted access only resolves DIRECT children in this client.
	applyPreviewWidget(card:recursiveGetChildById('preview'), entry, hr, bo, le, fe)
	card:recursiveGetChildById('name'):setText(entry.name)
	local bt = formatBonus(entry.bonus)
	card:recursiveGetChildById('bonus'):setText(clipBonus(bt ~= "" and bt or "No bonus", 5))
	card:recursiveGetChildById('details').onClick = function()
		openDetails(entry)
	end

	local obtainBtn = card:recursiveGetChildById('obtain')
	local buyBtn = card:recursiveGetChildById('buyBtn')
	local ownedLabel = card:recursiveGetChildById('ownedLabel')
	obtainBtn:setTooltip("")
	buyBtn:hide()
	if entry.owned then
		card:setOpacity(0.55)
		obtainBtn:hide()
		ownedLabel:show()
		return card
	end

	card:setOpacity(1)
	ownedLabel:hide()

	if entry.obtainable and entry.affordable then
		-- items you already have: Obtain (confirmation before consuming)
		obtainBtn:show()
		obtainBtn:setText("Obtain")
		obtainBtn:setColor("#8fdc8f")
		obtainBtn.onClick = function()
			confirm(string.format("Obtain %s?\n\nCost: %s", entry.name, entry.obtain or "-"), function()
				onObtainClick(entry.kind, entry.key)
			end)
		end
	elseif entry.store then
		-- coins: blue button showing the PRICE + coin sprite; buys in-window (server charges
		-- transferable coins + grants), no Store round-trip.
		obtainBtn:hide()
		buyBtn:show()
		buyBtn:recursiveGetChildById('price'):setText(fmtNum(entry.coins or 0))
		buyBtn.onClick = function()
			confirm(string.format("Buy %s for %s coins?", entry.name, fmtNum(entry.coins or 0)), function()
				onBuyClick(entry)
			end)
		end
	else
		obtainBtn:show()
		-- Not obtainable here (missing items, or quest/event/special = unknown). Keep the
		-- Obtain button visible but inactive-looking, with an explanatory tooltip. It stays
		-- ENABLED on purpose: a disabled widget gets no hover/tooltip in this client
		-- (uimanager.cpp clears the hovered widget when it is disabled).
		local tip
		if entry.obtainable then
			tip = "You don't have the required items."
		elseif entry.obtain and entry.obtain ~= "" and entry.obtain ~= "Unknown" then
			tip = entry.obtain
		else
			tip = "Unknown - not obtainable in this window."
		end
		obtainBtn:setText("Obtain")
		obtainBtn:setColor("#8a8a8a")
		obtainBtn:setTooltip(tip)
		obtainBtn.onClick = function()
			setHint(tip)
		end
	end
	return card
end

local function populateGridPage(page)
	local grid = w('contentGrid')
	if not grid then
		return
	end
	grid:destroyChildren()
	local hr, bo, le, fe = baseColors()
	for _, entry in ipairs(page or {}) do
		buildCard(grid, entry, hr, bo, le, fe)
	end
end

-- Paginate: only ever build PAGE_SIZE cards. The engine re-lays out EVERY card in the grid
-- on each scroll frame (O(n)), so a small page is what keeps FPS up at 150-300 entries.
local function renderPage()
	if not window then
		return
	end
	-- Total/Owned counters are over the whole list; the page walks the filtered list.
	local q = (searchText or ""):lower()
	local total, ownedCount = 0, 0
	local filtered = {}
	for _, entry in ipairs(lastEntries or {}) do
		if q == "" or (entry.name and entry.name:lower():find(q, 1, true)) then
			total = total + 1
			if entry.owned then
				ownedCount = ownedCount + 1
			end
			-- "Buyable with coins" == the entries whose button is Buy: store, not owned, and
			-- not already obtainable with items you have.
			local isBuyable = entry.store and not entry.owned and not (entry.obtainable and entry.affordable)
			if not (hideOwned and entry.owned) and (not onlyCoins or isBuyable) then
				filtered[#filtered + 1] = entry
			end
		end
	end
	setStatusCounts(total, ownedCount)

	local totalPages = math.max(1, math.ceil(#filtered / PAGE_SIZE))
	if currentPage > totalPages then
		currentPage = totalPages
	end
	if currentPage < 1 then
		currentPage = 1
	end

	local startI = (currentPage - 1) * PAGE_SIZE + 1
	local endI = math.min(startI + PAGE_SIZE - 1, #filtered)
	local page = {}
	for i = startI, endI do
		page[#page + 1] = filtered[i]
	end
	populateGridPage(page)

	local pageLabel = w('pageLabel')
	if pageLabel then
		pageLabel:setText(string.format("Page %d / %d", currentPage, totalPages))
	end
	local prev = w('prevBtn')
	if prev then
		prev:setEnabled(currentPage > 1)
	end
	local nxt = w('nextBtn')
	if nxt then
		nxt:setEnabled(currentPage < totalPages)
	end
	local sb = w('gridScroll')
	if sb then
		sb:setValue(0)
	end
end

-- ============================================================
-- bonuses (two boxes, totals first + per-item)
-- ============================================================
local function aggregate(entries, kind)
	local t = { skills = {}, damage = {}, defense = {} }
	local function acc(field, v)
		t[field] = (t[field] or 0) + (v or 0)
	end
	for _, e in ipairs(entries or {}) do
		local b = e.bonus
		if b then
			acc('maxHealthPercent', b.maxHealthPercent)
			acc('maxManaPercent', b.maxManaPercent)
			acc('capacity', b.capacity)
			acc('magicLevel', b.magicLevel)
			if kind == 'mounts' then
				t.speed = math.max(t.speed or 0, b.speed or 0) -- highest mount speed wins
			else
				acc('speed', b.speed)
			end
			acc('criticalChance', b.criticalChance)
			acc('criticalDamage', b.criticalDamage)
			acc('lifeLeechChance', b.lifeLeechChance)
			acc('lifeLeechAmount', b.lifeLeechAmount)
			acc('manaLeechChance', b.manaLeechChance)
			acc('manaLeechAmount', b.manaLeechAmount)
			acc('experiencePercent', b.experiencePercent)
			acc('mitigation', b.mitigation)
			if b.skills then
				for k, v in pairs(b.skills) do
					t.skills[k] = (t.skills[k] or 0) + v
				end
			end
			if b.damage then
				for k, v in pairs(b.damage) do
					t.damage[k] = (t.damage[k] or 0) + v
				end
			end
			if b.defense then
				for k, v in pairs(b.defense) do
					t.defense[k] = (t.defense[k] or 0) + v
				end
			end
			if (b.regeneration or 0) ~= 0 then
				acc('regeneration', 1)
			end
			if (b.manaShield or 0) ~= 0 then
				acc('manaShield', 1)
			end
			if (b.invisible or 0) ~= 0 then
				acc('invisible', 1)
			end
		end
	end
	return t
end

local function bonusLine(box, width, text, color)
	local lbl = g_ui.createWidget('AmBonusLine', box)
	lbl:setWidth(width)
	if color then
		lbl:setColor(color)
	end
	lbl:setText(text or "")
	return lbl
end

-- Render one Bonuses box as a list of per-item labels (avoids the single-huge-label
-- text clamp) with the cumulative totals first.
local function fillBonusBox(boxId, headerId, entries, kind)
	local header = w(headerId)
	if header then
		header:setText(kind == 'addons' and 'Addon' or 'Mount')
	end
	local box = w(boxId)
	if not box then
		return
	end
	box:destroyChildren()
	entries = entries or {}
	local width = math.max(80, box:getWidth() - 18)
	local noun = (kind == 'addons') and 'addon' or 'mount'
	bonusLine(box, width, "=== TOTAL BONUSES ===", "#ffe066")
	bonusLine(box, width, string.format("%d %s(s) owned", #entries, noun), "#a0a0a0")
	local totals = formatBonus(aggregate(entries, kind))
	bonusLine(box, width, totals ~= "" and totals or "No bonuses yet.", "#7fbf5f")
	bonusLine(box, width, "--- Per " .. (kind == 'addons' and 'Addon' or 'Mount') .. " ---", "#c0c0c0")
	for _, e in ipairs(entries) do
		local bs = formatBonus(e.bonus, "  ")
		bonusLine(box, width, e.name .. "\n" .. (bs ~= "" and bs or "  No bonus"))
	end
end

-- ============================================================
-- render current view
-- ============================================================
-- Footer coin-balance box (bottom-left) - always shown, every tab.
local function updateBalance()
	if not window then
		return
	end
	local bal = w('balanceLabel')
	if bal then
		bal:setText("Coins: " .. fmtNum(coinBalance or 0))
	end
end

-- Blue 'Buy all: X' bundle button (grid tabs only).
local function updateBuyAll()
	if not window then
		return
	end
	local isGrid = (mainTab == 'addons' or mainTab == 'mounts')
	local bar = w('buyAllBar')
	if bar then
		bar:setVisible(isGrid and (buyAllCount or 0) > 0)
	end
	local txt = w('buyAllText')
	if txt then
		txt:setText(string.format("Buy all: %s", fmtNum(buyAllPrice or 0)))
	end
end

-- Apply a store buy / buy-all response (a categoryPayload) to the current grid view.
local function applyBuyResponse(d, reqKind)
	if not window or mainTab ~= reqKind then
		return
	end
	lastEntries = d.entries
	buyAllPrice = d.buyAllPrice or 0
	buyAllCount = d.buyAllCount or 0
	coinBalance = d.coins or 0
	renderPage()
	updateBuyAll()
	updateBalance()
end

local function renderCatalog()
	setDesc(TAB_DESC[mainTab] or "")
	setHint("")
	local reqKind = mainTab
	CommandBridge.request('addonmount.category', { kind = reqKind, category = 'all' }, function(resp)
		if not resp or resp.type == 'error' then
			setHint(resp and resp.message or "Failed to load.")
			return
		end
		local d = resp.data or {}
		if mainTab == reqKind then
			lastEntries = d.entries
			buyAllPrice = d.buyAllPrice or 0
			buyAllCount = d.buyAllCount or 0
			coinBalance = d.coins or 0
			currentPage = 1
			renderPage()
			updateBuyAll()
			updateBalance()
		end
	end)
end

local function renderBonuses()
	setDesc(BONUS_DESC)
	setHint("")
	CommandBridge.request('addonmount.bonuses', {}, function(resp)
		if not resp or resp.type == 'error' then
			return
		end
		local d = resp.data or {}
		coinBalance = d.coins or coinBalance
		updateBalance()
		if mainTab == 'bonuses' then
			fillBonusBox('bonusAddons', 'bonusAddonsHeader', d.addons, 'addons')
			fillBonusBox('bonusMounts', 'bonusMountsHeader', d.mounts, 'mounts')
		end
	end)
end

local function render()
	if not window then
		return
	end
	if mainTab == 'bonuses' then
		renderBonuses()
	else
		renderCatalog()
	end
end

function onObtainClick(k, key)
	if pendingObtain then
		return
	end
	pendingObtain = true
	setHint("Obtaining...")
	CommandBridge.request('addonmount.obtain', { kind = k, key = key, category = 'all' }, function(resp)
		pendingObtain = false
		if not resp or resp.type == 'error' then
			setHint(resp and resp.message or "Could not obtain.")
			return
		end
		local d = resp.data or {}
		setHint("Obtained: " .. (d.key or key) .. ".")
		if (mainTab == 'addons' or mainTab == 'mounts') and k == d.kind then
			lastEntries = d.entries
			renderPage()
		else
			render()
		end
	end)
end

function onBuyClick(entry)
	if pendingObtain then
		return
	end
	pendingObtain = true
	setHint("Buying...")
	local data = { kind = entry.kind, category = 'all' }
	if entry.kind == 'addons' then
		data.look = entry.lookType
	else
		data.mount = entry.mountId
	end
	CommandBridge.request('addonmount.buy', data, function(resp)
		pendingObtain = false
		if not resp or resp.type == 'error' then
			setHint(resp and resp.message or "Could not buy.")
			return
		end
		setHint("Purchased: " .. entry.name .. ".")
		applyBuyResponse(resp.data or {}, entry.kind)
	end)
end

-- Buy every missing store outfit/mount for the current tab at the combo discount. price is
-- the amount shown to the player; the server refuses to charge more than that.
function buyAll()
	if pendingObtain or (buyAllCount or 0) <= 0 then
		return
	end
	local kind = mainTab
	if kind ~= 'addons' and kind ~= 'mounts' then
		return
	end
	local noun = (kind == 'addons') and 'outfits' or 'mounts'
	local count = buyAllCount
	confirm(string.format("Unlock all %d missing %s for %s coins?", buyAllCount, noun, fmtNum(buyAllPrice)), function()
		pendingObtain = true
		setHint("Buying...")
		CommandBridge.request('addonmount.buyall', { kind = kind, price = buyAllPrice, category = 'all' }, function(resp)
			pendingObtain = false
			if not resp or resp.type == 'error' then
				setHint(resp and resp.message or "Could not buy.")
				return
			end
			setHint(string.format("Unlocked %d %s.", count, noun))
			applyBuyResponse(resp.data or {}, kind)
		end)
	end)
end

-- ============================================================
-- tab / options state
-- ============================================================
local function applyStates()
	if not window then
		return
	end
	closeDetails()
	w('tabAddons'):setOn(mainTab == 'addons')
	w('tabMounts'):setOn(mainTab == 'mounts')
	w('tabBonuses'):setOn(mainTab == 'bonuses')

	local isGrid = (mainTab == 'addons' or mainTab == 'mounts')
	local isBonuses = mainTab == 'bonuses'
	w('contentGrid'):setVisible(isGrid)
	w('gridScroll'):setVisible(isGrid)
	w('optionsBar'):setVisible(isGrid)
	w('bonusAddonsHeader'):setVisible(isBonuses)
	w('bonusAddons'):setVisible(isBonuses)
	w('bonusAddonsScroll'):setVisible(isBonuses)
	w('bonusMountsHeader'):setVisible(isBonuses)
	w('bonusMounts'):setVisible(isBonuses)
	w('bonusMountsScroll'):setVisible(isBonuses)
	local searchBox = w('searchInput')
	if searchBox then
		searchBox:setVisible(isGrid)
	end
	-- updateBuyAll re-shows the bar for grid tabs once the payload arrives; hide it here so it
	-- never lingers on the Bonuses tab or before the data loads.
	local bar = w('buyAllBar')
	if bar then
		bar:setVisible(false)
	end
end

function setMainTab(tab)
	mainTab = tab
	applyStates()
	render()
end

function setHideOwned(v)
	hideOwned = v and true or false
	currentPage = 1
	if (mainTab == 'addons' or mainTab == 'mounts') and lastEntries then
		renderPage()
	end
end

function setOnlyCoins(v)
	onlyCoins = v and true or false
	currentPage = 1
	if (mainTab == 'addons' or mainTab == 'mounts') and lastEntries then
		renderPage()
	end
end

function setSearch(text)
	searchText = text or ""
	currentPage = 1
	if (mainTab == 'addons' or mainTab == 'mounts') and lastEntries then
		renderPage()
	end
end

function prevPage()
	if currentPage > 1 then
		currentPage = currentPage - 1
		renderPage()
	end
end

function nextPage()
	currentPage = currentPage + 1
	renderPage()
end

-- ============================================================
-- show / hide / lifecycle
-- ============================================================
-- Re-fetch after a Store purchase so a just-bought outfit/mount flips to Owned. Small
-- delay so the server-side grant is committed before we re-query ownership.
local function refreshOnPurchase()
	if window and window:isVisible() then
		scheduleEvent(function()
			if window and window:isVisible() then
				render()
			end
		end, 500)
	end
end

function show()
	if not window then
		return
	end
	window:show()
	window:raise()
	window:focus()
	render()
end

function hide()
	if window and window:isVisible() then
		window:hide()
	end
end

function toggle()
	if not g_game.isOnline() or not window then
		return
	end
	if window:isVisible() then
		hide()
	else
		show()
	end
end

function onGameStart()
	if window then
		window:destroy()
		window = nil
	end
	g_ui.importStyle(resolvepath('styles'))
	window = g_ui.displayUI(resolvepath('addonmount'))
	window:hide()
	g_keyboard.bindKeyDown('Escape', function()
		hide()
	end, window)

	mainTab = 'addons'
	hideOwned = false
	onlyCoins = false
	searchText = ""
	local check = w('showOwnedCheck')
	if check then
		check:setChecked(false)
		check.onCheckChange = function(_, checked)
			setHideOwned(checked)
		end
	end
	local coinsCheck = w('onlyCoinsCheck')
	if coinsCheck then
		coinsCheck:setChecked(false)
		coinsCheck.onCheckChange = function(_, checked)
			setOnlyCoins(checked)
		end
	end
	local search = w('searchInput')
	if search then
		search:setText("")
		search.onTextChange = function(widget, text)
			setSearch(text)
		end
	end
	applyStates()
end

function onGameEnd()
	lastEntries = nil
	if window then
		window:destroy()
		window = nil
	end
end

function init()
	connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onStorePurchase = refreshOnPurchase })
	if g_game.isOnline() then
		onGameStart()
	end
end

function terminate()
	disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onStorePurchase = refreshOnPurchase })
	if window then
		if not window:isDestroyed() then
			g_keyboard.unbindKeyDown('Escape', window)
		end
		window:destroy()
		window = nil
	end
end
