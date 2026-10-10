assert(loadfile('modules/gamelib/core/mapmarkers.lua'))()
local index = MapMarkerIndex.create()
for id = 1, 20000 do
  assert(index:insert({id=id, position={x=id%256+30000,y=math.floor(id/256)+30000,z=7}, imagePath='flag3', priority=0}))
end
assert(index:insert({id='near', position={x=1000,y=1000,z=7}, imagePath='flag3', priority=1}))
assert(index:insert({id='far', position={x=1001,y=1001,z=7}, imagePath='flag4', priority=0, positionKey='1001,1001,7'}))
local center, rect = {x=1000,y=1000}, {left=990,top=990,right=1010,bottom=1010}
local found = index:query(rect,7,center,128)
assert(#found==2 and found[1].record.id=='near')
assert(#index:query(rect,8,center,128)==0)
assert(#index:query(rect,7,center,128,{flag3=true})==1)
assert(#index:query(rect,7,center,128,nil,{near=true,far=true})==0)
assert(#index:query(rect,7,center,128,nil,nil,{['1001,1001,7']=true})==1)
index:remove('near'); assert(#index:query(rect,7,center,128)==1)
assert(index:insert({id='far', position={x=1000,y=1000,z=6}, imagePath='flag4'}))
assert(#index:query(rect,7,center,128)==0 and #index:query(rect,6,center,128)==1)
assert(not index:insert({id='bad',position={x=-1,y=5,z=7}}))
local wide = {left=0,top=0,right=65535,bottom=65535}
local expected = {}
for id, record in pairs(index.records) do
  if record.position.z==7 then expected[#expected+1]={id=id,distance=(record.position.x-center.x)^2+(record.position.y-center.y)^2} end
end
table.sort(expected,function(a,b) if a.distance~=b.distance then return a.distance<b.distance end; return tostring(a.id)<tostring(b.id) end)
local best = index:query(wide,7,center,128)
for i=1,128 do assert(best[i].record.id==expected[i].id, 'Heap did not select nearest deterministic top-k') end
local start = os.clock()
for _=1,100 do assert(#index:query(wide,7,center,128)==128) end
print(string.format('PASS: 20k data markers, spatial/floor culling, priority, filters, bounded top-k, removal/move; 100 wide queries %.3fs',os.clock()-start))
