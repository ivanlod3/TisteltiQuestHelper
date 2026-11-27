local root=assert(arg[1])
local callbacks,combat,instance,secret={},false,false,false
local secretValue={}
issecretvalue=function(v)return v==secretValue end
InCombatLockdown=function()return combat end
IsInInstance=function()return instance,instance and "party" or "none" end
C_Secrets={ShouldAurasBeSecret=function()return secret end}
Menu={ModifyMenu=function(tag,fn)callbacks[tag]=fn end}
SlashCmdList={}
local frame={}
function frame:RegisterEvent()end
function frame:UnregisterEvent()end
function frame:SetScript()end
CreateFrame=function()return frame end
local ns={}
assert(loadfile(root.."/QuestHelper_ManualTargets.lua"))("addon",ns)
ns.ManualTargets.Register()
local calls=0
local menu={}
function menu:CreateDivider()calls=calls+1 end
function menu:CreateButton()calls=calls+1;return self end
for _,tag in ipairs({"MENU_UNIT_TARGET","MENU_UNIT_ENEMY","MENU_UNIT_FOCUS"}) do
    local cb=assert(callbacks[tag])
    instance=true;calls=0;cb(nil,menu,nil);assert(calls==0,"instance menu touched")
    instance=false;combat=true;cb(nil,menu,nil);assert(calls==0,"combat menu touched")
    combat=false;secret=true;cb(nil,menu,nil);assert(calls==0,"secret menu touched")
    secret=secretValue;cb(nil,menu,nil);assert(calls==0,"secret boolean menu touched")
    secret=false;instance=nil;cb(nil,menu,nil);assert(calls==0,"unknown instance menu touched")
    instance=false;cb(nil,menu,nil);assert(calls==5,"world menu missing")
end
assert(type(SlashCmdList.TQHMANUAL)=="function")
print("OK manual menu restrictions and slash commands")
