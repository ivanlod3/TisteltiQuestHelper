local root=assert(arg[1])
local clock, calls, combat=10,0,false
GetTime=function()return clock end
InCombatLockdown=function()return combat end
local frame={}
function frame:RegisterEvent()end
function frame:SetScript(_,fn)self.event=fn end
CreateFrame=function()return frame end
local progress=0
C_QuestLog={GetNumQuestLogEntries=function()return 1 end,GetInfo=function()return {questID=1}end,
GetQuestObjectives=function()calls=calls+1;return {{numFulfilled=progress,numRequired=5}}end}
local ns={}
assert(loadfile(root.."/QuestHelper_State.lua"))("addon",ns)
local Q=ns.QuestState.API
assert(Q.GetQuestObjectives(1)[1].numFulfilled==0)
assert(Q.GetQuestObjectives(1)[1].numFulfilled==0 and calls==1)
frame.event(frame,"UNIT_QUEST_LOG_CHANGED","party1")
assert(Q.GetQuestObjectives(1)[1].numFulfilled==0 and calls==1)
progress=1;frame.event(frame,"QUEST_LOG_UPDATE")
assert(Q.GetQuestObjectives(1)[1].numFulfilled==1 and calls==2)
clock=11;progress=2
assert(Q.GetQuestObjectives(1)[1].numFulfilled==2 and calls==3)
combat=true;progress=3
assert(Q.GetQuestObjectives(1)[1].numFulfilled==3 and calls==4)
combat=false;frame.event(frame,"PLAYER_REGEN_ENABLED")
assert(Q.GetQuestObjectives(1)[1].numFulfilled==3 and calls==5)
assert(ns.Perf.Snapshot()["journal.hit.GetQuestObjectives"]==2)
