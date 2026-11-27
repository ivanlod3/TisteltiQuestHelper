-- Regressions: mass quest journal updates, real progress and recycled native blocks.
local root=assert(arg[1])
local clock=10
GetTime=function() return clock end
wipe=function(t) for k in pairs(t) do t[k]=nil end end
local timers={}
C_Timer={After=function(_,fn) timers[#timers+1]=fn end,NewTimer=function(_,fn)
  return {Cancel=function()end}
end}
local function flush()
  for n=1,30 do
    if #timers==0 then break end
    local queue=timers;timers={}
    for _,fn in ipairs(queue) do fn() end
  end
end
local frame={}
function frame:RegisterEvent()end
function frame:SetScript(_,fn)self.event=fn end
CreateFrame=function()return setmetatable({}, {__index=frame})end
local ids={101,102}
local data={
 [101]={text="Lobos: 0/8",finished=false},
 [102]={text="Mineral: 0/4",finished=false},
}
local blocks={}
local function block(id)
 local b={id=id,used=true,HeaderText={}}
 function b:IsShown()return true end
 function b:CreateTexture()
  local t={visible=false}
  function t:SetPoint()end
  function t:SetWidth()end
  function t:SetColorTexture()end
  function t:Show()self.visible=true end
  function t:Hide()self.visible=false end
  return t
 end
 return b
end
blocks[101]=block(101);blocks[102]=block(102)
QuestObjectiveTracker={GetExistingBlock=function(_,id) return blocks[id] end,
 EndLayout=function()end}
hooksecurefunc=function(obj,key,callback)
 local native=obj[key]
 obj[key]=function(...) native(...); callback(...) end
end
C_QuestLog={
 GetNumQuestLogEntries=function()return #ids end,
 GetInfo=function(i)return {questID=ids[i],isHeader=false}end,
 GetQuestObjectives=function(id)return {data[id]}end,
 GetNumQuestWatches=function()return #ids end,
 GetQuestIDForQuestWatchIndex=function(i)return ids[i]end,
}
local reasons={}
local ns={Config={Get=function(key)return key=="trackerRecentEnabled"end,
 Settings=function()return {trackerRecentSeconds=60}end},
 QuestStatus={IsReady=function()return false end},
 Diagnostics={RecordRecent=function(...) reasons[#reasons+1]={...} end}}
assert(loadfile(root.."/QuestHelper_Recent.lua"))("addon",ns)
ns.RecentQuests.Initialize()
local events
-- The event handler is registered on the frame created by this module.
-- Retrieve it without relying on Blizzard's frame naming.
local function find(fn,name)
 for i=1,100 do
  local key,value=debug.getupvalue(fn,i)
  if not key then return end
  if key==name then return value end
 end
end
events=assert(find(ns.RecentQuests.Initialize,"events"))
events.event(nil,"PLAYER_LOGIN");flush()
local function scan()events.event(nil,"QUEST_LOG_UPDATE");flush()end
assert(ns.RecentQuests.GetStatus(101)==nil)
data[101]={text="Lobos muertos: 0/8",finished=false}
data[102]={text="Mineral recogido: 0/4",finished=false}
scan()
assert(ns.RecentQuests.GetStatus(101)==nil and ns.RecentQuests.GetStatus(102)==nil,
 "journal refresh created false blue highlights")
data[101]={text="Lobos muertos: 1/8",finished=false}
scan()
assert(ns.RecentQuests.GetStatus(101)=="AVANCE" and ns.RecentQuests.GetStatus(102)==nil,
 "numeric increase must only mark the corresponding quest")
assert(reasons[#reasons][3]:find("contador",1,true),"missing reason")
data[102]={text="Mineral recogido: 0/4",finished=true}
scan()
assert(ns.RecentQuests.GetStatus(102)=="AVANCE","completion transition not detected")
-- Recycled blocks must never inherit the previous quest highlight.
local former=blocks[101]
ns.RecentQuests.RepaintRendered()
assert(former and former.id==101)
former.id=999
ns.RecentQuests.RepaintRendered()
-- No colour application to an obsolete GetExistingBlock result.
local paint=assert(find(ns.RecentQuests.Decorate,"paint"))
paint(former,101)
local glows=assert(find(paint,"glowByBlock"))
assert(not glows[former].glow.visible,"recycled row retained its glow")
print("OK real progress, mass updates and recycled highlights")
