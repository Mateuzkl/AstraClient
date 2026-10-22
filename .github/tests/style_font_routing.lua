-- Exercise the production startup loader with bitmap and RmlUi font assets.
local files = {
    ['/fonts/'] = {'/fonts/default.otfont', '/fonts/rml'},
    ['/fonts/rml'] = {'/fonts/rml/Barlow-Regular.ttf', '/fonts/rml/fallback.otf',
        '/fonts/rml/OFL.txt', '/fonts/rml/nested.otfont'},
    ['/styles/'] = {'/styles/default.otui'},
    ['/particles/'] = {'/particles/default.otps'},
}
local fonts, styles, particles, cursors
g_resources = {
    directoryExists = function(path) return files[path] ~= nil end,
    listDirectoryFiles = function(path) return assert(files[path]) end,
    isFileType = function(path, extension) return path:sub(-#extension - 1) == '.' .. extension end,
}
g_fonts = {importFont = function(path)
    assert(path:sub(-7) == '.otfont', 'outline font sent to the OTUI bitmap loader: ' .. path)
    fonts[#fonts + 1] = path
end}
g_ui = {importStyle = function(path) styles[#styles + 1] = path end}
g_particles = {importParticle = function(path) particles[#particles + 1] = path end,
    terminate = function() end}
g_mouse = {loadCursors = function() cursors = cursors + 1 end}
g_logger = {warning = function(message) error(message) end}

dofile(arg[1] or 'modules/client_styles/styles.lua')
for _, nativeRmlUi in ipairs({false, true}) do
    g_rml = nativeRmlUi and {loadFontFace = function() error('RmlUi fonts must load lazily') end} or nil
    fonts, styles, particles, cursors = {}, {}, {}, 0
    init()
    assert(#fonts == 2, 'bitmap fonts were not preserved')
    assert(#styles == 1 and #particles == 1 and cursors == 1, 'startup resources regressed')
    importResources('fonts', 'ttf')
    importResources('fonts', 'otf')
    assert(#fonts == 2, 'unsupported font import reached the bitmap loader')
    terminate()
end
print('Style font routing: PASS (with and without RmlUi)')
