local root=assert(arg[1])
local clock,queue=10,{}
GetTime=function()return clock end
InCombatLockdown=function()return false end
C_Timer={After=function(_,f)queue[#queue+1]=f end}
local function drain()
    local n=0
    while #queue>0 do local q=queue;queue={};for _,f in ipairs(q)do f()end;n=n+1;assert(n<30,"loop")end
end
local function frame(h)
    local f={h=h,clamp={-3,4,5,-6},hooks={},writes=0}
    function f:GetHeight()return self.h end
    function f:SetHeight(v)self.h=v;self.writes=self.writes+1;if self.hooks.OnSizeChanged then self.hooks.OnSizeChanged(self,240,v)end end
    function f:GetClampRectInsets()return unpack(self.clamp)end
    function f:SetClampRectInsets(...)self.clamp={...};self.writes=self.writes+1 end
    function f:IsProtected()return false end
    function f:HookScript(key,cb)self.hooks[key]=cb end
    function f:RegisterEvent()end
    function f:SetScript()end
    function f:Update()end
    function f:GetTop()return 900 end
    return f
end
CreateFrame=function()return frame(1)end
hooksecurefunc=function(o,k,f)local old=o[k];o[k]=function(...)old(...);f(...)end end
local parent,tracker=frame(800),frame(1000)
parent.modules={tracker}
tracker.parentContainer=parent
tracker.ContentsFrame={GetTop=function()return 875 end}
local count,trip=0,0
local missing=false
local ns={Config={Get=function()return true end},
 TrackerZones={NeedsCapacity=function()return true end,HasMissingNativeBlocks=function()return missing end,OnCapacityTripped=function()trip=trip+1 end,GetDiagnosticState=function()return {native=25,watches=25}end},
 Perf={Count=function(k)if k=="layout.height.write" or k=="layout.clamp.write" then count=count+1 end end}}
assert(loadfile(root.."/QuestHelper_NativeCapacity.lua"))("addon",ns)
local cap=ns.NativeCapacity
cap.Initialize(tracker,function()end);drain()
assert(not cap.GetState().enabled and parent.h==800 and count==0 and cap.GetState().reason=="native-complete","complete native rows must not expand")
missing=true
cap.Initialize(tracker,function()end);drain()
assert(cap.GetState().enabled and parent.h==32768)
local b=parent.clamp[4]
parent:SetClampRectInsets(-3,4,5,b)
assert(parent.clamp[4]==b,"compensated clamp fed back into itself")
local stable=count
-- Reproduce the asynchronous float rounding and the delayed own-size event
-- observed in Forever, without another write to the clamp.
parent.clamp[4]=b-0.004
parent.hooks.OnSizeChanged(parent,240,32768)
for i=1,20 do cap.Initialize(tracker,function()end) end
assert(count==stable,"unchanged or rounded geometry causes writes")
-- The first native return to the original height must stop expansion.
parent:SetHeight(800);drain()
assert(cap.IsTripped() and not cap.GetState().enabled and trip==1)
assert(cap.GetState().reason=="geometry-feedback")
assert(parent.h==800 and parent.clamp[4]==-6,"native geometry not restored")
local after=count
for i=1,100 do parent:Update();tracker:Update();cap.Initialize(tracker,function()end);cap.FitVisible(tracker,500);drain() end
assert(count==after and #queue==0,"writes continued after circuit breaker")
