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
            controllerNpcTrader.playerMoney = money or controllerNpcTrader:getPlayerMoney()
            controllerNpcTrader:refreshPlayerGoods()
        end,
        onCloseNpcTrade = function()
            self:onCloseNpcTrade()
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
    self:onCloseNpcTrade()
end

function controllerNpcTrader:onGameEnd()
    if saveData then
        saveData()
    end
    if modules.game_npctrade and modules.game_npctrade.NpcTradeTooltip then
        modules.game_npctrade.NpcTradeTooltip.onGameEnd()
        modules.game_npctrade.NpcTradeTooltip.terminate()
    end
    self:onCloseNpcTrade()
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

function controllerNpcTrader:onCloseNpcTrade(skipByeMessage)
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
    controllerNpcTrader.selectedItem = nil
    controllerNpcTrader.tradeItems = {}
    controllerNpcTrader.currentList = {}
    controllerNpcTrader.allTradeItems = {}
    controllerNpcTrader.buttons = nil
    controllerNpcTrader._detectedButtonIds = nil
    controllerNpcTrader._updatingAmount = false
    controllerNpcTrader._closedAt = g_clock.millis()

    if wasTrading then
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
