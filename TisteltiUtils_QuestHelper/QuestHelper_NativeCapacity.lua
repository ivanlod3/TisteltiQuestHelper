-- Capacidad de construccion del contenedor ORIGINAL; no crea filas ni pools.
-- Dimensiones y limites del frame, HookScript y hooks posteriores. Los campos Lua de Blizzard,
-- sus enumeradores y su cola de actualizacion permanecen bajo su control.
-- El evento OnSizeChanged original solicita la actualizacion. El contexto de
-- seguridad de ese recorrido debe verificarse en el cliente, no en los mocks.
local _, ns = ...
local Capacity = {}
ns.NativeCapacity = Capacity
local container, tracker, baseHeight, expandedHeight, callback
local writing, enabled = false, false
local owned, restoring, tripped, lastWanted = false, false, false, nil
local reason = "pending"
local trip, restoreOwned
local windowStart, windowWrites = nil, 0
local function count(key)
    if ns.Perf then ns.Perf.Count(key) end
end
local function trace(kind,a,b,c,d)
    if ns.Perf and ns.Perf.Trace then ns.Perf.Trace(kind,a,b,c,d) end
end
-- The native client can reset the module height and clamp asynchronously.
-- Never keep fighting it: fail closed for the session instead of polling.
local function permitWrite()
    if restoring then return true end
    if tripped then return false end
    if type(GetTime) ~= "function" then return true end
    local now=GetTime()
    if not windowStart or now-windowStart >= 0.5 then
        windowStart, windowWrites=now,0
    end
    windowWrites=windowWrites+1
    if windowWrites > 16 then trip(); return false end
    return true
end
local suspendedForModules = false
local reported, reportPending = false, false
local initializing, refreshPending, finishLayout = false, false, nil
local pendingSources={}
local function refreshAfterNative(source)
    if tripped or (not enabled and not suspendedForModules) then return end
    source=source or "capacity.unknown"
    count("capacity.request."..source)
    pendingSources[source]=true
    if refreshPending then return end
    refreshPending=true
    C_Timer.After(0,function()
        refreshPending=false
        local sources=pendingSources
        pendingSources={}
        if not tripped and finishLayout then finishLayout(sources) end
    end)
end
local BUILD_HEIGHT = 32768
local clampInsets, writingClamp, appliedClamp
local function setClamp(extra)
    if not clampInsets then return false end
    local l,r,t,b = container:GetClampRectInsets()
    local wanted = clampInsets[4]+extra
    if l==clampInsets[1] and r==clampInsets[2] and t==clampInsets[3] and b==wanted then return true end
    if not permitWrite() then return false end
    count("layout.clamp.write")
    trace("clamp.write",b,wanted,clampInsets[4],extra)
    writingClamp = true
    local ok = pcall(container.SetClampRectInsets, container,
        clampInsets[1], clampInsets[2], clampInsets[3], wanted)
    writingClamp = false
    if ok then appliedClamp = extra ~= 0 and {clampInsets[1],clampInsets[2],clampInsets[3],wanted} or nil end
    return ok
end
local events = CreateFrame("Frame")
local function number(v)
    return type(v) == "number" and (not issecretvalue or not issecretvalue(v))
end
local function editable(frame)
    return frame and type(frame.SetHeight) == "function"
        and type(frame.IsProtected) == "function" and not frame:IsProtected()
end
local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end
local function wanted()
    return ns.Config and ns.Config.Get and ns.Config.Get("trackerScrollBeta") == true
        and ns.TrackerZones and ns.TrackerZones.NeedsCapacity()
        and not inCombat()
        and not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
end
local function otherModuleHeight()
    local total, count = 0, 0
    for _, module in ipairs(container.modules) do
        if module ~= tracker and type(module.IsDisplayable)=="function" and module:IsDisplayable() then
            local h=module:GetHeight()
            if not number(h) then return end
            total, count=total+h, count+1
        end
    end
    return total, count
end
local function setHeight(frame, height)
    if not editable(frame) or not number(height) or height <= 0 then return false end
    if math.abs(frame:GetHeight() - height) < 0.01 then return true end
    if not permitWrite() then return false end
    count("layout.height.write")
    count(frame==container and "layout.height.container" or "layout.height.tracker")
    trace("height.write",frame==container and "container" or "tracker",frame:GetHeight(),height,reason)
    writing = true
    local ok = pcall(frame.SetHeight, frame, height)
    writing = false
    return ok
end
restoreOwned = function()
    if not owned then return end
    enabled, owned, restoring = false, false, true
    -- Restore only what we changed, not a height that Edit Mode already reset.
    if expandedHeight and math.abs(container:GetHeight()-expandedHeight)<0.01 then
        setHeight(container,baseHeight)
    end
    if appliedClamp then setClamp(0) end
    appliedClamp, expandedHeight, restoring = nil,nil,false
end
trip = function()
    if tripped then return end
    tripped, enabled, suspendedForModules = true,false,false
    reason="geometry-feedback"
    count("layout.circuit_breaker")
    trace("capacity.trip",windowWrites,baseHeight,expandedHeight)
    C_Timer.After(0,function()
        restoreOwned()
        print("|cff73c9ffQuestHelper:|r Scroll experimental suspendido: conflicto repetido de geometría. Desactiva el scroll experimental en opciones para recuperar zonas, orden y búsqueda sin ampliar el contenedor.")
        if ns.TrackerZones and ns.TrackerZones.OnCapacityTripped then
            ns.TrackerZones.OnCapacityTripped()
        elseif callback then callback(false) end
    end)
end
function Capacity.Configure()
    if not container or writing or restoring or tripped then return end
    lastWanted = wanted()
    if suspendedForModules and otherModuleHeight()==0 then suspendedForModules=false end
    local activate = lastWanted and not suspendedForModules and editable(container) and editable(tracker)
    enabled = activate == true
    reason = enabled and "native-container" or (inCombat() and "combat" or "disabled")
    if suspendedForModules then reason="other-modules-fill-viewport" end
    if enabled then
        owned=true
        expandedHeight = math.max(baseHeight, BUILD_HEIGHT)
        if not setClamp(expandedHeight-baseHeight) or not setHeight(container, expandedHeight) then
            if not tripped then reason="resize-failed"; restoreOwned() end
        end
    else
        restoreOwned()
    end
end
function Capacity.Initialize(target, refresh)
    callback = refresh or callback
    if container then
        -- Do not reconfigure on each render. Only intent transitions, a real
        -- native resize, combat transitions or initial activation may do so.
        if not initializing and not tripped and wanted() ~= lastWanted then Capacity.Configure() end
        return
    end
    local parent = target and target.parentContainer
    if not editable(parent) or type(parent.modules) ~= "table"
        or type(parent.Update) ~= "function" or type(parent.HookScript) ~= "function"
        or type(parent.GetClampRectInsets) ~= "function"
        or type(parent.SetClampRectInsets) ~= "function"
        or not C_Timer or type(C_Timer.After) ~= "function"
        or type(hooksecurefunc) ~= "function" then reason="unsupported-container"; return end
    local belongs = false
    for _, module in ipairs(parent.modules) do if module == target then belongs=true end end
    local height = parent:GetHeight()
    if not belongs or not number(height) or height < 100 or height > 6000 then
        reason="unknown-height"; return
    end
    local insets = {parent:GetClampRectInsets()}
    for i=1,4 do if not number(insets[i]) then reason="unknown-clamp"; return end end
    container, tracker, baseHeight = parent, target, height
    clampInsets = insets
    hooksecurefunc(parent, "SetClampRectInsets", function(self, left, right, top, bottom)
        if writingClamp or restoring or self ~= container then return end
        if not number(left) or not number(right) or not number(top) or not number(bottom) then return end
        count("layout.native.clamp")
        trace("clamp.native",bottom,clampInsets[4],appliedClamp and appliedClamp[4])
        -- Some clients feed our already compensated inset back to the setter.
        -- Never use that as a new baseline and add BUILD_HEIGHT twice.
        if appliedClamp and math.abs(bottom-appliedClamp[4])<0.01 then
            bottom=clampInsets[4]
            if left==appliedClamp[1] and right==appliedClamp[2] and top==appliedClamp[3] then return end
        end
        clampInsets = {left, right, top, bottom}
        if enabled and not tripped then setClamp(expandedHeight-baseHeight) end
    end)
    -- Capturar cambios reales de Edit Mode/resolucion sin realimentar nuestra
    -- altura ampliada. No sustituye el manejador OnSizeChanged nativo.
    parent:HookScript("OnSizeChanged", function(self, _, h)
        if writing or restoring or self ~= container or not number(h) then return end
        if tripped then return end
        count("layout.native.resize")
        trace("size.native",h,baseHeight,expandedHeight)
        if h>=100 and h<=6000 and (not expandedHeight or math.abs(h-expandedHeight)>0.01) then
            baseHeight=h
        end
        if enabled or suspendedForModules then
            Capacity.Configure()
            refreshAfterNative("native.OnSizeChanged")
        end
    end)
    finishLayout = function(sources)
        -- Aqui ya se conocen tambien los modulos posteriores al de misiones.
        if enabled and not inCombat() then
            local view=Capacity.GetViewHeight(tracker)
            -- No convertir un objetivo de escenario/otros modulos muy alto
            -- en contenido fuera de pantalla para hacer hueco a misiones.
            -- Volver al reparto nativo hasta que desaparezcan esos modulos.
            if view and view < 100 and otherModuleHeight()>0 then
                suspendedForModules=true
                Capacity.Configure()
                if callback then callback(false,"capacity.suspend_modules") end
                return
            end
            if callback then callback(false,sources) end

        elseif suspendedForModules and not inCombat() then
            Capacity.Configure()
        end
    end
    hooksecurefunc(parent, "Update", function()
        if enabled then count("layout.native.container") end
        refreshAfterNative("native.container.Update")
    end)
    -- dirtyCallback conserva una referencia previa a parent.Update. El
    -- modulo se invoca tambien en ese recorrido, incluso si omite EndLayout.
    hooksecurefunc(target, "Update", function()
        if enabled then count("layout.native.tracker") end
        refreshAfterNative("native.tracker.Update")
    end)
    for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do
        events:RegisterEvent(event)
    end
    -- EndLayout puede ejecutarse dentro de dirtyCallback. Esperar a que
    -- termine para que OnSizeChanged pueda encolar una nueva pasada nativa.
    initializing=true
    C_Timer.After(0, function()
        initializing=false
        Capacity.Configure()
        refreshAfterNative("capacity.initial")
        if not reported and not reportPending and C_Timer and C_Timer.After then
            reportPending=true
            C_Timer.After(1, function()
                reportPending=false
                if not enabled or inCombat() then return end
                reported=true
                if callback then callback(false,"capacity.initial_report") end
                local state=ns.TrackerZones.GetDiagnosticState()
                local insecure={}
                if type(issecurevariable)=="function" then
                    for _, key in ipairs({"EnumQuestWatchData","BuildQuestWatchInfos","isDirty","availableHeight","contentsHeight","state","usedBlocks"}) do
                        if not issecurevariable(tracker,key) then insecure[#insecure+1]=key end
                    end
                    for _, key in ipairs({"Update","GetAvailableHeight","dirtyCallback","dirty"}) do
                        if not issecurevariable(container,key) then insecure[#insecure+1]="container."..key end
                    end
                end
                local security=type(issecurevariable)~="function" and "no disponible" or
                    (#insecure==0 and "campos comprobados seguros" or "taint: "..table.concat(insecure,","))
                print("|cff73c9ffQuestHelper 0.7.53:|r nativas "..state.native.."/"..state.watches..
                    "; auxiliares 0; "..security..".")
            end)
        end
    end)
end
function Capacity.HandlesNative() return enabled and container ~= nil end
function Capacity.IsTripped() return tripped end
function Capacity.GetViewHeight(target)
    if not enabled or target ~= tracker or not baseHeight then return end
    local top = container.topModulePadding or 0
    local bottom = container.bottomModulePadding or 0
    local gap = container.moduleSpacing or 0
    if not number(top) or not number(bottom) or not number(gap) then return end
    local otherHeight, others=otherModuleHeight()
    if not otherHeight then return end
    local remaining = baseHeight-top-bottom-otherHeight
    local trackerTop, contentTop=tracker:GetTop(),tracker.ContentsFrame:GetTop()
    if not number(trackerTop) or not number(contentTop) then return end
    local inset=trackerTop-contentTop
    if not number(inset) or inset < 0 then return end
    -- Reservar el espacio de los otros modulos, incluidos los de prioridad.
    return math.max(0, remaining-others*gap-inset), inset
end
function Capacity.FitVisible(target, height)
    if not enabled or target ~= tracker or inCombat() then return end
    local view, inset=Capacity.GetViewHeight(target)
    if view and number(height) then setHeight(target, math.max(inset, math.min(height,view)+inset)) end
end
function Capacity.GetState()
    return {enabled=enabled, reason=reason, base=baseHeight,
        expanded=container and container:GetHeight(), view=tracker and Capacity.GetViewHeight(tracker),
        trackerHeight=tracker and tracker:GetHeight(),clampBottom=container and select(4,container:GetClampRectInsets()),
        baselineBottom=clampInsets and clampInsets[4],tripped=tripped}
end
events:SetScript("OnEvent", function(_,event)
    -- En combate solo se restaura la dimension del contenedor NO protegido.
    -- Su propio evento reconstruye el layout normal; no se llama a Update.
    if tripped then return end
    Capacity.Configure()
    if not inCombat() and callback then callback(false,"capacity."..tostring(event)) end
end)
