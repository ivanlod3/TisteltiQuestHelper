local root=assert(arg[1])
local mouseDown = false
IsMouseButtonDown=function()return mouseDown end
local frames, watchWrites, nativeCalls, combat = {}, 0, 0, false
local registered={}
local function node(kind,parent)
 local n={kind=kind,parent=parent,anchors={},width=240,height=28,shown=true,writes=0,scripts={}}
 function n:SetPoint(p,r,rp,x,y)
  self.writes=self.writes+1
  local a={p,r,rp,x or 0,y or 0}
  for i,v in ipairs(self.anchors)do if v[1]==p then self.anchors[i]=a;return end end
  self.anchors[#self.anchors+1]=a
 end
 function n:ClearAllPoints()self.writes=self.writes+1;self.anchors={}end
 function n:GetNumPoints()return #self.anchors end
 function n:GetPoint(i)return unpack(self.anchors[i])end
 function n:Anchor(p)for _,a in ipairs(self.anchors)do if a[1]==p then return a end end end
 function n:GetLeft()local a=self:Anchor('LEFT') or self:Anchor('TOPLEFT');return a and a[2]:GetLeft()+a[4] or self.left or 0 end
 function n:GetWidth()
  local a=self:Anchor('RIGHT')
  return a and a[2]:GetLeft()+a[2]:GetWidth()+a[4]-self:GetLeft() or self.width
 end
 function n:GetHeight()return self.height end
 function n:GetTop()
  local a=self:Anchor('TOP') or self:Anchor('TOPLEFT')
  if a then return a[2]:GetTop()-(a[3]=='BOTTOM' and a[2]:GetHeight() or 0)+a[5] end
  return self.top or 0
 end
 function n:GetRight()return self:GetLeft()+self:GetWidth()end
 function n:SetWidth(v)self.width=v;self.writes=self.writes+1 end
 function n:SetHeight(v)self.height=v;self.writes=self.writes+1 end
 function n:SetSize(w,h)self.width=w;self.height=h end
 function n:GetFont()return 'Fonts/FRIZQT__.TTF',12,''end
 function n:GetFontObject()return {}end
 function n:IsProtected()return self.protected or false end
 function n:GetParent()return self.parent end
 function n:SetText(t)self.text=t;if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self)end end
 function n:GetText()return self.text or ''end
 function n:GetStringHeight()return 12 end
 function n:IsMouseOver()return self.mouseOver or false end
 function n:HasFocus()return self.focused or false end
 function n:SetFocus()self.focused=true end
 function n:ClearFocus()local had=self.focused;self.focused=false;if had and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self)end end
 function n:SetScript(k,f)self.scripts[k]=f end
 function n:GetScript(k)return self.scripts[k]end
 function n:HookScript(k,f)local old=self.scripts[k];self.scripts[k]=function(...)if old then old(...)end;f(...)end end
 function n:EnableMouseWheel(v)self.wheel=v end
 function n:IsMouseWheelEnabled()return self.wheel end
 function n:Show()self.shown=true end
 function n:Hide()self.shown=false end
 function n:IsShown()return self.shown end
 function n:SetShown(v)self.shown=v end
 function n:CreateFontString()return node('font',self)end
 function n:CreateTexture()return node('texture',self)end
 for _,k in ipairs({'RegisterEvent','RegisterForClicks','SetFont','SetFontObject','SetJustifyH','SetWordWrap','SetNonSpaceWrap','SetMaxLines','SetHitRectInsets','SetTextColor','SetColorTexture','SetVertexColor','SetAtlas','SetTexture','SetAllPoints','SetMaxLetters','SetAutoFocus','unusedFocus'})do n[k]=function()end end
 function n:RegisterEvent(event) registered[event]=true end
 frames[#frames+1]=n;return n
end
CreateFrame=function(kind,_,parent,template)
 local f=node(kind,parent)
 if template=='SearchBoxNineSliceTemplate' then
  f.Instructions=node('instructions',f);f.clearButton=node('clear',f);f.clearButton:Hide()
  f:SetScript('OnTextChanged',function(self)
   local empty=self:GetText()==''
   self.Instructions:SetShown(empty);self.clearButton:SetShown(not empty)
  end)
  f:SetScript('OnEditFocusLost',function(self)self.nativeBlur=true end)
  f.clearButton:SetScript('OnClick',function()f:SetText('');f:ClearFocus();f.nativeClear=true end)
 end
 return f
end
InCombatLockdown=function()return combat end
C_Timer={After=function(_,f)f()end}
hooksecurefunc=function(o,k,f)local old=o[k];o[k]=function(...)old(...);f(...)end end
GameFontNormal={};NORMAL_FONT_COLOR={GetRGB=function()return 1,.82,0 end}
local ids={101,102,103,104,105,106}
local names={[101]='Cero',[102]='Dos',[103]='Uno',[104]='Cuatro',[105]='Cinco',[106]='Seis'}
C_QuestLog={GetNumQuestWatches=function()return #ids end,GetQuestIDForQuestWatchIndex=function(i)return ids[i]end,
 GetNumQuestLogEntries=function()return #ids+1 end,
 GetInfo=function(i)if i==1 then return {isHeader=true,title='Zona'} end return {isHeader=false,questID=ids[i-1]}end,
 GetTitleForQuestID=function(id)return names[id]end,
 GetQuestDifficultyLevel=function(id)return id end,
 GetLogIndexForQuestID=function(id)return id-99 end,
 GetQuestObjectives=function()return {}end,
 AddQuestWatch=function()watchWrites=watchWrites+1 end,RemoveQuestWatch=function()watchWrites=watchWrites+1 end}
local content=node('contents');content.left=2515;content.top=850;content.width=260
local tracker=node('tracker');tracker.top=876;tracker.height=751;tracker.availableHeight=753
tracker.ContentsFrame=content;tracker.fromHeaderOffsetY=-10;tracker.fromBlockOffsetY=-10
tracker.Header=node('header',tracker);tracker.Header.Text=node('font');tracker.Header.MinimizeButton=node('button')
local blocks={}
local function resetNative()
 local previous
 for _,id in ipairs(ids)do
  local b=blocks[id];b:ClearAllPoints();b:SetPoint('TOP',previous or content,previous and 'BOTTOM' or 'TOP',0,-10)
  b:SetPoint('LEFT',content,'LEFT',20,0)
  if id~=103 then b:SetPoint('RIGHT',content,'RIGHT',0,0)end
  b:Show();previous=b
 end
end
for _,id in ipairs(ids)do
 local b=node('native',content);b.id=id;b.used=true;b.height=id==102 and 68 or 140;b.width=160
 b.HeaderText=node('title',b);b.usedLines={{Text=node('objective',b)}};b.POIButton=node('poi',b)
 blocks[id]=b
end
resetNative()
-- Independently anchored native item button should follow the owning quest.
local item=node('item',content)
item:SetPoint('TOPLEFT',content,'TOPLEFT',20,-10)
blocks[101].ItemButton=item
function tracker:GetExistingBlock(id)return blocks[id]end
function tracker:EndLayout()end
function tracker:MarkDirty()nativeCalls=nativeCalls+1 end
function tracker:Update()nativeCalls=nativeCalls+1 end
_G.QuestObjectiveTracker=tracker
local opts={trackerZoneSections=true,trackerScrollBeta=true,trackerSearchButton=true}
local ns={Config={Get=function(k)return opts[k]end},TrackerSort={IsActive=function()return false end,Order=function(a)table.sort(a,function(x,y)return x.id<y.id end)end}}
assert(loadfile(root..'/QuestHelper_NativeCapacity.lua'))('addon',ns)
assert(loadfile(root..'/QuestHelper_TrackerZones.lua'))('addon',ns)
local function upvalue(fn,key,seen)
 seen=seen or {};if seen[fn]then return end;seen[fn]=true
 for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end
  if n==key then return v end
  if type(v)=='function'then local f=upvalue(v,key,seen);if f then return f end end
 end
end
local render=assert(upvalue(ns.TrackerZones.Initialize,'render'))
local positions=assert(upvalue(ns.TrackerZones.Initialize,'positions'))
ns.TrackerZones.Initialize()
local function checkGeometry()
 for _,id in ipairs(ids)do
  local b=blocks[id]
  assert(b:GetLeft()==2535,'margen nativo perdido')
  assert(b:GetWidth()==(id==103 and 160 or content.width-20),'ancho original perdido')
  assert(b:GetHeight()==(id==102 and 68 or 140),'altura original perdida')
  assert(b:GetNumPoints()==(id==103 and 2 or 3),'anclajes nativos eliminados')
  local corner=b:Anchor('TOPLEFT');if corner then assert(corner[4]==b:Anchor('LEFT')[4], 'centro horizontal contradictorio')end
  assert(b.HeaderText.writes==0 and b.usedLines[1].Text.writes==0 and b.POIButton.writes==0,'region interna modificada')
 end
end
checkGeometry()
assert(math.abs(item:GetTop()-blocks[101]:GetTop())<1,
 'item independently anchored to contents did not follow its native quest')
local state=ns.TrackerZones.GetDiagnosticState()
assert(state.native==6 and #state.auxiliary==0)
for event in pairs(registered) do assert(event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED" or event=="PLAYER_REGEN_DISABLED","unexpected tracker subscription: "..event) end
assert(not registered.QUEST_LOG_UPDATE and not registered.UNIT_QUEST_LOG_CHANGED)
local writesBeforeSwap=blocks[101].writes
ns.TrackerZones.RefreshAfterWatchSwap()
assert(blocks[101].writes==writesBeforeSwap,"watch swap rendered before native layout")
tracker:EndLayout()
state=ns.TrackerZones.GetDiagnosticState()
assert(state.geometry[1].y==37,'margen inicial nativo de 10 no conservado')
for i=2,#state.geometry do local a,b=state.geometry[i-1],state.geometry[i];assert(b.y==a.y+a.height+10,'separacion nativa alterada')end
assert(state.last<#ids+1,'paginacion no activada')
for _,r in ipairs(state.geometry)do assert(r.y+r.height<=727,'fila fuera de altura disponible de ContentsFrame')end
local observed={}
for step=1,10 do
 for _,r in ipairs(ns.TrackerZones.GetDiagnosticState().geometry)do observed[r.id]=true end
 tracker.scripts.OnMouseWheel(tracker,-1);checkGeometry()
end
for _,id in ipairs(ids)do assert(observed[id],'mision nativa inaccesible por scroll')end
for step=1,10 do tracker.scripts.OnMouseWheel(tracker,1)end
assert(ns.TrackerZones.GetDiagnosticState().index==1)
-- A saved legacy scroll=false value must not disable overflow scrolling.
opts.trackerScrollBeta=false
ns.TrackerZones.RefreshSettings("trackerScrollBeta")
local pager=upvalue(ns.TrackerZones.Initialize,"pager")
assert(not pager or not pager.frame:IsShown(),"artificial pager shown with working wheel")
assert(tracker:IsMouseWheelEnabled(),"overflow does not enable wheel")
local seen={}
for step=1,12 do
 local current=ns.TrackerZones.GetDiagnosticState()
 for _,r in ipairs(current.geometry)do
  assert(r.y+r.height<=current.viewport,"quest overflows native viewport")
  seen[r.id]=true
 end
 tracker.scripts.OnMouseWheel(tracker,-1)
end
for _,id in ipairs(ids)do assert(seen[id],"unreachable native row")end
for step=1,12 do tracker.scripts.OnMouseWheel(tracker,1)end
local foldHeadings=assert(upvalue(ns.TrackerZones.Initialize,"headings"))
for i=1,6 do
 foldHeadings[1].frame.scripts.OnClick()
 local current=ns.TrackerZones.GetDiagnosticState()
 for _,r in ipairs(current.geometry)do assert(r.y+r.height<=current.viewport,"fold overflow")end
 if i%2==1 then assert(not tracker:IsMouseWheelEnabled(),"wheel captured when all rows fit") end
end
assert(tracker:IsMouseWheelEnabled(),"unfold did not restore wheel")
opts.trackerScrollBeta=true
ns.TrackerZones.RefreshSettings("trackerScrollBeta")
-- Repetir EndLayout sin un nuevo AnchorBlock no debe contaminar el respaldo.
local stableWrites=blocks[101].writes
local h=tracker:GetHeight()
for i=1,200 do tracker:EndLayout()end
assert(blocks[101].writes==stableWrites,'layout estable vuelve a escribir anclajes')
assert(tracker:GetHeight()==h,'se modifico altura nativa')
checkGeometry();assert(positions[blocks[102]][1][2]==blocks[101])
assert(positions[blocks[101]][1][5]==-10)
-- Los anclajes laterales siguen respondiendo al ancho del padre.
content.width=300;render(tracker,false);checkGeometry()
-- Un layout nativo real sustituye la captura guardada, incluida la separacion.
resetNative();tracker.fromBlockOffsetY=-14;tracker:EndLayout();checkGeometry()
state=ns.TrackerZones.GetDiagnosticState();assert(state.geometry[2].y==state.geometry[1].y+state.geometry[1].height+14)
-- Buscador real: usar el handler instalado en el EditBox.
local search;for _,f in ipairs(frames)do if f.kind=='EditBox'then search=f end end
assert(search and search.Instructions:IsShown());search:SetText('Dos');state=ns.TrackerZones.GetDiagnosticState()
assert(not search.Instructions:IsShown() and search.clearButton:IsShown(),'Buscar se superpone al texto escrito')
assert(#state.geometry==1 and state.geometry[1].id==102,'busqueda no filtra')
search:SetText('');checkGeometry()
assert(search.Instructions:IsShown() and not search.clearButton:IsShown(),'el campo vacio no recupera ayuda nativa')
search.scripts.OnEditFocusLost(search);assert(search.nativeBlur,'se perdio OnEditFocusLost nativo')
-- Reproducir los dos ordenes de eventos de un clic y ambas preferencias.
local magnifier=assert(upvalue(ns.TrackerZones.Initialize,'searchButton'))
local function click(button,blurFirst)
 mouseDown=true;button.mouseOver=true
 if blurFirst=='beforeDown' then search:ClearFocus()end
 if button.scripts.OnMouseDown then button.scripts.OnMouseDown(button)end
 if blurFirst then search:ClearFocus()end
 button.scripts.OnClick(button)
 mouseDown=false;button.mouseOver=false
end
local function opened()
 click(magnifier,false)
 assert(search:IsShown() and search:HasFocus() and not tracker.Header.Text:IsShown())
 search:SetText('Dos')
 assert(#ns.TrackerZones.GetDiagnosticState().geometry==1)
end
local function closed()
 assert(not search:IsShown() and not search:HasFocus() and tracker.Header.Text:IsShown(),'campo no cerrado')
 assert(search:GetText()=='' and ns.TrackerZones.GetDiagnosticState().query=='','filtro no limpiado')
 assert(#ns.TrackerZones.GetDiagnosticState().geometry>1,'misiones no restauradas')
 assert(search.Instructions:IsShown(),'ayuda nativa no restaurada')
end
for _,keep in ipairs({true,false})do
 opts.trackerSearchKeepOnBlur=keep
 for _,blurFirst in ipairs({true,false,'beforeDown'})do
  opened();click(search.clearButton,blurFirst);closed()
  assert(search.nativeClear,'se sustituyo el manejador nativo de la X')
  opened();click(magnifier,blurFirst);closed()
 end
 opened();search:ClearFocus()
 if keep then
  assert(search:IsShown() and search:GetText()=='Dos' and #ns.TrackerZones.GetDiagnosticState().geometry==1,'no conserva al perder foco')
  search:SetText('');closed()
 else closed()end
 opened();search:SetText('');assert(search:IsShown(),'vaciar mientras escribe cierra el campo');search:ClearFocus();closed()
 opened();search.scripts.OnEscapePressed(search);closed()
 opened();search.scripts.OnEnterPressed(search)
 if keep then assert(search:IsShown());click(search.clearButton,false)end
 closed()
end
print('OK X, lupa, Escape, Enter y blur con conservar activado/desactivado; ambos ordenes de eventos')

-- Independently parented item visibility follows all presentation paths.
local initiallyHidden=node('item',content)
initiallyHidden:Hide();blocks[102].ItemButton=initiallyHidden
local child=node('item',blocks[103]);blocks[103].ItemButton=child
local protected=node('item',content);protected.protected=true;blocks[104].ItemButton=protected
local writes=0
local hide,show=item.Hide,item.Show
function item:Hide() writes=writes+1;hide(self) end
function item:Show() writes=writes+1;show(self) end
local headings=assert(upvalue(ns.TrackerZones.Initialize,'headings'))
assert(item:IsShown())
headings[1].frame.scripts.OnClick();assert(#ns.TrackerZones.GetDiagnosticState().geometry==0)
assert(not item:IsShown(),"external item floated after fold")
assert(not initiallyHidden:IsShown() and child:IsShown() and protected:IsShown(),"native hidden/child/protected item changed")
local stable=writes;tracker:EndLayout();assert(writes==stable,"redundant item visibility writes")
-- Simulate a genuine next-frame timer, not the synchronous default mock.
-- A native rebuild must restore visibility before any queued callback runs.
local immediateTimer=C_Timer.After
local pending={}
C_Timer.After=function(_,f)pending[#pending+1]=f end
resetNative()
show(item)
tracker:EndLayout()
assert(#pending==0,"native EndLayout scheduled a deferred presentation")
assert(#ns.TrackerZones.GetDiagnosticState().geometry==0,"folded rows rendered before next frame")
for _,id in ipairs(ids)do assert(not blocks[id]:IsShown(),"native rebuild exposed folded row "..id)end
assert(not item:IsShown(),"native rebuild exposed folded item")
C_Timer.After=immediateTimer
headings[1].frame.scripts.OnClick();assert(#ns.TrackerZones.GetDiagnosticState().geometry>0)
assert(item:IsShown() and not initiallyHidden:IsShown(),"unfold must only restore addon-hidden items")
search:SetText('Dos');assert(not item:IsShown(),"search exposed filtered item")
search:SetText('');assert(item:IsShown(),"search reset did not restore item")
-- The first step can move from a zone heading to its first quest;
-- advance until that quest actually leaves the viewport.
for i=1,10 do
 if not blocks[101]:IsShown() then break end
 tracker.scripts.OnMouseWheel(tracker,-1)
end
assert(not blocks[101]:IsShown() and not item:IsShown(),"scroll exposed offscreen item")
for i=1,10 do tracker.scripts.OnMouseWheel(tracker,1) end
assert(item:IsShown(),"scroll return did not restore item")
-- Replacing an owned button must never resurrect the old pooled object.
headings[1].frame.scripts.OnClick();assert(not item:IsShown())
local replacement=node('item',content);replacement:Hide();blocks[101].ItemButton=replacement
headings[1].frame.scripts.OnClick()
assert(not item:IsShown() and not replacement:IsShown(),"recycled/hidden item resurrected")
blocks[101].ItemButton=item;show(item)
-- Disabling presentation restores only visibility we own.
headings[1].frame.scripts.OnClick();assert(not item:IsShown())
opts.trackerZoneSections=false;render(tracker,false)
assert(item:IsShown() and not initiallyHidden:IsShown(),"disable failed to restore owned visibility")
opts.trackerZoneSections=true;TisteltiQuestHelperCharDB.trackerFoldedZones={};resetNative();render(tracker,true)
-- No escribir ni mover en combate.
local writes=blocks[101].writes;combat=true;tracker.scripts.OnMouseWheel(tracker,-1);tracker:EndLayout();assert(blocks[101].writes==writes);combat=false
-- Apagar las funciones restaura la cadena nativa, no anclajes propios.
opts.trackerZoneSections=false;render(tracker,false)
assert(blocks[101]:Anchor('TOP')[5]==-10)
assert(blocks[102]:Anchor('TOP')[2]==blocks[101]);checkGeometry()
-- No restaurar un frame que Blizzard ya ha reasignado o liberado.
opts.trackerZoneSections=true;resetNative();render(tracker,true)
local old=blocks[106];old.id=999;old.used=false;local w=old.writes
opts.trackerZoneSections=false;render(tracker,false);assert(old.writes==w,'se modifico un bloque liberado')
old.id=106;old.used=true
-- Geometria ajena desconocida: devolver layout original, sin aplanarla.
resetNative();blocks[101]:ClearAllPoints();blocks[101]:SetPoint('TOPLEFT',content,'TOPLEFT',33,-12)
opts.trackerZoneSections=true;render(tracker,true)
assert(blocks[101]:GetNumPoints()==1 and blocks[101]:GetPoint(1)=='TOPLEFT')
assert(blocks[101].anchors[1][4]==33 and ns.TrackerZones.GetDiagnosticState().rows==0)
assert(watchWrites==0 and nativeCalls==0,'se altero seguimiento o layout nativo')
print("OK geometria exclusivamente nativa, scroll, busqueda, plegado y cero cambios de seguimiento")
