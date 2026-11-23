-- Reordenacion visual de filas originales de Blizzard. Sin filas auxiliares.
-- NativeCapacity permite que el contenedor original construya todas las filas.
local addonName, ns = ...
local Q = C_QuestLog
local Zones = {}
ns.TrackerZones = Zones

local eventFrame = CreateFrame("Frame")
local headings = {}
local positions = setmetatable({}, { __mode = "k" })
local hiddenByUs = setmetatable({}, { __mode = "k" })
local zoneByID = {}
local cacheDirty, hooked, applying, warned = true, false, false, false
local wheelHooked, wheelTracker, oldWheelEnabled = false, nil, nil
local scrollIndex, scrollKey, scrollRows, scrollLast, totalWatches, nativeWatches = 1, nil, nil, 0, 0, 0
local lastGeometry = {}
local warnedIncomplete = false
-- Las capturas de anclajes solo son nativas si Blizzard ha sustituido las
-- coordenadas impuestas en el render anterior. Evita guardar nuestro propio
-- layout como plantilla para la siguiente actualización.
local addonPlacement = setmetatable({}, {__mode="k"})
-- Native quest item buttons may be parented elsewhere and stay at the old
-- coordinates when their owning block is visually reordered.
local itemPositions = setmetatable({}, {__mode="k"})
local function questItem(block)
    local b = block and (block.ItemButton or block.itemButton)
    if b and type(b.GetParent) == "function" and type(b.GetNumPoints) == "function"
        and type(b.SetPoint) == "function" then return b end
end

local searchButton, searchBox, searchVisible
local searchAnchor
local searchQuery, searchCorpus = "", {}
local searchClosing = false
local HEADER_HEIGHT, HEADER_TOP_GAP, HEADER_BOTTOM_GAP = 18, 9, 9

local function readable(v)
    return v ~= nil and (not issecretvalue or not issecretvalue(v))
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end
local function unsafe()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return true end
    local check = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if type(check) == "function" and safe(check) ~= false then return true end
    return false
end
local function option(key)
    return ns.Config and ns.Config.Get and ns.Config.Get(key) == true
end
local function conflictingTracker()
    -- Two addons rearranging the same native blocks will fight over anchors.
    if _G.QuestSections or _G.QuestSectionsPlus or _G.KalielsTracker
        or _G.shupaz_ForeverQuestLog then return true end
    local questie = _G.Questie
    if questie and questie.db and questie.db.profile
        and questie.db.profile.trackerEnabled then return true end
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        for _, name in ipairs({"QuestSectionsForever", "QuestSections", "QuestSectionsPlus",
            "shupaz_ForeverQuestLog", "QuestTrackerEnhanced"}) do
            if safe(C_AddOns.IsAddOnLoaded, name) == true then return true end
        end
    end
    return false
end
local function folded()
    if type(TisteltiQuestHelperCharDB) ~= "table" then TisteltiQuestHelperCharDB = {} end
    if type(TisteltiQuestHelperCharDB.trackerFoldedZones) ~= "table" then
        TisteltiQuestHelperCharDB.trackerFoldedZones = {}
    end
    return TisteltiQuestHelperCharDB.trackerFoldedZones
end
local function lower(text)
    if type(text) ~= "string" then return "" end
    text = text:lower()
    local replace = { ["Á"]="á", ["É"]="é", ["Í"]="í", ["Ó"]="ó", ["Ú"]="ú", ["Ñ"]="ñ" }
    for upper, small in pairs(replace) do text = text:gsub(upper, small) end
    return text
end
local function refreshZoneCache()
    if not cacheDirty or unsafe() then return end
    cacheDirty = false
    local result, current = {}, "Otras misiones"
    local count = safe(Q and Q.GetNumQuestLogEntries)
    if type(count) ~= "number" or count < 0 or count > 500 then
        cacheDirty = true
        return
    end
    for i = 1, count do
        local item = safe(Q.GetInfo, i)
        if type(item) == "table" then
            if readable(item.isHeader) and item.isHeader == true then
                if readable(item.title) and type(item.title) == "string" and item.title ~= "" then
                    current = item.title
                end
            elseif readable(item.questID) and type(item.questID) == "number" then
                result[item.questID] = current
            end
        end
    end
    zoneByID = result
end
local function findZone(id)
    if zoneByID[id] then return zoneByID[id] end
    local index = safe(Q and Q.GetHeaderIndexForQuest, id)
    if type(index) == "number" and index > 0 then
        local entry = safe(Q.GetInfo, index)
        if type(entry) == "table" and readable(entry.title)
            and type(entry.title) == "string" and entry.title ~= "" then
            return entry.title
        end
    end
    return "Otras misiones"
end
local function canMove(frame)
    if not frame or unsafe() then return false end
    -- These blocks must be movable without touching protected UI elements.
    if type(frame.IsProtected) == "function" and safe(frame.IsProtected, frame) == true then return false end
    return type(frame.SetPoint) == "function" and type(frame.ClearAllPoints) == "function"
end
local function readPosition(block)
    local count = safe(block.GetNumPoints, block)
    if type(count) ~= "number" or count < 1 or count > 6 then return end
    local anchors = {}
    for i = 1, count do
        local ok, point, rel, relPoint, x, y = pcall(block.GetPoint, block, i)
        if not ok then return end
        if not readable(point) or not readable(rel) or not readable(x) or not readable(y) then return end
        if relPoint ~= nil and not readable(relPoint) then return end
        anchors[#anchors + 1] = {point, rel, relPoint or point, x, y}
    end
    return anchors
end
local function itemSnapshot(block)
    local item = questItem(block)
    if not item or (type(item.IsProtected) == "function"
        and safe(item.IsProtected,item) == true) then return end
    local anchors = readPosition(item)
    if not anchors then return end
    return {button=item, questID=block.id, parent=safe(item.GetParent,item), anchors=anchors,
        left=safe(item.GetLeft,item), top=safe(item.GetTop,item),
        blockLeft=safe(block.GetLeft,block),blockTop=safe(block.GetTop,block)}
end
local function syncQuestItem(block, before)
    if not before or before.questID ~= block.id or before.button ~= questItem(block) then return end
    local item = before.button
    if not canMove(item) or not before.blockLeft or not before.blockTop then return end
    local bx,by=safe(block.GetLeft,block),safe(block.GetTop,block)
    local ix,iy=safe(item.GetLeft,item),safe(item.GetTop,item)
    if type(bx)~="number" or type(by)~="number"
        or type(ix)~="number" or type(iy)~="number"
        or type(before.left)~="number" or type(before.top)~="number" then return end
    local dx,dy=bx-before.blockLeft,by-before.blockTop
    if math.abs(dx)<0.5 and math.abs(dy)<0.5 then return end
    -- An item anchored to the block follows automatically; an item which
    -- hasn't followed is adjusted only when a simple owned anchor is available.
    if math.abs(ix-before.left-dx)<1 and math.abs(iy-before.top-dy)<1 then return end
    if math.abs(ix-before.left)>1 or math.abs(iy-before.top)>1 then return end
    if #before.anchors ~= 1 then return end
    local a=before.anchors[1]
    local content = safe(block.GetParent,block)
    if a[2] ~= block and a[2] ~= content then return end
    -- A button with a single anchor to its owner is expected to follow it.
    -- For an independently anchored button on the same content layer, apply
    -- the observed displacement. Reject ambiguous multi-anchor geometry.
    local x, y = a[4], a[5]
    if a[2] == content then x, y = x + dx, y + dy end
    local ok = pcall(item.ClearAllPoints,item)
    if ok then pcall(item.SetPoint,item,a[1],a[2],a[3],x,y) end
end
local function samePosition(a, b)
    if not a or not b or #a ~= #b then return false end
    for i, p in ipairs(a) do
        local q = b[i]
        for j = 1, 5 do
            if type(p[j]) == "number" and type(q[j]) == "number" then
                if math.abs(p[j] - q[j]) > 0.001 then return false end
            elseif p[j] ~= q[j] then return false end
        end
    end
    return true
end
local function rememberPosition(block)
    local anchors = readPosition(block)
    if not anchors then return end
    -- GetPoint redondea a float en el cliente. No realimentar ese redondeo
    -- ni capturar nuestro TOP como si fuera un nuevo layout de Blizzard.
    local placed = addonPlacement[block]
    if placed and placed.id == block.id and samePosition(anchors, placed) then return end
    anchors.id = block.id
    positions[block] = anchors
    addonPlacement[block] = nil
end
local function nativeVerticalAnchor(block, content)
    local top, left, right
    for i, a in ipairs(positions[block] or {}) do
        if a[1] == "TOP" and not top and type(a[4]) == "number" then top = i
        elseif a[1] == "LEFT" and not left and a[2] == content and a[3] == "LEFT"
            and type(a[4]) == "number" then left = i
        elseif a[1] == "RIGHT" and not right and a[2] == content and a[3] == "RIGHT" then right = i
        else return nil end
    end
    -- AnchorBlock de 1.60.1: TOP + LEFT + RIGHT (sin RIGHT si fixedWidth).
    -- Una geometría desconocida no se convierte en un rectángulo inventado.
    if top and left then return top, left end
end
local function restorePosition(block)
    if not canMove(block) then return end
    local anchors = positions[block]
    if anchors and (block.used ~= true or block.id ~= anchors.id) then
        positions[block], addonPlacement[block], hiddenByUs[block] = nil, nil, nil
        return
    end
    local itemBefore = itemSnapshot(block)
    if anchors then
        block:ClearAllPoints()
        for _, a in ipairs(anchors) do
            block:SetPoint(a[1], a[2], a[3], a[4], a[5])
        end
    end
    if hiddenByUs[block] then
        if readable(block.used) and block.used == true then block:Show() end
        hiddenByUs[block] = nil
    end
    addonPlacement[block] = nil
    syncQuestItem(block,itemBefore)
end
local function hideHeadings()
    for _, head in ipairs(headings) do head.frame:Hide() end
end
local refreshVisual -- forward reference for local heading click handlers
-- Las zonas toman la tipografia y color del titulo nativo "Misiones".
-- Solo afecta a elementos creados por el addon.
local function headingFont(text)
    local tracker = _G.QuestObjectiveTracker
    local label = tracker and tracker.Header and tracker.Header.Text
    local font = label and type(label.GetFontObject) == "function"
        and safe(label.GetFontObject, label) or _G.GameFontNormal
    if font then text:SetFontObject(font) end
end
local function headingColor(text, arrow, highlighted)
    local color = highlighted and _G.HIGHLIGHT_FONT_COLOR or _G.NORMAL_FONT_COLOR
    local r,g,b = 1, 0.82, 0
    if color and type(color.GetRGB) == "function" then
        local ok, a, c, d = pcall(color.GetRGB, color)
        if ok and type(a) == "number" then r,g,b = a,c,d end
    end
    text:SetTextColor(r,g,b)
    arrow:SetVertexColor(r,g,b)
end
local function heading(parent, index)
    local record = headings[index]
    if record then return record end
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(200, HEADER_HEIGHT)
    button:RegisterForClicks("LeftButtonUp")
    -- Igual que el original: el icono ocupa el margen izquierdo, pero el
    -- encabezado completo sigue siendo pulsable.
    if button.SetHitRectInsets then button:SetHitRectInsets(-16, 0, 0, 0) end
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", button, "LEFT", 7, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    text:SetJustifyH("LEFT")
    text:SetMaxLines(1)
    if text.SetWordWrap then text:SetWordWrap(false) end
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end

    -- Mismo anclaje del indicador del QuestHelper original; la flecha es
    -- una textura TGA para evitar los glifos + y -.
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", text, "LEFT", -4, 0)
    headingFont(text)
    headingColor(text, arrow, false)
    record = {frame = button, text = text, arrow = arrow, hovered = false}
    headings[index] = record
    button:SetScript("OnEnter", function()
        record.hovered = true
        headingColor(text, arrow, true)
    end)
    button:SetScript("OnLeave", function()
        record.hovered = false
        headingColor(text, arrow, false)
    end)
    button:SetScript("OnClick", function()
        if unsafe() or not record.zone then return end
        local current = folded()
        current[record.zone] = not current[record.zone] or nil
        refreshVisual(false)
    end)
    button:Hide()
    return record
end
-- Only our own heading texture is changed; no Blizzard widget is modified.
local function setHeadingArrow(rec, collapsed)
    rec.arrow:SetTexture(collapsed
        and "Interface\\AddOns\\TisteltiUtils_QuestHelper\\media\\ArrowRight"
        or "Interface\\AddOns\\TisteltiUtils_QuestHelper\\media\\ArrowDown")
end

local function searchMatches(id, block)
    if searchQuery == "" then return true end
    local corpus = searchCorpus[id]
    if not corpus then
        local parts = {}
        local title = safe(Q and Q.GetTitleForQuestID, id) or
            (block.HeaderText and safe(block.HeaderText.GetText, block.HeaderText))
        if type(title) == "string" then parts[#parts + 1] = title end
        local logIndex = safe(Q and Q.GetLogIndexForQuestID, id)
        if type(logIndex) == "number" and logIndex > 0 and type(GetQuestLogQuestText) == "function" then
            local ok, description, logText = pcall(GetQuestLogQuestText, logIndex)
            if ok then
                if readable(description) and type(description) == "string" then
                    parts[#parts + 1] = description
                end
                if readable(logText) and type(logText) == "string" then
                    parts[#parts + 1] = logText
                end
            end
        end
        local objectives = safe(Q and Q.GetQuestObjectives, id)
        if type(objectives) == "table" then
            for _, obj in ipairs(objectives) do
                if type(obj) == "table" and readable(obj.text)
                    and type(obj.text) == "string" then parts[#parts + 1] = obj.text end
            end
        end
        corpus = lower(table.concat(parts, "\n"))
        searchCorpus[id] = corpus
    end
    return corpus:find(searchQuery, 1, true) ~= nil
end
local function collectRendered(tracker)
    local count = safe(Q and Q.GetNumQuestWatches)
    if type(count) ~= "number" or count < 0 or count > 100 then return {} end
    totalWatches = count
    local result, seen = {}, {}
    for i = 1, count do
        local id = safe(Q.GetQuestIDForQuestWatchIndex, i)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            local block = safe(tracker.GetExistingBlock, tracker, id)
            if block and readable(block.id) and block.id == id and block.HeaderText
                and readable(block.used) and block.used == true then
                result[#result+1]={id=id,block=block,zone=findZone(id),original=i}
            end
        end
    end
    nativeWatches = #result
    return result
end
function Zones.NeedsCapacity()
    return not conflictingTracker() and option("trackerScrollBeta") and
        (option("trackerZoneSections") or searchQuery ~= "" or
        (ns.TrackerSort and ns.TrackerSort.IsActive and ns.TrackerSort.IsActive()))
end
-- Reflow ONLY the blocks created by the native tracker on this layout pass.
-- Unlike the 0.7.42-0.7.46 fallback modes, this never guesses a capacity
-- from ContentsFrame:GetHeight() (which is the *used*, not available height),
-- and it never leaves a header anchored to a discarded quest block.
local function render(tracker, fromNative)
    if applying or unsafe() or not tracker or not tracker.ContentsFrame then return end
    if ns.TurnInFilter and ns.TurnInFilter.IsSwapping
        and ns.TurnInFilter.IsSwapping() then return end
    if safe(tracker.IsCollapsed, tracker) == true or
        (tracker.parentContainer and safe(tracker.parentContainer.IsCollapsed, tracker.parentContainer) == true) then
        hideHeadings()
        scrollRows, lastGeometry = nil, {}
        return
    end
    if conflictingTracker() then
        hideHeadings()
        for block in pairs(positions) do restorePosition(block) end
        return
    end
    applying = true
    if ns.Diagnostics then ns.Diagnostics.Capture("before-addon") end
    local content = tracker.ContentsFrame
    local wantZones = option("trackerZoneSections")
    local wantOrder = ns.TrackerSort and ns.TrackerSort.IsActive and ns.TrackerSort.IsActive() or false
    if not wantZones and not wantOrder and searchQuery == "" then
        hideHeadings()
        for block in pairs(positions) do restorePosition(block) end
        scrollRows, scrollIndex, scrollKey, scrollLast, lastGeometry = nil, 1, nil, 0, {}
        applying = false
        return
    end
    refreshZoneCache()
    local entries = collectRendered(tracker)
    -- A block that Blizzard has not used this frame must NEVER be recycled into
    -- our visual layout. Previously hidden blocks are eligible only when the
    -- native pass has marked them used again.
    local actual = {}
    for _, e in ipairs(entries) do
        local block = e.block
        local used = readable(block.used) and block.used == true
        if used and canMove(block) then
            actual[#actual + 1] = e
        end
    end
    if #actual == 0 then
        hideHeadings()
        scrollRows, scrollIndex, scrollKey, scrollLast, lastGeometry = nil, 1, nil, 0, {}
        if ns.NativeCapacity then ns.NativeCapacity.FitVisible(tracker, 0) end
        applying = false
        return
    end
    for _, e in ipairs(actual) do
        rememberPosition(e.block)
        if not positions[e.block] then
            hideHeadings()
            applying = false
            return
        end
    end
    if ns.TrackerSort and ns.TrackerSort.Order then
        ns.TrackerSort.Order(actual, wantZones)
    end
    local collapsedZones = folded()
    local rows, lastZone = {}, nil
    for _, e in ipairs(actual) do
        if searchMatches(e.id, e.block) then
            if wantZones and lastZone ~= e.zone then
                rows[#rows + 1] = {type="heading", zone=e.zone}
                lastZone = e.zone
            end
            if not wantZones or not collapsedZones[e.zone] or searchQuery ~= "" then
                rows[#rows + 1] = {type="quest", entry=e}
            end
        end
    end
    -- Medidas para paginar, nunca para imponer tamaño a los bloques nativos.
    local nativeRects = {}
    for _, e in ipairs(actual) do
        local b = e.block
        local w, h = safe(b.GetWidth, b), safe(b.GetHeight, b)
        if type(h) ~= "number" or h < 8 then
            h = readable(b.height) and type(b.height) == "number" and b.height or nil
        end
        if type(w) ~= "number" or w < 40 or type(h) ~= "number" or h < 8 then
            hideHeadings()
            for block in pairs(positions) do restorePosition(block) end
            applying = false
            return
        end
        local top, left = nativeVerticalAnchor(b, content)
        if not top then
            hideHeadings()
                for block in pairs(positions) do restorePosition(block) end
            scrollRows, scrollIndex, scrollKey, scrollLast, lastGeometry = nil, 1, nil, 0, {}
            applying = false
            return
        end
        nativeRects[b] = {width = w, height = h, top = top, left = left}
    end

    -- Solo se cuentan bloques existentes, usados y con el mismo ID.
    local paging = option("trackerScrollBeta") and #actual > 0
    local capacityState = ns.NativeCapacity and ns.NativeCapacity.GetState()
    local awaitingBuild = capacityState and capacityState.enabled and
        type(tracker.availableHeight)=="number" and tracker.availableHeight < capacityState.base
    if fromNative and option("trackerScrollBeta") and not awaitingBuild and #actual ~= totalWatches and not warnedIncomplete then
        warnedIncomplete = true
        print("|cff73c9ffQuestHelper:|r Blizzard ha construido " .. nativeWatches .. "/" ..
            totalWatches .. " misiones. Faltan filas nativas; /tqhdiag full conserva el detalle.")
    end
    if #actual == totalWatches then warnedIncomplete=false end
    local viewHeight = ns.NativeCapacity and ns.NativeCapacity.GetViewHeight(tracker)
    if paging and viewHeight == nil then
        -- availableHeight es solo lectura; nunca se escribe en Edit Mode.
        local candidate = readable(tracker.availableHeight) and tracker.availableHeight
        if type(candidate) == "number" and candidate > 40 and candidate < 3000 then
            local top, contentTop = safe(tracker.GetTop, tracker), safe(content.GetTop, content)
            local inset = type(top) == "number" and type(contentTop) == "number" and top - contentTop
                or (readable(tracker.headerHeight) and tracker.headerHeight)
            if type(inset) == "number" and inset >= 0 and inset < candidate then
                viewHeight = candidate - inset
            end
        else
            local overall = safe(tracker.GetHeight, tracker)
            local header = tracker.Header
            local headerHeight = header and safe(header.GetHeight, header)
            if type(overall) == "number" and overall > 70 and overall < 3000 then
                viewHeight = overall - (type(headerHeight) == "number" and headerHeight or 28) - 10
            end
        end
        if not viewHeight then paging = false end
    end
    local startIndex = 1
    if paging and #rows > 1 then
        startIndex = math.min(math.max(scrollIndex, 1), #rows)
        if scrollKey then
            for i, row in ipairs(rows) do
                local key = row.type == "heading" and "zone:" .. row.zone
                    or "quest:" .. tostring(row.entry.id)
                if key == scrollKey then startIndex = i; break end
            end
        end
    end
    local contentWidth = safe(content.GetWidth, content) or 235
    local questGap = readable(tracker.fromBlockOffsetY) and tracker.fromBlockOffsetY
    questGap = type(questGap) == "number" and math.max(0, -questGap) or 10
    local headerGap = readable(tracker.fromHeaderOffsetY) and tracker.fromHeaderOffsetY
    headerGap = type(headerGap) == "number" and math.max(0, -headerGap) or 10
    local y, headingsUsed, visible, lastDrawn = headerGap, 0, {}, startIndex - 1
    local managed = {}
    for _, e in ipairs(actual) do managed[e.block]=true end
    if type(tracker.usedBlocks)=="table" then
        for _, blocks in pairs(tracker.usedBlocks) do
            for _, b in pairs(blocks) do
                if b.used==true and not managed[b] and safe(b.IsShown,b)==true then
                    local top, h=safe(b.GetTop,b),safe(b.GetHeight,b)
                    local contentTop=safe(content.GetTop,content)
                    if type(top)=="number" and type(h)=="number" and type(contentTop)=="number" then
                        y=math.max(y,contentTop-top+h+questGap)
                    end
                end
            end
        end
    end
    -- Cuando empieza una pagina a mitad de zona, mostrar su encabezado
    -- sin repetirlo dentro de la misma pagina.
    local previousZone
    if paging and rows[startIndex] and rows[startIndex].type == "quest" and wantZones then
        previousZone = rows[startIndex].entry.zone
    end
    local function drawHeading(zone)
        local gap = headingsUsed == 0 and 0 or HEADER_TOP_GAP
        headingsUsed = headingsUsed + 1
        local rec = heading(content, headingsUsed)
        rec.zone = zone
        rec.text:SetText(zone)
        headingFont(rec.text)
        headingColor(rec.text, rec.arrow, rec.hovered)
        setHeadingArrow(rec, collapsedZones[zone] and searchQuery == "")
        rec.frame:ClearAllPoints()
        rec.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + gap))
        rec.frame:SetWidth(math.max(70, contentWidth - 10))
        rec.frame:Show()
        y = y + gap + HEADER_HEIGHT + HEADER_BOTTOM_GAP
    end
    if previousZone and (not paging or y+HEADER_HEIGHT+HEADER_BOTTOM_GAP <= viewHeight) then drawHeading(previousZone) end
    lastGeometry = {}
    for i = startIndex, #rows do
        local row = rows[i]
        local isHeading = row.type == "heading"
        local rect = not isHeading and nativeRects[row.entry.block]
        local required = isHeading and (HEADER_HEIGHT + HEADER_BOTTOM_GAP +
            (headingsUsed == 0 and 0 or HEADER_TOP_GAP))
            or (rect and rect.height + questGap or 0)
        if paging and viewHeight and y + required > viewHeight then
            break
        end
        if isHeading then
            -- No dejar un titulo huerfano al final de una pagina.
            local nextRow = rows[i + 1]
            local nextRect = nextRow and nextRow.type == "quest"
                and nativeRects[nextRow.entry.block]
            if paging and nextRect and y + required + nextRect.height + questGap > viewHeight then
                break
            end
            drawHeading(row.zone)
        elseif rect then
            local b = row.entry.block
            -- Solo la referencia vertical del bloque. Regiones, anchuras,
            -- alturas, callbacks e iconos siguen siendo los de Blizzard.
            local anchors = positions[b]
            local itemBefore = itemSnapshot(b)
            b:ClearAllPoints()
            for j, a in ipairs(anchors) do
                if j == rect.top then
                    b:SetPoint("TOPLEFT", content, "TOPLEFT", anchors[rect.left][4], -y)
                else b:SetPoint(a[1], a[2], a[3], a[4], a[5]) end
            end
            local placed = readPosition(b)
            if placed then placed.id = b.id end
            addonPlacement[b] = placed
            syncQuestItem(b,itemBefore)
            if safe(b.IsShown, b) ~= true then b:Show() end
            hiddenByUs[b] = nil
            visible[b] = true
            lastGeometry[#lastGeometry + 1] = {id = row.entry.id, y = y,
                width = rect.width, height = rect.height}
            y = y + rect.height + questGap
        end
        lastDrawn = i
    end
    for _, e in ipairs(actual) do
        if not visible[e.block] then
            if safe(e.block.IsShown, e.block) == true then e.block:Hide() end
            hiddenByUs[e.block] = true
        end
    end
    for i = headingsUsed + 1, #headings do headings[i].frame:Hide() end
    if ns.NativeCapacity and paging then ns.NativeCapacity.FitVisible(tracker, y) end
    scrollRows, scrollLast = paging and rows or nil, lastDrawn
    scrollIndex = startIndex
    local first = rows[startIndex]
    scrollKey = paging and first and (first.type == "heading" and "zone:" .. first.zone
        or "quest:" .. tostring(first.entry.id)) or nil
    -- Los resaltados se repintan despues de ocultar/mostrar; asi no dependen
    -- del orden de registro de los hooks EndLayout entre modulos.
    if ns.RecentQuests and ns.RecentQuests.RepaintRendered then
        ns.RecentQuests.RepaintRendered()
    end
    applying = false
    if ns.Diagnostics then ns.Diagnostics.Capture("after-addon") end
end
refreshVisual = function(fromNative)
    if unsafe() then return end
    local tracker = _G.QuestObjectiveTracker
    if tracker then
        if ns.NativeCapacity then ns.NativeCapacity.Initialize(tracker, refreshVisual) end
        render(tracker, fromNative)
    end
end
local function installHooks()
    if hooked or type(hooksecurefunc) ~= "function" then return end
    local tracker = _G.QuestObjectiveTracker
    if not tracker or type(tracker.GetExistingBlock) ~= "function" then return end
    local method = type(tracker.EndLayout) == "function" and "EndLayout"
        or (type(tracker.LayoutContents) == "function" and "LayoutContents")
    if not method then return end
    local ok = pcall(hooksecurefunc, tracker, method, function(self)
        if not unsafe() then refreshVisual(true) end
    end)
    if ok then hooked = true end
end
local function makeSearch()
    if searchButton then
        searchButton:SetShown(option("trackerSearchButton"))
        return
    end
    if not option("trackerSearchButton") or unsafe() then return end
    local tracker = _G.QuestObjectiveTracker
    local header = tracker and tracker.Header
    local minimize = header and header.MinimizeButton
    if not header or not minimize or not header.Text then return end
    local btn = CreateFrame("Button", nil, header)
    btn:SetSize(20, 20)
    btn:SetPoint("RIGHT", searchAnchor or minimize, "LEFT", -6, 0)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(15, 15)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    local ok, field = pcall(CreateFrame, "EditBox", nil, header, "SearchBoxNineSliceTemplate")
    if not ok or not field then btn:Hide(); return end
    field:SetHeight(20)
    field:SetPoint("LEFT", header, "LEFT", 7, 0)
    field:SetPoint("RIGHT", btn, "LEFT", -5, 0)
    field:SetMaxLetters(64)
    field:SetAutoFocus(false)
    field:Hide()
    searchButton, searchBox = btn, field
    local function closeSearch()
        if searchClosing or not searchVisible then return end
        searchClosing = true
        searchVisible = false
        field:ClearFocus()
        field:SetText("")
        field:Hide()
        header.Text:Show()
        searchQuery, searchCorpus = "", {}
        searchClosing = false
        refreshVisual(false)
    end
    -- Conservar el manejador de la plantilla: actualiza Buscar, la lupa y
    -- el boton de borrado antes de aplicar nuestro filtro.
    field:HookScript("OnTextChanged", function(self)
        if searchClosing then return end
        local value = lower((self:GetText() or ""):match("^%s*(.-)%s*$"))
        if value ~= searchQuery then
            searchQuery, searchCorpus = value, {}
            refreshVisual(false)
        end
        -- El clic en borrar puede quitar el foco antes de vaciar el campo.
        -- En ese orden no llega un segundo OnEditFocusLost.
        if searchVisible and value == "" and not self:HasFocus() then closeSearch() end
    end)
    if field.clearButton then
        field.clearButton:HookScript("OnClick", closeSearch)
    end
    local closeOnClick = false
    field:HookScript("OnEditFocusLost", function()
        if searchVisible and (searchQuery == "" or not option("trackerSearchKeepOnBlur")) then
            -- En este cliente el blur precede incluso a OnMouseDown.
            if btn:IsMouseOver() and IsMouseButtonDown("LeftButton") then closeOnClick = true end
            closeSearch()
        end
    end)
    field:SetScript("OnEscapePressed", closeSearch)
    field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    btn:SetScript("OnMouseDown", function() closeOnClick = closeOnClick or searchVisible end)
    btn:SetScript("OnClick", function()
        if unsafe() then return end
        -- El blur puede haber cerrado el campo entre MouseDown y Click.
        local shouldClose = closeOnClick or searchVisible
        closeOnClick = false
        if shouldClose then closeSearch() else
            searchVisible = true
            header.Text:Hide()
            field:Show()
            field:SetFocus()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Buscar misiones visibles en el seguimiento")
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        closeOnClick = false
        if GameTooltip then GameTooltip:Hide() end
    end)
end
-- Position the existing magnifier beside independent tracker controls.
-- Only our magnifier is moved; Blizzard's header and minimise button are untouched.
function Zones.PositionSearchBefore(anchor)
    searchAnchor = anchor
    local tracker = _G.QuestObjectiveTracker
    local minimize = tracker and tracker.Header and tracker.Header.MinimizeButton
    if searchButton and (anchor or minimize) then
        searchButton:ClearAllPoints()
        searchButton:SetPoint("RIGHT", anchor or minimize, "LEFT", -6, 0)
    end
end
-- Enganchar la rueda exclusivamente al modulo nativo, sin modificar su
-- enumerador ni invocar MarkDirty/Update/LayoutContents desde Lua inseguro.
local function configureWheel()
    local tracker = _G.QuestObjectiveTracker
    if not tracker or unsafe() then return end
    local target = tracker
    if type(target.IsProtected) == "function" and safe(target.IsProtected,target)==true then
        target=tracker.ContentsFrame
        if not target or (type(target.IsProtected)=="function"
            and safe(target.IsProtected,target)==true) then return end
    end
    if type(target.EnableMouseWheel)~="function" then return end
    if wheelHooked then
        if wheelTracker==target and oldWheelEnabled~=nil then
            pcall(target.EnableMouseWheel,target,
                option("trackerScrollBeta") or oldWheelEnabled)
        end
        return
    end
    if type(target.GetScript)~="function" or type(target.HookScript)~="function" then return end
    -- Respeto al scroll que ya tenga el cliente u otro addon.
    -- HookScript preserves any existing handler. A handler already attached to
    -- the same target may also scroll; avoid double movement by using our own
    -- listener only on a separate, unclaimed ContentsFrame when possible.
    if safe(target.GetScript,target,"OnMouseWheel") then
        local content=tracker.ContentsFrame
        if content and content ~= target and canMove(content)
            and type(content.HookScript)=="function"
            and type(content.EnableMouseWheel)=="function"
            and not safe(content.GetScript,content,"OnMouseWheel") then
            target=content
        else return end
    end
    oldWheelEnabled = type(target.IsMouseWheelEnabled)=="function"
        and safe(target.IsMouseWheelEnabled,target)==true or false
    local ok = pcall(target.HookScript,target,"OnMouseWheel",function(self,delta)
        if unsafe() or self ~= wheelTracker or not option("trackerScrollBeta")
            or not scrollRows or type(delta) ~= "number" then return end
        local step = delta > 0 and -1 or 1
        local index = scrollIndex + step
        if index < 1 or index > #scrollRows then return end
        if step > 0 and scrollLast >= #scrollRows then return end
        scrollIndex, scrollKey = index, nil
        refreshVisual(false)
    end)
    if ok then
        wheelHooked,wheelTracker=true,target
        pcall(target.EnableMouseWheel,target,
            option("trackerScrollBeta") or oldWheelEnabled)
    end
end

local scheduled = false
local function scheduleVisual()
    if scheduled or unsafe() then return end
    if C_Timer and type(C_Timer.After) == "function" then
        scheduled = true
        C_Timer.After(0.05, function()
            scheduled = false
            installHooks()
            configureWheel()
            refreshVisual(false)
        end)
    else
        refreshVisual(false)
    end
end
function Zones.Initialize()
    installHooks()
    makeSearch()
    configureWheel()
    for _, name in ipairs({"PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
        "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED"}) do
        pcall(eventFrame.RegisterEvent, eventFrame, name)
    end
    scheduleVisual()
end
function Zones.RefreshAfterWatchSwap()
    -- El antiguo scrollKey apuntaba a una instantánea diferente de watches.
    scrollIndex, scrollKey, scrollRows = 1, nil, nil
    scheduleVisual()
end
function Zones.RefreshSettings(key)
    if key == "trackerSearchButton" then
        makeSearch()
        if not option("trackerSearchButton") and searchVisible and searchBox then
            searchVisible = false
            searchQuery, searchCorpus = "", {}
            searchBox:ClearFocus()
            searchBox:Hide()
            local tracker = _G.QuestObjectiveTracker
            if tracker and tracker.Header and tracker.Header.Text then tracker.Header.Text:Show() end
        end
    elseif key == "trackerScrollBeta" then
        scrollIndex, scrollKey = 1, nil
        configureWheel()
    end
    scheduleVisual()
end
-- Diagnóstico a demanda: permite distinguir en el juego si Blizzard
-- está entregando un bloque real o una fila auxiliar para cada questID.
-- No muta ni el diario ni el rastreador.
function Zones.Diagnose()
    if unsafe() then print("|cff73c9ffQuestHelper:|r diagnóstico no disponible en combate/estado secreto") return end
    local tracker = _G.QuestObjectiveTracker
    if not tracker or not Q then return end
    local count = safe(Q.GetNumQuestWatches)
    if type(count) ~= "number" then return end
    print("|cff73c9ffQuestHelper:|r diag — watches=" .. count ..
        " modo=" .. tostring(ns.TrackerSort and ns.TrackerSort.Mode and ns.TrackerSort.Mode()) ..
        " filtro=" .. tostring(ns.TurnInFilter and ns.TurnInFilter.IsActive and ns.TurnInFilter.IsActive()))
    for i = 1, math.min(25, count) do
        local id = safe(Q.GetQuestIDForQuestWatchIndex, i)
        if type(id) == "number" then
            local b = safe(tracker.GetExistingBlock, tracker, id)
            local isNative = b and readable(b.used) and b.used == true
                and (not readable(b.id) or type(b.id) ~= "number" or b.id == id)
            local source = isNative and "N" or "?"
            local level = safe(Q.GetQuestDifficultyLevel, id)
            local title = safe(Q.GetTitleForQuestID, id)
            print(("%d. [%s] %s lvl=%s ready=%s %s")
                :format(i, source, tostring(id), tostring(level),
                    tostring(ns.QuestStatus and ns.QuestStatus.IsReady(id)),
                    type(title)=="string" and title or "(titulo no disponible)"))
        end
    end
end
-- Lectura del estado real; no reconstruye filas ni confunde auxiliares con nativas.
function Zones.GetDiagnosticState()
    local auxiliary, geometry = {}, {}
    for i, row in ipairs(lastGeometry) do
        geometry[i] = {id=row.id, y=row.y, width=row.width, height=row.height}
    end
    local collapsed = {}
    local saved = type(TisteltiQuestHelperCharDB) == "table" and TisteltiQuestHelperCharDB.trackerFoldedZones
    if type(saved) == "table" then
        for zone, value in pairs(saved) do if value == true then collapsed[#collapsed + 1] = zone end end
        table.sort(collapsed)
    end
    return {index=scrollIndex, last=scrollLast, rows=scrollRows and #scrollRows or 0,
        key=scrollKey, query=searchQuery, native=nativeWatches, watches=totalWatches,
        auxiliary=auxiliary, geometry=geometry, collapsed=collapsed,
        capacity=ns.NativeCapacity and ns.NativeCapacity.GetState()}
end
function Zones.Debug()
    local count = 0
    for _ in pairs(zoneByID) do count = count + 1 end
    print(("|cff73c9ffTisteltiUtils QuestHelper:|r Zonas=%s, orden=%s, hook seguro=%s, misiones indexadas=%d, bloques nativos=%d/%d, scroll=%s")
        :format(tostring(option("trackerZoneSections")),
            tostring(ns.TrackerSort and ns.TrackerSort.Mode and ns.TrackerSort.Mode()),
            tostring(hooked), count, nativeWatches, totalWatches, tostring(scrollRows ~= nil)))
end
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        hideHeadings()
        return
    end
    if event ~= "PLAYER_REGEN_ENABLED" then cacheDirty = true end
    searchCorpus = {}
    if event == "PLAYER_ENTERING_WORLD" then installHooks(); makeSearch(); configureWheel() end
    if not unsafe() then scheduleVisual() end
end)
