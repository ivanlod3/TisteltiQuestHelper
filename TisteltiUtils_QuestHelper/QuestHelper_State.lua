-- Shared short-lived read-through journal view. Never caches protected/secret data.
-- Invalidate on journal events; no timer, no polling, no writes to Blizzard.
local _, ns = ...
local Q = C_QuestLog
local cache, started = {}, nil
local Perf, State = {}, {}
ns.Perf, ns.QuestState = Perf, State
local counts, since = {}, GetTime()
function Perf.Count(key)
    counts[key] = (counts[key] or 0) + 1
end
function Perf.Report(reset)
    if reset then counts, since = {}, GetTime(); print("QuestHelper perf: contadores reiniciados."); return end
    local keys = {}
    for key in pairs(counts) do keys[#keys+1] = key end
    table.sort(keys)
    print(("QuestHelper perf: %.1f s desde el reinicio"):format(GetTime()-since))
    for _, key in ipairs(keys) do print(key .. ": " .. counts[key]) end
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
    State.Invalidate()
end)
