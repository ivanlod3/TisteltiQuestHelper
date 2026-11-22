-- TisteltiUtils QuestHelper: compartir progreso manualmente desde el menu
-- contextual nativo de las misiones seguidas en WoW Forever.
-- Ningun envio automatico; no se cambia el seguimiento ni se toca el tracker.
local addonName, ns = ...

local lastHoveredQuestID
local registered = false

local function readable(value)
    return value ~= nil and (not issecretvalue or not issecretvalue(value))
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end

local function notify(message)
    print("|cff73c9ffTisteltiUtils QuestHelper:|r " .. message)
end

local function chatChannel()
    if safe(IsInRaid) == true then return "RAID" end
    if type(LE_PARTY_CATEGORY_INSTANCE) == "number"
        and safe(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) == true then return "INSTANCE_CHAT" end
    if type(LE_PARTY_CATEGORY_HOME) == "number"
        and safe(IsInGroup, LE_PARTY_CATEGORY_HOME) == true then return "PARTY" end
    if safe(IsInGroup) == true then return "PARTY" end
    return nil
end

local function utf8Fit(text, limit)
    if #text <= limit then return text end
    if limit <= 0 then return "" end
    local n = limit
    while n > 0 do
        local byte = text:byte(n + 1)
        if not byte or byte < 128 or byte >= 192 then break end
        n = n - 1
    end
    return text:sub(1, n)
end

local function questLink(questID, name)
    local link = safe(GetQuestLink, questID)
    if type(link) == "string" and link ~= "" and #link < 140 then return link end
    return "[" .. utf8Fit(name, 100) .. "]"
end

local function objectiveName(text)
    local label = text:match("^(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
        or text:match("^%d+%s*/%s*%d+%s+(.-)%s*$")
        or text:match("^(.-)%s*%(%d+%s*/%s*%d+%)%s*$")
        or text:match("^(.-)%s+%d+%s*/%s*%d+%s*$")
    return label or text
end

-- Una unica lectura puntual de la mision al pulsar. No cache ni escaneos.
local function progressMessage(questID)
    local title = safe(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID)
    if type(title) ~= "string" or title == "" then return nil end
    local objectives = safe(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if type(objectives) ~= "table" then return nil end

    local outstanding, found = {}, 0
    for _, obj in ipairs(objectives) do
        if type(obj) == "table" then
            local text = readable(obj.text) and obj.text or nil
            if type(text) == "string" and text ~= "" then
                found = found + 1
                local required = readable(obj.numRequired) and obj.numRequired or nil
                local fulfilled = readable(obj.numFulfilled) and obj.numFulfilled or nil
                local finished = (readable(obj.finished) and obj.finished == true)
                    or (type(required) == "number" and required > 0
                        and type(fulfilled) == "number" and fulfilled >= required)
                if not finished then
                    local name = objectiveName(text)
                    if type(required) == "number" and type(fulfilled) == "number"
                        and required > 0 and fulfilled >= 0 then
                        outstanding[#outstanding + 1] = name .. " " .. math.floor(fulfilled) .. "/" .. math.floor(required)
                    else
                        outstanding[#outstanding + 1] = text
                    end
                end
            end
        end
    end

    local header = "[QuestHelper] " .. questLink(questID, title) .. ": "
    if #header > 190 then header = "[QuestHelper] [" .. utf8Fit(title, 90) .. "]: " end
    if #outstanding == 0 then
        if safe(C_QuestLog and C_QuestLog.IsComplete, questID) == true
            or safe(C_QuestLog and C_QuestLog.ReadyForTurnIn, questID) == true
            or found > 0 then
            return utf8Fit(header .. "Objetivos completados (pendiente de entregar)", 255)
        end
        return utf8Fit(header .. "Sin progreso de objetivos disponible", 255)
    end

    local message = header .. "Pendiente: "
    for i, part in ipairs(outstanding) do
        local separator = i == 1 and "" or "; "
        local remaining = #outstanding - i
        local suffix = remaining > 0 and ("; +" .. remaining .. " más") or ""
        if #message + #separator + #part + #suffix > 255 then
            local count = #outstanding - i + 1
            local more = "; +" .. count .. " más"
            if #message + #more <= 255 then
                message = message .. more
            end
            break
        end
        message = message .. separator .. part
    end
    return message
end

local function sendProgress(questID)
    -- El ID se captura al crear el menu, no al pulsar la opcion.
    if type(questID) ~= "number" or questID <= 0 then return end
    local channel = chatChannel()
    if not channel then
        notify("Debes estar en un grupo para compartir el progreso.")
        return
    end
    if safe(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) == true then
        notify("El cliente no permite enviar mensajes al grupo en este momento.")
        return
    end
    local message = progressMessage(questID)
    if not message then
        notify("Los datos de esta mision no estan disponibles todavia.")
        return
    end
    local func = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(func) ~= "function" then
        notify("El cliente no expone la API de chat.")
        return
    end
    local ok, err = pcall(func, message, channel)
    if not ok then
        notify("No se ha podido enviar el progreso (restriccion de chat).")
    end
end

local function onQuestHover(_, block, questID)
    if type(questID) == "number" and questID > 0 then
        lastHoveredQuestID = questID
    end
end

local function populateMenu(_, rootDescription)
    -- La API del menu no pasa el questID en contextData. El evento nativo
    -- OnQuestBlockHeader.OnEnter nos da el ID exacto del bloque bajo el cursor.
    local questID = lastHoveredQuestID
    if type(questID) ~= "number" or questID <= 0 then return end
    if safe(C_QuestLog and C_QuestLog.IsOnQuest, questID) ~= true then return end
    if not rootDescription or type(rootDescription.CreateButton) ~= "function" then return end
    rootDescription:CreateDivider()
    rootDescription:CreateButton("Compartir progreso en grupo", function()
        sendProgress(questID)
    end)
end

local function register()
    if registered then return end
    if not Menu or type(Menu.ModifyMenu) ~= "function"
        or not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end
    EventRegistry:RegisterCallback("OnQuestBlockHeader.OnEnter", onQuestHover)
    Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", populateMenu)
    registered = true
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    register()
    init:UnregisterAllEvents()
end)

ns.ProgressShare = { Send = sendProgress, Register = register }
