-- [ygo_intent] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- INTENT-BASED STATE MACHINE
-- ============================================================
-- Layering (bottom up):
--   Primitives : sendMonsterToGY, changeLp, procActivate, ... (state + events)
--   Intents    : submitIntent + INTENTS[T] handlers          (validation + costs)
--   Producers  : sel_* confirm branches, aiTick              (decision + submit)
--
-- Phase machine is data: PHASE_TABLE[ph] = {next, onEnter, onExit, legal}.
-- ADVANCE_PHASE runs PHASE_TABLE[G.ph].onExit, sets G.ph=next, runs onEnter.
--
-- Handler contract: returns ok, err. ok=true means the intent committed
-- (state mutated + events raised). ok=false means rejected; err is a short
-- string for trace(). Handlers MUST NOT yield — chain reacts run later via
-- procTick.

-- ============================================================
-- PHASE TABLE
-- ============================================================
-- `next` is the default successor used when ADVANCE_PHASE has no `to` arg.
-- `onExit(plr)` runs in the OLD phase context; `onEnter(plr)` in the NEW.
-- EV_PHASE raises BETWEEN them.
-- `legal` = intent types accepted in this phase (RESPONSE bypasses).
PHASE_TABLE={
 [PH_DRAW]={
  next=PH_STBY,
  onEnter=function(plr) end,
  onExit =function(plr) end,
  legal  ={ACTIVATE=true, ADVANCE_PHASE=true},
 },
 [PH_STBY]={
  next=PH_MAIN,
  onEnter=function(plr) end,
  onExit =function(plr) end,
  legal  ={ACTIVATE=true, ADVANCE_PHASE=true},
 },
 [PH_MAIN]={
  next=PH_BATTLE,
  onEnter=function(plr) end,
  onExit =function(plr) end,
  legal  ={SUMMON=true, CAST=true, SET_ST=true, ACTIVATE=true,
           CHANGE_POS=true, ADVANCE_PHASE=true},
 },
 [PH_BATTLE]={
  next=PH_END,
  onEnter=function(plr) G.aiBattleIdx=1 end,
  onExit =function(plr) end,
  legal  ={DECLARE_ATTACK=true, ACTIVATE=true, CHANGE_POS=true,
           ADVANCE_PHASE=true},
 },
 [PH_END]={
  next=PH_DRAW,
  onEnter=function(plr) end,
  onExit =function(plr)
   -- Order matters: tickSwords reads G.active to find opp's swords counter,
   -- so it must run BEFORE the active flip.
   tickSwords()
   clearTurnMods()
   G.turn=G.turn+1
   G.active=3-plr
   G.normalSummoned=false
   drawCard(G.active)
   resetTurnFlags()
   if G.active==1 then G.autoTimer=50 else G.aiTimer=AI_DELAY end
  end,
  legal  ={ACTIVATE=true, ADVANCE_PHASE=true},
 },
}

-- Phase advance core. Shared by INTENTS.ADVANCE_PHASE and any effect that
-- needs to force a phase change (Negate Attack -> PH_END). Bypasses the
-- intent's procBusy gate so it can be called from inside a react.
function doAdvancePhase(target)
 local cur=PHASE_TABLE[G.ph]
 if not cur then return end
 target=target or cur.next
 if target==PH_BATTLE and G.turn==1 and G.active==G.firstPlayer then
  target=PH_END
 end
 local nxt=PHASE_TABLE[target]
 if not nxt then return end
 cur.onExit(G.active)
 local prev=G.ph
 G.ph=target
 raise(EV_PHASE,{phase=target,prevPhase=prev,toPhase=target,actor=G.active})
 nxt.onEnter(G.active)
end

-- ============================================================
-- INTENT HANDLERS
-- ============================================================
INTENTS={}

-- SUMMON: Normal / Tribute / Set monster placement (+ Legion extra summon).
-- Args: {card, col, position="ATK"|"SET", tributes={col,...}, handIdx, extra}.
-- A col that's also in `tributes` is allowed as the destination — the intent
-- vacates the tribute zones atomically with placement.
INTENTS.SUMMON=function(plr,a)
 if plr~=G.active then return false,"not active player" end
 local card=a.card
 if not card or card.cat~="monster" then return false,"not a monster" end
 if a.extra then
  if not G.extraSpellcasterSummon then return false,"no extra summon avail" end
 else
  if G.normalSummoned then return false,"already summoned" end
 end
 if not a.col or a.col<1 or a.col>3 then return false,"bad col" end
 local tribCols=a.tributes or {}
 if G.mon[plr][a.col] then
  local isTrib=false
  for _,tcol in ipairs(tribCols) do
   if tcol==a.col then isTrib=true; break end
  end
  if not isTrib then return false,"zone occupied" end
 end
 local trib=tribsNeeded(getMonLvl(card))
 if trib>0 then
  local total=0
  for _,tcol in ipairs(tribCols) do
   local m=G.mon[plr][tcol]
   if not m then return false,"tribute zone empty" end
   total=total+tributeValueOf(card,m)
  end
  if total<trib then return false,"insufficient tribute" end
 end
 local position=a.position or "ATK"
 if position~="ATK" and position~="SET" then return false,"bad position" end
 if a.extra and position~="ATK" then return false,"extra summon must be ATK" end

 local commit=function()
  local tributedMonsters={}
  for _,tcol in ipairs(tribCols) do
   local tm=G.mon[plr][tcol]
   if tm then table.insert(tributedMonsters,{card=tm,plr=plr,col=tcol}) end
  end
  for _,tcol in ipairs(tribCols) do
   sendMonsterToGY(plr,tcol,"tribute")
  end
  if a.handIdx then table.remove(G.hand[plr],a.handIdx) end
  local placed=card
  if position=="SET" then
   placed=copyCard(card); placed.pos=2; placed.facedown=true
  end
  G.mon[plr][a.col]=placed
  placed.summoned=true
  if a.extra then
   G.extraSpellcasterSummon=false
  else
   G.normalSummoned=true
  end
  summonEvent(placed,plr,a.col,#tribCols>0 and "tribute" or "normal",tributedMonsters)
  -- EV_TRIBUTED fires AFTER the new monster lands so "sent from field to GY"
  -- triggers (Legion) can react with the new field state in place.
  for _,t in ipairs(tributedMonsters) do
   raise(EV_TRIBUTED,{card=t.card,plr=t.plr,actor=plr})
  end
 end

 -- Tribute anim plays inside the handler; #ANIM>0 blocks input + AI until
 -- the commit callback fires.
 if #tribCols>0 then
  local zones={}
  local rowY=(plr==1) and PY_M or OY_M
  for _,tcol in ipairs(tribCols) do
   local x=(plr==1) and COL[tcol] or COL[4-tcol]
   table.insert(zones,{x=x,y=rowY})
  end
  animTribute(zones,commit)
 else
  commit()
 end
 return true
end

-- CAST: Play a Spell from hand. Args: {card, col?, target?, handIdx}.
-- Covers Normal / Continuous / Quick-Play / Field / Equip via card.subtype.
-- `target={plr,col}` only for equips. `col` may be omitted for AI (handler
-- picks firstEmpty or falls through to hand→GY direct).
-- Player path dispatches to b.activate; AI path goes straight to procActivate
-- (b.resolve handles AI auto-targeting).
INTENTS.CAST=function(plr,a)
 if plr~=G.active then return false,"not active player" end
 local card=a.card
 if not card or card.cat~="spell" then return false,"not a spell" end
 local subtype=card.subtype
 if subtype=="field" then
  if staticActive("blocksFieldSpells",3-plr) then return false,"field spell blocked" end
 elseif subtype=="equip" then
  if not a.target then return false,"no equip target" end
  local t=G.mon[a.target.plr][a.target.col]
  if not t or t.facedown then return false,"bad equip target" end
  if not a.col then a.col=firstEmpty(G.st[plr]) end
  if not a.col or G.st[plr][a.col] then return false,"st zone occupied" end
 else
  if a.col and (a.col<1 or a.col>3 or G.st[plr][a.col]) then
   return false,"st zone occupied"
  end
 end
 -- UI cleanup BEFORE b.activate (which may set its own sub-mode synchronously,
 -- e.g. MST → sel_st_target). Resetting after the dispatch would clobber it.
 if plr==1 then G.mode="free"; G.pending=nil end
 if subtype=="field" then
  local placed=copyCard(card)
  -- Only one field spell on the whole field: activating a new one sends ANY
  -- existing field spell (yours OR the opponent's) to its owner's GY.
  if G.fs[plr] then sendFieldSpellToGY(plr,"rule") end
  if G.fs[3-plr] then sendFieldSpellToGY(3-plr,"rule") end
  G.fs[plr]=placed
  table.remove(G.hand[plr],a.handIdx)
  procActivate(placed,plr,"fs",nil)
 elseif subtype=="equip" then
  local placed=copyCard(card)
  placed.facedown=false
  placed.equippedTo=a.target
  G.st[plr][a.col]=placed
  table.remove(G.hand[plr],a.handIdx)
  procActivate(placed,plr,"st",a.col)
 else
  local stCol=a.col or firstEmpty(G.st[plr])
  if stCol then
   local placed=copyCard(card)
   placed.facedown=false
   G.st[plr][stCol]=placed
   table.remove(G.hand[plr],a.handIdx)
   local b=behaviorOf(placed)
   if plr==1 and b and b.activate then
    b.activate{col=stCol,card=placed,zone="st",plr=plr}
   else
    procActivate(placed,plr,"st",stCol)
   end
  else
   -- No S/T zone free: spell resolves directly from hand to GY (AI fallback).
   table.remove(G.hand[plr],a.handIdx)
   addToGY(plr,card,"effect")
   procPushFrame(function()
    playActivateAnim(card,plr,"hand",nil)
    local link={source=card,controller=plr,speed=chainSpeed(card),sourceLoc=nil}
    link.react=function() applyResolve(card,plr,nil) end
    pushLink(link)
    runResponseWindow(EV_ACTIVATE,{card=card,controller=plr,actor=plr,link=link})
   end)
  end
 end
 return true
end

-- SET_ST: Place a Spell or Trap face-down in an S/T zone.
-- Args: {card, col, handIdx}. No chain, no event — Set is silent.
INTENTS.SET_ST=function(plr,a)
 if plr~=G.active then return false,"not active player" end
 local card=a.card
 if not card or (card.cat~="spell" and card.cat~="trap") then return false,"not a spell/trap" end
 if card.subtype=="field" then return false,"field spell cannot be set" end
 if not a.col or a.col<1 or a.col>3 or G.st[plr][a.col] then return false,"st zone occupied" end
 if plr==1 then G.mode="free"; G.pending=nil end
 local placed=copyCard(card)
 placed.facedown=true
 placed.setThisTurn=true
 G.st[plr][a.col]=placed
 table.remove(G.hand[plr],a.handIdx)
 return true
end

-- ACTIVATE: Flip a face-down S/T card face-up + push it onto the chain.
-- (CAST is hand→field; ACTIVATE is already-on-field.)
-- Args: {col, target?}. `target={plr,col}` for Equip activation.
-- Dispatches to b.activate (player, custom flows) or procActivate.
INTENTS.ACTIVATE=function(plr,a)
 if not a.col or a.col<1 or a.col>3 then return false,"bad col" end
 local card=G.st[plr][a.col]
 if not card then return false,"no card in zone" end
 if not card.facedown then return false,"card already face-up" end
 local b=behaviorOf(card)
 if b and b.canActivate and not b.canActivate(card) then
  return false,"canActivate=false"
 end
 if plr==1 then G.mode="free"; G.pending=nil end
 if card.subtype=="equip" then
  if not a.target then return false,"no equip target" end
  local t=G.mon[a.target.plr][a.target.col]
  if not t or t.facedown then return false,"bad equip target" end
  card.equippedTo=a.target
  procActivate(card,plr,"st",a.col)
 else
  if plr==1 and b and b.activate then
   b.activate{col=a.col,card=card,zone="st",plr=plr}
  else
   procActivate(card,plr,"st",a.col)
  end
 end
 return true
end

-- RESPONSE: Player's reply to an open chain response window.
-- Args: {optionIdx} to activate a responder, or {pass=true} to pass priority.
-- Window gating is enforced by submitIntent (requires currentChoice).
INTENTS.RESPONSE=function(plr,a)
 if a.pass then
  G.mode="free"
  procAnswerChoice(false)
  return true
 end
 local req=G.proc and G.proc.currentChoice
 if not (a.optionIdx and req and req.options and req.options[a.optionIdx]) then
  return false,"bad optionIdx"
 end
 G.mode="free"
 procAnswerChoice({optionIdx=a.optionIdx})
 return true
end

-- DECLARE_ATTACK: a monster attacks a target zone, or direct if opp has none.
-- Args: {atkCol, tgtCol?}. tgtCol=nil means direct attack.
-- Push-then-raiseNow: the battle body goes on the proc stack FIRST, then
-- raiseNow(EV_ATTACK) — so attack-response listeners (Mirror Force,
-- gkassailant) resolve before the body runs. The continuation re-checks
-- attacker/target survival; Mirror Force destroying the attacker cancels
-- the attack naturally.
INTENTS.DECLARE_ATTACK=function(plr,a)
 if plr~=G.active then return false,"not active player" end
 local atkCol=a.atkCol
 if not atkCol or atkCol<1 or atkCol>3 then return false,"bad atkCol" end
 local attacker=G.mon[plr][atkCol]
 if not attacker then return false,"no attacker" end
 if attacker.facedown or attacker.pos~=1 then return false,"attacker not face-up ATK" end
 if attacker.attacked then return false,"already attacked" end
 if attackBlocked(attacker,plr) then return false,"attack blocked" end
 local tgtCol=a.tgtCol
 if tgtCol then
  if tgtCol<1 or tgtCol>3 then return false,"bad tgtCol" end
  if not G.mon[3-plr][tgtCol] then return false,"no target" end
 else
  if hasMonsters(3-plr) then return false,"target required" end
 end

 attacker.attacked=true
 -- Leave sel_atk before the chain runs so menu input (e.g. gkassailant's
 -- forced EFFECT/NORMAL menu) takes precedence.
 if plr==1 then
  G.mode="free"; G.pending=nil
  G.cur={side=1,row=1,col=atkCol}
 end

 procPushFrame(function()
  -- Bail if the chain advanced the phase (Negate Attack), the attacker
  -- died (Mirror Force), or the attacker is no longer in face-up ATK
  -- (Kunai with Chain change-pos branch).
  if G.ph~=PH_BATTLE or G.mon[plr][atkCol]~=attacker
     or attacker.pos~=1 or attacker.facedown then
   G.battleAnim=nil
   return
  end
  -- Replay: re-derive target from current field state (chain may have
  -- added/cleared monsters).
  if hasMonsters(3-plr) then
   if not tgtCol or not G.mon[3-plr][tgtCol] then
    tgtCol=firstOccupied(G.mon[3-plr])
   end
  else
   tgtCol=nil
  end
  if tgtCol then
   local target=G.mon[3-plr][tgtCol]
   if not target then
    G.battleAnim=nil
    return
   end
   runAttackBattle(plr,attacker,atkCol,target,tgtCol)
  else
   runDirectAttack(plr,attacker,atkCol)
  end
 end)
 -- Must be raiseNow not raise: frames is non-empty after the push above;
 -- raise() would queue to pending and the body would run BEFORE the chain.
 raiseNow(EV_ATTACK,{attacker=attacker,plr=plr,actor=plr})
 return true
end

-- CHANGE_POS: Toggle a monster's battle position.
-- Face-down flips up to ATK (raises EV_FLIP). Face-up toggles ATK ↔ DEF.
-- Rules: once per turn, not on summon turn. Flags reset in resetTurnFlags.
INTENTS.CHANGE_POS=function(plr,a)
 if plr~=G.active then return false,"not active player" end
 if not a.col or a.col<1 or a.col>3 then return false,"bad col" end
 local card=G.mon[plr][a.col]
 if not card then return false,"no monster" end
 if card.summoned then return false,"summoned this turn" end
 if card.posChanged then return false,"already changed pos this turn" end
 if card.facedown then
  card.facedown=false; card.pos=1
  flipEvent(card,plr,a.col)
 else
  card.pos=(card.pos==1) and 2 or 1
 end
 card.posChanged=true
 checkEquips()
 return true
end

-- ADVANCE_PHASE: move from G.ph to its successor.
-- Args: {to?}. If `to` is set, jumps directly (END TURN uses to=PH_END).
-- Pipeline: cur.onExit(active) → set G.ph → raise EV_PHASE → next.onEnter.
-- First-turn battle-skip rule applied after computing target.
INTENTS.ADVANCE_PHASE=function(plr,a)
 if plr~=G.active then return false,"not active player" end
 if G.winner then return false,"game over" end
 doAdvancePhase(a.to)
 return true
end

-- ============================================================
-- DISPATCHER
-- ============================================================
-- RESPONSE is the only intent valid during a response window (procBusy=true).
-- All others reject on procBusy and must be in PHASE_TABLE[G.ph].legal.
-- Active-player checks are delegated to handlers (some intents are valid for
-- the non-turn player).
function submitIntent(plr,t,a)
 a=a or {}
 local fn=INTENTS[t]
 if not fn then
  trace("intent: unknown type "..tostring(t))
  return false,"unknown intent"
 end
 if t=="RESPONSE" then
  local cc=G.proc and G.proc.currentChoice
  if not (cc and cc.kind=="response" and cc.plr==plr) then
   trace("intent: RESPONSE outside response window")
   return false,"no response window"
  end
 else
  if procBusy() then
   trace("intent: "..t.." rejected (procBusy)")
   return false,"busy"
  end
  local ph=PHASE_TABLE[G.ph]
  if not (ph and ph.legal[t]) then
   trace("intent: "..t.." illegal in phase "..tostring(G.ph))
   return false,"illegal phase"
  end
 end
 return fn(plr,a)
end
