-- Read-only native viewport. The historical module name is retained for
-- diagnostics compatibility. No hooks, events, timers or native geometry writes.
local _,ns=...
local View={}
ns.NativeCapacity=View
local function safe(fn,...)
    if type(fn)~="function" then return end
    local ok,v=pcall(fn,...)
    if ok and (not issecretvalue or not issecretvalue(v)) then return v end
end
local function number(v)
    return (not issecretvalue or not issecretvalue(v)) and type(v)=="number"
end
function View.GetViewHeight(tracker)
    if not tracker or not tracker.ContentsFrame then return end
    local top=safe(tracker.GetTop,tracker)
    local contentTop=safe(tracker.ContentsFrame.GetTop,tracker.ContentsFrame)
    local inset=number(top) and number(contentTop) and top-contentTop or nil
    if not number(inset) or inset<0 then return end
    local available=tracker.availableHeight
    local height=safe(tracker.GetHeight,tracker)
    if not number(height) or height<=inset or height>6000 then return end
    if not number(available) or available<=inset or available>6000 then available=height end
    -- The visible frame must never exceed its actual native allocation.
    available=math.min(available,height)
    return math.max(0,available-inset),inset
end
function View.GetState()
    local tracker=_G.QuestObjectiveTracker
    local parent=tracker and tracker.parentContainer
    local height=parent and safe(parent.GetHeight,parent)
    local bottom
    if parent and type(parent.GetClampRectInsets)=="function" then
        local ok,_,_,_,value=pcall(parent.GetClampRectInsets,parent)
        if ok and number(value) then bottom=value end
    end
    return {enabled=false,reason="native-read-only",base=height,expanded=height,
        view=View.GetViewHeight(tracker),trackerHeight=tracker and safe(tracker.GetHeight,tracker),
        clampBottom=bottom,baselineBottom=bottom,tripped=false}
end
