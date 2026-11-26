-- Shared short-lived read-through journal view. Never caches protected/secret data.
-- Invalidate on journal events; no timer, no polling, no writes to Blizzard.
local _, ns = ...
local Q = C_QuestLog
local cache, started = {}, nil
local Perf, State = {}, {}
ns.Perf, ns.QuestState = Perf, State
local counts, since = {}, GetTime()
local first, recent, serial = {}, {}, 0
local FIRST, LAST = 24, 64
function Perf.Count(key)
    counts[key] = (counts[key] or 0) + 1
end
local function safeText(value)
    if issecretvalue and issecretvalue(value) then return "secret" end
    if value == nil then return "-" end
    if type(value) == "number" then return ("%.3f"):format(value) end
    if type(value) == "boolean" or type(value) == "string" then return tostring(value) end
    return type(value)
end
function Perf.Trace(kind, a, b, c, d)
    serial=serial+1
    local line=("%.3f #%d %s %s | %s | %s | %s"):format(GetTime()-since,serial,kind,safeText(a),safeText(b),safeText(c),safeText(d))
    if #first<FIRST then first[#first+1]=line
    else recent[(serial-FIRST-1)%LAST+1]=line end
end
function Perf.BuildReport()
    local elapsed=math.max(0,GetTime()-since)
    local out={"TQHPERF/2","elapsed_seconds="..safeText(elapsed)}
    local function append(label,value) out[#out+1]=label.."="..safeText(value) end
    if GetBuildInfo then local v,b=GetBuildInfo();append("client",v);append("build",b) end
    if ns.Config and ns.Config.Settings then
        local opts=ns.Config.Settings() or {}
        for _,key in ipairs({"trackerScrollBeta","trackerZoneSections","trackerSortMode","trackerRecentEnabled","markBaganator"}) do append("option."..key,opts[key]) end
    end
    if ns.NativeCapacity and ns.NativeCapacity.GetState then
        local ok,state=pcall(ns.NativeCapacity.GetState)
        if ok and type(state)=="table" then
            for _,key in ipairs({"enabled","reason","base","expanded","view","trackerHeight","clampBottom","baselineBottom","tripped"}) do append("capacity."..key,state[key]) end
        else append("capacity.error",state) end
    end
    if ns.TrackerZones and ns.TrackerZones.GetDiagnosticState then
        local ok,state=pcall(ns.TrackerZones.GetDiagnosticState)
        if ok and type(state)=="table" then
            for _,key in ipairs({"native","watches","index","last","rows"}) do append("tracker."..key,state[key]) end
        end
    end
    out[#out+1]="\nCOUNTERS (count | rate/sec; merged origins are not mutually exclusive)"
    local keys,seen={},{}
    for _,key in ipairs({"layout.render","layout.render.attempt","layout.coalesced","layout.height.write","layout.height.container","layout.height.tracker","layout.clamp.write","layout.anchor.quest","layout.circuit_breaker","recent.repaint","recent.texture.write","baganator.refresh","scan.core","scan.recent","scan.zones","macro.write"}) do keys[#keys+1]=key;seen[key]=true end
    for key in pairs(counts) do if not seen[key] then keys[#keys+1]=key end end
    table.sort(keys)
    for _,key in ipairs(keys) do local value=counts[key] or 0;out[#out+1]=("%s: %d | %.2f/s"):format(key,value,elapsed>0 and value/elapsed or 0) end
    out[#out+1]="\nTRACE (first 24 + last 64; elapsed seconds, origin and geometry; bounded memory)"
    for _,line in ipairs(first) do out[#out+1]=line end
    local start=math.max(FIRST+1,serial-LAST+1)
    if start>FIRST+1 then out[#out+1]="... "..(start-FIRST-1).." intermediate entries omitted ..." end
    for i=start,serial do local line=recent[(i-FIRST-1)%LAST+1];if line then out[#out+1]=line end end
    return table.concat(out,"\n")
end
function Perf.Report(reset)
    if reset then counts,since,first,recent,serial={},GetTime(),{},{},0;print("QuestHelper perf: contadores reiniciados.");return end
    local report=Perf.BuildReport()
    if ns.Diagnostics and ns.Diagnostics.ShowReport then ns.Diagnostics.ShowReport(report,"Rendimiento QuestHelper")
    else print(report) end
end
function Perf.Snapshot()
    local result = {}
    for key, value in pairs(counts) do result[key]=value end
    return result
end
function State.Invalidate()
    cache, started = {}, nil
end
local function usable(value, depth)
    if issecretvalue and issecretvalue(value) then return false end
    if type(value) ~= "table" then return true end
    if depth > 3 then return false end
    for key, child in pairs(value) do
        if not usable(key, depth+1) or not usable(child, depth+1) then return false end
    end
    return true
end
local function canCache()
    if InCombatLockdown and InCombatLockdown() then return false end
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if fn then
        local ok, result = pcall(fn)
        if not ok or (issecretvalue and issecretvalue(result)) or result ~= false then return false end
    end
    return true
end
local api = setmetatable({}, {__index=Q})
State.API = api
-- Bounded freshness even if a client misses a notification. Never cache nil,
-- empty objective arrays, or a zero-entry journal during login/zone changes.
local function wrap(name)
    api[name] = function(arg)
        local fn = Q and Q[name]
        if type(fn) ~= "function" then return nil end
        if not canCache() or (arg ~= nil and not usable(arg,0)) then return fn(arg) end
        local now = GetTime()
        if not started or now-started > 0.35 then cache, started = {}, now end
        local key = arg == nil and "_" or arg
        local bucket = cache[name]
        if not bucket then bucket={}; cache[name]=bucket end
        if bucket[key] ~= nil then Perf.Count("journal.hit."..name); return bucket[key] end
        Perf.Count("journal.read."..name)
        local result
        if arg == nil then result=fn() else result=fn(arg) end
        if result ~= nil and usable(result,0)
            and not (name=="GetNumQuestLogEntries" and result==0)
            and not (name=="GetQuestObjectives" and type(result)=="table" and next(result)==nil) then
            bucket[key]=result
        end
        return result
    end
end
for _, name in ipairs({"GetNumQuestLogEntries","GetInfo","GetQuestObjectives","GetTitleForQuestID","GetQuestDifficultyLevel"}) do wrap(name) end
local frame=CreateFrame("Frame")
for _, event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LOGIN","QUEST_LOG_UPDATE","QUEST_ACCEPTED",
    "QUEST_REMOVED","QUEST_TURNED_IN","QUEST_COMPLETE","QUEST_WATCH_UPDATE","QUEST_WATCH_LIST_CHANGED",
    "QUEST_DATA_LOAD_RESULT","UNIT_QUEST_LOG_CHANGED","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_LEVEL_UP"}) do
    pcall(frame.RegisterEvent,frame,event)
end
frame:SetScript("OnEvent",function(_,event,unit)
    if event=="UNIT_QUEST_LOG_CHANGED" and (not usable(unit,0) or unit~="player") then return end
    Perf.Count("event."..event)
    Perf.Trace("event",event)
    State.Invalidate()
end)
