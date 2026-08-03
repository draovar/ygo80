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
 G.legionSearchUsed={}
 G.extraSpellcasterSummon=false
end

-- Legion: search deck (+ GY when Necrovalley is not active) for a
-- vanilla Spellcaster and add it to hand. Yields via choose{}, so callers
-- must invoke this from inside a proc coroutine frame.
function legionSearch(plr)
 G.legionSearchUsed=G.legionSearchUsed or {}
 if G.legionSearchUsed[plr] then return end
 G.legionSearchUsed[plr]=true
 local items={}
 local function addItem(source,card,realIdx)
  if card.type=="spellcaster" and not card.effect then
   table.insert(items,{source=source,realIdx=realIdx,deckIdx=realIdx,card=card,
    name=card.name,atk=card.atk,def=card.def,lvl=card.lvl,desc=card.desc})
  end
 end
 for i,id in ipairs(G.deck[plr]) do addItem("deck",CARDS[id],i) end
 if not staticActive("blocksGYMoves") then
  for i,card in ipairs(G.gy[plr]) do addItem("gy",card,i) end
 end
 if #items==0 then return end
 local ans=choose{kind="card",plr=plr,items=items,title="LEGION  SPELLCASTER"}
 if not ans then return end
 local it=ans.item
 if it.source=="deck" then
  table.insert(G.hand[plr],makeCard(table.remove(G.deck[plr],it.realIdx)))
 else
  table.insert(G.hand[plr],table.remove(G.gy[plr],it.realIdx))
 end
end

-- Response-window picker for cards with listens.X + optional=true.
-- Reads G.proc.currentChoice (set by procRouteChoice when kind="response"
-- and plr==1). Left/right cycle eligible responders, A activates the one
-- at cursor, B passes priority. Both submit via INTENTS.RESPONSE.
function handleChooseResponse()
 local req=G.proc and G.proc.currentChoice
 -- Defensive: if mode is "choose_response" but the actual request was lost
 -- (cleared by a parallel code path, or never set due to a stale frame),
 -- recover to free mode so the player isn't softlocked at the prompt.
 if not (req and req.options and #req.options>0) then
  G.mode="free"
  if G.proc then G.proc.currentChoice=nil end
  return
 end
 local c=G.cur
 -- Zone helpers: convert listener.self {zone,col} <-> cursor {row,col}.
 -- Hand is row=3 with cursor col = listener col - 1 (cursor is 0-based,
 -- listener tracks 1-based hand index).
 local function rowFor(s)
  return (s.zone=="mon" and 1) or (s.zone=="hand" and 3) or 2
 end
 local function curColFor(s)
  return (s.zone=="hand") and (s.col-1) or s.col
 end
 local function findOptIdx()
  for i,opt in ipairs(req.options) do
   local s=opt.self
   if s.plr==c.side and c.col==curColFor(s) and c.row==rowFor(s) then
    return i
   end
  end
  return nil
 end
 if btnp(2) or btnp(3) then
  local n=#req.options
  local cur=findOptIdx() or 1
  local nxt=btnp(3) and (cur%n+1) or ((cur-2)%n+1)
  local s=req.options[nxt].self
  G.cur={side=s.plr,row=rowFor(s),col=curColFor(s)}
 elseif btnp(4) then    -- A: activate current responder
  local idx=findOptIdx()
  if idx then submitIntent(1,"RESPONSE",{optionIdx=idx}) end
 elseif btnp(5) then    -- B: pass priority
  submitIntent(1,"RESPONSE",{pass=true})
 end
end

function handleInput()
 if G.winner then
  local elapsed=G.tick-(G.winTick or 0)
  if elapsed>90 and btnp(4) then sync(3,0,false); music(1,-1,-1,true); SCENE="menu"; TITLE_SEL=1; G={tick=G.tick} end
  return
 end
 if #ANIM>0 then return end
 if G.infoCard then
  if btnp(0) then G.infoScroll=(G.infoScroll or 0)-1
  elseif btnp(1) then G.infoScroll=(G.infoScroll or 0)+1
  elseif btnp(5) or btnp(4) then G.infoCard=nil; G.infoScroll=0 end
  return
 end
 -- Response window: a coroutine is waiting on a kind="response" choice.
 -- Takes priority over normal navigation and other sel_* modes.
 if G.mode=="choose_response" then handleChooseResponse(); return end
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
  elseif btnp(6) then if gy[gv.sel] then G.infoCard=gy[gv.sel] end
  elseif btnp(5) then G.mode="free"; G.gyView=nil end
  return
 end

 -- Extra-Deck viewer
 if G.mode=="ed_view" and G.edView then
  local ev=G.edView
  local ex=G.extra[ev.plr]
  if btnp(0) then ev.sel=math.max(1,ev.sel-1)
  elseif btnp(1) then ev.sel=math.min(#ex,ev.sel+1)
  elseif btnp(6) then if ex[ev.sel] then G.infoCard=ex[ev.sel] end
  elseif btnp(5) then G.mode="free"; G.edView=nil end
  return
 end

 -- Discard picker (e.g. Magic Jammer cost): cursor on player hand
 if G.mode=="sel_discard" and G.discardSel then
  local n=#G.hand[1]
  if n==0 then G.mode="free"; G.discardSel=nil; return end
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
   -- Direct attack iff opp has no monsters; else cursor col → opp data col.
   local tgtCol=hasOppMon and (4-c.col) or nil
   -- The intent handles push-then-raiseNow + chain + battle body. Validation
   -- (e.g. target zone empty → "no target") rejects; player stays in sel_atk.
   submitIntent(1,"DECLARE_ATTACK",{atkCol=p.atkCol,tgtCol=tgtCol})
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
     -- Tributes picked; switch to zone-select. The SUMMON intent (fired
     -- at sel_mon confirm) does the actual GY-move + anim. Initial cursor
     -- prefers a truly-empty zone, else a tribute zone (will be vacated).
     G.mode="sel_mon"
     local initCol=firstEmpty(G.mon[1]) or p.tributes[1] or 1
     G.cur={side=1,row=1,col=initCol}
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
  -- A tribute col counts as empty here — it'll be empty after the SUMMON
  -- intent processes (tribute happens atomically with placement).
  local function zoneFree(col)
   if not G.mon[1][col] then return true end
   if G.pending and G.pending.tributes then
    for _,t in ipairs(G.pending.tributes) do if t==col then return true end end
   end
   return false
  end
  if btnp(2) then  -- left: skip to prev empty zone
   for col=c.col-1,1,-1 do
    if zoneFree(col) then c.col=col; break end
   end
  elseif btnp(3) then  -- right: skip to next empty zone
   for col=c.col+1,3 do
    if zoneFree(col) then c.col=col; break end
   end
  elseif btnp(4) then  -- A: place card
   local col=c.col
   if col>=1 and col<=3 and zoneFree(col) then
    local p=G.pending
    local position=(p.action=="set") and "SET" or "ATK"
    local ok=submitIntent(1,"SUMMON",{
     card=p.card, col=col, position=position,
     tributes=p.tributes, handIdx=p.handIdx,
     extra=(p.action=="summon_extra"),
    })
    if ok then
     G.mode="free"; G.pending=nil
     G.cur={side=1,row=1,col=col}
    end
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
    local t=(p.action=="cast_hand") and "CAST" or "SET_ST"
    -- The intent clears G.mode + G.pending itself (so sub-modes set by
    -- b.activate, e.g. MST's sel_st_target picker, aren't clobbered).
    -- Producer only updates the cursor on success.
    if submitIntent(1,t,{card=p.card,col=col,handIdx=p.handIdx}) then
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
    local p=G.pending
    local ok
    if p.action=="cast_equip" then
     -- Equip from hand: CAST handles place + activate + equippedTo stamp.
     ok=submitIntent(1,"CAST",{
      card=p.card, handIdx=p.handIdx,
      target={plr=c.side,col=ti},
     })
    else  -- activate_equip (face-down equip already in zone)
     ok=submitIntent(1,"ACTIVATE",{
      col=p.stCol, target={plr=c.side,col=ti},
     })
    end
    -- Intent clears G.mode + G.pending. Producer only updates the cursor.
    if ok then
     G.cur={side=1,row=2,col=firstOccupied(G.st[1]) or 1}
    end
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
   local key=G.menu.items[G.menu.sel][2]
   if G.menu.onChoose then
    local cb=G.menu.onChoose
    G.menu={open=false,sel=1,items={}}
    cb(key)
   else
    execAction(key)
   end
  elseif btnp(5) and not G.menu.forced then  -- B: cancel (forced menus can't)
   if G.menu.onChoose then
    local cb=G.menu.onChoose
    G.menu={open=false,sel=1,items={}}
    cb(nil)
   else
    G.menu.open=false
   end
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
  elseif c.row==2 and c.col==0 and c.side==1 then  -- player ED
   if #G.extra[1]>0 then G.mode="ed_view"; G.edView={plr=1,sel=1} end
  elseif c.row==2 and c.col==4 and c.side==2 then  -- opp ED
   if #G.extra[2]>0 then G.mode="ed_view"; G.edView={plr=2,sel=1} end
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
 -- Pause auto-advance while any chain / response is in flight.
 if procBusy() then return end
 -- Auto-advance only in the "no manual action expected" phases. MAIN and
 -- BATTLE require the player to click NEXT PHASE / END TURN (or take an
 -- action). The ADVANCE_PHASE intent handles tickSwords + active flip +
 -- new-turn setup inside PH_END.onExit — autoPhase just submits.
 if G.ph~=PH_DRAW and G.ph~=PH_STBY and G.ph~=PH_END then return end
 G.autoTimer=G.autoTimer-1
 if G.autoTimer<=0 then
  G.autoTimer=50
  submitIntent(1,"ADVANCE_PHASE",{})
 end
end

