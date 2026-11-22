local statusPath,filterPath=assert(arg[1]),assert(arg[2])
local logIds={100,101,102}
local watched={100,102}
local snapshots={}
local refreshCount=0
local eventCallback
local events={RegisterEvent=function()end,SetScript=function(self,name,callback) if name=='OnEvent' then eventCallback=callback end end}
CreateFrame=function() return events end
C_Timer={After=function(delay,cb) cb() end}
C_QuestLog={
 GetNumQuestLogEntries=function() return #logIds end,
 GetLogIndexForQuestID=function(id) for i,j in ipairs(logIds) do if id==j then return i end end end,
 GetInfo=function(i) local id=logIds[i];return {questID=id,isHeader=false,title='Quest '..id,isComplete=id==101} end,
 GetQuestObjectives=function(id) return {{text=(id==101 and '1/1' or '0/1'),finished=id==101,numFulfilled=id==101 and 1 or 0,numRequired=1}} end,
 GetNumQuestWatches=function() return #watched end,
 GetQuestIDForQuestWatchIndex=function(i) return watched[i] end,
 AddQuestWatch=function(id) for _,v in ipairs(watched) do if v==id then return end end watched[#watched+1]=id; snapshots[#snapshots+1]='add:'..id end,
 RemoveQuestWatch=function(id) for i,v in ipairs(watched) do if v==id then table.remove(watched,i);break end end snapshots[#snapshots+1]='remove:'..id end,
 IsComplete=function(id) return id==101 end,
}
local ns={TrackerZones={RefreshAfterWatchSwap=function() refreshCount=refreshCount+1 end}}
assert(loadfile(statusPath))('addon',ns)
assert(loadfile(filterPath))('addon',ns)
ns.TurnInFilter.Initialize()
assert(eventCallback)
eventCallback(nil,'PLAYER_ENTERING_WORLD')
local function watchesSet() table.sort(watched);return table.concat(watched,',') end
assert(watchesSet()=='100,102')
local before=refreshCount
ns.TurnInFilter.Toggle()
assert(watchesSet()=='101','el filtro ha incluido una misión sin completar: '..watchesSet())
assert(ns.TurnInFilter.IsActive(),'el filtro no ha activado su estado')
assert(refreshCount==before+1,'se espera un reflow al finalizar, no uno por watch')
eventCallback(nil,'QUEST_LOG_UPDATE')
assert(refreshCount==before+1,'un QUEST_LOG_UPDATE sin cambios no debe reiniciar el scroll')
ns.TurnInFilter.Toggle()
assert(watchesSet()=='100,102','el seguimiento original no se ha restaurado: '..watchesSet())
assert(not ns.TurnInFilter.IsActive(),'el filtro sigue activo')
assert(refreshCount==before+2,'debe reordenar la vista después de restaurar')
assert(TisteltiQuestHelperCharDB and TisteltiQuestHelperCharDB.turnInWatchSwap==nil,'no ha limpiado snapshot')
print('OK intercambio de watches y restauracion sin misiones falsamente entregables')
