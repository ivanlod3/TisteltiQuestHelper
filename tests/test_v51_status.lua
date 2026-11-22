local path=assert(arg[1])
local objectives={[100]={{text='Baúl: 0/1',finished=false,numFulfilled=0,numRequired=1}},
 [101]={{text='Acabado: 1/1',finished=true,numFulfilled=1,numRequired=1}},
 [102]={{text='Registro: 0/1',finished=false,numFulfilled=0,numRequired=1}},
 [103]={{text='Completado: 1/1',finished=true,numFulfilled=1,numRequired=1}}}
local info={
 [100]={questID=100,title='Conseguir la mercancía',isComplete=true,readyForTurnIn=true,isHeader=false},
 [101]={questID=101,title='De puerto a puerto',isComplete=true,readyForTurnIn=true,isHeader=false},
 [102]={questID=102,title='Vendas para heridas',isComplete=false,readyForTurnIn=false,isHeader=false},
 [103]={questID=103,title='La hoja afilada',isComplete=nil,readyForTurnIn=nil,isHeader=false},
}
local watchIDs={100,101,102,103}
C_QuestLog={
 GetQuestObjectives=function(id) return objectives[id] end,
 GetLogIndexForQuestID=function(id) return id end,
 GetInfo=function(id) return info[({100,101,102,103})[id] or id] end,
 GetNumQuestLogEntries=function() return 4 end,
 GetNumQuestWatches=function() return #watchIDs end,
 GetQuestIDForQuestWatchIndex=function(i) return watchIDs[i] end,
 IsComplete=function(id) return id~=102 end,
 ReadyForTurnIn=function(id) return id==101 or id==100 end,
 GetTitleForQuestID=function(id) return info[id] and info[id].title end,
}
local ns={}
assert(loadfile(path))('addon',ns)
local status=ns.QuestStatus
assert(status.IsReady(100,info[100])==false,'API contradictorias deben vetarse si objetivos 0/1')
assert(status.IsReady(101,info[101])==true,'completada valida no detectada')
assert(status.IsReady(102,info[102])==false,'mision incompleta detectada como lista')
assert(status.IsReady(103,info[103])==true,'IsComplete sin flag GetInfo no se detecta')
assert(status.IsReady(100,info[100],{{text='Baúl: 0/1',done=false}})==false,'misión auxiliar 0/1 no debe aparecer lista')
assert(status.IsReady(100,info[100],{{text='Baúl: 0/1',done=true}})==false,'contador visible 0/1 contradice completado')
objectives[101]={{text='Acabado: 0/1',numFulfilled=0,numRequired=1}}
assert(status.IsReady(101,info[101])==false,'contador numFulfilled incompleto no veta estado completo')
objectives[101]={{text='Acabado: 1/1',finished=true,numFulfilled=1,numRequired=1}}
-- Filtro debe utilizar el mismo estado que el rastreador.
local events={RegisterEvent=function() end,SetScript=function() end}
CreateFrame=function() return events end
assert(loadfile(assert(arg[2])))('addon',ns)
local ready=assert(ns.TurnInFilter.Scan())
assert(#ready==2 and ready[1]==101 and ready[2]==103,'el filtro contiene falsos positivos: '..table.concat(ready,','))
print('OK estado compartido filtro/rastreador; objetivos pendientes vetan isComplete erróneo')
