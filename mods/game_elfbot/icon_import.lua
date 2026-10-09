-- Original [Icons] text import. Commands remain data and are compiled independently.
ElfBotIconImport={}
local I=ElfBotIconImport
local function trim(s) return s:match('^%s*(.-)%s*$') end
local function yes(s) return s:lower()=='yes' or s:lower()=='true' or s=='1' end
function I.color(value)
  if value and value:match('^#%x%x%x%x%x%x$') then return value end
  local n=tonumber(value) or 0
  -- ElfBot settings use Windows COLORREF: low byte red, then green, then blue.
  return string.format('#%02x%02x%02x',n%256,math.floor(n/256)%256,math.floor(n/65536)%256)
end
function I.parse(text,compile)
  assert(type(text)=='string' and #text<=1048576,'Icon file must be at most 1 MB')
  local rows,warnings={},{};local row,state;local section=false;local line=0
  for raw in (text..'\n'):gmatch('([^\n]*)\n') do
    line=line+1;raw=raw:gsub('\r$',''):gsub('^\239\187\191','')
    local heading=raw:match('^%s*%[([^%]]+)%]%s*$')
    if heading then section=trim(heading):lower()=='icons'
    elseif section then
      local key,value=raw:match('^([^:]+):%s?(.*)$')
      if key then
        key=trim(key)
        if key=='Name' then
          assert(#rows<512,'At most 512 icons can be imported')
          row={name=value,enabled=true,active=false,running=false,size='Small',background=true,offState={},onState={},sourceLine=line,commandLines={}}
          rows[#rows+1]=row;state=nil
        elseif row then
          if key=='State' then state=value:lower()=='active' and row.onState or row.offState
          elseif key=='Enabled' then row.enabled=yes(value)
          elseif key=='DrawAsBackground' then row.background=yes(value)
          elseif key=='Size' then row.size=value
          elseif key=='LeftCommand' then row.lclick=value;row.commandLines.lclick=line
          elseif key=='RightCommand' then row.rclick=value;row.commandLines.rclick=line
          elseif state then
            local fields={IconType='type',BkgType='bkgType',AlignX='xMode',AlignY='yMode',Text='text'}
            if fields[key] then state[fields[key]]=value
            elseif key=='PositionX' then state.x=tonumber(value) or 0
            elseif key=='PositionY' then state.y=tonumber(value) or 0
            elseif key=='TextColor' then state.foreground=I.color(value)
            elseif key=='HoverColor' then state.hover=I.color(value)
            elseif key=='IconIds' or key=='BkgIds' then
              local ids={};for n in value:gmatch('%d+') do ids[#ids+1]=tonumber(n) end
              while #ids<4 do ids[#ids+1]=0 end;state[key=='IconIds' and 'ids' or 'bkgIds']=ids
            end
          end
        end
      end
    end
  end
  assert(#rows>0,'No icon records found. Use Main Load for binary/JSON saves or command scripts; this importer requires [Icons] text with Name: entries')
  for _,icon in ipairs(rows) do
    icon.errors={}
    for _,side in ipairs({'lclick','rclick'}) do
      local script=icon[side]
      if script and script~='' and compile then
        local ok,err=pcall(compile,script)
        if not ok then icon.errors[side]=tostring(err);warnings[#warnings+1]=icon.name..' / '..(side=='lclick' and 'Left' or 'Right')..' (line '..(icon.commandLines[side] or icon.sourceLine)..'): '..tostring(err) end
      end
    end
  end
  return rows,warnings
end

-- Editable classic text representation for the Icons script window.
function I.serialize(rows)
  local lines={'[Icons]'}
  local function field(key,value) lines[#lines+1]=key..': '..tostring(value or ''):gsub('\r?\n',' | ') end
  for _,row in ipairs(rows or {}) do
    field('Name',row.name);field('Enabled',row.enabled~=false and 'yes' or 'no')
    field('Size',row.size or 'Small');field('DrawAsBackground',row.background~=false and 'yes' or 'no')
    field('LeftCommand',row.lclick);field('RightCommand',row.rclick)
    for _,kind in ipairs({'offState','onState'}) do
      local state=row[kind] or {};field('State',kind=='offState' and 'Inactive' or 'Active')
      field('IconType',state.type or 'Normal');field('IconIds',table.concat(state.ids or {0,0,0,0},','))
      field('BkgType',state.bkgType or 'Normal');field('BkgIds',table.concat(state.bkgIds or {0,0,0,0},','))
      field('AlignX',state.xMode or 'Absolute');field('AlignY',state.yMode or 'Absolute')
      field('PositionX',state.x or 0);field('PositionY',state.y or 0);field('Text',state.text)
      field('TextColor',state.foreground or '#000000');field('HoverColor',state.hover or state.foreground or '#000000')
    end
  end
  return table.concat(lines,'\n')
end
