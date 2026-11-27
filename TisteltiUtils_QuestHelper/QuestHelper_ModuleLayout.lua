-- Experimental visual compaction only. Never change native capacity,
-- module heights, state, parentage, watches or the native layout scheduler.
local _,ns=...
local Layout={}
ns.ModuleLayout=Layout
local owned
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
local function canMove(frame)
    return frame and safe(frame.IsProtected,frame)==false
        and type(frame.SetPoint)=="function"
end
local function topAnchor(frame)
    if safe(frame.GetNumPoints,frame)~=2 then return end
    local top,left
    for i=1,2 do
        local ok,p,r,rp,x,y=pcall(frame.GetPoint,frame,i)
        if not ok or not readable(p) or not readable(r) or not readable(rp)
            or not readable(x) or not readable(y) then return end
        if p=="TOP" and rp=="BOTTOM" and type(x)=="number" and type(y)=="number" then
            top={r=r,x=x,y=y}
        elseif p=="LEFT" then left=r
        else return end
    end
    return top,left
end
local function same(a,b)
    return a and b and a.r==b.r and math.abs(a.x-b.x)<0.01 and math.abs(a.y-b.y)<0.01
end
local function setTop(frame,a)
    -- SetPoint replaces only the existing TOP anchor, preserving LEFT.
    if pcall(frame.SetPoint,frame,"TOP",a.r,"BOTTOM",a.x,a.y) then
        if ns.Perf then ns.Perf.Count("layout.anchor.module") end
        return true
    end
end
function Layout.Restore()
    if not owned or unsafe() then return end
    local old=owned
    if not canMove(old.frame) then return end
    local current=topAnchor(old.frame)
    if same(current,old.applied) then
        if not setTop(old.frame,old.native) then return end
    end
    owned=nil
end
function Layout.Apply(tracker,visibleHeight)
    if unsafe() then return end
    local profession=_G.ProfessionsRecipeTracker
    local parent=tracker and tracker.parentContainer
    if not parent or not canMove(profession) or profession.parentContainer~=parent
        or safe(tracker.IsShown,tracker)~=true or safe(profession.IsShown,profession)~=true
        or safe(tracker.IsCollapsed,tracker)~=false or safe(parent.IsCollapsed,parent)~=false
        or type(visibleHeight)~="number" or visibleHeight<0
        or not tracker.ContentsFrame then Layout.Restore();return end
    local current,left=topAnchor(profession)
    if not current or current.r~=tracker or left~=parent then Layout.Restore();return end
    local native=current
    if owned and owned.frame==profession and same(current,owned.applied) then native=owned.native end
    local spacing=parent.moduleSpacing
    -- Only the exact native direct-successor anchor is supported.
    if not readable(spacing) or type(spacing)~="number" or math.abs(native.y+spacing)>0.01
        or math.abs(native.x)>0.01 then Layout.Restore();return end
    local top=safe(tracker.GetTop,tracker)
    local contentTop=safe(tracker.ContentsFrame.GetTop,tracker.ContentsFrame)
    local height=safe(tracker.GetHeight,tracker)
    if type(top)~="number" or type(contentTop)~="number" or type(height)~="number"
        or top<contentTop then Layout.Restore();return end
    local gap=height-(top-contentTop)-visibleHeight
    if gap<1 then Layout.Restore();return end
    local wanted={r=tracker,x=native.x,y=native.y+gap}
    if same(current,wanted) then return end
    if setTop(profession,wanted) then owned={frame=profession,native=native,applied=wanted} end
end
