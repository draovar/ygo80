-- [ygo_input] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- INPUT
-- ============================================================
function resetTurnFlags()
 for i=1,3 do
  if G.mon[1][i] then G.mon[1][i].attacked=false;G.mon[1][i].summoned=false;G.mon[1][i].posChanged=false end
  if G.mon[2][i] then G.mon[2][i].attacked=false;G.mon[2][i].summoned=false;G.mon[2][i].posChanged=false end
  if G.st[1][i] then G.st[1][i].setThisTurn=false end
  if G.st[2][i] then G.st[2][i].setThisTurn=false end
 end
 G.legionSummonUsed=false
 G.legionSearchUsed=false
 G.extraSpellcasterSummon=false
 G.legionSearchPending=false
end

function legionSearch(onDone)
 if G.legionSearchUsed then if onDone then onDone() end; return end
 G.legionSearchUsed=true
 local captured={}
 local items={}
 local function addItem(source,card,realIdx)
  if card.type=="spellcaster" and not card.effect then
   local n=#captured+1
   captured[n]={source=source,realIdx=realIdx}
   table.insert(items,{deckIdx=n,name=card.name,atk=card.atk,def=card.def,lvl=card.lvl,desc=card.desc})
  end
 end
 for i,id in ipairs(G.deck[1]) do addItem("deck",CARDS[id],i) end
 -- Necrovalley negates moving a card out of the GY: skip GY candidates.
 if not necrovalleyActive() then
  for i,card in ipairs(G.gy[1]) do addItem("gy",card,i) end
 end
 if #items==0 then if onDone then onDone() end; return end
 G.mode="sel_deck"
 G.deckSel={
  items=items,sel=1,title="LEGION  SPELLCASTER",
  onPick=function(idx)
   local src=captured[idx]
   if src.source=="deck" then
    table.insert(G.hand[1],makeCard(table.remove(G.deck[1],src.realIdx)))
   else
    table.insert(G.hand[1],table.remove(G.gy[1],src.realIdx))
   end
   if onDone then onDone() end
  end,
 }
end

function handleInput()
 if G.winner then
  local elapsed=G.tick-(G.winTick or 0)
  if elapsed>90 and btnp(4) then sync(3,0,false); SCENE="menu"; TITLE_SEL=1; G={tick=G.tick} end
  return
 end
 if #ANIM>0 then return end
 if G.infoCard then
  if btnp(5) or btnp(4) then G.infoCard=nil end
  return
 end
 local c=G.cur

 -- Deck selection (Sangan etc.)
 if G.mode=="sel_deck" and G.deckSel then
  handleDeckSelectInput()
  return
 end

 -- Graveyard viewer
 if G.mode=="gy_view" and G.gyView then
  local gv=G.gyView
  local gy=G.gy[gv.plr]
  if btnp(0) then gv.sel=math.min(#gy,gv.sel+1)
  elseif btnp(1) then gv.sel=math.max(1,gv.sel-1)
  elseif btnp(5) then G.mode="free"; G.gyView=nil end
  return
 end

 -- Trap activation prompt (fires during opponent's turn)
 if G.mode=="trap_ask" and G.trapAsk then
  if btnp(4) then
   local ta=G.trapAsk
   G.mode="free"; G.trapAsk=nil
   if ta.fromHand then
    discardFromHand(1,ta.handIdx,"cost")
    ta.onYes()
   else
    activateTrapAnim(ta.col,ta.card,ta.onYes)
   end
  elseif btnp(5) then
   local ta=G.trapAsk
   G.mode="free"; G.trapAsk=nil
   if ta.onNo then ta.onNo() end
  end
  return
 end

 -- Opponent-turn trap activation menu
 if G.mode=="opp_trap_select" and G.trapSelect then
  handleOppTrapSelectInput()
  return
 end

 -- Discard picker (e.g. Magic Jammer cost): cursor on player hand
 if G.mode=="sel_discard" and G.discardSel then
  local n=#G.hand[1]
  if n==0 then G.mode="opp_trap_select"; G.discardSel=nil; positionTrapSelectCursor(); return end
  if c.row~=3 then c.row=3; c.col=0 end
  if btnp(2) then c.col=math.max(0,c.col-1)
  elseif btnp(3) then c.col=math.min(n-1,c.col+1)
  elseif btnp(4) then
   local handIdx=c.col+1
   local picked=G.hand[1][handIdx]
   if picked then
    local cb=G.discardSel.onPick
    G.discardSel=nil; G.mode="free"
    cb(handIdx)
   end
  end
  return
 end

 -- S/T target picker (e.g. MST): cycles through every S/T card and field
 -- spell on the board. Any arrow key steps the selection; cursor snaps to it.
 if G.mode=="sel_st_target" and G.stTargetSel then
  local sts=G.stTargetSel
  local tgts=mstTargets(sts.source)
  if #tgts==0 then G.stTargetSel=nil; G.mode="free"; return end
  local idx=sts.idx or 1
  if idx>#tgts then idx=1 end
  if btnp(2) or btnp(0) then idx=((idx-2)%#tgts)+1
  elseif btnp(3) or btnp(1) then idx=(idx%#tgts)+1
  elseif btnp(4) then
   local t=tgts[idx]
   local cb=sts.onPick
   G.stTargetSel=nil; G.mode="free"
   cb(t.side,t.kind,t.di)
   return
  end
  sts.idx=idx
  local t=tgts[idx]
  G.cur={side=t.side,row=t.row,col=t.vcol}
  return
 end

 -- Attack target selection: cursor on opponent's monster zones
 if G.mode=="sel_atk" then
  local hasOppMon=hasMonsters(2)
  if btnp(2) then
   c.col=math.max(1,c.col-1)
  elseif btnp(3) then
   c.col=math.min(3,c.col+1)
  elseif btnp(4) then  -- A: confirm attack
   local p=G.pending
   p.tgtIdx=4-c.col
   -- An attacker's onAttackDeclared hook (e.g. Gravekeeper's Assailant) may
   -- run an interactive flow here, then resume via confirmPlayerAttack.
   declareAttack(p.attacker,1,confirmPlayerAttack)
  elseif btnp(5) then  -- B: cancel
   local col=G.pending and G.pending.atkCol or 2
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=1,col=col}
  end
  return
 end

 -- Tribute-select mode: pick monsters to tribute before summoning
 if G.mode=="sel_tribute" then
  if btnp(2) then
   for col=c.col-1,1,-1 do if G.mon[1][col] then c.col=col; break end end
  elseif btnp(3) then
   for col=c.col+1,3 do if G.mon[1][col] then c.col=col; break end end
  elseif btnp(4) then  -- A: toggle tribute selection
   local p=G.pending
   local col=c.col
   if col>=1 and col<=3 and G.mon[1][col] then
    local found=false
    for i,t in ipairs(p.tributes) do
     if t==col then table.remove(p.tributes,i); found=true; break end
    end
    if not found and tributeTotal(p)<p.tribNeeded then
     table.insert(p.tributes,col)
    end
    if tributeTotal(p)>=p.tribNeeded then
     local tribs={}
     for _,v in ipairs(p.tributes) do table.insert(tribs,v) end
     local zones={}
     for _,tcol in ipairs(tribs) do
      table.insert(zones,{x=COL[tcol],y=PY_M})
     end
     animTribute(zones,function()
      fireTributeSummonHook(p.card,1,tribs)
      for _,tcol in ipairs(tribs) do
       fireMonHook(G.mon[1][tcol],"onTributed",1)
       sendMonsterToGY(1,tcol,"tribute")
      end
      G.mode="sel_mon"
      G.cur={side=1,row=1,col=firstEmpty(G.mon[1]) or 1}
     end)
    end
   end
  elseif btnp(5) then  -- B: cancel
   local idx=G.pending and G.pending.handIdx-1 or 0
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=3,col=idx}
  end
  return
 end

 -- Zone-select mode: cursor locked to valid target zones
 if G.mode=="sel_mon" then
  if btnp(2) then  -- left: skip to prev empty zone
   for col=c.col-1,1,-1 do
    if not G.mon[1][col] then c.col=col; break end
   end
  elseif btnp(3) then  -- right: skip to next empty zone
   for col=c.col+1,3 do
    if not G.mon[1][col] then c.col=col; break end
   end
  elseif btnp(4) then  -- A: place card
   local col=c.col
   if col>=1 and col<=3 and not G.mon[1][col] then
    local p=G.pending
    local card=p.card
    if p.action=="set" then
     card=copyCard(p.card)
     card.pos=2; card.facedown=true
    end
    G.mon[1][col]=card
    card.summoned=true
    table.remove(G.hand[1],p.handIdx)
    if p.action=="summon" or p.action=="set" then G.normalSummoned=true end
    if p.action=="summon_extra" then G.extraSpellcasterSummon=false end
    G.mode="free"; G.pending=nil
    G.cur={side=1,row=1,col=col}
    if G.legionSearchPending then
     G.legionSearchPending=false; legionSearch()
    end
    if not card.facedown then fireSummonHook(card,1) end
    checkAITraps("summon",{card=card,monIdx=col})
   end
  elseif btnp(5) then  -- B: cancel, return cursor to the hand card
   local idx=G.pending and G.pending.handIdx-1 or 0
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=3,col=idx}
  end
  return
 end

 -- Spell/trap zone-select mode
 if G.mode=="sel_st" then
  if btnp(2) then
   for col=c.col-1,1,-1 do if not G.st[1][col] then c.col=col; break end end
  elseif btnp(3) then
   for col=c.col+1,3 do if not G.st[1][col] then c.col=col; break end end
  elseif btnp(4) then
   local col=c.col
   if col>=1 and col<=3 and not G.st[1][col] then
    local p=G.pending
    local card=copyCard(p.card)
    if p.action=="cast_hand" then
     card.facedown=false
     G.st[1][col]=card
     table.remove(G.hand[1],p.handIdx)
     G.mode="free"; G.pending=nil
     G.cur={side=1,row=2,col=col}
     local b=behaviorOf(card)
     if b and b.activate then
      b.activate{col=col,card=card,zone="st",plr=1}
     else
      animSpellActivation(col,PY_S,card,1)
     end
    else
     card.facedown=true; card.setThisTurn=true
     G.st[1][col]=card
     table.remove(G.hand[1],p.handIdx)
     G.mode="free"; G.pending=nil
     G.cur={side=1,row=2,col=col}
    end
   end
  elseif btnp(5) then
   local idx=G.pending and G.pending.handIdx-1 or 0
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=3,col=idx}
  end
  return
 end

 -- Equip spell: pick a face-up monster target
 if G.mode=="sel_equip" then
  if btnp(2) then c.col=math.max(1,c.col-1)
  elseif btnp(3) then c.col=math.min(3,c.col+1)
  elseif btnp(0) then if c.side==2 then c.side=1 end
  elseif btnp(1) then if c.side==1 then c.side=2 end
  elseif btnp(4) then
   local ti=(c.side==2) and (4-c.col) or c.col
   local target=G.mon[c.side][ti]
   if target and not target.facedown then
    local p=G.pending; G.mode="free"; G.pending=nil
    local card=p.card
    card.equippedTo={plr=c.side,col=ti}
    if p.action=="cast_equip" then
     local stCol=firstEmpty(G.st[1])
     if stCol then
      card.facedown=false
      G.st[1][stCol]=card
      table.remove(G.hand[1],p.handIdx)
      animSpellActivation(stCol,PY_S,card,1)
     end
    else  -- activate_equip (already in zone)
     card.facedown=false
     animSpellActivation(p.stCol,PY_S,card,1)
    end
    G.cur={side=1,row=2,col=firstOccupied(G.st[1]) or 1}
   end
  elseif btnp(5) then
   local idx=G.pending and G.pending.handIdx and G.pending.handIdx-1 or G.pending and G.pending.stCol or 0
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=3,col=idx}
  end
  return
 end

 -- Monster destroy picker (Man-Eater Bug = any; Thousand Knives = side 2 only)
 if G.mode=="sel_destroy" then
  local ds=G.destroySel
  if btnp(2) then c.col=math.max(1,c.col-1)
  elseif btnp(3) then c.col=math.min(3,c.col+1)
  elseif btnp(0) then if c.side==1 and ds.side~=1 then c.side=2 end
  elseif btnp(1) then if c.side==2 and ds.side~=2 then c.side=1 end
  elseif btnp(4) then
   local ti=(c.side==2) and (4-c.col) or c.col
   local grid=(c.side==1) and G.mon[1] or G.mon[2]
   if ti>=1 and ti<=3 and grid[ti] and (not ds.side or ds.side==c.side) then
    G.mode="free"; G.destroySel=nil
    ds.onPick(c.side,ti)
   end
  end
  return
 end

 -- Menu open: route all input into the menu
 if G.menu.open then
  if btnp(0) then  -- up
   G.menu.sel=math.max(1,G.menu.sel-1)
  elseif btnp(1) then  -- down
   G.menu.sel=math.min(#G.menu.items,G.menu.sel+1)
  elseif btnp(4) then  -- A: confirm
   execAction(G.menu.items[G.menu.sel][2])
  elseif btnp(5) and not G.menu.forced then  -- B: cancel (forced menus can't)
   G.menu.open=false
  end
  return
 end

 if btnp(0) then  -- up (toward opponent)
  local wasHand=(c.row==3)
  if c.side==1 then
   if    c.row==3 then c.row=2
   elseif c.row==2 then c.row=1
   else  c.side=2;c.row=1 end
  else
   if    c.row==1 then c.row=2
   elseif c.row==2 then c.row=3 end
  end
  if c.row==3 then clampToHand(c.side)
  elseif wasHand then c.col=math.min(c.col,4) end
 end

 if btnp(1) then  -- down (toward player)
  local wasHand=(c.row==3)
  if c.side==2 then
   if    c.row==3 then c.row=2
   elseif c.row==2 then c.row=1
   else  c.side=1;c.row=1 end
  else
   if    c.row==1 then c.row=2
   elseif c.row==2 then c.row=3 end
  end
  if c.row==3 then clampToHand(c.side)
  elseif wasHand then c.col=math.min(c.col,4) end
 end

 if btnp(2) then  -- left
  c.col=math.max(0,c.col-1)
 end

 if btnp(3) then  -- right
  if c.row==3 then
   c.col=math.min(math.max(0,#G.hand[c.side]-1),c.col+1)
  else
   c.col=math.min(4,c.col+1)
  end
 end

 if btnp(4) then
  if c.row==1 and c.col==4 and c.side==1 then  -- player GY
   if #G.gy[1]>0 then G.mode="gy_view"; G.gyView={plr=1,sel=#G.gy[1]} end
  elseif c.row==1 and c.col==0 and c.side==2 then  -- opp GY
   if #G.gy[2]>0 then G.mode="gy_view"; G.gyView={plr=2,sel=#G.gy[2]} end
  else
   local items=buildMenu()
   if items then
    G.menu={open=true,items=items,sel=1}
   else
    G.menu={open=false,items={},sel=1,hint=true}
   end
  end
 end

 -- B: open phase menu (player turn, free mode, no menu already open)
 if btnp(5) and G.active==1 and not G.menu.open then
  G.menu={open=true,sel=1,items={
   {"NEXT PHASE","nextphase"},
   {"END TURN",  "endturn"},
  }}
 end
end

-- ============================================================
-- AUTO-PHASE (player DRAW and STBY advance automatically)
-- ============================================================
function autoPhase()
 if G.active~=1 or G.winner or #ANIM>0 then return end
 if G.ph~=PH_DRAW and G.ph~=PH_STBY and G.ph~=PH_END then return end
 G.autoTimer=G.autoTimer-1
 if G.autoTimer<=0 then
  G.autoTimer=50
  if G.ph==PH_END then
   tickSwords()
   G.turn=G.turn+1; G.active=2; changePhase(PH_DRAW)
   G.normalSummoned=false; drawCard(2)
   resetTurnFlags(); G.aiTimer=AI_DELAY
  else
   changePhase(G.ph+1)
  end
 end
end

