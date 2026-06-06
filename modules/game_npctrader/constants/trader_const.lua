-- LuaFormatter off

-- ==============================================================================================
-- TRADE MODE CONSTANTS
-- ==============================================================================================
controllerNpcTrader.BUY = 1
controllerNpcTrader.SELL = 2

-- ==============================================================================================
-- UI LAYOUT CONSTANTS
-- ==============================================================================================
controllerNpcTrader.DEFAULT_CONSOLE_WIDTH = 470
controllerNpcTrader.TRADE_CONSOLE_WIDTH = 775

-- ==============================================================================================
-- VIRTUAL SCROLLING CONSTANTS
-- ==============================================================================================
controllerNpcTrader.ITEM_BATCH_SIZE = 30
controllerNpcTrader.ITEM_ROW_HEIGHT = 48
controllerNpcTrader.SCROLL_THRESHOLD = 50

-- ==============================================================================================
-- DEFAULT CURRENCY
-- ==============================================================================================
controllerNpcTrader.DEFAULT_CURRENCY_ID = 3031
controllerNpcTrader.DEFAULT_CURRENCY_NAME = "Gold Coin"

-- ==============================================================================================
-- DEFAULT SETTINGS
-- ==============================================================================================
controllerNpcTrader.DEFAULT_SORT_BY = 'name'
controllerNpcTrader.DEFAULT_IGNORE_CAPACITY = false
controllerNpcTrader.DEFAULT_BUY_WITH_BACKPACK = false
controllerNpcTrader.DEFAULT_IGNORE_EQUIPPED = true
controllerNpcTrader.DEFAULT_SHOW_SEARCH_FIELD = true
controllerNpcTrader.DEFAULT_NO_LARGE_AMOUNT_WARNING = false

-- ==============================================================================================
-- ITEM DISPLAY LIMITS
-- ==============================================================================================
controllerNpcTrader.MAX_ITEM_NAME_LENGTH = 18
controllerNpcTrader.MAX_ITEM_INFO_LENGTH = 22

-- ==============================================================================================
-- AMOUNT LIMITS
-- ==============================================================================================
controllerNpcTrader.MIN_AMOUNT = 1
-- Limite global do controle de quantidade (input + scrollbar) no UI do trade.
-- Mantido separado de MAX_AMOUNT_* pois BUY/SELL ainda calculam limites dinâmicos (dinheiro/estoque),
-- mas nunca devem ultrapassar esse teto na interface.
controllerNpcTrader.MAX_AMOUNT_UI = 50
controllerNpcTrader.MAX_AMOUNT_NORMAL = 100
controllerNpcTrader.MAX_AMOUNT_STACKABLE = 10000

-- ==============================================================================================
-- KEYWORD BUTTON ICONS
-- ==============================================================================================

KeywordButtonIcon = {
    KEYWORDBUTTONICON_GENERALTRADE   = 0,
    KEYWORDBUTTONICON_POTIONTRADE    = 1,
    KEYWORDBUTTONICON_EQUIPMENTTRADE = 2,
    KEYWORDBUTTONICON_SAIL           = 3,
    KEYWORDBUTTONICON_DEPOSITALL     = 4,
    KEYWORDBUTTONICON_WITHDRAW       = 5,
    KEYWORDBUTTONICON_BALANCE        = 6,
    KEYWORDBUTTONICON_YES            = 7,
    KEYWORDBUTTONICON_NO             = 8,
    KEYWORDBUTTONICON_BYE            = 9,
}

IconSpriteIndex = {
    [KeywordButtonIcon.KEYWORDBUTTONICON_GENERALTRADE]   = 1,
    [KeywordButtonIcon.KEYWORDBUTTONICON_POTIONTRADE]    = 2,
    [KeywordButtonIcon.KEYWORDBUTTONICON_EQUIPMENTTRADE] = 3,
    [KeywordButtonIcon.KEYWORDBUTTONICON_SAIL]           = 0,
    [KeywordButtonIcon.KEYWORDBUTTONICON_DEPOSITALL]     = 5,
    [KeywordButtonIcon.KEYWORDBUTTONICON_WITHDRAW]       = 6,
    [KeywordButtonIcon.KEYWORDBUTTONICON_BALANCE]        = 4,
    [KeywordButtonIcon.KEYWORDBUTTONICON_YES]            = 7,
    [KeywordButtonIcon.KEYWORDBUTTONICON_NO]             = 8,
    [KeywordButtonIcon.KEYWORDBUTTONICON_BYE]            = 9,
}

controllerNpcTrader.buttonsDefault = {
    [1] = { id = KeywordButtonIcon.KEYWORDBUTTONICON_YES, text = "yes" },
    [2] = { id = KeywordButtonIcon.KEYWORDBUTTONICON_NO, text = "no" },
    [3] = { id = KeywordButtonIcon.KEYWORDBUTTONICON_BYE, text = "bye" },
}

-- Maps NPC message keywords to the button that should be added.
-- When the NPC mentions a keyword inside {braces}, the matching button appears.
controllerNpcTrader.keywordButtonMap = {
    ["trade"]       = { id = KeywordButtonIcon.KEYWORDBUTTONICON_GENERALTRADE,   text = "trade" },
    ["offers"]      = { id = KeywordButtonIcon.KEYWORDBUTTONICON_GENERALTRADE,   text = "trade" },
    ["potions"]     = { id = KeywordButtonIcon.KEYWORDBUTTONICON_POTIONTRADE,    text = "potions" },
    ["equipment"]   = { id = KeywordButtonIcon.KEYWORDBUTTONICON_EQUIPMENTTRADE, text = "equipment" },
    ["sail"]        = { id = KeywordButtonIcon.KEYWORDBUTTONICON_SAIL,           text = "sail" },
    ["passage"]     = { id = KeywordButtonIcon.KEYWORDBUTTONICON_SAIL,           text = "sail" },
    ["deposit all"] = { id = KeywordButtonIcon.KEYWORDBUTTONICON_DEPOSITALL,     text = "deposit all" },
    ["deposit"]     = { id = KeywordButtonIcon.KEYWORDBUTTONICON_DEPOSITALL,     text = "deposit all" },
    ["withdraw"]    = { id = KeywordButtonIcon.KEYWORDBUTTONICON_WITHDRAW,       text = "withdraw" },
    ["balance"]     = { id = KeywordButtonIcon.KEYWORDBUTTONICON_BALANCE,        text = "balance" },
    ["bank"]        = { id = KeywordButtonIcon.KEYWORDBUTTONICON_BALANCE,        text = "balance" },
}

-- ==============================================================================================
-- NPC NAME → EXTRA BUTTONS (pre-defined by NPC name from server scripts)
-- Buttons are added on top of buttonsDefault when the NPC is identified.
-- ==============================================================================================

local B = KeywordButtonIcon

local BANK_BUTTONS = {
    { id = B.KEYWORDBUTTONICON_DEPOSITALL, text = "deposit all" },
    { id = B.KEYWORDBUTTONICON_WITHDRAW,   text = "withdraw" },
    { id = B.KEYWORDBUTTONICON_BALANCE,    text = "balance" },
}

--- Banco + correio: vende cartas/encomendas (say trade), além de operações de conta.
local BANK_AND_MAIL_BUTTONS = {
    { id = B.KEYWORDBUTTONICON_DEPOSITALL,     text = "deposit all" },
    { id = B.KEYWORDBUTTONICON_WITHDRAW,       text = "withdraw" },
    { id = B.KEYWORDBUTTONICON_BALANCE,        text = "balance" },
    { id = B.KEYWORDBUTTONICON_GENERALTRADE,   text = "trade" },
}

local BOAT_BUTTONS = {
    { id = B.KEYWORDBUTTONICON_SAIL, text = "sail" },
}

local TRADE_BUTTONS = {
    { id = B.KEYWORDBUTTONICON_GENERALTRADE, text = "trade" },
}

controllerNpcTrader.npcButtonPresets = {}

local function registerNpcPreset(names, extraButtons)
    for _, name in ipairs(names) do
        controllerNpcTrader.npcButtonPresets[name:lower()] = extraButtons
    end
end

registerNpcPreset({
    "Naji", "Kepar", "Gnomillion",
}, BANK_BUTTONS)

registerNpcPreset({
    "Bank And Mail",
}, BANK_AND_MAIL_BUTTONS)

registerNpcPreset({
    "Captain Guth", "Captain Charlin", "Captain Assun",
}, BOAT_BUTTONS)

registerNpcPreset({
    "Hireling",
}, {
    { id = B.KEYWORDBUTTONICON_DEPOSITALL, text = "deposit all" },
    { id = B.KEYWORDBUTTONICON_WITHDRAW,   text = "withdraw" },
    { id = B.KEYWORDBUTTONICON_BALANCE,    text = "balance" },
    { id = B.KEYWORDBUTTONICON_GENERALTRADE, text = "trade" },
})

registerNpcPreset({
    -- Custom / OTServBR
    "Compra Vende Tudo", "Loot Buyer", "Vip Trader", "Hunt Refiller",
    "Training Seller", "Castle King", "Battlefield Champion",
    "Special Itens Seller", "Sugar Daddy Buyer",
    "Gold Token Trader", "Silver Token Trader", "Stones Trader",
    "Itens Addon", "Itens Soulwar", "Itens Sanguine",
    "Itens Upgrader", "Itens Primal", "Soulwar Trader",
    "Forge Trader", "Imbuement Assistant", "Imbui Vip Assistant",
    "Drome Seller", "Skarvul Seller", "Lunar Relic Trader",
    "Santa Seller", "Papai Noel", "Messenger of Santa",
    "Crafter", "Loot Pouch Trader",
    -- Tibia NPCs
    "Xodet", "Gnomegica", "Asima", "Azil", "Baltim", "Cledwyn",
    "Dorbin", "Flint", "Gnomission", "Habdel", "Yasir",
    "Zuma Magehide", "Arkulius", "Benjamin", "Canary",
    "Cuisinier", "Dark Chocolate", "Milk Chocolate",
    "Edoch", "Enpa-Deia Pema", "Gnomailion", "Gnomally",
    "Gnomejam", "Gnomerrow", "Gnomette", "Gnomfurry",
    "Gnomincia", "Gnomux", "Halif", "Julius", "Majin", "Maun",
    "Mugluf", "Perod", "Yana", "Yulas", "Zethra",
    "Ash Ketchum",
    -- Ferreiro (nome exato do NPC no servidor)
    "Blacksmith", "Blacksmith Vip",
}, TRADE_BUTTONS)

-- ==============================================================================================
-- NPC TRADE — tooltip ajuda (poções/runas/boost)
-- ==============================================================================================
--- Atraso antes de mostrar o painel (ms), para evitar flicker ao mover o mouse na lista.
controllerNpcTrader.NPC_TRADE_TOOLTIP_HOVER_DELAY = 380

-- LuaFormatter on

function controllerNpcTrader.formatNumber(value)
    value = tonumber(value) or 0
    if value >= 1000000000000 then
        return string.format("%.1ft", value / 1000000000000)
    elseif value >= 1000000000 then
        return string.format("%.1fb", value / 1000000000)
    end
    local formatted = tostring(math.floor(value))
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
        if k == 0 then break end
    end
    return formatted
end

function controllerNpcTrader:getIconClip(id)
    local index = IconSpriteIndex[id] or 0
    local x = index * 32
    return x .. " 0 32 32"
end

function controllerNpcTrader:getItemInfoText(item)
    local price = item.priceText
    if not price or price == "" then
        price = controllerNpcTrader.formatNumber(item.price)
    end
    if self.tradeMode == controllerNpcTrader.SELL then
        return self:shortText("Price " .. price, 28)
    end
    return self:shortText("Price " .. price .. ", " .. item.weight .. " oz", 28)
end

function controllerNpcTrader:shortText(text, chars_limit)
    if not text then return "" end
    if #text > chars_limit then
        return text:sub(1, chars_limit) .. "..."
    end
    return text
end

function controllerNpcTrader:getTotalPriceText()
    return controllerNpcTrader.formatNumber(self.totalPrice or 0)
end

function controllerNpcTrader:getPlayerGoldText()
    local player = g_game.getLocalPlayer()
    if not player then return "0" end
    return controllerNpcTrader.formatNumber(player:getTotalMoney())
end

function controllerNpcTrader:hasCustomCurrency()
    local cid = self.currencyId or controllerNpcTrader.currencyId or controllerNpcTrader.DEFAULT_CURRENCY_ID
    return cid ~= controllerNpcTrader.DEFAULT_CURRENCY_ID
end

function controllerNpcTrader:getPlayerCurrencyText()
    local player = g_game.getLocalPlayer()
    if not player then return "0" end
    return controllerNpcTrader.formatNumber(player:getResourceBalance(ResourceTypes.CURRENCY_CUSTOM_EQUIPPED))
end

function controllerNpcTrader:getPlayerMoneyText()
    return controllerNpcTrader.formatNumber(self.playerMoney or 0)
end
