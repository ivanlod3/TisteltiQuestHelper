local root=assert(arg[1])
-- A read-only viewport must never write geometry or install an event/hook/timer.
local function forbidden()error("native geometry mutation or extra subscription")end
CreateFrame=forbidden;hooksecurefunc=forbidden;C_Timer={After=forbidden}
local parent={GetHeight=function()return 791 end,GetClampRectInsets=function()return 0,0,0,0 end,
    SetHeight=forbidden,SetClampRectInsets=forbidden,Update=forbidden,MarkDirty=forbidden}
local tracker={parentContainer=parent,availableHeight=753,GetHeight=function()return 701 end,
    GetTop=function()return 876 end,ContentsFrame={GetTop=function()return 850 end},
    SetHeight=forbidden,Update=forbidden,MarkDirty=forbidden}
parent.modules={tracker}
_G.QuestObjectiveTracker=tracker
local ns={}
assert(loadfile(root.."/QuestHelper_NativeCapacity.lua"))("addon",ns)
local view=ns.NativeCapacity
assert(view.GetViewHeight(tracker)==675,"visible area is the actual native height")
assert(view.GetState().reason=="native-read-only" and view.GetState().base==791)
parent.modules={tracker,{IsDisplayable=function()return true end}}
assert(view.GetViewHeight(tracker)==675,"must respect allocated quest module height")
tracker.availableHeight=nil
assert(view.GetViewHeight(tracker)==675)
tracker.GetTop=function()return nil end
assert(view.GetViewHeight(tracker)==nil)
print("OK read-only native viewport, no hooks/timers/events or geometry writes")
