-- [ygo_ai] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- AI
-- ============================================================
AI_DELAY=40  -- frames between AI actions (~0.67s at 60fps)

function aiDoMain()
 -- Monster ignition effects (Kaibaman SS Blue-Eyes etc.).
 for col=1,3 do
  local m=G.mon[2][col]
  if m and not m.facedown then
   local b=behaviorOf(m)
   if b and b.ignition and (not b.ignition.canActivate or b.ignition.canActivate(m,2)) then
    b.ignition.activate(m,2,col)
    return true
   end
  end
 end
 -- Activate direct-damage / board-wipe spells (one per tick).
 -- A spell is castable iff its BEHAVIORS entry has aiCanCast(card) returning true.
 for i=#G.hand[2],1,-1 do
  local card=G.hand[2][i]
  if card.cat=="spell" then
   local b=behaviorOf(card)
   local doIt=b and b.aiCanCast and b.aiCanCast(card)
   if doIt then
    -- CAST intent handles all three sub-cases: field (→ FS zone), normal
    -- with S/T free (→ S/T zone), and no-S/T-free fallback (→ hand-GY direct).
    if submitIntent(2,"CAST",{card=card,handIdx=i}) then return true end
   end
  end
 end
 -- Set one trap card face-down per tick
 local stEmpty=firstEmpty(G.st[2])
 if stEmpty then
  for i=#G.hand[2],1,-1 do
   local card=G.hand[2][i]
   if card.cat=="trap" then
    if submitIntent(2,"SET_ST",{card=card,col=stEmpty,handIdx=i}) then
     return true
    end
   end
  end
 end
 -- Normal summon (once per turn)
 if G.normalSummoned then return false end
 local empty,occupied={},{}
 for i=1,3 do
  if G.mon[2][i] then table.insert(occupied,i) else table.insert(empty,i) end
 end
 local bestAtk,bestIdx=-1,nil
 for i,card in ipairs(G.hand[2]) do
  if card.cat=="monster" then
   local trib=tribsNeeded(getMonLvl(card))
   local ok=(trib==0 and #empty>0)
         or (trib>=1 and #empty>0 and fieldTributeValue(card,2)>=trib)
   if ok and card.atk>bestAtk then bestAtk=card.atk; bestIdx=i end
  end
 end
 if not bestIdx then return false end
 local card=G.hand[2][bestIdx]
 local trib=tribsNeeded(getMonLvl(card))
 -- Set face-down DEF when defense stat exceeds attack stat
 local useDefPos=(card.def or 0)>card.atk
 local tribs=(trib>0) and aiPickTributes(card,occupied,trib) or {}
 -- Destination zone: prefer a truly-empty col; falls back to a tribute col
 -- (the intent treats tribute cols as available since they vacate atomically).
 local destCol=empty[1] or tribs[1]
 return submitIntent(2,"SUMMON",{
  card=card, col=destCol,
  position=useDefPos and "SET" or "ATK",
  tributes=tribs, handIdx=bestIdx,
 })
end

-- Returns the best profitable target column for attacker, or nil if none.
-- Profitable: vs ATK target att.atk >= target.atk; vs DEF target att.atk > target.def
local function aiBestTarget(att)
 local bestScore,bestCol=math.huge,nil
 local attAtk=getMonAtk(att)
 for j=1,3 do
  local t=G.mon[1][j]
  if t then
   local s,ok
   if t.facedown then
    -- Face-down monster: the AI can't see its stats, so it attacks
    -- speculatively. Scored above known kills so clean kills go first.
    s=3000; ok=true
   elseif t.pos==2 then
    s=getMonDef(t); ok=(attAtk>s)
   else
    s=getMonAtk(t);   ok=(attAtk>=s)
   end
   if ok and s<bestScore then bestScore=s; bestCol=j end
  end
 end
 return bestCol
end

function aiDoNextAttack()
 for i=G.aiBattleIdx,3 do
  local att=G.mon[2][i]
  if att and att.pos==1 and not att.facedown and not att.attacked
     and not attackBlocked(att,2) then
   local hasPlr=hasMonsters(1)
   local tgtCol=hasPlr and aiBestTarget(att) or nil
   if hasPlr and not tgtCol then
    -- Player has monsters but none are a worthwhile target (e.g. a face-up
    -- DEF wall the AI can't break). Skip this attacker without declaring.
    att.attacked=true
   else
   G.aiBattleIdx=i+1
   -- Show declaration indicator for 30 frames, then submit the intent. The
   -- DECLARE_ATTACK intent owns push-then-raiseNow + chain + battle body for
   -- both direct (tgtCol=nil) and target attacks; applyDamage in the body
   -- raises EV_BEFORE_DAMAGE for Kuriboh-style hand traps.
   local resolvedTgt=(not hasMonsters(1)) and nil or tgtCol
   G.battleAnim={atkCol=i,tgtCol=resolvedTgt}
   addAnim(30,function()end,function()
    if not submitIntent(2,"DECLARE_ATTACK",{atkCol=i,tgtCol=resolvedTgt}) then
     G.battleAnim=nil
    end
   end)
   return true
   end
  end
 end
 return false
end

function aiTick()
 if G.active~=2 or G.winner or #ANIM>0 or G.menu.open or G.infoCard or G.mode=="sel_deck" or G.mode=="sel_destroy" or G.mode=="sel_discard" or G.mode=="sel_st_target" then return end
 -- Pause AI while any chain / response / event resolution is in flight.
 -- Without this, aiTick keeps advancing the AI's turn while a coroutine
 -- is waiting on the player's response.
 if procBusy() then return end
 G.aiTimer=G.aiTimer-1
 if G.aiTimer>0 then return end
 G.aiTimer=AI_DELAY
 -- Pick at most one action per tick. MAIN/BATTLE try card-action intents
 -- first; if none fit, fall through to ADVANCE_PHASE. DRAW/STBY/END have
 -- no AI card actions, so always advance. ADVANCE_PHASE's PH_BATTLE.onEnter
 -- resets aiBattleIdx; PH_END.onExit flips active + does new-turn setup.
 if G.ph==PH_MAIN then
  if not aiDoMain() then submitIntent(2,"ADVANCE_PHASE",{}) end
 elseif G.ph==PH_BATTLE then
  if not aiDoNextAttack() then submitIntent(2,"ADVANCE_PHASE",{}) end
 else
  submitIntent(2,"ADVANCE_PHASE",{})
 end
end

