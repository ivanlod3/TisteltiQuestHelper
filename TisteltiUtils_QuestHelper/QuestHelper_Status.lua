-- Estado de entrega compartido por filtro, rastreador y resaltados.
-- La información incompleta del diario nunca debe transformar un objetivo
-- explícitamente pendiente en una misión lista para entregar.
local addonName, ns = ...
local Q = ns.QuestState and ns.QuestState.API or C_QuestLog
local Status = {}
ns.QuestStatus = Status

local function readable(value)
    return value ~= nil and (not issecretvalue or not issecretvalue(value))
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok and readable(result) then return result end
end
local function getInfo(id)
    local index = safe(Q and Q.GetLogIndexForQuestID, id)
    if type(index) ~= "number" or index <= 0 then return nil end
    local info = safe(Q.GetInfo, index)
    if type(info) == "table" and readable(info.questID) and info.questID == id then
        return info
    end
end

local function stillPending(objective)
    if type(objective) ~= "table" then return false end
    -- "done" lo usa nuestra vista auxiliar; "finished" lo entrega Blizzard.
    if readable(objective.done) and objective.done == false then return true end
    if readable(objective.finished) and objective.finished == false then return true end
    local done = readable(objective.numFulfilled) and objective.numFulfilled or nil
    local required = readable(objective.numRequired) and objective.numRequired or nil
    if type(done) == "number" and type(required) == "number"
        and required > 0 and done < required then return true end
    -- En Forever algunos objetivos enseñan 0/1 mientras un flag de la API
    -- permanece transitoriamente en true tras cambiar el seguimiento.
    -- Solo leer un contador numérico al final, nunca interpretar otro texto.
    if readable(objective.text) and type(objective.text) == "string" then
        local a,b = objective.text:match("(%d+)%s*/%s*(%d+)%s*$")
        if a and b and tonumber(b) > 0 and tonumber(a) < tonumber(b) then
            return true
        end
    end
    return false
end

function Status.IsReady(id, info, objectives)
    if type(id) ~= "number" or id <= 0 then return false end
    if type(info) ~= "table" then info = getInfo(id) end
    local stronglyReady = safe(Q and Q.ReadyForTurnIn, id) == true
        or safe(Q and Q.IsQuestReadyForTurnIn, id) == true
        or (info and readable(info.readyForTurnIn) and info.readyForTurnIn == true)
    local weaklyReady = (info and readable(info.isComplete) and info.isComplete == true)
        or safe(Q and Q.IsComplete, id) == true
    if not stronglyReady and not weaklyReady then return false end
    -- Una marca genérica de completado sin objetivos legibles no basta: ese
    -- vacío transitorio es habitual justo al cambiar el seguimiento.
    if objectives == nil then objectives = safe(Q and Q.GetQuestObjectives, id) end
    if type(objectives) ~= "table" then return stronglyReady == true end
    -- Los objetivos explícitamente pendientes tienen prioridad sobre
    -- cualquier flag de completado transitoriamente incoherente.
    for _, objective in ipairs(objectives) do
        if stillPending(objective) then return false end
    end
    return true
end
