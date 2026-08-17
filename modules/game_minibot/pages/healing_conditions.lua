healing_conditionsModule = {}

local healingConditionsWindow = nil

function healing_conditionsModule.init(widget)
    healingConditionsWindow = widget

end

function healing_conditionsModule.terminate()
    healingConditionsWindow = nil

end

function healing_conditionsModule.reloadInternalModule()

end
