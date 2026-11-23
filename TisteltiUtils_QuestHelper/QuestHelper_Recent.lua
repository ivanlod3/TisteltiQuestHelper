-- Resaltado temporal DE LA FILA de misión en el rastreador nativo.
-- Sin paneles, popups, notificaciones, sonidos ni cambios de zona.
-- Escaneos por eventos y un único temporizador de caducidad.
local addonName, ns = ...
local Q = C_QuestLog
local Recent = {}
ns.RecentQuests = Recent

local recent = {}          -- questID -> {kind, time, expires}
local snapshot = {}        -- questID -> {objectives, complete}
local knownQuestIDs = {}   -- misiones vistas desde el inicio de sesión
local initialized, baselineReady, pendingScan = false, false, false
local pendingBaseline, expiryTimer = false, nil
local events = CreateFrame("Frame")

local function readable(value)
    return value ~= nil and (not issecretvalue or not issecretvalue(value))
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok and readable(result) then return result end
end
local function allowed()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if type(fn) == "function" and safe(fn) ~= false then return false end
    return true
end
local function active()
    return ns.Config and ns.Config.Get and ns.Config.Get("trackerRecentEnabled") == true
end
local function duration()
    local settings = ns.Config and ns.Config.Settings and ns.Config.Settings()
    local value = settings and settings.trackerRecentSeconds
    return (value == 30 or value == 60 or value == 90 or value == 120) and value or 60
end
-- The only UI elements created by this module are textures parented to the
-- native quest block. No separate frame, notification or global redraw.
local glowByBlock = setmetatable({}, {__mode = "k"})
local nativeHooked = false
local function isUnsafe()
    return not allowed()
end
local function colorFor(kind)
    if kind == "NUEVA" then return 1, 0.76, 0.16 end
    if kind == "AVANCE" then return 0.25, 0.71, 1 end
    if kind == "LISTA" then return 0.32, 1, 0.48 end
end
local function paint(block, id)
    if not block or not block.HeaderText or isUnsafe() then return end
    -- GetExistingBlock can return a pooled row whose owner has already changed.
    -- Never colour a released block or one assigned to a different quest.
    if not readable(block.id) or block.id ~= id
        or not readable(block.used) or block.used ~= true then
        local old = glowByBlock[block]
        if old then old.glow:Hide(); old.edge:Hide(); old.questID = nil end
        return
    end
    local kind = recent[id] and recent[id].expires > GetTime() and recent[id].kind
    local r, g, b = colorFor(kind)
    local rec = glowByBlock[block]
    if not r then
        if rec then rec.glow:Hide(); rec.edge:Hide(); rec.questID = nil end
        return
    end
    if not rec then
        local title = block.HeaderText
        local glow = block:CreateTexture(nil, "OVERLAY", nil, -1)
        glow:SetPoint("TOPLEFT", title, "TOPLEFT", -5, 4)
        glow:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT", 5, -4)
        local edge = block:CreateTexture(nil, "OVERLAY")
        edge:SetPoint("TOPRIGHT", title, "TOPLEFT", -3, 3)
        edge:SetPoint("BOTTOMRIGHT", title, "BOTTOMLEFT", -3, -3)
        edge:SetWidth(4)
        rec = {glow = glow, edge = edge}
        glowByBlock[block] = rec
    end
    rec.questID = id  -- pooled block can later belong to another quest
    rec.glow:SetColorTexture(r, g, b, 0.38)
    rec.edge:SetColorTexture(r, g, b, 1)
    rec.glow:Show()
    rec.edge:Show()
end
function Recent.Decorate(module, quest, shown)
    if not module or not quest or isUnsafe() then return end
    local id = safe(quest.GetID, quest)
    if type(id) ~= "number" or id <= 0 then return end
    local block = safe(module.GetExistingBlock, module, id)
    if block and readable(block.id) and block.id == id
        and readable(block.used) and block.used == true then paint(block, id) end
end
local function updateDecoration(id)
    if isUnsafe() then return end
    if type(id) == "number" then
        local module = _G.QuestObjectiveTracker
        local block = module and safe(module.GetExistingBlock, module, id)
        if block and readable(block.id) and block.id == id
            and readable(block.used) and block.used == true then
            paint(block, id)
        end
    else
        for block, rec in pairs(glowByBlock) do
            local questID = readable(block.id) and block.id
            if type(questID) == "number" and questID > 0 then
                paint(block, questID)
            else
                rec.glow:Hide()
                rec.edge:Hide()
            end
        end
    end
end
-- After Blizzard has finished laying out its quest rows, decorate only the
-- actual rendered, currently watched blocks. No native repositioning/redraw.
function Recent.RepaintRendered()
    if isUnsafe() then return end
    local module = _G.QuestObjectiveTracker
    if not module or type(module.GetExistingBlock) ~= "function" then return end
    local count = safe(Q and Q.GetNumQuestWatches)
    if type(count) ~= "number" or count < 0 or count > 100 then return end
    local painted = {}
    for i = 1, count do
        local id = safe(Q.GetQuestIDForQuestWatchIndex, i)
        if type(id) == "number" and id > 0 then
            local block = safe(module.GetExistingBlock, module, id)
            if block and block.HeaderText and readable(block.id) and block.id == id
                and readable(block.used) and block.used == true
                and (type(block.IsShown) ~= "function" or safe(block.IsShown, block) == true) then
                painted[block] = true
                paint(block, id)
            end
        end
    end
    -- A native pool may recycle or release a block. Do not leave a glow on a
    -- different quest or a released row. Weak keys prevent retained UI frames.
    for block, rec in pairs(glowByBlock) do
        if not painted[block] then
            rec.glow:Hide()
            rec.edge:Hide()
            rec.questID = nil
        end
    end
end
local function tryNativeHook()
    if nativeHooked then return end
    local module = _G.QuestObjectiveTracker
    if not module or type(hooksecurefunc) ~= "function" then return end
    -- EndLayout is the first reliable point at which the final pooled rows
    -- are known. UpdateSingle alone runs too early on Forever.
    local method = type(module.EndLayout) == "function" and "EndLayout"
        or (type(module.LayoutContents) == "function" and "LayoutContents")
    if method then
        nativeHooked = pcall(hooksecurefunc, module, method, function()
            Recent.RepaintRendered()
        end)
    end
end
local function purgeExpired()
    local now = GetTime()
    for id, item in pairs(recent) do
        if item.expires <= now then
            recent[id] = nil
            updateDecoration(id)
        end
    end
end
function Recent.GetStatus(id)
    if not active() or type(id) ~= "number" then return nil end
    local item = recent[id]
    if item and item.expires > GetTime() then return item.kind end
    return nil
end
local scheduleExpiry
scheduleExpiry = function()
    if expiryTimer then expiryTimer:Cancel(); expiryTimer = nil end
    if not active() then return end
    local earliest
    for _, item in pairs(recent) do
        if not earliest or item.expires < earliest then earliest = item.expires end
    end
    if earliest and C_Timer and type(C_Timer.NewTimer) == "function" then
        expiryTimer = C_Timer.NewTimer(math.max(0.05, earliest - GetTime()), function()
            expiryTimer = nil
            purgeExpired()
            scheduleExpiry()
        end)
    end
end
local function stateText(state)
    if not state then return "sin instantanea" end
    local parts = {"lista=" .. tostring(state.complete)}
    for i, objective in ipairs(state.objectives or {}) do
        if i > 12 then parts[#parts + 1] = "..."; break end
        parts[#parts + 1] = tostring(i) .. ":" .. tostring(objective.identity)
            .. "=" .. tostring(objective.current or "-") .. "/" .. tostring(objective.required or "-")
            .. "(fin=" .. tostring(objective.done) .. ")"
    end
    return table.concat(parts, ";")
end
local function mark(id, kind, reason, before, after)
    if not active() or type(id) ~= "number" or id <= 0 then return end
    if ns.Diagnostics and ns.Diagnostics.RecordRecent then
        ns.Diagnostics.RecordRecent(id, kind, reason or "evento",
            stateText(before), stateText(after))
    end
    local now = GetTime()
    recent[id] = {kind = kind, time = now, expires = now + duration()}
    updateDecoration(id)
    scheduleExpiry()
end
local function remove(id)
    if type(id) ~= "number" then return end
    recent[id], snapshot[id], knownQuestIDs[id] = nil, nil, nil
    updateDecoration(id)
    scheduleExpiry()
end
-- Identidad estable: no interpretar la reescritura de una descripción como progreso.
-- Para el cliente que no rellena numFulfilled/numRequired, usar el sufijo 1/8.
local function objectiveText(obj)
    if type(obj) ~= "table" or not readable(obj.text)
        or type(obj.text) ~= "string" then return nil end
    local text = obj.text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local done = readable(obj.finished) and obj.finished == true
    local current = readable(obj.numFulfilled) and obj.numFulfilled or nil
    local required = readable(obj.numRequired) and obj.numRequired or nil
    if type(current) ~= "number" or type(required) ~= "number" then
        local a, b = text:match("(%d+)%s*/%s*(%d+)%s*$")
        current, required = tonumber(a), tonumber(b)
    end
    local identity = text:gsub("%s*%d+%s*/%s*%d+%s*$", ""):gsub("%s+$", "")
    return {identity=identity, current=current, required=required, done=done}
end
local function readObjectives(id)
    local raw = safe(Q and Q.GetQuestObjectives, id)
    if type(raw) ~= "table" then return nil end
    local out = {}
    for i, obj in ipairs(raw) do
        local item = objectiveText(obj)
        if item then out[i] = item end
    end
    return out
end
local function changedObjective(before, after)
    for index, item in pairs(after) do
        local previous = before[index]
        -- Objetivos reconstruidos o reordenados no prueban avance. Solo
        -- comparamos la misma identidad, conservando el denominador.
        if previous and previous.identity == item.identity then
            local validCount = type(previous.current) == "number"
                and type(item.current) == "number"
                and type(previous.required) == "number"
                and previous.required == item.required and item.required > 0
            if validCount and item.current > previous.current then
                return ("contador[%d] %d/%d -> %d/%d"):format(index,
                    previous.current,previous.required,item.current,item.required)
            end
            if not previous.done and item.done
                and (not validCount or item.current >= previous.current)
                and (previous.required == nil or item.required == previous.required) then
                return ("completado[%d] false -> true"):format(index)
            end
        end
    end
    return nil
end
local function scan(initial)
    pendingScan = false
    if not active() or not Q or not allowed() then return end
    local total = safe(Q.GetNumQuestLogEntries)
    if type(total) ~= "number" or total < 0 or total > 500 then return end
    local seen = {}
    for i = 1, total do
        local info = safe(Q.GetInfo, i)
        if type(info) == "table" and readable(info.isHeader) and not info.isHeader
            and readable(info.questID) and type(info.questID) == "number" and info.questID > 0 then
            local id = info.questID
            seen[id] = true
            local previouslyKnown = knownQuestIDs[id]
            knownQuestIDs[id] = true
            local objectives = readObjectives(id)
            if objectives then
                local complete = ns.QuestStatus
                    and ns.QuestStatus.IsReady(id, info) == true
                local old = snapshot[id]
                if not initial and baselineReady and old then
                    if complete and not old.complete then
                        mark(id, "LISTA", "lista para entregar", old,
                            {objectives=objectives, complete=complete})
                    else
                        local reason = changedObjective(old.objectives, objectives)
                        if reason then mark(id, "AVANCE", reason, old,
                            {objectives=objectives, complete=complete}) end
                    end
                elseif not initial and baselineReady and not old
                    and not previouslyKnown and not recent[id] then
                    mark(id, "NUEVA", "nueva en el diario", nil,
                        {objectives=objectives, complete=complete})
                end
                snapshot[id] = {objectives = objectives, complete = complete}
            end
        end
    end
    if baselineReady then
        for id in pairs(snapshot) do
            if not seen[id] then snapshot[id] = nil end
        end
    end
    baselineReady = true
end
local function requestScan(delay)
    if not active() or pendingScan or not baselineReady then return end
    if not C_Timer or type(C_Timer.After) ~= "function" then return end
    pendingScan = true
    C_Timer.After(delay or 0.18, function()
        if not allowed() then pendingScan = false; return end
        scan(false)
    end)
end
local function initializeBaseline()
    if pendingBaseline or not C_Timer or type(C_Timer.After) ~= "function" then return end
    pendingBaseline = true
    C_Timer.After(1.2, function()
        pendingBaseline = false
        if not baselineReady then scan(true) else requestScan(0) end
    end)
end
function Recent.Initialize()
    if initialized then return end
    initialized = true
    tryNativeHook()
    for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED",
        "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED",
        "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_COMPLETE", "QUEST_DATA_LOAD_RESULT",
        "PLAYER_REGEN_ENABLED"}) do
        pcall(events.RegisterEvent, events, event)
    end
end
function Recent.RefreshSettings(key)
    if key == "trackerRecentEnabled" then
        if not active() then
            for id in pairs(recent) do
                recent[id] = nil
                updateDecoration(id)
            end
            wipe(snapshot)
            wipe(knownQuestIDs)
            baselineReady = false
            if expiryTimer then expiryTimer:Cancel(); expiryTimer = nil end
            updateDecoration()  -- ocultar todos los brillos de la sesión
        else
            initializeBaseline()
        end
    elseif key == "trackerRecentSeconds" then
        for _, item in pairs(recent) do item.expires = item.time + duration() end
        purgeExpired()
        scheduleExpiry()
    end
end
events:SetScript("OnEvent", function(_, event, a, b)
    if not active() then return end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        tryNativeHook()
        if event == "PLAYER_ENTERING_WORLD" then
            baselineReady = false
            wipe(snapshot)
            wipe(knownQuestIDs)
        end
        initializeBaseline()
    elseif event == "QUEST_ACCEPTED" then
        local id = (readable(b) and type(b) == "number" and b > 0) and b or a
        if readable(id) and type(id) == "number" and id > 0 then
            mark(id, "NUEVA", "QUEST_ACCEPTED")
        end
        requestScan(0.2)
    elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        if readable(a) then remove(a) end
        requestScan(0.18)
    elseif event == "PLAYER_REGEN_ENABLED" then
        tryNativeHook()
        Recent.RepaintRendered()
        if baselineReady then requestScan(0.25) else initializeBaseline() end
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if readable(a) and a == "player" then requestScan(0.18) end
    else
        requestScan(0.18)
    end
end)
