local panelButtons = {}

local function addButton(id, description, image, callback, front, index)
  if panelButtons[id] and not panelButtons[id]:isDestroyed() then
    return panelButtons[id]
  end

  local button = nil
  if modules.client_topmenu and modules.client_topmenu.addRightGameToggleButton then
    button = modules.client_topmenu.addRightGameToggleButton(id, description, image, callback, front, index)
  elseif modules.client_topmenu and modules.client_topmenu.addLeftGameToggleButton then
    button = modules.client_topmenu.addLeftGameToggleButton(id, description, image, callback, front, index)
  end

  if button and type(index) == 'number' then
    button.index = index
  end

  panelButtons[id] = button
  return button
end

function init()
end

function terminate()
  for id, button in pairs(panelButtons) do
    if button and not button:isDestroyed() then
      button:destroy()
    end
    panelButtons[id] = nil
  end
end

function addToggleButton(id, description, image, callback, front, index)
  return addButton(id, description, image, callback, front, index)
end

function addSpecialToggleButton(id, description, image, callback, front, index)
  return addButton(id, description, image, callback, front, index)
end

function addStoreButton(id, description, image, callback, front, index)
  return addButton(id, description, image, callback, front, index)
end

function getButton(id)
  if panelButtons[id] and not panelButtons[id]:isDestroyed() then
    return panelButtons[id]
  end

  if modules.client_topmenu and modules.client_topmenu.getButton then
    return modules.client_topmenu.getButton(id)
  end

  return nil
end

function toggleStore()
  if modules.game_store and modules.game_store.toggle then
    modules.game_store.toggle()
  elseif modules.game_shop and modules.game_shop.toggle then
    modules.game_shop.toggle()
  end
end

function reloadMainPanelSizes()
end

function toggleExtendedViewButtons()
end
