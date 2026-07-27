function init()
  itemActionWarning = g_ui.displayUI('item_action')
end

function terminate()
  if itemActionWarning then
    itemActionWarning:destroy()
    itemActionWarning = nil
  end
end

function online()
 hide() 
end

function offline()
  hide()
end

function show()
  itemActionWarning:show(true)
  itemActionWarning:raise()
  itemActionWarning:focus()
end

function hide()
  itemActionWarning:hide()
end