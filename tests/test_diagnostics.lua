local root=assert(arg[1])
local allFrames, clock, mutations, hookCount = {}, 0, 0, 0
local function frame(name)
    local f={name=name, points={{"TOP",nil,"TOP",0,-10},{"LEFT",nil,"LEFT",20,0},{"RIGHT",nil,"RIGHT",0,0}}}
    function f:GetName()return self.name end
    function f:GetLeft()return self.left or 20 end
    function f:GetTop()return 500 end
    function f:GetWidth()return 220 end
    function f:GetHeight()return 50 end
    function f:GetEffectiveScale()return 1 end
    function f:IsShown()return true end
    function f:IsVisible()return true end
    function f:GetNumPoints()return #self.points end
    function f:GetPoint(i)return unpack(self.points[i])end
    function f:RegisterEvent()end
    function f:SetScript(key,fn)self[key]=fn end
    function f:SetText(t)self.text=t end
    function f:CreateFontString()return frame()end
    for _,key in ipairs({"SetSize","SetPoint","SetFrameStrata","SetBackdrop","SetBackdropColor","EnableMouse","SetMultiLine","SetFontObject","SetWidth","SetAutoFocus","SetMaxLetters","SetScrollChild","Show","Hide","SetFocus","HighlightText"}) do f[key]=function()end end
    allFrames[#allFrames+1]=f
    return f
end
CreateFrame=function()return frame()end
InCombatLockdown=function()return false end
GetTime=function()clock=clock+.1;return clock end
GetBuildInfo=function()return "1.60.1","71037" end
SlashCmdList={}
local b=frame("Native");b.id=100;b.used=true;b.HeaderText=frame("Title")
local auxiliary=frame("Auxiliary")
local tracker=frame("Tracker");tracker.ContentsFrame=frame("Contents");tracker.availableHeight=180
function tracker:GetExistingBlock(id)if id==100 then return b end end
function tracker:AnchorBlock()end
function tracker:LayoutBlock()end
function tracker:FreeBlock()end
function tracker:EndLayout()end
QuestObjectiveTracker=tracker
hooksecurefunc=function(obj,key,fn)
    hookCount=hookCount+1
    local original=obj[key];obj[key]=function(...)original(...);fn(...)end
end
C_QuestLog={GetNumQuestWatches=function()return 2 end,GetQuestIDForQuestWatchIndex=function(i)return i==1 and 100 or 101 end,GetTitleForQuestID=function(id)return "Quest "..id end,
AddQuestWatch=function()mutations=mutations+1 end,RemoveQuestWatch=function()mutations=mutations+1 end}
local ns={QuestStatus={IsReady=function()return false end},TrackerZones={GetDiagnosticState=function()return {index=1,last=2,rows=2,auxiliary={{id=101,frame=auxiliary}},geometry={{id=100,y=20,width=220,height=50}}}end}}
assert(loadfile(root.."/QuestHelper_Diagnostics.lua"))("addon",ns)
local cmd=SlashCmdList.TQHDIAG
ns.Diagnostics.Capture("disabled")
assert(hookCount==0,"hooks instalados antes de start")
cmd("start");assert(hookCount==4)
tracker:AnchorBlock(b);tracker:LayoutBlock(b);ns.Diagnostics.Capture("before-addon")
b.points={{"TOPLEFT",tracker.ContentsFrame,"TOPLEFT",0,-20},{"BOTTOMRIGHT",tracker.ContentsFrame,"TOPLEFT",220,-70}}
b.left=0;ns.Diagnostics.Capture("after-addon");tracker:FreeBlock(b);tracker:AnchorBlock(b)
cmd("mark filtro_on");cmd("stop");cmd("export")
local encoded
for _,f in ipairs(allFrames)do if f.text and f.text:find("TQHDIAG PART",1,true)then encoded=f.text end end
assert(encoded,"export ausente")
local dictionary, decoded={},{}
for line in encoded:gmatch("[^\n]+")do
    local id,value=line:match("^%+(%d+)\t(.*)$")
    if id then dictionary[id]=value;decoded[#decoded+1]=value else
        id=line:match("^@(%d+)$");if id then assert(dictionary[id]);decoded[#decoded+1]=dictionary[id]end
    end
end
local output=table.concat(decoded,"\n")
assert(output:find("before-addon",1,true) and output:find("after-addon",1,true))
assert(output:find("nativeAnchors=TOP",1,true) and output:find("anchors=TOPLEFT",1,true))
assert(output:find("watches=2\tnative=1\tauxShown=1",1,true),"auxiliar contada como nativa")
assert(output:find("generation=2",1,true),"no detecta reutilización")
assert(output:find("snapshots=5",1,true))
assert(output:find("error=-",1,true))
cmd("resumen")
local summary
for _,f in ipairs(allFrames)do if f.text and f.text:find("TQHDIAG PART",1,true)then summary=f.text end end
assert(summary:find("RESUMEN:",1,true))
assert(summary:find("NATIVE_VISIBLE\t100",1,true))
assert(summary:find("AUX_VISIBLE\t101",1,true))
assert(summary:find("GEOMETRIA id=100 dx=-20.000 dw=0.000 dh=0.000",1,true))
assert(summary:find("GEOMETRY_CHECKED\t100",1,true))
assert(summary:find("error=-",1,true))
assert(not output:find("TOP,20,-10,0",1,true),'campo espurio del segundo valor de gsub')
cmd("export");assert(mutations==0,"el observador cambió seguimiento")
cmd("start");assert(hookCount==4,"hooks duplicados tras reiniciar")
InCombatLockdown=function()return true end
cmd("mark combat");cmd("stop");cmd("full")
local raw
for _,f in ipairs(allFrames)do if f.text and f.text:find("TQHDIAG PART",1,true)then raw=f.text end end
assert(raw:find("SKIP\tcombat/secret",1,true))
assert(mutations==0)
print("OK observador: desactivado por defecto, fases nativa/addon, conteos separados, reciclado, exportación reversible, hooks únicos y combate")
