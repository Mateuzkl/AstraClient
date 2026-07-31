-- dev_otui: .otui screen editor/inspector rendered by OTClient itself.
-- Fidelity is exact because the same renderer that draws the game draws the
-- preview: same bitmap fonts, same image-border 9-slice, same style cascade.
--
-- The property panel mirrors the file's LINES (through otml.lua), not the
-- widget's getters. That is how properties without a getter show up, such as
-- anchors.* and @onClick, and why what you save is exactly what you read.

local editorWindow = nil
local topButton = nil

local stage = nil          -- isolated preview area to the right of the editor
local captureLayer = nil   -- transparent layer used by "Edit" mode
local selectionBox = nil   -- green rectangle around the selected widget
local hoverBox = nil       -- yellow rectangle around the widget under the mouse
local resizeHandle = nil   -- resize handle, bottom-right corner

local targetPath = nil
local targetFileTime = 0
local watchEvent = nil

local doc = nil            -- OTML document of the target file (otml.lua)
local currentNode = nil    -- file node matching the selected widget
local nodeError = nil      -- why the widget could not be mapped
local currentRef = nil     -- how to find currentNode again after reparsing

-- A third of the project's .otui files (every one under /data/styles) has no main
-- widget: they only define styles, and loadUI returns nil for them. For those
-- we build a showcase instantiating each style, and the selected widget then
-- points at the style definition in the file rather than at a tree node.
local showcaseMode = false
local showcaseStyleIndex = {} -- widget -> index into doc.styleDefs

local selectedWidget = nil
local selectedPath = nil   -- index path, used to reselect after a reload
local treeItems = {}
local propRows = {}        -- { key, edit, original, readOnly, pending }
local selecting = false

local drag = nil           -- state of the drag in progress

local guides = {}          -- parent-area guide widgets
local guidesEnabled = false

local pickerWindow = nil   -- helper window (open file / choose element)
local pickerEntries = {}
local pickerCallback = nil
local pickerPreview = false -- picker shows a live sample of the highlighted item
local fileCache = nil      -- project's .otui list (scanning is expensive)
local styleCache = nil     -- style palette; depends on the open file
local confirmWindow = nil

local AUTO_RELOAD_INTERVAL = 300
local MAX_TREE_DEPTH = 12
local HANDLE_SIZE = 10
local EDITOR_HOTKEY = 'Ctrl+Alt+U'
local PROJECT_ROOTS = { '/modules', '/mods', '/data/styles' }
local ensureEditorWindow
local closeConfirmWindow
local classProblem
local styleProblem

-- ============================================================ helpers

local function status(msg, isError)
  if not editorWindow then return end
  local label = editorWindow:recursiveGetChildById('statusLabel')
  label:setText(msg)
  label:setColor(isError and '#ff6b6b' or '#dfdf7f')
  label:setTooltip(msg) -- the message may not fit; the tooltip holds it whole
  if isError then
    g_logger.warning('[dev_otui] ' .. msg)
  end
end

local function isPreviewWidget(widget)
  if not widget or not stage or stage:isDestroyed() or widget == stage then return false end
  local current = widget
  while current do
    if current == stage then return true end
    current = current:getParent()
  end
  return false
end

local function normalizePath(path)
  path = path:trim()
  if path == '' then return nil end
  if path:sub(1, 1) ~= '/' then path = '/' .. path end
  if not path:ends('.otui') then path = path .. '.otui' end
  return path
end

-- Stacking (bottom -> top): stage, captureLayer, editorWindow, boxes.
local function restackLayers()
  if captureLayer and not captureLayer:isDestroyed() then captureLayer:raise() end
  if editorWindow and not editorWindow:isDestroyed() then editorWindow:raise() end
  if hoverBox and not hoverBox:isDestroyed() then hoverBox:raise() end
  if selectionBox and not selectionBox:isDestroyed() then selectionBox:raise() end
  if resizeHandle and not resizeHandle:isDestroyed() then resizeHandle:raise() end
end

local function describePath(widget)
  local parts = {}
  local w = widget
  while w and w ~= stage do
    local name = w:getStyleName()
    if not name or name == '' then name = 'UIWidget' end
    local id = w:getId()
    if id and id ~= '' and id ~= name then name = name .. '#' .. id end
    table.insert(parts, 1, name)
    w = w:getParent()
  end
  return table.concat(parts, ' > ')
end

local function indexPath(widget)
  local path = {}
  local w = widget
  while w and w ~= stage and w:getParent() do
    local parent = w:getParent()
    table.insert(path, 1, parent:getChildIndex(w))
    w = parent
  end
  return path
end

local function widgetFromIndexPath(path)
  if not path or not stage then return nil end
  local w = stage
  for _, index in ipairs(path) do
    w = w:getChildByIndex(index)
    if not w then return nil end
  end
  return w
end

local function ensureBox(existing, color, filled)
  if existing and not existing:isDestroyed() then return existing end
  local box = g_ui.createWidget('UIWidget', rootWidget)
  box:setPhantom(true)
  box:setFocusable(false)
  box:breakAnchors()
  if filled then
    box:setBackgroundColor(color)
  else
    box:setBorderWidth(1)
    box:setBorderColor(color)
  end
  box:hide()
  return box
end

local function moveBoxTo(box, widget)
  if not box then return end
  if not widget or widget:isDestroyed() then
    box:hide()
    return
  end
  box:setRect(widget:getRect())
  box:show()
  box:raise()
end

-- Repositions the selection rectangle and the resize handle on the current widget.
local function refreshSelectionVisuals()
  if not selectedWidget or selectedWidget:isDestroyed() then
    if selectionBox then selectionBox:hide() end
    if resizeHandle then resizeHandle:hide() end
    return
  end

  selectionBox = ensureBox(selectionBox, '#00ff00')
  moveBoxTo(selectionBox, selectedWidget)

  resizeHandle = ensureBox(resizeHandle, '#00ff00', true)
  local rect = selectedWidget:getRect()
  resizeHandle:setRect({
    x = rect.x + rect.width - HANDLE_SIZE,
    y = rect.y + rect.height - HANDLE_SIZE,
    width = HANDLE_SIZE,
    height = HANDLE_SIZE
  })
  resizeHandle:setVisible(captureLayer ~= nil)
  resizeHandle:raise()
end

-- ============================================================ parent guides

local function clearGuides()
  for _, guide in ipairs(guides) do
    if guide and not guide:isDestroyed() then guide:destroy() end
  end
  guides = {}
end

local function addGuide(rect, color, filled)
  local guide = g_ui.createWidget('UIWidget', rootWidget)
  guide:setPhantom(true)
  guide:setFocusable(false)
  guide:breakAnchors()
  if filled then
    guide:setBackgroundColor(color)
  else
    guide:setBorderWidth(1)
    guide:setBorderColor(color)
  end
  guide:setRect(rect)
  guide:raise()
  table.insert(guides, guide)
  return guide
end

-- Sibling a "prev"/"next"/"<id>" anchor points at, so the link is visible.
local function anchorTargetWidget(target)
  if not selectedWidget or target == 'parent' then return nil end

  local parent = selectedWidget:getParent()
  if not parent then return nil end

  if target == 'prev' or target == 'next' then
    local index = parent:getChildIndex(selectedWidget)
    local wanted = (target == 'prev') and index - 1 or index + 1
    -- getChildByIndex counts from the end for indices <= 0 (uiwidget.cpp:1510),
    -- so asking for 0 would hand back the last child instead of nothing
    if wanted < 1 or wanted > parent:getChildCount() then return nil end
    return parent:getChildByIndex(wanted)
  end

  return parent:getChildById(target)
end

-- Draws the parent's box and centre lines, plus a box around every sibling this
-- widget is anchored to. Only redrawn on selection: the parent does not move
-- while dragging, so there is no need to rebuild these every frame.
local function drawGuides()
  clearGuides()

  if not guidesEnabled then return end
  if not selectedWidget or selectedWidget:isDestroyed() then return end

  local parent = selectedWidget:getParent()
  if not parent or parent:isDestroyed() then return end

  -- padding rect, not the plain rect: that is the area children are laid inside
  local area = parent:getPaddingRect()
  addGuide(area, '#4c9fff')
  addGuide({ x = area.x, y = area.y + math.floor(area.height / 2),
             width = area.width, height = 1 }, '#4c9fff55', true)
  addGuide({ x = area.x + math.floor(area.width / 2), y = area.y,
             width = 1, height = area.height }, '#4c9fff55', true)

  if not currentNode then return end

  for _, prop in ipairs(Otml.properties(currentNode)) do
    if prop.tag:starts('anchors.') and prop.value then
      local target = prop.value:match('^([^.]+)')
      local widget = target and anchorTargetWidget(target)
      if widget and widget ~= selectedWidget and not widget:isDestroyed() then
        addGuide(widget:getRect(), '#ff9d3c')
      end
    end
  end
end

function setGuides(enabled)
  guidesEnabled = enabled
  drawGuides()
  if enabled then
    status('Guides on: blue is the parent area, orange is a widget this one is anchored to.')
  end
end

-- ============================================================ file document

-- Resolves the file node from an index path, without validating.
local function resolveNodeByPath(document, path)
  if not document or not document.root then return nil end
  local node = document.root
  for i = 2, #path do
    local kids = Otml.widgetChildren(node)
    node = kids[path[i]]
    if not node then return nil end
  end
  return node
end

-- Finds the edited node again in a freshly parsed document, whether it is a
-- widget from the tree or a style definition (showcase).
local function resolveRef(document, ref)
  if not document or not ref then return nil end
  if ref.kind == 'style' then
    return document.styleDefs[ref.index]
  end
  return resolveNodeByPath(document, ref.path)
end

-- A reference into the file is a path of child indices, so it survives a
-- reparse but says nothing about *which* widget sits there now: a file edited
-- in a text editor between load and save can resolve the same path onto a
-- different widget, and the edit would land on it. Two nodes count as the same
-- one when the style name and the id both match.
local function sameNodeIdentity(a, b)
  if not a or not b then return false end
  if a.tag ~= b.tag then return false end

  local idA = Otml.findProperty(a, 'id')
  local idB = Otml.findProperty(b, 'id')
  return (idA and idA.value or nil) == (idB and idB.value or nil)
end

local function resolveSameNode(document, ref, expected)
  local resolved = ref and resolveRef(document, ref) or (document and document.root)
  if not sameNodeIdentity(resolved, expected) then return nil end
  return resolved
end

-- The three go together: nodeError is the reason currentNode is missing, so
-- leaving it behind makes a later failure report the wrong cause.
local function clearNodeSelection()
  currentNode = nil
  nodeError = nil
  currentRef = nil
end

-- Resolves while validating file-tag against widget-style at every level.
-- A mismatch means the on-screen tree did not come from the file alone (a widget
-- created by an inherited style, say) and writing there would corrupt the file.
local function nodeForWidget(widget)
  if not stage or stage:isDestroyed() then return nil, 'preview is closed' end
  if not doc then return nil, 'file was not read' end

  -- style showcase: the widget is a sample, not a node of the file's tree.
  -- clicking a child of the sample walks up to the sample standing for the style.
  if showcaseMode then
    local w = widget
    while w and w ~= stage do
      local index = showcaseStyleIndex[w]
      if index then
        return doc.styleDefs[index], nil, { kind = 'style', index = index }
      end
      w = w:getParent()
    end
    return nil, 'click one of the style samples'
  end

  if not doc.root then return nil, 'file has no main widget' end

  local path = indexPath(widget)
  if #path == 0 then return nil, 'widget is outside the preview' end
  if path[1] ~= 1 then return nil, 'the preview has more than one root widget' end

  local node = doc.root
  local w = stage:getChildByIndex(1)
  if not w then return nil, 'preview is empty' end
  if w:getStyleName() ~= node.tag then
    return nil, 'file root and preview root disagree'
  end

  for i = 2, #path do
    local kids = Otml.widgetChildren(node)
    node = kids[path[i]]
    w = w:getChildByIndex(path[i])
    if not node or not w then
      return nil, 'this widget is not in the file (does it come from a style?)'
    end
    if w:getStyleName() ~= node.tag then
      return nil, 'file and preview disagree at "' .. tostring(node.tag) .. '"'
    end
  end

  return node, nil, { kind = 'widget', path = path }
end

local function readDocument(path)
  local readOk, text = pcall(function() return g_resources.readFileContents(path) end)
  if not readOk or not text then
    doc = nil
    -- callers only see false; without this the user is left with the vaguer
    -- "file was not read" that the next selection produces
    status('Could not read the file: ' .. tostring(path) ..
      (readOk and '' or (' (' .. tostring(text) .. ')')), true)
    return false
  end

  local parseOk, parsedOrErr = pcall(function() return Otml.parse(text) end)
  if not parseOk then
    doc = nil
    status('Could not parse the file: ' .. tostring(parsedOrErr), true)
    return false
  end

  doc = parsedOrErr
  return true
end

local function projectRelativePath(virtualPath)
  if type(virtualPath) ~= 'string' or virtualPath:sub(1, 1) ~= '/' then
    return nil, 'the project path must be absolute in the virtual filesystem'
  end
  if virtualPath:find('\\', 1, true) then
    return nil, 'backslashes are not allowed in project paths'
  end
  for part in virtualPath:gmatch('[^/]+') do
    if part == '.' or part == '..' then
      return nil, 'path traversal is not allowed'
    end
  end

  local relative = virtualPath:sub(2)
  local allowed = relative:starts('modules/') or relative:starts('mods/') or
    relative:starts('data/styles/')
  if not allowed or not relative:lower():ends('.otui') then
    return nil, 'only .otui files in modules/, mods/ or data/styles/ can be written'
  end
  return relative
end

-- Astra mounts the project root as-is, so virtual paths retain their
-- modules/, mods/ or data/styles/ prefix. Packed and embedded resources have
-- no real work directory and remain preview-only.
local function workDirWritePath(resources, virtualPath)
  local relative, pathError = projectRelativePath(virtualPath)
  if not relative then return nil, pathError end

  -- for a file that does not exist yet (new screen), ask about its directory
  local probe = virtualPath
  if not resources.fileExists(virtualPath) then
    probe = virtualPath:match('^(.*)/[^/]*$') or '/'
    if probe == '' then probe = '/' end
  end

  local workDir = resources.getWorkDir()
  if not workDir or workDir == '' then
    return nil, 'the client is running from data.zip, embedded data or a read-only package; preview is available but saving is disabled'
  end

  local realDir = resources.getRealDir(probe)
  if not realDir or realDir == '' then
    return nil, 'could not locate the project directory on disk'
  end
  realDir = realDir:gsub('\\', '/')
  workDir = workDir:gsub('\\', '/')
  realDir = realDir:gsub('/+$', ''):lower()
  workDir = workDir:gsub('/+$', ''):lower()

  if realDir ~= workDir then
    return nil, 'file is outside the project directory (' .. realDir .. ')'
  end
  return relative
end

-- ============================================================ tree

local function addTreeItem(widget, depth)
  local list = editorWindow:recursiveGetChildById('treeList')
  local item = g_ui.createWidget('OtuiTreeItem', list)

  local styleName = widget:getStyleName()
  if not styleName or styleName == '' then styleName = 'UIWidget' end

  local label = string.rep('  ', depth) .. styleName
  local id = widget:getId()
  if id and id ~= '' and id ~= styleName then label = label .. ' #' .. id end
  if not widget:isExplicitlyVisible() then label = label .. '  (hidden)' end
  item:setText(label)
  item:setTooltip(label:trim())

  item.otuiWidget = widget
  item.onFocusChange = function(self, focused)
    if focused and self.otuiWidget and not selecting then
      modules.dev_otui.selectWidget(self.otuiWidget)
    end
  end

  table.insert(treeItems, { item = item, widget = widget })
end

local function buildTreeFrom(widget, depth)
  if depth > MAX_TREE_DEPTH then return end
  for _, child in ipairs(widget:getChildren()) do
    addTreeItem(child, depth)
    buildTreeFrom(child, depth + 1)
  end
end

local function rebuildTree()
  local list = editorWindow:recursiveGetChildById('treeList')
  list:destroyChildren()
  treeItems = {}
  if stage and not stage:isDestroyed() then
    buildTreeFrom(stage, 0)
  end
end

local function findTreeItem(widget)
  for _, entry in ipairs(treeItems) do
    if entry.widget == widget then return entry.item end
  end
  return nil
end

-- ============================================================ property panel

local function findRow(key)
  for _, row in ipairs(propRows) do
    if row.key == key then return row end
  end
  return nil
end

local function propertyRowOriginal(value, pending)
  if pending then return nil end
  return value or ''
end

local function shouldRemovePropertyRow(row)
  return row.removed and not row.pending
end

local function addPropRow(key, value, readOnly, pending)
  local list = editorWindow:recursiveGetChildById('propList')
  local widget = g_ui.createWidget('OtuiPropRow', list)

  local keyLabel = widget:getChildById('keyLabel')
  local valueEdit = widget:getChildById('valueEdit')
  local removeBtn = widget:getChildById('removeBtn')

  keyLabel:setText(key)
  valueEdit:setText(value or '')

  if readOnly then
    valueEdit:setEnabled(false)
    keyLabel:setColor('#808080')
  elseif pending then
    keyLabel:setColor('#ffcc00')
  end

  local row = {
    key = key,
    edit = valueEdit,
    label = keyLabel,
    -- A pending row was created by drag/resize/anchor or the "new property"
    -- field and does not exist in the file yet. nil makes saveFile emit it.
    original = propertyRowOriginal(value, pending),
    readOnly = readOnly,
    pending = pending or false,
    removed = false,
  }

  removeBtn.onClick = function()
    modules.dev_otui.removeProperty(key)
  end

  valueEdit.onKeyPress = function(_, keyCode)
    if keyCode == KeyEnter then
      modules.dev_otui.applyAll()
      return true
    end
    return false
  end

  -- also apply when leaving the field, so Enter is not required on every edit
  valueEdit.onFocusChange = function(self, focused)
    if not focused and not self:isDestroyed() and self:getText() ~= row.original then
      modules.dev_otui.applyAll()
    end
  end

  table.insert(propRows, row)
  return row
end

local function rebuildPropertyPanel()
  local list = editorWindow:recursiveGetChildById('propList')
  list:destroyChildren()
  propRows = {}

  if not currentNode then return end

  for _, prop in ipairs(Otml.properties(currentNode)) do
    local composite = #prop.children > 0
    addPropRow(prop.tag, composite and '(block - edit it in the file)' or prop.value, composite, false)
  end
end

-- Used by dragging: reflects in the panel a value already applied to the widget.
local function setPendingProperty(key, value)
  local row = findRow(key)
  if row then
    row.edit:setText(value)
    if not row.pending then
      row.pending = true
      row.label:setColor('#ffcc00')
    end
  else
    addPropRow(key, value, false, true)
  end
end

function removeProperty(key)
  if not currentNode then
    status('Nothing selected.', true)
    return
  end
  local row = findRow(key)
  if not row then return end
  if row.readOnly then
    status('Block property: remove it directly in the file.', true)
    return
  end
  row.removed = true
  row.edit:setText('')
  row.edit:setEnabled(false)
  row.label:setColor('#ff6b6b')
  status('"' .. key .. '" will be removed on save.')
end

function addPropertyFromInput()
  if not selectedWidget then
    status('Select a widget first.', true)
    return
  end

  local input = editorWindow:recursiveGetChildById('newPropEdit'):getText():trim()
  local key, value = input:match('^%s*([^:]+)%s*:%s*(.-)%s*$')
  if not key then
    status('Use the format "property: value".', true)
    return
  end
  key = key:trim()

  local row = findRow(key)
  if row then
    row.edit:setText(value)
    row.removed = false
    row.edit:setEnabled(true)
    setPendingProperty(key, value)
  else
    addPropRow(key, value, false, true)
  end

  editorWindow:recursiveGetChildById('newPropEdit'):setText('')
  applyAll()
end

-- ============================================================ selection

local function refreshStateChecks(widget)
  local function set(id, value)
    local check = editorWindow:recursiveGetChildById(id)
    if not check then return end
    check.suppress = true
    check:setChecked(value)
    check.suppress = false
  end
  set('stateOn', widget:isOn())
  set('stateChecked', widget:isChecked())
  set('stateDisabled', widget:isDisabled())
  set('stateHidden', not widget:isExplicitlyVisible())
end

function selectWidget(widget)
  if not widget or widget:isDestroyed() then return end
  if not isPreviewWidget(widget) then
    status('Only widgets inside the OTUI preview can be selected.')
    return
  end
  if selecting then return end
  selecting = true

  selectedWidget = widget
  selectedPath = indexPath(widget)

  currentNode, nodeError, currentRef = nodeForWidget(widget)

  refreshSelectionVisuals()

  local rect = widget:getRect()
  local origin = currentNode
    and ('line ' .. currentNode.line .. ' of the file' ..
         (showcaseMode and ' (style definition)' or ''))
    or ('not mapped: ' .. tostring(nodeError))

  local info = table.concat({
    describePath(widget),
    string.format('rect: x=%d y=%d  w=%d h=%d', rect.x, rect.y, rect.width, rect.height),
    origin,
  }, '\n')
  local infoLabel = editorWindow:recursiveGetChildById('infoLabel')
  infoLabel:setText(info)
  infoLabel:setTooltip(info)

  refreshStateChecks(widget)
  rebuildPropertyPanel()
  drawGuides()

  local item = findTreeItem(widget)
  if item and not item:isFocused() then
    item:focus()
  end

  selecting = false
end

function applyState(state, value)
  local checkId = 'state' .. state:sub(1, 1):upper() .. state:sub(2)
  local check = editorWindow and editorWindow:recursiveGetChildById(checkId)
  if check and check.suppress then return end
  if not selectedWidget or selectedWidget:isDestroyed() then return end

  if state == 'on' then
    selectedWidget:setOn(value)
  elseif state == 'checked' then
    selectedWidget:setChecked(value)
  elseif state == 'disabled' then
    selectedWidget:setEnabled(not value)
  elseif state == 'hidden' then
    selectedWidget:setVisible(not value)
  end

  refreshSelectionVisuals()
end

-- Applies the panel contents to the live widget, without touching the file.
function applyAll()
  if not selectedWidget or selectedWidget:isDestroyed() then
    status('Select a widget first.', true)
    return
  end

  local count = 0
  for _, row in ipairs(propRows) do
    -- events (@onClick...) were bound at load time; reapplying does not help
    -- the preview and may duplicate handlers
    if not row.readOnly and not row.removed and row.key:sub(1, 1) ~= '@' then
      count = count + 1
      local ok, err = pcall(function()
        selectedWidget:mergeStyle({ [row.key] = row.edit:getText() })
      end)
      if not ok then
        local hint = ''
        if row.key:sub(1, 1) == '!' then
          -- tags with ! are evaluated as Lua expressions (uiwidget.cpp:714)
          hint = ' - values of "' .. row.key .. '" are Lua code: use quotes, like \'my text\''
        end
        -- Earlier rows may already have applied. Rebuild from the unchanged
        -- file so a failed preview never leaves a partially mutated widget.
        if targetPath then modules.dev_otui.reloadTarget() end
        status('Preview failed at "' .. row.key .. '": ' .. tostring(err) .. hint ..
          '. The preview was restored from the file.', true)
        return
      end
    end
  end

  if count == 0 then
    status('No applicable property.', true)
    return
  end

  local parent = selectedWidget:getParent()
  if parent then parent:updateLayout() end

  refreshSelectionVisuals()
  status('Preview applied. Use "Save to file" to persist it.')
end

-- ============================================================ saving

-- Writes text to the target file with a .bak backup and confirms by reading it
-- back through the resource system. The injected resource object keeps the
-- refusal and failure paths testable without touching project files.
local function persistTextWith(resources, virtualPath, newText, backupText)
  local writePath, why = workDirWritePath(resources, virtualPath)
  if not writePath then
    return false, 'cannot write: ' .. tostring(why)
  end

  if backupText then
    if not resources.writeFileContentsToWorkDir(writePath .. '.bak', backupText) then
      return false, 'could not write the .bak backup; nothing was changed'
    end
  end

  if not resources.writeFileContentsToWorkDir(writePath, newText) then
    return false, 'the write failed' ..
      (backupText and (' - the original is at ' .. writePath .. '.bak') or '')
  end

  -- real confirmation: read back through the virtual path and compare
  local okRead, current = pcall(function() return resources.readFileContents(virtualPath) end)
  if not okRead or current ~= newText then
    local restored = false
    if backupText then
      restored = resources.writeFileContentsToWorkDir(writePath, backupText)
      local okRestore, restoredText = pcall(function()
        return resources.readFileContents(virtualPath)
      end)
      restored = restored and okRestore and restoredText == backupText
    end
    return false, 'wrote to ' .. writePath .. ', but the file read back does not match' ..
      (backupText and (restored and '; the original was restored' or '; automatic restore failed') or '')
  end

  return true, writePath
end

local function persistText(virtualPath, newText, backupText)
  return persistTextWith(g_resources, virtualPath, newText, backupText)
end

function saveFile()
  if not targetPath then
    status('No file loaded.', true)
    return
  end
  if not selectedWidget or selectedWidget:isDestroyed() then
    status('Select a widget before saving.', true)
    return
  end
  if not currentNode then
    status('Cannot save: ' .. tostring(nodeError), true)
    return
  end

  local ref = currentRef
  local selectedSnapshot = currentNode

  -- re-read: the file may have changed in the text editor since it was loaded
  if not readDocument(targetPath) then
    status('Could not re-read the file before saving.', true)
    return
  end

  local originalText = Otml.serialize(doc)

  -- the re-read above may have brought in someone else's changes: the path
  -- still resolves, but possibly onto another widget
  if not resolveSameNode(doc, ref, selectedSnapshot) then
    status('The file changed since it was loaded and the selection no longer ' ..
      'matches. Nothing was written - reload and pick the widget again.', true)
    return
  end

  local edits = {}
  for _, row in ipairs(propRows) do
    -- readOnly rows are composite blocks (layout:, $hover:...): left untouched
    if not row.readOnly then
      if shouldRemovePropertyRow(row) then
        table.insert(edits, { key = row.key, remove = true })
      elseif not row.removed then
        local value = row.edit:getText()
        if value ~= row.original then
          table.insert(edits, { key = row.key, value = value })
        end
      end
    end
  end

  if #edits == 0 then
    status('Nothing changed.')
    return
  end

  -- each insertion/removal shifts the following lines, so we reparse and find
  -- the node again after every edit
  for _, edit in ipairs(edits) do
    local node = resolveRef(doc, ref)
    if not node then
      status('Lost track of the widget in the file. Nothing was written.', true)
      readDocument(targetPath)
      return
    end

    local ok, err
    if edit.remove then
      ok, err = Otml.removeProperty(doc, node, edit.key)
    else
      ok, err = Otml.setProperty(doc, node, edit.key, edit.value)
    end
    if not ok then
      status('Failed at "' .. edit.key .. '": ' .. tostring(err) .. '. Nothing was written.', true)
      readDocument(targetPath)
      return
    end

    doc = Otml.reparse(doc)
  end

  local newText = Otml.serialize(doc)

  local ok, result = persistText(targetPath, newText, originalText)
  if not ok then
    status(result .. '. Check the .bak before continuing.', true)
    readDocument(targetPath)
    return
  end

  targetFileTime = g_resources.getFileTime(targetPath)
  readDocument(targetPath)
  currentNode = resolveRef(doc, ref)
  rebuildPropertyPanel()

  status(#edits .. ' change(s) saved to ' .. result)
end

-- ============================================================ stage / loading

function closeStage()
  if captureLayer and not captureLayer:isDestroyed() then captureLayer:destroy() end
  captureLayer = nil
  if stage and not stage:isDestroyed() then stage:destroy() end
  stage = nil
  selectedWidget = nil
  clearNodeSelection()
  showcaseMode = false
  showcaseStyleIndex = {}
  treeItems = {}
  propRows = {}

  if editorWindow and not editorWindow:isDestroyed() then
    local pickCheck = editorWindow:recursiveGetChildById('pickCheck')
    if pickCheck and pickCheck:isChecked() then pickCheck:setChecked(false) end
    editorWindow:recursiveGetChildById('treeList'):destroyChildren()
    editorWindow:recursiveGetChildById('propList'):destroyChildren()
    editorWindow:recursiveGetChildById('infoLabel'):setText('No widget selected.')
  end
  if selectionBox and not selectionBox:isDestroyed() then selectionBox:hide() end
  if hoverBox and not hoverBox:isDestroyed() then hoverBox:hide() end
  if resizeHandle and not resizeHandle:isDestroyed() then resizeHandle:hide() end
  clearGuides()
end

-- Builds the showcase for style-only files: a live sample of each style with
-- its name beside it. It is the only way to "see" /data/styles/*.otui.
local function buildStyleShowcase()
  showcaseStyleIndex = {}

  if not doc or #doc.styleDefs == 0 then
    return 0, 0
  end

  local board = g_ui.createWidget('UIWidget', stage)
  board:setId('otuiShowcase')
  board:breakAnchors()
  board:addAnchor(AnchorTop, 'parent', AnchorTop)
  board:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  board:setMarginTop(20)
  board:setWidth(480)
  board:setBackgroundColor('#00000099')
  board:setPhantom(false)

  local shown, failed = 0, 0
  local y = 6
  local defs = {}
  for _, def in ipairs(doc.styleDefs) do
    local name, base = def.tag:match('^([%w_]+)%s*<%s*([%w_]+)')
    if name then defs[name] = { node = def, base = base, file = targetPath } end
  end

  -- positioned by anchoring to the board (not by absolute coordinates): the
  -- layout only resolves later, so getX()/getY() here would still be zero
  local function place(widget, marginLeft, marginTop)
    widget:breakAnchors()
    widget:addAnchor(AnchorTop, 'parent', AnchorTop)
    widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    widget:setMarginTop(marginTop)
    widget:setMarginLeft(marginLeft)
  end

  for index, def in ipairs(doc.styleDefs) do
    local name = def.tag:match('^([%w_]+)%s*<')
    if name then
      local label = g_ui.createWidget('OtuiTreeItem', board)
      label:setPhantom(true)
      label:setFocusable(false)
      label:setText(name)
      label:setWidth(190)
      label:setHeight(14)
      place(label, 6, y)

      -- styles that depend on a specific parent (MiniWindow, for instance) may
      -- fail to instantiate standalone: that is information, not a fatal error
      local problem = styleProblem and styleProblem(defs, name)
      local ok, sample
      if not problem then
        ok, sample = pcall(function()
          return g_ui.createWidget(name, board)
        end)
      end

      local rowHeight = 18
      if ok and sample then
        place(sample, 200, y)
        if sample:getWidth() <= 1 then sample:setWidth(120) end
        if sample:getHeight() <= 1 then sample:setHeight(16) end
        rowHeight = math.max(18, sample:getHeight() + 4)
        showcaseStyleIndex[sample] = index
        shown = shown + 1
      else
        label:setText(name .. '   (' .. (problem or 'cannot be instantiated standalone') .. ')')
        label:setColor('#ff8080')
        failed = failed + 1
      end

      y = y + rowHeight
    end
  end

  board:setHeight(y + 6)
  return shown, failed
end

local function loadInto(path, keepPath)
  if not g_resources.fileExists(path) then
    status('File not found: ' .. path, true)
    return false
  end

  closeStage()

  stage = g_ui.createWidget('UIWidget', rootWidget)
  stage:setId('otuiStage')
  stage:breakAnchors()
  stage:addAnchor(AnchorTop, 'parent', AnchorTop)
  stage:addAnchor(AnchorRight, 'parent', AnchorRight)
  stage:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  stage:addAnchor(AnchorLeft, editorWindow:getId(), AnchorRight)
  stage:setMarginTop(40)
  stage:setMarginRight(12)
  stage:setMarginBottom(12)
  stage:setMarginLeft(12)
  stage:setClipping(true)
  stage:setPhantom(true) -- the stage steals no clicks; children stay clickable
  stage:setFocusable(false)

  -- UIManager::loadUI swallows exceptions internally: on a syntax error it
  -- only logs and returns nil. That is why we check the return value.
  local ok, result = pcall(function() return g_ui.loadUI(path, stage) end)

  targetPath = path
  targetFileTime = g_resources.getFileTime(path)
  readDocument(path)
  styleCache = nil -- the palette includes styles defined in the open file

  rebuildTree()
  restackLayers()

  if not ok then
    status('Error while loading: ' .. tostring(result), true)
    return false
  end

  if not result then
    -- No main widget. If the file defines styles it is a library (every
    -- /data/styles/*.otui is one): show a sample of each style.
    if doc and #doc.styleDefs > 0 then
      showcaseMode = true
      local shown, failed = buildStyleShowcase()
      rebuildTree()
      restackLayers()

      local extra = failed > 0 and (', ' .. failed .. ' not instantiable standalone') or ''
      status('Style library: ' .. shown .. ' sample(s)' .. extra ..
        '. Click a sample to edit its definition.')
      return true
    end

    status('Failed to parse ' .. path .. ' - open the terminal (Ctrl+T) to see the error.', true)
    return false
  end

  if keepPath then
    selectedPath = keepPath
    local widget = widgetFromIndexPath(keepPath)
    if widget then selectWidget(widget) end
  end

  status('Loaded: ' .. path .. ' (' .. #treeItems .. ' widgets)')
  return true
end

function loadTarget()
  local path = normalizePath(editorWindow:recursiveGetChildById('pathEdit'):getText())
  if not path then
    status('Enter the path of the .otui file.', true)
    return
  end
  selectedPath = nil
  if loadInto(path, nil) then
    g_settings.set('dev_otui_lastPath', path)
  end
end

function reloadTarget()
  if not targetPath then
    status('Load a file first.', true)
    return
  end
  loadInto(targetPath, selectedPath)
end

-- ============================================================ auto-reload

local function watchTick()
  watchEvent = scheduleEvent(watchTick, AUTO_RELOAD_INTERVAL)
  if not targetPath then return end

  local time = g_resources.getFileTime(targetPath)
  if time > targetFileTime then
    targetFileTime = time
    loadInto(targetPath, selectedPath)
  end
end

function setAutoReload(enabled)
  removeEvent(watchEvent)
  watchEvent = nil
  if enabled then
    watchTick()
    status('Auto-reload on (' .. AUTO_RELOAD_INTERVAL .. 'ms).')
  else
    status('Auto-reload off.')
  end
end

function setDebugBoxes(enabled)
  g_ui.setDebugBoxesDrawing(enabled)
end

-- ============================================================ drag / resize

-- Which edges the widget anchors, read from the file (the widget exposes no
-- anchor getters). Decides whether moving changes margin-left or margin-right.
local function anchorFlags()
  local flags = {}
  if not currentNode then return flags end
  for _, prop in ipairs(Otml.properties(currentNode)) do
    if prop.tag:starts('anchors.') then
      local edge = prop.tag:sub(9)
      flags[edge] = true
      if edge == 'fill' then
        flags.left, flags.right, flags.top, flags.bottom = true, true, true, true
      elseif edge == 'centerIn' then
        flags.left, flags.top = true, true
      end
    end
  end
  return flags
end

local function beginDrag(mode, mousePos)
  -- the click handler calls this right after selectWidget, which returns early
  -- (leaving no selection) when it is re-entered or the widget is already gone
  if not selectedWidget or selectedWidget:isDestroyed() then return false end

  local rect = selectedWidget:getRect()
  drag = {
    mode = mode,
    start = { x = mousePos.x, y = mousePos.y },
    marginLeft = selectedWidget:getMarginLeft(),
    marginRight = selectedWidget:getMarginRight(),
    marginTop = selectedWidget:getMarginTop(),
    marginBottom = selectedWidget:getMarginBottom(),
    width = rect.width,
    height = rect.height,
    anchors = anchorFlags(),
    moved = false,
  }
  return true
end

local function updateDrag(mousePos)
  if not drag or not selectedWidget or selectedWidget:isDestroyed() then return end

  local dx = mousePos.x - drag.start.x
  local dy = mousePos.y - drag.start.y
  if dx == 0 and dy == 0 then return end
  drag.moved = true

  if drag.mode == 'resize' then
    selectedWidget:setWidth(math.max(1, drag.width + dx))
    selectedWidget:setHeight(math.max(1, drag.height + dy))
  else
    local a = drag.anchors
    if a.left then selectedWidget:setMarginLeft(drag.marginLeft + dx) end
    if a.right then selectedWidget:setMarginRight(drag.marginRight - dx) end
    if a.top then selectedWidget:setMarginTop(drag.marginTop + dy) end
    if a.bottom then selectedWidget:setMarginBottom(drag.marginBottom - dy) end
  end

  local parent = selectedWidget:getParent()
  if parent then parent:updateLayout() end
  refreshSelectionVisuals()
end

-- On release, carries the new values into the panel (not saved yet).
local function finishDrag()
  if not drag then return end

  if drag.moved and selectedWidget and not selectedWidget:isDestroyed() then
    if drag.mode == 'resize' then
      local sizeProp = currentNode and Otml.findProperty(currentNode, 'size')
      if sizeProp then
        setPendingProperty('size', selectedWidget:getWidth() .. ' ' .. selectedWidget:getHeight())
      else
        setPendingProperty('width', tostring(selectedWidget:getWidth()))
        setPendingProperty('height', tostring(selectedWidget:getHeight()))
      end
      status('Resized. Check the panel and save.')
    else
      local a = drag.anchors
      local touched = false
      if a.left then setPendingProperty('margin-left', tostring(selectedWidget:getMarginLeft())); touched = true end
      if a.right then setPendingProperty('margin-right', tostring(selectedWidget:getMarginRight())); touched = true end
      if a.top then setPendingProperty('margin-top', tostring(selectedWidget:getMarginTop())); touched = true end
      if a.bottom then setPendingProperty('margin-bottom', tostring(selectedWidget:getMarginBottom())); touched = true end

      if touched then
        status('Moved through margins. Check the panel and save.')
      else
        status('This widget has no anchor in the file, so there is no margin to adjust.', true)
      end
    end
  end

  drag = nil
end

-- ============================================================ edit mode

function setPickMode(enabled)
  if captureLayer and not captureLayer:isDestroyed() then captureLayer:destroy() end
  captureLayer = nil
  drag = nil
  if hoverBox and not hoverBox:isDestroyed() then hoverBox:hide() end

  if not enabled then
    if resizeHandle and not resizeHandle:isDestroyed() then resizeHandle:hide() end
    status('Edit mode off. The preview responds to clicks again.')
    return
  end

  captureLayer = g_ui.createWidget('UIWidget', rootWidget)
  captureLayer:setId('otuiCaptureLayer')
  captureLayer:breakAnchors()
  captureLayer:addAnchor(AnchorTop, 'otuiStage', AnchorTop)
  captureLayer:addAnchor(AnchorRight, 'otuiStage', AnchorRight)
  captureLayer:addAnchor(AnchorBottom, 'otuiStage', AnchorBottom)
  captureLayer:addAnchor(AnchorLeft, 'otuiStage', AnchorLeft)
  captureLayer:setFocusable(false)

  captureLayer.onMousePress = function(_, mousePos, button)
    if button ~= MouseLeftButton then return false end
    if not stage or stage:isDestroyed() then return true end

    -- the resize handle takes priority over selection
    if selectedWidget and not selectedWidget:isDestroyed() then
      local rect = selectedWidget:getRect()
      if mousePos.x >= rect.x + rect.width - HANDLE_SIZE
        and mousePos.x <= rect.x + rect.width
        and mousePos.y >= rect.y + rect.height - HANDLE_SIZE
        and mousePos.y <= rect.y + rect.height then
        beginDrag('resize', mousePos)
        return true
      end
    end

    local widget = stage:recursiveGetChildByPos(mousePos, true)
    if widget then
      modules.dev_otui.selectWidget(widget)
      beginDrag('move', mousePos)
    else
      status('No widget at that point.')
    end
    return true
  end

  captureLayer.onMouseMove = function(_, mousePos)
    if not stage or stage:isDestroyed() then return false end

    if drag then
      updateDrag(mousePos)
      return true
    end

    hoverBox = ensureBox(hoverBox, '#ffcc00')
    moveBoxTo(hoverBox, stage:recursiveGetChildByPos(mousePos, true))
    if selectionBox and not selectionBox:isDestroyed() and selectionBox:isVisible() then
      selectionBox:raise()
    end
    if resizeHandle and not resizeHandle:isDestroyed() and resizeHandle:isVisible() then
      resizeHandle:raise()
    end
    return false
  end

  captureLayer.onMouseRelease = function(_, _, button)
    if button ~= MouseLeftButton then return false end
    finishDrag()
    return true
  end

  restackLayers()
  refreshSelectionVisuals()
  status('Edit mode: click to select, drag to move, green corner to resize.')
end

-- ============================================================ picker (files / elements)

local PICKER_LIMIT = 500

-- Always-available base styles: UIManager defines by itself any name starting
-- with "UI" (uimanager.cpp:535), so they never appear in the style files.
local BUILTIN_STYLES = {
  'UIWidget', 'UILabel', 'UIButton', 'UITextEdit', 'UICheckBox',
  'UIScrollArea', 'UIScrollBar', 'UIWindow', 'UIProgressBar', 'UIItem',
}

function closePicker()
  if pickerWindow and not pickerWindow:isDestroyed() then
    pickerWindow:destroy()
  end
  pickerWindow = nil
  pickerEntries = {}
  pickerCallback = nil
  pickerPreview = false
end

-- Instantiates the highlighted style inside the preview box, so you can see
-- what you are about to add instead of guessing from the name.
function previewPickerItem(styleName, origin)
  if not pickerWindow or not pickerPreview then return end

  local slot = pickerWindow:recursiveGetChildById('previewSlot')
  slot:destroyChildren()

  pickerWindow:recursiveGetChildById('previewName'):setText(styleName or '')
  pickerWindow:recursiveGetChildById('previewOrigin'):setText(origin or '')

  if not styleName then return end

  local problem = classProblem and classProblem(styleName)
  if problem then
    pickerWindow:recursiveGetChildById('previewOrigin'):setText(
      (origin or '') .. '\n(' .. problem .. ')')
    return
  end

  -- styles that need a specific parent (MiniWindow wants a MiniWindowContainer)
  -- cannot be built standalone; say so instead of leaving an empty box
  local ok, sample = pcall(function() return g_ui.createWidget(styleName, slot) end)
  if not ok or not sample then
    pickerWindow:recursiveGetChildById('previewOrigin'):setText(
      (origin or '') .. '\n(cannot be instantiated standalone)')
    return
  end

  sample:breakAnchors()
  sample:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  sample:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  if sample:getWidth() <= 1 then sample:setWidth(120) end
  if sample:getHeight() <= 1 then sample:setHeight(20) end

  pickerWindow:recursiveGetChildById('previewName'):setText(
    styleName .. '   ' .. sample:getWidth() .. 'x' .. sample:getHeight())
end

function filterPicker()
  if not pickerWindow then return end

  local list = pickerWindow:recursiveGetChildById('itemList')
  list:destroyChildren()

  local filter = pickerWindow:recursiveGetChildById('filterEdit'):getText():trim():lower()
  local shown = 0

  for _, entry in ipairs(pickerEntries) do
    if filter == '' or entry.label:lower():find(filter, 1, true) then
      local item = g_ui.createWidget('OtuiPickerItem', list)
      item:setText(entry.label)
      item.pickerValue = entry.value
      item.pickerOrigin = entry.origin
      item.onDoubleClick = function() modules.dev_otui.acceptPicker() end
      item.onFocusChange = function(self, focused)
        if focused then
          modules.dev_otui.previewPickerItem(self.pickerValue, self.pickerOrigin)
        end
      end
      shown = shown + 1
      if shown >= PICKER_LIMIT then break end
    end
  end

  local firstItem = list:getFirstChild()
  if firstItem then list:focusChild(firstItem) end

  local total = #pickerEntries
  local text = shown .. ' of ' .. total
  if shown >= PICKER_LIMIT then
    text = text .. ' (limited to ' .. PICKER_LIMIT .. ' - refine the search)'
  end
  pickerWindow:recursiveGetChildById('countLabel'):setText(text)
end

function acceptPicker()
  if not pickerWindow then return end

  local list = pickerWindow:recursiveGetChildById('itemList')
  local item = list:getFocusedChild() or list:getFirstChild()
  if not item then
    status('Pick an item from the list.', true)
    return
  end

  local value = item.pickerValue
  local callback = pickerCallback
  if callback then callback(value) end
end

local function openPicker(title, hint, entries, callback, withPreview)
  closePicker()

  pickerEntries = entries
  pickerCallback = callback
  pickerPreview = withPreview or false

  pickerWindow = g_ui.displayUI('dev_otui_picker')

  -- without a preview the list takes the whole width
  local previewBox = pickerWindow:recursiveGetChildById('previewBox')
  previewBox:setVisible(pickerPreview)
  if not pickerPreview then
    previewBox:setWidth(0)
  end
  pickerWindow:setText(title)
  pickerWindow:recursiveGetChildById('hintLabel'):setText(hint)
  pickerWindow:recursiveGetChildById('acceptBtn').onClick = function()
    modules.dev_otui.acceptPicker()
  end
  pickerWindow:recursiveGetChildById('cancelBtn').onClick = function()
    modules.dev_otui.closePicker()
  end

  local filterEdit = pickerWindow:recursiveGetChildById('filterEdit')
  filterEdit.onTextChange = function() modules.dev_otui.filterPicker() end
  filterEdit:focus()

  filterPicker()
  pickerWindow:raise()
end

local function collectOtuiFiles()
  if fileCache then return fileCache end

  local out = {}

  for _, root in ipairs(PROJECT_ROOTS) do
    local files = {}
    local ok, result = pcall(function()
      return g_resources.listDirectoryFiles(root, true, false, true)
    end)
    if ok and result then files = result end
    for _, file in ipairs(files) do
      if file:lower():ends('.otui') then
        table.insert(out, { label = file, value = file })
      end
    end
  end

  table.sort(out, function(a, b) return a.label < b.label end)
  fileCache = out
  return out
end

-- Builds the palette by reading the "Name < Base" definitions of style files.
local function collectStyles()
  if styleCache then return styleCache end

  local seen, out = {}, {}

  for _, name in ipairs(BUILTIN_STYLES) do
    seen[name] = true
    table.insert(out, {
      label = name .. '   (base)',
      value = name,
      origin = 'defined by UIManager itself'
    })
  end

  local files = {}
  pcall(function()
    files = g_resources.listDirectoryFiles('/data/styles', true, false, true)
  end)

  -- the open file itself may also define local styles
  if targetPath then table.insert(files, targetPath) end

  for _, file in ipairs(files) do
    if file:ends('.otui') then
      local okRead, text = pcall(function() return g_resources.readFileContents(file) end)
      if okRead and text then
        local okParse, parsed = pcall(function() return Otml.parse(text) end)
        if okParse and parsed then
          for _, def in ipairs(parsed.styleDefs) do
            local name = def.tag:match('^([%w_]+)%s*<')
            if name and not seen[name] then
              seen[name] = true
              table.insert(out, {
                label = name .. '   (' .. file .. ')',
                value = name,
                origin = file .. '  line ' .. def.line
              })
            end
          end
        end
      end
    end
  end

  table.sort(out, function(a, b) return a.label < b.label end)
  styleCache = out
  return out
end

-- Every anchor an edge can legally take. An edge only hooks to an edge of the
-- same axis: anchors.top accepts top/bottom/verticalCenter, never left.
local VERTICAL_EDGES = { 'top', 'bottom', 'verticalCenter' }
local HORIZONTAL_EDGES = { 'left', 'right', 'horizontalCenter' }

local function anchorEntries()
  local out = {}

  table.insert(out, {
    label = 'anchors.fill   <-   parent          (fills the parent area)',
    value = { key = 'anchors.fill', value = 'parent' },
  })
  table.insert(out, {
    label = 'anchors.centerIn   <-   parent      (centers in the parent)',
    value = { key = 'anchors.centerIn', value = 'parent' },
  })

  -- targets: the parent, the neighbours, and every sibling that has an id
  local targets = { 'parent', 'prev', 'next' }
  if currentNode and currentNode.parent then
    for _, sibling in ipairs(Otml.widgetChildren(currentNode.parent)) do
      if sibling ~= currentNode then
        local idProp = Otml.findProperty(sibling, 'id')
        if idProp and idProp.value and idProp.value ~= '' then
          table.insert(targets, idProp.value)
        end
      end
    end
  end

  local edges = {
    { 'top', VERTICAL_EDGES }, { 'bottom', VERTICAL_EDGES },
    { 'verticalCenter', VERTICAL_EDGES },
    { 'left', HORIZONTAL_EDGES }, { 'right', HORIZONTAL_EDGES },
    { 'horizontalCenter', HORIZONTAL_EDGES },
  }

  for _, edge in ipairs(edges) do
    for _, target in ipairs(targets) do
      for _, targetEdge in ipairs(edge[2]) do
        table.insert(out, {
          label = 'anchors.' .. edge[1] .. '   <-   ' .. target .. '.' .. targetEdge,
          value = { key = 'anchors.' .. edge[1], value = target .. '.' .. targetEdge },
        })
      end
    end
  end

  return out
end

function editAnchors()
  if not selectedWidget or not currentNode then
    status('Select a widget first.', true)
    return
  end

  local hint = 'Type an edge to filter, e.g. "top". Siblings with an id are listed as targets.'
  openPicker('Anchor', hint, anchorEntries(), function(choice)
    closePicker()
    setPendingProperty(choice.key, choice.value)
    applyAll()
    drawGuides()
    status('Anchor set: ' .. choice.key .. ': ' .. choice.value ..
      '. Still a preview - use "Save to file" to persist.')
  end, false)
end

function browseFiles()
  local entries = collectOtuiFiles()
  if #entries == 0 then
    status('Found no .otui files.', true)
    return
  end

  openPicker('Open .otui', 'Double-click, or select and press "Use"', entries, function(path)
    closePicker()
    editorWindow:recursiveGetChildById('pathEdit'):setText(path)
    loadTarget()
  end, false)
end

-- Generates an id free in the file, like button1, button2...
local function suggestId(styleName)
  local base = styleName:gsub('^UI', ''):lower()
  local used = {}
  if doc and doc.root then
    local function walk(node)
      local idProp = Otml.findProperty(node, 'id')
      if idProp and idProp.value then used[idProp.value] = true end
      for _, child in ipairs(Otml.widgetChildren(node)) do walk(child) end
    end
    walk(doc.root)
  end

  local i = 1
  while used[base .. i] do i = i + 1 end
  return base .. i
end

local function insertElement(styleName)
  if not targetPath then
    status('Load a file first.', true)
    return
  end

  local parentRef = currentRef
  local parentSnapshot = currentNode or (doc and doc.root)
  local parentPath = (parentRef and parentRef.kind == 'widget') and parentRef.path or nil

  if not readDocument(targetPath) then
    status('Could not re-read the file.', true)
    return
  end

  local originalText = Otml.serialize(doc)

  -- With no selection the new element goes to the screen root. With one, a
  -- reference that no longer resolves means the file moved under us; falling
  -- back to the root here would quietly insert somewhere else entirely.
  local parentNode = resolveSameNode(doc, parentRef, parentSnapshot)

  if not parentNode then
    status('The selected parent changed or moved in the file. Nothing was written - ' ..
      'reload and pick it again.', true)
    return
  end

  -- A widget with no anchor cannot be positioned or dragged, so it never goes
  -- in bare. Under a box layout the parent places its children and anchors are
  -- ignored, so there we add none.
  local props = {}
  local layoutProp = Otml.findProperty(parentNode, 'layout')
  local managed = layoutProp ~= nil

  if not managed then
    if #Otml.widgetChildren(parentNode) > 0 then
      -- stack below the previous sibling, the usual pattern in this codebase
      props = {
        { 'anchors.top', 'prev.bottom' },
        { 'anchors.left', 'parent.left' },
        { 'margin-top', '4' },
      }
    else
      props = {
        { 'anchors.top', 'parent.top' },
        { 'anchors.left', 'parent.left' },
      }
    end
  end

  local newId = suggestId(styleName)
  local ok, err = Otml.addChildWidget(doc, parentNode, styleName, newId, props)
  if not ok then
    status('Could not insert: ' .. tostring(err), true)
    return
  end

  local okWrite, result = persistText(targetPath, Otml.serialize(doc), originalText)
  if not okWrite then
    status(result, true)
    readDocument(targetPath)
    return
  end

  targetFileTime = g_resources.getFileTime(targetPath)
  loadInto(targetPath, parentPath)

  local how = managed
    and ' (the parent has a layout, so it places the child)'
    or ' anchored to ' .. (props[1] and props[1][2] or 'parent')
  status(styleName .. ' #' .. newId .. ' added to ' .. (parentNode.tag or '?') .. how)
end

function addElement()
  if not targetPath then
    status('Load a file first.', true)
    return
  end

  local parentName = 'screen root'
  if selectedWidget and currentNode then
    parentName = currentNode.tag .. ' (selected)'
  elseif selectedWidget and not currentNode then
    status('The selected widget is not mapped in the file: ' .. tostring(nodeError), true)
    return
  end

  openPicker('Add element', 'Goes in as a child of: ' .. parentName,
    collectStyles(), function(styleName)
      closePicker()
      insertElement(styleName)
    end, true)
end

-- Deletes the selected widget from the file. Destructive and it takes the
-- children along, so it asks first; the .bak still covers a mistake.
local function deleteSelectedNode()
  if not targetPath then
    status('Load a file first.', true)
    return
  end

  local ref = currentRef
  local nodeSnapshot = currentNode
  if not ref or ref.kind ~= 'widget' then
    status('Select a widget of the tree first.', true)
    return
  end

  if not readDocument(targetPath) then
    status('Could not re-read the file.', true)
    return
  end

  local originalText = Otml.serialize(doc)
  local node = resolveSameNode(doc, ref, nodeSnapshot)
  if not node then
    status('The selected widget changed or moved in the file. Nothing was removed - ' ..
      'reload and pick it again.', true)
    return
  end

  if node == doc.root then
    status('Cannot remove the main widget: the file would have no screen.', true)
    return
  end

  local ok, err = Otml.removeNode(doc, node)
  if not ok then
    status('Could not remove: ' .. tostring(err), true)
    readDocument(targetPath)
    return
  end

  local okWrite, result = persistText(targetPath, Otml.serialize(doc), originalText)
  if not okWrite then
    status(result, true)
    readDocument(targetPath)
    return
  end

  targetFileTime = g_resources.getFileTime(targetPath)
  selectedPath = nil
  loadInto(targetPath, nil)
  status('Widget removed. The previous file is at ' .. result .. '.bak')
end

function removeElement()
  if not selectedWidget or not currentNode then
    status('Select a widget first.', true)
    return
  end
  if currentRef and currentRef.kind == 'style' then
    status('Removing a style definition is not supported here; edit the file.', true)
    return
  end

  local label = currentNode.tag
  local idProp = Otml.findProperty(currentNode, 'id')
  if idProp and idProp.value then
    label = label .. ' #' .. idProp.value
  end

  local children = #Otml.widgetChildren(currentNode)
  local message = 'Remove ' .. label .. ' from the file?'
  if children > 0 then
    message = message .. '\n' .. children .. ' child widget(s) are removed with it.'
  end

  closeConfirmWindow()
  confirmWindow = displayGeneralBox('Remove element', message, {
    {
      text = 'Yes',
      callback = function()
        closeConfirmWindow()
        modules.dev_otui.confirmRemoveElement()
      end
    },
    {
      text = 'No',
      callback = function()
        closeConfirmWindow()
      end
    },
    anchor = AnchorHorizontalCenter
  })
end

-- kept public because the message box callback needs a reachable function
function confirmRemoveElement()
  deleteSelectedNode()
end

-- The id of a new screen comes from its file name. Everything that is not a
-- letter or a digit is dropped, which can leave nothing at all ("__.otui"), and
-- a widget written with an empty id cannot be looked up by name afterwards.
local function screenIdFromPath(path)
  local name = (path or ''):match('([^/]+)%.otui$') or ''
  name = name:gsub('[^%w]', '')
  if name == '' then return 'newScreen' end
  return name
end

function newScreen()
  local path = normalizePath(editorWindow:recursiveGetChildById('pathEdit'):getText())
  if not path then
    status('Type the path of the new file in the field above.', true)
    return
  end

  if g_resources.fileExists(path) then
    status('Already exists: ' .. path .. '. Pick another name so nothing is overwritten.', true)
    return
  end

  local id = screenIdFromPath(path)
  local text = Otml.skeleton('MainWindow', id, id)

  local ok, result = persistText(path, text, nil)
  if not ok then
    status(result, true)
    return
  end

  fileCache = nil -- the new file must show up under "Open..."
  g_settings.set('dev_otui_lastPath', path)
  selectedPath = nil
  loadInto(path, nil)
  status('Screen created at ' .. result .. '. Use "+ Element" to populate it.')
end

-- ============================================================ style gallery

local galleryWindow = nil
local galleryBuildEvent = nil

local MAX_SAMPLE_HEIGHT = 90 -- MainWindow is 200x200; rows stay readable

function closeGallery()
  if galleryBuildEvent then
    removeEvent(galleryBuildEvent)
    galleryBuildEvent = nil
  end
  if galleryWindow and not galleryWindow:isDestroyed() then
    galleryWindow:destroyChildren()
    galleryWindow:destroy()
  end
  galleryWindow = nil
end

-- Classes whose widgets cannot be built outside a real screen: their Lua setup
-- assumes children that only exist there. Building them here renders nothing
-- useful and floods the log, since the failing callback runs again on every
-- geometry change. UIStatsBar:reloadBorder indexes self.grade, which stays nil
-- without its horizontalGrade/verticalGrade children.
-- The menu classes are worse than noisy: UIPopupScrollMenu wires a scroll area
-- and a scroll bar to itself in create(), and standing alone that arrangement
-- never settles -- each layout pass schedules another through
-- UILayout::updateLater, and deferred events run inside the same poll, so the
-- client freezes with no error at all. A menu only exists while display() has
-- it on the root widget, so there is nothing to sample here anyway.
local UNSAFE_CLASSES = {
  UIStatsBar = 'needs its grade children; only works inside a real screen',
  UIPopupScrollMenu = 'a menu only exists while displayed; standalone it loops the layout',
  UIPopupMenu = 'a menu only exists while displayed; standalone it loops the layout',
}

local function fileIsThere(path)
  local ok, found = pcall(function() return g_resources.fileExists(path) end)
  return ok and found
end

-- image-source values are written without the extension, and the loader appends
-- '.png' when resolving them.
local function textureMissing(path)
  if not path or path == '' then return false end
  -- only absolute paths are ours to check; anything else is a colour or an alias
  if path:sub(1, 1) ~= '/' then return false end
  if fileIsThere(path) then return false end
  if not path:match('%.%w+$') and fileIsThere(path .. '.png') then return false end
  return true
end

-- Every texture source declared inside the block, states included, so a texture
-- referenced only under $hover is not missed.
local function textureSources(node, out)
  out = out or {}
  for _, child in ipairs(node.children) do
    if child.isProp and (child.tag == 'image-source' or child.tag == 'icon-source') then
      table.insert(out, { property = child.tag, path = child.value })
    elseif #child.children > 0 then
      textureSources(child, out)
    end
  end
  return out
end

-- The first missing texture this style would try to load. Walks up the bases,
-- but stops at the first level that declares an image-source of its own: an
-- override hides whatever the base pointed at, broken or not.
local function missingTexture(defs, name, seen)
  seen = seen or {}
  if seen[name] then return nil end
  seen[name] = true

  local entry = defs[name]
  if not entry then return nil end

  local declared = textureSources(entry.node)
  if #declared > 0 then
    for _, source in ipairs(declared) do
      if textureMissing(source.path) then return source end
    end
    return nil
  end

  return entry.base and missingTexture(defs, entry.base, seen) or nil
end

-- A style block cannot define another style inside it: OTML reads the nested
-- line as a child widget whose style name is the whole 'Name < Base' string,
-- which is never defined. data/styles/global_alias_test.otui does exactly this.
local function nestedStyleDef(node)
  for _, child in ipairs(node.children) do
    if not child.isProp and child.tag:find('<', 1, true) then
      return child.tag
    end
    local nested = nestedStyleDef(child)
    if nested then return nested end
  end
  return nil
end

-- Why a style cannot be sampled, or nil when it can. Checking up front avoids
-- the engine error that asking anyway would log.
classProblem = function(styleName)
  local ok, className = pcall(function() return g_ui.getStyleClass(styleName) end)
  if not ok or not className or className == '' then return nil end

  if UNSAFE_CLASSES[className] then
    return UNSAFE_CLASSES[className]
  end

  -- data/styles has real cases of a base that exists nowhere, e.g.
  -- VerticalBar < UIVerticalProgressBarSD
  local okGlobal, value = pcall(function() return _G[className] end)
  if okGlobal and value == nil then
    return 'class ' .. className .. ' is not registered'
  end
  if okGlobal and value ~= nil then
    local okCreate, create = pcall(function() return value.create end)
    if okCreate and create == nil then
      return 'class ' .. className .. ' cannot be created from OTUI'
    end
  end

  return nil
end

-- The full pre-check, run before the style is instantiated. Everything it
-- catches would otherwise reach the log as an engine error.
styleProblem = function(defs, name)
  local problem = classProblem(name)
  if problem then return problem end

  local entry = defs[name]
  if not entry then return nil end

  local nested = nestedStyleDef(entry.node)
  if nested then
    return 'declares a nested style (' .. nested .. '), which OTML does not accept'
  end

  local texture = missingTexture(defs, name)
  if texture then
    return texture.property .. ' ' .. texture.path .. ' is not in the data folder'
  end

  return nil
end

-- Renders every style of every file under /data/styles into one scrollable list,
-- grouped by file. This is the closest thing this project has to a component
-- gallery, and it is exact: the samples are drawn by the client's own renderer.
--
-- Styles that cannot render are not hidden: the row shows the reason without
-- asking the engine to instantiate an unsupported widget.
function openGallery()
  closeGallery()

  galleryWindow = g_ui.displayUI('dev_otui_gallery')
  local list = galleryWindow:recursiveGetChildById('galleryList')
  local listLayout = list:getLayout()
  if listLayout then listLayout:disableUpdates() end

  local files = {}
  pcall(function()
    files = g_resources.listDirectoryFiles('/data/styles', true, false, true)
  end)
  table.sort(files)

  local shown, failed, groups = 0, 0, 0

  -- First pass: parse every file and index the definitions by name. The index is
  -- what lets the pre-check follow a style's bases, which live in other files.
  local parsedFiles = {}
  local defs = {}

  for _, file in ipairs(files) do
    if file:ends('.otui') then
      local okRead, text = pcall(function() return g_resources.readFileContents(file) end)
      local parsed
      if okRead and text then
        local okParse, result = pcall(function() return Otml.parse(text) end)
        if okParse then parsed = result end
      end

      if parsed and #parsed.styleDefs > 0 then
        table.insert(parsedFiles, { file = file, doc = parsed })
        for _, def in ipairs(parsed.styleDefs) do
          local name, base = def.tag:match('^([%w_]+)%s*<%s*([%w_]+)')
          -- last definition wins, the same rule the engine applies
          if name then defs[name] = { node = def, base = base, file = file } end
        end
      end
    end
  end

  local countLabel = galleryWindow:recursiveGetChildById('galleryCount')

  local function renderStyle(file, def)
    local name, base = def.tag:match('^([%w_]+)%s*<%s*([%w_]+)')
    if not name then return end

    local row = g_ui.createWidget('OtuiGalleryRow', list)
    local label = row:getChildById('styleName')
    local slot = row:getChildById('sampleSlot')
    label:setText(name .. '  <  ' .. (base or '?'))

    local problem = styleProblem(defs, name)
    local ok, sample

    if not problem then
      -- styles needing a specific parent (MiniWindow wants a
      -- MiniWindowContainer) throw here: report, do not crash
      ok, sample = pcall(function() return g_ui.createWidget(name, slot) end)
    end

    if ok and sample and not sample:isDestroyed() then
      sample:breakAnchors()
      sample:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      sample:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      if sample:getWidth() <= 1 then sample:setWidth(120) end
      if sample:getHeight() <= 1 then sample:setHeight(18) end

      local height = math.min(sample:getHeight(), MAX_SAMPLE_HEIGHT)
      row:setHeight(math.max(26, height + 6))
      shown = shown + 1
    else
      -- a half-built widget may have been left behind before the throw
      slot:destroyChildren()

      local reason = problem or 'needs a specific parent or setup'

      label:setColor('#ff8080')
      label:setText(name .. '  <  ' .. (base or '?') .. '   (' .. reason .. ')')
      label:setTooltip(name .. ': ' .. reason)
      failed = failed + 1
    end
  end

  local function finish()
    if listLayout then
      listLayout:enableUpdates()
      listLayout:update()
    end

    countLabel:setText(
      shown .. ' rendered in ' .. groups .. ' files   |   ' .. failed .. ' skipped')

    status('Style gallery: ' .. shown .. ' live samples, ' .. failed ..
      ' unavailable style(s) skipped safely.')
  end

  -- Second pass: one sample per frame.
  --
  -- Building everything inside a single call means the engine lays out the ~250
  -- samples in one pass, after this function has already returned: the client
  -- has nothing on screen while it does that, and a style whose
  -- onGeometryChange keeps re-triggering locks it there with no clue why. One
  -- sample per frame keeps the window drawn throughout, and the style being
  -- built is named before it is built, so a lock-up names its own cause.
  local queue = {}
  for _, item in ipairs(parsedFiles) do
    table.insert(queue, { header = item })
    for _, def in ipairs(item.doc.styleDefs) do
      table.insert(queue, { file = item.file, def = def })
    end
  end

  local index = 1

  local function step()
    galleryBuildEvent = nil
    if not galleryWindow or galleryWindow:isDestroyed() then return end

    local entry = queue[index]
    if not entry then
      finish()
      return
    end

    if entry.header then
      local header = g_ui.createWidget('OtuiGalleryHeader', list)
      header:setText(entry.header.file .. '   (' .. #entry.header.doc.styleDefs .. ')')
      groups = groups + 1
    else
      -- one style blowing up must not take the rest of the build with it: the
      -- error would leave the next frame unscheduled and the list half built
      local ok, err = pcall(renderStyle, entry.file, entry.def)
      if not ok then
        failed = failed + 1
        g_logger.warning('[dev_otui] Could not render ' .. entry.def.tag ..
          ' from ' .. entry.file .. ': ' .. tostring(err))
      end
    end

    countLabel:setText(string.format('building %d/%d', index, #queue))
    index = index + 1
    galleryBuildEvent = scheduleEvent(step, 1)
  end

  -- the editor raises its own layers when it reloads a file, so the gallery
  -- makes its own state explicit instead of relying on creation order
  galleryWindow:show()
  galleryWindow:raise()
  galleryWindow:focus()

  countLabel:setText('building...')
  status('Style gallery: building ' .. #queue .. ' entries...')

  -- the first file waits a frame too, so the empty window is drawn first
  galleryBuildEvent = scheduleEvent(step, 1)
end

-- ============================================================ self test
-- Run in the terminal (Ctrl+T):  modules.dev_otui.selfTest()
-- Validates the parser before you trust it to write your files.

local SAMPLE = table.concat({
  '// top comment',
  'MyStyle < Button',
  '  height: 20',
  '',
  'Window',
  '  id: win',
  '  size: 220 500',
  '',
  '  Button',
  '    id: b1',
  '    height: 22',
  '    anchors.top: parent.top',
  '',
  '  Panel',
  '    id: p1',
  '    layout:',
  '      type: verticalBox',
  '      spacing: 2',
  '',
}, '\n')

function selfTest()
  local hadEditorWindow = editorWindow and not editorWindow:isDestroyed()
  if not ensureEditorWindow() then
    print('[dev_otui] selfTest FAILED: editor window could not be created')
    return false
  end

  local failures = {}
  local function check(cond, msg)
    if not cond then table.insert(failures, msg) end
  end

  local d = Otml.parse(SAMPLE)

  check(propertyRowOriginal('5', false) == '5',
    'an existing property must retain its original value')
  check(propertyRowOriginal('5', true) == nil,
    'a pending new property must be saved as absent from the original file')
  check(shouldRemovePropertyRow({ removed = true, pending = false }),
    'an existing removed property must produce a removal edit')
  check(not shouldRemovePropertyRow({ removed = true, pending = true }),
    'a pending property removed before save must produce no edit')

  check(Otml.serialize(d) == SAMPLE, 'round-trip changed the file')
  check(d.root and d.root.tag == 'Window', 'root should be Window')
  check(#d.styleDefs == 1, 'there should be 1 style definition')

  local kids = Otml.widgetChildren(d.root)
  check(#kids == 2, 'Window should have 2 child widgets, has ' .. #kids)

  local sizeProp = Otml.findProperty(d.root, 'size')
  check(sizeProp and sizeProp.value == '220 500', 'size read incorrectly')

  local button, panel = kids[1], kids[2]
  check(button and button.tag == 'Button', 'first child should be Button')
  check(panel and panel.tag == 'Panel', 'second child should be Panel')

  local anchor = button and Otml.findProperty(button, 'anchors.top')
  check(anchor and anchor.value == 'parent.top', 'anchors.top read incorrectly')

  -- the content of "layout:" must not be mistaken for child widgets
  if panel then
    check(#Otml.widgetChildren(panel) == 0, 'content of layout: became a widget')
    local layout = Otml.findProperty(panel, 'layout')
    check(layout and #layout.children == 2, 'layout: block read incorrectly')
  end

  -- changing an existing property must not touch other lines
  local d2 = Otml.parse(SAMPLE)
  local b2 = Otml.widgetChildren(d2.root)[1]
  Otml.setProperty(d2, b2, 'height', '26')
  local out2 = Otml.serialize(d2)
  check(out2:find('\n    height: 26\n', 1, true) ~= nil, 'height was not changed')
  check(out2:find('\n  height: 20\n', 1, true) ~= nil, 'changed the style height by mistake')
  check(#Otml.parse(out2).lines == #d2.lines, 'line count changed without an insertion')

  -- inserting a new property: goes after the last one, with the block indentation
  local d3 = Otml.parse(SAMPLE)
  local b3 = Otml.widgetChildren(d3.root)[1]
  Otml.setProperty(d3, b3, 'margin-top', '4')
  local out3 = Otml.serialize(d3)
  check(out3:find('    anchors.top: parent.top\n    margin-top: 4\n', 1, true) ~= nil,
    'insertion landed in the wrong place')

  -- removing a property
  local d4 = Otml.parse(SAMPLE)
  local b4 = Otml.widgetChildren(d4.root)[1]
  Otml.removeProperty(d4, b4, 'height')
  local out4 = Otml.serialize(d4)
  check(out4:find('    height: 22', 1, true) == nil, 'height was not removed')
  check(out4:find('    id: b1', 1, true) ~= nil, 'removed too many lines')

  -- removing a composite block takes its children along
  local d5 = Otml.parse(SAMPLE)
  local p5 = Otml.widgetChildren(d5.root)[2]
  Otml.removeProperty(d5, p5, 'layout')
  local out5 = Otml.serialize(d5)
  check(out5:find('verticalBox', 1, true) == nil, 'leftover content from the removed block')
  check(out5:find('    id: p1', 1, true) ~= nil, 'removed too many lines in the block')

  -- inserting a child widget at the end of the parent block
  local d6 = Otml.parse(SAMPLE)
  Otml.addChildWidget(d6, d6.root, 'Label', 'meuLabel')
  local out6 = Otml.serialize(d6)
  check(out6:find('  Label\n    id: meuLabel', 1, true) ~= nil, 'new widget formatted incorrectly')
  local reparsed6 = Otml.parse(out6)
  check(#Otml.widgetChildren(reparsed6.root) == 3, 'new widget not recognised as a child')
  check(Otml.widgetChildren(reparsed6.root)[3].tag == 'Label', 'new widget landed in the wrong position')

  -- inserting inside a child respects that level's indentation
  local d7 = Otml.parse(SAMPLE)
  local panel7 = Otml.widgetChildren(d7.root)[2]
  Otml.addChildWidget(d7, panel7, 'Button', 'dentro')
  local reparsed7 = Otml.parse(Otml.serialize(d7))
  local panelAfter = Otml.widgetChildren(reparsed7.root)[2]
  check(#Otml.widgetChildren(panelAfter) == 1, 'nested child was not recognised')
  check(#Otml.widgetChildren(reparsed7.root) == 2, 'nested child moved up a level')

  -- style library: no main widget, the showcase case
  local styleLib = table.concat({
    'Button < UIButton',
    '  color: #ffffff',
    '',
    'TabButton < UIButton',
    '  size: 22 23',
    '',
  }, '\n')
  local d9 = Otml.parse(styleLib)
  check(d9.root == nil, 'a style library should have no main widget')
  check(#d9.styleDefs == 2, 'should detect 2 style definitions, found ' .. #d9.styleDefs)
  check(d9.styleDefs[1].tag:match('^([%w_]+)%s*<') == 'Button', 'style name extracted incorrectly')
  check(Otml.findProperty(d9.styleDefs[2], 'size') ~= nil, 'style property was not read')

  -- removing a widget takes its whole block, and only that
  local d10 = Otml.parse(SAMPLE)
  local panel10 = Otml.widgetChildren(d10.root)[2]
  Otml.removeNode(d10, panel10)
  local out10 = Otml.serialize(d10)
  check(out10:find('Panel', 1, true) == nil, 'removed widget left leftovers')
  check(out10:find('verticalBox', 1, true) == nil, 'block of the removed widget survived')
  check(out10:find('    id: b1', 1, true) ~= nil, 'removal ate a sibling widget')
  local reparsed10 = Otml.parse(out10)
  check(#Otml.widgetChildren(reparsed10.root) == 1, 'wrong child count after removal')
  check(reparsed10.root.tag == 'Window', 'removal damaged the root')

  -- removing a nested widget must not touch its parent
  local d11 = Otml.parse(SAMPLE)
  Otml.addChildWidget(d11, Otml.widgetChildren(d11.root)[1], 'Label', 'inner')
  d11 = Otml.parse(Otml.serialize(d11))
  local button11 = Otml.widgetChildren(d11.root)[1]
  Otml.removeNode(d11, Otml.widgetChildren(button11)[1])
  local reparsed11 = Otml.parse(Otml.serialize(d11))
  local buttonAfter = Otml.widgetChildren(reparsed11.root)[1]
  check(#Otml.widgetChildren(buttonAfter) == 0, 'nested widget was not removed')
  check(Otml.findProperty(buttonAfter, 'height') ~= nil, 'removal ate a parent property')
  check(#Otml.widgetChildren(reparsed11.root) == 2, 'removal changed the root child count')

  -- Trailing indented comments and blank lines belong to the preceding block.
  local trailingBlock = Otml.parse(table.concat({
    'Window',
    '  Panel',
    '    id: panel',
    '    // belongs to panel',
    '',
    '  Label',
    '    id: sibling',
    '',
  }, '\n'))
  local trailingPanel = Otml.widgetChildren(trailingBlock.root)[1]
  check(Otml.lastLineOf(trailingPanel) == 5,
    'trailing comment and blank line were not attached to the widget block')
  Otml.removeNode(trailingBlock, trailingPanel)
  local trailingRemoved = Otml.serialize(trailingBlock)
  check(not trailingRemoved:find('belongs to panel', 1, true),
    'removing a widget left its trailing comment behind')
  check(trailingRemoved:find('id: sibling', 1, true) ~= nil,
    'removing a commented block damaged its sibling')

  local trailingRoot = Otml.parse(table.concat({
    'Window',
    '  Panel',
    '    id: panel',
    '  // keep before inserted child',
    '',
  }, '\n'))
  Otml.addChildWidget(trailingRoot, trailingRoot.root, 'Label', 'added')
  local trailingInserted = Otml.serialize(trailingRoot)
  check(trailingInserted:find(
    '  // keep before inserted child\n\n  Label\n    id: added', 1, true) ~= nil,
    'new widget was inserted before a trailing parent comment')

  -- a new widget must come in with anchors, otherwise it cannot be positioned
  local d12 = Otml.parse(SAMPLE)
  Otml.addChildWidget(d12, d12.root, 'Label', 'anchored', {
    { 'anchors.top', 'prev.bottom' },
    { 'anchors.left', 'parent.left' },
  })
  local reparsed12 = Otml.parse(Otml.serialize(d12))
  local added = Otml.widgetChildren(reparsed12.root)[3]
  check(added and added.tag == 'Label', 'anchored widget was not added')
  if added then
    local top = Otml.findProperty(added, 'anchors.top')
    check(top and top.value == 'prev.bottom', 'anchor was not written')
    check(#Otml.widgetChildren(added) == 0, 'anchor lines became child widgets')
    check(added.indent == 2, 'anchored widget landed at the wrong indentation')
  end

  -- the new-screen skeleton must be parseable
  local d8 = Otml.parse(Otml.skeleton('MainWindow', 'myScreen', 'My Screen'))
  check(d8.root and d8.root.tag == 'MainWindow', 'skeleton has no main widget')
  check(Otml.findProperty(d8.root, 'id') ~= nil, 'skeleton has no id')
  check(Otml.skeleton('MainWindow', 'quoted', "Player's Window"):find(
    "  !text: 'Player\\'s Window'", 1, true) ~= nil,
    'skeleton did not escape an apostrophe in the title')

  -- the id of a new screen comes from the file name and must stay usable
  check(screenIdFromPath('/modules/game_idle/idle_panel.otui') == 'idlepanel',
    'punctuation should be stripped out of the id')
  check(screenIdFromPath('/x/MyWindow.otui') == 'MyWindow',
    'an already valid name should pass through unchanged')
  check(screenIdFromPath('/x/__.otui') == 'newScreen',
    'a name with no letters or digits needs a fallback id')
  check(screenIdFromPath('') == 'newScreen', 'an empty path needs a fallback id')
  check(Otml.parse(Otml.skeleton('MainWindow', screenIdFromPath('/x/__.otui'), 'x')).root ~= nil,
    'the skeleton built from a fallback id must still parse')

  -- A file reference is a path of child indices: it always resolves, even after
  -- someone reorders the file. Identity is what keeps a save off the wrong node.
  local beforeEdit = Otml.parse(table.concat({
    'Window', '  Button', '    id: ok', '  Label', '    id: cancel', '',
  }, '\n'))
  local afterEdit = Otml.parse(table.concat({
    'Window', '  Label', '    id: cancel', '  Button', '    id: ok', '',
  }, '\n'))
  local firstChild = { kind = 'widget', path = { 1, 1 } }

  local nodeBefore = resolveRef(beforeEdit, firstChild)
  local nodeAfter = resolveRef(afterEdit, firstChild)
  check(nodeBefore and nodeBefore.tag == 'Button', 'the reference should resolve to the Button')
  check(nodeAfter and nodeAfter.tag == 'Label', 'the same path should now land on the Label')
  check(not sameNodeIdentity(nodeBefore, nodeAfter),
    'a reordered file must not be treated as the same node')
  check(sameNodeIdentity(nodeBefore, resolveRef(Otml.parse(Otml.serialize(beforeEdit)), firstChild)),
    'an unchanged file must still resolve to the same node')

  -- same style name, different id: still a different widget
  local renamed = Otml.parse(table.concat({
    'Window', '  Button', '    id: other', '',
  }, '\n'))
  check(not sameNodeIdentity(nodeBefore, resolveRef(renamed, firstChild)),
    'a widget with another id must not be treated as the same node')
  check(not sameNodeIdentity(nodeBefore, nil), 'an unresolved reference is never the same node')

  -- A click selects and then starts a drag; when the selection does not happen
  -- the drag must decline instead of indexing a nil widget.
  local keepSelected, keepDrag = selectedWidget, drag
  selectedWidget, drag = nil, nil
  local dragOk, dragStarted = pcall(beginDrag, 'move', { x = 0, y = 0 })
  check(dragOk, 'beginDrag must not error without a selected widget')
  check(dragStarted == false, 'beginDrag must refuse without a selected widget')
  check(drag == nil, 'beginDrag must not leave a drag in progress')
  selectedWidget, drag = keepSelected, keepDrag

  -- Closing the preview must not leave a stale reason behind: a later save
  -- would report why the *previous* widget could not be mapped.
  local keepNode, keepError, keepRef = currentNode, nodeError, currentRef
  currentNode, nodeError, currentRef = {}, 'stale reason', {}
  clearNodeSelection()
  check(currentNode == nil and nodeError == nil and currentRef == nil,
    'clearNodeSelection must reset all three, nodeError included')
  currentNode, nodeError, currentRef = keepNode, keepError, keepRef

  -- A read failure must reach the user. readDocument writes the module's `doc`,
  -- so the current one is put back before returning.
  local savedDoc = doc
  check(readDocument('/dev_otui/__no_such_file__.otui') == false,
    'readDocument should return false for a missing file')
  check(doc == nil, 'readDocument should clear the document when it fails')
  local said = editorWindow
    and editorWindow:recursiveGetChildById('statusLabel'):getText() or ''
  check(said:find('__no_such_file__', 1, true) ~= nil,
    'a read failure must be reported, status said: ' .. said)
  doc = savedDoc

  -- Re-resolving by index is not enough for insert/delete. A reorganized file
  -- must leave its bytes untouched when the selected identity moved.
  local reorganizedText = Otml.serialize(afterEdit)
  local insertParent = resolveSameNode(afterEdit, firstChild, nodeBefore)
  check(insertParent == nil, 'insert must reject a different parent at the same index')
  if insertParent then Otml.addChildWidget(afterEdit, insertParent, 'Label', 'wrong') end
  check(Otml.serialize(afterEdit) == reorganizedText,
    'refused insert changed the reorganized file')

  local deleteNode = resolveSameNode(afterEdit, firstChild, nodeBefore)
  check(deleteNode == nil, 'delete must reject a different widget at the same index')
  if deleteNode then Otml.removeNode(afterEdit, deleteNode) end
  check(Otml.serialize(afterEdit) == reorganizedText,
    'refused delete changed the reorganized file')

  -- Astra's UIManager creates non-unique child nodes inherited from styles;
  -- styles with child widgets are valid and insertion remains supported.
  local styleChildren = Otml.parse(table.concat({
    'Card < UIWidget', '  Label', '    id: title', '',
  }, '\n'))
  local styleRef = { kind = 'style', index = 1 }
  local styleSnapshot = styleChildren.styleDefs[1]
  local styleParent = resolveSameNode(
    Otml.parse(Otml.serialize(styleChildren)), styleRef, styleSnapshot)
  check(styleParent ~= nil, 'an unchanged style definition should remain a valid parent')
  if styleParent then
    Otml.addChildWidget(styleChildren, styleChildren.styleDefs[1], 'Button', 'action')
    local styleAfter = Otml.parse(Otml.serialize(styleChildren)).styleDefs[1]
    check(#Otml.widgetChildren(styleAfter) == 2,
      'a valid child inserted in a style definition was not preserved')
  end

  -- Project paths are deliberately narrower than readable resource paths.
  check(projectRelativePath('/modules/example/view.otui') == 'modules/example/view.otui',
    'modules path should be writable')
  check(projectRelativePath('/mods/example/view.otui') == 'mods/example/view.otui',
    'mods path should be writable')
  check(projectRelativePath('/data/styles/example.otui') == 'data/styles/example.otui',
    'data/styles path should be writable')
  check(projectRelativePath('/modules/../init.lua') == nil,
    'path traversal must be rejected')
  check(projectRelativePath('/images/not-ui.otui') == nil,
    'files outside the three project roots must be rejected')
  check(projectRelativePath('C:/modules/view.otui') == nil,
    'absolute filesystem paths must be rejected')

  local function fakeResources(options)
    options = options or {}
    local state = {
      files = { ['/modules/test/view.otui'] = 'original' },
      writes = {},
      confirmationFailed = false,
    }
    local resources = {}
    resources.fileExists = function(path) return state.files[path] ~= nil end
    resources.getWorkDir = function() return options.workDir == false and '' or 'C:/project' end
    resources.getRealDir = function()
      return options.outside and 'D:/archive' or 'C:/project'
    end
    resources.writeFileContentsToWorkDir = function(path, contents)
      table.insert(state.writes, path)
      if options.failBackup and path:ends('.bak') then return false end
      if options.failMain and not path:ends('.bak') then return false end
      state.files['/' .. path] = contents
      return true
    end
    resources.readFileContents = function(path)
      if options.confirmationMismatch and not state.confirmationFailed and
        state.files[path] ~= 'original' then
        state.confirmationFailed = true
        return 'mismatch'
      end
      return state.files[path]
    end
    return resources, state
  end

  local fake, fakeState = fakeResources()
  local persisted = persistTextWith(fake, '/modules/test/view.otui', 'changed', 'original')
  check(persisted and fakeState.files['/modules/test/view.otui'] == 'changed',
    'transactional save did not persist the expected bytes')
  check(fakeState.files['/modules/test/view.otui.bak'] == 'original',
    'transactional save did not preserve the backup bytes')

  local readOnly, readOnlyState = fakeResources({ workDir = false })
  local readOnlyOk = persistTextWith(readOnly, '/modules/test/view.otui', 'changed', 'original')
  check(not readOnlyOk and #readOnlyState.writes == 0 and
    readOnlyState.files['/modules/test/view.otui'] == 'original',
    'read-only mode must refuse without changing the file')

  local outside, outsideState = fakeResources({ outside = true })
  local outsideOk = persistTextWith(outside, '/modules/test/view.otui', 'changed', 'original')
  check(not outsideOk and #outsideState.writes == 0 and
    outsideState.files['/modules/test/view.otui'] == 'original',
    'a resource outside the workdir must remain unchanged')

  local backupFail, backupFailState = fakeResources({ failBackup = true })
  local backupOk = persistTextWith(backupFail, '/modules/test/view.otui', 'changed', 'original')
  check(not backupOk and #backupFailState.writes == 1 and
    backupFailState.files['/modules/test/view.otui'] == 'original',
    'backup failure must stop before writing the target')

  local writeFail, writeFailState = fakeResources({ failMain = true })
  local writeOk = persistTextWith(writeFail, '/modules/test/view.otui', 'changed', 'original')
  check(not writeOk and writeFailState.files['/modules/test/view.otui'] == 'original',
    'main write failure must preserve the original')

  local confirmFail, confirmFailState = fakeResources({ confirmationMismatch = true })
  local confirmOk = persistTextWith(confirmFail, '/modules/test/view.otui', 'changed', 'original')
  check(not confirmOk and confirmFailState.files['/modules/test/view.otui'] == 'original',
    'confirmation failure must restore the original')

  if #failures == 0 then
    print('[dev_otui] selfTest: OK (all checks passed)')
    status('selfTest: OK')
  else
    print('[dev_otui] selfTest FAILED:')
    for _, msg in ipairs(failures) do print('  - ' .. msg) end
    status('selfTest failed on ' .. #failures .. ' check(s) - see the terminal', true)
  end

  local passed = #failures == 0
  if not hadEditorWindow then closeEditor() end
  return passed
end

-- ============================================================ lifecycle

closeConfirmWindow = function()
  if confirmWindow and not confirmWindow:isDestroyed() then
    confirmWindow:destroy()
  end
  confirmWindow = nil
end

local function destroyEditorOverlays()
  clearGuides()
  for _, widget in ipairs({ selectionBox, hoverBox, resizeHandle, captureLayer }) do
    if widget and not widget:isDestroyed() then widget:destroy() end
  end
  selectionBox, hoverBox, resizeHandle, captureLayer = nil, nil, nil, nil
end

local function clearEditorState()
  removeEvent(watchEvent)
  watchEvent = nil
  if editorWindow and not editorWindow:isDestroyed() then
    for _, id in ipairs({ 'autoReloadCheck', 'debugBoxesCheck', 'guidesCheck', 'pickCheck' }) do
      local check = editorWindow:recursiveGetChildById(id)
      if check and check:isChecked() then check:setChecked(false) end
    end
  end
  closePicker()
  closeGallery()
  closeConfirmWindow()
  closeStage()
  destroyEditorOverlays()
  g_ui.setDebugBoxesDrawing(false)

  targetPath = nil
  targetFileTime = 0
  selectedWidget = nil
  selectedPath = nil
  currentNode = nil
  currentRef = nil
  nodeError = nil
  doc = nil
  drag = nil
  guides = {}
  guidesEnabled = false
  treeItems = {}
  propRows = {}
  pickerEntries = {}
  pickerCallback = nil
  pickerPreview = false
  fileCache = nil
  styleCache = nil
  showcaseMode = false
  showcaseStyleIndex = {}
  selecting = false
end

ensureEditorWindow = function()
  if editorWindow and not editorWindow:isDestroyed() then return editorWindow end

  editorWindow = g_ui.displayUI('dev_otui')
  if not editorWindow then
    g_logger.warning('[dev_otui] Could not create the editor window.')
    return nil
  end
  editorWindow:hide()

  local saved = g_settings.getString('dev_otui_lastPath')
  if saved and saved ~= '' then
    editorWindow:recursiveGetChildById('pathEdit'):setText(saved)
  end
  return editorWindow
end

function closeEditor()
  clearEditorState()
  if editorWindow and not editorWindow:isDestroyed() then editorWindow:hide() end
  if topButton and not topButton:isDestroyed() then topButton:setOn(false) end
end

function toggle()
  local window = ensureEditorWindow()
  if not window then return end
  if window:isVisible() then
    closeEditor()
    return
  end

  window:show()
  restackLayers()
  window:focus()
  if topButton and not topButton:isDestroyed() then topButton:setOn(true) end
end

function init()
  local existingButton = modules.client_topmenu.getButton('otuiEditorButton')
  if existingButton then existingButton:destroy() end

  topButton = modules.client_topmenu.addRightToggleButton(
    'otuiEditorButton', tr('OTUI Editor'), '/images/topbuttons/buttons', toggle)
  topButton:setOn(false)

  ensureEditorWindow()
  g_keyboard.bindKeyDown(EDITOR_HOTKEY, toggle)
end

function terminate()
  g_keyboard.unbindKeyDown(EDITOR_HOTKEY, toggle)
  clearEditorState()

  if topButton and not topButton:isDestroyed() then topButton:destroy() end
  if editorWindow and not editorWindow:isDestroyed() then editorWindow:destroy() end
  topButton = nil
  editorWindow = nil
end
