local root=assert(arg[1])
local combat,secret=false,false
InCombatLockdown=function()return combat end
C_Secrets={ShouldAurasBeSecret=function()return secret end}
local installs=0
hooksecurefunc=function(o,k,f)
 local native=o[k];installs=installs+1
 o[k]=function(self,v)native(self,v);f(self,v)end
end
local parent={dirty=false,requests=0,layouts=0}
function parent:MarkDirty()
 self.requests=self.requests+1;self.dirty=true
end
local function module()
 local m={parentContainer=parent,closed=false,writes=0,protected=false}
 function m:IsCollapsed()return self.closed end
 function m:IsProtected()return self.protected end
 function m:SetCollapsed(v)
  self.closed=v;self.writes=self.writes+1
  self.parentContainer:MarkDirty()
 end
 function m:ToggleCollapsed()self:SetCollapsed(not self:IsCollapsed())end
 return m
end
local q,p=module(),module()
_G.QuestObjectiveTracker=q;_G.ProfessionsRecipeTracker=p
local function check()
 assert(q.closed or p.closed,"both modules open at the native layout boundary")
end
local function nativeFrame()
 check()
 if parent.dirty then parent.dirty=false;parent.layouts=parent.layouts+1 end
end
local ns={}
assert(loadfile(root.."/QuestHelper_TrackerAccordion.lua"))("addon",ns)
local A=ns.TrackerAccordion
A.Initialize(false);check();assert(not q.closed and p.closed)
assert(q.writes==0 and p.writes==1)
p:SetCollapsed(false);check();assert(not q.closed and p.closed,"automatic startup profession opening displaced quests")
A.Initialize(true);check()
assert(installs==2)
nativeFrame()
for i=1,100 do
 local m=i%2==1 and p or q
 local peer=m==p and q or p
 local w=peer.writes;local n=parent.layouts
 m:ToggleCollapsed();check()
 assert(not m.closed and peer.closed and peer.writes==w+1,"switch failed")
 assert(parent.layouts==n,"addon forced an immediate layout")
 nativeFrame()
end
q:SetCollapsed(true);check();assert(q.closed and p.closed,"manual close should not open peer")
p:ToggleCollapsed();check();assert(not p.closed and q.closed)
local w=q.writes+p.writes
A.Initialize(true);assert(q.writes+p.writes==w and installs==2,"redundant writes/hooks")
-- No addon writes in combat or secret context; recover exactly once at safe boundary.
combat=true;q:SetCollapsed(false);assert(not p.closed and not q.closed)
w=p.writes;assert(q.closed==false);A.Initialize(true);assert(p.writes==w)
combat=false;A.Initialize(true);check();assert(q.closed and not p.closed)
secret=true;q:SetCollapsed(false);assert(not p.closed);secret=false;A.Initialize(true);check()
-- Unsupported separate parents must remain completely native.
local other={MarkDirty=function()end};p.parentContainer=other
w=p.writes;q:SetCollapsed(false);assert(p.writes==w)
print("OK native accordion startup, switches, no duplicate hooks, no forced layouts, safety recovery")
