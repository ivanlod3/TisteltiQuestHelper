-- Observador local optativo. Solo lee Blizzard; no llama a layout ni a watches.
-- Datos en memoria: exportar antes de /reload. No añade SavedVariables.
local _, ns = ...
local D = {}
ns.Diagnostics = D
local active, busy, serial, generation = false, false, 0, 0
local samples, identities, native, hooked = {}, {}, {}, {}
local pending, dropped, failure = false, 0, nil
local recentEvents, MAX_RECENT = {}, 60
function D.IsActive() return active end
function D.RecordRecent(id, kind, reason, before, after)
    if not active then return end
    local record = "RECENT\tquest=" .. tostring(id) .. "\tkind=" .. tostring(kind)
        .. "\treason=" .. tostring(reason) .. "\tbefore=" .. tostring(before)
        .. "\tafter=" .. tostring(after)
    if #recentEvents >= MAX_RECENT then table.remove(recentEvents,1) end
    recentEvents[#recentEvents+1] = record
end
local MAX_SAMPLES = 100
local events = CreateFrame("Frame")
local function readable(v) return not issecretvalue or not issecretvalue(v) end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end
local function field(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok and readable(value) then return value end
end
local function text(v)
    if not readable(v) then return "<secret>" end
    if v == nil then return "-" end
    return (tostring(v):gsub("[\r\n\t]", " "):gsub("|", "/"))
end
local function permitted()
    if InCombatLockdown and safe(InCombatLockdown) ~= false then return false end
    local f = C_Secrets and C_Secrets.ShouldAurasBeSecret
    return not f or safe(f) == false
end
local function identify(frame)
    if not frame then return "nil" end
    if type(frame) == "string" then return frame end
    if not identities[frame] then serial = serial + 1; identities[frame] = serial end
    local name = safe(field(frame, "GetName"), frame)
    return (name or "frame") .. "#" .. identities[frame]
end
local function rect(frame)
    if not frame then return "-" end
    local out = {}
    for _, key in ipairs({"GetLeft", "GetTop", "GetWidth", "GetHeight", "GetEffectiveScale", "IsShown", "IsVisible"}) do
        out[#out + 1] = text(safe(field(frame, key), frame))
    end
    return table.concat(out, ",")
end
local function anchors(frame)
    local n = safe(field(frame, "GetNumPoints"), frame)
    if type(n) ~= "number" or n < 0 or n > 10 then return "?" end
    local out = {}
    for i = 1, n do
        local ok, p, rel, rp, x, y = pcall(frame.GetPoint, frame, i)
        if ok and readable(p) and readable(rel) and readable(rp) and readable(x) and readable(y) then
            out[#out + 1] = table.concat({text(p), identify(rel), text(rp), text(x), text(y)}, ",")
        else out[#out + 1] = "<unreadable>" end
    end
    return table.concat(out, ";")
end
local function blockInfo(frame)
    if not frame then return "absent" end
    local ref = native[frame]
    return table.concat({identify(frame), "id=" .. text(field(frame, "id")),
        "used=" .. text(field(frame, "used")), "protected=" .. text(safe(field(frame,"IsProtected"),frame)), "rect=" .. rect(frame),
        "anchors=" .. anchors(frame), "generation=" .. text(ref and ref.generation),
        "nativeID=" .. text(ref and ref.id), "released=" .. text(ref and ref.released),
        "nativeRect=" .. text(ref and ref.rect), "nativeAnchors=" .. text(ref and ref.anchors),
        "nativeTitle=" .. text(ref and ref.title)}, "\t")
end
local function appendRegion(out, name, frame, owner)
    if frame then out[#out + 1] = name .. "\t" .. identify(frame)
        .. "\tparent=" .. identify(safe(field(frame,"GetParent"),frame))
        .. "\towner=" .. text(owner) .. "\t" .. rect(frame)
        .. "\t" .. anchors(frame) end
end
local function detail(out, frame)
    appendRegion(out, "title", field(frame, "HeaderText"))
    appendRegion(out, "poi", field(frame, "poiButton") or field(frame, "POIButton"))
    appendRegion(out, "ItemButton", field(frame, "ItemButton") or field(frame,"itemButton"), field(frame,"id"))
    local lines = field(frame, "usedLines")
    if type(lines) == "table" then
        local count = 0
        for key, line in pairs(lines) do
            count = count + 1
            if count > 40 then break end
            if type(line) == "table" or type(line) == "userdata" then
                appendRegion(out, "objective:" .. text(key), line)
                appendRegion(out, "objectiveText:" .. text(key), field(line, "Text"))
            end
        end
    end
end
local function snapshot(label)
    local out = {"SNAP\t" .. text(GetTime and GetTime()) .. "\t" .. text(label)}
    if not permitted() then out[#out + 1] = "SKIP\tcombat/secret"; return table.concat(out, "\n") end
    local tracker, Q = _G.QuestObjectiveTracker, C_QuestLog
    local state = ns.TrackerZones and ns.TrackerZones.GetDiagnosticState and ns.TrackerZones.GetDiagnosticState() or {}
    local saved = type(TisteltiQuestHelperCharDB) == "table" and TisteltiQuestHelperCharDB.turnInWatchSwap
    out[#out + 1] = "STATE\tfilter=" .. text(saved and saved.mode) .. "\tswapping=" .. text(ns.TurnInFilter and ns.TurnInFilter.IsSwapping())
        .. "\tindex=" .. text(state.index) .. "\tlast=" .. text(state.last) .. "\trows=" .. text(state.rows)
        .. "\tkey=" .. text(state.key) .. "\tquery=" .. text(state.query)
        .. "\tcachedNative=" .. text(state.native) .. "\tsort=" .. text(ns.TrackerSort and ns.TrackerSort.Mode())
        .. "\tfolded=" .. table.concat(state.collapsed or {}, ",")
    out[#out + 1] = "TRACKER\t" .. rect(tracker) .. "\tavailable=" .. text(field(tracker, "availableHeight"))
        .. "\tcontents=" .. text(field(tracker, "contentsHeight")) .. "\tstate=" .. text(field(tracker, "state"))
        .. "\tskipped=" .. text(field(tracker, "hasSkippedBlocks"))
    appendRegion(out, "contentsFrame", field(tracker, "ContentsFrame"))
    if state.capacity then
        local c=state.capacity
        out[#out+1]="CAPACITY\tenabled=" .. text(c.enabled) .. "\treason=" .. text(c.reason)
            .. "\tbase=" .. text(c.base) .. "\texpanded=" .. text(c.expanded) .. "\tview=" .. text(c.view)
    end
    if tracker and issecurevariable then
        for _, key in ipairs({"EnumQuestWatchData", "BuildQuestWatchInfos", "isDirty", "availableHeight", "contentsHeight", "state", "usedBlocks"}) do
            local ok, secure, source = pcall(issecurevariable, tracker, key)
            if ok then out[#out+1] = "SECURITY\t" .. key .. "\t" .. text(secure) .. "\t" .. text(source) end
        end
        local parent=field(tracker,"parentContainer")
        if parent then
            for _, key in ipairs({"Update", "GetAvailableHeight", "dirtyCallback", "dirty"}) do
                local ok, secure, source=pcall(issecurevariable,parent,key)
                if ok then out[#out+1]="SECURITY\tcontainer." .. key .. "\t" .. text(secure) .. "\t" .. text(source) end
            end
        end
    end
    local ids, watched, count = {}, {}, safe(Q and Q.GetNumQuestWatches)
    if type(count) ~= "number" or count < 0 or count > 100 then out[#out + 1] = "WATCHES\tunreadable"; return table.concat(out,"\n") end
    for i = 1, count do
        local id = safe(Q.GetQuestIDForQuestWatchIndex, i)
        if type(id) == "number" then ids[#ids + 1] = id; watched[id] = i end
    end
    if saved and type(saved.original) == "table" then
        for _, id in ipairs(saved.original) do if type(id) == "number" and not watched[id] then ids[#ids + 1] = id end end
        out[#out + 1] = "ORIGINAL\t" .. table.concat(saved.original, ",")
    end
    local used, auxShown = 0, 0
    for _, id in ipairs(ids) do
        local b = safe(field(tracker, "GetExistingBlock"), tracker, id)
        local isNative = b and field(b, "used") == true and field(b, "id") == id
        if isNative and watched[id] then used = used + 1 end
        out[#out + 1] = "QUEST\t" .. id .. "\twatch=" .. text(watched[id]) .. "\tnative=" .. text(isNative == true)
            .. "\tready=" .. text(ns.QuestStatus and ns.QuestStatus.IsReady(id))
            .. "\ttitle=" .. text(safe(Q.GetTitleForQuestID, id))
        out[#out + 1] = "BLOCK\t" .. blockInfo(b)
        if b then detail(out, b) end
    end
    for _, row in ipairs(state.auxiliary or {}) do
        local shown = safe(field(row.frame, "IsShown"), row.frame)
        if shown then auxShown = auxShown + 1 end
        out[#out + 1] = "AUX\tquest=" .. text(row.id) .. "\t" .. blockInfo(row.frame)
        detail(out, row.frame)
    end
    for i, row in ipairs(state.geometry or {}) do
        out[#out + 1] = "ORDER\t" .. i .. "\t" .. text(row.id) .. "\ty=" .. text(row.y) .. "\tw=" .. text(row.width) .. "\th=" .. text(row.height)
    end
    out[#out + 1] = "COUNTS\twatches=" .. count .. "\tnative=" .. used .. "\tauxShown=" .. auxShown
    for _, event in ipairs(recentEvents) do out[#out+1] = event end
    return table.concat(out, "\n")
end
function D.Capture(label)
    if not active or busy then return end
    busy = true
    local ok, result = pcall(snapshot, label)
    busy = false
    if not ok then failure = text(result); return end
    if #samples >= MAX_SAMPLES then table.remove(samples, 1); dropped = dropped + 1 end
    samples[#samples + 1] = result
end
local function installHooks()
    local tracker = _G.QuestObjectiveTracker
    if not tracker or not hooksecurefunc or hooked[tracker] then return end
    local function captureBlock(self, block)
        if not active or not permitted() or not block then return end
        local ok, err = pcall(function()
            local id, old = field(block, "id"), native[block]
            if not old or old.id ~= id or old.released then
                generation = generation + 1
                old = {generation=generation, id=id}; native[block] = old
            end
            old.released = false
            old.anchors, old.rect, old.title = anchors(block), rect(block), rect(field(block,"HeaderText"))
        end)
        if not ok then failure = text(err) end
    end
    -- AnchorBlock captura la geometría antes del reflow; LayoutBlock añade
    -- las dimensiones finales después de construir objetivos y asignar altura.
    for _, method in ipairs({"AnchorBlock", "LayoutBlock"}) do
        if type(tracker[method]) == "function" then hooksecurefunc(tracker, method, captureBlock) end
    end
    if type(tracker.FreeBlock) == "function" then
        hooksecurefunc(tracker, "FreeBlock", function(_, block)
            if active and native[block] then native[block].released = true end
        end)
    end
    if type(tracker.EndLayout) == "function" then
        hooksecurefunc(tracker, "EndLayout", function() D.Capture("end-layout") end)
    end
    hooked[tracker] = true
end
local panel, edit, pageLabel, pages, page = nil, nil, nil, {}, 1
local function showPage()
    edit:SetText(pages[page] or "")
    pageLabel:SetText("Diagnóstico QuestHelper — " .. page .. "/" .. #pages .. " — Ctrl+C para copiar")
    panel:Show(); edit:SetFocus(); edit:HighlightText()
end
local function compactSummary()
    local out = {"RESUMEN: solo capturas retenidas; no certifica ausencia de taint."}
    local seen, visible, auxiliary, checked, unknown, issues = {}, {}, {}, {}, {}, {}
    local function unique(line)
        if not seen[line] then seen[line] = true; out[#out+1] = line end
    end
    local function ids(set)
        local list = {}; for id in pairs(set) do list[#list+1] = id end
        table.sort(list); return table.concat(list, ",")
    end
    local function values(s)
        local result = {}; for v in (s or ""):gmatch("[^,]+") do result[#result+1] = v end
        return result
    end
    for _, sample in ipairs(samples) do
        local label = sample:match("^SNAP\t[^\t]+\t([^\n]+)") or "?"
        local visual = label == "after-addon" or label == "stop" or label == "full"
        local watches, quest, watchedQuest = {}, nil, false
        for line in sample:gmatch("[^\n]+") do
            if line:match("^QUEST\t") then
                quest = tonumber(line:match("^QUEST\t(%d+)"))
                watchedQuest = line:match("\twatch=%d+") ~= nil
                if watchedQuest then watches[#watches+1] = quest end
            elseif line:match("^BLOCK\t") and visual and quest and watchedQuest
                and tonumber(line:match("\tid=(%d+)")) == quest then
                local r = values(line:match("\trect=([^\t]+)"))
                if r[6] == "true" and r[7] == "true" and line:find("\tused=true", 1, true) then
                    visible[quest] = true
                    local n = values(line:match("\tnativeRect=([^\t]+)"))
                    local id = tonumber(line:match("\tnativeID=(%d+)"))
                    if id == quest and line:find("\treleased=false", 1, true)
                        and tonumber(r[1]) and tonumber(n[1]) and tonumber(r[3]) and tonumber(n[3])
                        and tonumber(r[4]) and tonumber(n[4]) then
                        checked[quest] = true
                        local dx, dw, dh = r[1]-n[1], r[3]-n[3], r[4]-n[4]
                        if math.abs(dx) > .01 or math.abs(dw) > .01 or math.abs(dh) > .01 then
                            local issue = ("GEOMETRIA id=%d dx=%.3f dw=%.3f dh=%.3f"):format(quest,dx,dw,dh)
                            issues[issue] = true
                        end
                    else unknown[quest] = true end
                end
            elseif line:match("^AUX\t") and visual then
                local r = values(line:match("\trect=([^\t]+)"))
                local id = tonumber(line:match("\tquest=(%d+)"))
                if id and r[6] == "true" and r[7] == "true" then auxiliary[id] = true end
            elseif line:match("^STATE\t") or line:match("^COUNTS\t") or line:match("^CAPACITY\t") then
                unique(line)
            elseif line:match("^SECURITY\t") and not line:match("\ttrue\t") then
                unique(line)
            elseif line:match("^RECENT\t") then unique(line)
            elseif line:match("^ItemButton\t") then unique(line)
            elseif line:match("^SKIP\t") then unique(line) end
        end
        unique("WATCH_ORDER\t" .. table.concat(watches, ","))
        if label:find("ADDON_ACTION_",1,true) then unique("EVENT\t" .. label) end
    end
    out[#out+1] = "NATIVE_VISIBLE\t" .. ids(visible)
    out[#out+1] = "AUX_VISIBLE\t" .. ids(auxiliary)
    out[#out+1] = "GEOMETRY_CHECKED\t" .. ids(checked)
    out[#out+1] = "GEOMETRY_WITHOUT_REFERENCE\t" .. ids(unknown)
    local sorted = {}; for issue in pairs(issues) do sorted[#sorted+1] = issue end; table.sort(sorted)
    out[#out+1] = "GEOMETRY_DIFFERENCES\t" .. #sorted
    for _, issue in ipairs(sorted) do out[#out+1] = issue end
    return table.concat(out, "\n")
end
local function export(raw, compact)
    if not panel then
        panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        panel:SetSize(780, 520); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG")
        panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
        panel:SetBackdropColor(.04,.04,.04,.98); panel:EnableMouse(true)
        pageLabel = panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
        pageLabel:SetPoint("TOP",0,-15)
        local scroll = CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-42); scroll:SetPoint("BOTTOMRIGHT",-34,44)
        edit = CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal); edit:SetWidth(720)
        edit:SetAutoFocus(false); edit:SetMaxLetters(0); edit:SetScript("OnEscapePressed",function() panel:Hide() end)
        scroll:SetScrollChild(edit)
        local function button(label, x, callback)
            local b = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
            b:SetSize(125,24); b:SetPoint("BOTTOMLEFT",x,12); b:SetText(label); b:SetScript("OnClick",callback)
        end
        button("Anterior",16,function() page=math.max(1,page-1); showPage() end)
        button("Siguiente",151,function() page=math.min(#pages,page+1); showPage() end)
        button("Cerrar",626,function() panel:Hide() end)
    end
    local version, build = "?", "?"
    if GetBuildInfo then version, build = GetBuildInfo() end
    local header = "TQHDIAG/1 addon=0.7.53 client=" .. text(version) .. " build=" .. text(build)
        .. " snapshots=" .. #samples .. " dropped=" .. dropped .. " error=" .. text(failure)
        .. "\nrect=left,top,width,height,effectiveScale,shown,visible; anchors=point,relativeFrame,relativePoint,x,y\n"
    local body = header .. (compact and compactSummary() or table.concat(samples,"\n\n"))
    if not raw and not compact then
        local dictionary, encoded, nextID = {}, {"TQHDIAG DICT/1 (+id TAB literal; @id repeats literal)"}, 0
        for line in (body .. "\n"):gmatch("(.-)\n") do
            local id = dictionary[line]
            if id then encoded[#encoded+1] = "@" .. id
            else
                nextID = nextID + 1; dictionary[line] = nextID
                encoded[#encoded+1] = "+" .. nextID .. "\t" .. line
            end
        end
        body = table.concat(encoded,"\n")
    end
    pages, page = {}, 1
    -- División por líneas, no en medio de un carácter UTF-8. Cada parte se
    -- identifica para que puedan recomponerse las capturas largas sin pérdidas.
    local chunk, size = {}, 0
    for line in (body .. "\n"):gmatch("(.-)\n") do
        if size + #line > 200000 and #chunk > 0 then pages[#pages+1]=table.concat(chunk,"\n"); chunk={}; size=0 end
        chunk[#chunk+1]=line; size=size+#line+1
    end
    if #chunk > 0 then pages[#pages+1]=table.concat(chunk,"\n") end
    for i = 1, #pages do pages[i] = "TQHDIAG PART " .. i .. "/" .. #pages .. "\n" .. pages[i] end
    showPage()
end
SLASH_TQHDIAG1 = "/tqhdiag"
SlashCmdList.TQHDIAG = function(message)
    local cmd, label = (message or ""):match("^(%S*)%s*(.-)%s*$")
    if cmd == "start" then
        samples, native, identities, serial, generation, dropped, failure = {}, {}, {}, 0, 0, 0, nil
        recentEvents = {}
        active = true; installHooks(); D.Capture("start")
        print("QuestHelper: observador iniciado; /tqhdiag mark etiqueta, stop, export. Exporta antes de recargar.")
    elseif cmd == "mark" then D.Capture("mark:" .. label)
    elseif cmd == "stop" then D.Capture("stop"); active=false; print("QuestHelper: " .. #samples .. " capturas; /tqhdiag export para copiarlas.")
    elseif cmd == "export" then export()
    elseif cmd == "resumen" then export(false, true)
    elseif cmd == "full" then
        local wasActive=active; active=true; installHooks(); D.Capture("full"); active=wasActive; export(true)
    else print("/tqhdiag start | mark etiqueta | stop | resumen | export | full") end
end
for _, event in ipairs({"QUEST_WATCH_LIST_CHANGED","QUEST_LOG_UPDATE","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent",function(_, event, a, b)
    if not active then return end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then D.Capture(event .. ":" .. text(a) .. ":" .. text(b)); return end
    if pending then return end
    if not C_Timer or not C_Timer.After then D.Capture(event); return end
    pending = true
    C_Timer.After(.15,function() pending=false; if active then installHooks(); D.Capture(event) end end)
end)
