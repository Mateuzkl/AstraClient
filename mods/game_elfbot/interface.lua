-- Independent classic Windows appearance; widgets belong to game_elfbot.
function attachElfBot(c)
  c.storage.elfbot=c.storage.elfbot or {}
  local data=c.storage.elfbot
  local e=c.ElfBot or createElfBotEngine(c,data)
  c.ElfBot=e
  -- Discover profile files without executing commands or applying settings at startup.
  local function scriptFiles(extension)
    local files={};local resources=c.g_resources
    if not resources or not resources.listDirectoryFiles then return files end
    local ok,names=pcall(resources.listDirectoryFiles,'/elfbot/scripts',false,false)
    if ok and type(names)=='table' then
      table.sort(names)
      for _,name in ipairs(names) do
        if name:lower():sub(-#extension)==extension and not name:find('[/\\]') then
          files[#files+1]={name=name,path='/elfbot/scripts/'..name}
        end
      end
    end
    return files
  end
  local windows, statusLabels={},{}
  local alive=true
  local selectedSettingsPath
  local uiVisible=false
  local iconWidgets,iconJobs={},{}
  local overlays={}
  local function clearOverlays() for _,v in ipairs(overlays) do if not v:isDestroyed() then v:destroy() end end;overlays={} end
  local chatFilter
  local mapPanel=modules.game_interface.getMapPanel()
  local originalTop,originalBottom=mapPanel:getMarginTop(),mapPanel:getMarginBottom()
  -- Register cleanup before constructing windows, so failed startup is reversible.
  e.disposeInterface=function()
    if not alive then return end;alive=false;e.hudVisible=false;if e.clearPlayerLabels then e.clearPlayerLabels() end;if e.clearWallTimers then e.clearWallTimers() end;clearOverlays();e.jobs={};e.actionJobs={}
    for _,v in ipairs(iconWidgets) do if not v:isDestroyed() then v:destroy() end end;iconWidgets={}
    if e.spyFloor then mapPanel:unlockVisibleFloor() end;if e.scrollView and mapPanel.setLimitVisibleRange then mapPanel:setLimitVisibleRange(e.originalVisibleRange~=false) end
    mapPanel:setMarginTop(originalTop);mapPanel:setMarginBottom(originalBottom)
    if chatFilter and modules.game_console.removeFilter then modules.game_console.removeFilter(chatFilter) end
    for _,v in ipairs(windows) do if not v:isDestroyed() then v:destroy() end end
  end
  local function selectRow(row)
    local parent=row:getParent()
    for _,other in ipairs(parent:getChildren()) do if other:getStyleName()=='ElfBotRow' then other:setOn(other==row) end end
    -- Explicit selection also handles an already-focused single remaining row.
    if row.onFocusChange then row.onFocusChange(row,true) end
  end
  local function createRow(style,parent)
    local row=g_ui.createWidget(style,parent)
    row.onMousePress=function() selectRow(row);return true end
    return row
  end
  local function widget(style,parent,x,y,w,h,text)
    local v=g_ui.createWidget(style,parent)
    if parent==g_ui.getRootWidget() then
      v.elfWidget=true
      if style=='ElfBotOverlay' then v.elfOverlay=true elseif style=='ElfBotIcon' or style=='ElfBotIconCaption' then iconWidgets[#iconWidgets+1]=v else windows[#windows+1]=v end
    end
    -- Keep the window's hit-test rectangle unpadded, including its close button.
    -- Content still uses the same inset below the header; nested groups keep padding.
    if parent.elfContentOffset then x=x+parent.elfContentOffset.x;y=y+parent.elfContentOffset.y end
    v:setPosition({x=parent:getPaddingRect().x+x,y=parent:getPaddingRect().y+y})
    v:addAnchor(AnchorLeft,'parent',AnchorLeft);v:addAnchor(AnchorTop,'parent',AnchorTop)
    v:setMarginLeft(x);v:setMarginTop(y);v:setSize({width=w,height=h})
    if text then v:setText(text) end
    return v
  end
  local function label(parent,x,y,w,text)
    local v=widget('ElfBotLabel',parent,x,y,w,18,text)
    v:setHeight(math.max(18,v:getTextSize().height));return v
  end
  local function button(parent,x,y,w,text,callback)
    local v=widget('ElfBotButton',parent,x,y,w,24,text)
    v.onClick=function() local ok,err=pcall(callback);if not ok then e.status=tostring(err);c.warn('ElfBot: '..e.status) end end
    return v
  end
  local function edit(parent,x,y,w,text) return widget('ElfBotTextEdit',parent,x,y,w,22,text or '') end
  local function check(parent,x,y,w,text,value,callback)
    local v=widget('ElfBotCheck',parent,x,y,w,18,text);v:setChecked(value==true)
    v.onCheckChange=function(_,checked) callback(checked) end;return v
  end
  local function group(parent,x,y,w,h,title)
    local v=widget('ElfBotGroup',parent,x,y,w,h);label(v,0,0,w-16,title);return v
  end
  local function list(parent,x,y,w,h)
    local scroll=widget('ElfBotScrollBar',parent,x+w-12,y,12,h)
    local v=widget('ElfBotList',parent,x,y,w-14,h);v:setVerticalScrollBar(scroll);return v
  end
  local function window(title,w,h)
    local v=c.UI.createWindow('ElfBotWindow');windows[#windows+1]=v;v:setSize({width=w+16,height=h+37});v:setText(title)
    v.elfContentOffset={x=8,y=29}
    v.titleBar=widget('ElfBotTitle',v,-7,-27,w+14,23,title)
    local close=widget('ElfBotClose',v,w-15,-26,20,20,'x');close.onClick=function() v:hide() end
    v.closeButton=close
    v:hide();return v
  end
  local function show(v) v:show();v:raise();v:focus() end
  local function status(v,x,y,w)
    local s=label(v,x,y,w,'Ready');s:setTextWrap(true);s:setHeight(32);statusLabels[#statusLabels+1]=s;return s
  end
  local function save() data.awaitingLoad=nil;c.saveConfig();e.status='ElfBot settings saved' end
  local function guardCompile(source)
    local ok,p=pcall(e.compile,source);assert(ok,p);return p
  end
  local panels={}
  local showBotTab
  local function scriptEditor(title,value,callback,saveLabel)
    local win=window(title,650,350)
    local text=widget('ElfBotMultilineTextEdit',win,0,0,650,285,value)
    button(win,0,297,110,saveLabel or 'Save / Restart',function() callback(text:getText());save();win:destroy() end)
    button(win,116,297,80,'Copy',function() g_window.setClipboardText(text:getText()) end)
    button(win,202,297,80,'Paste',function() text:setText(g_window.getClipboardText()) end)
    show(win)
  end
  local function combo(parent,x,y,w,values,value)
    local v=widget('ElfBotCombo',parent,x,y,w,22)
    for _,name in ipairs(values) do v:addOption(tostring(name)) end
    if value then v:setCurrentOption(tostring(value)) end;return v
  end
  local function numberField(parent,x,y,w,value) return edit(parent,x,y,w,tostring(value or 0)) end
  local function readNumber(v,min,max)
    local n=assert(tonumber(v:getText()),'Expected a number');assert(n>=min and n<=max,'Number must be '..min..'..'..max);return n
  end
  local function colorField(parent,x,y,w,value)
    local v=widget('ElfBotButton',parent,x,y,w,20,'')
    v.getText=function(self) return self.hexValue end
    v.setText=function(self,text) self.hexValue=text;self:setBackgroundColor(text) end
    v:setText(value)
    v.onClick=function() scriptEditor('Color (#RRGGBB)',v:getText(),function(text) assert(text:match('^#%x%x%x%x%x%x$'),'Expected #RRGGBB');v:setText(text) end) end
    return v
  end
  -- Coordinates from the original ElfBot resource dialogs, in dialog units.
  -- Original dialog units need more horizontal room for Astra's bitmap font.
  local function dx(n) return math.floor(n*2+0.5) end
  local function dy(n) return math.floor(n*1.625+0.5) end
  local function dl(p,x,y,w,text) local v=label(p,dx(x),dy(y),dx(w),text);v:setHeight(math.max(dy(9),v:getTextSize().height));return v end
  local function de(p,x,y,w,text) local v=edit(p,dx(x),dy(y),dx(w),tostring(text or ''));v:setHeight(dy(9));return v end
  local function dc(p,x,y,w,values,value) local v=combo(p,dx(x),dy(y),dx(w),values,value);v:setHeight(dy(9));return v end
  local function db(p,x,y,w,h,text,fn) local v=button(p,dx(x),dy(y),dx(w),text,fn);v:setHeight(dy(h));return v end
  local function dk(p,x,y,w,text,value,fn) local v=check(p,dx(x),dy(y),dx(w),text,value,fn);v:setHeight(dy(9));return v end
  local function dg(p,x,y,w,h,title)
    local v=widget('ElfBotGroup',p,dx(x),dy(y+4),dx(w),dy(h-4));v:setPhantom(true)
    local t=dl(p,x+4,y,w-8,title);t:setBackgroundColor('#f0f0f0');t:setPhantom(true);return v
  end
  local function originalDialog(id)
    local definition=ElfBotOriginalDialogs[id]
    local win=window(definition.title,dx(definition.width),dy(definition.height));local refs={}
    for _,r in ipairs(definition.controls) do
      local cid,class,text,x,y,w,h,style=unpack(r);local v
      if class=='#128' then
        local subtype=style%16
        if subtype==7 then v=dg(win,x,y,w,h,text:gsub('&&','&'))
        elseif subtype==3 or subtype==9 then v=dk(win,x,y,w,text=='IDC_CHK' and '' or text,false,function() end)
        else v=db(win,x,y,w,h,text,function() end) end
      elseif class=='#130' then v=dl(win,x,y,w,text);v:setHeight(math.max(dy(h),v:getTextSize().height))
      elseif class=='#129' then
        if style%8>=4 then v=widget('ElfBotMultilineTextEdit',win,dx(x),dy(y),dx(w),dy(h),text)
        else v=de(win,x,y,w,text);v:setHeight(dy(h)) end
      elseif class=='#131' then
        if h>15 then v=list(win,dx(x),dy(y),dx(w),dy(h))
        else v=widget('ElfBotChoice',win,dx(x),dy(y),dx(w),dy(h)) end
      else v=widget('ElfBotLabel',win,dx(x),dy(y),dx(w),dy(h),text) end
      refs[cid]=v;v.originalControlId=cid;v.originalRect={x=x,y=y,width=w,height=h}
    end
    win.originalDialogId=id;win.originalControls=refs;return win,refs
  end
  local function setOptions(v,values,value)
    for _,name in ipairs(values) do v:addOption(tostring(name)) end
    v:setCurrentOption(tostring(value))
  end
  local function changeNumber(v,current,low,high,callback)
    v:setText(tostring(current))
    local function apply()
      local n=tonumber(v:getText());if not n or n<low or n>high then e.status='Value must be '..low..'..'..high;v:setText(tostring(current));return end
      current=n;callback(n)
    end
    v.onEnter=apply;v.onFocusChange=function(_,focus) if not focus then apply() end end
  end
  local function hotkeyWizard(callback)
    local win=window('Hotkey Wizard',565,280);local page=widget('ElfBotGroup',win,0,0,565,213)
    local state={step=1,auto=true,rate='200',command='say',parameters="'exura'",condition=''}
    local reader
    local function render()
      page:destroyChildren()
      if state.step==1 then
        label(page,0,0,530,'Hotkey type')
        label(page,0,30,530,'Choose repeated execution, or an action when pressed/held.')
        local auto=check(page,0,62,420,'Execute repeatedly after activation',state.auto,function() end)
        label(page,0,99,250,'Frequency of execution in milliseconds:');local rate=edit(page,285,96,100,state.rate)
        reader=function() state.auto=auto:isChecked();state.rate=rate:getText();local n=assert(tonumber(state.rate),'Numeric frequency required');assert(n>=1 and n<=86400000,'Invalid frequency') end
      elseif state.step==2 then
        label(page,0,0,530,'Action selection');label(page,0,31,530,'Select a command from the installed command registry.')
        local command=widget('ElfBotCombo',page,0,65,300,24);local names={};for name in pairs(e.commands) do names[#names+1]=name end;table.sort(names);for _,name in ipairs(names) do command:addOption(name) end;command:setCurrentOption(state.command)
        reader=function() state.command=command:getCurrentOption().text end
      elseif state.step==3 then
        label(page,0,0,530,'Parameter selection');label(page,0,32,530,'Command: '..state.command)
        local params=edit(page,0,68,530,state.parameters)
        label(page,0,108,530,"Examples: say 'exura', mana self, health 50 self, attack 'Rat'")
        label(page,0,139,530,'Leave parameters empty for commands such as haste.')
        reader=function() state.parameters=params:getText();guardCompile(state.command..' '..state.parameters) end
      elseif state.step==4 then
        label(page,0,0,530,'Condition selection');label(page,0,32,530,'Optional expression, for example: $hppc < 80 && $mp > 20')
        local condition=edit(page,0,68,530,state.condition)
        reader=function() state.condition=condition:getText() end
      else
        label(page,0,0,530,'Finalization / Complete command')
        state.source=(state.auto and 'auto '..state.rate..' ' or '')..(state.condition~='' and 'if ['..state.condition..'] ' or '')..state.command..' '..state.parameters
        guardCompile(state.source);widget('ElfBotMultilineTextEdit',page,0,30,530,136,state.source)
        reader=function() callback(state.source);win:destroy() end
      end
    end
    button(win,0,227,85,'< Back',function() if state.step>1 then state.step=state.step-1;render() end end)
    button(win,350,227,110,'Continue >>',function() reader();if state.step<5 then state.step=state.step+1;render() end end)
    button(win,468,227,90,'Cancel',function() win:destroy() end)
    render();show(win)
  end
  local function bindings(kind)
    local short=kind=='shortkeys';local rows=data[kind]
    local win,r=originalDialog(short and 10000 or 3000);panels[kind]=win
    r[1001]:setChecked(data[kind..'Enabled']);r[1001].onCheckChange=function(_,v) data[kind..'Enabled']=v end
    local persistent=false;local selected
    local rowsList=list(win,dx(6),dy(27),dx(244),dy(148))
    local refresh
    local function editEntry(index,source)
      if persistent then
        scriptEditor('Persistent Hotkeys',data.persistent,function(text)
          for line in text:gmatch('[^\r\n]+') do if line:match('%S') then guardCompile(line) end end
          data.persistent=text;e.reload();refresh()
        end);return
      end
      local row=index and rows[index] or {key='',script=source or '',enabled=true}
      local editor=window(short and 'Edit Shortkey' or 'Edit Hotkey',550,295)
      label(editor,0,0,100,short and 'Shortkey:' or 'Hotkey:');local key=edit(editor,105,0,230,row.key)
      if not short then key.onKeyDown=function(_,code,mods) local combo=determineKeyComboDesc(code,mods);if combo and combo~='' then key:setText(combo);return true end end end
      local enabled=check(editor,350,2,170,'Enabled',row.enabled,function() end)
      label(editor,0,33,100,'Toggle key:');local toggleKey=edit(editor,105,33,230,row.toggleKey or (not short and row.key) or '')
      toggleKey.onKeyDown=function(_,code,mods) local combo=determineKeyComboDesc(code,mods);if combo and combo~='' then toggleKey:setText(combo);return true end end
      local command=widget('ElfBotMultilineTextEdit',editor,0,68,550,167,row.script)
      command:setTooltip(row.importError or '')
      button(editor,0,250,100,'Save',function()
        if not command:getText():match('%S') then
          if index then table.remove(rows,index) end
          selected=nil;e.reload();refresh();save();editor:destroy();return
        end
        guardCompile(command:getText());local binding=key:getText():match('^%s*(.-)%s*$')
        if short then assert(binding~='','Shortkey cannot be empty')
        elseif binding~='' then binding=retranslateKeyComboDesc(binding);assert(binding and binding~='','Invalid hotkey') end
        local toggle=toggleKey:getText():match('^%s*(.-)%s*$');if toggle~='' then toggle=retranslateKeyComboDesc(toggle);assert(toggle and toggle~='','Invalid toggle key') end
        local value={key=binding,toggleKey=toggle,script=command:getText(),enabled=enabled:isChecked()}
        if index then rows[index]=value else rows[#rows+1]=value end
        e.reload();refresh();save();editor:destroy()
      end)
      button(editor,105,250,80,'Delete',function() assert(index,'Select an existing entry');table.remove(rows,index);selected=nil;e.reload();refresh();save();editor:destroy() end)
      button(editor,190,250,80,'Copy',function() g_window.setClipboardText(command:getText()) end)
      button(editor,275,250,80,'Paste',function() command:setText(g_window.getClipboardText()) end)
      button(editor,450,250,100,'Cancel',function() editor:destroy() end);show(editor)
    end
    refresh=function()
      rowsList:destroyChildren();selected=nil
      local displayed=rows
      if persistent then
        displayed={};for line in data.persistent:gmatch('[^\r\n]+') do displayed[#displayed+1]={key='',script=line,enabled=true} end
      end
      -- Original dialogs keep empty editable slots visible even with no saved commands.
      for i=1,math.max(100,#displayed) do
        local index=i;local existing=displayed[i];local storedIndex=existing and i;local row=existing or {key='',script='',enabled=false}
        local v=createRow('ElfBotRow',rowsList);v:setHeight(24);v:setSize({width=dx(244)-14,height=24});v:setTooltip(row.importError or row.script)
        v.onFocusChange=function(_,focus) if focus then selected=index end end
        local enabled;local keyField;local sourceField
        local function commit()
          selectRow(v);local source=sourceField:getText();local binding=keyField:getText():match('^%s*(.-)%s*$')
          if source:match('^%s*$') and not existing then return end
          local ok,err=pcall(function()
            if not short and binding~='' then binding=retranslateKeyComboDesc(binding);assert(binding and binding~='','Invalid hotkey') end
            local checked=enabled:isChecked()
            if existing and binding==(row.key or '') and source==(row.script or '') and checked==(row.enabled==true) then return end
            if not source:match('%S') and not persistent then
              table.remove(rows,storedIndex);existing=nil;storedIndex=nil;selected=nil
              e.reload();save();refresh();return
            end
            if source:match('%S') then guardCompile(source) end
            row.key=binding;row.script=source;row.enabled=checked
            if persistent then
              displayed[index]=row;local lines={};for j=1,math.max(index,#displayed) do local entry=displayed[j];if entry and entry.enabled and entry.script:match('%S') then lines[#lines+1]=entry.script end end;data.persistent=table.concat(lines,'\n')
            else
              if not existing then rows[#rows+1]=row;existing=row;storedIndex=#rows;selected=storedIndex else rows[storedIndex]=row end
            end
            e.reload();save()
          end);if not ok then e.status=tostring(err) end
        end
        enabled=check(v,0,0,18,'',row.enabled,function() if sourceField then commit() end end)
        keyField=edit(v,21,0,39,row.key or '');keyField:setHeight(17)
        sourceField=edit(v,64,0,dx(244)-82,row.script);sourceField:setHeight(17)
        sourceField.onEnter=function() if sourceField:getText():match('%S') and not existing then enabled:setChecked(true) end;commit() end
        keyField.onEnter=commit
        for _,field in ipairs({keyField,sourceField}) do field.onFocusChange=function(_,focus) if focus then selectRow(v) else commit() end end end
        keyField:setTooltip(persistent and 'Persistent commands have no activation key' or short and 'Shortkey command name' or 'Hotkey key combination')
        v.onDoubleClick=function() if persistent then editEntry() else editEntry(storedIndex,row.script) end end
      end
    end
    r[1003].onClick=function()
      if short then editEntry(nil,'')
      else hotkeyWizard(function(source)
        if persistent then data.persistent=data.persistent..(data.persistent~='' and '\n' or '')..source;e.reload();refresh();save()
        else editEntry(nil,source) end
      end) end
    end
    if short then
      r[1005]:setText(data.symbol);r[1005].onTextChange=function(_,text) if #text<=4 then data.symbol=text end end
      rowsList:setTooltip('Double-click a shortkey to edit it.')
    else
      r[1047].onClick=function() assert(persistent or selected,'Select a hotkey first');editEntry(selected and rows[selected] and selected or nil) end
      r[1048]:setChecked(false)
      r[1048].onCheckChange=function(_,v) persistent=v;refresh() end
    end
    refresh();return win
  end
  local function healing()
    data.healing=data.healing or {enabled=false,hiSpell='exura',hiHealth=90,hiMana=20,loSpell='exura vita',loHealth=50,loMana=160,hpHealth=40,hpType='uhealth',mpMana=40,mpType='gmana',paralysis=false,delay=1000}
    local h=data.healing;local win,r=originalDialog(4000);panels.healing=win
    local function text(id,key) r[id]:setText(h[key] or '');r[id].onTextChange=function(_,value) h[key]=value end end
    local function number(id,key,default,low,high) changeNumber(r[id],h[key] or default,low,high,function(n) h[key]=n end) end
    text(1023,'hiSpell');text(1009,'loSpell')
    number(1018,'hiHealth',90,0,100);number(1020,'hiMana',20,0,1000000000)
    number(1013,'loHealth',50,0,100);number(1011,'loMana',160,0,1000000000)
    number(1016,'uhHealth',40,0,100);number(1006,'hpHealth',40,0,100);number(1029,'mpMana',40,0,100)
    local function potion(id,key,values)
      setOptions(r[id],values,h[key]);r[id].onOptionChange=function(_,value) h[key]=value end
    end
    potion(1003,'hpType',{'health','shealth','ghealth','uhealth','gshealth'})
    potion(1032,'mpType',{'mana','smana','gmana','gsmana'})
    local function timing(id,key,default)
      local values={'200','300','500','750','1000','1500','2000','3000'}
      local value=tostring(h[key] or default);local found=false;for _,v in ipairs(values) do if v==value then found=true end end;if not found then values[#values+1]=value end
      setOptions(r[id],values,value);r[id].onOptionChange=function(_,v) h[key]=tonumber(v) end
    end
    timing(1014,'potionWait',1000);timing(1034,'delay',1000)
    local keys={'hiEnabled','loEnabled','uhEnabled','hpEnabled','mpEnabled'}
    local function enabled()
      local active=h.paralysis or h.friendEnabled
      for _,key in ipairs(keys) do active=active or h[key] end
      h.enabled=active==true;if h.enabled then e.paused=false end
    end
    for i,row in ipairs({{'hiEnabled',14},{'loEnabled',25},{'uhEnabled',36},{'hpEnabled',48},{'mpEnabled',59}}) do
      local key=row[1];if h[key]==nil then h[key]=key~='uhEnabled' and h.enabled==true end
      local checkbox=dk(win,5,row[2],9,'',h[key],function(v) h[key]=v;enabled() end);checkbox:setTooltip('Enable '..key:gsub('Enabled',''))
    end
    dk(win,5,70,9,'',h.paralysis,function(v) h.paralysis=v;enabled() end):setTooltip('Heal paralysis')
    local health={'Disabled','10','20','30','40','50','60','70','80','90','100'}
    setOptions(r[1026],health,h.friendEnabled and tostring(h.friendHealth or 60) or 'Disabled')
    r[1026].onOptionChange=function(_,value) h.friendEnabled=value~='Disabled';h.friendHealth=tonumber(value) or 60;h.friend=h.friend or 'friend';enabled() end
    local mana={'0','20','50','100','160','200','300','500','1000'};local current=tostring(h.friendMana or 160)
    local found=false;for _,v in ipairs(mana) do if v==current then found=true end end;if not found then mana[#mana+1]=current end
    setOptions(r[1024],mana,current);r[1024].onOptionChange=function(_,value) h.friendMana=tonumber(value) end
    r[1026]:setTooltip('Heal the configured friend, or a player from Lists / Friends. Disabled turns friend healing off.')
    return win
  end
  local function cavebot()
    local win,r=originalDialog(14000);panels.cavebot=win
    local selected,lootIndex;local refresh,refreshRoutes,refreshLoot
    local visibleRows={}
    local b=e.route();local action=r[1011];action:hide()
    local offsets={Center={0,0},North={0,-1},East={1,0},South={0,1},West={-1,0},['North-East']={1,-1},['South-East']={1,1},['South-West']={-1,1},['North-West']={-1,-1}}
    setOptions(r[1040],{'Center','North','East','South','West','North-East','South-East','South-West','North-West'},'Center')
    data.showLabels=data.showLabels~=false;r[1020]:setChecked(data.showLabels)
    refresh=function()
      r[1028]:destroyChildren();visibleRows={}
      local count=b.actionList:getChildCount();selected=count>0 and math.max(1,math.min(selected or b.index or 1,count)) or nil
      for i,node in ipairs(b.actionList:getChildren()) do if data.showLabels or node.action~='label' then
        local index=i;local row=createRow('ElfBotRow',r[1028]);visibleRows[index]=row;local letters={elfstand='S',elfnode='N',elfwalk='W',elfrope='R',elfladder='L',elfshovel='H',elflure='U',elfaction='A',label='Label',use='L',usewith='Use'}
        local p=node.actionPosition;local value=p and (p.x..' '..p.y..' '..p.z) or node.value:gsub(',',' '):gsub('\n',' ')
        row:setText(string.format('%s %03d: %s',letters[node.action] or node.action,i-1,value))
        row.onFocusChange=function(_,focus) if focus then selected=index;action:setText(node.value);action:setVisible(node.action=='elfaction');b.actionList:focusChild(node) end end
      end end
      if selected and not visibleRows[selected] then selected=nil;for index in pairs(visibleRows) do if not selected or index<selected then selected=index end end end
      if visibleRows[selected] then selectRow(visibleRows[selected]) end
    end
    e.syncWaypointSelection=function()
      if win:isDestroyed() then return end
      if b.isOn() and b.index~=selected then
        local row=visibleRows[b.index];if row then selectRow(row);if r[1028].ensureChildVisible then r[1028]:ensureChildVisible(row) end end
      end
    end
    local function append(kind)
      local value
      if kind=='action' then
        value=action:getText()
        guardCompile(value);action:show()
      else local pos=c.pos();local offset=offsets[r[1040]:getCurrentOption().text];value=table.concat({pos.x+offset[1],pos.y+offset[2],pos.z},',') end
      local p=c.pos();local offset=offsets[r[1040]:getCurrentOption().text]
      local node=b.addAction('elf'..kind,value,true,kind=='action' and {x=p.x+offset[1],y=p.y+offset[2],z=p.z} or nil)
      if selected then b.actionList:moveChildToIndex(node,selected+1) end
      selected=b.actionList:getChildIndex(node);action:setText(value);b.save();refresh()
    end
    for id,kind in pairs({[1004]='stand',[1007]='node',[1001]='walk',[1005]='action',[1002]='rope',[1003]='ladder',[1006]='shovel',[1008]='lure'}) do local name=kind;r[id].onClick=function() append(name) end end
    action.onEnter=function()
      assert(selected,'Select an Action waypoint');local node=b.actionList:getChildByIndex(selected);assert(node and node.action=='elfaction','Select an Action waypoint')
      guardCompile(action:getText());b.editAction(node,node.action,action:getText());b.save();refresh()
    end
    action.onFocusChange=function(_,focus) if not focus and selected and b.actionList:getChildByIndex(selected).action=='elfaction' then local ok,err=pcall(action.onEnter);if not ok then e.status=tostring(err) end end end
    r[1027].onClick=function() selected=math.max(1,(selected or 1)-1);local node=b.actionList:getChildByIndex(selected);if node then action:setText(node.value);action:setVisible(node.action=='elfaction');b.actionList:focusChild(node);if visibleRows[selected] then selectRow(visibleRows[selected]) end end end
    r[1026].onClick=function() selected=math.min(b.actionList:getChildCount(),(selected or 0)+1);local node=b.actionList:getChildByIndex(selected);if node then action:setText(node.value);action:setVisible(node.action=='elfaction');b.actionList:focusChild(node);if visibleRows[selected] then selectRow(visibleRows[selected]) end end end
    r[1038].onClick=function() assert(selected,'Select a waypoint');b.actionList:getChildByIndex(selected):destroy();selected=math.min(selected,b.actionList:getChildCount());action:hide();b.save();refresh() end
    r[1051].onClick=function() scriptEditor('Clear waypoints: type CLEAR to confirm','',function(text) assert(text=='CLEAR','Type CLEAR to confirm');b.setOff();b.actionList:destroyChildren();selected=nil;b.save();refresh() end) end
    r[1018].onClick=function()
      local popup=window('Label a waypoint',270,75);label(popup,0,0,250,'Label name:');local name=edit(popup,0,22,270,'')
      button(popup,170,49,100,'OK',function() local text=name:getText():match('^%s*(.-)%s*$');assert(text~='','Enter a label');local node=b.addAction('label',text,true);if selected then b.actionList:moveChildToIndex(node,selected) end;b.save();refresh();popup:destroy() end);show(popup)
    end
    r[1020].onCheckChange=function(_,value) data.showLabels=value;refresh() end
    action:setHeight(dy(52))
    local recordButton=db(win,132,120,120,13,'Auto Record',function()
      if b.Recorder.isOn() then b.Recorder.disable() else b.Recorder.enable();r[1012]:setChecked(false) end
    end)
    local function recordingState() recordButton:setText(b.Recorder.isOn() and 'Auto Record: ON' or 'Auto Record');recordButton:setOn(b.Recorder.isOn()) end
    local previousRecordClick=recordButton.onClick
    recordButton.onClick=function(...) previousRecordClick(...);recordingState() end
    b.Recorder.onChange=function() if not win:isDestroyed() then refresh();recordingState() end end
    recordingState()
    r[1012].onCheckChange=function(_,value) if not e.syncFollow then e.commands.setcavebot({value});recordingState() end end;e.followCheck=r[1012]
    data.caveKeys=data.caveKeys or ''
    r[1047].onClick=function() scriptEditor('Cavebot Hotkey List',data.caveKeys,function(text) for line in text:gmatch('[^\r\n]+') do if line:match('%S') then guardCompile(line) end end;data.caveKeys=text;e.reload() end) end
    data.loot=data.loot or {}
    refreshLoot=function()
      r[1035]:destroyChildren()
      for i,row in ipairs(data.loot) do local index=i;local item=createRow('ElfBotRow',r[1035]);item:setText(row.id..' '..row.destination..' '..row.name)
        item.onFocusChange=function(_,focus) if focus then lootIndex=index;r[1032]:setText(row.id);r[1031]:setText(row.destination);r[1029]:setText(row.name) end end
      end
    end
    local function lootApply()
      local id=assert(tonumber(r[1032]:getText()),'Enter an item ID');assert(id>0 and id<=65535,'Invalid item ID')
      local dest=r[1031]:getText():upper();local n=tonumber(dest);assert(dest=='E' or dest=='E1' or dest=='G' or n and n>=0 and n<=15 and n%1==0,'Use E, E1, G or container 0..15')
      local row={id=id,destination=dest,name=r[1029]:getText()};if lootIndex then data.loot[lootIndex]=row else data.loot[#data.loot+1]=row end
      lootIndex=nil;save();refreshLoot()
    end
    r[1031]:setText('E');for _,id in ipairs({1032,1031,1029}) do r[id].onEnter=lootApply end
    r[1032]:setTooltip('Item ID: press Enter to add or apply this loot entry.');r[1031]:setTooltip('Destination: E / E1 / G / 0..15. Press Enter to apply.')
    r[1033].onClick=function() assert(lootIndex,'Select a loot entry');table.remove(data.loot,lootIndex);lootIndex=nil;save();refreshLoot() end
    local function snapshot() local rows={};for _,node in ipairs(b.actionList:getChildren()) do rows[#rows+1]={node.action,node.value,node.actionPosition} end;return rows end
    local function restore(rows)
      assert(type(rows)=='table','Expected a route')
      for _,row in ipairs(rows) do assert(type(row)=='table' and b.Actions[row[1]] and type(row[2])=='string','Invalid waypoint');if row[1]=='elfaction' then guardCompile(row[2]) end end
      b.setOff();b.actionList:destroyChildren();for _,row in ipairs(rows) do b.addAction(row[1],row[2],false,row[3]) end;selected=nil;b.save();refresh()
    end
    r[1041]:setText(data.routeName or 'ElfBot route')
    refreshRoutes=function() r[1009]:destroyChildren();local names={};for name in pairs(data.routes) do names[#names+1]=name end;table.sort(names)
      for _,name in ipairs(names) do local route=name;local row=createRow('ElfBotRow',r[1009]);row:setText(route);row.onFocusChange=function(_,focus) if focus then r[1041]:setText(route) end end end
      for _,file in ipairs(scriptFiles('.elfc')) do
        local entry=file;local row=createRow('ElfBotRow',r[1009]);row:setText(entry.name)
        row.onFocusChange=function(_,focus) if focus then
          local result=c.previewElfFile(entry.path);restore(assert(result.patch and result.patch.waypoints,'Expected a cavebot profile'))
          data.routeName=entry.name;r[1041]:setText(entry.name);e.status=ElfBotSettingsImport.summary(result)
        end end
      end
    end
    r[1050].onClick=function() local name=r[1041]:getText();assert(name~='','Enter a route name');data.routeName=name;data.routes[name]=snapshot();save();refreshRoutes() end
    r[1075].onClick=function() local name=r[1041]:getText();restore(assert(data.routes[name],'No route with that name'));data.routeName=name end
    r[1048].onClick=function() scriptEditor('Route editor',json.encode(snapshot(),2),function(text) restore(text:match('%S') and json.decode(text) or {}) end) end
    for id,key in pairs({[1015]='rope',[1016]='shovel',[1042]='nodeRadius'}) do
      local field=key;local values=field=='nodeRadius' and {'0','1','2','3','4','5','6','7','8','9'} or {tostring(data[field])}
      if field~='nodeRadius' then values[#values+1]='Custom...' end
      setOptions(r[id],values,data[field] or 1);r[id].onOptionChange=function(_,value)
        if value=='Custom...' then
          local editor=window('Item ID',230,65);local input=numberField(editor,5,5,130,data[field]);button(editor,145,5,70,'Apply',function()
            data[field]=readNumber(input,1,65535);setOptions(r[id],{tostring(data[field]),'Custom...'},data[field]);save();editor:destroy()
          end)
        else data[field]=tonumber(value) end
      end
    end
    for id,key in pairs({[1037]='openNextBp',[1036]='lootNearby',[1024]='lootDistant'}) do local name=key;r[id]:setChecked(data.extras[name]~=false and name~='openNextBp' or data.extras[name]==true);r[id].onCheckChange=function(_,value) data.extras[name]=value end end
    data.alerts=data.alerts or {}
    for i,key in ipairs({'player','gm','attack','default','private'}) do data.alerts[key]=data.alerts[key] or {}
      for j,field in ipairs({'sound','pause','logout'}) do local name,property=key,field;local control=r[1100+(i-1)*3+j-1];control:setChecked(data.alerts[name][property]);control.onCheckChange=function(_,value) data.alerts[name][property]=value end end
    end
    data.alerts.disconnected=data.alerts.disconnected or {}
    for id,key in pairs({[1115]='sound',[1117]='logout'}) do local name=key;r[id]:setChecked(data.alerts.disconnected[name]);r[id].onCheckChange=function(_,value) data.alerts.disconnected[name]=value end end
    local reconnect=dk(win,246,223,9,'',data.extras.reconnect,function(value) data.extras.reconnect=value end);reconnect:setTooltip('Reconnect after disconnect')
    refresh();refreshRoutes();refreshLoot();win.onVisibilityChange=function(_,visible) if visible then refresh() end end;return win
  end
  local function targeting()
    local d=data.targeting;d.range=d.range or 2;d.frequency=d.frequency or 2000
    local win=window('Monster Targeting',dx(380),dy(253));panels.targeting=win
    dg(win,2,1,234,157,'Monsters definition and behaviours');dg(win,240,1,138,118,'Target selection')
    dg(win,2,160,132,91,'Stance options');dg(win,138,160,98,91,'Saving & Loading settings');dg(win,240,160,138,91,'Blocked tiles')
    local monsters=list(win,dx(10),dy(14),dx(88),dy(122));local selected,settingIndex,loading=nil,1,false
    dl(win,108,18,24,'Name');local name=de(win,134,18,94,'');name:setTooltip('Enter a name and press Enter to add or update. Use * for all monsters.')
    dl(win,108,29,24,'Count');local count=dc(win,134,29,28,{'Any','1','2','3','4','5','6','7','8','9','10'},'Any')
    dl(win,170,29,30,'Setting #');local settings=dc(win,200,29,28,{'1','New','Delete'},'1')
    dl(win,108,40,38,'Categories');local categories=de(win,148,40,80,'')
    dl(win,108,59,52,'HP% range');local hpMin=de(win,168,59,20,0);dl(win,196,59,12,'to');local hpMax=de(win,208,59,20,100)
    dl(win,108,70,58,'Monster attacks');local avoid=dc(win,168,70,60,{"Don't avoid",'Avoid beams','Avoid waves','Avoid all'},"Don't avoid")
    dl(win,108,81,72,'Danger level');local danger=de(win,200,81,28,0)
    dl(win,108,92,60,'Desired distance');local stance=dc(win,168,92,60,{'No Movement','Approach','Follow','Keep distance','Lure'},'No Movement')
    dl(win,108,103,60,'Desired action');local action=de(win,168,103,60,'');action:setTooltip('Type your attack spell, for example exori frigo, or an ElfBot command such as sd target. Empty means no spell.')
    dl(win,108,114,60,'Attack mode');local fight=dc(win,168,114,60,{'No change','Offensive','Balanced','Defensive'},'No change')
    dl(win,108,125,60,'Wear ring');local ring=de(win,168,125,60,'No change')
    local alarm=dk(win,110,144,56,'Play alarm',false,function() end);local loot=dk(win,174,144,54,'Loot monster',true,function() end)
    local reachable=dk(win,248,96,124,'Target must be reachable',d.reachable,function(v) d.reachable=v;save() end)
    local shootable=dk(win,248,105,124,'Target must be shootable',d.shootable,function(v) d.shootable=v;save() end)
    for i,row in ipairs({{'order','List order'},{'health','Health'},{'proximity','Proximity'},{'danger','Danger'},{'random','Random'},{'stick','Stick'}}) do
      dl(win,248,16+(i-1)*13,38,row[2]);local bar=widget('ElfBotSlider',win,dx(288),dy(18+(i-1)*13),dx(82),dy(8))
      bar:setMinimum(0);bar:setMaximum(100);bar:setValue(row[1]=='stick' and (d.stickWeight or (d.stick and 100 or 0)) or (d.weights[row[1]] or 0))
      local key=row[1];bar:setTooltip(row[2]..' priority');bar.onValueChange=function(_,value) if key=='stick' then d.stickWeight=value;d.stick=value>0 else d.weights[key]=value end;save() end
    end
    dl(win,10,173,73,'Range distance');local range=de(win,86,173,38,d.range)
    dl(win,10,184,73,'Attack frequency');local frequency=de(win,86,184,38,d.frequency)
    dl(win,10,195,73,"Ignore other's monsters");local ignore=dc(win,86,195,38,{"Don't",'All','Friends','Enemies'},d.ignoreOthers or "Don't");ignore:setTooltip("Uses server ownership data supplied through ElfBot.setMonsterOwner(id, playerName).")
    dk(win,10,210,120,'Ignore Anti-bot monsters',d.ignoreAntiBot,function(v) d.ignoreAntiBot=v;save() end):setTooltip('Uses names in the Anti-bot category. The server must supply the name; no hidden server flags are assumed.')
    dk(win,10,219,120,'Sync spell with attacks',d.syncSpell,function(v) d.syncSpell=v;save() end)
    dk(win,10,228,120,'Allow diagonal movement',d.diagonal~=false,function(v) d.diagonal=v;save() end)
    dk(win,10,238,120,'Run Targeting',c.TargetBot.isOn(),function(v) if v then c.TargetBot.setOn() else c.TargetBot.setOff() end end)
    local function option(v) return v:getCurrentOption().text end
    local refresh,load,store
    load=function()
      loading=true;local parent=selected and d.monsters[selected];local rule=parent and (parent.settings or {parent})[settingIndex] or {}
      name:setText(parent and parent.name or '');count:setCurrentOption(parent and (parent.count and parent.count>0 and tostring(parent.count) or 'Any') or 'Any')
      categories:setText(parent and parent.categories or '');settings:clearOptions();for i=1,(parent and #(parent.settings or {parent}) or 1) do settings:addOption(tostring(i)) end;settings:addOption('New');settings:addOption('Delete');settings:setCurrentOption(tostring(settingIndex))
      hpMin:setText(tostring(rule.hpMin or 0));hpMax:setText(tostring(rule.hpMax or 100));danger:setText(tostring(rule.danger or 0));stance:setCurrentOption(rule.stance=='Stand' and 'No Movement' or rule.stance or 'No Movement');action:setText(rule.action or '')
      avoid:setCurrentOption(rule.avoid or "Don't avoid");fight:setCurrentOption(({'Offensive','Balanced','Defensive'})[rule.fightMode or 0] or 'No change');ring:setText(rule.ring and rule.ring>0 and tostring(rule.ring) or 'No change');alarm:setChecked(rule.alarm==true);loot:setChecked(not parent or parent.loot~=false);loading=false
    end
    store=function()
      if loading then return end
      local text=name:getText():match('^%s*(.-)%s*$');assert(text~='','Enter a monster name')
      assert(not e.compileAttack(action:getText()).interval,'Attack action cannot contain auto')
      local low,high=readNumber(hpMin,0,100),readNumber(hpMax,0,100);assert(low<=high,'HP range is reversed')
      local parent=selected and d.monsters[selected]
      if not parent then parent={settings={}};d.monsters[#d.monsters+1]=parent;selected=#d.monsters end
      parent.name=text;parent.count=tonumber(option(count)) or 0;parent.categories=categories:getText();parent.loot=loot:isChecked();parent.enabled=true;if not parent.settings then local original={};for k,v in pairs(parent) do if k~="settings" then original[k]=v end end;parent.settings={original} end
      parent.settings[settingIndex]={hpMin=low,hpMax=high,danger=readNumber(danger,0,100),stance=option(stance),action=action:getText(),avoid=option(avoid),ring=ring:getText():lower()=='no change' and 0 or readNumber(ring,0,65535),alarm=alarm:isChecked(),fightMode=({Offensive=1,Balanced=2,Defensive=3})[option(fight)]}
      d.range=readNumber(range,0,9);d.frequency=readNumber(frequency,200,60000);d.ignoreOthers=option(ignore);refresh();save()
    end
    refresh=function()
      monsters:destroyChildren();local new=createRow('ElfBotRow',monsters);new:setText('<New monster>');new.onFocusChange=function(_,v) if v then selected=nil;settingIndex=1;load() end end
      for i,rule in ipairs(d.monsters) do local index=i;local row=createRow('ElfBotRow',monsters);row:setText(rule.name);row.onFocusChange=function(_,v) if v then selected=index;settingIndex=1;load() end end end
    end
    local function apply() local ok,err=pcall(store);if not ok then e.status=tostring(err);c.warn(e.status) end end
    for _,v in ipairs({name,categories,hpMin,hpMax,danger,action,ring,range,frequency}) do v.onEnter=apply;v.onFocusChange=function(_,focus) if not focus and name:getText()~='' then apply() end end end
    for _,v in ipairs({count,stance,avoid,fight,ignore}) do v.onOptionChange=function() if not loading and name:getText()~='' then apply() end end end
    alarm.onCheckChange=function() if not loading and selected then apply() end end;loot.onCheckChange=alarm.onCheckChange
    settings.onOptionChange=function(_,text)
      if loading or not selected then return end;local parent=d.monsters[selected];if not parent.settings then local original={};for k,v in pairs(parent) do if k~="settings" then original[k]=v end end;parent.settings={original} end
      if text=='New' then parent.settings[#parent.settings+1]={hpMin=0,hpMax=100};settingIndex=#parent.settings
      elseif text=='Delete' then assert(#parent.settings>1,'Keep at least one setting');table.remove(parent.settings,settingIndex);settingIndex=1
      else settingIndex=tonumber(text) or 1 end;load();save()
    end
    local function reorder(delta) assert(selected,'Select a monster');local index=math.max(1,math.min(#d.monsters,selected+delta));local row=table.remove(d.monsters,selected);table.insert(d.monsters,index,row);selected=index;refresh();save() end
    db(win,8,140,14,13,'<',function() reorder(-1) end);db(win,26,140,14,13,'>',function() reorder(1) end)
    db(win,80,140,20,13,'Del',function() assert(selected,'Select a monster');table.remove(d.monsters,selected);selected=nil;settingIndex=1;refresh();load();save() end)
    local saved=list(win,dx(148),dy(173),dx(78),dy(44));data.targetProfiles=data.targetProfiles or {}
    dl(win,148,221,24,'Name');local configName=de(win,172,221,54,data.targetName or 'Default')
    local function profiles()
      saved:destroyChildren()
      for key in pairs(data.targetProfiles) do local profileName=key;local row=createRow('ElfBotRow',saved);row:setText(profileName);row.onFocusChange=function(_,v) if v then configName:setText(profileName) end end end
      for _,file in ipairs(scriptFiles('.elft')) do
        local entry=file;local row=createRow('ElfBotRow',saved);row:setText(entry.name)
        row.onFocusChange=function(_,focus) if focus then
          local result=c.previewElfFile(entry.path);local source=assert(result.patch and result.patch.targeting,'Expected a targeting profile')
          c.TargetBot.setOff();for key,value in pairs(source) do d[key]=value end
          selected=nil;settingIndex=1;data.targetName=entry.name;configName:setText(entry.name);refresh();load();save();e.status=ElfBotSettingsImport.summary(result)
        end end
      end
    end
    db(win,146,234,30,11,'Edit',apply)
    db(win,176,234,26,11,'Save',function() if name:getText()~='' then store() end;data.targetName=configName:getText();data.targetProfiles[data.targetName]=json.decode(json.encode(d));profiles();save() end)
    db(win,202,234,26,11,'Load',function() local source=assert(data.targetProfiles[configName:getText()],'Unknown targeting settings');c.TargetBot.setOff();data.targeting=json.decode(json.encode(source));win:destroy();panels.targeting=nil;show(targeting());save() end)
    local blocked=list(win,dx(248),dy(173),dx(122),dy(44));dl(win,250,221,46,'Only on label');local onlyLabel=de(win,298,221,72,d.blockedLabel or '')
    onlyLabel.onEnter=function() d.blockedLabel=onlyLabel:getText();save() end;onlyLabel.onFocusChange=function(_,focus) if not focus then d.blockedLabel=onlyLabel:getText();save() end end
    local chosen;local function blocks() blocked:destroyChildren();for line in (d.blocked or ''):gmatch('[^\r\n]+') do local value=line;local row=createRow('ElfBotRow',blocked);row:setText(value);row.onFocusChange=function(_,v) if v then chosen=value end end end end
    db(win,310,234,30,11,'Add',function() local p=c.pos();d.blocked=(d.blocked or '')..p.x..','..p.y..','..p.z..'\n';blocks();save() end):setTooltip('Add the tile under your character')
    db(win,340,234,30,11,'Del',function() assert(chosen,'Select a blocked tile');local rows={};for line in d.blocked:gmatch('[^\r\n]+') do if line~=chosen then rows[#rows+1]=line end end;d.blocked=table.concat(rows,'\n');blocks();save() end)
    e.selectMonsterSetting=load;refresh();load();profiles();blocks();return win
  end
  local function listsPanel()
    local win=window('Lists',650,410);panels.lists=win
    local entries={}
    for i,row in ipairs({{'friends','Friend names'},{'subfriends','Subfriend names'},{'enemies','Enemy names'},{'subenemies','Subenemy names'},{'leaders','Aim leaders'}}) do
      local x=((i-1)%3)*215;local y=math.floor((i-1)/3)*167
      label(win,x,y,205,row[2]);entries[row[1]]=widget('ElfBotMultilineTextEdit',win,x,y+23,205,133,data.lists[row[1]])
    end
    button(win,430,190,200,'Save lists',function() for key,v in pairs(entries) do data.lists[key]=v:getText() end;save() end)
    check(win,430,230,200,'Color listed players',data.lists.colors,function(v) data.lists.colors=v end)
    status(win,0,368,630);return win
  end
  local function aimbot()
    local a=data.aimbot;local win=window('Aimbot',580,460);panels.aimbot=win
    group(win,0,0,580,224,'Core Aimbot');group(win,0,232,284,228,'Trigger Aimbot')
    local function option(x,y,text,value,callback)
      local v=check(win,x,y,266,text,value,callback);v:setTextWrap(true);v:setHeight(28);v:setTooltip(text);return v
    end
    local function pending(x,y,text)
      local v=option(x,y,text,false,function() end)
      if v.setEnabled then v:setEnabled(false) end
      v:setTooltip(text..'\nThis original ElfBot feature is not supported by this client port.')
    end
    for i,text in ipairs({'Prioritize mages with least cur mp','Prioritize mages with most miss. mp','Choose enemies with lowest cur hp',"Lock on leader's target",'Auto-combo paralyze/leader target'}) do
      if i==3 then option(14,28+(i-1)*30,text,a.lowestHealth~=false,function(v) a.lowestHealth=v;save() end)
      else pending(14,28+(i-1)*30,text) end
    end
    for i,text in ipairs({'Trace shots','Display best target','Discount Protection zones','Lock on paralyzed sub/enemies','Choose subenemy if no enemy'}) do pending(300,28+(i-1)*30,text) end
    label(win,14,200,84,'Aim leaders:');local leaders=edit(win,100,198,180,data.lists.leaders or '');leaders.onEnter=function() data.lists.leaders=leaders:getText();save() end
    label(win,300,180,80,'Aim type:');local command=edit(win,382,178,184,a.command or '')
    command:setTooltip('client attack command or spell text; the original aim-type modes remain incomplete.')
    command.onEnter=function() assert(not e.compileAttack(command:getText()).interval,'Attack cannot contain auto');a.command=command:getText();save() end
    label(win,300,205,80,'Combo rate:');local rate=numberField(win,382,202,82,a.frequency or 200)
    rate.onEnter=function() a.frequency=readNumber(rate,200,60000);save() end
    a.triggerWords=a.triggerWords or {}
    for i,name in ipairs({'Combo','Sync combo','Paralyze','Single'}) do
      local key=name;label(win,14,251+(i-1)*28,94,name..':');local field=edit(win,110,248+(i-1)*28,160,a.triggerWords[key] or '')
      field.onEnter=function() a.triggerWords[key]=field:getText();a.triggers={};for _,word in pairs(a.triggerWords) do if word~='' then a.triggers[#a.triggers+1]={word=word,command=a.command or ''} end end;save() end
    end
    option(14,374,'Word triggering enabled',a.wordTriggers,function(v) a.wordTriggers=v end)
    option(14,402,'Execute automatically',a.enabled,function(v) a.enabled=v;if v then e.paused=false end end)
    pending(14,430,"Target others if can't be shot")
    pending(300,248,'Ignore lower priority leaders')
    option(300,280,'Target enemies only if skulled/war',a.skulledOnly,function(v) a.skulledOnly=v end):setTooltip('Current client mode filters all eligible players by skull; war emblems are not implemented.')
    pending(300,312,'Target subenemies if skulled/war');pending(300,344,'Target others if skulled/war')
    return win
  end
  local hudLayer=g_ui.createWidget('ElfBotHudLayer',g_ui.getRootWidget())
  hudLayer.elfWidget=true;windows[#windows+1]=hudLayer;hudLayer:hide()
  local hudDisplay=createElfBotHud(e,c,data,hudLayer,mapPanel)
  local function hud()
    local h=data.hud;local win=window('HUD Display',700,326);panels.hud=win
    group(win,0,0,700,142,'Player Info (above creatures)')
    group(win,0,150,700,176,'On-screen information')
    local fields={{'playerInfo','Player Info Enabled',14,28},{'guild','Show guild name',14,56},{'vocation','Show vocation, level and HP',14,84},{'mana','Show estimated mana when known',14,112},
      {'autoLook','Look at players automatically',360,28},{'cachePlayers','Cache player information',360,56},{'updateCache','Look and update cached entries',360,84},
      {'enabled','On-screen Info Enabled',14,178},{'general','General information and session XP',14,206},{'deathTimers','Recent death timers',14,234},{'wallTimers','Magic wall timers',14,262},{'active','Activated hotkeys/shortkeys',14,290},
      {'healing','Healing status and percentages',360,178},{'damage','Damage per second and best hit',360,206},{'spellTimers','Spell timers',360,234},{'navigation','Navigation & exiva players',360,262},{'skills','Skills, magic level and stamina',360,290}}
    for _,row in ipairs(fields) do
      local key=row[1];local value=h[key];if key=='skills' then value=h.skills~=false end
      local option=check(win,row[3],row[4],320,row[2],value,function(v)
        h[key]=v;if key=='cachePlayers' then data.playerCache=v and e.playerCache or nil end;save()
      end)
      option:setTextWrap(true);option:setHeight(26)
    end
    return win
  end
  local function extras()
    local win=window('Extras',440,325);panels.extras=win
    for i,row in ipairs({{'fullLight','Full light'},{'nonPvp','Non-pvp mode (safe fight)'},{'lootDistant','Loot distant targets'},{'loadAtLogin','Open ElfBot at login'},{'openBackpacks','Open backpack at login'},{'openNextBp','Open next backpack when full'}}) do
      check(win,0,(i-1)*31,400,row[2],data.extras[row[1]],function(v) data.extras[row[1]]=v;save() end)
    end
    button(win,0,233,150,'Pause all automation',function() e.paused=true;c.CaveBot.setOff();c.TargetBot.setOff();data.aimbot.enabled=false;data.hotkeysEnabled=false;data.shortkeysEnabled=false;if data.healing then data.healing.enabled=false end;e.jobs={};e.status='All automation paused' end)
    button(win,160,233,130,'Restart scripts',function() data.hotkeysEnabled=true;data.shortkeysEnabled=true;e.reload() end)
    status(win,0,276,425);return win
  end
  local iconDragging
  local iconControllers={}
  local function clearIcons() iconDragging=nil;for _,v in ipairs(iconWidgets) do if not v:isDestroyed() then v:destroy() end end;iconWidgets={} end
  local function iconController(program)
    local controller
    for _,node in ipairs(program.body) do
      if node.kind~='command' then return end
      local kind=({setcavebot='CaveBot',setfollowwaypoints='CaveBot',settargeting='TargetBot'})[node.name]
      if kind then if controller and controller~=kind then return end;controller=kind
      elseif node.name~='listas' and node.name~='dontlist' and node.name~='setcolor' then return end
    end
    return controller
  end
  local function iconActive(row)
    if data.botEnabled==false or e.paused then return false end
    local job=iconJobs[row]
    local controller=iconControllers[row] or job and job.iconController
    if controller then return c[controller].isOn() end
    return row.active==true
  end
  local function iconColor(row,state,hover)
    if hover and state.hover then return state.hover end
    local job=iconJobs[row];local color=iconActive(row) and job and job.env and job.env.color
    if color then return string.format('#%02x%02x%02x',color[1],color[2],color[3]) end
    return state.foreground or (iconActive(row) and '#55ff88' or '#ff5a61')
  end
  local function iconState(row) return iconActive(row) and row.onState or row.offState end
  local function iconNotice(row,script,state)
    e.status=row.name..' '..state..': '..script
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
      modules.game_textmessage.displayStatusMessage(e.status)
    else c.info(e.status) end
  end
  local function iconCommand(row,right)
    local script=right and row.rclick or row.lclick;if row.enabled==false or not script or script=='' then return end
    if data.botEnabled==false or e.paused then e.status='Automation is OFF. Switch ON before running icon commands.';c.info(e.status);return end
    local errorText=(row.errors or {})[right and 'rclick' or 'lclick'];assert(not errorText,errorText)
    local ok,program=pcall(guardCompile,script);assert(ok,'Icon '..row.name..' / '..(right and 'Right' or 'Left')..': '..tostring(program)..' | Script: '..script)
    local controller=iconController(program)
    if controller then
      -- Module toggles act once per click, even in old "auto ... setcavebot toggle" scripts.
      -- Match the badge to the live controller rather than repeatedly flipping it.
      if iconJobs[row] then iconJobs[row].active=false;iconJobs[row].thread=nil end
      local job,err=e.runProgram({body=program.body});assert(job,err);job.iconController=controller;job.iconName=row.name;job.row.script=script;iconJobs[row]=job
      local done=e.advance(job);assert(done~=nil,job.error);if done then job.active=false end
      row.running=false;row.active=c[controller].isOn();iconNotice(row,script,row.active and 'enabled' or 'cancelled')
    elseif program.interval then
      if iconJobs[row] and iconJobs[row].active and (iconJobs[row].iconRight==right or row.rclick==row.lclick) then iconJobs[row].active=false;iconJobs[row].thread=nil;row.active=false;row.running=false;iconNotice(row,script,'cancelled')
      else if iconJobs[row] then iconJobs[row].active=false;iconJobs[row].thread=nil end;local job,err=e.run(script);assert(job,err);job.iconRight=right;job.iconName=row.name;job.row.script=script;iconJobs[row]=job;row.active=true;row.running=true;row.runningRight=right;iconNotice(row,script,'enabled') end
    else local job,err=e.run(script);assert(job,err);job.iconName=row.name;job.row.script=script;row.active=not row.active;iconNotice(row,script,'executed') end
  end
  -- Valkor-style frame, caption and ON/OFF badge stay clickable even without an item.
  -- Reuse the button on clicks: do not destroy the native pressed widget mid-event.
  local function renderIcon(v,row)
    local active=iconActive(row);local state=iconState(row) or {};local size=v:getSize().width
    v:setBackgroundColor(row.background~=false and (state.background or (active and '#0a2b25dd' or '#081724cc')) or '#00000000')
    v:setBorderColor(active and '#00d3c8' or '#2a3a46')
    local text=state.text and state.text~='' and state.text or row.name
    if row.extraText then text=text..' '..row.extraText end
    v.caption:setText(text);v.caption:setColor(iconColor(row,state,v.iconHovered))
    v.badge:setText(active and 'ON' or 'OFF');v.badge:setBackgroundColor(active and '#149447' or '#b72f37')
    v:setTooltip(row.name..'\nLeft / right click: configured command. Drag to move.'..(data.botEnabled==false and '\nAutomation is OFF.' or '')..
      ((row.errors or {}).lclick and '\nLeft click needs editing' or '')..((row.errors or {}).rclick and '\nRight click needs editing' or ''))
    if v.iconState==state then return end
    local previous=v.iconState
    if previous and (previous.x~=state.x or previous.y~=state.y or previous.xMode~=state.xMode or previous.yMode~=state.yMode) then e.iconsDirty=true end
    v.iconState=state;v.items:destroyChildren()
    local content=size-26
    local function layer(ids,kind)
      if not ids or kind=='Text' then return end
      local many=(ids[2] or 0)>0 or (ids[3] or 0)>0 or (ids[4] or 0)>0
      for index,id in ipairs(ids) do if id>0 then
        local side=kind=='Resize' and (many and math.floor(content/2) or content) or 32
        local ix=many and ((index-1)%2)*side or (content-side)/2;local iy=many and math.floor((index-1)/2)*side or (content-side)/2
        if kind=='Center' or kind=='Center X' then ix=(content-side)/2 elseif kind=='Right' then ix=content-side elseif kind=='Left' then ix=0 end
        if kind=='Center' or kind=='Center Y' then iy=(content-side)/2 elseif kind=='Bottom' then iy=content-side elseif kind=='Top' then iy=0 end
        local function draw(x,y,w,h) local item=widget('UIItem',v.items,x,y,w,h);item:setBackgroundColor('#00000000');item:setBorderWidth(0);item:setVirtual(true);item:setItemId(id);item:setPhantom(true) end
        if kind=='Tile' then for tx=0,content-1,side do for ty=0,content-1,side do draw(tx,ty,math.min(side,content-tx),math.min(side,content-ty)) end end else draw(ix,iy,side,side) end
      end end
    end
    if row.background~=false then layer(state.bkgIds,state.bkgType) end
    layer(state.ids,state.type)
  end
  -- Migrate saved icons once; later visual updates must not start click scripts.
  for _,row in ipairs(data.icons) do if row.running==nil then row.running=row.active==true end end
  local function rebuildIcons()
    if iconDragging and uiVisible and data.iconsEnabled then e.iconsDirty=true;return end
    e.iconsDirty=false;clearIcons();iconControllers={}
    mapPanel:setMarginTop(originalTop+(uiVisible and data.iconsEnabled and data.iconsSpaceTop and (data.iconsLargeTop and 98 or 70) or 0))
    mapPanel:setMarginBottom(originalBottom+(uiVisible and data.iconsEnabled and data.iconsSpaceBottom and (data.iconsLargeBottom and 98 or 70) or 0))
    if not data.iconsEnabled then for row,job in pairs(iconJobs) do job.active=false;job.thread=nil;row.active=false;row.running=false end;return end
    if not uiVisible then return end
    local previousX,previousY=0,0
    for _,row in ipairs(data.icons) do
      local controller,consistent
      for _,script in ipairs({row.lclick or '',row.rclick or ''}) do if script:match('%S') then
        local ok,program=pcall(e.compile,script);local kind=ok and iconController(program)
        if not kind or controller and controller~=kind then consistent=false;break end
        controller=kind;consistent=true
      end end
      if consistent then iconControllers[row]=controller end
      local state=iconState(row) or {};local size=row.size=='Large' and 92 or row.size=='Medium' and 76 or 64;local height=size+6
      local rect=g_ui.getRootWidget():getPaddingRect();local x,y=state.x or 20,state.y or 80
      local widthLimit,heightLimit=math.max(0,rect.width-size),math.max(0,rect.height-height)
      if state.xMode=='Previous' then x=previousX+x
      elseif (state.xMode=='From right' or state.xMode=='Right') then x=widthLimit-x elseif state.xMode=='Center' then x=widthLimit/2+x elseif state.xMode=='Percent' then x=widthLimit*x/100 end
      if state.yMode=='Previous' then y=previousY+y
      elseif (state.yMode=='From bottom' or state.yMode=='Bottom') then y=heightLimit-y elseif state.yMode=='Center' then y=heightLimit/2+y elseif state.yMode=='Percent' then y=heightLimit*y/100 end
      x=math.floor(math.max(0,math.min(widthLimit,x)));y=math.floor(math.max(0,math.min(heightLimit,y)))
      -- Disabled icons still define anchors for subsequent entries in the script.
      previousX,previousY=x,y
      if row.enabled~=false then
      local resumeScript=row.runningRight and row.rclick or row.lclick
      if data.botEnabled~=false and not e.paused and row.running and (not iconJobs[row] or not iconJobs[row].active and not iconJobs[row].failed) and resumeScript and resumeScript~='' then local ok,program=pcall(e.compile,resumeScript);if ok and program.interval and not iconController(program) then local job=e.run(resumeScript);iconJobs[row]=job;if job then job.iconRight=row.runningRight==true;job.iconName=row.name;job.row.script=resumeScript end end end
      local v=widget('ElfBotIcon',g_ui.getRootWidget(),x,y,size,height,'');v.iconRow=row
      v.items=widget('UIWidget',v,13,18,size-26,size-26);v.items:setPhantom(true);v.items:setClipping(true)
      v.caption=widget('ElfBotIconCaption',v,3,3,size-6,14,'')
      v.badge=widget('ElfBotIconStatus',v,size-24,height-13,22,11,'')
      local function click(right)
        if not alive or v:isDestroyed() or not v:isVisible() or iconDragging then return end
        c.now=g_clock.millis();c.time=c.now
        local ok,err=pcall(iconCommand,row,right);if not ok then e.status=tostring(err);c.warn(e.status) end
        if alive and not v:isDestroyed() then renderIcon(v,row) end
      end
      v.onClick=function() click(false) end
      v.onMousePress=function() return true end
      v.onMouseRelease=function(self,pos,button)
        if not alive or self:isDestroyed() or not pos then return true end
        local p,s=self:getPosition(),self:getSize()
        if button==MouseRightButton and pos.x>=p.x and pos.y>=p.y and pos.x<p.x+s.width and pos.y<p.y+s.height then click(true) end
        return true
      end
      v.onHoverChange=function(_,hover) if not alive or v:isDestroyed() then return end;v.iconHovered=hover;v.caption:setColor(iconColor(row,iconState(row) or {},hover)) end
      v.onDragEnter=function(self,mouse)
        if not alive or self:isDestroyed() or not self:isVisible() then return false end
        local p=self:getPosition();iconDragging=self;self.dragReference={x=mouse.x-p.x,y=mouse.y-p.y};self.dragPosition=nil;self:raise();return true
      end
      v.onDragMove=function(self,mouse)
        if not alive or self:isDestroyed() or iconDragging~=self then return false end
        local bounds,s=self:getParent():getPaddingRect(),self:getSize()
        local nx=math.floor(math.max(0,math.min(math.max(0,bounds.width-s.width),mouse.x-self.dragReference.x-bounds.x)))
        local ny=math.floor(math.max(0,math.min(math.max(0,bounds.height-s.height),mouse.y-self.dragReference.y-bounds.y)))
        self:setMarginLeft(nx);self:setMarginTop(ny);self.dragPosition={x=nx,y=ny};return true
      end
      v.onDragLeave=function(self)
        if alive and not self:isDestroyed() and iconDragging==self and self.dragPosition and uiVisible then
          for _,key in ipairs({'offState','onState'}) do row[key]=row[key] or {};row[key].xMode='Absolute';row[key].yMode='Absolute';row[key].x=self.dragPosition.x;row[key].y=self.dragPosition.y end
          save();e.iconsDirty=true
        end
        if iconDragging==self then iconDragging=nil end;return true
      end
      renderIcon(v,row)
    end end
  end
  function e.importIcons(text)
    local imported,warnings=ElfBotIconImport.parse(text,e.compile)
    local buckets,occurrences={},{}
    for i,existing in ipairs(data.icons) do local key=existing.name:lower();buckets[key]=buckets[key] or {};table.insert(buckets[key],i) end
    for _,row in ipairs(imported) do
      local key=row.name:lower();occurrences[key]=(occurrences[key] or 0)+1;local index=buckets[key] and buckets[key][occurrences[key]]
      if index then local old=data.icons[index];if iconJobs[old] then iconJobs[old].active=false;iconJobs[old].thread=nil;iconJobs[old]=nil end;data.icons[index]=row else data.icons[#data.icons+1]=row end
    end
    data.iconsEnabled=true;data.awaitingLoad=nil;e.importWarnings=warnings;save();e.status='Imported '..#imported..' icons; '..#warnings..' click scripts need editing';rebuildIcons()
    if panels.icons and not panels.icons:isDestroyed() then panels.icons:destroy();panels.icons=nil end
    return #imported,warnings
  end
  function e.replaceIcons(text)
    local rows,warnings={},{}
    if text:match('%S') and not text:lower():match('^%s*%[icons%]%s*$') then rows,warnings=ElfBotIconImport.parse(text,e.compile) end
    -- Editor Save replaces the displayed document; file import remains a merge.
    for row,job in pairs(iconJobs) do job.active=false;job.thread=nil;row.active=false;row.running=false end
    iconJobs={};data.icons=rows;data.iconsEnabled=#rows>0;e.importWarnings=warnings
    save();rebuildIcons();e.status='Saved '..#rows..' icons; '..#warnings..' click scripts need editing'
    if panels.icons and not panels.icons:isDestroyed() then panels.icons:destroy();panels.icons=nil end
    return #rows,warnings
  end
  local function loadFiles()
    local win=window('Load ElfBot settings / scripts',650,430);panels.loadFiles=win
    label(win,0,0,630,'Choose a file below or enter its full Windows path. Preview checks scripts before loading.')
    local files=list(win,0,28,210,180)
    local report=widget('ElfBotMultilineTextEdit',win,222,28,428,180,'')
    local path=edit(win,0,237,650,'')
    label(win,0,211,640,'File path (original extensionless settings, .txt commands, [Icons], or ElfBot JSON):')
    label(win,0,271,640,'You can also copy files into elfbot/imports in client\'s AppData folder.')
    local function preview()
      local ok,result=pcall(c.previewElfFile,path:getText())
      if not ok then report:setText(tostring(result));return false end
      report:setText(ElfBotSettingsImport.summary(result)..'\n\n'..table.concat(result.warnings,'\n\n'))
      return true
    end
    local resources=c.g_resources
    local function refreshFiles()
      files:destroyChildren()
      for _,dir in ipairs({'/elfbot','/elfbot/imports','/elfbot/scripts'}) do
        local ok,names=pcall(resources.listDirectoryFiles,dir,false,false)
        if ok and type(names)=='table' then
          table.sort(names)
          for _,name in ipairs(names) do
            local full=dir..'/'..name
            if resources.fileExists(full) and name~='before-import.json' then
              local row=createRow('ElfBotRow',files);row:setText((dir~='/elfbot' and dir:sub(9)..'/' or '')..name)
              row.onFocusChange=function(_,focused) if focused then path:setText(full);preview() end end
              row.onDoubleClick=function() path:setText(full);if preview() then c.loadElfFile(full) end end
            end
          end
        end
      end
    end
    button(win,0,283,160,'Open saves folder',function()
      resources.makeDir('/elfbot');resources.makeDir('/elfbot/imports');resources.makeDir('/elfbot/scripts')
      g_platform.openDir(resources.getWriteDir()..'/elfbot')
    end)
    button(win,166,283,100,'Refresh files',refreshFiles)
    refreshFiles()
    button(win,0,310,100,'Preview',preview)
    button(win,106,310,100,'Load file',function() if preview() then c.loadElfFile(path:getText()) end end)
    button(win,212,310,140,'Paste script',function()
      scriptEditor('Load original ElfBot text',g_window.getClipboardText(),function(text) c.loadElfText(text) end)
    end)
    button(win,358,310,135,'Load selected slot',function() c.loadElfSlot(data.slot or 1) end)
    button(win,499,310,150,'Last import notices',function() report:setText(table.concat(data.importWarnings or {},'\n\n')) end)
    label(win,0,349,635,'Imported sections replace the matching sections. Other settings stay as they are.')
    label(win,0,374,635,'Unsupported scripts stay available to edit; invalid hotkeys are disabled.')
    status(win,0,397,635);return win
  end
  local function icons()
    local win=window('Command Icons',dx(378),dy(164));panels.icons=win
    dg(win,2,1,374,161,'Icon list');local names=list(win,dx(10),dy(12),dx(88),dy(107))
    dl(win,108,16,26,'Name');local name=de(win,134,16,94,'')
    dl(win,234,16,24,'Lclick');local left=de(win,258,16,108,'')
    dl(win,234,27,24,'Rclick');local right=de(win,258,27,108,'')
    dl(win,108,27,26,'Size');local size=dc(win,134,27,24,{'Small','Medium','Large'},'Small')
    local on=dk(win,162,27,24,'On',true,function() end);on:setTooltip('Show this icon. Commands run only when Automation is ON.')
    local bkg=dk(win,186,27,47,'Bkg Draw',true,function() end)
    local fields={};local types={'Normal','Resize','Top','Bottom','Left','Right','Tile','Center','Center X','Center Y','Text'}
    for i,kind in ipairs({'offState','onState'}) do
      local x=104+(i-1)*136;dg(win,x,44,132,92,i==1 and 'Inactive state' or 'Active state');local f={};fields[kind]=f
      dl(win,x+6,55,32,'Icon type');f.type=dc(win,x+40,55,42,types,'Normal')
      dl(win,x+6,66,32,'Icon ids');f.ids={};for n=1,4 do f.ids[n]=de(win,x+40+(n-1)*22,66,20,0) end
      dl(win,x+6,77,32,'Bkg type');f.bkgType=dc(win,x+40,77,42,types,'Normal')
      dl(win,x+6,88,32,'Bkg ids');f.bkgIds={};for n=1,4 do f.bkgIds[n]=de(win,x+40+(n-1)*22,88,20,0) end
      dl(win,x+6,99,32,'Xpos');f.xMode=dc(win,x+40,99,42,{'Absolute','Left','Right','Center','From right','Percent','Previous'},'Absolute');f.x=de(win,x+84,99,20,0)
      dl(win,x+6,110,32,'Ypos');f.yMode=dc(win,x+40,110,42,{'Absolute','Top','Bottom','Center','From bottom','Percent','Previous'},'Absolute');f.y=de(win,x+84,110,20,0)
      dl(win,x+6,121,32,'Text');f.text=de(win,x+40,121,42,'');f.foreground=colorField(win,dx(x+84),dy(121),dx(20),'#000000');f.hover=colorField(win,dx(x+106),dy(121),dx(20),'#000000');f.foreground:setHeight(dy(9));f.hover:setHeight(dy(9))
      f.foreground:setTooltip('Text color');f.hover:setTooltip('Hover text color')
    end
    left:setTooltip('ElfBot command, for example: auto 1000 say "exura"')
    right:setTooltip('Optional ElfBot command for the right mouse button')
    local enableIcons
    local selected;local function clear()
      selected=nil;name:setText('');left:setText('');right:setText('');on:setChecked(true);bkg:setChecked(true);size:setCurrentOption('Small')
      for kind,f in pairs(fields) do f.type:setCurrentOption('Resize');f.bkgType:setCurrentOption('Normal');f.xMode:setCurrentOption('Absolute');f.yMode:setCurrentOption('Absolute');f.x:setText(tostring(20+#data.icons*74));f.y:setText('80');f.text:setText('');for _,v in ipairs(f.ids) do v:setText('0') end;for _,v in ipairs(f.bkgIds) do v:setText('0') end;f.foreground:setText(kind=='onState' and '#55ff88' or '#ff5a61');f.hover:setText('#ffffff') end
    end
    local function refresh()
      names:destroyChildren();local new=createRow('ElfBotRow',names);new:setText('<New Icon>');new.onFocusChange=function(_,focus) if focus then clear() end end
      for i,row in ipairs(data.icons) do local index=i;local v=createRow('ElfBotRow',names);v:setText(row.name)
        v.onFocusChange=function(_,focus) if not focus then return end;selected=index;name:setText(row.name);left:setText(row.lclick or '');right:setText(row.rclick or '');size:setCurrentOption(row.size or 'Small');on:setChecked(row.enabled~=false);bkg:setChecked(row.background~=false)
          left:setTooltip((row.errors or {}).lclick or 'Left-click script');right:setTooltip((row.errors or {}).rclick or 'Right-click script')
          for kind,f in pairs(fields) do local state=row[kind] or {};f.type:setCurrentOption(state.type or 'Normal');f.bkgType:setCurrentOption(state.bkgType or 'Normal');f.xMode:setCurrentOption(state.xMode or 'Absolute');f.yMode:setCurrentOption(state.yMode or 'Absolute');f.x:setText(tostring(state.x or 0));f.y:setText(tostring(state.y or 0));f.text:setText(state.text or '');f.foreground:setText(state.foreground or '#000000');f.hover:setText(state.hover or state.foreground or '#000000');for n,v in ipairs(f.ids) do v:setText(tostring((state.ids or {})[n] or 0)) end;for n,v in ipairs(f.bkgIds) do v:setText(tostring((state.bkgIds or {})[n] or 0)) end end
        end
      end
      if selected and data.icons[selected] then selectRow(names:getChildByIndex(selected+1)) end
    end
    local function apply(copy)
      assert(name:getText():match('%S'),'Enter an icon name')
      local row={name=name:getText(),lclick=left:getText(),rclick=right:getText(),size=size:getCurrentOption().text,enabled=on:isChecked(),active=false,running=false,background=bkg:isChecked(),errors={}}
      -- Preserve broken imported clicks for editing without rejecting the valid side.
      for _,side in ipairs({'lclick','rclick'}) do if row[side]~='' then local ok,err=pcall(e.compile,row[side]);if not ok then row.errors[side]=tostring(err) end end end
      for kind,f in pairs(fields) do local state={type=f.type:getCurrentOption().text,ids={},bkgIds={},bkgType=f.bkgType:getCurrentOption().text,foreground=f.foreground:getText(),hover=f.hover:getText(),xMode=f.xMode:getCurrentOption().text,yMode=f.yMode:getCurrentOption().text,x=readNumber(f.x,-4000,4000),y=readNumber(f.y,-4000,4000),text=f.text:getText()};for n,v in ipairs(f.ids) do state.ids[n]=readNumber(v,0,65535) end;for n,v in ipairs(f.bkgIds) do state.bkgIds[n]=readNumber(v,0,65535) end;row[kind]=state end
      if selected and not copy then local previous=data.icons[selected];if iconJobs[previous] then iconJobs[previous].active=false;iconJobs[previous].thread=nil;iconJobs[previous]=nil end;data.icons[selected]=row else data.icons[#data.icons+1]=row;selected=#data.icons end
      if row.enabled then data.iconsEnabled=true;enableIcons:setChecked(true) end
      save();refresh();rebuildIcons();if next(row.errors) then e.status='Icon saved; invalid click scripts need editing' end
    end
    local function move(delta) assert(selected,'Select an icon');local index=math.max(1,math.min(#data.icons,selected+delta));local row=table.remove(data.icons,selected);table.insert(data.icons,index,row);selected=index;refresh();save() end
    db(win,8,123,14,13,'<',function() move(-1) end);db(win,26,123,14,13,'>',function() move(1) end)
    db(win,42,123,18,13,'Edit',function()
      scriptEditor('Icon Scripts',ElfBotIconImport.serialize(data.icons),function(text)
        e.replaceIcons(text)
      end,'Save')
    end):setTooltip('Paste or edit a complete [Icons] script')
    db(win,104,123,34,13,'Apply',function() apply(false) end):setTooltip('Save the icon fields')
    db(win,60,123,20,13,'Clear',clear)
    db(win,80,123,20,13,'Del',function() assert(selected,'Select an icon');local row=data.icons[selected];if iconJobs[row] then iconJobs[row].active=false;iconJobs[row].thread=nil;iconJobs[row]=nil end;table.remove(data.icons,selected);clear();refresh();save();rebuildIcons() end)
    enableIcons=dk(win,8,142,100,'Enable Icons',data.iconsEnabled,function(v) if data.iconsEnabled==v then return end;data.iconsEnabled=v;rebuildIcons();save() end)
    db(win,202,140,34,13,'Copy >>',function() apply(true) end)
    dk(win,242,140,93,'Make icon space top',data.iconsSpaceTop,function(v) data.iconsSpaceTop=v;rebuildIcons();save() end)
    dk(win,242,149,94,'Make icon space bottom',data.iconsSpaceBottom,function(v) data.iconsSpaceBottom=v;rebuildIcons();save() end)
    dk(win,338,140,34,'Large',data.iconsLargeTop,function(v) data.iconsLargeTop=v;rebuildIcons();save() end)
    dk(win,338,149,34,'Large',data.iconsLargeBottom,function(v) data.iconsLargeBottom=v;rebuildIcons();save() end)
    clear();refresh();return win
  end
  local function navigation()
    local win=window('Navigation',400,245);panels.navigation=win
    label(win,0,0,375,'Go to a coordinate through client pathfinding')
    local coords=edit(win,0,30,260,table.concat({c.posx(),c.posy(),c.posz()},','))
    button(win,270,30,110,'Navigate',function() local x,y,z=coords:getText():match('^(%d+),(%d+),(%d+)$');assert(x,'Expected x,y,z');assert(c.autoWalk({x=tonumber(x),y=tonumber(y),z=tonumber(z)},200,{precision=0}),'No path found') end)
    label(win,0,69,375,'Exiva player');local playerName=edit(win,0,96,260,'')
    button(win,270,96,110,'Exiva',function() c.saySpell('exiva "'..playerName:getText(),1000) end)
    button(win,0,138,140,'Stop walking',function() c.g_game.stop() end)
    status(win,0,178,375);return win
  end
  local function spy()
    local win=window('Creature Spy',440,294);panels.spy=win
    local text=widget('ElfBotSpyText',win,0,0,440,294,'');e.spyWidget=text;return win
  end
  function e.spyText()
    local origin=c.pos();local floors={};for _,creature in ipairs(c.getSpectators(true)) do local p=creature:getPosition();if p then floors[p.z]=floors[p.z] or {};floors[p.z][#floors[p.z]+1]=creature end end
    local keys={};for z in pairs(floors) do keys[#keys+1]=z end;table.sort(keys,function(a,b) return a>b end)
    local lines={};for _,z in ipairs(keys) do
      local relative=origin.z-z;lines[#lines+1]=relative==0 and ('***Level '..z..'***') or string.format('***Level %+d***',relative)
      table.sort(floors[z],function(a,b) return a:getName()<b:getName() end)
      for _,creature in ipairs(floors[z]) do local p=creature:getPosition();local speed=creature.getSpeed and creature:getSpeed() or '?';local base=creature.getBaseSpeed and creature:getBaseSpeed() or '?'
        lines[#lines+1]=string.format('%-16s Pos: (%+d,%+d)  Health: %3d%%  Speed: %s (%s)',creature:getName():sub(1,16),p.x-origin.x,p.y-origin.y,creature:getHealthPercent(),tostring(speed),tostring(base))
      end;lines[#lines+1]=''
    end;return table.concat(lines,'\n')
  end
  local function reconnect()
    local win=window('Reconnect',395,160);panels.reconnect=win
    check(win,0,0,370,'Reconnect after disconnection',data.extras.reconnect,function(v) data.extras.reconnect=v;save() end)
    label(win,0,37,130,'Delay (seconds)');local delay=numberField(win,140,34,75,data.extras.reconnectDelay or 5)
    button(win,0,75,95,'Save',function() data.extras.reconnectDelay=readNumber(delay,3,300);save() end)
    button(win,105,75,135,'Reconnect now',function() c.requestElfReconnect() end)
    label(win,0,117,370,'Uses the selected character and client login session.');return win
  end
  local menu=window('ElfBot OTC v.1',550,100)
  local function updateCaption()
    local stats=e.getSessionStats()
    local playerName=stats.name~='' and stats.name or 'Startup'
    menu.titleBar:setText(e.caption or ('ElfBot OTC - '..playerName..' - Slot '..(data.slot or 1)..' - '..(c.ping and c.ping() or 0)..' ms - '..ElfBotSession.formatNumber(stats.perHour)..' exp/hour'))
    menu:setTooltip('ElfBot OTC v.1\nPlayer: '..playerName..'\nSession: '..stats.timeText..
      '\nXP gained: '..ElfBotSession.formatNumber(stats.gained)..'\nAverage XP/hour: '..ElfBotSession.formatNumber(stats.perHour)..
      (stats.ready and '' or '\nWaiting for valid character statistics'))
    return stats
  end
  updateCaption()
  local function hideAll() uiVisible=false;e.hudVisible=false;if e.clearPlayerLabels then e.clearPlayerLabels() end;if e.clearWallTimers then e.clearWallTimers() end;rebuildIcons();clearOverlays();hudDisplay.hide();for _,v in ipairs(windows) do if not v:isDestroyed() then v:hide() end end end
  local function showMenu() uiVisible=true;e.hudVisible=true;local stats=updateCaption();show(menu);rebuildIcons();hudDisplay.update(true,stats);c.playSound('/game_elfbot/sounds/elfng.ogg') end
  local function open(key,create) show(panels[key] or create()) end
  local commandsView=function() local names={};for name in pairs(e.commands) do names[#names+1]=name end;table.sort(names);scriptEditor('Supported ElfBot commands',table.concat(names,'\n'),function() end) end
  local rows={
    {{'Healing',function() open('healing',healing) end},{'Aimbot',function() open('aimbot',aimbot) end},{'Lists',function() open('lists',listsPanel) end},{'HUD',function() open('hud',hud) end}},
    {{'Extras',function() open('extras',extras) end},{'Hotkeys',function() open('hotkeys',function() return bindings('hotkeys') end) end},{'Shortkeys',function() open('shortkeys',function() return bindings('shortkeys') end) end},{'Reconnect',function() open('reconnect',reconnect) end}},
    {{'Cavebot',function() open('cavebot',cavebot) end},{'Navigation',function() open('navigation',navigation) end},{'Creature Spy',function() open('spy',spy) end}},
    {{'Targeting',function() open('targeting',targeting) end},{'Icons',function() open('icons',icons) end}}
  }
  for y,row in ipairs(rows) do for x,entry in ipairs(row) do button(menu,(x-1)*96,(y-1)*26,94,entry[1],entry[2]) end end
  for i=1,5 do local index=i;button(menu,388+(i-1)*32,0,30,tostring(i),function() data.slot=index;e.status='Selected settings slot '..index end) end
  local function chooseSettingsFile()
    if g_platform.selectElfBotFile then
      local resources=c.g_resources;resources.makeDir('/elfbot')
      g_platform.selectElfBotFile(resources.getWriteDir()..'/elfbot',function(path)
        if not alive or not path or path=='' then return end
        local ok,result=pcall(c.previewElfFile,path)
        if not ok then e.status='Selection failed: '..tostring(result);c.warn(e.status);return end
        selectedSettingsPath=path;e.status='Selected '..path..'. Click Load to apply. '..ElfBotSettingsImport.summary(result)
        if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then modules.game_textmessage.displayStatusMessage(e.status) else c.info(e.status) end
      end)
    else open('loadFiles',loadFiles) end
  end
  local right={{'Save',function() c.saveElfSlot(data.slot or 1) end},{'Custom',chooseSettingsFile},{'Load',function()
    if selectedSettingsPath and selectedSettingsPath~='' then c.loadElfFile(selectedSettingsPath)
    elseif g_platform.selectElfBotFile then c.loadElfSlot(data.slot or 1)
    else open('loadFiles',loadFiles) end
  end},{'Help',commandsView}}
  for i,entry in ipairs(right) do button(menu,388+(i-1)%2*82,26+math.floor((i-1)/2)*26,80,entry[1],entry[2]) end
  local enableButton=button(menu,388,78,162,'Automation: OFF',function() c.setElfEnabled(not c.isElfEnabled()) end)
  local function updateEnabled()
    local enabled=c.isElfEnabled()
    enableButton:setText(enabled and 'Automation: ON' or 'Automation: OFF')
    enableButton:setOn(enabled)
  end
  updateEnabled()
  menu.onEscape=hideAll
  menu.closeButton.onClick=hideAll
  local nextDisplay=0
  local oldTick=e.tick
  e.tick=function()
    oldTick()
    if c.now<nextDisplay then return end;nextDisplay=c.now+500
    for i=#windows,1,-1 do if windows[i]:isDestroyed() then table.remove(windows,i) end end
    for i=#statusLabels,1,-1 do if statusLabels[i]:isDestroyed() then table.remove(statusLabels,i) end end
    updateEnabled()
    local rect=g_ui.getRootWidget():getPaddingRect()
    local iconSignature=tostring(data.iconsEnabled)..tostring(data.iconsSpaceTop)..tostring(data.iconsSpaceBottom)..':'..rect.width..':'..rect.height
    if e.iconsDirty or iconSignature~=e.iconSignature then e.iconSignature=iconSignature;rebuildIcons() end
    local changed=false;for row,job in pairs(iconJobs) do if job.failed and row.running then row.active=false;row.running=false;changed=true end end;if changed then rebuildIcons() end
    for _,v in ipairs(iconWidgets) do if not v:isDestroyed() and v.iconRow then renderIcon(v,v.iconRow) end end
    local session=updateCaption()
    e.updatePlayerLabels(uiVisible)
    if e.spyWidget and not e.spyWidget:isDestroyed() and panels.spy:isVisible() then e.spyWidget:setText(e.spyText()) end
    clearOverlays()
    local function overlay(text,x,y,color) if not uiVisible then return end;local v=widget('ElfBotOverlay',g_ui.getRootWidget(),x,y,700,16,tostring(text));v:setColor(color or '#ffffff');v:setPhantom(true);overlays[#overlays+1]=v end
    local function rgb(color) return color and string.format('#%02x%02x%02x',color[1],color[2],color[3]) or '#ffffff' end
    for key,display in pairs(e.displays or {}) do if c.now>display.expires then e.displays[key]=nil else overlay(display.text,display.x,display.y,rgb(display.color)) end end
    for _,box in pairs(e.listboxes) do for i,line in ipairs(box.lines) do local offset=box.direction=='up' and -(#box.lines-i+1)*15 or (i-1)*15;overlay(line.text,box.x,box.y+offset,rgb(line.color)) end end
    hudDisplay.update(uiVisible,session)
    if data.lists.colors then for _,spec in ipairs(c.getSpectators()) do if spec:isPlayer() and spec~=c.player then local color=e.listContains('enemies',spec:getName()) and '#ff4040' or e.listContains('friends',spec:getName()) and '#40ff40' or nil;if color then spec:setMarked(color) end end end end
  end
  e.onReload=function() iconJobs={};e.displays={};clearOverlays();rebuildIcons() end
  rebuildIcons()
  -- Login can precede inventory packets. Try for five seconds without blocking startup.
  local backpackDeadline=data.extras.openBackpacks and c.now+5000
  local nextBackpackTry=c.now
  if data.extras.loadAtLogin then showMenu() end

  chatFilter=function(text) return alive and e.shortkey(text) or false end
  if modules.game_console.addFilter then modules.game_console.addFilter(chatFilter) end
  function e.loadCaveKeys() e.reload() end
  local rawTick=e.tick
  e.tick=function()
    -- Cavebot hotkeys only run while Follow waypoints is enabled.
    for _,job in ipairs(e.jobs) do if job.kind=='cave' then job.row.enabled=c.CaveBot and c.CaveBot.isOn() or false end end
    rawTick()
    if data.botEnabled~=false and backpackDeadline and c.now>=nextBackpackTry then
      nextBackpackTry=c.now+250
      local player=c.g_game.getLocalPlayer()
      local item=player and player:getInventoryItem(3)
      if item then
        local ok,result=pcall(c.g_game.open,item)
        if not ok then backpackDeadline=nil;e.status='Unable to open backpack: '..tostring(result)
        elseif result~=-1 then backpackDeadline=nil end
      end
      if backpackDeadline and c.now>=backpackDeadline then
        backpackDeadline=nil;e.status=item and 'Opening backpack at login skipped: no container slot available' or 'No backpack equipped; opening at login skipped'
      end
    end
    e.healTick();e.lootTick()
    if e.syncWaypointSelection then e.syncWaypointSelection() end
    if e.followCheck and not e.followCheck:isDestroyed() then
      local value=c.CaveBot and c.CaveBot.isOn() or false
      if e.followCheck:isChecked()~=value then e.syncFollow=true;e.followCheck:setChecked(value);e.syncFollow=false end
    end
    for _,v in ipairs(statusLabels) do if not v:isDestroyed() and v:getText()~=e.status then v:setText(e.status) end end
  end
  function e.healTick()
    local h=data.healing;if e.paused or not h or not h.enabled or c.now<(e.nextHeal or 0) then return end
    e.nextHeal=c.now+(h.delay or 1000)
    local hp,mp=c.hppercent(),c.mana()
    if hp<=math.max(h.hiHealth or 90,h.loHealth or 50,h.hpHealth or 40) then e.healingBusyUntil=c.now+(h.delay or 1000) end
    if c.now>=(e.nextPotion or 0) then
      if h.uhEnabled and hp<=(h.uhHealth or 40) then c.useWith(data.items.uh,c.player);e.nextPotion=c.now+(h.potionWait or 1000)
      elseif h.hpEnabled~=false and type(e.commands[h.hpType])=='function' and hp<=h.hpHealth then e.commands[h.hpType]({h.hpHealth,'self'});e.nextPotion=c.now+(h.potionWait or 1000)
      elseif h.mpEnabled~=false and type(e.commands[h.mpType])=='function' and c.manapercent()<=h.mpMana then e.commands[h.mpType]({'self'});e.nextPotion=c.now+(h.potionWait or 1000) end
    end
    if h.friendEnabled~=false and h.friend and h.friend~='' and mp>=(h.friendMana or 160) then
      local friend=e.getCreature(h.friend);if friend and friend:isPlayer() and friend:getHealthPercent()<=(h.friendHealth or 60) then c.saySpell('exura sio "'..friend:getName(),1000);return end
    end
    if h.loEnabled~=false and hp<=h.loHealth and mp>=h.loMana then c.saySpell(h.loSpell,1000)
    elseif h.hiEnabled~=false and hp<=h.hiHealth and mp>=h.hiMana then c.saySpell(h.hiSpell,1000)
    elseif h.paralysis and c.isParalyzed() then c.saySpell(h.hiSpell,1000) end
  end
  function e.lootTick() end
  local function alert(key)
    if data.botEnabled==false then return end
    local a=data.alerts and data.alerts[key];if not a or c.now<(e.nextAlert or 0) then return end
    if not a.sound and not a.pause and not a.logout then return end
    e.nextAlert=c.now+3000;e.status='Alert: '..key
    if a.sound then local names={player='playeronscreen',attack='playerattacking',private='privatemessage',default='defaultmessage',gm='gmdetected',disconnected='disconnected'};c.playSound('/game_elfbot/sounds/'..names[key]..'.ogg') end
    if a.pause and c.CaveBot then c.CaveBot.setOff() end
    if a.logout and key~='disconnected' then c.safeLogout() end
  end
  c.onCreatureAppear(function(creature) if creature:isPlayer() and creature~=c.player then local name=creature:getName():lower();if name:match('^gm[%s_]') or name:match('^cm[%s_]') or name:find('gamemaster',1,true) then alert('gm') else alert('player') end end end)
  c.onTalk(function(name,level,mode,text) if name~=c.name() then
    if mode==MessageModes.PrivateFrom then alert('private') elseif mode==MessageModes.Say then alert('default') end
  end end)
  c.onTextMessage(function(mode,text) if text:lower():find('you lose') and text:lower():find('attack by') then alert('attack') end end)
  local api={}
  api.tick=e.tick
  api.disconnected=function() alert('disconnected') end
  api.show=showMenu
  api.automationChanged=function() updateEnabled();rebuildIcons() end
  api.isVisible=function() return menu:isVisible() end
  api.hide=hideAll
  api.toggle=function() if menu:isVisible() then hideAll() else showMenu() end end
  local function editingText()
    local focus=g_ui.getRootWidget():getFocusedChild()
    while focus do
      if focus:getClassName()=='UITextEdit' then return true end
      focus=focus:getFocusedChild()
    end
    return false
  end
  api.keyDown=function(key) if editingText() then return false end;return e.key(key,false) end
  api.keyPress=function(key) if editingText() then return false end;return e.key(key,true) end
  api.dispose=function()
    e.disposeInterface()
    if e.disposeControllers then e.disposeControllers() end
  end
  return api
end
