-- [ygo_menu] YGO80 module -- loaded via require() from ygo80.lua

function startMonsterPlacement(handIdx,action)
 local card=G.hand[1][handIdx]
 if not card then return end
 local tribNeeded=tribsNeeded(getMonLvl(card))
 G.pending={handIdx=handIdx,card=card,action=action,tribNeeded=tribNeeded,tributes={}}
 if tribNeeded>0 then
  G.mode="sel_tribute"
  G.cur={side=1,row=1,col=firstOccupied(G.mon[1]) or 1}
 else
  G.mode="sel_mon"
  G.cur={side=1,row=1,col=firstEmpty(G.mon[1]) or 1}
 end
end

-- Opens the sequential Oracle effect picker. `op` holds pick state.
function openOraclePick(op)
 local items={}
 if not op.used[1] then items[#items+1]={"+"..op.lvlSum*100 .." ATK","oracle_e1"} end
 if not op.used[2] then items[#items+1]={"DESTROY SET MONS","oracle_e2"} end
 if not op.used[3] then items[#items+1]={"OPP -2000 ATK/DEF","oracle_e3"} end
 items[#items+1]={"DONE","oracle_done"}
 G.oraclePick=op
 G.menu={open=true,sel=1,items=items}
end

-- Build context-sensitive menu items for the current cursor position.
-- Returns a list of {label, actionKey} or nil if no menu should open.
function buildMenu()
 local c=G.cur
 local isMain=(G.ph==PH_MAIN)
 local items={}

 if c.side==1 and G.active==1 then  -- player's own stuff, player's turn

  if c.row==3 then  -- hand card
   local card=G.hand[1][c.col+1]
   if card and isMain then
    if card.cat=="spell" then
     local emptyZone=firstEmpty(G.st[1])~=nil
     local b=behaviorOf(card)
     local canActivate
     if card.subtype=="equip" then
      canActivate = emptyZone and (hasMonsters(1) or hasMonsters(2))
     elseif b and b.canActivate then
      canActivate = emptyZone and b.canActivate(card)
     else
      canActivate = true
     end
     if canActivate then table.insert(items,{"ACTIVATE","cast_hand"}) end
     -- Field spells go straight to the FS zone; no face-down Set option.
     if emptyZone and card.subtype~="field" then table.insert(items,{"SET","set_st"}) end
    elseif card.cat=="trap" then
     if firstEmpty(G.st[1]) then table.insert(items,{"SET","set_st"}) end
    elseif not G.normalSummoned then
     local emptyZone=false
     for i=1,3 do
      if not G.mon[1][i] then emptyZone=true end
     end
     local tribNeeded=tribsNeeded(getMonLvl(card))
     -- fieldTributeValue counts Double Coston as 2 for DARK summons.
     local canSummon=(tribNeeded==0 and emptyZone)
                  or (tribNeeded>=1 and fieldTributeValue(card,1)>=tribNeeded)
     if canSummon then table.insert(items,{"SUMMON","summon"}) end
     if canSummon then table.insert(items,{"SET","set"}) end
    end
    -- Legion extra tribute summon (separate from normal summon slot)
    if isMain and G.extraSpellcasterSummon and card.cat=="monster" and card.type=="spellcaster" then
     local monCount,emptyZone=0,false
     for i=1,3 do
      if G.mon[1][i] then monCount=monCount+1 else emptyZone=true end
     end
     local tribNeeded=tribsNeeded(getMonLvl(card))
     if tribNeeded>=1 and monCount>=tribNeeded then
      table.insert(items,{"EXTRA SUMMON","summon_extra"})
     end
    end
   end

  elseif c.row==1 and c.col>=1 and c.col<=3 then  -- monster zone
   local card=G.mon[1][c.col]
   if card then
    if isMain and not card.summoned and not card.posChanged then
     table.insert(items,{"CHG POS","chgpos"})
    end
    if isMain and not card.facedown then
     local b=behaviorOf(card)
     if b and b.ignition and (not b.ignition.canActivate or b.ignition.canActivate(card,1)) then
      table.insert(items,{b.ignition.label,"ignition"})
     end
    end
    if G.ph==PH_BATTLE and card.pos==1 and not card.facedown and not card.attacked
       and not attackBlocked(card,1) then
     table.insert(items,{"ATTACK","attack"})
    end
   end

  elseif c.row==2 and c.col>=1 and c.col<=3 then  -- spell/trap zone
   local card=G.st[1][c.col]
   -- Only face-down cards may be activated; a face-up card here is an
   -- already-active continuous/equip card and must not be re-activated.
   if card and card.facedown and not card.setThisTurn then
    local b=behaviorOf(card)
    if card.cat=="spell" and isMain then
     local canActivate
     if card.subtype=="equip" then
      canActivate = hasMonsters(1) or hasMonsters(2)
     elseif b and b.canActivate then
      canActivate = b.canActivate(card)
     else
      canActivate = true
     end
     if canActivate then table.insert(items,{"ACTIVATE","activate"}) end
    elseif card.cat=="trap" and not (b and b.responseOnly) and not staticActive("blocksTraps") then
     if not (b and b.canActivate) or b.canActivate(card) then
      table.insert(items,{"ACTIVATE","activate"})
     end
    end
   end
  end

 end

 local hovCard=getHoveredCard()
 if hovCard and hovCard.desc and not (G.cur.side==2 and hovCard.facedown) then
  table.insert(items,{"INFO","info"})
 end
 if #items==0 then return nil end  -- nothing to do, don't open
 table.insert(items,{"CANCEL","cancel"})
 return items
end

-- Execute a menu action.
function execAction(key)
 local c=G.cur
 G.menu.open=false  -- close menu first; specific actions may reopen or change state

 if key=="cancel" then
  -- nothing

 elseif key=="info" then
  G.infoCard=getHoveredCard()

 elseif key=="chgpos" then
  submitIntent(1,"CHANGE_POS",{col=c.col})

 elseif key=="summon" then
  startMonsterPlacement(G.cur.col+1,"summon")
 elseif key=="summon_extra" then
  startMonsterPlacement(G.cur.col+1,"summon_extra")
 elseif key=="set" then
  startMonsterPlacement(G.cur.col+1,"set")
 elseif key=="ignition" then
  local card=G.mon[1][c.col]
  local b=card and behaviorOf(card)
  if b and b.ignition and b.ignition.activate then
   b.ignition.activate(card,1,c.col)
  end
 elseif key=="attack" then
  local atkCol=c.col
  local attacker=G.mon[1][atkCol]
  if attacker then
   G.pending={attacker=attacker,atkCol=atkCol,action="attack"}
   G.mode="sel_atk"
   G.cur={side=2,row=1,col=2}
   for i=1,3 do
    if G.mon[2][i] then G.cur.col=4-i; break end
   end
  end
 elseif key=="set_st" then
  local handIdx=G.cur.col+1
  local card=G.hand[1][handIdx]
  if card then
   G.pending={handIdx=handIdx,card=card,action="set_st"}
   G.mode="sel_st"
   G.cur={side=1,row=2,col=firstEmpty(G.st[1]) or 1}
  end
 elseif key=="cast_hand" then
  local handIdx=G.cur.col+1
  local card=G.hand[1][handIdx]
  if card then
   if card.subtype=="equip" then
    -- Equip: pick monster target first (sel_equip), then submit CAST at confirm.
    G.pending={handIdx=handIdx,card=card,action="cast_equip"}
    G.mode="sel_equip"
    local startCol=firstOccupied(G.mon[1]) or firstOccupied(G.mon[2]) or 1
    G.cur={side=1,row=1,col=startCol}
   elseif card.subtype=="field" then
    -- Field: no zone pick needed; submit CAST directly. Intent owns G.mode.
    if submitIntent(1,"CAST",{card=card,handIdx=handIdx}) then
     G.cur={side=1,row=1,col=0}
    end
   else
    -- Normal / Continuous / Quick-Play: open S/T zone picker; CAST submitted at confirm.
    G.pending={handIdx=handIdx,card=card,action="cast_hand"}
    G.mode="sel_st"
    G.cur={side=1,row=2,col=firstEmpty(G.st[1]) or 1}
   end
  end
 elseif key=="activate" then
  local col=c.col
  local card=G.st[1][col]
  if card then
   if card.subtype=="equip" then
    -- Equip activation: pick monster target first (sel_equip), then submit ACTIVATE.
    G.pending={stCol=col,card=card,action="activate_equip"}
    G.mode="sel_equip"
    local startCol=firstOccupied(G.mon[1]) or firstOccupied(G.mon[2]) or 1
    G.cur={side=1,row=1,col=startCol}
   else
    submitIntent(1,"ACTIVATE",{col=col})
   end
  end

 elseif key=="nextphase" then
  submitIntent(1,"ADVANCE_PHASE",{})

 elseif key=="endturn" then
  -- Jump straight to PH_END (may skip PH_BATTLE entirely). autoTimer=1
  -- makes autoPhase fire the END→DRAW transition next frame — no end-phase
  -- response window when the player asks to skip ahead.
  if submitIntent(1,"ADVANCE_PHASE",{to=PH_END}) then
   G.autoTimer=1
  end

 elseif key=="oracle_e1" or key=="oracle_e2" or key=="oracle_e3" or key=="oracle_done" then
  local op=G.oraclePick; if not op then return end
  if key~="oracle_done" then
   local eff=({oracle_e1=1,oracle_e2=2,oracle_e3=3})[key]
   op.used[eff]=true
   if eff==1 then
    op.card.atkMod=(op.card.atkMod or 0)+op.lvlSum*100
   elseif eff==2 then
    local opp=3-op.plr
    for i=1,3 do
     if G.mon[opp][i] and G.mon[opp][i].facedown then
      revealAndDestroyMon(opp,i,"effect")
     end
    end
    checkEquips()
   elseif eff==3 then
    local opp=3-op.plr
    for i=1,3 do
     local m=G.mon[opp][i]
     if m then
      m.atkMod=(m.atkMod or 0)-2000
      m.defMod=(m.defMod or 0)-2000
     end
    end
   end
   op.remaining=op.remaining-1
  end
  if key=="oracle_done" or op.remaining<=0 then
   G.oraclePick=nil
  else
   openOraclePick(op)
  end

 end
end

-- Battle resolution body — symmetric for both players. Called by
-- INTENTS.DECLARE_ATTACK's continuation AFTER the EV_ATTACK chain resolves.
-- attacker / target are card refs that have been confirmed still alive.
-- Handles face-down flip + sword anim + ATK/DEF damage math + GY moves.
function runAttackBattle(plr,attacker,atkCol,target,tgtCol)
 local opp=3-plr
 local attScrCol=(plr==1) and atkCol or (4-atkCol)
 local tgtScrCol=(plr==1) and (4-tgtCol) or tgtCol
 local attY=(plr==1) and PY_M or OY_M
 local tgtY=(plr==1) and OY_M or PY_M
 local tgtZoneColor=(plr==1) and COZ or CZ
 local ax=COL[attScrCol]+ZW_MAIN//2-8
 local ay=attY+ZH//2-8
 local tx=COL[tgtScrCol]+ZW_MAIN//2-8
 local ty=tgtY+ZH//2-8
 local wasFlipped=target.facedown
 local function doSlash()
  animSwordSlash(ax,ay,tx,ty,function()
   local atkV=getMonAtk(attacker); local tgtV=getMonAtk(target); local tgtDef=getMonDef(target)
   local atkB=behaviorOf(attacker)
   if target.pos==2 then
    if atkV>tgtDef then
     sendMonsterToGY(opp,tgtCol,"battle")
     if atkB and atkB.piercing then applyDamage(opp,atkV-tgtDef) end
    elseif atkV<tgtDef then
     if not battleDamageImmune(attacker,plr) then changeLp(plr,-(tgtDef-atkV)) end
    end
   else
    if atkV>tgtV then
     sendMonsterToGY(opp,tgtCol,"battle")
     applyDamage(opp,atkV-tgtV)
    elseif atkV<tgtV then
     if not battleIndestructible(attacker,plr) then sendMonsterToGY(plr,atkCol,"battle") end
     if not battleDamageImmune(attacker,plr) then changeLp(plr,-(tgtV-atkV)) end
    else
     sendMonsterToGY(opp,tgtCol,"battle")
     if not battleIndestructible(attacker,plr) then sendMonsterToGY(plr,atkCol,"battle") end
    end
   end
   G.battleAnim=nil
   checkWin()
   checkEquips()
   if atkB and atkB.onAfterAttack and G.mon[plr][atkCol]==attacker then
    atkB.onAfterAttack(attacker,plr,atkCol,target,tgtCol,opp)
   end
   if wasFlipped then flipEvent(target,opp,tgtCol) end
  end)
 end
 if wasFlipped then
  target.facedown=false
  local zx=COL[tgtScrCol]
  addAnim(24,function(t,f)
   if (t//4)%2==0 then rect(zx,tgtY,ZW_MAIN,ZH,tgtZoneColor); rectb(zx,tgtY,ZW_MAIN,ZH,CT) end
  end,doSlash)
 else
  doSlash()
 end
end

-- Direct attack body — attacker slashes the opp's S/T-row center, deals
-- applyDamage to opp (which itself raises EV_BEFORE_DAMAGE for Kuriboh).
function runDirectAttack(plr,attacker,atkCol)
 local opp=3-plr
 local attScrCol=(plr==1) and atkCol or (4-atkCol)
 local attY=(plr==1) and PY_M or OY_M
 local tgtY=(plr==1) and OY_S or PY_S
 local ax=COL[attScrCol]+ZW_MAIN//2-8
 local ay=attY+ZH//2-8
 local tx=FA_X+FA_W//2-8
 local ty=tgtY+ZH//2-8
 local dmg=getMonAtk(attacker)
 animSwordSlash(ax,ay,tx,ty,function()
  G.battleAnim=nil
  applyDamage(opp,dmg)
  local b=behaviorOf(attacker)
  if b and b.onAfterAttack and G.mon[plr][atkCol]==attacker then
   b.onAfterAttack(attacker,plr,atkCol)
  end
 end)
end

