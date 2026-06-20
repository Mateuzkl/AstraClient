function init()
  local files
  local loaded_files = {}
  local layout = g_resources:getLayout()

  local style_files = {}
  if layout:len() > 0 then
    loaded_files = {}
    files = g_resources.listDirectoryFiles('/layouts/' .. layout .. '/styles')
    for _,file in pairs(files) do
      if g_resources.isFileType(file, 'otui') then
        table.insert(style_files, file)
        loaded_files[file] = true
      end
    end
  end

  files = g_resources.listDirectoryFiles('/data/styles')
  for _,file in pairs(files) do
    if g_resources.isFileType(file, 'otui') and not loaded_files[file] then
        table.insert(style_files, file)
    end
  end

  table.sort(style_files)
  for _,file in pairs(style_files) do
    if g_resources.isFileType(file, 'otui') then
      -- pcall so one malformed .otui doesn't abort all subsequent loads
      local success, err = pcall(g_ui.importStyle, '/styles/' .. file)
      if not success then
        g_logger.warning("Failed to load style: /styles/" .. file .. " (" .. tostring(err) .. ")")
      end
    end
  end

  if layout:len() > 0 then
    files = g_resources.listDirectoryFiles('/layouts/' .. layout .. '/fonts')
    loaded_files = {}
    for _,file in pairs(files) do
      if g_resources.isFileType(file, 'otfont') then
        -- pcall so one bad .otfont doesn't abort all subsequent font loads
        local fontPath = '/layouts/' .. layout .. '/fonts/' .. file
        local success, err = pcall(g_fonts.importFont, fontPath)
        if not success then
          g_logger.warning("Failed to load font: " .. fontPath .. " (" .. tostring(err) .. ")")
        end
        loaded_files[file] = true
      end
    end
  end

  files = g_resources.listDirectoryFiles('/data/fonts')
  -- sort for a deterministic font-atlas packing order (filesystem enumeration
  -- order is not stable across runs and made the atlas overflow nondeterministic)
  table.sort(files)
  for _,file in pairs(files) do
    if g_resources.isFileType(file, 'otfont') and not loaded_files[file] then
      -- pcall so one bad .otfont doesn't abort all subsequent font loads
      local success, err = pcall(g_fonts.importFont, '/data/fonts/' .. file)
      if not success then
        g_logger.warning("Failed to load font: /data/fonts/" .. file .. " (" .. tostring(err) .. ")")
      end
    end
  end

  g_mouse.loadCursors('/data/cursors/cursors')
  if layout:len() > 0 and g_resources.directoryExists('/layouts/' .. layout .. '/cursors/cursors') then
    g_mouse.loadCursors('/layouts/' .. layout .. '/cursors/cursors')
  end
end

function terminate()
end

