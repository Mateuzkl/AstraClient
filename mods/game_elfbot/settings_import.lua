-- Original files are parsed as data; no imported file is executed as Lua.
ElfBotSettingsImport={}
local I=ElfBotSettingsImport
I.maxBytes=8*1024*1024
local function trim(s) return (s:gsub('^%s+',''):gsub('%s+$','')) end
local function yes(s) return s==true or s=='1' or tostring(s):lower()=='yes' or tostring(s):lower()=='true' end
local function clone(t)
  if type(t)~='table' then return t end
  local result={};for k,v in pairs(t) do result[k]=clone(v) end;return result
end
function I.read(path,resources)
  assert(type(path)=='string' and #path<=4096 and not path:find('%z'),'Invalid file path')
  path=trim(path):gsub('\\','/')
  assert(path~='' and not path:find('://',1,true),'Enter an ElfBot settings or script file path')
  if path:match('^%a:/') or path:sub(1,2)=='//' then
    assert(io and io.open,'This client cannot read external files; copy the file into elfbot/imports')
    local file,err=io.open(path,'rb');assert(file,'Cannot open file: '..tostring(err))
    local ok,text=pcall(file.read,file,I.maxBytes+1);file:close();assert(ok,text)
    assert(text and #text<=I.maxBytes,'ElfBot file exceeds 8 MB');return text
  end
  assert(not path:find('%.%.'),'Relative paths cannot contain ..')
  if path:sub(1,1)~='/' then path='/elfbot/imports/'..path end
  local text=resources.readFileContents(path)
  assert(type(text)=='string' and #text<=I.maxBytes,'ElfBot file exceeds 8 MB');return text
end
local vk={[8]='Backspace',[9]='Tab',[13]='Enter',[19]='Pause',[27]='Escape',[32]='Space',
 [33]='PageUp',[34]='PageDown',[35]='End',[36]='Home',[37]='Left',[38]='Up',[39]='Right',[40]='Down',
 [45]='Insert',[46]='Delete',[106]='*',[107]='+',[109]='-',[110]='.',[111]='/',
 [186]=';',[187]='=',[188]=',',[189]='-',[190]='.',[191]='/',[192]='`',[219]='[',[220]='\\',[221]=']',[222]="'"}
function I.key(code)
  local key=code%256;local flags=math.floor(code/256)
  if code==0 then return '' end
  local name=vk[key]
  if key>=48 and key<=90 then name=string.char(key)
  elseif key>=96 and key<=105 then name='Numpad'..(key-96)
  elseif key>=112 and key<=123 then name='F'..(key-111) end
  if not name or flags>7 then return nil end
  local parts={};if math.floor(flags/2)%2==1 then parts[#parts+1]='Ctrl' end
  if math.floor(flags/4)%2==1 then parts[#parts+1]='Alt' end
  if flags%2==1 then parts[#parts+1]='Shift' end
  parts[#parts+1]=name;return table.concat(parts,'+')
end
local function validated(row,compile,warnings,description)
  local ok,err=pcall(compile,row.script)
  if not ok then row.enabled=false;row.importError=tostring(err);warnings[#warnings+1]=description..': '..tostring(err) end
end
local function binary(text,compile)
  -- Fixed packed layout observed in the supplied original NG 4.5.9 profiles.
  assert(#text==903650,'Unsupported original binary settings version (expected 903650 bytes)')
  local function byte(offset) return text:byte(offset+1) end
  local function u32(offset) local a,b,c,d=text:byte(offset+1,offset+4);return a+b*256+c*65536+d*16777216 end
  local function i32(offset) local n=u32(offset);return n>=2147483648 and n-4294967296 or n end
  local function str(offset,size)
    local value=text:sub(offset+1,offset+size);local stop=value:find('\0',1,true)
    assert(stop,'Unterminated string at binary offset '..offset)
    value=value:sub(1,stop-1)
    assert(not value:find('[%z\1-\8\11\12\14-\31]'),'Invalid text at binary offset '..offset)
    return value
  end
  local patch={hotkeys={},shortkeys={},icons={}};local warnings={}
  -- DLL UI/runtime: 96 records, one key byte, one enabled byte, 512 command bytes.
  for index=0,95 do
    local off=0x15a8+index*514;local source=str(off+2,512)
    if trim(source)~='' then
      local code=byte(off)+byte(off+1)*256;local key=I.key(byte(off))
      local row={script=source,key=key or '',enabled=byte(off+1)~=0 and key~=nil,originalShortcut=code,sourceRecord=index+1}
      if not key then row.importError='Unmapped Win32 shortcut '..code;warnings[#warnings+1]=row.importError end
      validated(row,compile,warnings,'Hotkey '..(index+1));patch.hotkeys[#patch.hotkeys+1]=row
    end
  end
  -- Original Custom Shortkeys: 128 records at 0x10106b02, stride 0x222.
  for index=0,127 do
    local off=0x10106b02-0x100f9494+index*0x222
    local name,source=str(off,33),str(off+34,512)
    if trim(source)~='' then
      local row={key=name,script=source,enabled=byte(off+33)~=0,sourceRecord=index+1}
      if name=='' then row.enabled=false;warnings[#warnings+1]='Shortkey '..(index+1)..' has no command name' end
      validated(row,compile,warnings,'Shortkey '..(index+1));patch.shortkeys[#patch.shortkeys+1]=row
    end
  end
  patch.shortkeysEnabled=byte(0x10135279-0x100f9494)~=0
  patch.symbol=str(0x1013f327-0x100f9494,2)
  local types={[0]='Normal',[1]='Resize',[2]='Tile',[3]='Center',[4]='Center X',[8]='Top'}
  local aligns={'Absolute','Center','Right'}
  local function state(off)
    local kind,bkg=u32(off),u32(off+24)
    assert(types[kind] and types[bkg] and u32(off+48)==0 and u32(off+56)==0,'Unsupported binary icon state')
    local s={type=types[kind],bkgType=types[bkg],ids={},bkgIds={},
      foreground=ElfBotIconImport.color(tostring(u32(off+96))),hover=ElfBotIconImport.color(tostring(u32(off+4))),
      xMode=aligns[u32(off+48)+1],yMode=({'Absolute','Center','Bottom'})[u32(off+56)+1],x=i32(off+52),y=i32(off+60),text=str(off+64,32)}
    for i=1,4 do s.ids[i]=u32(off+4+i*4);s.bkgIds[i]=u32(off+28+i*4) end
    return s
  end
  for index=0,127 do
    local off=0x55f8c+index*4308;local name=str(off,68)
    if name~='' then
      assert(u32(off+68)<=1 and u32(off+72)<=1,'Invalid binary icon flags')
      local size=u32(off+4276);assert(size<=2,'Unsupported binary icon size')
      local row={name=name,enabled=u32(off+68)==1,background=u32(off+72)==1,size=({'Small','Medium','Large'})[size+1],
        lclick=str(off+76,2000),rclick=str(off+2076,2000),offState=state(off+4076),onState=state(off+4176),active=false,running=false,errors={},sourceRecord=index+1}
      for _,side in ipairs({'lclick','rclick'}) do
        if trim(row[side])~='' then local ok,err=pcall(compile,row[side]);if not ok then row.errors[side]=tostring(err);warnings[#warnings+1]='Icon '..name..' / '..side..': '..tostring(err) end end
      end
      patch.icons[#patch.icons+1]=row
    end
  end
  -- Original save handler 0x10006513..0x10006608 copies these controls into this block.
  local hiSpell,loSpell=str(0x105d,64),str(0x109d,64)
  local healingCount=(trim(hiSpell)~='' and 1 or 0)+(trim(loSpell)~='' and 1 or 0)
  patch.healing={hiSpell=hiSpell,loSpell=loSpell,hiMana=u32(1),hiHealth=u32(5),
    loMana=u32(0x10e1),loHealth=u32(0x10dd),uhHealth=u32(9),
    enabled=false,hiEnabled=false,loEnabled=false,uhEnabled=false,hpEnabled=false,mpEnabled=false,
    hpHealth=u32(0x10134e66-0x100f9494),mpMana=u32(0x1014f41a-0x100f9494),
    hpType='health',mpType='mana',paralysis=false,delay=1000}
  warnings[#warnings+1]='Healing spell and threshold fields decoded from the original save handler. Enable flags and potion selections are still under investigation; healing remains off.'
  patch.hotkeysEnabled=true;patch.iconsEnabled=byte(903564)==1
  warnings[#warnings+1]='Binary import supports the 96 hotkeys and all 128 icon records. Other binary settings (healing enable/type flags, HUD, aimbot, lists, targeting and cavebot) are not decoded and reset to empty/default values rather than carrying settings from another file.'
  warnings[#warnings+1]='Source records: '..#patch.hotkeys..' hotkeys, '..#patch.shortkeys..' shortkeys, '..#patch.icons..' icons. Zero means those original records are empty, not hidden by the UI.'
  return {format='Original NG binary (partial import)',replacement={},patch=patch,warnings=warnings,hotkeys=#patch.hotkeys,shortkeys=#patch.shortkeys,icons=#patch.icons,healing=healingCount}
end
-- Original NG separate profiles use bounded zero-run compression (0xfffffea0).
local function profile(text,path,compile)
  local kind=(path or ''):lower():match('%.(elf[ct])$')
  assert(kind,'Select the original .elfc or .elft file with its extension')
  local size=kind=='elfc' and 0xa1093 or 0x1102d
  local parts,length,i={},0,5
  local function append(value) length=length+#value;assert(length<=size,'Compressed profile exceeds its original structure size');parts[#parts+1]=value end
  while i<=#text do
    local token=text:byte(i);i=i+1
    if token>=192 then
      assert(i<=#text,'Truncated zero-run token');append(string.rep('\0',(token%64)*256+text:byte(i)));i=i+1
    else
      append(string.rep('\0',token%64));local count=({1,2,4})[math.floor(token/64)+1]
      assert(i+count-1<=#text,'Truncated profile literal');append(text:sub(i,i+count-1));i=i+count
    end
  end
  append(string.rep('\0',size-length));local raw=table.concat(parts)
  local function byte(off) return raw:byte(off+1) end
  local function word(off) return byte(off)+byte(off+1)*256 end
  local function u32(off) return word(off)+word(off+2)*65536 end
  local function str(off,n) local value=raw:sub(off+1,off+n);local stop=value:find('\0',1,true);assert(stop,'Unterminated profile text');return value:sub(1,stop-1) end
  local patch,warnings={},{}
  local result={patch=patch,warnings=warnings,hotkeys=0,shortkeys=0,icons=0}
  if kind=='elfc' then
    patch.waypoints={};local types={[1]='walk',[2]='rope',[3]='ladder',[4]='stand',[6]='shovel',[7]='node',[8]='lure'}
    for index=0,1023 do
      local off=index*48;local x,y,z=u32(off),u32(off+4),u32(off+8);local typ=word(off+44)
      -- Type zero marks an unused record, even if an old coordinate remains.
      if typ~=0 then
        assert(x<=65535 and y<=65535 and z<=15,'Invalid waypoint position')
        local label=str(off+12,32);if label~='' then patch.waypoints[#patch.waypoints+1]={'label',label} end
        if typ==5 then
          local actionIndex=word(off+46);assert(actionIndex<=128,'Invalid cavebot action reference')
          -- Zero is an empty action, not the first text slot or an out-of-bounds read.
          local source=actionIndex==0 and '' or str(0x21093+(actionIndex-1)*4096,4096)
          local ok,err=pcall(compile,source)
          if not ok then warnings[#warnings+1]='Action '..(index+1)..': '..tostring(err)..'. Source retained; following stops at this action until it is corrected.' end
          patch.waypoints[#patch.waypoints+1]={'elfaction',source,{x=x,y=y,z=z}}
        else assert(types[typ],'Unsupported original waypoint type '..typ);patch.waypoints[#patch.waypoints+1]={'elf'..types[typ],x..','..y..','..z} end
      end
    end
    result.waypoints=#patch.waypoints;result.format='Original NG cavebot profile (partial)'
    warnings[#warnings+1]='Waypoints imported; separate cavebot options, alerts and looting fields are not yet mapped.'
  else
    patch.targeting={monsters={}};local monsters=patch.targeting.monsters
    for index=0,127 do
      local off=index*320;local name=str(off,32)
      if name~='' then
        local rule={name=name,count=byte(off+33),loot=byte(off+32)~=0,alarm=byte(off+35)~=0,enabled=true,settings={}}
        for setting=0,3 do
          local pos=off+96+setting*56;local low,high=u32(pos+12),u32(pos+8)
          if high>0 then
            -- NG profiles use 101 as the upper sentinel for a full 0..100% range.
            assert(low<=100 and low<=high and high<=101,'Invalid targeting HP range')
            local stance=u32(pos+16);local attack=u32(pos+20);local mode=byte(pos+25)
            local mapped=({[0]='No Movement',[2]='Keep distance',[3]='Keep distance',[6]='Approach',[12]='Lure'})[stance] or 'No Movement'
            rule.settings[#rule.settings+1]={hpMin=low,hpMax=math.min(100,high),originalHpMax=high,danger=u32(pos),avoid=({[0]="Don't avoid",[1]='Avoid waves',[2]='Avoid beams'})[u32(pos+4)],stance=mapped,action='',fightMode=mode>0 and ((mode-1)%3+1) or nil,originalStance=stance,originalAttack=attack,originalRing=byte(pos+24)}
            if not ({[0]=true,[2]=true,[3]=true,[6]=true,[12]=true})[stance] or attack%64~=0 or byte(pos+24)~=0 then warnings[#warnings+1]=name..': original stance/spell/ring behavior needs further mapping; original values retained.' end
          end
        end
        monsters[#monsters+1]=rule
      end
    end
    result.targets=#monsters;result.format='Original NG targeting profile (partial)'
    warnings[#warnings+1]='Monster definitions and HP/settings imported; original selection weights, spell choices and some movement modes are not fully mapped.'
  end
  return result
end
function I.parse(text,compile,path)
  assert(type(text)=='string' and #text>0 and #text<=I.maxBytes,'ElfBot file must contain 1 byte to 8 MB')
  if text:sub(1,4)==string.char(160,254,255,255) then return profile(text,path,compile) end
  if text:find('\0',1,true) then return binary(text,compile) end
  text=text:gsub('^\239\187\191',''):gsub('\r\n','\n')
  local first=trim(text):sub(1,1)
  if first=='{' then
    local decoded=json.decode(text);assert(type(decoded)=='table' and type(decoded.elfbot)=='table','Expected a client ElfBot settings file')
    local d=decoded.elfbot;assert(type(d.hotkeys or {})=='table' and type(d.icons or {})=='table','Invalid ElfBot settings lists')
    local warnings={}
    for i,row in ipairs(d.hotkeys or {}) do assert(type(row)=='table' and type(row.script)=='string','Invalid hotkey');validated(row,compile,warnings,'Hotkey '..i) end
    for i,row in ipairs(d.shortkeys or {}) do assert(type(row)=='table' and type(row.script)=='string','Invalid shortkey');validated(row,compile,warnings,'Shortkey '..i) end
    return {format='client ElfBot JSON',replacement=d,warnings=warnings,hotkeys=#(d.hotkeys or {}),shortkeys=#(d.shortkeys or {}),icons=#(d.icons or {})}
  end
  local patch,warnings={},{ };local sections={};local section,row
  for line in (text..'\n'):gmatch('([^\n]*)\n') do
    local heading=line:match('^%s*%[([^%]]+)%]%s*$')
    if heading then section=heading:lower();sections[section]=true;row=nil
    elseif section=='hotkeys' or section=='shortkeys' then
      local key,value=line:match('^%s*([^:=]+)[:=]%s?(.*)$')
      if key then
        key=trim(key):lower();patch[section]=patch[section] or {}
        if key=='key' or key=='shortcut' or key=='name' then
          row={key=value,enabled=true,script=''};patch[section][#patch[section]+1]=row
        elseif key=='command' or key=='script' then
          if not row or row.script~='' then row={key='',enabled=true};patch[section][#patch[section]+1]=row end
          row.script=value
        elseif key=='enabled' then if row then row.enabled=yes(value) else patch[section..'Enabled']=yes(value) end
        elseif key=='symbol' and section=='shortkeys' then patch.symbol=value
        else warnings[#warnings+1]='Unsupported '..section..' field: '..key end
      end
    end
  end
  if next(sections) then
    for _,kind in ipairs({'hotkeys','shortkeys'}) do
      for index,entry in ipairs(patch[kind] or {}) do
        assert(trim(entry.script)~='','Empty '..kind..' command '..index)
        if kind=='shortkeys' then assert(entry.key~='','Shortkey needs a name') end
        validated(entry,compile,warnings,kind..' '..index)
      end
    end
    if sections.icons then local iconWarnings;patch.icons,iconWarnings=ElfBotIconImport.parse(text,compile);patch.iconsEnabled=true;for _,v in ipairs(iconWarnings) do warnings[#warnings+1]=v end end
    for name in pairs(sections) do if name~='icons' and name~='hotkeys' and name~='shortkeys' then warnings[#warnings+1]='Section ['..name..'] is not imported; existing values are kept' end end
    assert(next(patch),'No supported ElfBot sections found')
  else
    local rows={};local lines={};for line in text:gmatch('[^\n]+') do line=trim(line);if line~='' and not line:match('^;') and not line:match('^//') then lines[#lines+1]=line end end
    local separate=#lines>1;for _,line in ipairs(lines) do if not line:match('^[Aa][Uu][Tt][Oo]%s+%d+%s') then separate=false end end
    if not separate then lines={text} end
    for i,source in ipairs(lines) do local entry={key='',script=source,enabled=true};validated(entry,compile,warnings,'Script '..i);rows[#rows+1]=entry end
    patch.hotkeys=rows;patch.hotkeysEnabled=true
  end
  return {format=next(sections) and 'ElfBot text settings' or 'ElfBot command script',patch=patch,warnings=warnings,hotkeys=#(patch.hotkeys or {}),shortkeys=#(patch.shortkeys or {}),icons=#(patch.icons or {})}
end
function I.summary(result)
  return result.format..': '..result.hotkeys..' hotkeys, '..result.shortkeys..' shortkeys, '..result.icons..' icons'..(result.healing and ', '..result.healing..' healing spell fields' or '')..(result.waypoints and ', '..result.waypoints..' waypoints' or '')..(result.targets and ', '..result.targets..' targets' or '')..'. '..#result.warnings..' notices.'
end
function I.apply(current,result)
  local d=clone(result.replacement or current)
  for key,value in pairs(result.patch or {}) do d[key]=clone(value) end
  if result.replacement then d.botEnabled=current.botEnabled end
  d.importWarnings=clone(result.warnings);return d
end

-- Produce a native client settings document without executing imported commands.
function I.translate(text,compile,path)
  local result=I.parse(text,compile,path)
  local settings=I.apply({},result)
  settings.translation={format=result.format,warnings=clone(result.warnings)}
  return {elfbot=settings},result
end
