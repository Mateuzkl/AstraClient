controllerNpcTrader = Controller:new()
controllerNpcTrader.creatureName = ""
controllerNpcTrader.outfit = nil
controllerNpcTrader.buttons = nil
controllerNpcTrader.isTradeOpen = false
controllerNpcTrader._closedAt = 0

--- true = janela HTML (diálogo + trade integrado); false = consola + janela compacta legacy.
--- Controlado em Opções → Interface → consola: "Display new NPC Dialog Window".
function controllerNpcTrader:useNewNpcDialog()
    return controllerNpcTrader.forceLegacyMode ~= true
end

function controllerNpcTrader:onInit()
    self.widthConsole = self.DEFAULT_CONSOLE_WIDTH
    self.isTradeOpen = self.isTradeOpen or false
    self.tradeItems = self.tradeItems or {}
    self.selectedItem = self.selectedItem or nil
    self.amount = self.amount or 1
    self.totalPrice = self.totalPrice or 0
    self.totalWeight = self.totalWeight or "0.00"
end

function controllerNpcTrader:onGameStart()
    if loadData then
        loadData()
    end
    if modules.game_npctrade and modules.game_npctrade.NpcTradeTooltip then
        modules.game_npctrade.NpcTradeTooltip.init()
    end
    self:registerEvents(g_game, {
        onOpenNpcTrade = function(...)
            onOpenNpcTrade(...)
        end,
        onPlayerGoods = function(money, items)
            if not controllerNpcTrader:useNewNpcDialog() then
                controllerNpcTrader:onPlayerGoodsLegacy(money, items)
                return
            end
            local playerItemsMap = {}
            if items then
                for _, item in pairs(items) do
                    local id = item[1]:getId()
                    if not playerItemsMap[id] then
                        playerItemsMap[id] = item[2]
                    else
                        playerItemsMap[id] = playerItemsMap[id] + item[2]
                    end
                end
            end
            controllerNpcTrader.playerItems = playerItemsMap
            if money ~= nil then
                controllerNpcTrader.playerMoney = money
            else
                controllerNpcTrader.playerMoney = nil
                controllerNpcTrader.playerMoney = controllerNpcTrader:getPlayerMoney()
            end
            controllerNpcTrader:refreshPlayerGoods(true)
        end,
        onCloseNpcTrade = function()
            self:onCloseNpcTrade(true, true)
        end,
        onTalk = onNpcTalk
    })
end

function controllerNpcTrader:onTerminate()
    if saveData then
        saveData()
    end
    if modules.game_npctrade and modules.game_npctrade.NpcTradeTooltip then
        modules.game_npctrade.NpcTradeTooltip.terminate()
    end
    if self.legacy_terminate then
        self:legacy_terminate()
    end
    self:onCloseNpcTrade(true, true)
end

function controllerNpcTrader:onGameEnd()
    if saveData then
        saveData()
    end
    if modules.game_npctrade and modules.game_npctrade.NpcTradeTooltip then
        modules.game_npctrade.NpcTradeTooltip.onGameEnd()
        modules.game_npctrade.NpcTradeTooltip.terminate()
    end
    self:onCloseNpcTrade(true, true)
end

-- Coleta todos os widgets com id 'windowTrader' sob root (evita janelas órfãs duplicadas).
local function collectWindowTraderWidgets(root, out)
    if not root or root:isDestroyed() then return end
    if root:getId() == "windowTrader" then
        out[#out + 1] = root
        return
    end
    for _, child in ipairs(root:getChildren()) do
        collectWindowTraderWidgets(child, out)
    end
end

function controllerNpcTrader:onCloseNpcTrade(skipByeMessage, skipClosePacket)
    if controllerNpcTrader.releaseNpcTextInput then
        controllerNpcTrader:releaseNpcTextInput()
    end

    if not skipByeMessage and modules.game_console and g_game.getLocalPlayer() and controllerNpcTrader.creatureName and controllerNpcTrader.creatureName ~= "" then
        if controllerNpcTrader.sendNpcConsoleMessage then
            controllerNpcTrader:sendNpcConsoleMessage("bye")
        end
    end

    controllerNpcTrader._initNpcWindowInProgress = false
    controllerNpcTrader._pendingOpen = nil
    controllerNpcTrader._openScheduled = false
    local wasTrading = controllerNpcTrader.isTradeOpen

    controllerNpcTrader.isTradeOpen = false
    controllerNpcTrader.buyItems = {}
    controllerNpcTrader.sellItems = {}
    controllerNpcTrader.playerItems = {}
    controllerNpcTrader.playerMoney = nil
    controllerNpcTrader.selectedItem = nil
    controllerNpcTrader.tradeItems = {}
    controllerNpcTrader.currentList = {}
    controllerNpcTrader.allTradeItems = {}
    controllerNpcTrader.amount = 1
    controllerNpcTrader.totalPrice = 0
    controllerNpcTrader.totalWeight = "0.00"
    controllerNpcTrader.buttons = nil
    controllerNpcTrader._detectedButtonIds = nil
    controllerNpcTrader._updatingAmount = false
    controllerNpcTrader._closedAt = g_clock.millis()

    local isOnline = g_game and (not g_game.isOnline or g_game.isOnline())
    if wasTrading and not skipClosePacket and isOnline then
        g_game.closeNpcTrade()
    end

    if controllerNpcTrader.legacyWindow and not controllerNpcTrader.legacyWindow:isDestroyed() then
        controllerNpcTrader:legacy_hide()
        if controllerNpcTrader.legacy_onNpcTradeUiClosed then
            controllerNpcTrader:legacy_onNpcTradeUiClosed()
        end
    end

    -- Destrói a UI atual pelo controller (unloadHtml)
    if controllerNpcTrader.ui and not controllerNpcTrader.ui:isDestroyed() then
        pcall(function() controllerNpcTrader:unloadHtml() end)
    end

    -- Destrói qualquer janela órfã (duplicata) com id windowTrader que tenha ficado na árvore
    local root = g_ui.getRootWidget()
    if root then
        local toDestroy = {}
        collectWindowTraderWidgets(root, toDestroy)
        for _, w in ipairs(toDestroy) do
            if not w:isDestroyed() then
                w:destroy()
            end
        end
        controllerNpcTrader.ui = nil
        controllerNpcTrader.htmlId = nil
        if controllerNpcTrader.syncPublicWidgets then
            controllerNpcTrader:syncPublicWidgets()
        end
    end
end
