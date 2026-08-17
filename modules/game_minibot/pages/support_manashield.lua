support_manashieldModule = {}

local supportManaShieldWindow = nil

function support_manashieldModule.getItemShieldEnabledTooltip(language)
    if language == 'ptbr' then
        return 'Se o Mana Shield nao puder ser lancado e esta opcao estiver marcada, o sistema tentara usar a Magic Shield Potion.'
    end
    return 'If Magic Shield Spell cannot be casted and this option is checked, the system will try to use the Magic Shield Potion instead.'
end

function support_manashieldModule.init(widget)
    supportManaShieldWindow = widget

    support_manashieldModule.loadSettings()

    supportManaShieldWindow.panel.manaShieldOn:loadGif('/images/game_minibot/resources/gifs/manashield_minibot', 15, 100, { width = 80, height = 80 }, false)

    local player = g_game.getLocalPlayer()
    if player ~= nil then
        local outfit = player:getOutfit()
        outfit.category = ThingCategoryCreature
        outfit.mount = 0
        supportManaShieldWindow.panel.creatureBackground.creature:setOutfit(outfit)
    end
end

function support_manashieldModule.terminate()
    supportManaShieldWindow = nil
end

function support_manashieldModule.reloadLanguage(language)
    if language == 'ptbr' then
        supportManaShieldWindow.panel.description:setText('Com o Mana Shield Automatico, o Assistente sera ativado automaticamente quando todos os requisitos forem atendidos, para salvar seu personagem da morte certa.')
        supportManaShieldWindow.panel.list.spellShield.enabled:setText('Usar spell')
        supportManaShieldWindow.panel.list.spellShield.enabledHelp:setTooltip('Se o Mana Shield nao puder ser lancado e esta opcao estiver marcada, o sistema tentara usar a Magic Shield Potion.')
        supportManaShieldWindow.panel.list.spellShield.potion:setText('Usar a potion se CD')
        supportManaShieldWindow.panel.list.spellShield.recast.check:setText('Renovar shield')
        supportManaShieldWindow.panel.list.spellShield.recast.checkHelp:setTooltip('Se esta opcao estiver habilitada, o Assistente renovara o Mana Shield se ele ficar abaixo da porcentagem de shield selecionada.')
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:setText('Forcar uso se monstros >=')
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyHelp:setTooltip('Quando uma certa quantidade de monstros estiver na sua tela, o Assistente ativara automaticamente o Mana Shield para evitar surpresas durante a caca.')
        supportManaShieldWindow.panel.list.itemShield.enabled:setText('Usar item')
        supportManaShieldWindow.panel.list.itemShield.enabledHelp:setTooltip(
            support_manashieldModule.getItemShieldEnabledTooltip(language))
        supportManaShieldWindow.panel.list.itemShield.fear:setText('Usar no Fear')
        supportManaShieldWindow.panel.list.itemShield.recast.check:setText('Renovar shield')
        supportManaShieldWindow.panel.list.itemShield.recast.checkHelp:setTooltip('Se esta opcao estiver habilitada, o Assistente renovara o Mana Shield se ele ficar abaixo da porcentagem de shield selecionada.')
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:setText('Forcar uso se monstros >=')
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyHelp:setTooltip('Quando uma certa quantidade de monstros estiver na sua tela, o Assistente ativara automaticamente o Mana Shield para evitar surpresas durante a caca.')
        supportManaShieldWindow.panel.list.removeShield.enabled:setText('Remover')
        supportManaShieldWindow.panel.list.removeShield.enabledHelp:setTooltip('Se habilitado, o sistema removera automaticamente o Mana Shield quando todos os requisitos forem atendidos.')
        supportManaShieldWindow.panel.list.removeShield.fear:setText('Ignorar se Fear')

        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:setText('Ignorar ate')
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.checkHelp:setTooltip('Voc pode selecionar uma quantidade maxima de criaturas para que o sistema possa manter o Mana Shield ate que a batalha esteja a seu favor.')
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setText('Monstros <=')

    elseif language == 'enus' then
        supportManaShieldWindow.panel.description:setText('With Auto Mana Shield the Assistant will automatically triggers when all requiremen met, to save your characters from fatal damages.')
        supportManaShieldWindow.panel.list.spellShield.enabled:setText('Use spell')
        supportManaShieldWindow.panel.list.spellShield.enabledHelp:setTooltip('If Magic Shield Spell cannot be casted and this option is checked, the system will try to use the Magic Shield Potion instead.')
        supportManaShieldWindow.panel.list.spellShield.potion:setText('Use Potion when CD')
        supportManaShieldWindow.panel.list.spellShield.recast.check:setText('Renew shield')
        supportManaShieldWindow.panel.list.spellShield.recast.checkHelp:setTooltip('If this option is enabled, the Assistant will renew the Mana Shield if it reachs below the selected shield percentage.')
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:setText('Force use when monsters >=')
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyHelp:setTooltip('When a certain amount of monsters is on your screen, the Assistant will automatically trigger Mana Shield to prevent any surprises when hunting.')
        supportManaShieldWindow.panel.list.itemShield.enabled:setText('Use item')
        supportManaShieldWindow.panel.list.itemShield.enabledHelp:setTooltip(
            support_manashieldModule.getItemShieldEnabledTooltip(language))
        supportManaShieldWindow.panel.list.itemShield.fear:setText('Use when Fear')
        supportManaShieldWindow.panel.list.itemShield.recast.check:setText('Renew shield')
        supportManaShieldWindow.panel.list.itemShield.recast.checkHelp:setTooltip('If this option is enabled, the Assistant will renew the Mana Shield if it reachs below the selected shield percentage.')
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:setText('Force use when monsters >=')
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyHelp:setTooltip('When a certain amount of monsters is on your screen, the Assistant will automatically trigger Mana Shield to prevent any surprises when hunting.')
        supportManaShieldWindow.panel.list.removeShield.enabled:setText('Auto remove')
        supportManaShieldWindow.panel.list.removeShield.enabledHelp:setTooltip('If enabled, the system will automatically remove Mana Shield when the all the requirements met.')
        supportManaShieldWindow.panel.list.removeShield.fear:setText('Ignore when Fear')

        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:setText('Ignore until')
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.checkHelp:setTooltip('You can select a maximum amount of creatures so the system can hold the Mana Shield until battle is at your favor.')
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setText('Monsters <=')

    end
end

function support_manashieldModule.reloadInternalModule()
    if support_manashieldModule.ignoreQuerySaveSettings then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['support_manashield'] or {}

    -- Spell Shield
    local spellShieldSettings = sList['spell_shield'] or {}
    g_minibot.resetModule(13) -- Spell Mana Shield Module type
    g_minibot.setModuleToggle(13, spellShieldSettings['enabled']) -- Spell Mana Shield Module type
    if spellShieldSettings['enabled'] then
        local internal = {
            spell = '',
            spellGroup = {},
            reqmana = 0,
            max = spellShieldSettings['health'] or 0,
            item = 0,
            manaMin = 0, -- recast_value
            hits = 0, -- creatures_value

            use = false,
            health = 0,
            mana = 0,
            min = 0,
            manaMax = 0,
            harmony = 0,
            lastCall = 0,
            enabled = true,
            ignorePz = false,
            area = '',
            target = '',
            itemGroup = {},
            spellId = {},
        }

        if spellShieldSettings['use_potion'] then
            internal.item = 35563
        end

        if spellShieldSettings['recast_enabled'] then
            internal.manaMin = spellShieldSettings['recast_value'] or 0
        end

        if spellShieldSettings['creatures_enabled'] then
            internal.hits = spellShieldSettings['creatures_value'] or 0
        end

        local spell = g_spells.getSpellInfoById(44) -- utamo vita (Magic Shield)
        local canCastSpell = spell ~= nil and
            (modules.game_actionbar == nil or type(modules.game_actionbar.canSpellCast) ~= 'function' or
             modules.game_actionbar.canSpellCast(spell))
        if canCastSpell then
            internal.spell = spell.words
            internal.reqmana = spell.mana
            table.insert(internal.spellId, spell.id)
            for _, group in ipairs(spell.groups) do
                table.insert(internal.spellGroup, group)
            end
        end

        g_minibot.addModule(13, internal) -- Spell Mana Shield Module type
    end

    -- Item Shield
    local itemShieldSettings = sList['item_shield'] or {}
    g_minibot.resetModule(14) -- Item Mana Shield Module type
    g_minibot.setModuleToggle(14, itemShieldSettings['enabled']) -- Item Mana Shield Module type
    if itemShieldSettings['enabled'] then
        local internal = {
            item = 35563,
            use = false, -- use_fear
            max = itemShieldSettings['health'] or 0,
            manaMin = 0, -- recast_value
            hits = 0, -- creatures_value

            reqmana = 0,
            health = 0,
            mana = 0,
            min = 0,
            manaMax = 0,
            harmony = 0,
            lastCall = 0,
            enabled = true,
            ignorePz = false,
            area = '',
            target = '',
            spell = '',
            spellGroup = {},
            itemGroup = {},
            spellId = {},
        }

        if itemShieldSettings['use_fear'] then
            internal.use = true
        end

        if itemShieldSettings['recast_enabled'] then
            internal.manaMin = itemShieldSettings['recast_value'] or 0
        end

        if itemShieldSettings['creatures_enabled'] then
            internal.hits = itemShieldSettings['creatures_value'] or 0
        end

        g_minibot.addModule(14, internal) -- Item Mana Shield Module type
    end

    -- Remove Shield
    local removeShieldSettings = sList['remove_shield'] or {}
    g_minibot.resetModule(15) -- Remove Mana Shield Module type
    g_minibot.setModuleToggle(15, removeShieldSettings['enabled']) -- Item Mana Shield Module type
    if removeShieldSettings['enabled'] then
        local internal = {
            spell = '',
            spellGroup = {},
            reqmana = 0,
            max = removeShieldSettings['health'] or 0,
            use = false, -- ignore_fear
            hits = 0, -- creatures_value

            item = 0,
            manaMin = 0,
            health = 0,
            mana = 0,
            min = 0,
            manaMax = 0,
            harmony = 0,
            lastCall = 0,
            ignorePz = false,
            enabled = true,
            area = '',
            target = '',
            itemGroup = {},
            spellId = {},
        }

        if removeShieldSettings['ignore_fear'] then
            internal.use = true
        end

        if removeShieldSettings['creatures_enabled'] then
            internal.hits = removeShieldSettings['creatures_value'] or 0
        end

        local spell = g_spells.getSpellInfoById(245) -- exana vita (Remove Magic Shield)
        local canCastSpell = spell ~= nil and
            (modules.game_actionbar == nil or type(modules.game_actionbar.canSpellCast) ~= 'function' or
             modules.game_actionbar.canSpellCast(spell))
        if canCastSpell then
            internal.spell = spell.words
            internal.reqmana = spell.mana
            table.insert(internal.spellId, spell.id)
            for _, group in ipairs(spell.groups) do
                table.insert(internal.spellGroup, group)
            end
        end

        g_minibot.addModule(15, internal) -- Remove Mana Shield Module type
    end
end

function support_manashieldModule.loadSettings()
    support_manashieldModule.ignoreQuerySaveSettings = true
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['support_manashield'] or {}

    -- Spell Shield
    local spellShieldSettings = sList['spell_shield'] or {}
    supportManaShieldWindow.panel.list.spellShield.enabled:setChecked(not(spellShieldSettings['enabled'] or false))
    supportManaShieldWindow.panel.list.spellShield.enabled:setChecked(spellShieldSettings['enabled'] or false)
    supportManaShieldWindow.panel.list.spellShield.text:setText(spellShieldSettings['health'] or '')
    supportManaShieldWindow.panel.list.spellShield.potion:setChecked(not(spellShieldSettings['use_potion'] or false))
    supportManaShieldWindow.panel.list.spellShield.potion:setChecked(spellShieldSettings['use_potion'] or false)
    supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:setChecked(not(spellShieldSettings['creatures_enabled'] or false))
    supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:setChecked(spellShieldSettings['creatures_enabled'] or false)
    supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setText(spellShieldSettings['creatures_value'] or '')
    supportManaShieldWindow.panel.list.spellShield.recast.check:setChecked(not(spellShieldSettings['recast_enabled'] or false))
    supportManaShieldWindow.panel.list.spellShield.recast.check:setChecked(spellShieldSettings['recast_enabled'] or false)
    supportManaShieldWindow.panel.list.spellShield.recast.text:setText(spellShieldSettings['recast_value'] or '')

    -- Item Shield
    local itemShieldSettings = sList['item_shield'] or {}
    supportManaShieldWindow.panel.list.itemShield.enabled:setChecked(not(itemShieldSettings['enabled'] or false))
    supportManaShieldWindow.panel.list.itemShield.enabled:setChecked(itemShieldSettings['enabled'] or false)
    supportManaShieldWindow.panel.list.itemShield.text:setText(itemShieldSettings['health'] or '')
    supportManaShieldWindow.panel.list.itemShield.fear:setChecked(not(itemShieldSettings['use_fear'] or false))
    supportManaShieldWindow.panel.list.itemShield.fear:setChecked(itemShieldSettings['use_fear'] or false)
    supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:setChecked(not(itemShieldSettings['creatures_enabled'] or false))
    supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:setChecked(itemShieldSettings['creatures_enabled'] or false)
    supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setText(itemShieldSettings['creatures_value'] or '')
    supportManaShieldWindow.panel.list.itemShield.recast.check:setChecked(not(itemShieldSettings['recast_enabled'] or false))
    supportManaShieldWindow.panel.list.itemShield.recast.check:setChecked(itemShieldSettings['recast_enabled'] or false)
    supportManaShieldWindow.panel.list.itemShield.recast.text:setText(itemShieldSettings['recast_value'] or '')

    -- Remove Shield
    local removeShieldSettings = sList['remove_shield'] or {}
    supportManaShieldWindow.panel.list.removeShield.enabled:setChecked(not(removeShieldSettings['enabled'] or false))
    supportManaShieldWindow.panel.list.removeShield.enabled:setChecked(removeShieldSettings['enabled'] or false)
    supportManaShieldWindow.panel.list.removeShield.text:setText(removeShieldSettings['health'] or '')
    supportManaShieldWindow.panel.list.removeShield.fear:setChecked(not(removeShieldSettings['ignore_fear'] or false))
    supportManaShieldWindow.panel.list.removeShield.fear:setChecked(removeShieldSettings['ignore_fear'] or false)
    supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:setChecked(not(removeShieldSettings['creatures_enabled'] or false))
    supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:setChecked(removeShieldSettings['creatures_enabled'] or false)
    supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setText(removeShieldSettings['creatures_value'] or '')

    support_manashieldModule.ignoreQuerySaveSettings = nil
    support_manashieldModule.reloadCircleGif()
end

function support_manashieldModule.saveSettings()
    if support_manashieldModule.ignoreQuerySaveSettings then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['support_manashield'] or {}

    -- Spell Shield
    local spellShieldSettings = {}
    spellShieldSettings['enabled'] = supportManaShieldWindow.panel.list.spellShield.enabled:isChecked()
    spellShieldSettings['health'] = supportManaShieldWindow.panel.list.spellShield.text:getText() == '' and 0 or tonumber(supportManaShieldWindow.panel.list.spellShield.text:getText())
    spellShieldSettings['use_potion'] = supportManaShieldWindow.panel.list.spellShield.potion:isChecked()
    spellShieldSettings['creatures_enabled'] = supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:isChecked()
    spellShieldSettings['creatures_value'] = supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:getText() == '' and 0 or tonumber(supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:getText())
    spellShieldSettings['recast_enabled'] = supportManaShieldWindow.panel.list.spellShield.recast.check:isChecked()
    spellShieldSettings['recast_value'] = supportManaShieldWindow.panel.list.spellShield.recast.text:getText() == '' and 0 or tonumber(supportManaShieldWindow.panel.list.spellShield.recast.text:getText())
    sList['spell_shield'] = spellShieldSettings

    -- Item Shield
    local itemShieldSettings = {}
    itemShieldSettings['enabled'] = supportManaShieldWindow.panel.list.itemShield.enabled:isChecked()
    itemShieldSettings['health'] = supportManaShieldWindow.panel.list.itemShield.text:getText() == '' and 0 or tonumber(supportManaShieldWindow.panel.list.itemShield.text:getText())
    itemShieldSettings['use_fear'] = supportManaShieldWindow.panel.list.itemShield.fear:isChecked()
    itemShieldSettings['creatures_enabled'] = supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:isChecked()
    itemShieldSettings['creatures_value'] = supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:getText() == '' and 0 or tonumber(supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:getText())
    itemShieldSettings['recast_enabled'] = supportManaShieldWindow.panel.list.itemShield.recast.check:isChecked()
    itemShieldSettings['recast_value'] = supportManaShieldWindow.panel.list.itemShield.recast.text:getText() == '' and 0 or tonumber(supportManaShieldWindow.panel.list.itemShield.recast.text:getText())
    sList['item_shield'] = itemShieldSettings

    -- Remove Shield
    local removeShieldSettings = {}
    removeShieldSettings['enabled'] = supportManaShieldWindow.panel.list.removeShield.enabled:isChecked()
    removeShieldSettings['health'] = supportManaShieldWindow.panel.list.removeShield.text:getText() == '' and 0 or tonumber(supportManaShieldWindow.panel.list.removeShield.text:getText())
    removeShieldSettings['ignore_fear'] = supportManaShieldWindow.panel.list.removeShield.fear:isChecked()
    removeShieldSettings['creatures_enabled'] = supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:isChecked()
    removeShieldSettings['creatures_value'] = supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:getText() == '' and 0 or tonumber(supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:getText())
    sList['remove_shield'] = removeShieldSettings

    settings['support_manashield'] = sList
    modules.game_minibot.setPressetSettings(settings)
    support_manashieldModule.reloadInternalModule()
    support_manashieldModule.reloadCircleGif()
end

function support_manashieldModule.querySaveSettings()
    if support_manashieldModule.ignoreQuerySaveSettings then
        return
    end

    support_manashieldModule.saveSettings()
end

function support_manashieldModule.onItemShieldChange(widget)
    if supportManaShieldWindow == nil then
        return
    end

    if widget:isChecked() then
        supportManaShieldWindow.panel.list.itemShield.frameBackground:setPhantom(false)
        supportManaShieldWindow.panel.list.itemShield.block:hide()
        supportManaShieldWindow.panel.list.itemShield.label:setOpacity(1)
        supportManaShieldWindow.panel.list.itemShield.text:setEnabled(true)
        supportManaShieldWindow.panel.list.itemShield.text:setOpacity(1)
        supportManaShieldWindow.panel.list.itemShield.item:setOpacity(1)
        supportManaShieldWindow.panel.list.itemShield.fear:setPhantom(false)
        supportManaShieldWindow.panel.list.itemShield.fear:setOpacity(1)
        supportManaShieldWindow.panel.list.itemShield.recast.check:setPhantom(false)
        supportManaShieldWindow.panel.list.itemShield.recast.check:setOpacity(1)
        supportManaShieldWindow.panel.list.itemShield.recast.label:setPhantom(false)
        supportManaShieldWindow.panel.list.itemShield.recast.label:setOpacity(1)
        supportManaShieldWindow.panel.list.itemShield.recast.checkHelp:setPhantom(false)
        supportManaShieldWindow.panel.list.itemShield.recast.checkHelp:setOpacity(1)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:setPhantom(false)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:setOpacity(1)

        if supportManaShieldWindow.panel.list.itemShield.recast.check:isChecked() then
            supportManaShieldWindow.panel.list.itemShield.recast.label:setPhantom(false)
            supportManaShieldWindow.panel.list.itemShield.recast.label:setOpacity(1)
            supportManaShieldWindow.panel.list.itemShield.recast.text:setEnabled(true)
            supportManaShieldWindow.panel.list.itemShield.recast.text:setPhantom(false)
            supportManaShieldWindow.panel.list.itemShield.recast.text:setOpacity(1)
        else
            supportManaShieldWindow.panel.list.itemShield.recast.label:setPhantom(true)
            supportManaShieldWindow.panel.list.itemShield.recast.label:setOpacity(0.5)
            supportManaShieldWindow.panel.list.itemShield.recast.text:setEnabled(false)
            supportManaShieldWindow.panel.list.itemShield.recast.text:setPhantom(true)
            supportManaShieldWindow.panel.list.itemShield.recast.text:setOpacity(0.5)
        end

        if supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:isChecked() then
            supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setEnabled(true)
            supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setPhantom(false)
            supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setOpacity(1)
        else
            supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setEnabled(false)
            supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setPhantom(true)
            supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setOpacity(0.5)
        end
    else
        supportManaShieldWindow.panel.list.itemShield.frameBackground:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.block:show()
        supportManaShieldWindow.panel.list.itemShield.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.text:setEnabled(false)
        supportManaShieldWindow.panel.list.itemShield.text:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.item:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.fear:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.fear:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.recast.check:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.recast.check:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.recast.label:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.recast.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.recast.text:setEnabled(false)
        supportManaShieldWindow.panel.list.itemShield.recast.text:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.recast.text:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.recast.checkHelp:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.recast.checkHelp:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyLabel:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setEnabled(false)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setOpacity(0.5)
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.onSpellShieldChange(widget)
    if supportManaShieldWindow == nil then
        return
    end

    if widget:isChecked() then
        supportManaShieldWindow.panel.list.spellShield.frameBackground:setPhantom(false)
        supportManaShieldWindow.panel.list.spellShield.block:hide()
        supportManaShieldWindow.panel.list.spellShield.label:setOpacity(1)
        supportManaShieldWindow.panel.list.spellShield.text:setEnabled(true)
        supportManaShieldWindow.panel.list.spellShield.text:setOpacity(1)
        supportManaShieldWindow.panel.list.spellShield.spell:setOpacity(1)
        supportManaShieldWindow.panel.list.spellShield.potion:setPhantom(false)
        supportManaShieldWindow.panel.list.spellShield.potion:setOpacity(1)
        supportManaShieldWindow.panel.list.spellShield.recast.check:setPhantom(false)
        supportManaShieldWindow.panel.list.spellShield.recast.check:setOpacity(1)
        supportManaShieldWindow.panel.list.spellShield.recast.label:setPhantom(false)
        supportManaShieldWindow.panel.list.spellShield.recast.label:setOpacity(1)
        supportManaShieldWindow.panel.list.spellShield.recast.checkHelp:setPhantom(false)
        supportManaShieldWindow.panel.list.spellShield.recast.checkHelp:setOpacity(1)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:setPhantom(false)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:setOpacity(1)

        if supportManaShieldWindow.panel.list.spellShield.recast.check:isChecked() then
            supportManaShieldWindow.panel.list.spellShield.recast.label:setPhantom(false)
            supportManaShieldWindow.panel.list.spellShield.recast.label:setOpacity(1)
            supportManaShieldWindow.panel.list.spellShield.recast.text:setEnabled(true)
            supportManaShieldWindow.panel.list.spellShield.recast.text:setPhantom(false)
            supportManaShieldWindow.panel.list.spellShield.recast.text:setOpacity(1)
        else
            supportManaShieldWindow.panel.list.spellShield.recast.label:setPhantom(true)
            supportManaShieldWindow.panel.list.spellShield.recast.label:setOpacity(0.5)
            supportManaShieldWindow.panel.list.spellShield.recast.text:setEnabled(false)
            supportManaShieldWindow.panel.list.spellShield.recast.text:setPhantom(true)
            supportManaShieldWindow.panel.list.spellShield.recast.text:setOpacity(0.5)
        end

        if supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:isChecked() then
            supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setEnabled(true)
            supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setPhantom(false)
            supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setOpacity(1)
        else
            supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setEnabled(false)
            supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setPhantom(true)
            supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setOpacity(0.5)
        end
    else
        supportManaShieldWindow.panel.list.spellShield.frameBackground:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.block:show()
        supportManaShieldWindow.panel.list.spellShield.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.text:setEnabled(false)
        supportManaShieldWindow.panel.list.spellShield.text:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.spell:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.potion:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.potion:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.recast.check:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.recast.check:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.recast.label:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.recast.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.recast.text:setEnabled(false)
        supportManaShieldWindow.panel.list.spellShield.recast.text:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.recast.text:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.recast.checkHelp:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.recast.checkHelp:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyLabel:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setEnabled(false)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setOpacity(0.5)
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.onCreaturesNearbyItemShieldChange(widget)
    if supportManaShieldWindow == nil then
        return
    end

    if widget:isChecked() then
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setEnabled(true)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setOpacity(1)
    else
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setEnabled(false)
        supportManaShieldWindow.panel.list.itemShield.creaturesNearbyText:setOpacity(0.5)
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.onCreaturesNearbySpellShieldChange(widget)
    if supportManaShieldWindow == nil then
        return
    end

    if widget:isChecked() then
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setEnabled(true)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setOpacity(1)
    else
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setEnabled(false)
        supportManaShieldWindow.panel.list.spellShield.creaturesNearbyText:setOpacity(0.5)
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.onRenewSpellShieldChange(widget)
    if supportManaShieldWindow == nil then
        return
    end

    if widget:isChecked() then
        supportManaShieldWindow.panel.list.spellShield.recast.label:setPhantom(false)
        supportManaShieldWindow.panel.list.spellShield.recast.label:setOpacity(1)
        supportManaShieldWindow.panel.list.spellShield.recast.text:setPhantom(false)
        supportManaShieldWindow.panel.list.spellShield.recast.text:setOpacity(1)
    else
        supportManaShieldWindow.panel.list.spellShield.recast.label:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.recast.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.spellShield.recast.text:setPhantom(true)
        supportManaShieldWindow.panel.list.spellShield.recast.text:setOpacity(0.5)
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.onRenewItemShieldChange(widget)
    if supportManaShieldWindow == nil then
        return
    end

    if widget:isChecked() then
        supportManaShieldWindow.panel.list.itemShield.recast.label:setPhantom(false)
        supportManaShieldWindow.panel.list.itemShield.recast.label:setOpacity(1)
        supportManaShieldWindow.panel.list.itemShield.recast.text:setPhantom(false)
        supportManaShieldWindow.panel.list.itemShield.recast.text:setOpacity(1)
    else
        supportManaShieldWindow.panel.list.itemShield.recast.label:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.recast.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.itemShield.recast.text:setPhantom(true)
        supportManaShieldWindow.panel.list.itemShield.recast.text:setOpacity(0.5)
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.onCreaturesRemoveShieldChange(widget)
    if supportManaShieldWindow == nil then
        return
    end

    if widget:isChecked() then
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setPhantom(false)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setOpacity(1)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setPhantom(false)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setOpacity(1)
    else
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setPhantom(true)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setPhantom(true)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setOpacity(0.5)
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.onRemoveShieldChange(widget)
    if supportManaShieldWindow == nil then
        return
    end

    if widget:isChecked() then
        supportManaShieldWindow.panel.list.removeShield.frameBackground:setPhantom(false)
        supportManaShieldWindow.panel.list.removeShield.block:hide()
        supportManaShieldWindow.panel.list.removeShield.label:setOpacity(1)
        supportManaShieldWindow.panel.list.removeShield.text:setEnabled(true)
        supportManaShieldWindow.panel.list.removeShield.text:setOpacity(1)
        supportManaShieldWindow.panel.list.removeShield.spell:setOpacity(1)
        supportManaShieldWindow.panel.list.removeShield.fear:setPhantom(false)
        supportManaShieldWindow.panel.list.removeShield.fear:setOpacity(1)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:setPhantom(false)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:setOpacity(1)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setPhantom(false)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setOpacity(1)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.checkHelp:setPhantom(false)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.checkHelp:setOpacity(1)

        if supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:isChecked() then
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setPhantom(false)
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setOpacity(1)
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setEnabled(true)
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setPhantom(false)
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setOpacity(1)
        else
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setPhantom(true)
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setOpacity(0.5)
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setEnabled(false)
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setPhantom(true)
            supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setOpacity(0.5)
        end
    else
        supportManaShieldWindow.panel.list.removeShield.frameBackground:setPhantom(true)
        supportManaShieldWindow.panel.list.removeShield.block:show()
        supportManaShieldWindow.panel.list.removeShield.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.removeShield.text:setEnabled(false)
        supportManaShieldWindow.panel.list.removeShield.text:setOpacity(0.5)
        supportManaShieldWindow.panel.list.removeShield.spell:setOpacity(0.5)
        supportManaShieldWindow.panel.list.removeShield.fear:setPhantom(true)
        supportManaShieldWindow.panel.list.removeShield.fear:setOpacity(0.5)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:setPhantom(true)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.check:setOpacity(0.5)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setPhantom(true)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.label:setOpacity(0.5)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setEnabled(false)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setPhantom(true)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.text:setOpacity(0.5)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.checkHelp:setPhantom(true)
        supportManaShieldWindow.panel.list.removeShield.creaturesNearby.checkHelp:setOpacity(0.5)
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.validateTextPercentage(widget)
    if widget:getText() == '' then
        support_manashieldModule.querySaveSettings()
        return
    end

    local value = tonumber(widget:getText())
    if value == nil or value == 0 then
        widget:clearText()
        support_manashieldModule.querySaveSettings()
        return
    end

    if value > 100 then
        widget:setText(100)
        support_manashieldModule.querySaveSettings()
        return
    end

    support_manashieldModule.querySaveSettings()
end

function support_manashieldModule.reloadCircleGif()
    if supportManaShieldWindow.panel.list.spellShield.enabled:isChecked() or supportManaShieldWindow.panel.list.itemShield.enabled:isChecked() then
        supportManaShieldWindow.panel.manaShieldOn:show()
        supportManaShieldWindow.panel.manaShieldOff:hide()
    else
        supportManaShieldWindow.panel.manaShieldOn:hide()
        supportManaShieldWindow.panel.manaShieldOff:show()
    end
end
