-- Independent manually curated NPC targeting macro (WoW Forever).
-- Only explicit menu clicks mutate the per-character FIFO; no polling.
local _, ns = ...
local NAME, LIMIT = "TQH_Manual", 255
local MACRO_ICON = "Ability_Hunter_SniperShot"
local macroIconApplied = false
local PREFIX, SUFFIX = "/cleartarget", "\n/cleartarget [dead][noharm]"
local pending, registered = false, false
local function say(text)
    print("|cff73c9ffTisteltiUtils QuestHelper:|r " .. text)
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and (not issecretvalue or not issecretvalue(value)) then return value end
end
local function valid(name)
    return type(name) == "string" and name ~= "" and not name:find("[%c%[%];|]")
        and #PREFIX + #"\n/targetexact [noexists][dead][noharm] " + #name + #SUFFIX <= LIMIT
end
local function build(list)
    if #list == 0 then return "/stopmacro" end
    local body = PREFIX
    -- Most recent first, oldest first to evict. Never retain a non-listed target.
    for i = #list, 1, -1 do
        body = body .. "\n/targetexact [noexists][dead][noharm] " .. list[i]
    end
    return body .. SUFFIX
end
local function trim(list)
    while #build(list) > LIMIT do table.remove(list, 1) end
end
local function listForCharacter()
    if type(TisteltiQuestHelperCharDB) ~= "table" then TisteltiQuestHelperCharDB = {} end
    if type(TisteltiQuestHelperCharDB.manualTargets) ~= "table" then
        TisteltiQuestHelperCharDB.manualTargets = {}
    end
    return TisteltiQuestHelperCharDB.manualTargets
end
local function normalize()
    local clean, seen = {}, {}
    for _, name in ipairs(listForCharacter()) do
        if valid(name) and not seen[name] then
            clean[#clean + 1], seen[name] = name, true
        end
    end
    trim(clean)
    TisteltiQuestHelperCharDB.manualTargets = clean
    return clean
end
local function write()
    if InCombatLockdown() then pending = true; return end
    pending = false
    local list = listForCharacter()
    local body = build(list)
    local index = safe(GetMacroIndexByName, NAME) or 0
    -- Do not overwrite an account-wide macro with the same name.
    if index > 0 and index <= (MAX_ACCOUNT_MACROS or 120) then
        say("Existe una macro general llamada " .. NAME .. ". Renombrala para continuar.")
        return
    end
    if index == 0 then
        if #list == 0 then return end
        local id = safe(CreateMacro, NAME, MACRO_ICON, body, true)
        if not id or id == 0 then
            say("No puedo crear " .. NAME .. ": comprueba el espacio de macros personales.")
        else
            macroIconApplied = true
            say("Macro personal creada: " .. NAME .. ". Arrastrala a tu barra.")
        end
    elseif not macroIconApplied or safe(GetMacroBody, index) ~= body then
        local ok = pcall(EditMacro, index, NAME, MACRO_ICON, body, true)
        if ok and safe(GetMacroBody, index) == body then macroIconApplied = true
        else say("No se pudo actualizar " .. NAME .. ".") end
    end
end
local function add(name)
    if not valid(name) then return false end
    local list = listForCharacter()
    for _, saved in ipairs(list) do
        if saved == name then say("Ya guardado: " .. name); write(); return false end
    end
    list[#list + 1] = name
    local count = #list
    trim(list)
    say("Guardado: " .. name .. " (" .. #list .. " NPC"
        .. (count > #list and ", " .. (count - #list) .. " antiguos retirados" or "") .. ").")
    write()
    if pending then say("Macro pendiente hasta salir de combate.") end
    return true
end
local function remove(name)
    local list = listForCharacter()
    for i, saved in ipairs(list) do
        if saved == name then
            table.remove(list, i)
            write()
            say("Eliminado: " .. name)
            return true
        end
    end
    say("Ese NPC no esta guardado.")
    return false
end
local function clear()
    listForCharacter()
    TisteltiQuestHelperCharDB.manualTargets = {}
    write()
    say("Objetivos manuales vaciados.")
end
-- Resolve unit only on the user's click, never during native menu generation.
-- Do not mutate Blizzard menu tables, hooks, target frames or protected actions.
local function enemyName(context, fallback)
    local ok, name = pcall(function()
        local unit = context and context.unit
        if issecretvalue and issecretvalue(unit) then return nil end
        if unit == nil then unit = fallback end
        if type(unit) ~= "string" or unit == "" then return nil end
        if safe(UnitExists, unit) ~= true or safe(UnitIsPlayer, unit) ~= false
            or safe(UnitCanAttack, "player", unit) ~= true then return nil end
        local value = safe(UnitName, unit)
        if valid(value) then return value end
    end)
    if ok then return name end
end
local function menu(root, context, fallback)
    if not root or type(root.CreateButton) ~= "function" then return end
    root:CreateDivider()
    local sub = root:CreateButton("QuestHelper: objetivos manuales")
    sub:CreateButton("Anadir a macro manual", function()
        local name = enemyName(context, fallback)
        if name then add(name) else say("Selecciona un NPC enemigo valido.") end
    end)
    sub:CreateButton("Eliminar de macro manual", function()
        local name = enemyName(context, fallback)
        if name then remove(name) else say("Selecciona un NPC enemigo valido.") end
    end)
    sub:CreateButton("Vaciar macro manual", clear)
end
local function register()
    if registered then return end
    if not Menu or type(Menu.ModifyMenu) ~= "function" then
        say("Menu nativo no disponible; usa /tqhmanual add con el NPC seleccionado.")
        return
    end
    Menu.ModifyMenu("MENU_UNIT_ENEMY", function(_, root, context) menu(root, context, "target") end)
    Menu.ModifyMenu("MENU_UNIT_TARGET", function(_, root, context) menu(root, context, "target") end)
    Menu.ModifyMenu("MENU_UNIT_FOCUS", function(_, root, context) menu(root, context, "focus") end)
    registered = true
end
-- Slash commands also serve as a fallback if a client uses a different menu tag.
SLASH_TQHMANUAL1 = "/tqhmanual"
SlashCmdList.TQHMANUAL = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)")
    if cmd == "clear" then clear()
    elseif cmd == "add" or cmd == "remove" then
        local name = enemyName(nil, "target")
        if not name then say("Selecciona un NPC enemigo valido."); return end
        if cmd == "add" then add(name) else remove(name) end
    elseif cmd == "sync" then write()
    else
        local list = listForCharacter()
        say(#list == 0 and "Sin objetivos manuales." or table.concat(list, ", "))
        say("/tqhmanual add | remove | clear | sync")
    end
end
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        normalize()
        register()
        write()
        frame:UnregisterEvent("PLAYER_LOGIN")
    elseif pending then write() end
end)
ns.ManualTargets = { Add = add, Remove = remove, Clear = clear, Build = build, Register = register }
