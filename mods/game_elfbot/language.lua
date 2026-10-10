-- ElfBot command language. No Lua code is evaluated from user commands.
ElfBotLanguage = {}
local L = ElfBotLanguage
local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
L.truth = function(v) return v ~= nil and v ~= false and v ~= 0 and v ~= '' end

local function lex(source)
  local out, i = {}, 1
  local function add(kind, value) out[#out + 1] = {kind=kind, value=value, at=i} end
  while i <= #source do
    local c = source:sub(i,i)
    if c == '\r' or c == ' ' or c == '\t' then i=i+1
    elseif c == '\n' then add('|','|');out[#out].newline=true;i=i+1
    elseif c == "'" or c == '"' then
      local q, value, start = c, '', i; i=i+1
      while i <= #source and source:sub(i,i) ~= q do
        c=source:sub(i,i)
        if c == '\\' and source:sub(i+1,i+1) == q then i=i+1; c=q end
        value=value..c; i=i+1
      end
      assert(i <= #source, 'Unclosed quote at '..start)
      add('string',value); i=i+1
    elseif c == '$' then
      local start=i; i=i+1
      local name=source:sub(i):match('^[%w_]+')
      assert(name, 'Expected variable name at '..start); i=i+#name
      while source:sub(i,i)=='.' do
        i=i+1; c=source:sub(i,i)
        if c=="'" or c=='"' then
          local q=c; i=i+1; local j=source:find(q,i,true)
          assert(j,'Unclosed variable member'); name=name..'.'..source:sub(i,j-1); i=j+1
        else
          local member=source:sub(i):match('^%$?[%w_]+')
          assert(member,'Expected variable member'); name=name..'.'..member; i=i+#member
        end
      end
      add('var',name)
    elseif c:match('%d') then
      local number=source:sub(i):match('^%d+%.?%d*'); add('number',tonumber(number)); i=i+#number
    else
      local two=source:sub(i,i+1)
      if two=='=>' then two='>=' elseif two=='=<' then two='<=' end
      if two=='&&' or two=='||' or two=='==' or two=='!=' or two=='<=' or two=='>=' then add('op',two); i=i+2
      elseif c:match('[%[%]{}()|]') then add(c,c); i=i+1
      elseif c:match('[+*/%%<>!=%-]') then add('op',c); i=i+1
      else
        local word=source:sub(i):match([[^[^%s%[%]{}()|+*/%%<>!=%-$'"]+]])
        assert(word and #word>0,'Unexpected character at '..i)
        add('word',word); i=i+#word
      end
    end
  end
  out[#out+1]={kind='eof',value='',at=i}; return out
end
local precedence={['||']=1,['&&']=2,['==']=3,['!=']=3,['=']=3,['<']=4,['>']=4,['<=']=4,['>=']=4,['+']=5,['-']=5,['*']=6,['/']=6,['%']=6}
local predicates={ifhasted='hasted',ifnothasted='!hasted',ifparalyzed='paralyzed',ifnotparalyzed='!paralyzed',
  ifmanashielded='manashielded',ifnotmanashielded='!manashielded',ifdrunk='drunk',ifpoisoned='poisoned',safe='safetoact',
  ifdefaultmessage='defaultmessage',ifprivatemessage='privatemessage',ifplayerattacking='playerattacking',ifgm='gm',ifnogm='!gm',
  isattacking='attacking',isnotattacking='!attacking',istargeting='targetingon',isnottargeting='!targetingon',
  ifplayeronscreen='playersaround.7',ifnoplayeronscreen='!playersaround.7',ifmonstersonscreen='monstersaround.7',ifnomonstersonscreen='!monstersaround.7'}
function L.compile(source, commands)
  assert(type(source)=='string' and #source<=32768,'Script must be at most 32768 characters')
  local tokens, pos, nodes = lex(source), 1, 0
  local function peek() return tokens[pos] end
  local function take() local t=tokens[pos];pos=pos+1;return t end
  local function expect(kind) local t=take(); assert(t.kind==kind,'Expected '..kind..' at '..t.at);return t end
  local expression, statement, sequence
  expression=function(minimum, depth)
    depth=(depth or 0)+1; assert(depth<=64,'Expression is too deeply nested')
    local t=take(); local left
    if t.kind=='number' or t.kind=='string' then left={kind='literal',value=t.value}
    elseif t.kind=='var' then left={kind='variable',name=t.value}
    elseif t.kind=='op' and (t.value=='!' or t.value=='-') then left={kind='unary',op=t.value,right=expression(7,depth)}
    elseif t.kind=='(' then left=expression(1,depth);expect(')')
    elseif t.kind=='word' then left={kind='literal',value=t.value}
    else error('Expected expression at '..t.at) end
    while peek().kind=='op' and precedence[peek().value] and precedence[peek().value]>=minimum do
      local op=take().value; left={kind='binary',op=op,left=left,right=expression(precedence[op]+1,depth)}
    end
    return left
  end
  local function argument()
    if peek().kind=='[' then take();local e=expression(1);expect(']');return e end
    if peek().kind=='(' then take();local e=expression(1);expect(')');return e end
    local t=take()
    if t.kind=='var' then return {kind='variable',name=t.value} end
    if t.kind=='op' and t.value=='-' then return {kind='literal',value=-expect('number').value} end
    assert(t.kind=='word' or t.kind=='string' or t.kind=='number','Expected argument at '..t.at)
    return {kind='literal',value=t.value,quoted=t.kind=='string'}
  end
  local function body(depth)
    if peek().kind=='{' then take();local b=sequence(depth+1);expect('}');return b end
    return {statement(depth+1)}
  end
  local function conditional(kind,condition,depth,invert)
    local node={kind=kind,condition=condition,invert=invert,body=body(depth)}
    if kind~='while' then
      -- Else also belongs to legacy predicates (isdistance, hplower, etc.).
      -- Newlines are whitespace here only when an else actually follows.
      local nextPos=pos
      while tokens[nextPos].newline do nextPos=nextPos+1 end
      if tokens[nextPos].kind=='word' and tokens[nextPos].value:lower()=='else' then
        pos=nextPos+1;node.otherwise=body(depth)
      end
    end
    return node
  end
  statement=function(depth)
    assert(depth<=48,'Script is too deeply nested');nodes=nodes+1;assert(nodes<=2048,'Script has too many statements')
    if peek().kind=='{' then take();local b=sequence(depth+1);expect('}');return {kind='block',body=b} end
    if peek().kind=='var' then
      local variable=take();return {kind='command',name='set',args={{kind='variable',name=variable.value},argument()}}
    end
    local t=expect('word');local name=t.value:lower()
    if name=='foreach' then
      local list=argument();local variable=expect('var')
      return {kind='foreach',list=list,variable=variable.value,body=body(depth)}
    elseif name=='loop' and peek().kind~='|' and peek().kind~='eof' and peek().kind~='}' then
      return {kind='repeat',count=argument(),body=body(depth)}
    end
    local comparisons={hplower={'hp','<'},hphigher={'hp','>'},mplower={'mp','<'},mphigher={'mp','>'},
      hpmissinglower={'hpmissing','<'},hpmissinghigher={'hpmissing','>'},mpmissinglower={'mpmissing','<'},mpmissinghigher={'mpmissing','>'},
      targethplower={'target.hppc','<'},counthigher={'count','>'},countlower={'count','<'},caplower={'cap','<'},caphigher={'cap','>'},isposz={'posz','=='}}
    if comparisons[name] then
      local p=comparisons[name];return conditional('if',{kind='binary',op=p[2],left={kind='variable',name=p[1]},right=argument()},depth)
    end
    if name=='islocation' or name=='isnotlocation' then return conditional('if',{kind='predicate',name=name,args={}},depth) end
    if name=='isonscreen' or name=='isnotonscreen' or name=='isattackedname' or name=='istargetname' or name=='isdistance' or name=='isnotdistance' then
      return conditional('if',{kind='predicate',name=name,args={argument()}},depth)
    end
    if name=='if' or name=='ifnot' or name=='while' then
      local condition
      if peek().kind=='[' then take();condition=expression(1);expect(']') else condition=argument() end
      return conditional(name=='while' and 'while' or 'if',condition,depth,name=='ifnot')
    elseif predicates[name] then
      local variable=predicates[name];local invert=variable:sub(1,1)=='!'
      return conditional('if',{kind='variable',name=invert and variable:sub(2) or variable},depth,invert)
    end
    assert(commands[name] or name=='wait' or name=='end' or name=='loop' or name=='set' or name=='inc' or name=='dec' or name=='clear', 'Unsupported ElfBot command: '..name)
    local args={}
    while peek().kind~='|' and peek().kind~='}' and peek().kind~='eof' and not (peek().kind=='word' and peek().value:lower()=='else') do args[#args+1]=argument() end
    return {kind='command',name=name,args=args}
  end
  sequence=function(depth)
    local result={}
    while peek().kind~='eof' and peek().kind~='}' do
      if peek().kind=='|' then take() else result[#result+1]=statement(depth) end
    end
    return result
  end
  local interval
  if peek().kind=='word' and peek().value:lower()=='auto' then
    take();interval=expect('number').value
    assert(interval>=1 and interval<=86400000,'auto interval must be 1..86400000 milliseconds')
  end
  local program={body=sequence(0),interval=interval,source=source};expect('eof');return program
end
local function scalar(v) if type(v)=='boolean' then return v and 1 or 0 end;return v end
function L.evaluate(node, env)
  if node.kind=='literal' then
    if type(node.value)=='string' then return (node.value:gsub('%$([%w_]+[%w_%.%$]*)',function(name) return tostring(env.resolve(name) or 0) end)) end
    return node.value
  elseif node.kind=='predicate' then local args={};for i,arg in ipairs(node.args) do args[i]=L.evaluate(arg,env) end;return env.predicate(node.name,args)
  elseif node.kind=='variable' then return env.resolve(node.name)
  elseif node.kind=='unary' then
    local v=L.evaluate(node.right,env);if node.op=='!' then return not L.truth(v) end;return -assert(tonumber(v),'Expected number')
  end
  local a=L.evaluate(node.left,env);local op=node.op
  if op=='&&' then return L.truth(a) and L.truth(L.evaluate(node.right,env)) end
  if op=='||' then return L.truth(a) or L.truth(L.evaluate(node.right,env)) end
  local b=L.evaluate(node.right,env);a=scalar(a);b=scalar(b)
  if op=='==' or op=='=' then return a==b elseif op=='!=' then return a~=b end
  a=assert(tonumber(a),'Expected numeric left operand');b=assert(tonumber(b),'Expected numeric right operand')
  if op=='<' then return a<b elseif op=='>' then return a>b elseif op=='<=' then return a<=b elseif op=='>=' then return a>=b
  elseif op=='+' then return a+b elseif op=='-' then return a-b elseif op=='*' then return a*b
  elseif op=='/' then assert(b~=0,'Division by zero');return a/b elseif op=='%' then assert(b~=0,'Division by zero');return a%b end
end
function L.start(program, env)
  return coroutine.create(function()
    local budget=0;local run
    local function step() budget=budget+1;assert(budget<=20000,'Script execution limit exceeded') end
    local execDepth=0
    env.exec=function(program)
      execDepth=execDepth+1;assert(execDepth<=8,'exec nesting limit exceeded')
      local result=run(program.body);execDepth=execDepth-1;return result
    end
    run=function(body)
      for _,node in ipairs(body) do
        step()
        if node.kind=='block' then if run(node.body)=='end' then return 'end' end
        elseif node.kind=='if' then
          local pass=L.truth(L.evaluate(node.condition,env));if node.invert then pass=not pass end
          if run(pass and node.body or node.otherwise or {})=='end' then return 'end' end
        elseif node.kind=='foreach' then
          local list=env.iterate(L.evaluate(node.list,env));assert(#list<=256,'Too many creatures in foreach')
          local old=env.locals[node.variable]
          for _,creature in ipairs(list) do
            step();env.locals[node.variable]=creature
            local result=run(node.body);if result=='end' then env.locals[node.variable]=old;return 'end' end
          end
          env.locals[node.variable]=old
        elseif node.kind=='repeat' then
          local count=assert(tonumber(L.evaluate(node.count,env)),'loop needs a count');assert(count>=0 and count<=1000,'loop count must be 0..1000')
          for i=1,math.floor(count) do step();if run(node.body)=='end' then return 'end' end end
        elseif node.kind=='while' then
          while L.truth(L.evaluate(node.condition,env)) do
            step();if run(node.body)=='end' then return 'end' end
            coroutine.yield(50);budget=0
          end
        else
          local name,args=node.name,{}
          for i,arg in ipairs(node.args) do args[i]=L.evaluate(arg,env) end
          if name=='end' then return 'end'
          elseif name=='loop' then return 'end'
          elseif name=='wait' then
            local duration=assert(tonumber(args[1]),'wait needs milliseconds');assert(duration>=0 and duration<=86400000,'Invalid wait duration')
            coroutine.yield(math.max(1,duration));budget=0
          elseif name=='set' or name=='clear' or name=='inc' or name=='dec' then
            local variable=node.args[1];assert(variable and variable.kind=='variable','Expected $variable')
            local value=args[2] or 0
            if name=='clear' then value=0 elseif name=='inc' then value=(tonumber(env.resolve(variable.name)) or 0)+(args[2] or 1)
            elseif name=='dec' then value=(tonumber(env.resolve(variable.name)) or 0)-(args[2] or 1) end
            env.assign(variable.name,value)
          else env.commands[name](args,env);if env.stop then env.stop=nil;return 'end' end end
        end
      end
    end
    run(program.body)
  end)
end
function L.resume(thread)
  local ok,delay=coroutine.resume(thread)
  if not ok then return nil,delay end
  if coroutine.status(thread)=='dead' then return true end
  return false,tonumber(delay) or 50
end
