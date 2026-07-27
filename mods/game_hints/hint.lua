hintWindow = nil
local maxPages = 3
local currentPage = 1
local openedHints = {}

function init()
end

function terminate()
  for _, window in pairs(openedHints) do
    if window then
      window:destroy()
    end
  end

  openedHints = {}
end

function showHint(hintType)
  local hintPath = 'styles/' .. hintType

  if openedHints[hintType] then
    return
  end

  if hintType == 'tutorialhint' then
    currentPage = 1
  end

  local hintWindow = g_ui.loadUI(hintPath, g_ui.getRootWidget())
  hintWindow:show(true)
  openedHints[hintType] = hintWindow
end

function destroyHint(hintType)
  local hintWindow = openedHints[hintType]
  if hintWindow then
    hintWindow:destroy()
    openedHints[hintType] = nil
  end
end

function tutorialHint(action)
  showHint('tutorialhint')
  local hintWindow = openedHints['tutorialhint']
  if action == 'next' then
    if currentPage < 3 then
      currentPage = currentPage + 1
    end
  elseif action == 'back' then
    if currentPage > 1 then
      currentPage = currentPage - 1
    end
  end

  hintWindow.contentPanel:getChildById('firstScreen'):setVisible(currentPage == 1)
  hintWindow.contentPanel:getChildById('secondScreen'):setVisible(currentPage == 2)
  hintWindow.contentPanel:getChildById('thirdScreen'):setVisible(currentPage == 3)

  if currentPage == 3 then
    hintWindow.contentPanel:getChildById('ok'):setVisible(true)
    hintWindow.contentPanel:getChildById('next'):setVisible(false)
  else
    hintWindow.contentPanel:getChildById('ok'):setVisible(false)
    hintWindow.contentPanel:getChildById('next'):setVisible(true)
  end

  hintWindow.contentPanel:getChildById('back'):setEnabled(currentPage > 1)
end

function vocationHint(vocationId)
  showHint('voc_change')
  local hintWindow = openedHints['voc_change']
  if not hintWindow then
    return
  end

  local imageSource = ''
  if vocationId == 1 then
    imageSource = '/images/game/tutorial/hint_03_vocationknight'
  elseif vocationId == 2 then
    imageSource = '/images/game/tutorial/hint_04_vocationpaladin'
  elseif vocationId == 3 then
    imageSource = '/images/game/tutorial/hint_05_vocationsorcerer'
  elseif vocationId == 4 then
    imageSource = '/images/game/tutorial/hint_06_vocationdruid'
  end

  if imageSource ~= '' then
    hintWindow.contentPanel:getChildById('vocation'):setImageSource(imageSource)
  end
end

function arrivalHint(vocationId)
  showHint('arrival')
  local hintWindow = openedHints['arrival']
  if not hintWindow then
    return
  end

  local imageSource = ''
  if vocationId == 1 then
    imageSource = '/images/game/tutorial/hint_07_arrivalmainknight'
  elseif vocationId == 2 then
    imageSource = '/images/game/tutorial/hint_08_arrivalmainpaladin'
  elseif vocationId == 3 then
    imageSource = '/images/game/tutorial/hint_09_arrivalmainsorcerer'
  elseif vocationId == 4 then
    imageSource = '/images/game/tutorial/hint_10_arrivalmaindruid'
  end

  if imageSource ~= '' then
    hintWindow.contentPanel:getChildById('arrivalMain'):setImageSource(imageSource)
  end
end