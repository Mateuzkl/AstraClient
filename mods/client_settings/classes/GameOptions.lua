if not GameOptions then
    GameOptions = {
        loadedWindows = {},
        options = dofile('dataset.lua')
    }
    GameOptions.__index = GameOptions
end

function GameOptions:setLoadedWindow(windows)
    self.loadedWindows = windows
end

function GameOptions:getLoadedWindow(value)
    return self.loadedWindows[value]
end

function GameOptions:setupStart()
    for key, option in pairs(self.options) do
        g_settings.setDefault(key, option.value)
    end

    g_logger.info("> All default options have been set.")
end

function GameOptions:loadSettings()
    for key, option in pairs(self.options) do
        if type(option.value) == 'boolean' then
            self:setOption(key, g_settings.getBoolean(key))
        elseif type(option.value) == 'number' then
            self:setOption(key, g_settings.getNumber(key))
        elseif type(option.value) == 'string' then
            self:setOption(key, g_settings.getString(key))
        end
    end

    g_logger.info("> All local options have been set.")
end

function GameOptions:getOption(key)
    if not self.options[key] then
        g_logger.error("[GameOptions::getOption] Option not found: " .. key)
    end
    return self.options[key] and self.options[key].value or false
end

function GameOptions:getDataSet(key)
    return self.options[key]
end

function  GameOptions:setOption(key, value)
    if self.options[key].apply and not self.options[key].apply(value) then
        g_logger.warning("Failed to apply option: " .. key)
        return
    end

    self.options[key].value = value
    g_settings.set(key, value)

    -- change value for keybind updates
    for _,panel in pairs(self.loadedWindows) do
        local widget = panel:recursiveGetChildById(key)
        if widget then
            if key == 'antialiasing' then
                if value == 1 then
                    widget:setCurrentOption("None", true)
                elseif value == 2 then
                    widget:setCurrentOption("Antialiasing", true)
                elseif value == 3 then
                    widget:setCurrentOption("Smooth Retro", true)
                end
            elseif widget:getStyle().__class == 'UICheckBox' then
                widget:setChecked(value)
            elseif widget:getStyle().__class == 'UIScrollBar' then
                widget:setValue(value)
            elseif widget:getStyle().__class == 'UIComboBox' then
                if type(value) == "string" then
                    widget:setCurrentOption(value, true)
                    break
                end
                if value == nil or value < 1 then
                    value = 1
                end
                if widget.currentIndex ~= value then
                    widget:setCurrentIndex(value, true)
                end
            end
            break
        end
    end

end
