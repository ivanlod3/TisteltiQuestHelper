local root=assert(arg[1])
local function scenario(opts)
 opts=opts or {}
 local log={100,101,102};local watched={100,102};local ready=opts.ready or {};local writes={};local queue={};local callback
 local combat, failAdd, scans=false,false,0
 local function setText()end
 CreateFrame=function()
  return {RegisterEvent=function()end,SetScript=function(_,name,fn)if name=='OnEvent' then callback=fn end end}
 end
 QuestObjectiveTracker=nil;TisteltiQuestHelperCharDB={};C_Secrets=nil;issecretvalue=nil
 InCombatLockdown=function()return combat end
 C_Timer={After=function(_,fn)queue[#queue+1]=fn end}
 C_QuestLog={
  GetNumQuestLogEntries=function()scans=scans+1;if opts.race and scans==3 then ready={} end;return #log end,
  GetInfo=function(i)return {questID=log[i],isHeader=false}end,
  GetLogIndexForQuestID=function(id)for i,v in ipairs(log)do if v==id then return i end end end,
  GetNumQuestWatches=function()return #watched end,
  GetQuestIDForQuestWatchIndex=function(i)return watched[i]end,
  AddQuestWatch=function(id)writes[#writes+1]='add:'..id;if not failAdd then watched[#watched+1]=id end end,
  RemoveQuestWatch=function(id)writes[#writes+1]='remove:'..id;for i,v in ipairs(watched)do if v==id then table.remove(watched,i);break end end end,
 }
 local ns={QuestStatus={IsReady=function(id)return ready[id]==true end},TrackerZones={RefreshAfterWatchSwap=function()end}}
 assert(loadfile(root..'/QuestHelper_TurnInFilter.lua'))('addon',ns)
 ns.TurnInFilter.Initialize();callback(nil,'PLAYER_ENTERING_WORLD')
 local function drain()local rounds=0;while #queue>0 do rounds=rounds+1;assert(rounds<30,'retry loop');table.remove(queue,1)()end end
 local function ids()table.sort(watched);return table.concat(watched,',')end
 if opts.empty or opts.race then
  ns.TurnInFilter.Toggle();drain()
  assert(#writes==0,'empty activation must not change watches')
  assert(ids()=='100,102' and not ns.TurnInFilter.IsActive())
  assert(TisteltiQuestHelperCharDB.turnInWatchSwap==nil,'empty filter left saved state')
  return
 end
 ns.TurnInFilter.Toggle();drain();assert(ids()=='101' and ns.TurnInFilter.IsActive())
 ready={}
 if opts.delivered then log={100,102} end
 if opts.combat then combat=true end
 if opts.failure then failAdd=true end
 callback(nil,'QUEST_TURNED_IN');drain()
 if opts.combat then
  assert(ids()=='101' and ns.TurnInFilter.IsActive(),'writes during combat')
  combat=false;callback(nil,'PLAYER_REGEN_ENABLED');drain()
 end
 if opts.failure then
  assert(TisteltiQuestHelperCharDB.turnInWatchSwap.mode=='restoring','lost recovery after failure')
  assert(table.concat(TisteltiQuestHelperCharDB.turnInWatchSwap.original,',')=='100,102')
  failAdd=false
  if opts.reload then
   assert(loadfile(root..'/QuestHelper_TurnInFilter.lua'))('addon',ns)
   ns.TurnInFilter.Initialize();callback(nil,'PLAYER_ENTERING_WORLD')
  else callback(nil,'QUEST_LOG_UPDATE') end
  drain()
 end
 assert(ids()=='100,102','original watches not restored: '..ids())
 assert(not ns.TurnInFilter.IsActive() and TisteltiQuestHelperCharDB.turnInWatchSwap==nil)
 local n=#writes;callback(nil,'QUEST_LOG_UPDATE');drain();assert(#writes==n,'repeated unnecessary swap')
end
scenario({empty=true})
scenario({ready={[101]=true},race=true})
scenario({ready={[101]=true}})
scenario({ready={[101]=true},delivered=true})
scenario({ready={[101]=true},delivered=true,combat=true})
scenario({ready={[101]=true},delivered=true,failure=true})
scenario({ready={[101]=true},delivered=true,failure=true,reload=true})
print('OK filtro vacío: sin escrituras; carrera entre lecturas; última entrega; combate; fallo y recarga')
