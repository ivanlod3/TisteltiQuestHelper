-- QuestHelper 0.7.1: mission-item markers + native Baganator stack-count replacement.
-- Uses the quest objective snapshot from the main module; no second quest scan,
-- no periodic tickers, no global frame enumeration, and no item database.
local addonName, ns = ...
local ICON_ATLAS = "Crosshair_pickup_32"
local BAG_ICON_SIZE = 15
local function appearanceNumber(key, fallback)
    return ns.Config and ns.Config.GetNumber and ns.Config.GetNumber(key) or fallback
end
local itemObjectives = {}   -- normalised item name -> active quest objective(s)
local questsByID = {}       -- active item objective(s) by quest ID
local inventoryUnknown = {} -- unclassified client objectives, inventory only
local nameCache = {}       -- itemID -> resolved item name
local matchCache = {}      -- itemID -> pending objective entries or false; invalidated on quest change
local marks = setmetatable({}, { __mode = "k" })
local updateQueued, needScanAfterCombat = false, false
local tooltipHooked, bagHooksInstalled = false, false
local loggedIn = false
local lastActiveObjectives, lastUnknownObjectives, lastCompletedObjectives = nil, nil, nil
local lastItemEntries = {} -- session-only last progress of item objectives
local lastJournalQuestIDs
ns.QuestItems = {}

local function readable(value)
    return value ~= nil and (not issecretvalue or not issecretvalue(value))
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok and readable(result) then return result end
end
local function enabled(key)
    return ns.Config and ns.Config.Get and ns.Config.Get(key)
end
local function normalize(text)
    if type(text) ~= "string" or not readable(text) then return nil end
    text = text:lower()
    -- Supports "Pieles: 3/8", "3/8 Pieles" and "Pieles (3/8)".
    text = text:gsub("%s*%(%d+%s*/%s*%d+%)%s*$", "")
    text = text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    text = text:gsub("^%s*%d+%s*/%s*%d+%s*", "")
    text = text:gsub(":%s*$", "")
    text = text:gsub("^%s*%-%s*", "")
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end
local function variants(name)
    local key = normalize(name)
    if not key then return end
    -- Exact first. Minimal plural aliases (Pieles/Piel, Lobos/Lobo):
    -- no substring or similarity matching, which would mark unrelated objects.
    local singleS = key:gsub("([%a\128-\255]+)", function(word)
        if #word >= 4 and word:sub(-1) == "s" then return word:sub(1, -2) end
        return word
    end)
    local singleES = key:gsub("([%a\128-\255]+)", function(word)
        if #word >= 5 and word:sub(-2) == "es" then return word:sub(1, -3) end
        if #word >= 4 and word:sub(-1) == "s" then return word:sub(1, -2) end
        return word
    end)
    return key, singleS, singleES
end
local function putIndex(key, entry)
    if not key then return end
    local bucket = itemObjectives[key]
    if not bucket then bucket = {}; itemObjectives[key] = bucket end
    for i = 1, #bucket do if bucket[i] == entry then return end end
    bucket[#bucket + 1] = entry
end
local function addQuestObjective(entry)
    local a, b, c = variants(entry.text)
    putIndex(a, entry)
    if b ~= a then putIndex(b, entry) end
    if c ~= a and c ~= b then putIndex(c, entry) end
    local quest = questsByID[entry.questID]
    if not quest then quest = {}; questsByID[entry.questID] = quest end
    quest[#quest + 1] = entry
end
local function forName(name)
    local a, b, c = variants(name)
    -- Prefer exact match, then limited plural aliases.
    return a and (itemObjectives[a] or itemObjectives[b] or itemObjectives[c])
end
local function itemName(itemID)
    if type(itemID) ~= "number" or not readable(itemID) then return nil end
    if nameCache[itemID] then return nameCache[itemID] end
    local name = safe(C_Item and C_Item.GetItemNameByID, itemID)
        or safe(GetItemInfo, itemID)
    if type(name) == "string" and name ~= "" then
        nameCache[itemID] = name
        return name
    end
end
local function findEntries(itemID, questID)
    if type(itemID) ~= "number" then return end
    local cached = matchCache[itemID]
    if cached == nil then
        local name = itemName(itemID)
        if name then
            cached = forName(name) or false
            matchCache[itemID] = cached
        end
    end
    if cached and cached ~= false then return cached end
    -- An active quest ID is a native explicit association; avoid fuzzy guesses.
    if type(questID) == "number" then
        local byQuest = questsByID[questID] or inventoryUnknown[questID]
        if byQuest then
            -- Cache the *explicit* native association so item tooltips use it too.
            matchCache[itemID] = byQuest
            return byQuest
        end
    end
end
local function questTitle(questID)
    return safe(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID) or ("Misión " .. tostring(questID))
end
local function slotInfo(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" or bag < 0 or bag > 5 or slot < 1 then return end
    local info = safe(C_Container and C_Container.GetContainerItemInfo, bag, slot)
    if type(info) ~= "table" or not readable(info.itemID) then return end
    local questInfo = safe(C_Container and C_Container.GetContainerItemQuestInfo, bag, slot)
    local questID
    if type(questInfo) == "table" and readable(questInfo.questID)
        and type(questInfo.questID) == "number" and questInfo.questID > 0
        and (questInfo.isActive == true or questsByID[questInfo.questID]) then
        questID = questInfo.questID
    end
    return info.itemID, questID
end
local function clearMark(button)
    local mark = marks[button]
    if mark then mark:Hide() end
end
local function markButton(button)
    if not button or not button.CreateTexture then return end
    if button.IsForbidden and safe(button.IsForbidden, button) == true then return end
    if not enabled("markBags") then clearMark(button); return end
    if button.IsVisible and safe(button.IsVisible, button) == false then
        clearMark(button)
        return
    end
    local bag, slot = safe(button.GetBagID, button), safe(button.GetID, button)
    local itemID, questID = slotInfo(bag, slot)
    if not itemID or not findEntries(itemID, questID) then clearMark(button); return end
    local mark = marks[button]
    if not mark then
        if InCombatLockdown and InCombatLockdown() then
            needScanAfterCombat = true
            return
        end
        mark = button:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetSize(appearanceNumber("bagMarkerSize", BAG_ICON_SIZE), appearanceNumber("bagMarkerSize", BAG_ICON_SIZE))
        mark:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -1)
        mark:SetAtlas(ICON_ATLAS)
        marks[button] = mark
    end
    mark:Show()
end
local function visible(frame)
    return frame and frame.IsVisible and safe(frame.IsVisible, frame) == true
end
local function scanBlizzardBags()
    local seen = setmetatable({}, { __mode = "k" })
    local function view(frame)
        if not visible(frame) or not frame.EnumerateValidItems then return end
        local ok = pcall(function()
            local count = 0
            for _, button in frame:EnumerateValidItems() do
                if button and not seen[button] then
                    seen[button] = true
                    markButton(button)
                    count = count + 1
                    if count >= 220 then break end
                end
            end
        end)
        return ok
    end
    view(_G.ContainerFrameCombinedBags)
    local container = _G.ContainerFrameContainer
    local frames = container and container.ContainerFrames
    if type(frames) == "table" then
        for _, frame in pairs(frames) do view(frame) end
    end
    -- Older bag layout uses individual ContainerFrame1..13 frames.
    for i = 1, 13 do view(_G["ContainerFrame" .. i]) end
end
local function updateBags()
    if InCombatLockdown and InCombatLockdown() then
        needScanAfterCombat = true
        return
    end
    if not enabled("markBags") then
        for button, mark in pairs(marks) do mark:Hide() end
        return
    end
    -- No item-type objectives => no need to walk bag UI at all.
    if not next(itemObjectives) then
        for _, mark in pairs(marks) do mark:Hide() end
        return
    end
    scanBlizzardBags()
end
local function queueBagUpdate()
    if not enabled("markBags") then return end
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0.15, function()
        updateQueued = false
        updateBags()
    end)
end
function ns.QuestItems.ObjectivesChanged(active, unknown, completed, journalQuestIDs)
    lastActiveObjectives = active
    lastUnknownObjectives = unknown
    lastCompletedObjectives = completed
    if journalQuestIDs then lastJournalQuestIDs = journalQuestIDs end
    journalQuestIDs = journalQuestIDs or lastJournalQuestIDs
    wipe(matchCache)
    if not enabled("markBags") and not enabled("markBaganator") and not enabled("itemTooltips") then
        wipe(itemObjectives)
        wipe(questsByID)
        wipe(inventoryUnknown)
        wipe(lastItemEntries)
        return
    end
    wipe(itemObjectives)
    wipe(questsByID)
    wipe(inventoryUnknown)
    for _, entry in pairs(active) do
        if entry.kind == "item" and type(entry.questID) == "number" then
            addQuestObjective(entry)
        end
    end
    -- QuestSage accepts nil item types on some versions of the client.
    -- Index them for exact item-name matching, NEVER for nameplates or macros.
    if type(unknown) == "table" then
        for _, entry in pairs(unknown) do
            if entry.kind == "unknown" and type(entry.questID) == "number" then
                addQuestObjective(entry)
                local bucket = inventoryUnknown[entry.questID]
                if not bucket then bucket = {}; inventoryUnknown[entry.questID] = bucket end
                bucket[#bucket + 1] = entry
            end
        end
    end
    -- Completed objectives remain in the *inventory-only* index until
    -- quest turn-in/removal. The main module never offers them to NPC macros.
    if type(completed) == "table" then
        for _, entry in pairs(completed) do
            if entry.completed == true and type(entry.questID) == "number" then
                addQuestObjective(entry)
                if entry.kind == "unknown" then
                    local bucket = inventoryUnknown[entry.questID]
                    if not bucket then bucket = {}; inventoryUnknown[entry.questID] = bucket end
                    bucket[#bucket + 1] = entry
                end
            end
        end
    end
    -- Reuse the parent module's quest-log membership. No extra log traversal.
    -- Cache only exact item objectives, never NPCs or arbitrary inventory data.
    local currentKeys = {}
    local function remember(entries)
        if type(entries) ~= "table" then return end
        for _, entry in pairs(entries) do
            if type(entry) == "table" and type(entry.key) == "string"
                and (entry.kind == "item" or entry.kind == "unknown")
                and type(entry.questID) == "number" then
                currentKeys[entry.key] = true
                lastItemEntries[entry.key] = { key = entry.key, questID = entry.questID,
                    kind = entry.kind, text = entry.text, count = entry.count,
                    completed = entry.completed == true }
            end
        end
    end
    remember(active)
    remember(unknown)
    remember(completed)
    for key, entry in pairs(lastItemEntries) do
        if type(journalQuestIDs) == "table" and not journalQuestIDs[entry.questID] then
            lastItemEntries[key] = nil -- quest turned in / abandoned
        elseif not currentKeys[key] then
            local questFinished = safe(C_QuestLog and C_QuestLog.IsComplete, entry.questID) == true
            if entry.completed or questFinished then
                local goal = type(entry.count) == "string" and entry.count:match("/%s*(%d+)")
                if goal then
                    entry.count = goal .. "/" .. goal
                    entry.completed = true
                end
                addQuestObjective(entry)
            end
        end
    end
    queueBagUpdate()
    if ns.QuestItems.RefreshBaganator then ns.QuestItems.RefreshBaganator() end
end

local function tooltipPostCall(tooltip, data)
    if not enabled("itemTooltips") or not tooltip or not tooltip.AddLine then return end
    local itemID = type(data) == "table" and readable(data.id) and data.id or nil
    if type(itemID) ~= "number" and type(data) == "table" and type(data.hyperlink) == "string" then
        itemID = tonumber(data.hyperlink:match("item:(%d+)"))
    end
    if type(itemID) ~= "number" then return end
    local entries = findEntries(itemID)
    if not entries then return end
    local printed = {}
    local added = 0
    for i = 1, #entries do
        local entry = entries[i]
        if not printed[entry.questID] then
            printed[entry.questID] = true
            local message = "|cff73c9ffQuestHelper:|r " .. tostring(questTitle(entry.questID))
            if entry.count then message = message .. "  |cffffd100" .. entry.count .. "|r" end
            tooltip:AddLine(message, 1, 1, 1, true)
            added = added + 1
            if added >= 3 then break end
        end
    end
    if added > 0 and tooltip.Show then tooltip:Show() end
end

-- Baganator is NOT Bagnon nor Blizzard's bag frame. Use its public corner
-- widget API, which already handles recycled item buttons and visible updates.
-- Never search Baganator's frames or hook its internal mixins.
local baganatorRegistered = false
local baganatorRegistrationError
local baganatorChecks, baganatorMatches, nativeAssociations = 0, 0, 0
-- Weak keys: recycled Baganator item buttons must never retain an old quest count.
local stackOverrides = setmetatable({}, { __mode = "k" })
local stackHooks = setmetatable({}, { __mode = "k" })

local function stackTextRegion(button)
    if not button then return nil end
    -- Baganator uses Blizzard's ItemButton Count text for stack quantities.
    -- Never modify anything if this version/skin does not expose that region.
    local region = button.Count or button.CountText or button.ItemCount
    if (type(region) == "table" or type(region) == "userdata")
        and type(region.SetText) == "function" and type(region.Show) == "function" then
        return region
    end
end

-- Count style is button-local: never modify Baganator's shared FontObject.
-- Preserve the original font/colour so recycled slots restore normally.
local function restoreCountStyle(button, state)
    local region = stackTextRegion(button)
    if not region or not state then return end
    if state.baseFont and region.SetFont then
        pcall(region.SetFont, region, state.baseFont, state.baseSize, state.baseFlags)
    end
    if state.baseR and region.SetTextColor then
        region:SetTextColor(state.baseR, state.baseG, state.baseB, state.baseA)
    end
end
local function styleQuestCount(region, state)
    if not region or not region.GetFont then return end
    if not state.baseFont then
        local font, size, flags = region:GetFont()
        if type(font) ~= "string" or type(size) ~= "number" then return end
        state.baseFont, state.baseSize, state.baseFlags = font, size, flags
        if region.GetTextColor then
            state.baseR, state.baseG, state.baseB, state.baseA = region:GetTextColor()
        end
    end
    local target = appearanceNumber("bagCounterSize", 11)
    if state.appliedSize ~= target then
        region:SetFont(state.baseFont, target, "OUTLINE")
        state.appliedSize = target
    end
    if region.SetTextColor then region:SetTextColor(1, 0.82, 0, 1) end
end
local function putQuestCount(button, itemID, label)
    local region = stackTextRegion(button)
    if not region or type(label) ~= "string" then return false end
    if not label:match("^%d+%s*/%s*%d+$") then return false end
    local state = stackOverrides[button]
    if not state then
        state = {}
        stackOverrides[button] = state
    end
    state.itemID, state.label = itemID, label
    styleQuestCount(region, state)
    -- SetItemButtonCount may have reset it during Baganator's own refresh.
    region:SetText(label)
    region:Show()
    return true
end

local function restoreStackCount(button, details)
    local state = stackOverrides[button]
    if not state then return end
    restoreCountStyle(button, state)
    stackOverrides[button] = nil
    -- Restore through the same Blizzard helper Baganator itself uses.
    local count = details and details.itemCount
    if count == nil and button and button.BGR then count = button.BGR.itemCount end
    if type(SetItemButtonCount) == "function" then
        local ok = pcall(SetItemButtonCount, button, count,
            type(count) == "number" and count > 9999)
        if ok then return end
    end
    local region = stackTextRegion(button)
    if not region then return end
    if type(count) == "number" and count > 1 then
        region:SetText(tostring(count))
        region:Show()
    else
        region:Hide()
    end
end

local function ensurePostRefresh(button)
    if not button or stackHooks[button] or type(hooksecurefunc) ~= "function"
        or type(button.SetItemDetails) ~= "function" then return end
    -- Classic-style Baganator calls SetItemButtonCount AFTER its widget callback.
    -- This one post-hook re-applies our label at the end of that existing refresh.
    -- O(1), no timers, events, new scans or per-frame work.
    local ok = pcall(hooksecurefunc, button, "SetItemDetails", function(b)
        local state = stackOverrides[b]
        if not state then return end
        if not enabled("markBaganator") then
            restoreStackCount(b)
            return
        end
        local currentID = b.BGR and b.BGR.itemID
        if currentID ~= state.itemID then
            -- Baganator has recycled the button for another item.
            restoreCountStyle(b, state)
            stackOverrides[b] = nil
            return
        end
        putQuestCount(b, currentID, state.label)
    end)
    if ok then stackHooks[button] = true end
end
local function baganatorAvailable()
    return type(Baganator) == "table" and type(Baganator.API) == "table"
end
local function currentBagQuestID(widget, expectedID)
    -- The corner widget is parented below Baganator's real slot button.
    -- Only inspect the ONE live slot Baganator is currently updating.
    local parent = widget and safe(widget.GetParent, widget)
    local button = parent and safe(parent.GetParent, parent)
    if not button then return end
    local bag = safe(button.GetBagID, button)
    if type(bag) ~= "number" then
        local holder = safe(button.GetParent, button)
        bag = safe(holder and holder.GetID, holder)
    end
    local slot = safe(button.GetID, button)
    local actualID, questID = slotInfo(bag, slot)
    if actualID == expectedID then return questID end
end
-- All bag overlays reuse the journal snapshot: completed items retain
-- their final count (6/6), while unfinished objectives take precedence.
local function progressForEntries(entries)
    if type(entries) ~= "table" then return nil end
    local completedProgress
    for i = 1, #entries do
        local entry = entries[i]
        if entry and type(entry.count) == "string" and entry.count ~= "" then
            if not entry.completed then return entry.count end
            if not completedProgress then completedProgress = entry.count end
        end
    end
    return completedProgress
end

-- Shared factory for real Baganator widgets and the static configuration preview.
-- The silhouette is outlined on all four sides; zero OnUpdate activity.
local function createBagGlyph(widget)
    widget.QHShadows = {}
    for i = 1, 4 do
        local shadow = widget:CreateTexture(nil, "BACKGROUND")
        shadow:SetAtlas(ICON_ATLAS)
        shadow:SetVertexColor(0, 0, 0, 0.95)
        widget.QHShadows[i] = shadow
    end
    widget.QHIcon = widget:CreateTexture(nil, "ARTWORK")
    widget.QHIcon:SetAtlas(ICON_ATLAS)
    widget.QHIcon:SetVertexColor(1, 1, 1, 1)
end
local function applyBagGlyphStyle(widget)
    if not widget or not widget.QHIcon then return end
    local size = appearanceNumber("bagMarkerSize", BAG_ICON_SIZE)
    local outline = appearanceNumber("bagOutlineWidth", 1)
    local sig = tostring(size) .. ":" .. tostring(outline)
    if widget.QHStyleSignature == sig then return end
    widget.QHStyleSignature = sig
    widget:SetSize(size + 2 * outline, size + 2 * outline)
    local icon = widget.QHIcon
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", widget, "CENTER", 0, 0)
    icon:SetSize(size, size)
    local offsets = {{-outline, 0}, {outline, 0}, {0, outline}, {0, -outline}}
    for i, shadow in ipairs(widget.QHShadows) do
        shadow:ClearAllPoints()
        shadow:SetPoint("CENTER", icon, "CENTER", offsets[i][1], offsets[i][2])
        shadow:SetSize(size, size)
        shadow:SetShown(outline > 0)
    end
end
function ns.QuestItems.CreatePreviewMarker(parent)
    local widget = CreateFrame("Frame", nil, parent)
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
    createBagGlyph(widget)
    applyBagGlyphStyle(widget)
    return widget
end
function ns.QuestItems.StylePreviewCount(region)
    if not region.QHPreviewState then region.QHPreviewState = {} end
    styleQuestCount(region, region.QHPreviewState)
end
function ns.QuestItems.RefreshPreviewMarker(widget)
    applyBagGlyphStyle(widget)
end

local function registerBaganator()
    if baganatorRegistered or not enabled("markBaganator") or not baganatorAvailable()
        or type(Baganator.API.RegisterCornerWidget) ~= "function" then return end
    local ok, err = pcall(Baganator.API.RegisterCornerWidget,
        "QuestHelper - Objetos de misión", "tistelti_questhelper_needed",
        function(icon, details)
            applyBagGlyphStyle(icon)
            local button = icon and icon.itemButton
            if not enabled("markBaganator") or not next(itemObjectives)
                or type(details) ~= "table" then
                restoreStackCount(button, details)
                return false
            end
            baganatorChecks = baganatorChecks + 1
            local id = readable(details.itemID) and details.itemID or nil
            if type(id) == "string" then id = tonumber(id) end
            if type(id) ~= "number" and type(details.itemLink) == "string" then
                id = tonumber(details.itemLink:match("item:(%d+)"))
            end
            if type(id) ~= "number" and type(details.hyperlink) == "string" then
                id = tonumber(details.hyperlink:match("item:(%d+)"))
            end
            if type(id) ~= "number" then
                restoreStackCount(button, details)
                return false
            end
            -- First, cheap in-memory name matching. On a miss, try the native
            -- questID from this one live bag slot; never scan other buttons.
            local entries = findEntries(id)
            if not entries then
                local questID = currentBagQuestID(icon, id)
                if questID then
                    entries = findEntries(id, questID)
                    if entries then nativeAssociations = nativeAssociations + 1 end
                end
            end
            if entries then
                baganatorMatches = baganatorMatches + 1
                -- Use Baganator's own stack counter, not another floating number.
                -- If its Count text is unavailable leave its native quantity alone.
                local label = progressForEntries(entries)
                if label then putQuestCount(button, id, label)
                else restoreStackCount(button, details) end
                return true
            end
            restoreStackCount(button, details)
            -- Uncached names: Baganator understands nil as "try again later".
            if not itemName(id) then return nil end
            return false
        end,
        function(itemButton)
            local widget = CreateFrame("Frame", nil, itemButton)
            widget.itemButton = itemButton
            ensurePostRefresh(itemButton)
            createBagGlyph(widget)
            applyBagGlyphStyle(widget)
            return widget
        end,
        -- Baganator's documented defaultPosition parameter is
        -- { corner = "top_left", priority = N }. Using "default_position"
        -- registers an unassigned widget, so its onUpdate is never called.
        { corner = "top_left", priority = 1 }
    )
    if ok then
        baganatorRegistered = true
        baganatorRegistrationError = nil
        -- One on-demand refresh so currently open bags can show the widget.
        -- Baganator coalesces this internally; there is no periodic work.
        ns.QuestItems.RefreshBaganator()
    else
        baganatorRegistrationError = tostring(err)
    end
end
function ns.QuestItems.RefreshBaganator(force)
    if not baganatorRegistered or not baganatorAvailable()
        or (not force and not enabled("markBaganator")) then return end
    local refresh = Baganator.API.RequestItemButtonsRefresh
    if type(refresh) ~= "function" then return end
    -- Only after a quest change or toggling, not on BAG_UPDATE / every frame.
    local reason = Baganator.Constants and Baganator.Constants.RefreshReason
        and Baganator.Constants.RefreshReason.ItemWidgets
    if reason then
        pcall(refresh, { reason })
    else
        pcall(refresh)
    end
end

-- Diagnostic: point at an item in Baganator and run /qh itemdebug.
-- Only executes on demand; no tooltip scanner, bag enumeration or new event.
function ns.QuestItems.Debug()
    local active = enabled("markBaganator")
    local api = baganatorAvailable() and Baganator.API
    local cornerActive = api and type(api.IsCornerWidgetActive) == "function"
        and safe(api.IsCornerWidgetActive, "tistelti_questhelper_needed")
    local count = 0
    for _ in pairs(itemObjectives) do count = count + 1 end
    print(("|cff73c9ffQuestHelper:|r Baganator opcion=%s, API=%s, widget registrado=%s, widget visible=%s, objetivos indexados=%d")
        :format(tostring(active), tostring(api ~= nil), tostring(baganatorRegistered),
                tostring(cornerActive), count))
    print(("|cff73c9ffQuestHelper:|r Llamadas de Baganator=%d, coincidencias=%d, asociaciones nativas=%d")
        :format(baganatorChecks, baganatorMatches, nativeAssociations))
    if baganatorRegistrationError then
        print("|cff73c9ffQuestHelper:|r Error al registrar widget: " .. baganatorRegistrationError)
    end
    local link
    -- The two return values from GameTooltip:GetItem() require a direct pcall.
    if GameTooltip and type(GameTooltip.GetItem) == "function" then
        local ok, _, candidate = pcall(GameTooltip.GetItem, GameTooltip)
        if ok and readable(candidate) and type(candidate) == "string" then link = candidate end
    end
    if type(link) == "string" then
        local id = tonumber(link:match("item:(%d+)"))
        if id then
            local name = itemName(id) or "(nombre no cargado)"
            local entries = findEntries(id)
            print(("|cff73c9ffQuestHelper:|r Tooltip: %s (itemID %d), pendiente=%s")
                :format(name, id, tostring(entries ~= nil)))
        end
    else
        print("|cff73c9ffQuestHelper:|r Situa el cursor sobre el objeto antes de ejecutar /qh itemdebug.")
    end
    local listed = 0
    for key in pairs(itemObjectives) do
        if key:find("colmillo", 1, true) or key:find("necr", 1, true) then
            print("|cff73c9ffQuestHelper:|r Objetivo indexado: " .. key)
            listed = listed + 1
            if listed >= 4 then break end
        end
    end
    if active and baganatorRegistered and cornerActive == false then
        print("|cff73c9ffQuestHelper:|r Baganator tiene el widget desactivado: activalo en Opciones de Baganator > Iconos / Esquinas.")
    end
end

-- Hooks can be installed lazily once a feature is enabled. Hooksecurefunc and
-- tooltip post-calls cannot be undone, so wrappers check their individual
-- settings before doing any actual work.
local function installTooltipHook()
    if tooltipHooked or not enabled("itemTooltips") then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall,
            Enum.TooltipDataType.Item,
            function(tooltip, data)
                if enabled("itemTooltips") then pcall(tooltipPostCall, tooltip, data) end
            end)
        if ok then tooltipHooked = true end
    end
end
local function installBagHooks()
    if bagHooksInstalled or not enabled("markBags") then return end
    bagHooksInstalled = true
    local mixin = _G.ContainerFrameItemButtonMixin
    if type(mixin) == "table" and type(mixin.UpdateQuestItem) == "function"
        and type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, mixin, "UpdateQuestItem", function(button)
            if enabled("markBags") and next(itemObjectives) then
                pcall(markButton, button)
            end
        end)
    end
    if type(hooksecurefunc) == "function" then
        for _, fn in ipairs({"ToggleAllBags", "OpenAllBags", "ToggleBackpack",
                            "OpenBackpack", "ToggleBag", "OpenBag"}) do
            if type(_G[fn]) == "function" then
                pcall(hooksecurefunc, fn, function()
                    if enabled("markBags") then queueBagUpdate() end
                end)
            end
        end
    end
end

local events = CreateFrame("Frame")
local bagEvents = { "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED" }
local function syncBagEvents()
    for _, name in ipairs(bagEvents) do
        if loggedIn and enabled("markBags") then
            events:RegisterEvent(name)
        else
            events:UnregisterEvent(name)
        end
    end
end

function ns.QuestItems.RefreshAppearance(key)
    -- No inventory scan: Baganator runs our registered widget only when it
    -- refreshes its item buttons. Blizzard bag textures are already allocated.
    if key == "bagMarkerSize" then
        local size = appearanceNumber("bagMarkerSize", BAG_ICON_SIZE)
        for _, mark in pairs(marks) do mark:SetSize(size, size) end
    end
    if loggedIn and enabled("markBaganator") then
        ns.QuestItems.RefreshBaganator()
    end
end

function ns.QuestItems.RefreshSettings(key)
    if not loggedIn then return end
    syncBagEvents()
    installTooltipHook()
    installBagHooks()
    registerBaganator()
    -- Tooltip-only mode never opens/enumerates bag UI.
    if (key == "markBags" or key == "markBaganator" or key == "itemTooltips") and lastActiveObjectives then
        ns.QuestItems.ObjectivesChanged(lastActiveObjectives, lastUnknownObjectives, lastCompletedObjectives, lastJournalQuestIDs)
    end
    -- On disable, one forced refresh removes cached markers. While disabled,
    -- subsequent quest changes never trigger any more Baganator work.
    if key == "markBaganator" and not enabled("markBaganator") then
        ns.QuestItems.RefreshBaganator(true)
    end
    if not enabled("markBags") then
        needScanAfterCombat = false
        for _, mark in pairs(marks) do mark:Hide() end
    elseif key == "markBags" then
        queueBagUpdate()
    end
end

events:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_LOGIN" then
        loggedIn = true
        ns.QuestItems.RefreshSettings("markBags")
        -- If Baganator loaded before QuestHelper, it is available now.
        registerBaganator()
    elseif event == "ADDON_LOADED" then
        if arg == "Baganator" then
            registerBaganator()
            ns.QuestItems.RefreshBaganator()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if needScanAfterCombat then
            needScanAfterCombat = false
            queueBagUpdate()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Item names can be loaded asynchronously. No retry timer.
        if type(arg) == "number" then nameCache[arg] = nil end
        if next(itemObjectives) then queueBagUpdate() end
    elseif event == "BAG_UPDATE_DELAYED" then
        if next(itemObjectives) then queueBagUpdate() end
    end
end)
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
