-- Minimal Markdown parser for the changelog popup. Returns a flat list of block
-- descriptors that changelog.lua turns into native OTUI Labels. No icons in-game
-- (gold heading + plain content); inline emphasis is flattened to plain text and
-- shortcode tokens (:new: etc.) are dropped.
--
-- Block shapes:
--   { kind='heading', level=1..6, text= }
--   { kind='bullet',  text= }
--   { kind='ol',      num=, text= }
--   { kind='quote',   text= }
--   { kind='code',    text= }   (all fenced lines joined by \n)
--   { kind='hr' }
--   { kind='text',    text= }
ChangelogMd = {}

-- Known shortcodes: the WEBSITE renders these as emoji; the in-game client just
-- drops them (no icons). Keep in sync with SHORTCODE_EMOJI in src/lib/changelog.ts.
ChangelogMd.KNOWN_SHORTCODES = {
  new = true, fix = true, balance = true, up = true, warn = true, star = true,
}

-- Flatten inline markdown to plain text (native Labels render raw text).
local function flatten(s)
  s = tostring(s or '')
  s = s:gsub('!%[(.-)%]%((.-)%)', '')      -- markdown images: drop
  s = s:gsub('%[(.-)%]%((.-)%)', '%1')      -- links: keep text
  s = s:gsub('%*%*(.-)%*%*', '%1')          -- bold
  s = s:gsub('__(.-)__', '%1')
  s = s:gsub('%*(.-)%*', '%1')              -- italic
  s = s:gsub('_(.-)_', '%1')
  s = s:gsub('`(.-)`', '%1')                -- inline code
  s = s:gsub(':([%w_]+):', function(c)      -- shortcodes: drop known, keep unknown
    return ChangelogMd.KNOWN_SHORTCODES[c:lower()] and '' or (':' .. c .. ':')
  end)
  s = s:gsub('%s+', ' ')
  s = s:gsub('^%s+', ''):gsub('%s+$', '')
  return s
end

local function isHr(line)
  local t = line:gsub('%s', '')
  return #t >= 3 and (t:match('^%-+$') or t:match('^%*+$') or t:match('^_+$')) ~= nil
end

function ChangelogMd.parse(md)
  md = tostring(md or '')
  md = md:gsub('\r\n', '\n'):gsub('\r', '\n')

  local lines = {}
  for line in (md .. '\n'):gmatch('(.-)\n') do
    table.insert(lines, line)
  end

  local blocks = {}
  local olCounter = 0
  local i = 1
  while i <= #lines do
    local line = lines[i]

    if line:match('^%s*```') then
      olCounter = 0
      local codeLines = {}
      i = i + 1
      while i <= #lines and not lines[i]:match('^%s*```') do
        table.insert(codeLines, lines[i])
        i = i + 1
      end
      table.insert(blocks, { kind = 'code', text = table.concat(codeLines, '\n') })
      i = i + 1 -- skip closing fence
    elseif line:match('^%s*$') then
      olCounter = 0
      i = i + 1
    elseif isHr(line) then
      olCounter = 0
      table.insert(blocks, { kind = 'hr' })
      i = i + 1
    elseif line:match('^#+%s') then
      olCounter = 0
      local hashes, text = line:match('^(#+)%s+(.*)$')
      table.insert(blocks, { kind = 'heading', level = math.min(#hashes, 6), text = flatten(text) })
      i = i + 1
    elseif line:match('^%s*[-*+]%s+') then
      olCounter = 0
      table.insert(blocks, { kind = 'bullet', text = flatten(line:match('^%s*[-*+]%s+(.*)$')) })
      i = i + 1
    elseif line:match('^%s*%d+%.%s+') then
      olCounter = olCounter + 1
      table.insert(blocks, { kind = 'ol', num = olCounter, text = flatten(line:match('^%s*%d+%.%s+(.*)$')) })
      i = i + 1
    elseif line:match('^%s*>%s?') then
      olCounter = 0
      table.insert(blocks, { kind = 'quote', text = flatten((line:gsub('^%s*>%s?', ''))) })
      i = i + 1
    else
      olCounter = 0
      table.insert(blocks, { kind = 'text', text = flatten(line) })
      i = i + 1
    end
  end

  return blocks
end
