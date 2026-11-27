-- Orden visual del rastreador nativo. No modifica las misiones seguidas.
-- Usa la lista que Blizzard ya enumera, sin RemoveQuestWatch/AddQuestWatch.
-- Funciona con agrupacion por zonas, busqueda y paginacion.
local addonName, ns = ...
local Q = ns.QuestState and ns.QuestState.API or C_QuestLog
local Sort = {}
ns.TrackerSort = Sort

local modes = {
    native = true, level_asc = true, level_desc = true, zone = true,
    zone_level_asc = true, zone_level_desc = true, name = true,
}
local function readable(v)
    return v ~= nil and (not issecretvalue or not issecretvalue(v))
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end
local accents = { ["Á"]="á", ["É"]="é", ["Í"]="í", ["Ó"]="ó", ["Ú"]="ú", ["Ü"]="ü", ["Ñ"]="ñ" }
local function foldName(name)
    if type(name) ~= "string" then return "" end
    name = string.lower(name)
    for upper, lower in pairs(accents) do name = name:gsub(upper, lower) end
    return name
end
function Sort.Mode()
    local settings = ns.Config and ns.Config.Settings and ns.Config.Settings()
    local selected = settings and settings.trackerSortMode
    return modes[selected] and selected or "native"
end
function Sort.IsActive()
    return Sort.Mode() ~= "native"
end
function Sort.NeedsZone()
    local mode = Sort.Mode()
    return mode == "zone" or mode == "zone_level_asc" or mode == "zone_level_desc"
end
local function difficulty(id)
    local level = safe(Q and Q.GetQuestDifficultyLevel, id)
    if type(level) == "number" then return level end
    local index = safe(Q and Q.GetLogIndexForQuestID, id)
    if type(index) == "number" and index > 0 then
        local info = safe(Q and Q.GetInfo, index)
        if type(info) == "table" and readable(info.difficultyLevel)
            and type(info.difficultyLevel) == "number" then
            return info.difficultyLevel
        end
    end
    return nil
end
-- Al aplicar/quitar el filtro cambia el orden interno de las watches.
-- Un nombre leído previamente nunca debe perderse durante ese intercambio.
local titleCache = {}
local function title(id, quest)
    local name = safe(Q and Q.GetTitleForQuestID, id)
    if type(name) ~= "string" or name == "" then
        local index = safe(Q and Q.GetLogIndexForQuestID, id)
        if type(index) == "number" and index > 0 then
            local info = safe(Q.GetInfo, index)
            if type(info) == "table" and readable(info.questID) and info.questID == id
                and readable(info.title) and type(info.title) == "string" then
                name = info.title
            end
        end
    end
    if type(name) ~= "string" or name == "" then
        name = quest and readable(quest.title) and quest.title or nil
    end
    if type(name) == "string" and name ~= "" then
        titleCache[id] = foldName(name)
    end
    return titleCache[id] or ""
end

-- El modo Nativo conserva el orden original si las zonas estan desactivadas.
-- Con zonas, siempre ordena ALFABETICAMENTE las zonas; despues aplica el
-- criterio del usuario dentro de cada zona. Igualdad => orden nativo estable.
-- Metadatos ausentes => al final y sin perder ni ocultar la mision.
function Sort.Order(entries, grouped)
    local mode = Sort.Mode()
    if mode == "native" and not grouped then return end
    local byZone = grouped or Sort.NeedsZone()
    local byLevel = (grouped and (mode == "native" or mode == "zone"))
        or mode == "level_asc" or mode == "level_desc"
        or mode == "zone_level_asc" or mode == "zone_level_desc"
    local descending = mode == "level_desc" or mode == "zone_level_desc"
    -- Criterio secundario SIEMPRE por nombre, independientemente del modo
    -- seleccionado, si existe agrupación o clasificación visual por nivel.
    -- Antes zone_level_asc ordenaba los empates por la watch list mutable.
    local byName = mode == "name" or byLevel or byZone
    for i, entry in ipairs(entries) do
        entry.sortOriginal = entry.original or i
        if byZone then
            local zone = entry.zone or "Otras misiones"
            entry.sortZoneMissing = (zone == "Otras misiones")
            entry.sortZone = foldName(zone)
        end
        if byLevel then
            entry.sortLevel = type(entry.id) == "number" and difficulty(entry.id) or nil
        end
        if byName then
            entry.sortTitle = type(entry.id) == "number" and title(entry.id, entry.quest) or ""
        end
    end
    table.sort(entries, function(a,b)
        if byZone then
            if a.sortZoneMissing ~= b.sortZoneMissing then return not a.sortZoneMissing end
            if a.sortZone ~= b.sortZone then return a.sortZone < b.sortZone end
        end
        if byLevel then
            if a.sortLevel == nil and b.sortLevel ~= nil then return false end
            if b.sortLevel == nil and a.sortLevel ~= nil then return true end
            if a.sortLevel ~= b.sortLevel then
                return descending and a.sortLevel > b.sortLevel or (not descending and a.sortLevel < b.sortLevel)
            end
        end
        if byName then
            if a.sortTitle == "" and b.sortTitle ~= "" then return false end
            if b.sortTitle == "" and a.sortTitle ~= "" then return true end
            if a.sortTitle ~= b.sortTitle then return a.sortTitle < b.sortTitle end
        end
        return a.sortOriginal < b.sortOriginal
    end)
    for _, entry in ipairs(entries) do
        entry.sortOriginal, entry.sortZoneMissing, entry.sortZone = nil, nil, nil
        entry.sortLevel, entry.sortTitle = nil, nil
    end
end
function Sort.Initialize() end -- Sin eventos y sin alterar la watch list.
function Sort.RefreshSettings() end -- El tracker visual procesa este cambio.
function Sort.Debug()
    print("|cff73c9ffTisteltiUtils QuestHelper:|r Orden visual=" .. Sort.Mode() ..
        "; sin RemoveQuestWatch/AddQuestWatch")
end
