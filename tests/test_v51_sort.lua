local path=assert(arg[1])
local titles={
[38]='No es mi circo ni son mis monos',
[39]='La hoja más afilada',
[41]='Conseguir la mercancía',
[42]='La deuda de Tazzik',
[43]='Vendas para heridas',
[60]='Libranza del artesano: bomba Hierro Negro',
[61]='Libranza del artesano: juego de reparación mecánico',
}
local levels={[38]=38,[39]=38,[41]=40,[42]=40,[43]=40,[60]=60,[61]=60}
local emptyTitle=false
C_QuestLog={
 GetQuestDifficultyLevel=function(id) return levels[id] end,
 GetTitleForQuestID=function(id) if emptyTitle and id==41 then return nil end return titles[id] end,
 GetLogIndexForQuestID=function(id) return id end,
 GetInfo=function(id) return {questID=id,title=titles[id],difficultyLevel=levels[id]} end,
}
local mode='zone_level_asc'
local ns={Config={Settings=function() return {trackerSortMode=mode} end}}
assert(loadfile(path))('addon',ns)
local function make(ids)
 local a={}
 for i,id in ipairs(ids) do
  a[#a+1]={id=id,zone=id<50 and 'Clarofluvial' or 'Fabricación',original=i}
 end
 return a
end
local function get(a)
 local out={}
 for _,v in ipairs(a) do out[#out+1]=v.id end
 return table.concat(out,',')
end
local e1=make({38,39,41,42,43,60,61})
local e2=make({39,38,43,42,41,61,60})
ns.TrackerSort.Order(e1,true)
emptyTitle=true -- simula valor nil transitorio durante el filtro
ns.TrackerSort.Order(e2,true)
assert(get(e1)=='39,38,41,42,43,60,61','orden 1 no es alfabético por nivel: '..get(e1))
assert(get(e2)==get(e1),'alternancia de orden al restaurar seguimiento: '..get(e1)..' / '..get(e2))
mode='native'
local e3=make({38,39,43,41,42,61,60})
ns.TrackerSort.Order(e3,true)
assert(get(e3)==get(e1),'modo native agrupado no es determinista: '..get(e3))
print('OK ordenacion por nivel + nombre estable ante swaps y títulos temporalmente nulos')
