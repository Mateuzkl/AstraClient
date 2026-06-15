if not TempOptions then
    TempOptions = {
        options = {}
    }
    TempOptions.__index = TempOptions
end

function TempOptions:setOption(key, value)
    local option = GameOptions:getDataSet(key)
    if option.tempApply and not option.tempApply(value) then
        g_logger.info("Failed to apply tmp option: " .. key)
        return
    end
    self.options[key] = value
end

function TempOptions:getOption(key)
    return self.options[key]
end

function TempOptions:resetOption(key)
    self.options[key] = nil
end

function TempOptions:resetAllOptions()
    self.options = {}
end

function TempOptions:hasOptions()
    return next(self.options) ~= nil
end

function TempOptions:applyOptions()
    for key, value in pairs(self.options) do
        GameOptions:setOption(key, value)
    end

    self:resetAllOptions()
end
