local function ensureCamViewerWindow()
    if camViewerWindow then
        return availableCamsList ~= nil
    end

    camViewerWindow = g_ui.displayUI("client_camviewer")
    if not camViewerWindow then
        return false
    end

    camViewerWindow:hide()
    availableCamsList = camViewerWindow.contentPanel:getChildById("availableCams")
    if not availableCamsList then
        camViewerWindow:destroy()
        camViewerWindow = nil
        return false
    end
    return true
end

function init()
    connect(g_game, {
      onRecordEnd = onRecordEnd
    })
end

function terminate()
    disconnect(g_game, {
      onRecordEnd = onRecordEnd
    })

    if camViewerWindow then
        camViewerWindow:destroy()
        camViewerWindow = nil
    end
    availableCamsList = nil
end

function show()
    if not ensureCamViewerWindow() then
        return
    end

	load()
	camViewerWindow:show(true)
	camViewerWindow:raise()
	camViewerWindow:focus()
end

function toggle()
	if camViewerWindow and camViewerWindow:isVisible() then
		hide()
		return
	end
	show()
end

function hide()
    if camViewerWindow then
	    camViewerWindow:hide()
    end
end

function onRecordEnd()
  modules.client_entergame.EnterGame.show()
end

function load()
    if not ensureCamViewerWindow() then
        return
    end

    local t = {}
    local i = 0

    if g_app.getOs() == "windows" then
        for dir in io.popen("dir \"records\" /B /O:N /A:-D"):lines() do
            i = i + 1
            t[i] = dir
        end
    else
        for dir in io.popen("ls -1 records | grep -v /"):lines() do
            i = i + 1
            t[i] = dir
        end
    end


    local availableCams = {}
    availableCamsList:destroyChildren()

    if not table.empty(t) then
        availableCams = t
    end

    if not table.empty(availableCams) then
        for _, fileName in pairs(availableCams) do
            local formattedName = formatCamName(fileName)
            local label = g_ui.createWidget("CamListLabel", availableCamsList)
            label:setText(short_text(formattedName,34))
            label.camName = fileName
        end
    end
end

function formatCamName(fileName)
    local nameWithoutExtension = string.match(fileName, "(.-)%..+$")
    local charName, worldName, year, month, day, hour, min, sec = string.match(nameWithoutExtension, "(.-)_(.-)_(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)")

    if charName and worldName and year and month and day and hour and min then
        local formattedName = string.format("%s | %s [%s/%s/%s | %s:%s]", charName, worldName, day, month, year, hour, min)
        return formattedName
    else
        return nameWithoutExtension -- Retorna o nome original caso não consiga formatar
    end
end

function renameCam()
    local cam = availableCamsList:getFocusedChild()
    if not cam then
        displayErrorBox(tr("Error"), tr("You must select a recording to rename."))
        return
    end
    local camName = cam.camName
	-- Adicionar Lógica
end

function deleteCam()
    local cam = availableCamsList:getFocusedChild()
    if not cam then
        displayErrorBox(tr("Error"), tr("You must select a recording to delete."))
        return
    end
    local camName = cam.camName
	local confirmText = "Are you sure you want to delete this recording?"

    local okFunc = function()
		check:destroy()
        os.remove("records/" .. camName)
        load()
    end

    local cancelFunc = function() check:destroy() end

    check = displayGeneralBox(tr("Confirm Deletion"), confirmText,
        { { text=tr('Yes'), callback=okFunc },
          { text=tr('No'), callback=cancelFunc }
        }, okFunc, cancelFunc)
end

function playCam()
	local cam = availableCamsList:getFocusedChild()
	if not cam then
        errorBox = displayErrorBox(tr("Error"), tr("You must select a reason."))
        errorBox.onOk = function()
            errorBox = nil
            modules.client_entergame.EnterGame.show()
        end
        return
    end
	local camName = cam.camName
	g_settings.setNode("things", {})
	g_game.playRecord(camName)
end
