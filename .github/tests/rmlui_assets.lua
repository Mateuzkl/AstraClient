-- Validate literal file textures in the shipped examples against real client assets.
local modules = {'client_rmldemo/rmldemo', 'client_rmlshowcase/showcase',
    'client_rmloptions/rmloptions', 'game_rmloutfit/rmloutfit', 'game_rmlminimap/rmlminimap',
    'game_rmlskilltree/skilltree'}
local references = 0
for _, module in ipairs(modules) do
    for _, extension in ipairs({'lua', 'rcss', 'rml'}) do
        local source = 'modules/' .. module .. '.' .. extension
        local file = assert(io.open(source, 'rb'), source)
        local content = file:read('*a')
        file:close()
        for path in content:gmatch('(/images/[^%s\'"%)]+%.png)') do
            local image = assert(io.open('data' .. path, 'rb'), source .. ': missing asset ' .. path)
            image:close()
            references = references + 1
        end
    end
end
assert(references > 0, 'no RmlUi texture references were checked')
print('RmlUi example assets: PASS (' .. references .. ' references)')
