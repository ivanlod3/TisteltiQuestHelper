-- Exclusivity through the original Blizzard collapse API only.
-- No layout, geometry, alpha, watch or timer mutations.
local _,ns=...
local Accordion={}
ns.TrackerAccordion=Accordion
local hooked=setmetatable({}, {__mode="k"})
local busy,initializing=false,true
local preferred
local function readable(v)
    return not issecretvalue or not issecretvalue(v)
end
local function safe(fn,...)
    if type(fn)~="function" then return end
    local ok,v=pcall(fn,...)
    if ok and readable(v) then return v end
end
local function unsafe()
    if safe(InCombatLockdown)~=false then return true end
    local check=C_Secrets and C_Secrets.ShouldAurasBeSecret
    return check~=nil and safe(check)~=false
end
local function pair()
    local q,p=_G.QuestObjectiveTracker,_G.ProfessionsRecipeTracker
    if not q or not p or not q.parentContainer or q.parentContainer~=p.parentContainer then return end
    return q,p
end
local function collapsed(m)
    local v=safe(m.IsCollapsed,m)
    if type(v)=="boolean" then return v end
end
local function canChange(m)
    return type(m.SetCollapsed)=="function" and safe(m.IsProtected,m)==false
end
local function reconcile(requested)
    if busy or unsafe() then return end
    local q,p=pair()
    if not q or not hooked[q] or not hooked[p] then return end
    if collapsed(q)~=false or collapsed(p)~=false then return end
    -- Until initial world entry, never let an automatic profession opening
    -- displace an already expanded quest module.
    local keep=initializing and q or requested or preferred or q
    if keep~=q and keep~=p then keep=q end
    local other=keep==q and p or q
    if not canChange(other) then return end
    busy=true
    local ok=pcall(other.SetCollapsed,other,true)
    busy=false
    if ok and collapsed(other)==true then
        preferred=keep
        if ns.Perf then ns.Perf.Count("accordion.native.collapse") end
    end
end
local function onCollapsed(self,value)
    if busy or unsafe() or not readable(value) or type(value)~="boolean" then return end
    local q,p=pair()
    if self~=q and self~=p then return end
    if value==false and collapsed(self)==false then
        -- The original setter has finished, but the native dirty layout is
        -- queued for the next frame. Collapse the peer in this same stack.
        if not initializing then preferred=self end
        reconcile(self)
    end
end
function Accordion.Initialize(worldReady)
    if unsafe() or type(hooksecurefunc)~="function" then return end
    local q,p=pair()
    if not q then return end
    for _,m in ipairs({q,p}) do
        if not hooked[m] and type(m.SetCollapsed)=="function" then
            hooked[m]=pcall(hooksecurefunc,m,"SetCollapsed",onCollapsed)
        end
    end
    reconcile()
    if worldReady then initializing=false end
end
