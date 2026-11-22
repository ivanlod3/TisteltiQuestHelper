-- Opciones nativas: Opciones > Addons > TisteltiUtils - QuestHelper.
local addonName, ns = ...
local category
local function checkbox(key, title, tooltip)
    local setting = Settings.RegisterAddOnSetting(
        category, "TISTELTI_QH_" .. key, key, ns.Config.Settings(),
        Settings.VarType.Boolean, title, ns.Config.Defaults()[key]
    )
    Settings.CreateCheckbox(category, setting, tooltip)
    if setting and type(setting.SetValueChangedCallback) == "function" then
        setting:SetValueChangedCallback(function()
            if ns.RefreshSettings then ns.RefreshSettings(key) end
        end)
    elseif Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback("TISTELTI_QH_" .. key, function()
            if ns.RefreshSettings then ns.RefreshSettings(key) end
        end)
    end
end
local function trackerDropdown()
    local modes = {
        { "native", "Nativo (nivel ascendente con zonas)" },
        { "level_asc", "Nivel ascendente" },
        { "level_desc", "Nivel descendente" },
        { "zone", "Por zona" },
        { "zone_level_asc", "Zona y nivel ascendente" },
        { "zone_level_desc", "Zona y nivel descendente" },
        { "name", "Nombre alfabético" },
    }
    local function options()
        local container = Settings.CreateControlTextContainer()
        for _, item in ipairs(modes) do container:Add(item[1], item[2]) end
        return container:GetData()
    end
    local setting = Settings.RegisterAddOnSetting(
        category, "TISTELTI_QH_trackerSortMode", "trackerSortMode", ns.Config.Settings(),
        Settings.VarType.String, "Orden del seguimiento", "native")
    Settings.CreateDropdown(category, setting, options,
        "Ordena visualmente el seguimiento sin quitar ni volver a añadir misiones. " ..
        "Con zonas activas, agrupa por zona y aplica el criterio dentro de cada zona. " ..
        "Nativo sin zonas conserva el orden del juego.")
    if setting and type(setting.SetValueChangedCallback) == "function" then
        setting:SetValueChangedCallback(function()
            if ns.RefreshSettings then ns.RefreshSettings("trackerSortMode") end
        end)
    elseif Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback("TISTELTI_QH_trackerSortMode", function()
            if ns.RefreshSettings then ns.RefreshSettings("trackerSortMode") end
        end)
    end
end
local function recentDurationDropdown()
    local function options()
        local container = Settings.CreateControlTextContainer()
        for _, value in ipairs({30, 60, 90, 120}) do
            container:Add(value, tostring(value) .. " segundos")
        end
        return container:GetData()
    end
    local setting = Settings.RegisterAddOnSetting(
        category, "TISTELTI_QH_trackerRecentSeconds", "trackerRecentSeconds",
        ns.Config.Settings(), Settings.VarType.Number,
        "Duración del resaltado", 60)
    Settings.CreateDropdown(category, setting, options,
        "Tiempo que el título de una misión nueva o actualizada permanece iluminado en su propia fila.")
    if setting and type(setting.SetValueChangedCallback) == "function" then
        setting:SetValueChangedCallback(function()
            if ns.RefreshSettings then ns.RefreshSettings("trackerRecentSeconds") end
        end)
    elseif Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback("TISTELTI_QH_trackerRecentSeconds", function()
            if ns.RefreshSettings then ns.RefreshSettings("trackerRecentSeconds") end
        end)
    end
end

local function header(layout, title)
    if CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
    end
end
-- A canvas subcategory with live, event-only previews (no OnUpdate, timers or polling).
-- Plate previews use the exact same draw routine as the real nameplates.
-- Inventory preview shares the Baganator bag icon factory and font styling.
local function registerAppearance()
    if not Settings or not Settings.RegisterCanvasLayoutSubcategory
        or not category or not ns.Config or not ns.Config.GetNumber then return end

    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(555, 590)
    panel:Hide() -- Settings alone controls its visibility.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(510, 1005)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self)
        content:SetWidth(math.max(470, self:GetWidth() - 8))
    end)

    local function label(parent, text, x, y, template)
        local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
        font:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        font:SetText(text)
        return font
    end
    local function background(parent, r, g, b, a)
        local texture = parent:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        texture:SetColorTexture(r, g, b, a)
        return texture
    end
    local function button(parent, text, x, y, width, callback)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        b:SetText(text)
        b:SetScript("OnClick", callback)
        return b
    end

    label(content, "Apariencia y vista previa", 13, -12, "GameFontNormalLarge")
    label(content, "Arte nativo de Forever; muestra sin crear placas protegidas.",
        13, -39, "GameFontHighlightSmall")

    label(content, "Placas de enemigos (apariencia nativa de Forever)", 13, -70, "GameFontNormal")
    local plates = CreateFrame("Frame", nil, content)
    plates:SetSize(485, 255)
    plates:SetPoint("TOPLEFT", content, "TOPLEFT", 13, -93)
    background(plates, 0.035, 0.095, 0.13, 0.95)
    label(plates, "Seleccionada (un objetivo)", 11, -14, "GameFontHighlightSmall")
    label(plates, "Proximidad + marca de banda", 11, -93, "GameFontHighlightSmall")
    label(plates, "Élite sin marca de banda", 11, -173, "GameFontHighlightSmall")

    -- We cannot safely instantiate Blizzard's live, unit-bound nameplate template:
    -- it has unit, protected UI and driver state. Build just its public art
    -- (statusbar, background, border, name, health, level and raid marker)
    -- using the same atlases/fonts and the active NamePlateSetupOptions.
    -- The ACTUAL quest number/icon overlay is rendered by ns.PlateAppearance.Preview.
    local function useAtlas(tex, name)
        if not name or type(tex.SetAtlas) ~= "function" then return false end
        if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
            local ok, info = pcall(C_Texture.GetAtlasInfo, name)
            if not ok or not info then return false end
        end
        return pcall(tex.SetAtlas, tex, name, true)
    end
    local plateExamples = {}
    local function mockPlate(y, title, health, selected, raidMarked, elite)
        local plate = CreateFrame("Frame", nil, plates)
        plate:SetSize(230, 48)
        plate:SetPoint("TOPLEFT", plates, "TOPLEFT", 240, y)
        local bar = CreateFrame("StatusBar", nil, plate)
        bar:SetPoint("LEFT", plate, "LEFT", 0, 0)
        bar:SetSize(188, 20)
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(health)
        local barTex = bar:CreateTexture(nil, "ARTWORK")
        bar:SetStatusBarTexture(barTex)
        local borderBg = bar:CreateTexture(nil, "BACKGROUND")
        local deselected = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        local border = bar:CreateTexture(nil, "OVERLAY", nil, 2)
        local nameText = bar:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
        nameText:SetText(title)
        nameText:SetTextColor(1, 1, 1)
        nameText:SetJustifyH("LEFT")
        local healthText = bar:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
        healthText:SetText("863")
        healthText:SetTextColor(1, 1, 1)
        healthText:SetJustifyH("RIGHT")
        healthText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        nameText:SetPoint("LEFT", bar, "LEFT", 5, 0)
        nameText:SetPoint("RIGHT", healthText, "LEFT", -3, 0)
        nameText:SetMaxLines(1)
        local levelFrame = CreateFrame("Frame", nil, plate)
        levelFrame:SetSize(28, 23)
        levelFrame:SetPoint("LEFT", bar, "RIGHT", 5, 0)
        local levelArt = levelFrame:CreateTexture(nil, "ARTWORK")
        levelArt:SetAllPoints()
        local levelText = levelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        levelText:SetPoint("CENTER", 0, 0)
        levelText:SetText("24")
        levelText:SetTextColor(0.14, 0.9, 0.18)
        local marker = CreateFrame("Frame", nil, plate)
        marker:SetSize(22, 22)
        marker:SetPoint("RIGHT", bar, "LEFT", 0, 0)
        local markerTex = marker:CreateTexture(nil, "ARTWORK")
        markerTex:SetAllPoints()
        markerTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        if type(SetRaidTargetIconTexture) == "function" then
            SetRaidTargetIconTexture(markerTex, 8) -- Skull = raid-target index 8
        else
            markerTex:SetTexCoord(0.75, 1, 0.5, 1)
        end
        marker:SetShown(raidMarked)
        local classification = CreateFrame("Frame", nil, plate)
        classification:SetSize(20, 20)
        -- Identical hierarchy to Forever: ClassificationFrame sits to the
        -- left of RaidTargetFrame and is hidden when a raid mark is assigned.
        classification:SetPoint("RIGHT", marker, "LEFT", 0, 0)
        local classificationTex = classification:CreateTexture(nil, "ARTWORK")
        classificationTex:SetAllPoints()
        if not useAtlas(classificationTex, "nameplates-icon-elite-gold") then
            classificationTex:SetColorTexture(0.82, 0.64, 0.22, 0.85)
        end
        classification:SetShown(elite == true and not raidMarked)
        plate.UnitFrame = { healthBar = bar, HealthBarsContainer = {healthBar = bar},
            RaidTargetFrame = marker, ClassificationFrame = classification }
        plate.RefreshChrome = function()
            local options = NamePlateSetupOptions or {}
            local constants = NamePlateConstants or {}
            local classic = options.useClassicHealthBar == true
            local xScale = type(options.horizontalScale) == "number" and options.horizontalScale or 1
            local yScale = type(options.verticalScale) == "number" and options.verticalScale or 1
            local baseWidth = classic and (constants.CLASSIC_NAME_PLATE_WIDTH or 152) or (constants.NAME_PLATE_WIDTH or 190)
            -- The live nameplate uses horizontalScale/verticalScale from its size setting.
            bar:SetSize(math.min(205, math.max(125, baseWidth * xScale)),
                math.min(27, math.max(10, (options.healthBarHeight or 20) * yScale)))
            if classic then
                barTex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
                borderBg:SetTexture("Interface\\Tooltips\\Nameplate-Border")
                borderBg:SetTexCoord(0, 1, 0.5, 1)
                borderBg:ClearAllPoints()
                borderBg:SetPoint("TOPLEFT", bar, "TOPLEFT", -4, 4)
                borderBg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4, -4)
                border:Hide()
                deselected:Hide()
            else
                if not useAtlas(barTex, "UI-HUD-CoolDownManager-Bar") then
                    barTex:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
                end
                if not useAtlas(borderBg, "UI-HUD-CoolDownManager-Bar-BG") then
                    borderBg:SetColorTexture(0.04, 0.035, 0.025, 1)
                end
                borderBg:ClearAllPoints()
                borderBg:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
                borderBg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
                if selected then
                    if not useAtlas(border, constants.SELECTED_BORDER_ATLAS or "UI-HUD-CoolDownManager-Selected-yellow") then
                        border:SetColorTexture(1, 0.82, 0.15, 0.8)
                    end
                    local o = constants.SELECTED_BORDER_OFFSETS or {}
                    border:ClearAllPoints()
                    border:SetPoint("TOPLEFT", borderBg, "TOPLEFT", o.topLeftX or -3, o.topLeftY or 2)
                    border:SetPoint("BOTTOMRIGHT", borderBg, "BOTTOMRIGHT", o.bottomRightX or 0, o.bottomRightY or 2)
                    border:Show()
                    deselected:Hide()
                else
                    border:Hide()
                    if useAtlas(deselected, "ui-hud-nameplates-deselected-overlay") then
                        deselected:SetAllPoints(bar)
                        deselected:Show()
                    else
                        deselected:Hide()
                    end
                end
            end
            bar:SetStatusBarColor(0.68, 0.05, 0.055, 1)
            if not useAtlas(levelArt, "ui-hud-nameplates-levelindicator-rectangle-c60") then
                levelArt:SetColorTexture(0.08, 0.07, 0.05, 0.95)
            end
        end
        return plate
    end
    -- Both examples are actual QuestHelper overlays on Blizzard-like bar art.
    plateExamples[1] = mockPlate(-38, "Horror esquelético", 86, true, false, false)
    plateExamples[2] = mockPlate(-118, "Mefisto esquelético", 52, false, true, false)
    plateExamples[3] = mockPlate(-198, "Eliza", 78, true, false, true)

    local numberControls = {}
    local function numericControl(y, setting, text)
        local range = ns.Config.AppearanceRanges()[setting]
        label(content, text, 22, y - 3, "GameFontHighlightSmall")
        local value = label(content, "", 352, y - 3, "GameFontNormalSmall")
        local minus = button(content, "-", 306, y, 24, function()
            ns.Config.SetAppearance(setting, ns.Config.GetNumber(setting) - 1)
        end)
        local plus = button(content, "+", 401, y, 24, function()
            ns.Config.SetAppearance(setting, ns.Config.GetNumber(setting) + 1)
        end)
        numberControls[#numberControls + 1] = {key = setting, value = value, min = minus, max = plus, range = range}
    end
    local plateRows = {
        {"plateIconSize", "Icono con un objetivo"},
        {"plateTextSize", "Número con un objetivo"},
        {"plateStackIconSize", "Iconos con varias filas"},
        {"plateStackTextSize", "Números con dos tipos de objetivo"},
        {"plateMultiTextSize", "Números de varios botines"},
        {"plateNumberGap", "Espacio entre números e iconos"},
        {"plateRowSpacing", "Separación entre saquito y espada"},
        {"plateDistance", "Distancia respecto a la placa"},
        {"plateRaidTargetExtra", "Margen extra con marca o élite"},
    }
    for i, entry in ipairs(plateRows) do
        numericControl(-361 - (i-1)*28, entry[1], entry[2])
    end
    button(content, "Restaurar placas", 22, -625, 141, function()
        ns.Config.ResetAppearance("plate")
    end)

    label(content, "Inventario / Baganator", 13, -663, "GameFontNormal")
    local inventory = CreateFrame("Frame", nil, content)
    inventory:SetSize(485, 100)
    inventory:SetPoint("TOPLEFT", content, "TOPLEFT", 13, -686)
    background(inventory, 0.07, 0.09, 0.12, 0.95)
    local bagExamples = {}
    local function mockItem(x, qty, itemTexture, text)
        local slot = CreateFrame("Frame", nil, inventory)
        slot:SetSize(47, 47)
        slot:SetPoint("TOPLEFT", inventory, "TOPLEFT", x, -13)
        background(slot, 0.04, 0.035, 0.025, 1)
        local item = slot:CreateTexture(nil, "ARTWORK")
        item:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
        item:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
        item:SetTexture(itemTexture)
        local marker
        if ns.QuestItems and ns.QuestItems.CreatePreviewMarker then
            marker = ns.QuestItems.CreatePreviewMarker(slot)
        end
        local count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 2)
        count:SetText(qty)
        label(inventory, text, x, -66, "GameFontHighlightSmall")
        return {slot = slot, marker = marker, number = count}
    end
    bagExamples[1] = mockItem(45, "5/8", "Interface\\Icons\\INV_Misc_Herb_05", "Pendiente")
    bagExamples[2] = mockItem(190, "8/8", "Interface\\Icons\\INV_Misc_Herb_07", "Completada")

    local bagRows = {
        {"bagMarkerSize", "Tamaño del saquito"},
        {"bagOutlineWidth", "Grosor del contorno oscuro"},
        {"bagCounterSize", "Tamaño del progreso (x/x)"},
    }
    for i, entry in ipairs(bagRows) do
        numericControl(-802 - (i-1)*28, entry[1], entry[2])
    end
    button(content, "Restaurar inventario", 22, -893, 163, function()
        ns.Config.ResetAppearance("bag")
    end)
    label(content, "La vista previa no activa funciones deshabilitadas ni consulta el inventario.",
        22, -930, "GameFontHighlightSmall")

    ns.AppearanceOptions = {
        Refresh = function()
            -- No preview work happens while its Settings panel is closed.
            if not panel:IsVisible() then return end
            for _, control in ipairs(numberControls) do
                local value = ns.Config.GetNumber(control.key)
                control.value:SetText(tostring(value) .. " px")
                control.min:SetEnabled(value > control.range[2])
                control.max:SetEnabled(value < control.range[3])
            end
            if ns.PlateAppearance and ns.PlateAppearance.Preview then
                for _, example in ipairs(plateExamples) do
                    if example.RefreshChrome then example.RefreshChrome() end
                end
                ns.PlateAppearance.Preview(plateExamples[1], {
                    item = {{key="preview1", count="5/8"}}, monster = {},
                })
                ns.PlateAppearance.Preview(plateExamples[2], {
                    item = {{key="preview2", count="7/8"},{key="preview3", count="0/1"}},
                    monster = {{key="preview4", count="4/15"}},
                })
                ns.PlateAppearance.Preview(plateExamples[3], {
                    item = {{key="preview5", count="0/1"}}, monster = {},
                })
            end
            for _, demo in ipairs(bagExamples) do
                if ns.QuestItems and ns.QuestItems.RefreshPreviewMarker and demo.marker then
                    ns.QuestItems.RefreshPreviewMarker(demo.marker)
                end
                if ns.QuestItems and ns.QuestItems.StylePreviewCount then
                    ns.QuestItems.StylePreviewCount(demo.number)
                end
            end
        end,
    }
    panel:SetScript("OnShow", function() ns.AppearanceOptions.Refresh() end)
    panel.OnRefresh = function() ns.AppearanceOptions.Refresh() end
    local sub = Settings.RegisterCanvasLayoutSubcategory(category, panel, "Apariencia y vista previa")
    -- Canvas subcategories belong to their parent category; registering the
    -- parent is sufficient. OpenToCategory uses the returned subcategory ID.
    ns.AppearanceOptions.Category = sub
end

local function registerOptions()
    if not Settings or not Settings.RegisterVerticalLayoutCategory or not ns.Config
        or not ns.Config.Settings() then return end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("TisteltiUtils - QuestHelper")
    header(layout, "Objetivos sobre los enemigos")
    checkbox("nameplateIcons", "Mostrar espada, saquito y contadores en placas",
        "Desactiva la lectura de tooltips de las placas si la macro automática también está desactivada.")
    checkbox("autoMacro", "Actualizar la macro QuestHelper automáticamente",
        "Aprende NPC de misiones y reescribe la macro solo cuando cambia lo necesario, fuera de combate.")
    header(layout, "Inventario (funciones opcionales)")
    checkbox("markBaganator", "Mostrar saquitos de misión en Baganator",
        "Desactivado por defecto. Usa exclusivamente la API de indicadores de Baganator; no busca ventanas ni botones.")
    checkbox("markBags", "Mostrar saquitos en las bolsas de Blizzard",
        "Desactivado por defecto. Solo comprueba botones de bolsas oficiales al abrirlas o cuando cambian los objetos.")
    checkbox("itemTooltips", "Mostrar misión y progreso en el tooltip de objetos",
        "Desactivado por defecto. Consulta el índice de objetivos solo cuando se muestra un tooltip de objeto.")
    header(layout, "Seguimiento de misiones")
    checkbox("trackerRecentEnabled", "Resaltar misiones nuevas y avances en el rastreador",
        "Resalta la fila de la misión en su zona: amarillo al aceptarla, azul al avanzar " ..
        "y verde cuando está lista para entregar. Sin paneles ni notificaciones.")
    recentDurationDropdown()
    header(layout, "Opciones del seguimiento nativo")
    trackerDropdown()
    checkbox("trackerZoneSections", "Agrupar por zonas (clic en título para plegar)",
        "Activado por defecto. Reutiliza las misiones y botones nativos. " ..
        "Se organiza visualmente después del dibujo nativo, sin reemplazar funciones de Blizzard. " ..
        "Orden por nivel ascendente dentro de cada zona con modo Nativo. Clic para plegar.")
    checkbox("trackerSearchButton", "Mostrar botón de búsqueda en el seguimiento",
        "Activado por defecto. Abre el buscador nativo desde la cabecera de Misiones. " ..
        "Filtra por título y objetivos sin alterar las misiones seguidas. No fuerza actualizaciones protegidas.")
    checkbox("trackerSearchKeepOnBlur", "Mantener búsqueda al perder el foco",
        "Si hay texto, conserva el campo visible y el filtro al pulsar fuera. " ..
        "Si está desactivado, se cierran y limpian al perder el foco. " ..
        "Con el campo vacío siempre se oculta.")
    checkbox("trackerScrollBeta", "Desplazamiento por misiones (experimental)",
        "La rueda recorre las misiones en el espacio del rastreador sin modificar " ..
        "el seguimiento. Para las misiones descartadas por altura, crea filas " ..
        "de reserva con tipografía de Blizzard. Experimental en Forever.")
    header(layout, "Avisos al grupo")
    checkbox("announceObjectives", "Anunciar objetivos completados",
        "Publica en PARTY los objetivos terminados; no se anuncia nada en solitario.")
    checkbox("announceQuests", "Anunciar misiones listas para entregar",
        "Publica en PARTY cuando una misión está lista para entregar, sin duplicar el último objetivo.")
    checkbox("announceLevels", "Anunciar subidas de nivel",
        "Desactivado por defecto para instalaciones nuevas. Respeta los ajustes guardados y no publica recuentos incompletos.")
    registerAppearance()
    Settings.RegisterAddOnCategory(category)
end
function ns.OpenOptions(appearance)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        print("|cff73c9ffTisteltiUtils QuestHelper:|r Abre las opciones fuera de combate.")
        return
    end
    if category and Settings and Settings.OpenToCategory then
        local target = appearance and ns.AppearanceOptions and ns.AppearanceOptions.Category or category
        Settings.OpenToCategory(target:GetID())
    else
        print("|cff73c9ffTisteltiUtils QuestHelper:|r Opciones no disponibles en este cliente.")
    end
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", registerOptions)
