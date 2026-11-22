-- TisteltiUtils QuestHelper: avisos de grupo.
-- La deteccion por cambios de objetivos y el recuento al subir de nivel siguen el
-- comportamiento de Quest Together (Tim, MIT; ver LICENSE-QuestTogether.txt).
-- No se comparte ninguna mision ni se modifica la macro desde este modulo.
local addonName, ns = ...
ns = ns or {}

local Config = {}
ns.Config = Config
-- Numeric appearance settings are account-wide. Existing SavedVariables are kept.
-- Ranges keep the UI compact and prevent invalid font/layout dimensions.
local appearance = {
    plateIconSize = {20, 14, 28},
    plateTextSize = {12, 9, 20},
    plateStackIconSize = {16, 12, 24},
    plateStackTextSize = {13, 9, 20},
    plateMultiTextSize = {10, 9, 18},
    plateNumberGap = {5, 0, 14},
    plateRowSpacing = {0, 0, 9},
    plateDistance = {6, 0, 20},
    plateRaidTargetExtra = {4, 0, 20}, -- extra separation for native raid markers and elite/rare indicators
    bagMarkerSize = {15, 10, 24},
    bagOutlineWidth = {1, 0, 3},
    bagCounterSize = {11, 9, 18},
}
local defaults = {
    announceObjectives = true,
    announceQuests = true,
    announceLevels = false, -- new installations; existing true/false is preserved
    nameplateIcons = true,
    autoMacro = true,
    markBags = false, -- Blizzard bags; optional
    markBaganator = false, -- Baganator's native corner-widget API; optional
    itemTooltips = false, -- optional; post-call only
    trackerSortMode = "native", -- tracker watches only; inactive means zero extra events
    trackerZoneSections = true, -- native post-layout zones; preserve any existing saved choice
    trackerSearchButton = true, -- display native search magnifier by default
    trackerSearchKeepOnBlur = true, -- retain nonempty search when the input loses focus
    trackerScrollBeta = true, -- wheel paging if all watched quests have native blocks
    trackerMarkNewQuests = true, -- legacy setting (unused, retained for SavedVariables)
    trackerRecentEnabled = true, -- inline native quest highlights; no notifications
    trackerRecentSeconds = 60, -- inline glow duration: 30/60/90/120 seconds
}
for key, range in pairs(appearance) do defaults[key] = range[1] end
local settings, character

local function note(message)
    print("|cff73c9ffTisteltiUtils QuestHelper:|r " .. message)
end

local function usable(value)
    return not issecretvalue or not issecretvalue(value)
end
local function secureCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and usable(value) then return value end
end
local function bool(value)
    if not usable(value) then return nil end
    if type(value) == "boolean" then return value end
    return nil
end
local function numeric(value)
    if usable(value) and type(value) == "number" then return value end
end
local function stringValue(value)
    if usable(value) and type(value) == "string" then return value end
end

function Config.Init()
    if type(TisteltiQuestHelperDB) ~= "table" then TisteltiQuestHelperDB = {} end
    if type(TisteltiQuestHelperDB.settings) ~= "table" then TisteltiQuestHelperDB.settings = {} end
    settings = TisteltiQuestHelperDB.settings
    -- Migrar 0.7.28: una protección defectuosa deshabilitó las zonas.
    -- Ya no existe y no debe prevalecer sobre trackerZoneSections guardado.
    settings.trackerSafeMode = nil
    for key, value in pairs(defaults) do
        if type(settings[key]) ~= type(value) then settings[key] = value end
    end
    if settings.trackerRecentSeconds ~= 30 and settings.trackerRecentSeconds ~= 60
        and settings.trackerRecentSeconds ~= 90 and settings.trackerRecentSeconds ~= 120 then
        settings.trackerRecentSeconds = 60
    end
    if type(settings.trackerSortMode) ~= "string" then settings.trackerSortMode = "native" end
    for key, range in pairs(appearance) do
        local n = settings[key]
        if type(n) ~= "number" or n ~= n then n = range[1] end
        settings[key] = math.max(range[2], math.min(range[3], math.floor(n + 0.5)))
    end
    if ns.TrackerSort and ns.TrackerSort.Initialize then ns.TrackerSort.Initialize() end
    if ns.TrackerZones and ns.TrackerZones.Initialize then ns.TrackerZones.Initialize() end
    if ns.RecentQuests and ns.RecentQuests.Initialize then ns.RecentQuests.Initialize() end
    if ns.TurnInFilter and ns.TurnInFilter.Initialize then ns.TurnInFilter.Initialize() end
    if type(TisteltiQuestHelperCharDB) ~= "table" then TisteltiQuestHelperCharDB = {} end
    character = TisteltiQuestHelperCharDB
end
function Config.Settings() return settings end
function Config.Defaults() return defaults end
function Config.Get(key) return settings and settings[key] == true end
function Config.GetNumber(key)
    local r = appearance[key]
    if not r then return nil end
    return settings and settings[key] or r[1]
end
function Config.IsAppearance(key) return appearance[key] ~= nil end
function Config.AppearanceRanges() return appearance end
function Config.SetAppearance(key, value)
    local r = appearance[key]
    if not r or type(settings) ~= "table" or type(value) ~= "number" or value ~= value then return end
    local new = math.max(r[2], math.min(r[3], math.floor(value + 0.5)))
    if settings[key] == new then return end
    settings[key] = new
    if key:sub(1, 5) == "plate" and ns.PlateAppearance and ns.PlateAppearance.Refresh then
        ns.PlateAppearance.Refresh()
    elseif key:sub(1, 3) == "bag" and ns.QuestItems and ns.QuestItems.RefreshAppearance then
        ns.QuestItems.RefreshAppearance(key)
    end
    if ns.AppearanceOptions and ns.AppearanceOptions.Refresh then ns.AppearanceOptions.Refresh() end
end
function Config.ResetAppearance(prefix)
    if type(settings) ~= "table" then return end
    local changedPlate, changedBag = false, false
    for key, range in pairs(appearance) do
        if key:sub(1, #prefix) == prefix and settings[key] ~= range[1] then
            settings[key] = range[1]
            if prefix == "plate" then changedPlate = true else changedBag = true end
        end
    end
    if changedPlate and ns.PlateAppearance and ns.PlateAppearance.Refresh then ns.PlateAppearance.Refresh() end
    if changedBag and ns.QuestItems and ns.QuestItems.RefreshAppearance then ns.QuestItems.RefreshAppearance("bagMarkerSize") end
    if ns.AppearanceOptions and ns.AppearanceOptions.Refresh then ns.AppearanceOptions.Refresh() end
end
-- Settings callbacks are fired by the native interface. Keep an explicit
-- dispatcher to apply changes immediately without a permanently running tick.
function ns.RefreshSettings(key)
    if ns.CoreRefreshSettings then ns.CoreRefreshSettings(key) end
    if ns.QuestItems and ns.QuestItems.RefreshSettings then
        ns.QuestItems.RefreshSettings(key)
    end
    if ns.AnnounceRefreshSettings then ns.AnnounceRefreshSettings(key) end
    if ns.TrackerSort and ns.TrackerSort.RefreshSettings then ns.TrackerSort.RefreshSettings(key) end
    if ns.TrackerZones and ns.TrackerZones.RefreshSettings then ns.TrackerZones.RefreshSettings(key) end
    if ns.RecentQuests and ns.RecentQuests.RefreshSettings then ns.RecentQuests.RefreshSettings(key) end
end

local function inParty()
    if secureCall(IsInRaid) == true then return false end
    if type(IsInGroup) == "function" then
        return secureCall(IsInGroup, LE_PARTY_CATEGORY_HOME) == true
    end
    return (numeric(secureCall(GetNumSubgroupMembers)) or 0) > 0
end

-- Mensajes cortos, con una unica cola para evitar rafagas y mensajes caducados.
local pending, ticker = {}, nil
local blocked, sent = false, 0
local function chatLocked()
    return secureCall(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) == true
end
local function stopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end
local startTicker
local function pump()
    if not inParty() or blocked then
        wipe(pending)
        stopTicker()
        return
    end
    local nextMessage = pending[1]
    if not nextMessage then stopTicker(); return end
    if GetTime() - nextMessage.time > 120 then
        table.remove(pending, 1)
        return
    end
    if chatLocked() then
        stopTicker()
        -- Tras un bloqueo de chat se reintenta, sin enviar mientras dura.
        C_Timer.After(5, function() if #pending > 0 then startTicker() end end)
        return
    end
    local func = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(func) ~= "function" then
        wipe(pending)
        stopTicker()
        return
    end
    local ok = pcall(func, nextMessage.text, "PARTY")
    table.remove(pending, 1)
    if ok then sent = sent + 1 end
    if not pending[1] then stopTicker() end
end
function startTicker()
    if ticker or not pending[1] or blocked then return end
    ticker = C_Timer.NewTicker(0.3, pump)
    pump()
end
local function queue(message)
    if not inParty() or blocked or type(message) ~= "string" or message == "" then return false end
    if #pending >= 10 then table.remove(pending, 1) end
    pending[#pending + 1] = { text = message, time = GetTime() }
    startTicker()
    return true
end

-- Evitar cortar caracteres UTF-8 al respetar los 255 bytes de chat.
local function fit(text, limit)
    if #text <= limit then return text end
    if limit <= 0 then return "" end
    local n = limit
    while n > 0 do
        local b = text:byte(n + 1)
        if not b or b < 128 or b >= 192 then break end
        n = n - 1
    end
    return text:sub(1, n)
end
local function questLink(questID, title)
    local link = stringValue(secureCall(GetQuestLink, questID))
    if link and link ~= "" and #link < 180 then return link end
    return "[" .. fit(title, 125) .. "]"
end
local function compose(prefix, detail, suffix)
    prefix, detail, suffix = prefix or "", detail or "", suffix or ""
    local room = 255 - #prefix - #suffix
    if room < 0 then return nil end
    return prefix .. fit(detail, room) .. suffix
end

local countPatterns = {
    "^%d+%s*/%s*%d+%s+(.-)$",  -- 4/6 Lobos
    "^(.-)%s*:%s*%d+%s*/%s*%d+$", -- Lobos: 4/6
    "^(.-)%s*%(%d+%s*/%s*%d+%)$", -- Lobos (4/6)
}
local function objectiveLabel(text)
    if type(text) ~= "string" then return "", false end
    local completed = stringValue(COMPLETE)
    if completed then
        local suffix = " (" .. completed .. ")"
        if text:sub(-#suffix) == suffix then text = text:sub(1, -#suffix - 1) end
    end
    for _, pattern in ipairs(countPatterns) do
        local label = text:match(pattern)
        if label and label ~= "" then return label, true end
    end
    return text, false
end

local function readQuest(questID, titleHint)
    local title = stringValue(secureCall(C_QuestLog.GetTitleForQuestID, questID)) or titleHint
    if not title or title == "" then return nil end
    local raw = secureCall(C_QuestLog.GetQuestObjectives, questID)
    if type(raw) ~= "table" then
        if C_QuestLog.RequestLoadQuestByID then
            pcall(C_QuestLog.RequestLoadQuestByID, questID)
        end
        return nil
    end
    local objectives, allDone, visible = {}, true, 0
    for index, obj in ipairs(raw) do
        if type(obj) ~= "table" then return nil end
        local text = stringValue(obj.text)
        local finished = bool(obj.finished)
        if not text or finished == nil or not stringValue(obj.type) then return nil end
        -- Datos provisionales tras cargas de zona: no compararlos con un registro estable.
        if text ~= "" and (text:find("^%s") or text:find("%s$")) then return nil end
        local label, hadCount = objectiveLabel(text)
        local required = math.max(1, math.floor(numeric(obj.numRequired) or 0))
        local current = math.max(0, math.floor(numeric(obj.numFulfilled) or 0))
        if finished then current = required else current = math.min(current, required - 1) end
        objectives[index] = {
            done = finished, label = label, hadCount = hadCount,
            required = required, current = current, hidden = text == "",
        }
        if text ~= "" then visible = visible + 1 end
        allDone = allDone and finished
    end
    local completed = bool(secureCall(C_QuestLog.IsComplete, questID)) == true
    local ready = bool(secureCall(C_QuestLog.ReadyForTurnIn, questID)) == true
    local failed = bool(secureCall(C_QuestLog.IsFailed, questID)) == true
    return {
        id = questID, title = title, objectives = objectives,
        completed = not failed and (completed or ready or (#objectives > 0 and allDone)),
        visible = visible,
    }
end

local records, missing = {}, {}
local started, refreshPending = false, false
local settleUntil, silentAfterZoning = 0, false
local totalObjectives, totalQuests = 0, 0

local function objectiveLine(quest, objective)
    local detail = objective.label
    if objective.hadCount or objective.required > 1 then
        detail = objective.current .. "/" .. objective.required .. " " .. detail
    end
    local suffix = " para " .. questLink(quest.id, quest.title) .. "!"
    return compose("{rt1} ", detail, suffix)
end
local function questLine(quest)
    return compose("{rt1} Misión completada: ", questLink(quest.id, quest.title), "!")
end
local function applyQuest(quest, silent)
    local before = records[quest.id]
    if not before then
        local announced = {}
        local done = {}
        for i, obj in ipairs(quest.objectives) do
            done[i] = obj.done
            announced[i] = obj.done
        end
        records[quest.id] = { done = done, announced = announced, completed = quest.completed, title = quest.title }
        return
    end
    local finalObjectiveSent = false
    for index, obj in ipairs(quest.objectives) do
        local wasDone = before.done[index]
        -- Objetivos que aparecen terminados sin haberse visto pendientes son baseline.
        if wasDone == false and obj.done and not before.announced[index] then
            before.announced[index] = true
            if not silent and not obj.hidden and Config.Get("announceObjectives") then
                if queue(objectiveLine(quest, obj)) then
                    totalObjectives = totalObjectives + 1
                    finalObjectiveSent = true
                end
            end
        elseif wasDone == nil and obj.done then
            before.announced[index] = true
        end
        before.done[index] = obj.done
    end
    for index = #before.done, #quest.objectives + 1, -1 do
        before.done[index], before.announced[index] = nil, nil
    end
    if quest.completed and not before.completed and not silent then
        -- Al igual que Quest Together, la ultima linea de objetivo ya basta.
        -- Si objetivos esta desactivado (o no hay objetivo visible), se anuncia la mision.
        if Config.Get("announceQuests") and not finalObjectiveSent then
            if queue(questLine(quest)) then totalQuests = totalQuests + 1 end
        end
    end
    before.completed, before.title = quest.completed, quest.title
end

local scan
local function scanNoticesEnabled()
    return Config.Get("announceObjectives") or Config.Get("announceQuests")
end
local function requestScan(delay)
    if not started or not scanNoticesEnabled() or not inParty() or refreshPending then return end
    refreshPending = true
    C_Timer.After(delay or 0.25, function()
        refreshPending = false
        scan()
    end)
end
function scan()
    if not started or not C_QuestLog or not scanNoticesEnabled() or not inParty() then return end
    -- En la ventana de estabilizacion no modificar el baseline; evitamos falsos avisos
    -- por contadores que el cliente restaura al entrar al mundo.
    if GetTime() < settleUntil then
        requestScan(math.max(0.1, settleUntil - GetTime() + 0.1))
        return
    end
    local total = numeric(secureCall(C_QuestLog.GetNumQuestLogEntries)) or 0
    local found = {}
    local silent = silentAfterZoning
    silentAfterZoning = false
    for i = 1, total do
        local info = secureCall(C_QuestLog.GetInfo, i)
        if type(info) == "table" and bool(info.isHeader) == false then
            local questID = numeric(info.questID)
            if questID and questID > 0 and not found[questID] then
                found[questID] = true
                local quest = readQuest(questID, stringValue(info.title))
                if quest then applyQuest(quest, silent) end
            end
        end
    end
    -- Mantener misiones que desaparecieron de la lista por cabeceras plegadas.
    for questID in pairs(records) do
        if not found[questID] then
            if bool(secureCall(C_QuestLog.IsOnQuest, questID)) == true then
                local quest = readQuest(questID, records[questID].title)
                if quest then applyQuest(quest, silent) end
                missing[questID] = nil
            else
                missing[questID] = (missing[questID] or 0) + 1
                if missing[questID] >= 2 then
                    records[questID], missing[questID] = nil, nil
                end
            end
        else
            missing[questID] = nil
        end
    end
end

-- Recuento al subir de nivel (como Quest Together), persistente por personaje.
local completedAt = {}
local pendingLevel, levelTimer, levelUpAt, levelUpFrom
local function currentLevel() return numeric(secureCall(UnitLevel, "player")) end
local function initializeLevel()
    if not character then return end
    local guid = stringValue(secureCall(UnitGUID, "player"))
    if guid and character.guid ~= guid then
        wipe(character)
        character.guid = guid
    end
    local level = currentLevel()
    if not level then return end
    if character.level ~= level or type(character.quests) ~= "number" then
        character.level, character.quests = level, 0
        character.partial = (numeric(secureCall(UnitXP, "player")) or 0) > 0
    end
end
local function postLevel()
    levelTimer = nil
    local previous = pendingLevel
    pendingLevel = nil
    if not previous or not Config.Get("announceLevels") or not inParty() then return end
    if previous.partial then
        note(("El nivel %d no se siguió completo; no envío un recuento parcial al grupo."):format(previous.level))
        return
    end
    local label = previous.quests == 1 and "misión completada" or "misiones completadas"
    queue(("[QuestHelper]: %d %s en el nivel %d!"):format(previous.quests, label, previous.level))
end
local function levelUp(level)
    level = numeric(level)
    if not character or not level or not character.level or level <= character.level then return end
    if pendingLevel then
        if levelTimer then levelTimer:Cancel() end
        postLevel()
    end
    pendingLevel = { level = character.level, quests = character.quests or 0, partial = character.partial }
    levelUpAt, levelUpFrom = GetTime(), character.level
    character.level, character.quests, character.partial = level, 0, false
    levelTimer = C_Timer.NewTimer(3, postLevel)
end
local function questTurnedIn(questID)
    questID = numeric(questID)
    if not questID or not character or not character.level then return end
    if not Config.Get("announceLevels") then
        completedAt[questID] = nil
        records[questID], missing[questID] = nil, nil
        requestScan()
        return
    end
    local level = completedAt[questID]
    completedAt[questID] = nil
    if not level then
        local recently = levelUpAt and GetTime() - levelUpAt < 3
        level = recently and levelUpFrom or character.level
    end
    if pendingLevel and level == pendingLevel.level then
        pendingLevel.quests = pendingLevel.quests + 1
    elseif level == character.level then
        character.quests = (character.quests or 0) + 1
    end
    records[questID], missing[questID] = nil, nil
    requestScan()
end

local frame = CreateFrame("Frame")
local wasInParty = false
frame:SetScript("OnEvent", function(_, event, arg, detail)
    if event == "ADDON_LOADED" then
        if arg == addonName then Config.Init() end
    elseif event == "PLAYER_LOGIN" then
        initializeLevel()
        started = true
        requestScan(0.1)
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
        if loaded and (secureCall(loaded, "QuestTogether") == true or secureCall(loaded, "Questie") == true)
            and Config.Get("announceObjectives") and not TisteltiQuestHelperDB.duplicateWarning then
            TisteltiQuestHelperDB.duplicateWarning = true
            note("Si QuestTogether o Questie anuncia objetivos tambien, desactiva los avisos en uno para evitar duplicados.")
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        local nowParty = inParty()
        if nowParty ~= wasInParty then
            wasInParty = nowParty
            wipe(records)
            wipe(missing)
            silentAfterZoning = true
            if nowParty then requestScan(0.1) else wipe(pending); stopTicker() end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        wasInParty = inParty()
        settleUntil = GetTime() + 5
        silentAfterZoning = true
        requestScan(5.1)
    elseif event == "QUEST_COMPLETE" then
        if Config.Get("announceLevels") then
            local questID = numeric(secureCall(GetQuestID))
            if questID and questID > 0 then completedAt[questID] = currentLevel() end
        end
    elseif event == "QUEST_TURNED_IN" then
        questTurnedIn(arg)
    elseif event == "QUEST_REMOVED" then
        if numeric(arg) then records[arg], missing[arg] = nil, nil end
        requestScan()
    elseif event == "PLAYER_LEVEL_UP" then
        if Config.Get("announceLevels") then levelUp(arg) end
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if arg == "player" then requestScan() end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if #pending > 0 and not chatLocked() then stopTicker(); startTicker() end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg == addonName and stringValue(detail)
            and detail:find("SendChatMessage", 1, true) then
            blocked = true
            wipe(pending)
            stopTicker()
            note("El cliente ha bloqueado una acción del addon. Los avisos al grupo se detienen en esta sesion.")
        end
    else
        requestScan()
    end
end)
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_COMPLETE",
    "QUEST_DATA_LOAD_RESULT", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED",
    "PLAYER_LEVEL_UP", "GROUP_ROSTER_UPDATE", "ADDON_RESTRICTION_STATE_CHANGED", "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN",
}) do
    pcall(frame.RegisterEvent, frame, event)
end

function ns.AnnounceRefreshSettings(key)
    if key == "announceObjectives" or key == "announceQuests" then
        -- Always capture a fresh baseline after toggling: do not interpret
        -- already finished objectives as newly completed.
        wipe(records)
        wipe(missing)
        silentAfterZoning = true
        requestScan(0.1)
    end
    if key == "announceLevels" and character then
        -- Switching level announcements on mid-level cannot reconstruct the
        -- earlier quest count. The current level is marked partial.
        if Config.Get("announceLevels") then
            initializeLevel()
            character.partial = true
        elseif levelTimer then
            levelTimer:Cancel()
            levelTimer = nil
            pendingLevel = nil
        end
    end
    if not Config.Get("announceObjectives") and not Config.Get("announceQuests")
       and not Config.Get("announceLevels") then
        wipe(pending)
        stopTicker()
    end
end

function ns.AnnounceDebug()
    note(("Avisos: %d objetivos, %d misiones, %d mensajes enviados; %d en cola.")
        :format(totalObjectives, totalQuests, sent, #pending))
    if character then
        note(("Nivel %s: %s misiones entregadas; seguimiento parcial: %s.")
            :format(tostring(character.level or "?"), tostring(character.quests or 0),
                tostring(character.partial == true)))
    end
end
