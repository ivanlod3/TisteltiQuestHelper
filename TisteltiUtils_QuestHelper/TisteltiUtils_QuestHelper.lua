-- TisteltiUtils QuestHelper 0.7.9 - World of Warcraft Forever
-- Objective detection: same native quest-tooltip join as Simple Objective Icons (MIT).
-- One inspection drives nameplate sword/bag, current/required counters and character macro.
-- No fixed NPC/item names, no QuestieDB, no soft target, no OnUpdate.

local ADDON_NAME, ns = ...
local MACRO_NAME = "QuestHelper"
local MACRO_ICON = "INV_Misc_Map_01"
local macroIconApplied = false
local LEGACY_MACRO_NAME = "QuestTargetLite" -- rename in place to preserve existing action-bar slots
local MACRO_LIMIT = 255
local LINE_OBJECTIVE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8
local ICONS = { monster = "Crosshair_Attack_32", item = "Crosshair_pickup_32" }
local DISPLAY_KINDS = { "item", "monster" }
-- Kept as fallback constants; live appearance numbers come from ns.Config.
local ICON_WIDTH, ICON_HEIGHT = 20, 20
local function visualNumber(key, fallback)
    return ns.Config and ns.Config.GetNumber and ns.Config.GetNumber(key) or fallback
end
-- Two rows form a real two-column grid: the numbers share a right edge,
-- and the icon at the end of each row occupies the same logical column.
-- No extra events, timers or animation needed to maintain the layout.
local COMPACT_ICON_SIZE, COMPACT_TEXT_SIZE, ROW_SPACING = 16, 13, 0
local MULTI_TEXT_SIZE, MULTI_LINE_HEIGHT = 10, 11 -- two numbers fit beside one bag icon
-- Shared number-to-icon spacing setting in every layout. The baseline
-- single-objective offsets are preserved at the default value (5px),
-- but changing the setting moves numbers in both single and stacked views.
-- The bag atlas has more transparent pixels than the diagonal sword.
local COMPACT_COLUMN_GAP = 5
local COMPACT_SWORD_INSET = 2 -- stacked sword only; keeps its visible tip near the bag's right edge
-- The sword atlas needs less overlap than the bag to look equally spaced.
local ICON_TEXT_OFFSET = { monster = 0, item = 3 }
local PLATE_GAP = 6 -- from the actual health bar, not the wider nameplate frame
local eventFrame = CreateFrame("Frame")
local objectivesByText = {} -- exact journal objective string -> list of active objective entries
local activeByKey = {}      -- questID:index -> active objective
local activeCount = 0
local visiblePlates = {}   -- nameplate token -> true
local visibleQuest = {}    -- nameplate token -> { name, monster, item }; only living objectives
local lastSeen = {}        -- NPC name -> timestamp, session only
local refreshPending, macroPending, combatPending = false, false, false
local stats = { tooltips = 0, hits = 0, learned = 0, macroNames = 0, omitted = 0, macroKill = 0, macroLoot = 0, availableKill = 0, availableLoot = 0 }
local function feature(key)
    -- Settings live in the announcement module and initialize on ADDON_LOADED.
    return not ns.Config or not ns.Config.Get or ns.Config.Get(key)
end
local function npcEnabled()
    return feature("nameplateIcons") or feature("autoMacro")
end
local function anyObjectivesNeeded()
    return npcEnabled() or feature("markBags") or feature("markBaganator") or feature("itemTooltips")
end

local function readable(value)
    return value ~= nil and (not issecretvalue or not issecretvalue(value))
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local success, value = pcall(fn, ...)
    if success and readable(value) then return value end
end

local function out(message)
    print("|cff73c9ffTisteltiUtils QuestHelper:|r " .. message)
end

local function learnedCache()
    if type(FQTL4_Seen) ~= "table" then FQTL4_Seen = {} end
    return FQTL4_Seen
end

local function keyOf(questID, index)
    return tostring(questID) .. ":" .. tostring(index)
end

local function progress(objective)
    -- Native numbers take priority; they are independent of the client language.
    if readable(objective.numRequired) and readable(objective.numFulfilled)
        and type(objective.numRequired) == "number" and type(objective.numFulfilled) == "number" then
        local total = math.max(0, math.floor(objective.numRequired))
        local done = math.max(0, math.floor(objective.numFulfilled))
        return tostring(done) .. "/" .. tostring(total), math.max(0, total - done)
    end
    -- Locale-agnostic fallback when the client only exposes the objective line.
    if readable(objective.text) and type(objective.text) == "string" then
        local done, total = objective.text:match("(%d+)%s*/%s*(%d+)")
        if done and total then
            return done .. "/" .. total, math.max(0, tonumber(total) - tonumber(done))
        end
    end
    return nil, nil
end

local function rebuildObjectives()
    wipe(objectivesByText)
    wipe(activeByKey)
    activeCount = 0
    -- Only the inventory may retain completed item objectives until turn-in.
    -- NPC nameplates and the macro still see ONLY pending objectives.
    local inventoryUnknown, inventoryCompleted = {}, {}
    local inventoryEnabled = feature("markBags") or feature("markBaganator") or feature("itemTooltips")
    local inventoryQuestIDs = {} -- no second journal scan in the inventory module

    local logCount = safe(C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or 0
    if type(logCount) ~= "number" then logCount = 0 end
    for i = 1, logCount do
        local quest = safe(C_QuestLog and C_QuestLog.GetInfo, i)
        if type(quest) == "table" and readable(quest.isHeader) and not quest.isHeader
            and readable(quest.questID) and type(quest.questID) == "number" then
            local questID = quest.questID
            if inventoryEnabled then inventoryQuestIDs[questID] = true end
            local questComplete = safe(C_QuestLog and C_QuestLog.IsComplete, questID) == true
            local list = safe(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
            if type(list) == "table" then
                for index, obj in ipairs(list) do
                    if type(obj) == "table" and readable(obj.text)
                        and type(obj.text) == "string" and obj.text ~= "" then
                        local kind = readable(obj.type) and obj.type or nil
                        local count, left = progress(obj)
                        local finished = questComplete or (readable(obj.finished) and obj.finished == true)
                            or (left ~= nil and left == 0)
                        local key = keyOf(questID, index)
                        -- Completed items must stay marked (e.g. 6/6) while the
                        -- quest is still in the log, without becoming macro targets.
                        if inventoryEnabled and finished
                            and (kind == "item" or kind == nil or kind == "") then
                            inventoryCompleted[key] = { key = key, questID = questID,
                                kind = kind == "item" and "item" or "unknown",
                                completed = true, count = count, left = left, text = obj.text }
                        end
                        if not questComplete and not finished then
                            if kind == nil or kind == "" then
                                inventoryUnknown[key] = { key = key, questID = questID,
                                    kind = "unknown", count = count, left = left, text = obj.text }
                            elseif (kind == "monster" or kind == "item")
                                and readable(obj.finished) and obj.finished == false then
                                local entry = { key = key, questID = questID, kind = kind,
                                    count = count, left = left, text = obj.text }
                                activeByKey[key] = entry
                                activeCount = activeCount + 1
                                local entries = objectivesByText[obj.text]
                                if not entries then entries = {}; objectivesByText[obj.text] = entries end
                                entries[#entries + 1] = entry
                            end
                        end
                    end
                end
            end
        end
    end

    -- Never retain a completed mission's NPCs for plates or /targetexact.
    for key in pairs(learnedCache()) do
        if not activeByKey[key] then FQTL4_Seen[key] = nil end
    end
    -- Single journal traversal: Baganator and tooltips share the same snapshot.
    if ns and ns.QuestItems and ns.QuestItems.ObjectivesChanged then
        ns.QuestItems.ObjectivesChanged(activeByKey, inventoryUnknown, inventoryCompleted, inventoryQuestIDs)
    end
end

-- The native tracker marks its focused quest as super-tracked. A quest selected
-- in the journal is a secondary priority when it differs from that focus.
-- Never change either selection: these are read-only API calls.
local function macroQuestPriorities()
    local superTracked = safe(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID)
    local selected = safe(C_QuestLog and C_QuestLog.GetSelectedQuest)
    if type(superTracked) ~= "number" or superTracked <= 0 then superTracked = nil end
    if type(selected) ~= "number" or selected <= 0 or selected == superTracked then selected = nil end
    return superTracked, selected
end

local function buildMacro()
    -- Use the same learned NPCs for BOTH quest categories; neither one may
    -- monopolize the limited 255-character WoW macro. The focused quest goes
    -- first, then the journal selection and finally all other learned NPCs.
    local focusedQuest, selectedQuest = macroQuestPriorities()
    local byName = {}
    for key, entry in pairs(activeByKey) do
        local found = learnedCache()[key]
        if type(found) == "table" then
            for name in pairs(found) do
                if type(name) == "string" and name ~= "" and not name:find("[\r\n]") then
                    local npc = byName[name]
                    if not npc then
                        npc = { name = name, monster = false, item = false, tier = 0 }
                        byName[name] = npc
                    end
                    npc[entry.kind] = true
                    if entry.questID == focusedQuest then
                        npc.tier = 2
                    elseif entry.questID == selectedQuest and npc.tier < 1 then
                        npc.tier = 1
                    end
                end
            end
        end
    end

    -- Recently seen *living* quest nameplates take precedence over old names.
    -- The set is refreshed only by nameplate/quest events (no OnUpdate).
    local nearby = {}
    for unit, npc in pairs(visibleQuest) do
        if visiblePlates[unit] then nearby[npc.name] = true end
    end
    local tiers = {
        [2] = { monster = {}, item = {} }, -- native tracker focus
        [1] = { monster = {}, item = {} }, -- selected in quest journal
        [0] = { monster = {}, item = {} }, -- other missions
    }
    local total, allKills, allLoot = 0, 0, 0
    for name, npc in pairs(byName) do
        total = total + 1
        local group = tiers[npc.tier]
        if npc.monster then
            group.monster[#group.monster + 1] = name
            allKills = allKills + 1
        end
        if npc.item then
            group.item[#group.item + 1] = name
            allLoot = allLoot + 1
        end
    end
    local function byPriority(a, b)
        local aVisible, bVisible = nearby[a] and 1 or 0, nearby[b] and 1 or 0
        if aVisible ~= bVisible then return aVisible > bVisible end
        local aa, bb = lastSeen[a] or 0, lastSeen[b] or 0
        if aa ~= bb then return aa > bb end
        return a < b
    end
    for tier = 2, 0, -1 do
        table.sort(tiers[tier].monster, byPriority)
        table.sort(tiers[tier].item, byPriority)
    end

    -- A living target is kept; a corpse is cleared at the end. In WoW macros,
    -- /targetexact can only check names, not whether an NPC has a quest icon.
    local body, inserted = "/cleartarget [dead][noharm]", 0
    local deadCleanup = "\n/cleartarget [dead]"
    local included = {}
    local includedKills, includedLoot = 0, 0
    local function append(name)
        if included[name] then return end
        local line = "\n/targetexact [noexists][dead] " .. name
        if #body + #line + #deadCleanup > MACRO_LIMIT then return end
        body = body .. line
        inserted = inserted + 1
        included[name] = true
        local npc = byName[name]
        if npc.monster then includedKills = includedKills + 1 end
        if npc.item then includedLoot = includedLoot + 1 end
    end

    -- Finish all names belonging to the focused mission BEFORE adding any
    -- other mission. Within a tier keep the old kill/loot alternation, which
    -- prevents either objective type from filling the whole macro by itself.
    for tier = 2, 0, -1 do
        local kills, loot = tiers[tier].monster, tiers[tier].item
        local ki, li = 1, 1
        while ki <= #kills or li <= #loot do
            if ki <= #kills then append(kills[ki]); ki = ki + 1 end
            if li <= #loot then append(loot[li]); li = li + 1 end
        end
    end
    stats.macroNames = inserted
    stats.omitted = total - inserted
    stats.macroKill, stats.macroLoot = includedKills, includedLoot
    stats.availableKill, stats.availableLoot = allKills, allLoot
    return inserted > 0 and (body .. deadCleanup) or "/stopmacro"
end

local function writeMacro()
    if not feature("autoMacro") then return end
    if InCombatLockdown() then combatPending = true; return end
    local body = buildMacro()
    local index = safe(GetMacroIndexByName, MACRO_NAME) or 0
    local legacy = false
    if index == 0 then
        index = safe(GetMacroIndexByName, LEGACY_MACRO_NAME) or 0
        legacy = index ~= 0
    end
    if index == 0 then
        local success, result = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, body, true)
        if not success or not result or result == 0 then
            out("No puedo crear la macro (¿limite de macros personales alcanzado?).")
        else
            macroIconApplied = true
        end
    elseif legacy or not macroIconApplied or safe(GetMacroBody, index) ~= body then
        -- Edit the existing macro ID so action-bar placements keep working.
        local success = pcall(EditMacro, index, MACRO_NAME, MACRO_ICON, body, true)
        if success then macroIconApplied = true
        else out("No puedo editar la macro. Intentalo fuera de combate.") end
    end
end

local function requestMacro()
    if not feature("autoMacro") then return end
    -- Macro edits are protected during combat. Defer just one rebuild.
    if InCombatLockdown() then combatPending = true; return end
    if macroPending then return end
    macroPending = true
    C_Timer.After(0.25, function()
        macroPending = false
        if feature("autoMacro") then writeMacro() end
    end)
end

local function setVisibleQuest(unit, name, monster, item)
    if not feature("autoMacro") or not visiblePlates[unit] then return end
    local old = visibleQuest[unit]
    if not name or (not monster and not item) then
        if old then
            visibleQuest[unit] = nil
            requestMacro()
        end
        return
    end
    if not old or old.name ~= name or old.monster ~= monster or old.item ~= item then
        visibleQuest[unit] = { name = name, monster = monster, item = item }
        -- Refresh even if this NPC was learned in a previous session: that
        -- name could have been excluded from the old macro by the 255-char cap.
        requestMacro()
    end
end

local function ensureIcons(plate)
    if plate.FQTLVisual then return plate.FQTLVisual end
    local visuals = {}
    for index, kind in ipairs(DISPLAY_KINDS) do
        local frame = CreateFrame("Frame", nil, plate)
        frame:SetSize(ICON_WIDTH + 25, ICON_HEIGHT)
        frame:SetFrameLevel(plate:GetFrameLevel() + 5)
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetSize(ICON_WIDTH, ICON_HEIGHT)
        texture:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        texture:SetAtlas(ICONS[kind])
        local number = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        number:SetPoint("RIGHT", texture, "LEFT", ICON_TEXT_OFFSET[kind], 0)
        number:SetJustifyH("RIGHT")
        -- Always keep progress such as 5/15 on one line, even on small/scaled plates.
        if type(number.SetWordWrap) == "function" then number:SetWordWrap(false) end
        if type(number.SetNonSpaceWrap) == "function" then number:SetNonSpaceWrap(false) end
        if type(number.SetMaxLines) == "function" then number:SetMaxLines(1) end
        number:SetTextColor(1, 0.82, 0)
        local fontPath, fontSize, fontFlags = number:GetFont()
        visuals[index] = {
            kind = kind, frame = frame, texture = texture, number = number,
            numbers = { number }, oldValues = {},
            fontPath = fontPath, fontSize = fontSize, fontFlags = fontFlags,
            mode = nil, width = nil, textWidth = nil, numberWidth = nil,
            measuredWidths = {},
            anchor = nil, y = nil, height = nil,
        }
        frame:Hide()
    end
    plate.FQTLVisual = visuals
    return visuals
end

local function hidePlateIcons(plate)
    if not plate then return end
    if not plate.FQTLPreview then plate.FQTLLastQuestObjectives = nil end
    if not plate.FQTLVisual then return end
    for _, entry in ipairs(plate.FQTLVisual) do entry.frame:Hide() end
end

local function measureLabel(label, fontSize)
    -- In WoW Forever, FontString:GetUnboundedStringWidth() and GetStringWidth()
    -- can return protected (secret) numbers on nearby/unselected nameplates.
    -- Comparing, rounding or even passing such values to math.max is tainted.
    -- Progress labels are ASCII strings composed locally from journal data, so
    -- reserve ample invisible width using only the text and configured font size.
    -- The RIGHT anchor on the texture keeps the visible number-to-icon gap fixed.
    -- Recalculated only when text or appearance changes; no per-frame work.
    return math.max(32, math.ceil(#label * (fontSize or 12) * 0.85 + 12))
end

local function valuesFor(entries)
    local values, seen = {}, {}
    for _, entry in ipairs(entries) do
        if entry.key and not seen[entry.key] then
            seen[entry.key] = true
            values[#values + 1] = entry.count or "?"
        end
    end
    return values
end

local function updateCategory(entry, values, compact)
    local n = #values
    local multi = n > 1
    local mode = table.concat({compact and "small" or "normal", multi and "multi" or "single",
        visualNumber("plateIconSize", ICON_WIDTH), visualNumber("plateTextSize", 12),
        visualNumber("plateStackIconSize", COMPACT_ICON_SIZE), visualNumber("plateStackTextSize", COMPACT_TEXT_SIZE),
        visualNumber("plateMultiTextSize", MULTI_TEXT_SIZE)}, ":")
    local iconSize = compact and visualNumber("plateStackIconSize", COMPACT_ICON_SIZE)
        or visualNumber("plateIconSize", ICON_WIDTH)
    local fontSize = multi and visualNumber("plateMultiTextSize", MULTI_TEXT_SIZE)
        or (compact and visualNumber("plateStackTextSize", COMPACT_TEXT_SIZE)
        or visualNumber("plateTextSize", entry.fontSize or 12))
    local styleChanged = entry.mode ~= mode
    if styleChanged then
        entry.mode = mode
        entry.texture:SetSize(iconSize, iconSize)
    end
    -- Only allocate new font strings for genuinely new objectives. They are
    -- reused when the native nameplate is assigned to another NPC.
    while #entry.numbers < n do
        local number = entry.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        number:SetJustifyH("RIGHT")
        if type(number.SetWordWrap) == "function" then number:SetWordWrap(false) end
        if type(number.SetNonSpaceWrap) == "function" then number:SetNonSpaceWrap(false) end
        if type(number.SetMaxLines) == "function" then number:SetMaxLines(1) end
        number:SetTextColor(1, 0.82, 0)
        entry.numbers[#entry.numbers + 1] = number
    end
    local width = 0
    for i, label in ipairs(values) do
        local number = entry.numbers[i]
        if styleChanged or i > #entry.oldValues then
            if entry.fontPath then number:SetFont(entry.fontPath, fontSize, entry.fontFlags) end
        end
        if entry.oldValues[i] ~= label or styleChanged then
            number:SetText(label)
            entry.oldValues[i] = label
            entry.measuredWidths[i] = measureLabel(label, fontSize)
        end
        number:Show()
        local measured = entry.measuredWidths[i] or 13
        if measured > width then width = measured end
    end
    for i = n + 1, #entry.numbers do
        entry.numbers[i]:Hide()
        entry.oldValues[i] = nil
        entry.measuredWidths[i] = nil
    end
    local lineHeight = visualNumber("plateMultiTextSize", MULTI_TEXT_SIZE) + 1
    local height = math.max(iconSize, multi and n * lineHeight or iconSize)
    if entry.height ~= height then
        entry.frame:SetHeight(height)
        entry.height = height
    end
    if entry.textWidth ~= width or styleChanged then
        entry.textWidth = width
    end
    -- The same numerical column will be applied across both categories below.
    return height, width
end

-- Match the VISIBLE text-to-icon spacing between single and stacked layouts.
-- The cursor atlases contain transparent padding, and reducing icon/font sizes
-- changes the apparent gap even when the font string has the same anchor offset.
-- Compensate for both size changes relative to the single-objective layout.
-- Only configured, non-secret values are used (never GetStringWidth).
local function numberToIconOffset(kind, iconSize, numberSize, gap)
    local referenceIcon = visualNumber("plateIconSize", ICON_WIDTH)
    local referenceText = visualNumber("plateTextSize", 12)
    local visualCorrection = math.floor((referenceIcon - iconSize) * 0.5
        + (referenceText - numberSize) * 0.5 + 0.5)
    return ICON_TEXT_OFFSET[kind] - (gap - COMPACT_COLUMN_GAP) - visualCorrection
end

local function positionCategoryNumbers(entry, n, column, compact)
    local iconSize = compact and visualNumber("plateStackIconSize", COMPACT_ICON_SIZE)
        or visualNumber("plateIconSize", ICON_WIDTH)
    local multi = n > 1
    local gutter = visualNumber("plateNumberGap", COMPACT_COLUMN_GAP)
    local fontSize = multi and visualNumber("plateMultiTextSize", MULTI_TEXT_SIZE)
        or (compact and visualNumber("plateStackTextSize", COMPACT_TEXT_SIZE)
        or visualNumber("plateTextSize", entry.fontSize or 12))
    -- Measured text width is enough on a selected plate, but on distant
    -- unselected plates the client's font-layout scale may differ from the
    -- health bar's scale. Give the RIGHT-justified label ample invisible space:
    -- its visible right edge does not move, and '/' cannot force a new line.
    local width = math.max(64, math.ceil(column * 2 + 12))
    if entry.numberWidth ~= width or entry.numberCount ~= n then
        for i = 1, #entry.numbers do entry.numbers[i]:SetWidth(width) end
        entry.numberWidth, entry.numberCount = width, n
    end
    -- The configurable gap is shared by every layout. A calibrated optical
    -- adjustment is necessary because the stacked icon and text are smaller.
    -- Without it (v0.7.7), the same anchor offset looks like a narrower gap.
    local gapDelta = gutter - COMPACT_COLUMN_GAP
    local iconGapOffset = numberToIconOffset(entry.kind, iconSize, fontSize, gutter)
    local totalWidth = (compact or multi)
        and (width + gutter + iconSize)
        or (width + iconSize - 1 + (3 - ICON_TEXT_OFFSET[entry.kind]) + gapDelta)
    if entry.width ~= totalWidth then
        entry.frame:SetWidth(totalWidth)
        entry.width = totalWidth
    end
    -- Position only when category layout changes; changes in values do not
    -- shift any of the anchors.
    local signature = table.concat({n, column, compact and 1 or 0, iconSize, gutter,
        fontSize, visualNumber("plateIconSize", ICON_WIDTH),
        visualNumber("plateTextSize", 12)}, ":")
    if entry.numberLayout ~= signature then
        entry.numberLayout = signature
        entry.texture:ClearAllPoints()
        entry.texture:SetPoint("RIGHT", entry.frame, "RIGHT",
            compact and entry.kind == "monster" and COMPACT_SWORD_INSET or 0, 0)
        for i = 1, n do
            local number = entry.numbers[i]
            number:ClearAllPoints()
            local y = multi and (n + 1 - 2 * i)
                * (visualNumber("plateMultiTextSize", MULTI_TEXT_SIZE) + 1) / 2 or 0
            -- Anchor to the ICON (not the variable-width frame) in every
            -- layout. Adjusting plateNumberGap moves all number columns by
            -- exactly the same amount, preserving their vertical positions.
            number:SetPoint("RIGHT", entry.texture, "LEFT", iconGapOffset, y)
        end
    end
end

local function showOnPlate(plate, categorized)
    if not feature("nameplateIcons") and not plate.FQTLPreview then hidePlateIcons(plate); return end
    local loot = valuesFor(categorized.item or {})
    local kill = valuesFor(categorized.monster or {})
    if #loot == 0 and #kill == 0 then hidePlateIcons(plate); return end

    if not plate.FQTLPreview then plate.FQTLLastQuestObjectives = categorized end
    local ui = ensureIcons(plate)
    local unitFrame = plate.UnitFrame
    local barAnchor = unitFrame and (unitFrame.healthBar
        or (unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar)) or plate
    -- Forever positions the raid marker at the health bar's left edge and
    -- the rarity/elite indicator immediately to the LEFT of that marker.
    -- Blizzard hides classification when a raid icon is assigned, but both
    -- frames may briefly be shown during a state transition. Prefer the outer
    -- classification frame when visible. Never rely on GetPoint() returning
    -- a specific anchor name: a valid marker can be shown before its layout
    -- is finalized, and that check caused overlap with raid marks in 0.7.4.
    -- In name-only mode raid marks sit ABOVE the unit name, not to its left.
    local raidFrame = unitFrame and unitFrame.RaidTargetFrame
    local classificationFrame = unitFrame and unitFrame.ClassificationFrame
    local nameOnly = unitFrame and (unitFrame.showOnlyName == true
        or (type(unitFrame.IsShowOnlyName) == "function"
            and safe(unitFrame.IsShowOnlyName, unitFrame) == true))
    local hasClassification = not nameOnly and classificationFrame
        and safe(classificationFrame.IsShown, classificationFrame) == true
    local hasRaidMarker = not nameOnly and raidFrame
        and safe(raidFrame.IsShown, raidFrame) == true
    local anchor = hasClassification and classificationFrame
        or (hasRaidMarker and raidFrame) or barAnchor
    local extraMargin = (hasClassification or hasRaidMarker)
        and visualNumber("plateRaidTargetExtra", 4) or 0
    local distance = visualNumber("plateDistance", PLATE_GAP) + extraMargin
    local both = #loot > 0 and #kill > 0
    local heights, numbers, column = {}, {}, 0
    for index, kind in ipairs(DISPLAY_KINDS) do
        local values = kind == "item" and loot or kill
        if #values > 0 then
            local height, width = updateCategory(ui[index], values, both)
            heights[kind], numbers[kind] = height, #values
            column = math.max(column, width)
        end
    end
    local rowSpacing = visualNumber("plateRowSpacing", ROW_SPACING)
    local totalHeight = (heights.item or 0) + (heights.monster or 0)
        + (both and rowSpacing or 0)
    local topY = totalHeight / 2
    for index, kind in ipairs(DISPLAY_KINDS) do
        local entry = ui[index]
        local height = heights[kind]
        if height then
            positionCategoryNumbers(entry, numbers[kind], both and column or entry.textWidth, both)
            local y = topY - height / 2
            topY = topY - height - rowSpacing
            if entry.anchor ~= anchor or entry.y ~= y or entry.distance ~= distance then
                entry.frame:ClearAllPoints()
                entry.frame:SetPoint("RIGHT", anchor, "LEFT", -distance, y)
                entry.anchor, entry.y, entry.distance = anchor, y, distance
            end
            entry.frame:Show()
        else
            entry.frame:Hide()
        end
    end
end

ns.PlateAppearance = {
    Refresh = function()
        if not feature("nameplateIcons") then return end
        for unit in pairs(visiblePlates) do
            local plate = safe(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit)
            if plate and plate.FQTLLastQuestObjectives then
                showOnPlate(plate, plate.FQTLLastQuestObjectives)
            end
        end
    end,
    Preview = function(plate, categorized)
        plate.FQTLPreview = true
        -- Exactly the same layout function as the live nameplates.
        showOnPlate(plate, categorized)
    end,
}

-- One native-tooltip read drives visuals and the macro's learned NPC list.
local function inspectUnit(unit, plate)
    if not npcEnabled() then return false end
    if not unit or activeCount == 0 or safe(UnitExists, unit) ~= true
        or safe(UnitIsPlayer, unit) == true then
        if plate then
            setVisibleQuest(unit)
            showOnPlate(plate, { monster = {}, item = {} })
        end
        return false
    end

    local tooltip = safe(C_TooltipInfo and C_TooltipInfo.GetUnit, unit)
    if type(tooltip) ~= "table" then
        if plate then
            setVisibleQuest(unit)
            showOnPlate(plate, { monster = {}, item = {} })
        end
        return false
    end
    if TooltipUtil and type(TooltipUtil.SurfaceArgs) == "function" then
        pcall(TooltipUtil.SurfaceArgs, tooltip)
    end
    if type(tooltip.lines) ~= "table" then
        if plate then
            setVisibleQuest(unit)
            showOnPlate(plate, { monster = {}, item = {} })
        end
        return false
    end

    stats.tooltips = stats.tooltips + 1
    local result = { monster = {}, item = {} }
    local unique = {}
    local name = safe(UnitName, unit)
    local hasName = type(name) == "string" and name ~= "" and not name:find("[\r\n]")
    local newlyLearned = false
    local matching = false

    for _, line in ipairs(tooltip.lines) do
        if type(line) == "table" then
            if TooltipUtil and type(TooltipUtil.SurfaceArgs) == "function" then
                pcall(TooltipUtil.SurfaceArgs, line)
            end
            if readable(line.type) and line.type == LINE_OBJECTIVE
                and readable(line.leftText) and type(line.leftText) == "string" then
                local entries = objectivesByText[line.leftText]
                if entries then
                    for _, entry in ipairs(entries) do
                        matching = true
                        if not unique[entry.key] then
                            unique[entry.key] = true
                            local bucket = result[entry.kind]
                            bucket[#bucket + 1] = entry
                        end
                        if hasName and feature("autoMacro") then
                            local seen = learnedCache()[entry.key]
                            if not seen then seen = {}; FQTL4_Seen[entry.key] = seen end
                            lastSeen[name] = GetTime()
                            if not seen[name] then
                                seen[name] = true
                                stats.learned = stats.learned + 1
                                newlyLearned = true
                            end
                        end
                    end
                end
            end
        end
    end

    if matching then stats.hits = stats.hits + 1 end
    if plate then
        -- Do not prioritize dead nameplates when generating new macro text.
        local alive = safe(UnitIsDeadOrGhost, unit) ~= true and safe(UnitIsDead, unit) ~= true
        setVisibleQuest(unit, (hasName and alive) and name or nil,
            #result.monster > 0, #result.item > 0)
        showOnPlate(plate, result)
    end
    if newlyLearned then requestMacro() end
    return matching
end

local function updatePlate(unit)
    if not npcEnabled() or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return false end
    local plate = safe(C_NamePlate.GetNamePlateForUnit, unit)
    if not plate then setVisibleQuest(unit); return false end
    return inspectUnit(unit, plate)
end

local function updateVisible()
    if not npcEnabled() then return end
    for unit in pairs(visiblePlates) do updatePlate(unit) end
    if feature("autoMacro") then
        inspectUnit("target")
        inspectUnit("mouseover")
    end
end

local function refreshNow()
    refreshPending = false
    if not anyObjectivesNeeded() then return end
    rebuildObjectives()
    updateVisible()
    requestMacro()
end

local function refreshSoon()
    if not anyObjectivesNeeded() or refreshPending then return end
    refreshPending = true
    C_Timer.After(0.25, refreshNow)
end

-- No priority-only event cost when automatic macro generation is disabled.
-- The optional journal-selection event is registered only if the Forever
-- client accepts it; focused quest changes always use SUPER_TRACKING_CHANGED.
local macroPriorityEvents = { "SUPER_TRACKING_CHANGED", "QUEST_LOG_SELECTION_CHANGED" }
local macroPriorityEventsEnabled = false
local plateAdornmentEventEnabled = false
local plateAdornmentEvents = { "RAID_TARGET_UPDATE", "UNIT_CLASSIFICATION_CHANGED" }
local function syncPlateAdornmentEvents()
    -- Only the two native state-change events; no hooks or per-frame checks.
    -- No added event cost at all if plate indicators are disabled.
    local enabled = feature("nameplateIcons") == true
    if enabled == plateAdornmentEventEnabled then return end
    for _, event in ipairs(plateAdornmentEvents) do
        if enabled then
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        else
            pcall(eventFrame.UnregisterEvent, eventFrame, event)
        end
    end
    plateAdornmentEventEnabled = enabled
end

-- Multiple native events can occur during one change. Coalesce them into
-- one after-Blizzard pass using the already cached quest associations.
local adornmentRefreshPending = false
local adornmentRefreshAll = false
local adornmentRefreshUnits = {}
local function refreshAdornments(unit)
    if not feature("nameplateIcons") then return end
    if not unit then
        adornmentRefreshAll = true
    elseif visiblePlates[unit] then
        adornmentRefreshUnits[unit] = true
    else
        return
    end
    if adornmentRefreshPending then return end
    adornmentRefreshPending = true
    C_Timer.After(0, function()
        adornmentRefreshPending = false
        local all = adornmentRefreshAll
        adornmentRefreshAll = false
        if not feature("nameplateIcons") then wipe(adornmentRefreshUnits); return end
        local units = all and visiblePlates or adornmentRefreshUnits
        for token in pairs(units) do
            if visiblePlates[token] then
                local plate = safe(C_NamePlate and C_NamePlate.GetNamePlateForUnit, token)
                if plate and plate.FQTLLastQuestObjectives then
                    showOnPlate(plate, plate.FQTLLastQuestObjectives)
                end
            end
        end
        wipe(adornmentRefreshUnits)
    end)
end
local function syncMacroPriorityEvents()
    local enabled = feature("autoMacro") == true
    if enabled == macroPriorityEventsEnabled then return end
    macroPriorityEventsEnabled = enabled
    for _, event in ipairs(macroPriorityEvents) do
        if enabled then
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        else
            pcall(eventFrame.UnregisterEvent, eventFrame, event)
        end
    end
end

-- Native settings callbacks, not a polling loop. Disabled features are cleaned
-- up immediately; an existing macro is left on the action bar untouched.
function ns.CoreRefreshSettings(key)
    if key == "autoMacro" then syncMacroPriorityEvents() end
    if key == "nameplateIcons" then syncPlateAdornmentEvents() end
    if key == "nameplateIcons" and not feature("nameplateIcons") then
        for unit in pairs(visiblePlates) do
            local plate = safe(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit)
            hidePlateIcons(plate)
        end
    end
    if key == "autoMacro" and not feature("autoMacro") then
        wipe(visibleQuest)
        combatPending = false
    end
    if key == "autoMacro" and feature("autoMacro") then requestMacro() end
    if anyObjectivesNeeded() then refreshSoon() end
end

eventFrame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= ADDON_NAME then return end
        learnedCache()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        syncMacroPriorityEvents()
        syncPlateAdornmentEvents()
        refreshSoon()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if not npcEnabled() or type(arg) ~= "string" then return end
        visiblePlates[arg] = true
        -- Tooltip can become available slightly after the nameplate event.
        updatePlate(arg)
        C_Timer.After(0.12, function()
            if visiblePlates[arg] and npcEnabled() then updatePlate(arg) end
        end)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if visibleQuest[arg] then
            visibleQuest[arg] = nil
            requestMacro()
        end
        visiblePlates[arg] = nil
        if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
            local plate = safe(C_NamePlate.GetNamePlateForUnit, arg)
            hidePlateIcons(plate)
        end
    elseif event == "RAID_TARGET_UPDATE" then
        -- Marks can affect any visible unit; let Blizzard finish positioning.
        refreshAdornments()
    elseif event == "UNIT_CLASSIFICATION_CHANGED" then
        -- Rarity changed on one unit. Re-anchor only its cached indicator.
        if type(arg) == "string" then refreshAdornments(arg) end
    elseif event == "SUPER_TRACKING_CHANGED" or event == "QUEST_LOG_SELECTION_CHANGED" then
        -- No objective rescan or frame work; only rewrite if the resulting
        -- macro text changes. A combat change is deferred normally.
        requestMacro()
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if feature("autoMacro") then inspectUnit("mouseover") end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if feature("autoMacro") then inspectUnit("target") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if combatPending then combatPending = false; requestMacro() end
    else
        refreshSoon()
    end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED",
}) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end

SLASH_FQTL1 = "/qh"
SLASH_FQTL2 = "/qtl" -- backward-compatible alias
SlashCmdList.FQTL = function(text)
    local cmd = type(text) == "string" and text:match("^%s*(.-)%s*$"):lower() or ""
    if cmd == "update" then
        refreshNow()
        if feature("autoMacro") and not InCombatLockdown() then writeMacro() end
        out(("Revisado: %d objetivos, %d NPC en macro (espada %d/%d, saquito %d/%d), %d omitidos.")
            :format(activeCount, stats.macroNames, stats.macroKill, stats.availableKill,
                stats.macroLoot, stats.availableLoot, stats.omitted))
    elseif cmd == "debug" then
        buildMacro()
        local focusedQuest, journalQuest = macroQuestPriorities()
        out(("Prioridad macro: superseguida=%s | diario=%s")
            :format(tostring(focusedQuest or "ninguna"), tostring(journalQuest or "ninguna")))
        out(("Objetivos: %d | NPC macro: %d | omitidos (limite 255): %d")
            :format(activeCount, stats.macroNames, stats.omitted))
        out(("Espada: %d/%d NPC | Saquito: %d/%d NPC")
            :format(stats.macroKill, stats.availableKill, stats.macroLoot, stats.availableLoot))
        out(("Tooltips leidos: %d | coincidencias: %d | nombres aprendidos: %d")
            :format(stats.tooltips, stats.hits, stats.learned))
        local printed = 0
        for key, entry in pairs(activeByKey) do
            local n = 0
            for _ in pairs(learnedCache()[key] or {}) do n = n + 1 end
            out(("%s: %d NPC, %s pendiente(s) | %s")
                :format(key, n, tostring(entry.left or "?"), entry.text))
            printed = printed + 1
            if printed >= 12 then break end
        end
    elseif cmd == "itemdebug" or cmd == "bagdebug" then
        if ns.QuestItems and ns.QuestItems.Debug then ns.QuestItems.Debug() end
    elseif cmd == "options" or cmd == "config" then
        if ns and ns.OpenOptions then ns.OpenOptions() end
    elseif cmd == "apariencia" or cmd == "appearance" then
        if ns and ns.OpenOptions then ns.OpenOptions(true) end
    elseif cmd == "sortdebug" then
        if ns and ns.TrackerSort and ns.TrackerSort.Debug then ns.TrackerSort.Debug() end
        if ns and ns.TrackerZones and ns.TrackerZones.Debug then ns.TrackerZones.Debug() end
    elseif cmd == "trackerdiag" then
        if ns and ns.TrackerZones and ns.TrackerZones.Diagnose then ns.TrackerZones.Diagnose() end
    elseif cmd == "chatdebug" then
        if ns and ns.AnnounceDebug then ns.AnnounceDebug() end
    elseif cmd == "reset" then
        wipe(learnedCache())
        wipe(lastSeen)
        refreshNow()
        out("Nombres aprendidos borrados; se reconstruiran al ver NPC de mision.")
    else
        out("/qh update | /qh debug | /qh itemdebug | /qh reset | /qh options | /qh apariencia | /qh chatdebug | /qh sortdebug | /qh trackerdiag (alias: /qtl)")
        out("No cambia tu objetivo salvo cuando pulsas la macro QuestHelper.")
    end
end
