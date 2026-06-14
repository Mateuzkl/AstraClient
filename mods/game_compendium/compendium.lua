local compendiumWindow
local currentSection = 1
local currentPage = 1

local sections = {
  {
    title = "Game Content",
    pages = {
      "Task Hunt\nComplete bounty and weekly tasks, improve your talismans and spend hunting points in the task shop.",
      "Soul Seal\nUse Soul Pit content to collect Soul Seal points and unlock its progression rewards."
    }
  },
  {
    title = "Client Features",
    pages = {
      "ATC Helper\nConfigure supported helper tools, alarms and shortcuts from the ATC Helper panel.",
      "Modern Windows\nInspect items, customise monster podiums and manage familiar appearance through Astra-only protocol extensions."
    }
  },
  {
    title = "Useful Info",
    pages = {
      "Use the right-side menu to open Cyclopedia, Task Hunt, Compendium and other game systems.",
      "Only Astra Client receives the modern extension bytes. Legacy Cip and OTC clients keep their original packet layout."
    }
  },
  {
    title = "Major Updates",
    pages = {
      "Modern Systems\nTask Hunt, Soul Seal, Familiar, item inspection and monster podium support are integrated with the 8.60 protocol."
    }
  },
  {
    title = "Support",
    pages = {
      "For account or gameplay support, use the official Astra support channels. Include screenshots and the exact error message when reporting a problem."
    }
  }
}

local function renderPage()
  if not compendiumWindow then
    return
  end

  local section = sections[currentSection]
  currentPage = math.max(1, math.min(currentPage, #section.pages))
  local content = compendiumWindow:recursiveGetChildById('compendiumContent')
  local pages = compendiumWindow:recursiveGetChildById('pages')
  local previousButton = compendiumWindow:recursiveGetChildById('previousPageButton')
  local nextButton = compendiumWindow:recursiveGetChildById('nextPageButton')

  if content then
    content:setText(section.pages[currentPage])
  end
  if pages then
    pages:setText(string.format("%d / %d", currentPage, #section.pages))
  end
  if previousButton then
    previousButton:setEnabled(currentPage > 1)
  end
  if nextButton then
    nextButton:setEnabled(currentPage < #section.pages)
  end

  for index = 1, #sections do
    local button = compendiumWindow:recursiveGetChildById("buttonMenu" .. index)
    if button then
      button:setChecked(index == currentSection)
    end
  end
end

function init()
  compendiumWindow = g_ui.displayUI('compendium')
  renderPage()
  hide()
end

function terminate()
  g_client.setInputLockWidget(nil)
  if compendiumWindow then
    compendiumWindow:destroy()
    compendiumWindow = nil
  end
end

function hide()
  if not compendiumWindow then
    return
  end
  compendiumWindow:hide()
  g_client.setInputLockWidget(nil)
end

function show()
  if not compendiumWindow then
    return
  end
  currentSection = 1
  currentPage = 1
  compendiumWindow:show(true)
  compendiumWindow:focus()
  g_client.setInputLockWidget(compendiumWindow)
  renderPage()
end

function selectSection(index)
  if not sections[index] then
    return
  end
  currentSection = index
  currentPage = 1
  renderPage()
end

function previousPage()
  currentPage = currentPage - 1
  renderPage()
end

function nextPage()
  currentPage = currentPage + 1
  renderPage()
end
