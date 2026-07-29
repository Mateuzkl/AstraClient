if not ControllerAnalyser then
    ControllerAnalyser = {
        name = "ControllerAnalyser",
        class = "ControllerAnalyser",
        window = nil,
        session = nil,
        event250 = nil,
        event1000 = nil,
        event2000 = nil,
        eventGraph = nil,
        data = {}
    }
    ControllerAnalyser.__index = ControllerAnalyser
end

function ControllerAnalyser:stopEvents()
    if ControllerAnalyser.eventGraph then
        removeEvent(ControllerAnalyser.eventGraph)
        ControllerAnalyser.eventGraph = nil
    end
    if ControllerAnalyser.event250 then
        removeEvent(ControllerAnalyser.event250)
        ControllerAnalyser.event250 = nil
    end
    if ControllerAnalyser.event1000 then
        removeEvent(ControllerAnalyser.event1000)
        ControllerAnalyser.event1000 = nil
    end
    if ControllerAnalyser.event2000 then
        removeEvent(ControllerAnalyser.event2000)
        ControllerAnalyser.event2000 = nil
    end
end

function ControllerAnalyser:startEvent()
	HuntingAnalyser.session = os.time()
    LootAnalyser.session = os.time()
    SupplyAnalyser.session = os.time()
    ImpactAnalyser.session = os.time()
    InputAnalyser.session = os.time()
    XPAnalyser.session = os.time()
    DropTrackerAnalyser.session = os.time()
    MiscAnalyzer.session = os.time()

    ControllerAnalyser:stopEvents()

    ControllerAnalyser.event250 = cycleEvent(function()
        if g_game.isOnline() then
            BossCooldown:checkTicks()
        end
	end, 250)

    ControllerAnalyser.event1000 = cycleEvent(function()
        if g_game.isOnline() then
            HuntingAnalyser:updateWindow()
            LootAnalyser:checkBalance()
            ImpactAnalyser:updateWindow()
            InputAnalyser:checkDPS()
            XPAnalyser:checkExpHour()
            DropTrackerAnalyser:checkTracker()
            MiscAnalyzer:updateWindow()
            SupplyAnalyser:updateGraphics()
        end
	end, 1000)
	ControllerAnalyser.event2000 = cycleEvent(function()
        if g_game.isOnline() then
            InputAnalyser:updateWindow()
            SupplyAnalyser:checkBalance()
        end
	end, 2000)
	ControllerAnalyser.eventGraph = cycleEvent(function()
        if g_game.isOnline() then
            LootAnalyser:updateGraphics()
            SupplyAnalyser:updateGraphics()
            XPAnalyser:updateWindow()
        end
	end, 60*1000)


    ImpactAnalyser:checkAnchos()
    InputAnalyser:checkAnchos()
end
