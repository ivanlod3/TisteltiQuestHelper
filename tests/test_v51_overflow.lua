-- Prueba automatizada acotada de filas de reserva QuestHelper 0.7.51.
local function node(kind)
    local n={kind=kind,anchors={},shown=false,width=240,height=18,color={}}
    function n:SetPoint(...) self.anchors[#self.anchors+1]={...} end
    function n:ClearAllPoints() self.anchors={} end
    function n:SetWidth(v) self.width=v end
    function n:SetHeight(v) self.height=v end
    function n:SetSize(w,h) self.width=w; self.height=h end
    function n:GetWidth() return self.width end
    function n:GetHeight() return self.height end
    function n:GetLeft() return self.left end
    function n:GetRight() return self.right end
    function n:GetFont() return 'Fonts/FRIZQT__.TTF',12,'OUTLINE' end
    function n:SetFont(...) self.fontArgs={...} end
    function n:SetFontObject(...) self.fontObject={...} end
    function n:SetJustifyH() end
    function n:SetWordWrap() end
    function n:SetShadowOffset() end
    function n:SetShadowColor() end
    function n:SetText(t) self.text=t end
    function n:GetStringHeight() return 16 end
    function n:SetTextColor(...) self.color={...} end
    function n:SetColorTexture(...) self.colorTexture={...} end
    function n:SetAtlas(atlas) self.atlas=atlas end
    function n:SetTexture(texture) self.texture=texture end
    function n:SetAllPoints() end
    function n:RegisterForClicks() end
    function n:SetScript(event,f) self[event]=f end
    function n:Show() self.shown=true end
    function n:Hide() self.shown=false end
    function n:CreateFontString() return node('fontstring') end
    function n:CreateTexture() return node('texture') end
    function n:SetSelected(v) self.selected=v end
    function n:SetQuestID(v) self.questId=v end
    function n:SetStyle(v) self.style=v end
    function n:UpdateButtonStyle() self.drawnStyle=self.style end
    return n
end
local unsupportedPOI=false
CreateFrame=function(kind,_,parent,template)
    local f=node(template or kind)
    f.parent=parent
    if template=="POIButtonTemplate" and unsupportedPOI then
        f.SetStyle=nil; f.UpdateButtonStyle=nil
    end
    return f
end
GameFontNormal = {}
POIButtonUtil={ Style={ QuestInProgress=2, QuestComplete=3 } }
local objectives={{text='Baúl Velasangre examinado: 0/1',finished=false}}
local complete=false
C_QuestLog={
    GetNumQuestWatches=function() return 2 end,
    GetQuestIDForQuestWatchIndex=function(i) return i==1 and 1111 or 2222 end,
    GetQuestObjectives=function(id) if id==2222 then return objectives else return {{text='Objetivo: 0/1',finished=false}} end end,
    GetLogIndexForQuestID=function() return 2 end,
    GetInfo=function() return {questID=2222,isComplete=true,readyForTurnIn=false,difficultyLevel=40} end,
    GetTitleForQuestID=function() return 'Conseguir la mercancía' end,
    GetQuestDifficultyLevel=function() return 40 end,
    GetQuestTagInfo=function() return {} end,
    ReadyForTurnIn=function() return complete end,
    IsQuestReadyForTurnIn=function() return complete end,
    IsComplete=function() return true end,
}
GetQuestDifficultyColor=function() return {r=0.1,g=1,b=0.2} end
C_SuperTrack={ GetSuperTrackedQuestID=function() return 0 end }
local native=node('native')
native.left=100; native.right=340; native.width=240; native.used=true
native.HeaderText=node('fontstring'); native.HeaderText.left=135; native.HeaderText.right=336
native.usedLines={{Text=node('fontstring')}}
local tracker={ContentsFrame=node('contents'),GetExistingBlock=function(self,id) if id==1111 then return native end end}
local namespace={Config={Get=function() return true end}}
if arg[2] then assert(loadfile(arg[2]))('test_addon',namespace) end
assert(loadfile(arg[1]))('test_addon',namespace)
local function findUpvalue(fn,target,seen)
    seen=seen or {}
    if seen[fn] then return end
    seen[fn]=true
    for i=1,100 do
        local name,v=debug.getupvalue(fn,i)
        if not name then break end
        if name==target then return v end
        if type(v)=='function' then
            local found=findUpvalue(v,target,seen)
            if found then return found end
        end
    end
end
local acquire=findUpvalue(namespace.TrackerZones.Initialize,'acquireOverflow')
local sampleFn=findUpvalue(namespace.TrackerZones.Initialize,'nativeSample')
assert(type(acquire)=='function','acquireOverflow no disponible en cierre')
assert(type(sampleFn)=='function','nativeSample no disponible en cierre')
local sample=assert(sampleFn(tracker))
assert(sample.titleInset==35,'sangria del titulo nativo no extraida: '..tostring(sample.titleInset))
assert(sample.rightInset==4,'margen derecho no extraido')
local block=acquire(tracker,2222,2,sample,1)
assert(block,'no se crea fila auxiliar')
assert(block.anchors[1][1]=='TOPLEFT','no se ancla la fila')
local row=block
local titleInset
-- Se inspeccionan nodos hijos mediante el pool capturado en las upvalues.
local pool=findUpvalue(namespace.TrackerZones.Initialize,'overflowPool')
assert(type(pool)=='table' and pool[1],'pool no disponible')
local record=pool[1]
assert(record.title.anchors[1][4]==35, 'la fila auxiliar no replica la sangria original')
assert(record.lines[1].anchors[1][4]==35, 'la linea de objetivo no replica la sangria original')
assert(record.poi.drawnStyle==2, 'mision con objetivo 0/1 mostrada como entregable')
assert(record.title.text:find('Conseguir la mercancía',1,true),'titulo erroneo')
assert(not record.title.text:find('Completa',1,true),'marca de completo espuria')
-- Simular cambio de seguimiento -> se recicla la fila. Su estado debe ser reescrito.
objectives={{text='Objetivo completado: 1/1',finished=true}}
complete=true
acquire(tracker,2222,2,sample,1)
assert(record.poi.drawnStyle==3,'mision completada no adquiere icono de entrega')
assert(record.title.text:find('Completa',1,true),'falta etiqueta de completa')
assert(record.title.anchors[1][4]==35,'la sangria cambia tras el reciclado')
objectives={{text='Baúl: 0/1',finished=false}}
complete=false
acquire(tracker,2222,2,sample,1)
assert(record.poi.drawnStyle==2,'el icono de entrega se queda atascado tras reciclado')
assert(record.title.anchors[1][4]==35,'la sangria se queda atascada tras reciclado')
-- Cuando la plantilla no soporta los metodos de estilo de Forever, no
-- aceptamos su '?' por defecto: usamos textura de progreso y boton privado.
unsupportedPOI=true
acquire(tracker,2222,2,sample,2)
local fallback=pool[2]
assert(fallback and fallback.poi.fallbackIcon, 'sin fallback de POI para build antigua')
assert(fallback.poi.fallbackIcon.atlas=='Quest-In-Progress-Icon-yellow',
    'fallback muestra un icono de entrega para una mision sin terminar')
assert(fallback.title.anchors[1][4]==35,'el fallback cambia el margen')
print('OK: iconos de progreso y entrega, fallback, reciclado, anchura y sangria nativa')
