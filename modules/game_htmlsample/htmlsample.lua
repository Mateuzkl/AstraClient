HtmlSample = Controller:new()
HtmlSample.exampleBasePath = '/docs/exampleHTML_flex/'

function HtmlSample:toggle()
    if self.ui and not self.ui:isDestroyed() then
        self:close()
        return
    end

    self:onInit()
end

function HtmlSample:close()
    self:clearScheduledEvents()
    if self.htmlId then
        self:unloadHtml()
    end
    self:setButtonOn(false)
end

function HtmlSample:onTerminate()
    self:close()
end

function toggle()
    HtmlSample:toggle()
end

function close()
    HtmlSample:close()
end

function HtmlSample:getButton()
    local rightPanel = modules.game_interface and modules.game_interface.getRightPanel()
    if not rightPanel then
        return nil
    end
    return rightPanel:recursiveGetChildById('htmlSampleButton')
end

function HtmlSample:setButtonOn(on)
    local button = self:getButton()
    if button then
        button:setOn(on)
    end
end

function HtmlSample:isThingsLoaded()
    return modules.game_things and modules.game_things.isLoaded()
end

function HtmlSample:onInit()
    if modules.test_html and modules.test_html.close then
        modules.test_html.close()
    elseif modules.test_html and modules.test_html.TestHtmlModule and modules.test_html.TestHtmlModule.close then
        modules.test_html.TestHtmlModule:close()
    end

    self.playerName = ''
    self.lookType = '128'
    self.players = {}

    self.title = 'HTML/CSS'
    self.height = 585
    self.width = 820
    self.selectedTab = 'main'
    self.selectedExampleFile = nil
    self.exampleCountText = ''
    self.responsiveWidth = 520
    self.responsiveDirection = -1
    self.responsiveMinWidth = 260
    self.responsiveMaxWidth = 744

    self:setTabFlags()
    self:loadHtml('htmlsample.html')
    self:setupFooterButtons()
    self:updateTabsState()
    self:renderCurrentTab()
    self:setButtonOn(true)
end

function HtmlSample:cancelScheduledEvent(name)
    if not self.scheduledEvents then
        return
    end

    for _, events in pairs(self.scheduledEvents) do
        if events and events[name] then
            removeEvent(events[name])
            events[name] = nil
        end
    end
end

function HtmlSample:setTabFlags()
    self.isMainTab = self.selectedTab == 'main'
    self.isExamplesTab = self.selectedTab == 'examples'
    self.isResponsiveTab = self.selectedTab == 'responsive'
end

function HtmlSample:updateTabsState()
    local tabs = {
        main = self:findWidget('#tabMain'),
        examples = self:findWidget('#tabExamples'),
        responsive = self:findWidget('#tabResponsive')
    }

    for tab, widget in pairs(tabs) do
        if widget and not widget:isDestroyed() and widget.setOn then
            widget:setOn(tab == self.selectedTab)
        end
    end
end

function HtmlSample:selectTab(tab)
    if tab ~= 'main' and tab ~= 'examples' and tab ~= 'responsive' then
        tab = 'main'
    end

    if self.selectedTab == tab then
        return
    end

    if self.selectedTab == 'responsive' then
        self:cancelScheduledEvent('responsive-demo')
    end

    self.selectedTab = tab
    self:setTabFlags()

    if self.ui and not self.ui:isDestroyed() then
        self.ui:setHeight(self.height)
        self.ui:setWidth(self.width)
        self:scheduleHtmlCenter()
    end

    self:updateTabsState()
    self:renderCurrentTab()
end

function HtmlSample:getContentArea()
    return self:findWidget('#contentArea')
end

function HtmlSample:getPreviewLookType()
    return tonumber(self.lookType) or 128
end

function HtmlSample:refreshWidget(widget)
    if not widget or widget:isDestroyed() then
        return
    end

    if widget.updateLayout then
        widget:updateLayout()
    end
    if widget.updateParentLayout then
        widget:updateParentLayout()
    end
    if widget.updateScrollBars then
        widget:updateScrollBars()
    end
end

function HtmlSample:renderCurrentTab()
    local content = self:getContentArea()
    if not content then
        return
    end

    content:destroyChildren()
    if content.setVirtualOffset then
        content:setVirtualOffset({ x = 0, y = 0 })
    end

    if self.isExamplesTab then
        self:renderExamplesTab(content)
    elseif self.isResponsiveTab then
        self:renderResponsiveTab(content)
    else
        self:renderMainTab(content)
    end

    self:refreshWidget(content)
end

function HtmlSample:renderMainTab(content)
    self:createWidgetFromHTML([[
      <div class="mainContent">
        <div class="sectionCaption">Demo HTML/CSS</div>

        <div class="topPanel">
          <div class="formPanel">
            <div class="panelTitle">Add player</div>
            <div class="formRow">
              <label class="fieldLabel">Name:</label>
              <div id="playerNameSlot" class="fieldInput fieldSlot"></div>
            </div>
            <div class="formRow">
              <label class="fieldLabel">Look type:</label>
              <div id="lookTypeSlot" class="fieldInput fieldSlot"></div>
            </div>
            <div id="addPlayerButtonSlot" class="addButton"></div>
          </div>
          <div class="previewPanel">
            <div class="previewTitle">Preview</div>
            <div class="previewBox">
              <uicreature id="previewCreature" class="HtmlPreviewCreature previewCreature" *outfit="{type = self:getPreviewLookType()}"></uicreature>
            </div>
          </div>
        </div>

        <div id="players" class="playersPanel">
          <table class="playersTable">
            <thead>
              <tr>
                <th>#</th>
                <th>Outfit</th>
                <th>Name</th>
                <th>Remove</th>
              </tr>
            </thead>
            <tbody>
              <tr *for="local player in self.players">
                <td>{{index + 1}}</td>
                <td><uicreature class="HtmlListCreature listCreature" *outfit="{type = player.lookType}"></uicreature></td>
                <td>{{player.name}}</td>
                <td><button class="HtmlSmallButton buttonRemovePlayer" text="X" onclick="self:removePlayer(index)"></button></td>
              </tr>
            </tbody>
          </table>
          <div class="emptyPlayers" *if="#self.players == 0">No players added yet.</div>
        </div>
      </div>
    ]], content)

    self:scheduleMainNativeWidgets()
end

function HtmlSample:createNativeWidget(styleName, slotId, width, height)
    local slot = self:findWidget('#' .. slotId)
    if not slot or slot:isDestroyed() then
        return
    end

    local widget = slot:getChildByIndex(1)
    if not widget or widget:isDestroyed() or widget:getStyleName() ~= styleName then
        slot:destroyChildren()
        widget = g_ui.createWidget(styleName, slot)
    end

    widget:setWidth(width or slot:getWidth())
    widget:setHeight(height or slot:getHeight())
    widget:setPosition({ x = 0, y = 0 })
    return widget
end

function HtmlSample:setupFooterButtons()
    local aboutButton = self:createNativeWidget('Button', 'aboutButtonSlot', 65, 20)
    if aboutButton then
        aboutButton:setText('About')
        aboutButton.onClick = function()
            alert('HTML/CSS V.4b')
        end
    end

    local closeButton = self:createNativeWidget('Button', 'closeButtonSlot', 43, 20)
    if closeButton then
        closeButton:setText('Close')
        closeButton.onClick = function()
            self:unloadHtml()
        end
    end
end

function HtmlSample:createTextInput(slotId, value, callback)
    local input = self:createNativeWidget('TextEdit', slotId, 280, 20)
    if not input then
        return
    end

    input:setFocusable(true)
    if input.setEditable then
        input:setEditable(true)
    end
    if input.setSelectable then
        input:setSelectable(true)
    end
    if input.setCursor then
        input:setCursor('text')
    end
    if input.setMaxLength then
        input:setMaxLength(32)
    end

    input:setText(tostring(value or ''))
    input.onTextChange = function(_, text)
        callback(tostring(text or ''))
    end

    return input
end

function HtmlSample:setupMainNativeWidgets()
    self.playerNameInput = self:createTextInput('playerNameSlot', self.playerName, function(text)
        self.playerName = text
    end)

    self.lookTypeInput = self:createTextInput('lookTypeSlot', self.lookType, function(text)
        self.lookType = text
        self:updatePreviewCreature()
    end)

    local addButton = self:createNativeWidget('LongButton', 'addPlayerButtonSlot', 86, 20)
    if addButton then
        addButton:setText('Add player')
        addButton.onClick = function()
            self:addPlayer()
        end
    end
end

function HtmlSample:scheduleMainNativeWidgets()
    self:setupMainNativeWidgets()
    self:scheduleEvent(function()
        if self.ui and not self.ui:isDestroyed() and self.isMainTab then
            self:setupMainNativeWidgets()
        end
    end, 1, 'main-native-widgets')
end

function HtmlSample:updatePreviewCreature()
    local preview = self:findWidget('#previewCreature')
    if preview and not preview:isDestroyed() and preview.setOutfit then
        preview:setOutfit({ type = self:getPreviewLookType() })
    end
end

function HtmlSample:renderExamplesTab(content)
    self:createWidgetFromHTML([[
      <div class="examplesContent">
        <div class="exampleControls">
          <label for="exampleComboBox">Example:</label>
          <select id="exampleComboBox" onchange="self:onExampleComboBoxChange(event)"></select>
          <div id="exampleMeta" class="exampleMeta" *text="self.exampleCountText"></div>
        </div>
        <div class="exampleFrame">
          <div id="examplePreview" class="examplePreview"></div>
        </div>
      </div>
    ]], content)

    self:setupExamplesComboBox()
end

function HtmlSample:renderResponsiveTab(content)
    self:createWidgetFromHTML([[
      <div class="responsiveContent">
        <div class="responsiveHeader">
          <div class="responsiveTitle">Responsive flex-wrap demo</div>
          <div id="responsiveWidthLabel" class="responsiveMeta">Width: 520px</div>
        </div>
        <div class="responsiveHint">Viewport changes width automatically to show flex-wrap.</div>
        <div class="responsiveStage">
          <div id="responsiveViewport" class="responsiveViewport"></div>
        </div>
      </div>
    ]], content)

    self:setupResponsiveDemo()
    self:startResponsiveDemo()
end

function HtmlSample:refreshMainTab()
    if self.isMainTab then
        self:renderCurrentTab()
    end
end

function HtmlSample:getExampleFiles()
    local files = g_resources.listDirectoryFiles(self.exampleBasePath)
    local htmlFiles = {}

    for _, file in ipairs(files) do
        if g_resources.isFileType(file, 'html') then
            table.insert(htmlFiles, file)
        end
    end

    table.sort(htmlFiles)
    return htmlFiles
end

function HtmlSample:selectExampleFile(files)
    if self.selectedExampleFile then
        for _, file in ipairs(files) do
            if file == self.selectedExampleFile then
                return file
            end
        end
    end

    return files[1]
end

function HtmlSample:setupExamplesComboBox()
    local combo = self:findWidget('#exampleComboBox')
    if not combo then
        return
    end

    combo:clearOptions()
    combo.menuScroll = true
    combo.menuHeight = 220
    combo.menuScrollStep = 22

    local htmlFiles = self:getExampleFiles()
    self.selectedExampleFile = self:selectExampleFile(htmlFiles)
    self.exampleCountText = #htmlFiles > 0 and string.format('%d examples available', #htmlFiles) or ''

    for _, file in ipairs(htmlFiles) do
        combo:addOption(file, { file = file })
    end

    if self.selectedExampleFile then
        combo:setCurrentOption(self.selectedExampleFile, true)
        self:renderSelectedExample()
    else
        self:showExampleMessage('No .html files found in ' .. self.exampleBasePath)
    end
end

function HtmlSample:onExampleComboBoxChange(event)
    local file = nil

    if event then
        if type(event.data) == 'table' then
            file = event.data.file
        elseif type(event.data) == 'string' then
            file = event.data
        elseif event.target and event.target.getCurrentOption then
            local option = event.target:getCurrentOption()
            if option then
                file = type(option.data) == 'table' and option.data.file or option.text
            end
        end
        file = file or event.text or event.value
    end

    if not file or #file == 0 then
        return
    end

    self.selectedExampleFile = file
    if self.isExamplesTab then
        self:renderSelectedExample()
    end
end

function HtmlSample:showExampleMessage(message)
    local preview = self:findWidget('#examplePreview')
    if not preview then
        return
    end

    preview:destroyChildren()
    self:createWidgetFromHTML('<div class="exampleMessage">' .. tostring(message or '') .. '</div>', preview)
    self:refreshPreviewLayout()
end

function HtmlSample:prepareExampleHtml(html)
    html = tostring(html or '')
    html = html:gsub('%-%-image%-source%s*:', 'image-source:')

    local override = [[
      <style>
        window {
          display: block;
          width: 746;
          min-height: 384;
          height: auto;
          margin: 0;
          padding: 12;
          image-source: none;
          image-border: 0;
          background-color: #f6f6f6;
          color: #222222;
          overflow: visible;
        }
      </style>
    ]]

    local injected, count = html:gsub('</html>%s*$', override .. '</html>')
    if count == 0 then
        injected = html .. override
    end
    return injected
end

function HtmlSample:refreshPreviewLayout()
    local preview = self:findWidget('#examplePreview')
    if not preview or preview:isDestroyed() then
        return
    end

    self:refreshWidget(preview)
end

function HtmlSample:renderSelectedExample()
    local preview = self:findWidget('#examplePreview')
    if not preview then
        return
    end

    preview:destroyChildren()
    if preview.setVirtualOffset then
        preview:setVirtualOffset({ x = 0, y = 0 })
    end

    if not self.selectedExampleFile or #self.selectedExampleFile == 0 then
        self:showExampleMessage('Select an example to preview.')
        return
    end

    local filePath = self.exampleBasePath .. self.selectedExampleFile
    if not g_resources.fileExists(filePath) then
        self:showExampleMessage('File not found: ' .. self.selectedExampleFile)
        return
    end

    local html = g_resources.readFileContents(filePath)
    if not html or #html == 0 then
        self:showExampleMessage('File is empty: ' .. self.selectedExampleFile)
        return
    end

    local root = self:createWidgetFromHTML(self:prepareExampleHtml(html), preview)
    local function refreshPreviewLayout()
        if root and not root:isDestroyed() then
            self:refreshWidget(root)
        end
        self:refreshPreviewLayout()
    end

    self:scheduleEvent(refreshPreviewLayout, 1, 'example-preview-refresh-1')
    self:scheduleEvent(refreshPreviewLayout, 30, 'example-preview-refresh-30')
    self:scheduleEvent(refreshPreviewLayout, 80, 'example-preview-refresh-80')
end

function HtmlSample:setupResponsiveDemo()
    local viewport = self:findWidget('#responsiveViewport')
    if not viewport then
        return
    end

    viewport:destroyChildren()

    local palette = {
        '#203a78',
        '#7f19c6',
        '#d98319',
        '#ba2d2d',
        '#1d8d2d',
        '#105f6b',
        '#8b6f22',
        '#4d4d4d'
    }

    for i = 1, 30 do
        local width = math.random(28, 86)
        local color = palette[((i - 1) % #palette) + 1]
        self:createWidgetFromHTML(string.format(
            '<div class="responsiveBox" style="width: %dpx; background-color: %s;"></div>',
            width,
            color
        ), viewport)
    end

    self:updateResponsiveViewport()
end

function HtmlSample:updateResponsiveViewport()
    local viewport = self:findWidget('#responsiveViewport')
    if not viewport or viewport:isDestroyed() then
        return
    end

    viewport:setWidth(self.responsiveWidth)

    local widthLabel = self:findWidget('#responsiveWidthLabel')
    if widthLabel and not widthLabel:isDestroyed() then
        widthLabel:setText(string.format('Width: %dpx', self.responsiveWidth))
    end

    self:refreshWidget(viewport)
end

function HtmlSample:startResponsiveDemo()
    self:cancelScheduledEvent('responsive-demo')

    self:cycleEvent(function()
        if not self.ui or self.ui:isDestroyed() then
            return false
        end

        local viewport = self:findWidget('#responsiveViewport')
        if not viewport or viewport:isDestroyed() or not self.isResponsiveTab then
            return false
        end

        self.responsiveWidth = self.responsiveWidth + self.responsiveDirection * 24
        if self.responsiveWidth <= self.responsiveMinWidth then
            self.responsiveWidth = self.responsiveMinWidth
            self.responsiveDirection = 1
        elseif self.responsiveWidth >= self.responsiveMaxWidth then
            self.responsiveWidth = self.responsiveMaxWidth
            self.responsiveDirection = -1
        end

        self:updateResponsiveViewport()
    end, 90, 'responsive-demo')
end

function HtmlSample:addPlayer(name)
    if self.playerNameInput and not self.playerNameInput:isDestroyed() then
        self.playerName = self.playerNameInput:getText()
    end
    if self.lookTypeInput and not self.lookTypeInput:isDestroyed() then
        self.lookType = self.lookTypeInput:getText()
    end

    name = tostring(name or self.playerName or ''):trim()
    if #name == 0 then
        return
    end

    table.insert(self.players, {
        name = name,
        lookType = tonumber(self.lookType) or 128
    })

    self.playerName = ''
    self:refreshMainTab()
end

function HtmlSample:removePlayer(index)
    index = tonumber(index)
    if not index then
        return
    end

    table.remove(self.players, index + 1)
    self:refreshMainTab()
end
