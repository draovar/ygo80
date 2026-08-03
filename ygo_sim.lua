-- [ygo_sim] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- SIMULATION HARNESS
-- ============================================================
-- Lets the AI answer "what does the board look like after this move?" by
-- running the REAL engine forward on a snapshot, then rolling back. There is
-- no separate rules model to keep in sync -- a move is scored by the same
-- code that would execute it for real.
--
-- Three things have to be neutralised while simulating:
--   * animations   -- addAnim fires its onDone immediately (G.sim check there)
--   * choices      -- procRouteChoice hands every request to simAnswer
--   * hidden cards -- collectListeners drops the opponent's face-down S/T and
--                     their hand, so their identity can't leak into the score
--
-- Preconditions: procIdle() and no animations in flight. simRun asserts both.

SIM_MAX_TICKS=400   -- drain cap; a chain that needs more is a bug, not deep
SIM_COIN=1          -- pinned RNG (see "known gaps" at the bottom)
SIM_DICE=3

-- ============================================================
-- SNAPSHOT / RESTORE
-- ============================================================
-- Identity-preserving deep copy. Card tables are reachable from several
-- places at once (equippedTo, linkedMon, chain links, ctx.card), and effects
-- test them with `==`. A plain recursive copy would split one card into
-- several and silently break every one of those tests, so shared references
-- have to stay shared inside a snapshot.
local function deepCopy(v,memo)
 if type(v)~="table" then return v end
 local hit=memo[v]
 if hit then return hit end
 local out={}
 memo[v]=out
 for k,val in pairs(v) do out[deepCopy(k,memo)]=deepCopy(val,memo) end
 return out
end

-- G.proc is excluded: it holds live coroutines (not copyable) and simRun
-- requires an idle processor anyway. Everything else in G is game state or
-- UI state, and rolling UI state back too is what we want -- a simulation
-- must not leave cursor/menu residue behind.
function simSnapshot()
 local memo={}
 local snap={}
 for k,v in pairs(G) do
  if k~="proc" then snap[k]=deepCopy(v,memo) end
 end
 return snap
end

-- Installs a FRESH copy each call, so one snapshot can seed many candidate
-- moves without the sim mutating the snapshot itself.
function simRestore(snap)
 local memo={}
 for k in pairs(G) do
  if k~="proc" then G[k]=nil end
 end
 for k,v in pairs(snap) do G[k]=deepCopy(v,memo) end
 procInit()
end

-- Replay bookkeeping. These live OUTSIDE G on purpose: ORIGIN holds a whole
-- snapshot, and if it sat in G then simSnapshot would deep-copy the previous
-- snapshot into the next one and the cost would double every turn.
local ORIGIN=nil     -- {plr,type,args,snap} -- last action taken from idle
local DECISIONS={}   -- response answers already given in the current chain
local RESPONDED={}   -- players who chained into the current chain by choice
local PLAN=nil       -- scripted answers while replaying (see simScoreResponse)

-- ============================================================
-- CHOICE POLICY WHILE SIMULATING
-- ============================================================
-- Called from procRouteChoice instead of the normal player/AI split.
function simAnswer(req)
 if req.kind=="coin" then return SIM_COIN end
 if req.kind=="dice" then return SIM_DICE end
 if req.kind=="response" then
  -- The opponent's set cards must not act inside a simulation. Letting them
  -- respond would make the resulting score reflect a card the AI cannot see,
  -- which leaks its identity just as surely as reading it directly.
  if req.plr~=G.simActor then return false end
  -- Follow the script: the answers already given this chain, then the one
  -- candidate being measured. Anything past the script passes, so a replay
  -- can't recurse into scoring another response.
  if PLAN then
   PLAN.i=PLAN.i+1
   local step=PLAN[PLAN.i]
   if step~=nil then return step end
  end
  return false
 end
 local ok,ans=pcall(aiAnswer,req)
 if not ok or ans==nil then return false end
 return ans
end

-- ============================================================
-- RUN
-- ============================================================
-- Drives the processor to completion. Every wait resolves inline under sim
-- (anims fire instantly, choices answer inline), so this terminates in a
-- handful of passes; the cap only exists to contain a genuine bug.
function simDrain()
 local n=0
 while not procIdle() and n<SIM_MAX_TICKS do
  procTick()
  n=n+1
 end
 return n<SIM_MAX_TICKS,n
end

-- Run `body` against a throwaway copy of the current state and return the
-- evaluation from plr's point of view. State is always rolled back, including
-- when body errors.
--   ok    -- body ran and the processor drained
--   score -- simEvaluate(plr) on the resulting board
-- Rollback is by REFERENCE, not by re-copying the snapshot. The simulation
-- works entirely on fresh copies, so the live tables are never touched and
-- handing the originals back restores the live state with its object identity
-- intact. That matters once this is called mid-chain: a suspended coroutine
-- on the live proc stack holds direct references to card tables, and giving
-- it back copies instead of the originals would silently detach it from the
-- board it is operating on.
function simRun(plr,body,snap)
 snap=snap or simSnapshot()
 local liveProc=G.proc
 local live={}
 for k,v in pairs(G) do
  if k~="proc" then live[k]=v end
 end

 simRestore(snap)
 G.sim=true
 G.simActor=plr
 local ok,err=pcall(body)
 local drained=false
 if ok then drained=simDrain() end
 local score=nil
 if ok and drained then score=simEvaluate(plr) end

 for k in pairs(G) do
  if k~="proc" then G[k]=nil end
 end
 for k,v in pairs(live) do G[k]=v end
 G.proc=liveProc

 if not ok then return false,nil,tostring(err) end
 if not drained then return false,nil,"drain cap hit" end
 return true,score,nil
end

-- ============================================================
-- RESPONSE SCORING BY REPLAY
-- ============================================================
-- A response window cannot be snapshotted: it is mid-chain, and the frame
-- stack holds live coroutines, which Lua cannot copy. So instead of forking
-- from the decision point, we fork from the last IDLE point and replay the
-- action that opened the chain, scripting the answers along the way. This is
-- only expressible because every action is now an intent with a plain
-- argument table -- there is no hidden state in "what the opponent did".

-- Called from submitIntent. Only fires when the engine is idle, so it records
-- turn actions and never the RESPONSE intents inside a chain.
function simRecordOrigin(plr,t,a)
 if G.sim then return end
 if t=="RESPONSE" then return end
 -- Clear rather than skip when the fork point can't be captured: a leftover
 -- ORIGIN would replay some earlier action and score the wrong board.
 if not procIdle() or #ANIM>0 then ORIGIN=nil; DECISIONS={}; RESPONDED={}; return end
 ORIGIN={plr=plr,type=t,args=a,snap=simSnapshot()}
 DECISIONS={}
 RESPONDED={}
end

function simNoteDecision(ans)
 if G.sim then return end
 DECISIONS[#DECISIONS+1]=(ans==nil) and false or ans
end

-- Card references in an intent's args point at tables that no longer exist
-- after a restore. handIdx is the locator every card-carrying intent already
-- supplies, so rebinding through it is enough to make args replay-safe.
function simReboundArgs(plr,a)
 local r={}
 for k,v in pairs(a) do r[k]=v end
 if r.handIdx and G.hand[plr] then r.card=G.hand[plr][r.handIdx] end
 return r
end
local reboundArgs=simReboundArgs

-- Replay reproduces the action that OPENED the chain (it is ORIGIN), so the
-- opponent merely acting is fine. What it cannot reproduce is the opponent
-- *choosing* to chain, because their hidden responders are suppressed inside
-- a simulation. Track that specific event and nothing else.
function simNoteOpponentResponse(plr)
 if G.sim then return end
 RESPONDED[plr]=true
end

-- Scores passing against activating each offered responder, by replaying the
-- whole chain from idle once per candidate. Returns the best answer
-- ({optionIdx=N} or false), or nil when replay isn't applicable.
function simScoreResponse(req)
 if G.sim or not ORIGIN then return nil end
 local plr=req.plr
 if RESPONDED[3-plr] then return nil end

 local cands={false}
 for i=1,#(req.options or {}) do cands[#cands+1]={optionIdx=i} end

 local best,bestAns=nil,nil
 for _,cand in ipairs(cands) do
  local plan={i=0}
  for j,d in ipairs(DECISIONS) do plan[j]=d end
  plan[#DECISIONS+1]=cand
  PLAN=plan
  local o=ORIGIN
  local ok,score=simRun(plr,function()
   submitIntent(o.plr,o.type,reboundArgs(o.plr,o.args))
  end,o.snap)
  PLAN=nil
  if ok and (best==nil or score>best) then best,bestAns=score,cand end
 end
 return bestAns
end

-- ============================================================
-- EVALUATION  (placeholder weights -- tune these, the shape is what matters)
-- ============================================================
-- One signed number, AI-positive. Everything is expressed in life-point
-- equivalents so the terms are actually comparable: a monster is worth
-- roughly the damage it threatens per turn, a card is worth what it buys.
SIM_W={
 atk          =1.0,    -- face-up ATK monster: threatens ~ATK per turn
 def          =0.5,    -- wall: denies damage, deals none
 faceDownMon  =300,    -- unknown body, some defensive value
 backrow      =500,    -- a set card is a threat whoever owns it
 handCard     =450,
 normalSummon =600,    -- an unused summon is a resource, not nothing
 extraSummon  =600,
 win          =1000000,
}

local function simSideValue(p)
 local s=G.lp[p] or 0
 for c=1,3 do
  local m=G.mon[p][c]
  if m then
   if m.facedown then s=s+SIM_W.faceDownMon
   elseif m.pos==1 then s=s+(getMonAtk(m) or 0)*SIM_W.atk
   else s=s+(getMonDef(m) or 0)*SIM_W.def end
  end
  if G.st[p][c] then s=s+SIM_W.backrow end
 end
 s=s+#G.hand[p]*SIM_W.handCard
 return s
end

function simEvaluate(plr)
 local opp=3-plr
 if G.winner==plr then return SIM_W.win end
 if G.winner==opp then return -SIM_W.win end
 local s=simSideValue(plr)-simSideValue(opp)
 -- Latent capabilities. Without these, any move whose only product is a
 -- capability (Legion's extra summon) evaluates as exactly zero.
 if G.active==plr and not G.normalSummoned then s=s+SIM_W.normalSummon end
 if G.extraSpellcasterSummon then s=s+SIM_W.extraSummon end
 return s
end

-- ============================================================
-- BENCHMARK  (call simBench() from a debug key; traces to the console)
-- ============================================================
-- Answers the one question that sizes the whole design: how many full move
-- simulations fit in a frame? That number decides whether the AI enumerates
-- every legal move or pre-filters to a candidate set, and how deep the
-- enabler re-examination pass (K) can go.
-- NOTE for the enumerator: a move must be a LOCATOR (hand index, zone column),
-- never a captured card reference. Every restore rebuilds the card tables, so
-- a reference taken before the snapshot points at a table that is no longer
-- the one on the board. Each body below re-resolves its cards from live state.
local function benchFirstSummon(plr)
 for i,card in ipairs(G.hand[plr]) do
  if card.cat=="monster" and tribsNeeded(getMonLvl(card))==0 then
   return function()
    local c=G.hand[plr][i]
    local col=firstEmpty(G.mon[plr])
    if not c or not col then return false end
    return submitIntent(plr,"SUMMON",{card=c,col=col,position="ATK",handIdx=i})
   end,"SUMMON "..tostring(card.name)
  end
 end
 return nil,"no summonable monster in hand"
end

local function benchFirstCast(plr)
 for i,card in ipairs(G.hand[plr]) do
  if card.cat=="spell" and card.subtype~="equip" and card.subtype~="field" then
   local b=behaviorOf(card)
   if not (b and b.canActivate) or b.canActivate(card,plr) then
    return function()
     local c=G.hand[plr][i]
     if not c then return false end
     return submitIntent(plr,"CAST",{card=c,handIdx=i})
    end,"CAST "..tostring(card.name)
   end
  end
 end
 return nil,"no castable spell in hand"
end

local function benchOne(plr,make,iters)
 local body,label=make(plr)
 if not body then return label end
 -- The bench may be pressed on either turn or in any phase; the intent layer
 -- would reject on both counts. Legal to force inside a snapshot.
 local committed=0
 local wrapped=function()
  G.active=plr
  G.ph=PH_MAIN
  if body() then committed=committed+1 end
 end
 local snap=simSnapshot()
 simRun(plr,wrapped,snap)   -- warm-up: keeps first-call GC out of the average
 committed=0
 local t0=time()
 local errs=0
 for _=1,iters do
  local ok=simRun(plr,wrapped,snap)
  if not ok then errs=errs+1 end
 end
 local dt=time()-t0
 -- A rejected intent costs almost nothing to "simulate", so a run with
 -- rejections is measuring the snapshot, not the effect. Say so plainly.
 return string.format("%s: %.2f ms/sim over %d (%.1f/frame) committed=%d errored=%d",
  label,dt/iters,iters,(dt>0) and (16.6/(dt/iters)) or 999,committed,errs)
end

function simBench(iters)
 -- 200, not 20: TIC-80's time() resolves to about a millisecond, so a run
 -- totalling only a few ms measures the clock more than the code.
 iters=iters or 200
 local plr=2
 if not procIdle() then trace("simBench: proc busy"); return end
 if #ANIM>0 then trace("simBench: anim in flight"); return end
 local function countMon(p)
  local n=0
  for c=1,3 do if G.mon[p][c] then n=n+1 end end
  return n
 end
 -- Clone cost scales with everything below, so a timing is only meaningful
 -- alongside the board it was taken on. Re-run this late in a duel.
 trace(string.format("simBench: turn=%d gy=%d/%d hand=%d/%d mon=%d/%d deck=%d/%d",
  G.turn,#G.gy[1],#G.gy[2],#G.hand[1],#G.hand[2],
  countMon(1),countMon(2),#G.deck[1],#G.deck[2]))

 local snap=simSnapshot()
 -- Hold the live tables by reference: the timing loop below overwrites G with
 -- copies, and handing back the originals is the only exact rollback.
 local live={}
 for k,v in pairs(G) do
  if k~="proc" then live[k]=v end
 end
 simRestore(snap)   -- warm-up
 local t0=time()
 for _=1,iters do simRestore(snap) end
 local cloneMs=(time()-t0)/iters
 for k in pairs(G) do
  if k~="proc" then G[k]=nil end
 end
 for k,v in pairs(live) do G[k]=v end
 trace(string.format("simBench: snapshot restore %.3f ms",cloneMs))
 trace("simBench: "..tostring(benchOne(plr,benchFirstSummon,iters)))
 trace("simBench: "..tostring(benchOne(plr,benchFirstCast,iters)))
end

-- ============================================================
-- KNOWN GAPS  (deliberate for the spike -- close before shipping the AI)
-- ============================================================
-- * RNG is pinned (SIM_COIN/SIM_DICE), so Time Wizard always simulates as a
--   win and Graceful Dice as a 3. The fix is to run both/all branches and
--   average, which multiplies sim count -- decide after the numbers below.
-- * Opponent responses are suppressed entirely, so the AI plays as if no
--   traps exist and will walk into Mirror Force. That reads as an optimistic
--   personality; a flat risk penalty per unknown backrow tunes it without
--   ever revealing what the card is.
-- * simEvaluate has no term for persistent effects yet (swordsCounter,
--   staticActive buffs). Those are readable from state -- see the design
--   note: lasting value must leave a trace, and the evaluator scores traces.
