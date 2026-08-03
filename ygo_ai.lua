-- [ygo_ai] YGO80 module -- loaded via require() from ygo80.lua

AI_DELAY=40

-- The AI picks moves by simulating them (see SIMULATION-DRIVEN MOVE SELECTION
-- below), so "is this worth doing?" is answered by comparing board scores
-- against doing nothing. The old per-action thresholds are gone with the
-- scorers they gated. This one survives because response windows still fall
-- back to per-card scores when replay can't reproduce the chain.
TRAP_ACTIVATE_THRESHOLD=200

-- ============================================================
-- AI HELPERS (callable from BEHAVIORS.ai hooks)
-- ============================================================
function aiBestGyMonsterAtk(plr)
 local best=0
 for _,c in ipairs(G.gy[plr]) do
  if c.cat=="monster" and (c.atk or 0)>best then best=c.atk end
 end
 return best
end

-- ============================================================
-- AI CONTEXT
-- ============================================================
function aiBuildCtx(plr)
 local opp=3-plr
 local ownMons,oppMons={},{}
 local ownAtkTotal,oppAtkTotal=0,0
 local ownFaceUp,oppFaceUp=0,0
 for c=1,3 do
  local m=G.mon[plr][c]
  if m then
   ownMons[#ownMons+1]={card=m,col=c}
   if not m.facedown then
    ownFaceUp=ownFaceUp+1
    ownAtkTotal=ownAtkTotal+(getMonAtk(m) or 0)
   end
  end
  local om=G.mon[opp][c]
  if om then
   oppMons[#oppMons+1]={card=om,col=c}
   if not om.facedown then
    oppFaceUp=oppFaceUp+1
    oppAtkTotal=oppAtkTotal+(getMonAtk(om) or 0)
   end
  end
 end
 local ownST,oppST=0,0
 for c=1,3 do
  if G.st[plr][c] then ownST=ownST+1 end
  if G.st[opp][c] then oppST=oppST+1 end
 end
 return {
  plr=plr, opp=opp,
  ownLP=G.lp[plr], oppLP=G.lp[opp],
  ownMons=ownMons, oppMons=oppMons,
  ownAtkTotal=ownAtkTotal, oppAtkTotal=oppAtkTotal,
  ownFaceUp=ownFaceUp, oppFaceUp=oppFaceUp,
  ownST=ownST, oppST=oppST,
  ownFS=G.fs[plr], oppFS=G.fs[opp],
  handSize=#G.hand[plr], oppHandSize=#G.hand[opp], deckSize=#G.deck[plr],
  turn=G.turn,
 }
end

-- ============================================================
-- RESPONSE FALLBACK SCORING
-- ============================================================
-- The only surviving per-card score. Used when the AI must answer a response
-- window that simScoreResponse declined -- the opponent chose to chain, and
-- replay cannot reproduce that without their hidden cards. Everything else
-- the AI decides is decided by simulation.
local function aiHook(card,name)
 local b=behaviorOf(card)
 return b and b.ai and b.ai[name]
end

function scoreTrapActivate(card,plr,ctx,event,eventCtx)
 if not card then return nil end
 local fn=aiHook(card,"scoreActivate")
 if not fn then return nil end
 local s=fn(card,plr,ctx,event,eventCtx)
 if s==nil then return nil end
 if G.strategy and G.strategy.activateBonus then
  s=s+(G.strategy.activateBonus(card,ctx,event,eventCtx) or 0)
 end
 return s
end

-- ============================================================
-- SIMULATION-DRIVEN MOVE SELECTION
-- ============================================================
-- Enumerate every legal action, play each one out on a snapshot through the
-- real engine, and keep the one whose resulting board scores highest. There
-- are no per-card scoring hooks on this path: a card is AI-usable as soon as
-- it works for the player, because the AI runs the same code.
AI_ENABLER_K=5   -- how many flat/negative moves get a second look at 2 plies

-- Moves are LOCATORS, never card references: every snapshot restore rebuilds
-- the card tables, so a captured reference points at a table that is no
-- longer on the board. simReboundArgs re-resolves card from handIdx at apply
-- time. Destination column is always firstEmpty -- which empty zone a monster
-- lands in never changes the board score, so enumerating all three would
-- triple the search for nothing.
local function tributeCombos(card,plr,need)
 if need<=0 then return {{}} end
 local occ={}
 for c=1,3 do if G.mon[plr][c] then occ[#occ+1]=c end end
 local out={}
 for i=1,#occ do
  if tributeValueOf(card,G.mon[plr][occ[i]])>=need then
   out[#out+1]={occ[i]}
  end
  for j=i+1,#occ do
   local v=tributeValueOf(card,G.mon[plr][occ[i]])+tributeValueOf(card,G.mon[plr][occ[j]])
   if v>=need then out[#out+1]={occ[i],occ[j]} end
  end
 end
 return out
end

function aiEnumerateMain(plr)
 local moves={}
 local function add(t,args,label) moves[#moves+1]={type=t,args=args,label=label} end
 local monCol=firstEmpty(G.mon[plr])
 local stCol=firstEmpty(G.st[plr])

 for i,card in ipairs(G.hand[plr]) do
  local b=behaviorOf(card)
  if card.cat=="monster" then
   if not G.normalSummoned then
    local need=tribsNeeded(getMonLvl(card))
    for _,tr in ipairs(tributeCombos(card,plr,need)) do
     local dest=monCol or tr[1]
     if dest then
      add("SUMMON",{handIdx=i,col=dest,position="ATK",tributes=tr},"SUMMON "..card.name)
      add("SUMMON",{handIdx=i,col=dest,position="SET",tributes=tr},"SET "..card.name)
     end
    end
   end
   -- Legion's extra summon. Enumerating it is what makes the ignition worth
   -- firing: the ignition alone changes no board state, so it only ever wins
   -- via the enabler pass finding this follow-up.
   if G.extraSpellcasterSummon and card.type=="spellcaster" then
    local need=tribsNeeded(getMonLvl(card))
    if need>=1 then
     for _,tr in ipairs(tributeCombos(card,plr,need)) do
      local dest=monCol or tr[1]
      if dest then
       add("SUMMON",{handIdx=i,col=dest,position="ATK",tributes=tr,extra=true},
        "XSUMMON "..card.name)
      end
     end
    end
   end
   if b and b.handIgnition
      and (not b.handIgnition.canActivate or b.handIgnition.canActivate(card,plr)) then
    add("HAND_IGNITION",{handIdx=i},"HANDIGN "..card.name)
   end
  elseif card.cat=="spell" then
   local ok=true
   if card.subtype=="equip" then ok=false           -- needs a target; see below
   elseif b and b.canActivate then ok=b.canActivate(card,plr) end
   if ok and (stCol or card.subtype=="field") then
    add("CAST",{handIdx=i},"CAST "..card.name)
   end
   if stCol and card.subtype~="field" then
    add("SET_ST",{handIdx=i,col=stCol},"SET "..card.name)
   end
  elseif card.cat=="trap" then
   if stCol then add("SET_ST",{handIdx=i,col=stCol},"SET "..card.name) end
  end
 end

 for c=1,3 do
  local m=G.mon[plr][c]
  if m then
   if not m.summoned and not m.posChanged then
    add("CHANGE_POS",{col=c},"CHGPOS "..c)
   end
   if not m.facedown then
    local b=behaviorOf(m)
    if b and b.ignition
       and (not b.ignition.canActivate or b.ignition.canActivate(m,plr)) then
     add("IGNITION",{col=c},"IGNITION "..m.name)
    end
   end
  end
  local st=G.st[plr][c]
  if st and st.facedown and not st.setThisTurn then
   local b=behaviorOf(st)
   if b and not b.responseOnly
      and (not b.canActivate or b.canActivate(st,plr)) then
    add("ACTIVATE",{col=c},"ACTIVATE "..st.name)
   end
  end
 end
 return moves
end

-- Equip spells are enumerated separately: they carry a target, so each
-- (equip, monster) pair is its own move.
local function addEquipMoves(plr,moves)
 local stCol=firstEmpty(G.st[plr])
 if not stCol then return end
 for i,card in ipairs(G.hand[plr]) do
  if card.cat=="spell" and card.subtype=="equip" then
   for p=1,2 do
    for c=1,3 do
     local m=G.mon[p][c]
     if m and not m.facedown then
      moves[#moves+1]={type="CAST",
       args={handIdx=i,col=stCol,target={plr=p,col=c}},
       label="EQUIP "..card.name}
     end
    end
   end
  end
 end
end

-- Score one move by playing it out. Returns nil if it could not be applied.
local function aiScoreMove(plr,mv,snap)
 local ok,score=simRun(plr,function()
  return submitIntent(plr,mv.type,simReboundArgs(plr,mv.args))
 end,snap)
 if not ok then return nil end
 return score
end

-- Greedy argmax is blind to moves whose payoff lands on the NEXT move: an
-- enabler changes nothing visible, so it scores at the baseline forever.
-- Anything at or below the baseline gets re-scored as "best follow-up",
-- which also catches cost-payers that dip below it. Two plies, never three.
local function aiScoreWithFollowUp(plr,mv,snap)
 local best=nil
 local ok=simRun(plr,function()
  if not submitIntent(plr,mv.type,simReboundArgs(plr,mv.args)) then return end
  simDrain()
  local inner=simSnapshot()
  for _,m2 in ipairs(aiEnumerateMain(plr)) do
   local ok2,s2=simRun(plr,function()
    return submitIntent(plr,m2.type,simReboundArgs(plr,m2.args))
   end,inner)
   if ok2 and (best==nil or s2>best) then best=s2 end
  end
 end,snap)
 if not ok then return nil end
 return best
end

function aiDoMain()
 local plr=2
 local moves=aiEnumerateMain(plr)
 addEquipMoves(plr,moves)
 if #moves==0 then return false end

 local snap=simSnapshot()
 -- Doing nothing is a move like any other: it is the baseline every other
 -- move must beat, and it replaces the old per-action score thresholds.
 local _,baseline=simRun(plr,function() end,snap)
 if baseline==nil then return false end

 local best,bestMv=baseline,nil
 local flat={}
 for _,mv in ipairs(moves) do
  local s=aiScoreMove(plr,mv,snap)
  if s then
   mv.score=s
   if s>best then best,bestMv=s,mv end
   if s<=baseline then flat[#flat+1]=mv end
  end
 end

 table.sort(flat,function(a,b) return (a.score or 0)>(b.score or 0) end)
 for i=1,math.min(AI_ENABLER_K,#flat) do
  local s=aiScoreWithFollowUp(plr,flat[i],snap)
  if s and s>best then best,bestMv=s,flat[i] end
 end

 if not bestMv then return false end
 return submitIntent(plr,bestMv.type,simReboundArgs(plr,bestMv.args)) and true or false
end

-- Attacks are direct-value: no enabler pass, no follow-up ply. Enumerate
-- every legal (attacker, target) pair plus "stop attacking" and play them out.
function aiDoNextAttack()
 local plr=2
 local moves={}
 local oppHasMons=hasMonsters(1)
 for ac=1,3 do
  local att=G.mon[plr][ac]
  if att and att.pos==1 and not att.facedown and not att.attacked
     and not attackBlocked(att,plr) then
   if oppHasMons then
    for tc=1,3 do
     if G.mon[1][tc] then
      moves[#moves+1]={atkCol=ac,tgtCol=tc}
     end
    end
   else
    moves[#moves+1]={atkCol=ac,tgtCol=nil}
   end
  end
 end
 if #moves==0 then return false end

 local snap=simSnapshot()
 local _,baseline=simRun(plr,function() end,snap)
 if baseline==nil then return false end

 local best,bestMv=baseline,nil
 for _,mv in ipairs(moves) do
  local ok,s=simRun(plr,function()
   return submitIntent(plr,"DECLARE_ATTACK",{atkCol=mv.atkCol,tgtCol=mv.tgtCol})
  end,snap)
  if ok and s and s>best then best,bestMv=s,mv end
 end

 -- No attack beats standing pat: mark the rest done so the phase can end
 -- instead of re-deciding the same non-attack every tick.
 if not bestMv then
  for ac=1,3 do
   local att=G.mon[plr][ac]
   if att and att.pos==1 and not att.facedown and not att.attacked
      and not attackBlocked(att,plr) then
    att.attacked=true
   end
  end
  return false
 end

 G.battleAnim={atkCol=bestMv.atkCol,tgtCol=bestMv.tgtCol}
 addAnim(30,function() end,function()
  if not submitIntent(plr,"DECLARE_ATTACK",{atkCol=bestMv.atkCol,tgtCol=bestMv.tgtCol}) then
   G.battleAnim=nil
  end
 end)
 return true
end

function aiTick()
 if G.active~=2 or G.winner or #ANIM>0 or G.menu.open or G.infoCard or G.mode=="sel_deck" or G.mode=="sel_destroy" or G.mode=="sel_discard" or G.mode=="sel_st_target" then return end
 if procBusy() then return end
 G.aiTimer=G.aiTimer-1
 if G.aiTimer>0 then return end
 G.aiTimer=AI_DELAY
 if G.ph==PH_MAIN then
  if not aiDoMain() then submitIntent(2,"ADVANCE_PHASE",{}) end
 elseif G.ph==PH_BATTLE then
  if not aiDoNextAttack() then submitIntent(2,"ADVANCE_PHASE",{}) end
 else
  submitIntent(2,"ADVANCE_PHASE",{})
 end
end
