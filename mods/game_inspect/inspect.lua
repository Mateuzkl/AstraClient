tibiaInspect = nil

local inspectInfoWidth = 430
local inspectLabelWidth = 95
local inspectContentWidth = 320

function init()
  tibiaInspect = g_ui.displayUI('styles/inspectItem')
  hide()

  connect(g_game, { onInspection = onInspection, onGameStart = hide, onGameEnd = hide })
end

function terminate()
  if tibiaInspect then
    tibiaInspect:destroy()
    tibiaInspect = nil
  end

  disconnect(g_game, { onInspection = onInspection, onGameStart = hide, onGameEnd = hide })
end

function toggle()
  if tibiaInspect:isVisible() then
    tibiaInspect:hide()
    g_client.setInputLockWidget(nil)
  else
    tibiaInspect:show(true)
    g_client.setInputLockWidget(tibiaInspect)
  end
end

function hide()
  tibiaInspect:hide()
  g_client.setInputLockWidget(nil)
end

function show()
  tibiaInspect:show(true)
  g_client.setInputLockWidget(tibiaInspect)
end

function onInspection(inspectType, itemName, item, descriptions, imbuements)
  if inspectType > 0 then
    return
  end

  show()
  if #imbuements == 3 then
    tibiaInspect.contentPanel.name:setWidth(170)
  elseif #imbuements == 2 then
    tibiaInspect.contentPanel.name:setWidth(240)
  elseif #imbuements == 1 then
    tibiaInspect.contentPanel.name:setWidth(315)
  end

  tibiaInspect.contentPanel.item:setItemId(item:getId())
  tibiaInspect.contentPanel.item:getItem():setTier(item:getTier())
  tibiaInspect.contentPanel.name:setText("You are inspecting: " .. itemName)

  -- clear all slots
  for i = 1, 3 do
    local widget = tibiaInspect:recursiveGetChildById("imbuiSlot" .. i)
    widget:setVisible(false)
    widget:setImageSource("/images/game/imbuing/slot-inactive")
    widget:setImageClip("0 0 64 64")
  end

  -- fill slots  
  for k, v in pairs(imbuements) do
    local widget = tibiaInspect:recursiveGetChildById("imbuiSlot" .. (4 - k))
    widget:setVisible(true)
    if v > 0 then
      widget:setImageSource("/images/game/imbuing/imbuement-icons-64")
      widget:setImageClip(getFramePosition(v, 64, 64, 21) .. " 64 64")
    end
  end

  tibiaInspect.contentPanel.itemInfo:destroyChildren()
  for _, data in pairs(descriptions) do
		local widget = g_ui.createWidget("InspectLabel", tibiaInspect.contentPanel.itemInfo)
		widget:setWidth(inspectInfoWidth)
		widget.label:setWidth(inspectLabelWidth)
		widget.separator:setMarginLeft(inspectLabelWidth)
		widget.content:setWidth(inspectContentWidth)
		if widget.content.setTextWrap then
			widget.content:setTextWrap(true)
		end
		if widget.content.setTextAutoResize then
			widget.content:setTextAutoResize(true)
		end
		widget.label:setText(data.detail .. ":")
		widget.content:setText(data.description)

		if widget.content:isTextWraped() then
			local wrappedLines = math.max(1, widget.content:getWrappedLinesCount())
			local rowHeight = math.max(21, 21 * wrappedLines + 6)
			widget:setSize(tosize(inspectInfoWidth .. " " .. rowHeight))
			widget.label:setHeight(rowHeight)
			widget.separator:setHeight(rowHeight)
			widget.content:setHeight(rowHeight)
		end
	end
end
