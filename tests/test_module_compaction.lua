local root=assert(arg[1])
local combat,secret=false,false
InCombatLockdown=function()return combat end
C_Secrets={ShouldAurasBeSecret=function()return secret end}
local parent={moduleSpacing=10,IsCollapsed=function()return false end}
local tracker={parentContainer=parent,GetTop=function()return 900 end,
 GetHeight=function()return 700 end,ContentsFrame={GetTop=function()return 874 end},
 IsShown=function()return true end,IsCollapsed=function()return false end}
local p={parentContainer=parent,protected=false,shown=true,writes=0,y=-10}
function p:IsProtected()return self.protected end
function p:IsShown()return self.shown end
function p:GetNumPoints()return 2 end
function p:GetPoint(i)if i==1 then return "TOP",tracker,"BOTTOM",0,self.y else return "LEFT",parent,"LEFT",0,0 end end
function p:SetPoint(point,r,rp,x,y)assert(point=="TOP" and r==tracker and rp=="BOTTOM" and x==0);self.y=y;self.writes=self.writes+1 end
_G.ProfessionsRecipeTracker=p
local ns={}
assert(loadfile(root.."/QuestHelper_ModuleLayout.lua"))("addon",ns)
local L=ns.ModuleLayout
L.Apply(tracker,300);assert(p.y==364 and p.writes==1)
L.Apply(tracker,300);assert(p.writes==1,"feedback")
L.Apply(tracker,400);assert(p.y==264 and p.writes==2)
L.Apply(tracker,nil);assert(p.y==-10 and p.writes==3,"restore")
L.Apply(tracker,200);combat=true;L.Apply(tracker,nil);assert(p.y==464);combat=false
L.Apply(tracker,nil);assert(p.y==-10)
L.Apply(tracker,200);p.y=-10;L.Apply(tracker,200);assert(p.y==464,"native reanchor")
L.Apply(tracker,nil);p.protected=true;local n=p.writes;L.Apply(tracker,200);assert(p.writes==n)
p.protected=false;secret=true;L.Apply(tracker,200);assert(p.writes==n);secret=false
p.y=-15;L.Apply(tracker,200);assert(p.y==-15,"foreign anchor")
p.y=-10;L.Apply(tracker,674);assert(p.y==-10,"no gap")
print("OK visual module compaction, restoration, no redundant writes, native reanchor, combat/protection")
