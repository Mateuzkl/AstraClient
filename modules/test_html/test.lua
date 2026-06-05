TestHtmlModule = Controller:new()

function TestHtmlModule:onInit()
    self.clicks = 0
    self.statusText = 'Waiting for click'
    self.counterText = 'Clicks: 0'
    self.buttonText = 'Click'
end

function TestHtmlModule:onTerminate()
    self:unloadHtml()
    self:setButtonOn(false)
end

function TestHtmlModule:getButton()
    local rightPanel = modules.game_interface and modules.game_interface.getRightPanel()
    if not rightPanel then
        return nil
    end
    return rightPanel:recursiveGetChildById('testHtmlButton')
end

function TestHtmlModule:setButtonOn(on)
    local button = self:getButton()
    if button then
        button:setOn(on)
    end
end

function TestHtmlModule:open()
    if self.htmlId then
        return
    end

    if modules.game_htmlsample and modules.game_htmlsample.close then
        modules.game_htmlsample.close()
    elseif modules.game_htmlsample and modules.game_htmlsample.HtmlSample and modules.game_htmlsample.HtmlSample.close then
        modules.game_htmlsample.HtmlSample:close()
    end

    if not g_html then
        displayErrorBox('HTML Test', 'This executable does not have g_html. Open the otclient_dx_x64.exe built on 2026-05-20 or rebuild the GL executable with the HTML/CSS engine.')
        return
    end

    self.clicks = 0
    self.statusText = 'Waiting for click'
    self.counterText = 'Clicks: 0'
    self.buttonText = 'Click'
    self:loadHtml('test.html')
    self:setButtonOn(true)
end

function TestHtmlModule:updateLabels()
    self.counterText = 'Clicks: ' .. tostring(self.clicks)
    self.statusText = self.clicks == 0 and 'Waiting for click' or 'Button clicked successfully'
end

function TestHtmlModule:onButtonClick(target)
    self.clicks = self.clicks + 1
    self.buttonText = 'Click again'
    self:updateLabels()
end

function TestHtmlModule:close()
    if self.htmlId then
        self:unloadHtml()
    end
    self:setButtonOn(false)
end

function TestHtmlModule:toggle()
    if self.htmlId then
        self:close()
    else
        self:open()
    end
end

function toggle()
    TestHtmlModule:toggle()
end

function close()
    TestHtmlModule:close()
end
