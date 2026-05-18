-- [ygo_menu] YGO80 module -- loaded via require() from ygo80.lua

function startMonsterPlacement(handIdx,action)
 local card=G.hand[1][handIdx]
 if not card then return end
 local tribNeeded=tribsNeeded(card.lvl or 1)
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
     local tribNeeded=tribsNeeded(card.lvl or 1)
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
     local tribNeeded=tribsNeeded(card.lvl or 1)
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
    if isMain and not card.facedown and card.effect=="legion" and not G.legionSummonUsed and not G.extraSpellcasterSummon then
     table.insert(items,{"EXTRA SUMMON","legion_extra"})
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
  local card=G.mon[1][c.col]
  if card then
   if card.facedown then
    card.facedown=false; card.pos=1
    fireMonHook(card,"onFlip",1)
   else
    card.pos=(card.pos==1) and 2 or 1
   end
   card.posChanged=true
   checkEquips()
  end

 elseif key=="summon" then
  startMonsterPlacement(G.cur.col+1,"summon")
 elseif key=="summon_extra" then
  startMonsterPlacement(G.cur.col+1,"summon_extra")
 elseif key=="set" then
  startMonsterPlacement(G.cur.col+1,"set")
 elseif key=="legion_extra" then
  G.extraSpellcasterSummon=true; G.legionSummonUsed=true
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
    G.pending={handIdx=handIdx,card=card,action="cast_equip"}
    G.mode="sel_equip"
    local startCol=firstOccupied(G.mon[1]) or firstOccupied(G.mon[2]) or 1
    G.cur={side=1,row=1,col=startCol}
   elseif card.subtype=="field" then
    if fieldSpellBlocked(1) then return end
    -- Field spell: goes straight to the FS zone, replacing any field spell
    -- already there. No zone pick needed (one field zone per player).
    local fcard=copyCard(card)
    fcard.facedown=false
    if G.fs[1] then sendFieldSpellToGY(1,"rule") end
    G.fs[1]=fcard
    table.remove(G.hand[1],handIdx)
    G.mode="free"
    G.cur={side=1,row=1,col=0}
    animFieldSpellActivation(fcard,1)
   else
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
    G.pending={stCol=col,card=card,action="activate_equip"}
    G.mode="sel_equip"
    local startCol=firstOccupied(G.mon[1]) or firstOccupied(G.mon[2]) or 1
    G.cur={side=1,row=1,col=startCol}
   else
    local b=behaviorOf(card)
    if b and b.activate then
     b.activate{col=col,card=card,zone="st",plr=1}
    elseif card.cat=="trap" then
     activateTrapAnim(col,card,function() applyResolve(card,1) end)
    else
     card.facedown=false
     animSpellActivation(col,PY_S,card,1)
    end
   end
  end

 elseif key=="nextphase" then
  changePhase(G.ph+1)

 elseif key=="endturn" then
  changePhase(PH_END)
  G.autoTimer=1

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
    flushTriggers()
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

 elseif key=="ss_atk" or key=="ss_def" then
  local ps=G.pendingSS; G.pendingSS=nil
  if ps then
   local col=firstEmpty(G.mon[ps.plr])
   if col then
    local m=ps.card
    m.pos=(key=="ss_atk") and 1 or 2
    m.facedown=false; m.attacked=false; m.summoned=true; m.posChanged=false
    G.mon[ps.plr][col]=m
    fireSummonHook(m,ps.plr)
   end
  end

 elseif key=="reborn_atk" or key=="reborn_def" then
  -- Monster Reborn: position chosen, now activate. The chain link's resolveFn
  -- special-summons the captured GY monster at the picked position.
  local rs=G.rebornSel; G.rebornSel=nil
  if rs then
   local pos=(key=="reborn_atk") and 1 or 2
   pushActivationLink({card=rs.card,col=rs.col,zone=rs.zone,plr=1},function()
    local emptyCol=firstEmpty(G.mon[1])
    local m=emptyCol and G.gy[rs.gyPlr][rs.gyIdx]
    if not (emptyCol and m and m.cat=="monster") then return end
    table.remove(G.gy[rs.gyPlr],rs.gyIdx)
    m.pos=pos; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
    m.linkedTrap=nil
    G.mon[1][emptyCol]=m
    fireSummonHook(m,1)
   end)
  end

 elseif key=="assail_yes" then
  -- Gravekeeper's Assailant: pick 1 opponent monster, change its battle
  -- position, then continue the declared attack.
  G.mode="sel_destroy"
  G.destroySel={side=2,title="ASSAILANT: CHANGE POS",onPick=function(side,ti)
   local m=G.mon[side][ti]
   if m then
    if m.facedown then
     m.facedown=false; m.pos=1; fireMonHook(m,"onFlip",2)
    else
     m.pos=(m.pos==1) and 2 or 1
    end
    m.posChanged=true
    checkEquips()
   end
   resumeAttack()
  end}
  G.cur={side=2,row=1,col=4-(firstOccupied(G.mon[2]) or 1)}

 elseif key=="assail_no" then
  resumeAttack()
 end
end

function resolveAttack(attacker,atkCol,target,tgtIdx)
 attacker.attacked=true
 G.mode="free"; G.pending=nil
 G.cur={side=1,row=1,col=atkCol}

 local ax=COL[atkCol]+ZW_MAIN//2-8
 local ay=PY_M+ZH//2-8

 if not target then
  local tx=FA_X+FA_W//2-8; local ty=OY_S+ZH//2-8
  animSwordSlash(ax,ay,tx,ty,function() applyDamage(2,getMonAtk(attacker)) end)
  return
 end

 local tx=COL[4-tgtIdx]+ZW_MAIN//2-8
 local ty=OY_M+ZH//2-8
 local wasFlipped=target.facedown

 local function doSlash()
  animSwordSlash(ax,ay,tx,ty,function()
   local atkV=getMonAtk(attacker); local tgtV=getMonAtk(target); local tgtDef=getMonDef(target)
   if target.pos==2 then
    if atkV>tgtDef then
     sendMonsterToGY(2,tgtIdx,"battle")
    elseif atkV<tgtDef then
     changeLp(1,-(tgtDef-atkV))
    end
   else
    if atkV>tgtV then
     sendMonsterToGY(2,tgtIdx,"battle")
     applyDamage(2,atkV-tgtV)
    elseif atkV<tgtV then
     sendMonsterToGY(1,atkCol,"battle")
     changeLp(1,-(tgtV-atkV))
    else
     sendMonsterToGY(2,tgtIdx,"battle")
     sendMonsterToGY(1,atkCol,"battle")
    end
   end
   checkWin()
   flushTriggers()
   if wasFlipped then fireMonHook(target,"onFlip",2) end
  end)
 end

 if wasFlipped then
  target.facedown=false
  local zx=COL[4-tgtIdx]
  addAnim(24,function(t,f)
   if (t//4)%2==0 then rect(zx,OY_M,ZW_MAIN,ZH,COZ); rectb(zx,OY_M,ZW_MAIN,ZH,CT) end
  end,doSlash)
 else
  doSlash()
 end
end

-- Resolve a player-declared attack: run the AI's trap window, then carry out
-- the attack on the target stored in G.pending (set when the attack was
-- confirmed). Used both for normal attacks and after Assailant's effect.
function confirmPlayerAttack()
 local p=G.pending
 if not p then return end
 local tgtIdx=p.tgtIdx
 local function proceedAttack()
  -- Re-check attacker (chain may have destroyed it, e.g. Mirror Force)
  if not p.attacker or G.mon[1][p.atkCol]~=p.attacker then
   G.mode="free"; G.pending=nil; return
  end
  if not hasMonsters(2) then
   resolveAttack(p.attacker,p.atkCol,nil,nil)
  else
   local target=G.mon[2][tgtIdx]
   if target then
    resolveAttack(p.attacker,p.atkCol,target,tgtIdx)
   end
   -- If target is nil (cursor on empty zone), do nothing; player stays in
   -- sel_atk and can re-navigate. Matches pre-chain behavior.
  end
 end
 if not checkAITraps("attack",{att=p.attacker,atkCol=p.atkCol},proceedAttack) then
  proceedAttack()
 end
end

