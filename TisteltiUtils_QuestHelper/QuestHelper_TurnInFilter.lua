-- Filtro reversible de entregables para el rastreador NATIVO de WoW Forever.
-- No crea filas ni paneles: cambia temporalmente C_QuestLog watches.
-- La instantánea ORIGINAL se persiste por personaje ANTES de tocar el seguimiento.
-- Las acciones se omiten durante combate/auras secretas. Sin hooks de escritura.
local addonName, ns = ...
local Q = C_QuestLog
local Filter = {}
ns.TurnInFilter = Filter

local button, buttonIcon, initialized, enteredWorld = nil, nil, false, false
local buttonAnchor = nil
local active, scheduled, working, deferred, warned = false, false, false, false, false
local journalUpdated = false
local events = CreateFrame("Frame")
-- El encabezado se puede crear después de ADDON_LOADED/PLAYER_ENTERING_WORLD.
-- Reintentos limitados, nunca OnUpdate ni un sondeo permanente.
local buttonRetryPending, buttonRetryRemaining = false, 0
local MAX_NATIVE_WATCHES = 25 -- Forever 1.60.1; rechazar antes que mostrar un filtro parcial.

local function readable(v)
    return v ~= nil and (not issecretvalue or not issecretvalue(v))
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end
local function permitted()
    if type(InCombatLockdown) == "function" and safe(InCombatLockdown) ~= false then return false end
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if type(fn) == "function" and safe(fn) ~= false then return false end
    return true
end
local function notifyError(message)
    if not warned then
        warned = true
        print("|cff73c9ffTisteltiUtils QuestHelper:|r " .. message)
    end
end
local function state()
    if type(TisteltiQuestHelperCharDB) ~= "table" then TisteltiQuestHelperCharDB = {} end
    local data = TisteltiQuestHelperCharDB.turnInWatchSwap
    if type(data) == "table" and data.version == 1
        and type(data.original) == "table"
        and (data.mode == "active" or data.mode == "restoring") then
        return data
    end
end
local function saveState(data)
    if type(TisteltiQuestHelperCharDB) ~= "table" then TisteltiQuestHelperCharDB = {} end
    TisteltiQuestHelperCharDB.turnInWatchSwap = data
end
local function validID(id)
    return readable(id) and type(id) == "number"
        and id > 0 and id == math.floor(id)
end
local function readWatches()
    if not Q or type(Q.GetNumQuestWatches) ~= "function"
        or type(Q.GetQuestIDForQuestWatchIndex) ~= "function" then return nil end
    local count = safe(Q.GetNumQuestWatches)
    if type(count) ~= "number" or count < 0 or count > 100 then return nil end
    local watched, seen = {}, {}
    for i = 1, count do
        local id = safe(Q.GetQuestIDForQuestWatchIndex, i)
        if not validID(id) then return nil end -- no hacer una copia parcial
        if not seen[id] then watched[#watched + 1] = id; seen[id] = true end
    end
    if safe(Q.GetNumQuestWatches) ~= count then return nil end
    return watched
end
local function isReady(id, info)
    return ns.QuestStatus and ns.QuestStatus.IsReady(id, info) == true
end
local function scanJournal()
    if ns.Perf then ns.Perf.Count("scan.filter.fresh") end
    if not permitted() or not Q or type(Q.GetInfo) ~= "function" then return nil end
    local count = safe(Q.GetNumQuestLogEntries)
    if type(count) ~= "number" or count < 0 or count > 500 then return nil end
    local ready, existing, seen = {}, {}, {}
    for i = 1, count do
        local info = safe(Q.GetInfo, i)
        if type(info) ~= "table" then return nil end -- diario parcial / secreto
        if not readable(info.isHeader) or type(info.isHeader) ~= "boolean" then return nil end
        if info.isHeader ~= true then
            local id = readable(info.questID) and info.questID or nil
            if not validID(id) or existing[id] then return nil end
            if validID(id) then
                existing[id] = true
                if not seen[id] and isReady(id, info) then
                    seen[id] = true
                    ready[#ready + 1] = id
                end
            end
        end
    end
    if safe(Q.GetNumQuestLogEntries) ~= count then return nil end
    return ready, existing, count
end
-- Solo los IDs que todavía figuran en el diario. No se restauran misiones
-- abandonadas, entregadas o inexistentes, ni índices del diario obsoletos.
local function validSaved(original, existing, journalCount)
    if type(original) ~= "table" then return nil end
    local valid, seen = {}, {}
    for i = 1, #original do
        local id = original[i]
        if not validID(id) then return nil end -- instantánea dañada: no tocar el seguimiento
        if not seen[id] then
            seen[id] = true
            local exists = existing[id] == true
            if not exists and type(Q.GetLogIndexForQuestID) == "function" then
                local index = safe(Q.GetLogIndexForQuestID, id)
                if type(index) == "number" and index > 0 then
                    local info = safe(Q.GetInfo, index)
                    -- Un índice existente con datos incompletos no demuestra
                    -- que la misión haya desaparecido: conservar la instantánea.
                    if type(info) ~= "table" or not readable(info.questID)
                        or info.questID ~= id then return nil end
                    exists = true
                end
            end
            if exists then valid[#valid + 1] = id end
        end
    end
    -- Si el diario aún no ha cargado, NO interpretar todas las misiones como borradas.
    if journalCount == 0 and #original > 0 then return nil end
    return valid
end
local function equalsSet(a, b)
    if #a ~= #b then return false end
    local wanted = {}
    for _, id in ipairs(b) do wanted[id] = true end
    for _, id in ipairs(a) do if not wanted[id] then return false end end
    return true
end
local function hasID(watches, id)
    for _, watchID in ipairs(watches) do if watchID == id then return true end end
    return false
end
-- Verificar el estado real DESPUÉS de cada llamada. pcall(true) no implica
-- que Forever haya aceptado la operación (límite de slots, restricciones, etc.).
local function applyWatches(wanted)
    if not permitted() or not Q or type(Q.AddQuestWatch) ~= "function"
        or type(Q.RemoveQuestWatch) ~= "function" then return false end
    if #wanted > MAX_NATIVE_WATCHES then return false end
    local current = readWatches()
    if not current then return false end
    local desired = {}
    for _, id in ipairs(wanted) do desired[id] = true end
    for _, id in ipairs(current) do
        if not desired[id] then
            if not permitted() then return false end
            pcall(Q.RemoveQuestWatch, id)
            current = readWatches()
            if not current or hasID(current, id) then return false end
        end
    end
    for _, id in ipairs(wanted) do
        if not hasID(current, id) then
            if not permitted() then return false end
            pcall(Q.AddQuestWatch, id)
            current = readWatches()
            if not current or not hasID(current, id) then return false end
        end
    end
    return permitted() and equalsSet(current, wanted)
end
local function updateButton()
    if not button or not buttonIcon or not permitted() then return end
    -- El mismo tamaño y estilo sobrio que la lupa; sin UIPanelButtonTemplate.
    if active then
        buttonIcon:SetTextColor(1, 0.82, 0) -- gold, same accent as zone arrows
    else
        buttonIcon:SetTextColor(0.85, 0.85, 0.85) -- neutral while inactive/restoring
    end
    button:SetAlpha(active and 1 or 0.85)
end

local function restoreOriginal(data, existing, journalCount)
    local desired = validSaved(data.original, existing, journalCount)
    if not desired then return false end
    local done = applyWatches(desired)
    if done then
        saveState(nil)
        active, warned, deferred = false, false, false
        updateButton()
    end
    return done
end

local function process()
    if working or not enteredWorld then return end
    local data = state()
    if not data then return end
    if not permitted() then deferred = true; return end
    working = true
    local beforeWatches = readWatches()
    local ready, existing, logCount = scanJournal()
    if not ready or (logCount == 0 and #data.original > 0) then
        deferred = true
        working = false
        return
    end
    local ok
    if data.mode == "restoring" then
        ok = restoreOriginal(data, existing, logCount)
        if not ok then notifyError("Restauración pendiente: se reintentará al actualizarse el diario o salir de combate.") end
    else
        if #ready == 0 then
            -- Sin watches, Blizzard oculta también la cabecera y el botón de
            -- salida. Si se entrega la última misión (o deja de estar lista),
            -- recuperar la selección guardada en lugar de aplicar un vacío.
            data.mode = "restoring"
            active = false
            updateButton()
            ok = restoreOriginal(data, existing, logCount)
            if ok then
                print("|cff73c9ffTisteltiUtils QuestHelper:|r No hay misiones listas para entregar. Se ha recuperado el seguimiento anterior.")
            else
                deferred = true
                notifyError("No quedan misiones listas para entregar. Restauración pendiente del seguimiento anterior.")
            end
        elseif #ready > MAX_NATIVE_WATCHES then
            -- No mostrar una selección incompleta ni perder la copia original.
            data.mode = "restoring"
            active = false
            updateButton()
            restoreOriginal(data, existing, logCount)
            notifyError("Hay más de 25 misiones entregables: filtro cancelado para no omitir ninguna.")
        else
            ok = applyWatches(ready)
            if not ok then
                -- Si la API rechaza algo, recuperar SIEMPRE la selección guardada.
                data.mode = "restoring"
                active = false
                updateButton()
                restoreOriginal(data, existing, logCount)
                notifyError("El cliente ha rechazado un cambio de seguimiento. Recuperando el seguimiento original.")
            else
                warned, deferred = false, false
            end
        end
    end
    working = false
    -- Durante el swap no tocar bloques que Blizzard está reciclando.
    -- Solo reconstruir si realmente cambió el conjunto de watches: un
    -- QUEST_LOG_UPDATE ordinario no debe reiniciar el scroll activo.
    local afterWatches = readWatches()
    if beforeWatches and afterWatches and not equalsSet(beforeWatches, afterWatches)
        and ns.TrackerZones and ns.TrackerZones.RefreshAfterWatchSwap then
        ns.TrackerZones.RefreshAfterWatchSwap()
    end
end
local function schedule(delay)
    if scheduled or not enteredWorld then return end
    scheduled = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay or 0.12, function()
            scheduled = false
            process()
        end)
    else
        scheduled = false
        process()
    end
end

local function toggle()
    local data = state()
    if data and data.mode == "restoring" then
        schedule(0)
        return
    end
    if data and data.mode == "active" then
        -- No cambiar el original aunque el usuario haya tocado el seguimiento.
        data.mode = "restoring" -- persistir incluso si combat/secret impide operar ahora
        active = false
        updateButton()
        schedule(0)
        return
    end
    if not enteredWorld or not permitted() then return end
    if not Q or type(Q.AddQuestWatch) ~= "function"
        or type(Q.RemoveQuestWatch) ~= "function" then
        notifyError("Este cliente no admite las API de seguimiento requeridas.")
        return
    end
    local snapshot = readWatches()
    local ready, _, logCount = scanJournal()
    if not snapshot or not ready or (logCount == 0 and #snapshot > 0) then
        notifyError("No se ha podido leer íntegro el diario o el seguimiento; no se ha cambiado nada.")
        return
    end
    if #ready == 0 then
        -- No guardar un swap ni retirar watches: se perdería la cabecera que
        -- contiene el propio botón para desactivar el filtro.
        print("|cff73c9ffTisteltiUtils QuestHelper:|r No hay misiones listas para entregar. Se mantiene tu seguimiento.")
        return
    end
    if #ready > MAX_NATIVE_WATCHES then
        notifyError("Hay más de 25 misiones entregables; no se activa un filtro incompleto.")
        return
    end
    -- Persistir la copia ANTES de la primera escritura en Blizzard.
    saveState({version = 1, mode = "active", original = snapshot})
    active, warned = true, false
    updateButton()
    process()
end

local function makeButton()
    local tracker = _G.QuestObjectiveTracker
    local header = tracker and tracker.Header
    local minimize = header and header.MinimizeButton
    -- La cabecera puede existir antes que MinimizeButton o ContentsFrame.
    if not header then return false end
    local function position(btn)
        btn:ClearAllPoints()
        if minimize then
            btn:SetPoint("RIGHT", minimize, "LEFT", -6, 0)
        else
            btn:SetPoint("RIGHT", header, "RIGHT", -29, 0)
        end
    end
    if button then
        -- Do not re-anchor on every native layout; avoid spurious UI updates.
        local moved = false
        if type(button.GetParent) == "function" and button:GetParent() ~= header
            and type(button.SetParent) == "function" then
            button:SetParent(header)
            moved = true
        end
        local anchor = minimize or header
        if moved or buttonAnchor ~= anchor then
            position(button)
            buttonAnchor = anchor
            if ns.TrackerZones and ns.TrackerZones.PositionSearchBefore then
                ns.TrackerZones.PositionSearchBefore(button)
            end
        end
        button:Show()
        updateButton()
        return true
    end
    local btn = CreateFrame("Button", nil, header)
    btn:SetSize(20, 20)
    position(btn)
    buttonAnchor = minimize or header
    btn:RegisterForClicks("LeftButtonUp")
    local glyph = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    glyph:SetPoint("CENTER", btn, "CENTER", 0, 0)
    glyph:SetText("?")
    btn:SetScript("OnClick", toggle)
    btn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local data = state()
        if data and data.mode == "restoring" then
            GameTooltip:SetText("Restauración de seguimiento pendiente")
            GameTooltip:AddLine("Se recuperarán las misiones originales que todavía existan.", 1, 1, 1, true)
        elseif active then
            GameTooltip:SetText("Restaurar seguimiento original")
            GameTooltip:AddLine("Los cambios de seguimiento hechos durante el filtro se descartarán.", 1, 1, 1, true)
        else
            GameTooltip:SetText("Mostrar solo misiones listas para entregar")
            GameTooltip:AddLine("Sustituye temporalmente las misiones seguidas; guarda las anteriores.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button, buttonIcon = btn, glyph
    updateButton()
    -- Colocar la lupa a la izquierda, sin modificar la cabecera de Blizzard.
    if ns.TrackerZones and ns.TrackerZones.PositionSearchBefore then
        ns.TrackerZones.PositionSearchBefore(btn)
    end
    return true
end
local function ensureButton()
    if makeButton() then
        buttonRetryRemaining = 0
        return
    end
    -- La carga perezosa puede retrasar el tracker después de entrar al mundo.
    if buttonRetryPending or buttonRetryRemaining <= 0 then return end
    if not C_Timer or type(C_Timer.After) ~= "function" then return end
    buttonRetryPending = true
    C_Timer.After(0.5, function()
        buttonRetryPending = false
        if buttonRetryRemaining <= 0 then return end
        buttonRetryRemaining = buttonRetryRemaining - 1
        ensureButton()
    end)
end
function Filter.Toggle() toggle() end
function Filter.EnsureButton() ensureButton() end
function Filter.IsActive() return active end
function Filter.IsSwapping() return working end
function Filter.GetButton() return button end
function Filter.Scan() return scanJournal() end
function Filter.Initialize()
    if initialized then return end
    initialized = true
    -- Un /reload durante el filtro NUNCA debe perder la selección original:
    -- recuperar en lugar de reactivar automáticamente un seguimiento temporal.
    local data = state()
    if data then data.mode = "restoring" end
    active = false
    for _, name in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE",
        "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED",
        "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_REGEN_ENABLED"}) do
        events:RegisterEvent(name)
    end
    makeButton()
end
events:SetScript("OnEvent", function(_, event)
    if not initialized then return end
    if event == "PLAYER_LOGIN" then
        -- El tracker puede aparecer después del login.
        buttonRetryRemaining = 12
        ensureButton()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        enteredWorld = true
        journalUpdated = false
        buttonRetryRemaining = 12
        ensureButton()
        if state() then schedule(0.5) end -- el diario puede tardar en poblarse
        return
    end
    if not button then ensureButton() elseif event == "PLAYER_REGEN_ENABLED" then makeButton() end
    if event == "QUEST_LOG_UPDATE" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        journalUpdated = true
    end
    local data = state()
    if not data then return end
    if event == "QUEST_WATCH_LIST_CHANGED" and data.mode == "restoring" then
        -- Evitar reintentos en bucle si la API rechazó una restauración.
        return
    end
    if event == "PLAYER_REGEN_ENABLED" or event == "QUEST_LOG_UPDATE"
        or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN"
        or event == "QUEST_ACCEPTED" or event == "QUEST_WATCH_LIST_CHANGED"
        or event == "QUEST_WATCH_UPDATE" then
        schedule(0.12)
    end
end)
