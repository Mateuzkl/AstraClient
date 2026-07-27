realCreatureBtnTestSuiteWindow = nil
realCreatureBtnTestSuiteWindowTopButton = nil

function init()
    realCreatureBtnTestSuiteWindow = g_ui.displayUI('realcreaturebutton')

    realCreatureBtnTestSuiteWindowTopButton = modules.client_topmenu.addRightGameToggleButton('realCreatureBtnTestSuiteWindowTopButton',
        tr('Real Creature Button') .. ' (Ctrl+M)', '/images/topbuttons/minimap', toggle)
    realCreatureBtnTestSuiteWindowTopButton:setOn(true)

    local gameRootPanel = m_interface.getRootPanel()

    local cButton = realCreatureBtnTestSuiteWindow:recursiveGetChildById("creatureButton")
    cButton:setCreature(nil)
    cButton:setText("None")
    cButton:setHealthPercent(50)

    cButton.onHoverChange = function(self, hovered)
        self:toggleSelectionBoxHover(hovered)
    end
    cButton.onClick = function(self)
        self.clicked = not self.clicked
        if self.clicked then
            self:setSelectionBoxState(CREATURE_BUTTON_SELECTION_TYPES.TARGETING + CREATURE_BUTTON_SELECTION_TYPES.HEALING)
        else
            self:setSelectionBoxState(0)
        end
    end
    cButton.onMousePress = function(self, mousePos, button)
        if button == MouseRightButton then
            print("Activate Attack!!!")
            self:attack()
        end
    end

    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
    })

    connect(LocalPlayer, {
        onHealthChange = updateHealth
    })

    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
    })

    disconnect(LocalPlayer, {
        onHealthChange = updateHealth
    })

    if realCreatureBtnTestSuiteWindowTopButton then
        realCreatureBtnTestSuiteWindowTopButton:destroy()
        realCreatureBtnTestSuiteWindowTopButton = nil
    end

    if realCreatureBtnTestSuiteWindow then
        realCreatureBtnTestSuiteWindow:destroy()
        realCreatureBtnTestSuiteWindow = nil
    end
end

function online()
    local benchmark = g_clock.millis()
    local cButton = realCreatureBtnTestSuiteWindow:recursiveGetChildById("creatureButton")
    local player = g_game.getLocalPlayer()
    cButton:setCreature(player)
    cButton:setText(player:getName())
    cButton:setHealthPercent(player:getHealthPercent())
    cButton:setManaPercent(30)
    cButton:toggleManaBar(true)

    local icons = {
        '/images/game/skulls/skull_yellow',
        '/images/game/skulls/skull_green',
        --'/images/game/skulls/skull_white',
        --'/images/game/skulls/skull_red',
        --'/images/game/skulls/skull_black',
        --'/images/game/skulls/skull_orange',
    }

    for _, iconPath in ipairs(icons) do
        cButton:addIcon(iconPath)
    end

    consoleln("Real Creature Button loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
    local cButton = realCreatureBtnTestSuiteWindow:recursiveGetChildById("creatureButton")
    cButton:setCreature(nil)
    cButton:setText("None")
    cButton:setHealthPercent(50)
end

function onClose()
    realCreatureBtnTestSuiteWindow:hide()
end

function updateHealth(localPlayer, health, maxHealth)
    local cButton = realCreatureBtnTestSuiteWindow:recursiveGetChildById("creatureButton")
    cButton:setHealthPercent((health / maxHealth) * 100)
end
