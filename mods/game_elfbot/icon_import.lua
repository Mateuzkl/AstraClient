-- Original [Icons] text import. Commands remain data and are compiled independently.
ElfBotIconImport={}
local I=ElfBotIconImport
local function trim(s) return s:match('^%s*(.-)%s*$') end
local function yes(s) return s:lower()=='yes' or s:lower()=='true' or s=='1' end
-- Built-in controls save appearance only; their controller identity is fixed.
local controls={
  waypoint={name='Cavebot',controller='CaveBot',id=3116,x=20},
  target={name='Target',controller='TargetBot',id=3264,x=94}
}
local iconTypes={Normal=true,Resize=true,Top=true,Bottom=true,Left=true,Right=true,Tile=true,Center=true,['Center X']=true,['Center Y']=true,Text=true}
local xModes={Absolute=true,Left=true,Right=true,Center=true,['From right']=true,Percent=true,Previous=true}
local yModes={Absolute=true,Top=true,Bottom=true,Center=true,['From bottom']=true,Percent=true,Previous=true}
local function numberIn(n,min,max) return type(n)=='number' and n>=min and n<=max end
local function control(key,positions,appearances)
  local preset=controls[key];local position=type(positions)=='table' and positions[key]
  local moved=type(position)=='table' and type(position.x)=='number' and type(position.y)=='number' and
    position.x==position.x and position.y==position.y and position.x>=0 and position.x<=4000 and position.y>=0 and position.y<=4000
  local function state(color)
    return {type='Resize',ids={preset.id,0,0,0},bkgType='Normal',bkgIds={0,0,0,0},
      text=preset.name,foreground=color,hover='#ffffff',xMode='Absolute',x=moved and position.x or preset.x,
      yMode=moved and 'Absolute' or 'From bottom',y=moved and position.y or 20}
  end
  local row={controlKey=key,builtinController=preset.controller,name=preset.name,enabled=true,size='Small',background=true,
    errors={},offState=state('#ff5a61'),onState=state('#55ff88')}
  local saved=type(appearances)=='table' and appearances[key]
  if type(saved)=='table' then
    if type(saved.name)=='string' and saved.name:match('%S') then row.name=saved.name end
    if type(saved.enabled)=='boolean' then row.enabled=saved.enabled end
    if type(saved.background)=='boolean' then row.background=saved.background end
    if saved.size=='Small' or saved.size=='Medium' or saved.size=='Large' then row.size=saved.size end
    for _,kind in ipairs({'offState','onState'}) do
      local source=saved[kind];local dest=row[kind]
      if type(source)=='table' then
        if iconTypes[source.type] then dest.type=source.type end
        if iconTypes[source.bkgType] then dest.bkgType=source.bkgType end
        if xModes[source.xMode] then dest.xMode=source.xMode end
        if yModes[source.yMode] then dest.yMode=source.yMode end
        for _,field in ipairs({'x','y'}) do if numberIn(source[field],-4000,4000) then dest[field]=source[field] end end
        if type(source.text)=='string' then dest.text=source.text end
        for _,field in ipairs({'foreground','hover'}) do
          if type(source[field])=='string' and source[field]:match('^#%x%x%x%x%x%x$') then dest[field]=source[field] end
        end
        for _,field in ipairs({'ids','bkgIds'}) do
          if type(source[field])=='table' then for i=1,4 do
            local id=source[field][i];if numberIn(id,0,65535) and id%1==0 then dest[field][i]=id end
          end end
        end
      end
    end
  end
  return row
end
function I.builtinControls(positions,appearances) return {control('waypoint',positions,appearances),control('target',positions,appearances)} end
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
