local root, reference=assert(arg[1]),assert(arg[2])
local frames, watchWrites, nativeCalls, combat = {}, 0, 0, false
local function node(kind,parent)
 local n={kind=kind,parent=parent,anchors={},width=240,height=28,shown=true,writes=0,scripts={},clamp={0,0,0,0}}
 function n:GetClampRectInsets()return unpack(self.clamp)end
 function n:SetClampRectInsets(l,r,t,b)self.clamp={l,r,t,b}end
 function n:SetPoint(p,r,rp,x,y)
  self.writes=self.writes+1
  if type(r)=="number" then x,y,r,rp=r,rp,self.parent,p
  elseif r==nil then r,rp,x,y=self.parent,p,0,0 end
  local a={p,r,rp or p,x or 0,y or 0}
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
  if a then local top=a[2]:GetTop();if top==nil then return nil end;return top-(a[3]=='BOTTOM' and a[2]:GetHeight() or 0)+a[5] end
  local top=self.top or 0
  if self.clamped then
   -- Screen clamping moves geometry without changing the saved anchor.
   top=math.min(self.parent:GetTop()-self.clamp[3], math.max(top,
       self.parent:GetBottom()+self.height-self.clamp[4]))
  end
  return top
 end
 function n:GetRight()return self:GetLeft()+self:GetWidth()end
 function n:SetWidth(v)self.width=v;self.writes=self.writes+1 end
 function n:SetHeight(v)
  local old=self.height;self.height=v;self.writes=self.writes+1
  if old~=v and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self,self.width,v) end
 end
 function n:SetParent(p)self.parent=p end
 function n:GetParent()return self.parent end
 function n:GetBottom()return self:GetTop()-self:GetHeight()end
 function n:SetSize(w,h)self.width=w;self.height=h end
 function n:GetFont()return 'Fonts/FRIZQT__.TTF',12,''end
 function n:GetFontObject()return {}end
 function n:IsProtected()return self.protected or false end
 function n:SetText(t)self.text=t;if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self)end end
 function n:GetText()return self.text or ''end
 function n:GetStringHeight()return 12 end
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
 for _,k in ipairs({'RegisterEvent','RegisterForClicks','SetFont','SetFontObject','SetJustifyH','SetWordWrap','SetNonSpaceWrap','SetMaxLines','SetHitRectInsets','SetTextColor','SetColorTexture','SetVertexColor','SetAtlas','SetTexture','SetAllPoints','SetMaxLetters','SetAutoFocus','ClearFocus','SetFocus'})do n[k]=function()end end
 frames[#frames+1]=n;return n
end
CreateFrame=function(kind,_,parent)return node(kind,parent)end
InCombatLockdown=function()return combat end
local queue={}
C_Timer={After=function(_,f)queue[#queue+1]=f end}
local function drain()
 local loops=0
 while #queue>0 do local q=queue;queue={};for _,f in ipairs(q)do f()end;loops=loops+1;assert(loops<20,"bucle de actualizacion") end
end
hooksecurefunc=function(o,k,f)local old=o[k];o[k]=function(...)old(...);f(...)end end
GameFontNormal={};NORMAL_FONT_COLOR={GetRGB=function()return 1,.82,0 end}
local function noop()end
CreateFromMixins=function(...)local o={};for i=1,select('#',...)do for k,v in pairs(select(i,...) or {})do o[k]=v end end;return o end
EnumUtil={MakeEnum=function(...)local t={};for i=1,select('#',...)do t[select(i,...)]=i end;return t end}
Enum={QuestClassification={Campaign=9}}
ObjectiveTrackerSlidingMixin={ClearFanfares=noop}
AutoQuestPopupTrackerMixin={AddAutoQuestObjectives=noop}
ObjectiveTrackerAnimLineMixin={};ObjectiveTrackerAnimLineState={Present=1,Completed=2,Completing=3,Faded=4}
TRACKER_HEADER_QUESTS='Misiones';QUEST_WATCH_QUEST_READY='Lista';OBJECTIVE_TRACKER_COLOR={Complete={}}
-- Execute the original dirty queue, including its pre-hook method capture.
RunNextFrame=function(f)C_Timer.After(0,f)end
assert(loadfile(reference..'/MixinUtil.lua'))()
EventRegistry={RegisterCallback=noop}
GenerateClosure=function(fn,obj,dirty)return function()fn(obj,dirty)end end
IsInInstance=function()return false,'none'end
GetMoney=function()return 0 end
GetNumQuestLeaderBoards=function()return 1 end
GetQuestLogLeaderBoard=function(_,index)return 'Objetivo '..index,'monster',false end
GetQuestLogCompletionText=function()return nil end
QuestMapFrame_GetFocusedQuestID=function()return 0 end
IsQuestSequenced=function()return false end
SetQuestTitleLevelAndDifficultyColor=function(id,title)return '['..id..'] '..title end
QuestUtil={CanCreateQuestGroup=function()return false end,QuestShowsItemByIndex=function()return false end}
C_SuperTrack={GetSuperTrackedQuestID=function()return 0 end}
EditModeManagerFrame={IsEditModeActive=function()return false end}
ManageFramePositions=noop
local ids,quests={},{}
for id=1,23 do
 ids[id]=id
 local q={title='Mision '..id,requiredMoney=0}
 function q:GetID()return id end
 function q:GetQuestLogIndex()return id end
 function q:IsComplete()return id==23 end
 function q:IsCalling()return false end
 function q:IsDisabledForSession()return false end
 function q:GetQuestClassification()return 0 end
 quests[id]=q
end
QuestCache={Get=function(_,id)return quests[id]end}
C_QuestLog={GetNumQuestWatches=function()return #ids end,GetQuestIDForQuestWatchIndex=function(i)return ids[i]end,
 GetNumQuestLogEntries=function()return #ids+1 end,
 GetInfo=function(i)if i==1 then return {isHeader=true,title='Zona'}end;return {questID=ids[i-1]}end,
 GetTitleForQuestID=function(id)return quests[id].title end,
 GetQuestDifficultyLevel=function(id)return id end,
 GetLogIndexForQuestID=function(id)return id end,
 GetQuestObjectives=function(id)return {{text='Objetivo '..id}}end,
 IsFailed=function()return false end,GetNextWaypointText=function()return nil end,GetTimeAllowed=function()return nil end,
 AddQuestWatch=function()watchWrites=watchWrites+1 end,RemoveQuestWatch=function()watchWrites=watchWrites+1 end}
local allocations,releases=0,0
ObjectiveTrackerManager={AcquireFrame=function(_,module,template)
 allocations=allocations+1
 local b=node('native');b.template=template;b.usedLines={}
 b.HeaderText=node('title',b);b.poiButton=node('poi',b)
 function b:Init()end
 function b:Reset()self.used=false;self.height=0 end
 function b:SetHeader(t)self.HeaderText:SetText(t);self.height=24 end
 function b:GetExistingLine(k)return self.usedLines[k]end
 function b:AddObjective(k,t)
  self.height=self.height+28
  local line=self.usedLines[k] or {state=1,Text=node('text',self),SetState=function(l,v)l.state=v end}
  line.Text:SetText(t);self.usedLines[k]=line;return line
 end
 function b:ForEachUsedLine(fn)for k,l in pairs(self.usedLines)do fn(l,k)end end
 function b:SetPOIInfo(id,complete)self.poiButton.questID=id;self.poiButton.complete=complete end
 function b:OnLayout()self.poiButton:SetPoint('TOPRIGHT',self.HeaderText,'TOPLEFT',-7,5)end
 function b:Free()self:Hide()end
 return b,true
end,ReleaseFrame=function()releases=releases+1 end}
assert(loadfile(reference..'/Blizzard_ObjectiveTrackerModule.lua'))()
assert(loadfile(reference..'/Blizzard_QuestObjectiveTracker.lua'))()
assert(loadfile(reference..'/Blizzard_ObjectiveTrackerContainer.lua'))()
local function mix(target,source)for k,v in pairs(source)do if target[k]==nil then target[k]=v end end end
local ui=node('ui');ui.top=1000;ui.height=1000
local container=node('container',ui);mix(container,ObjectiveTrackerContainerMixin)
container.height=800;container.top=900;container.left=2515;container.width=260
container.clamped=true;container.clamp={-3,4,5,-6}
container:OnLoad()
container.topModulePadding=38;container.bottomModulePadding=10;container.moduleSpacing=10
container.topPaddingProviders={};container.modules={};container.NineSlice=node('background',container)
container.IsInDefaultPosition=function()return false end
container:SetScript('OnSizeChanged',container.OnSizeChanged)
local tracker=node('tracker',container);mix(tracker,QuestObjectiveTrackerMixin)
tracker.Header=node('header',tracker);tracker.Header.Text=node('font');tracker.Header.MinimizeButton=node('button')
tracker.Header.PlayAddAnimation=noop
tracker.ContentsFrame=node('contents',tracker);tracker.ContentsFrame.width=260
tracker.ContentsFrame:SetPoint('TOPLEFT',tracker,'TOPLEFT',0,-26)
tracker.parentContainer=container;tracker.usedBlocks={};tracker.uiOrder=2
container.modules={tracker};_G.QuestObjectiveTracker=tracker
container:Update()
local function nativeCount()local count=0;for _,id in ipairs(ids)do local b=tracker:GetExistingBlock(id);if b and b.used then count=count+1 end end;return count end
assert(nativeCount()>0 and nativeCount()<23,'La referencia nativa debe reproducir el corte por altura')
local originalCount=nativeCount()
local originals={};for _,k in ipairs({'EnumQuestWatchData','BuildQuestWatchInfos','UpdateSingle','CanFitBlock','GetBlock','MarkDirty'})do originals[k]=tracker[k]end
local opts={trackerZoneSections=true,trackerScrollBeta=true,trackerSearchButton=true}
local ns={Config={Get=function(k)return opts[k]end},TrackerSort={IsActive=function()return false end,Order=function(a)table.sort(a,function(x,y)return x.id<y.id end)end}}
assert(loadfile(root..'/QuestHelper_NativeCapacity.lua'))('addon',ns)
assert(loadfile(root..'/QuestHelper_TrackerZones.lua'))('addon',ns)
container:MarkDirty() -- primera activacion dentro del callback nativo ya pendiente
ns.TrackerZones.Initialize();drain()
assert(nativeCount()==originalCount,"addon changed native construction limit")
assert(container:GetHeight()==800 and ns.NativeCapacity.GetState().reason=="native-read-only")
local function checkPosition()
 assert(container:GetHeight()==800 and container:GetTop()==900)
 local l,r,t,b=container:GetClampRectInsets()
 assert(l==-3 and r==4 and t==5 and b==-6)
end
for k,v in pairs(originals)do assert(tracker[k]==v,'metodo nativo sustituido: '..k)end
local function checkPage()
 checkPosition()
 local s=ns.TrackerZones.GetDiagnosticState()
 assert(#s.auxiliary==0 and s.native==nativeCount())
 for _,g in ipairs(s.geometry)do
  local b=tracker:GetExistingBlock(g.id)
  assert(b.used and b.id==g.id and b.parentModule==tracker)
  assert(b:GetWidth()==240 and b:GetHeight()==52)
  assert(b:GetLeft()==2535 and b.poiButton.questID==g.id)
  assert(g.y+g.height<=s.capacity.view)
 end
 return s
end
local nativeIDs={}
for _,id in ipairs(ids)do local b=tracker:GetExistingBlock(id);if b and b.used then nativeIDs[id]=true end end
local seen={}
for i=1,40 do for _,g in ipairs(checkPage().geometry)do seen[g.id]=true end;tracker.scripts.OnMouseWheel(tracker,-1)end
for id in pairs(nativeIDs) do assert(seen[id],"unreachable native row "..id) end
for id in pairs(seen) do assert(nativeIDs[id],"non-native row "..id) end
local before=allocations
for i=1,200 do container:Update();drain()end
assert(allocations==before,"native pool grew")
checkPage()
assert(watchWrites==0,"addon mutated watches")
print("OK native-only presentation: available native rows pageable; no expansion, replacement, or watch changes")
