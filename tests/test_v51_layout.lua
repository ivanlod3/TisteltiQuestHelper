local path, statuspath, sortpath=arg[1],arg[2],arg[3]
local function node(kind,parent)
 local n={kind=kind,anchors={},shown=false,width=242,height=17,parent=parent}
 function n:SetPoint(...) self.anchors[#self.anchors+1]={...} end
 function n:ClearAllPoints() self.anchors={} end
 function n:GetNumPoints() return #self.anchors end
 function n:GetPoint(i) local a=self.anchors[i]; if a then return table.unpack(a) end end
 function n:SetWidth(v) self.width=v end
 function n:SetHeight(v) self.height=v end
 function n:SetSize(w,h) self.width=w;self.height=h end
 function n:GetWidth() return self.width end
 function n:GetHeight() return self.height end
 function n:GetLeft() return self.left or 0 end
 function n:GetRight() return self.right or self:GetLeft()+self.width end
 function n:GetFont() return 'Fonts/FRIZQT__.TTF',12,'OUTLINE' end
 function n:GetFontObject() return {} end
 function n:SetFont() end
 function n:SetFontObject() end
 function n:SetJustifyH() end
 function n:SetWordWrap() end
 function n:SetMaxLines() end
 function n:SetHitRectInsets() end
 function n:IsProtected() return false end
 function n:SetText(t) self.text=t end
 function n:GetStringHeight() return 16 end
 function n:SetTextColor() end
 function n:SetColorTexture() end
 function n:SetVertexColor() end
 function n:SetAtlas(t) self.atlas=t end
 function n:SetTexture(t) self.texture=t end
 function n:SetAllPoints() end
 function n:RegisterForClicks() end
 function n:SetScript(name,func) self[name]=func end
 function n:Show() self.shown=true end
 function n:Hide() self.shown=false end
 function n:IsShown() return self.shown end
 function n:CreateFontString() return node('fontstring',self) end
 function n:CreateTexture() return node('texture',self) end
 function n:SetSelected(v) self.selected=v end
 function n:SetQuestID(v) self.questId=v end
 function n:SetStyle(v) self.style=v end
 function n:UpdateButtonStyle() self.drawnStyle=self.style end
 return n
end
CreateFrame=function(kind,_,parent,template) return node(template or kind,parent) end
GameFontNormal={}
NORMAL_FONT_COLOR={GetRGB=function() return 1,0.82,0 end}
POIButtonUtil={Style={QuestInProgress=2,QuestComplete=3}}
local n=3
local watchIDs={111,222,333}
local names={[111]='La hoja más afilada',[222]='No es mi circo',[333]='Conseguir la mercancía'}
local levels={[111]=38,[222]=38,[333]=40}
local objectives={[111]={{text='Piedra: 0/8',finished=false}},[222]={{text='Estofado: 0/10',finished=false}},[333]={{text='Baúl: 0/1',finished=false}}}
C_QuestLog={
 GetNumQuestWatches=function() return #watchIDs end,
 GetQuestIDForQuestWatchIndex=function(i) return watchIDs[i] end,
 GetNumQuestLogEntries=function() return n+1 end,
 GetInfo=function(i) if i==1 then return {isHeader=true,title='Clarofluvial'} end local id=watchIDs[i-1];return {isHeader=false,questID=id,title=names[id],isComplete=false,difficultyLevel=levels[id]} end,
 GetHeaderIndexForQuest=function() return 1 end,
 GetLogIndexForQuestID=function(id) for i,k in ipairs(watchIDs) do if k==id then return i+1 end end end,
 GetQuestObjectives=function(id) return objectives[id] end,
 GetTitleForQuestID=function(id) return names[id] end,
 GetQuestDifficultyLevel=function(id) return levels[id] end,
 GetQuestTagInfo=function() return {} end,
 IsComplete=function() return false end,
}
GetQuestDifficultyColor=function() return {r=.2,g=1,b=.3} end
local contents=node('contents');contents.width=242
local native1=node('native',contents);native1.id=111;native1.used=true;native1.height=39;native1.width=242;native1.left=25;native1.right=267;native1.shown=true
native1.HeaderText=node('fontstring',native1);native1.HeaderText.left=59;native1.HeaderText.right=262
native1.usedLines={{Text=node('fontstring')}}
native1:SetPoint('TOPLEFT',contents,'TOPLEFT',0,-12)
local native2=node('native',contents);native2.id=222;native2.used=true;native2.height=39;native2.width=242;native2.left=48;native2.right=290;native2.shown=true
native2.HeaderText=node('fontstring',native2);native2.HeaderText.left=82;native2.HeaderText.right=285
native2.usedLines={{Text=node('fontstring')}}
native2:SetPoint('TOPLEFT',native1,'BOTTOMLEFT',0,-5)
local tracker={ContentsFrame=contents,GetExistingBlock=function(self,id) if id==111 then return native1 elseif id==222 then return native2 end end}
_G.QuestObjectiveTracker=tracker
local ns={Config={Get=function(k) return k=='trackerZoneSections' end,Settings=function() return {trackerSortMode='zone_level_asc'} end},RecentQuests={RepaintRendered=function() end}}
assert(loadfile(statuspath))('addon',ns)
assert(loadfile(sortpath))('addon',ns)
assert(loadfile(path))('addon',ns)
local function findUpvalue(fn,target,seen)
 seen=seen or {}
 if seen[fn] then return end
 seen[fn]=true
 for i=1,90 do
  local name,v=debug.getupvalue(fn,i)
  if not name then break end
  if name==target then return v end
  if type(v)=='function' then
   local found=findUpvalue(v,target,seen)
   if found then return found end
  end
 end
end
local render=assert(findUpvalue(ns.TrackerZones.Initialize,'render'))
local positions=assert(findUpvalue(ns.TrackerZones.Initialize,'positions'))
local pool=assert(findUpvalue(ns.TrackerZones.Initialize,'overflowPool'))
render(tracker,true)
assert(#pool>=1 and pool[1].questID==333,'fila auxiliar ausente')
assert(#native1.anchors==2 and native1.anchors[1][4]==0,'primera misión desplazada horizontalmente')
assert(#native2.anchors==2 and native2.anchors[1][4]==0,'segunda misión desplazada horizontalmente')
assert(pool[1].frame.anchors[1][4]==0,'auxiliar desalineada horizontalmente')
assert(positions[native1][1][1]=='TOPLEFT' and positions[native1][1][5]==-12,'no conserva anclajes originales')
assert(positions[native2][1][2]==native1,'no conserva anclaje relativo de Blizzard')
-- EndLayout llama al hook incluso si los bloques mantenían nuestros anclajes.
render(tracker,true)
assert(positions[native1][1][5]==-12,'se corrompió la instantánea nativa de anchors')
assert(positions[native2][1][2]==native1,'se sobrescribió con anchors del addon')
-- El watcher nativo puede ser reciclado; no dibujar contenido de otro id.
native2.id=999
render(tracker,true)
assert(pool[1] and pool[1].questID==222 and pool[2] and pool[2].questID==333,'bloque reciclado debe usarse como auxiliar')
-- Un bloque `used=false` no se oculta nunca por el simple hecho de existir.
native2.used=false; native2.shown=true
render(tracker,true)
assert(native2.shown,'se ha ocultado un bloque liberado ajeno al addon')
print('OK anclajes nativos estables, x uniforme, overflow, reciclado y sin ocultar unused')
