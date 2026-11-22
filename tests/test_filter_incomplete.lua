local root = assert(arg[1])
local cases = 0
local function run(name, setup, check)
    local log = {{isHeader=false,questID=100},{isHeader=false,questID=101},{isHeader=false,questID=102}}
    local ctx = {log=log, watches={100,102}, mutations={}, combat=false, partial=false}
    TisteltiQuestHelperCharDB = nil
    local handler
    CreateFrame = function() return {RegisterEvent=function()end, SetScript=function(_,_,fn) handler=fn end} end
    C_Timer = {After=function(_,fn) fn() end}
    C_Secrets = nil
    InCombatLockdown = function() if ctx.combatError then error("combat unreadable") end; return ctx.combat end
    C_QuestLog = {
        GetNumQuestLogEntries=function() return #ctx.log end,
        GetInfo=function(i) return ctx.log[i] end,
        GetLogIndexForQuestID=function(id) for i,v in ipairs(ctx.log) do if v.questID==id then return i end end; return ctx.extraIndex end,
        GetNumQuestWatches=function() return #ctx.watches end,
        GetQuestIDForQuestWatchIndex=function(i) return ctx.watches[i] end,
        AddQuestWatch=function(id) assert(not ctx.combat); ctx.mutations[#ctx.mutations+1]="add"..id; ctx.watches[#ctx.watches+1]=id end,
        RemoveQuestWatch=function(id)
            assert(not ctx.combat); ctx.mutations[#ctx.mutations+1]="remove"..id
            for i,v in ipairs(ctx.watches) do if id==v then table.remove(ctx.watches,i);break end end
            if ctx.combatAfterRemove then ctx.combat=true end
        end,
    }
    local ns={QuestStatus={IsReady=function(id) return id==101 end}}
    assert(loadfile(root .. "/QuestHelper_TurnInFilter.lua"))("addon",ns)
    ns.TurnInFilter.Initialize();handler(nil,"PLAYER_ENTERING_WORLD")
    ctx.event=function(e)handler(nil,e)end
    setup(ctx,ns.TurnInFilter)
    check(ctx,ns.TurnInFilter)
    cases=cases+1;print("OK "..name)
end
local function unchanged(c)
    assert(#c.mutations==0,"se modificó seguimiento con datos incompletos")
    assert(table.concat(c.watches,",")=="100,102")
end
run("isHeader ausente",function(c,f)c.log[2].isHeader=nil;f.Toggle()end,unchanged)
run("ID ausente",function(c,f)c.log[2].questID=nil;f.Toggle()end,unchanged)
run("ID duplicado",function(c,f)c.log[2].questID=100;f.Toggle()end,unchanged)
run("diario vacío al activar",function(c,f)c.log={};f.Toggle()end,unchanged)
run("lectura de combate fallida",function(c,f)c.combatError=true;f.Toggle()end,unchanged)
run("combate empieza entre llamadas",function(c,f)c.combatAfterRemove=true;f.Toggle()end,function(c,f)
    assert(#c.mutations==1);assert(TisteltiQuestHelperCharDB.turnInWatchSwap)
    c.combat=false;c.combatAfterRemove=false;c.event("PLAYER_REGEN_ENABLED")
    table.sort(c.watches);assert(table.concat(c.watches,",")=="100,102");assert(not TisteltiQuestHelperCharDB.turnInWatchSwap)
end)
run("restauración aplazada por diario parcial",function(c,f)
    f.Toggle();c.log[1].isHeader=nil;c.mutations={};f.Toggle()
end,function(c,f)
    assert(#c.mutations==0);assert(TisteltiQuestHelperCharDB.turnInWatchSwap.mode=="restoring")
    c.log[1].isHeader=false;c.event("QUEST_LOG_UPDATE")
    table.sort(c.watches);assert(table.concat(c.watches,",")=="100,102");assert(not TisteltiQuestHelperCharDB.turnInWatchSwap)
end)
run("diario vacío después de actualizar",function(c,f)
    f.Toggle();c.log={};c.event("QUEST_LOG_UPDATE");c.mutations={};f.Toggle()
end,function(c)assert(#c.mutations==0);assert(TisteltiQuestHelperCharDB.turnInWatchSwap)end)
run("índice existente con información incoherente",function(c,f)
    f.Toggle();c.log={{questID=101,isHeader=false}};c.extraIndex=1;c.mutations={};f.Toggle()
end,function(c)assert(#c.mutations==0);assert(TisteltiQuestHelperCharDB.turnInWatchSwap)end)
print("TOTAL "..cases.." casos de integridad del filtro")
