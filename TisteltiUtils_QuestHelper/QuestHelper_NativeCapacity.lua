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
local reason = "pending"
local suspendedForModules = false
local reported, reportPending = false, false
local initializing, refreshPending, finishLayout = false, false, nil
local function refreshAfterNative()
    if refreshPending then return end
    refreshPending=true
    C_Timer.After(0, function()
        refreshPending=false
        if finishLayout then finishLayout() end
    end)
end
local BUILD_HEIGHT = 32768
local clampInsets, writingClamp
local function setClamp(extra)
    if not clampInsets then return false end
    writingClamp = true
    local ok = pcall(container.SetClampRectInsets, container,
        clampInsets[1], clampInsets[2], clampInsets[3], clampInsets[4] + extra)
    writingClamp = false
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
    writing = true
    local ok = pcall(frame.SetHeight, frame, height)
    writing = false
    return ok
end
function Capacity.Configure()
    if not container or writing then return end
    if suspendedForModules and otherModuleHeight()==0 then suspendedForModules=false end
    local activate = wanted() and not suspendedForModules and editable(container) and editable(tracker)
    enabled = activate == true
    reason = enabled and "native-container" or (inCombat() and "combat" or "disabled")
    if suspendedForModules then reason="other-modules-fill-viewport" end
    if enabled then
        expandedHeight = math.max(baseHeight, BUILD_HEIGHT)
        -- La altura de construccion no debe desplazar el rectangulo visible.
        -- Blizzard mide el borde inferior como GetBottom()+bottomInset.
        -- Mantener el clamp y los anclajes originales; compensar solo la
        -- diferencia entre la altura de construccion y la altura visible.
        if not setClamp(expandedHeight-baseHeight) or not setHeight(container, expandedHeight) then
            enabled=false; reason="resize-failed"
            setHeight(container, baseHeight); setClamp(0)
        end
    elseif baseHeight then
        setHeight(container, baseHeight)
        setClamp(0)
    end
end
function Capacity.Initialize(target, refresh)
    callback = refresh or callback
    if container then if not initializing then Capacity.Configure() end; return end
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
        if writingClamp or self ~= container then return end
        if not number(left) or not number(right) or not number(top) or not number(bottom) then return end
        clampInsets = {left, right, top, bottom}
        if enabled then setClamp(expandedHeight-baseHeight) end
    end)
    -- Capturar cambios reales de Edit Mode/resolucion sin realimentar nuestra
    -- altura ampliada. No sustituye el manejador OnSizeChanged nativo.
    parent:HookScript("OnSizeChanged", function(self, _, h)
        if writing or self ~= container or not number(h) then return end
        if not expandedHeight or math.abs(h-expandedHeight) > 0.01 then baseHeight=h end
        Capacity.Configure()
        refreshAfterNative()
    end)
    finishLayout = function()
        -- Aqui ya se conocen tambien los modulos posteriores al de misiones.
        if enabled and not inCombat() then
            local view=Capacity.GetViewHeight(tracker)
            -- No convertir un objetivo de escenario/otros modulos muy alto
            -- en contenido fuera de pantalla para hacer hueco a misiones.
            -- Volver al reparto nativo hasta que desaparezcan esos modulos.
            if view and view < 100 and otherModuleHeight()>0 then
                suspendedForModules=true
                Capacity.Configure()
                if callback then callback(false) end
                return
            end
            if callback then callback(false) end

        elseif suspendedForModules and not inCombat() then
            Capacity.Configure()
        end
    end
    hooksecurefunc(parent, "Update", finishLayout)
    -- dirtyCallback conserva una referencia previa a parent.Update. El
    -- modulo se invoca tambien en ese recorrido, incluso si omite EndLayout.
    hooksecurefunc(target, "Update", refreshAfterNative)
    for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do
        events:RegisterEvent(event)
    end
    -- EndLayout puede ejecutarse dentro de dirtyCallback. Esperar a que
    -- termine para que OnSizeChanged pueda encolar una nueva pasada nativa.
    initializing=true
    C_Timer.After(0, function()
        initializing=false
        Capacity.Configure()
        refreshAfterNative()
        if not reported and not reportPending and C_Timer and C_Timer.After then
            reportPending=true
            C_Timer.After(1, function()
                reportPending=false
                if not enabled or inCombat() then return end
                reported=true
                if callback then callback(false) end
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
        expanded=container and container:GetHeight(), view=tracker and Capacity.GetViewHeight(tracker)}
end
events:SetScript("OnEvent", function()
    -- En combate solo se restaura la dimension del contenedor NO protegido.
    -- Su propio evento reconstruye el layout normal; no se llama a Update.
    Capacity.Configure()
    if not inCombat() and callback then callback(false) end
end)
