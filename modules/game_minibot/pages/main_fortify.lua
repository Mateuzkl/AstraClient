main_fortifyModule = {}

local mainFortifyWindow = nil

function main_fortifyModule.init(widget)
    mainFortifyWindow = widget

end

function main_fortifyModule.terminate()
    mainFortifyWindow = nil

end

function main_fortifyModule.reloadInternalModule()

end
