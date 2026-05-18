-- [ygo_chain] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- CHAIN STACK
-- ============================================================
-- The chain is YGO's mechanism for resolving simultaneous/responding
-- effects. LIFO: links push onto the top as players respond, then resolve
-- from top to bottom once both players pass consecutively.
--
-- G.chain is nil when no chain is active. When active:
--   G.chain = {
--     links    = { EffectInstance, ... },   -- index 1 = Link 1 (bottom)
--     offering = 1 | 2,                     -- who currently has priority
--     passes   = 0,                         -- 2 = both passed -> resolve
--     trigger  = { event=, ctx= } | nil,    -- the action that opened this
--     reason   = "spell"|"trap"|"trigger",  -- why this chain exists
--   }
--
-- EffectInstance fields:
--   source     - the card object
--   controller - 1 | 2  (who activated)
--   speed      - 1 | 2 | 3
--   sourceLoc  - { zone, plr, col } cleanup location after resolution
--                  zone = "st" | "hand" | "field" | nil
--   targets    - frozen snapshot at activation (for fizzle checks)
--   resolveFn  - function(self) called when this link resolves
--
-- This file ONLY defines the data model + lifecycle. Existing code paths
-- (spell activation, attack resolution, AI traps) have not been rewired
-- yet -- the game still works as before. Wiring is step 2b.

-- Derive spell speed from card data so we don't have to annotate every card.
function chainSpeed(card)
 if not card then return 1 end
 local b=behaviorOf(card)
 if b and b.speed then return b.speed end
 if card.cat=="trap"  then return card.subtype=="counter"   and 3 or 2 end
 if card.cat=="spell" then return card.subtype=="quickplay" and 2 or 1 end
 return 1  -- monster default (Ignition / Flip / Trigger)
end

function chainTopSpeed()
 if not G.chain or #G.chain.links==0 then return 0 end
 return G.chain.links[#G.chain.links].speed
end

function openChain(trigger,reason)
 G.chain={links={},offering=nil,passes=0,trigger=trigger,reason=reason}
end

function closeChain()
 G.chain=nil
end

function pushChainLink(link)
 if not G.chain then openChain(nil,"spell") end
 link.speed=link.speed or chainSpeed(link.source)
 table.insert(G.chain.links,link)
 G.chain.passes=0
 G.chain.offering=3-link.controller  -- pass priority to opponent
end

-- Build a chain link for a spell or trap card activated from a known location.
-- col may be nil for cards activated from hand (e.g. Quick-Play from hand).
function makeSpellTrapLink(card,controller,zone,plr,col,targets)
 return {
  source     = card,
  controller = controller,
  speed      = chainSpeed(card),
  sourceLoc  = {zone=zone,plr=plr,col=col},
  targets    = targets,
  resolveFn  = function(self)
   local ctx=G.chain and G.chain.trigger and G.chain.trigger.ctx
   applyResolve(self.source,self.controller,ctx)
  end,
 }
end

-- After a link resolves, dispose of its source per card type:
--  - Normal spell/trap on field -> GY
--  - Continuous/equip spell -> stays face-up on field
--  - Card activated from hand -> GY
function spendChainLink(link)
 local loc=link.sourceLoc
 if not loc then return end
 if loc.zone=="st" then
  local c=link.source
  if c.subtype=="continuous" or c.subtype=="equip" then
   c.facedown=false
  else
   sendSpellTrapToGY(loc.plr,loc.col,"effect")
  end
 elseif loc.zone=="fs" then
  -- Field spell stays face-up in the FS zone after resolving.
  link.source.facedown=false
 elseif loc.zone=="hand" then
  for i,h in ipairs(G.hand[loc.plr]) do
   if h==link.source then discardFromHand(loc.plr,i,"effect"); break end
  end
 end
end

-- Called when both players have passed consecutively.
-- Resolves links from top (last pushed) to bottom (first pushed).
-- Sets G.chainResolving=true during the loop so callbacks invoked from
-- resolveFn (e.g. legacy returnToTrapSelect) can detect they're mid-chain
-- and skip flow control they no longer own.
-- If trigger.onResolved is set and trigger.consumed is not, runs the
-- continuation after the chain closes.
function resolveChain()
 if not G.chain then return end
 local trig=G.chain.trigger
 local links=G.chain.links
 local resolved=#links>0
 G.chainResolving=true
 for i=#links,1,-1 do
  local link=links[i]
  -- Negated links (e.g. by Magic Jammer) skip their resolveFn but still
  -- run spendChainLink so the source card goes to GY / cleans up properly.
  -- (The negating effect typically also destroys the source itself, but
  -- spendChainLink is idempotent — sendSpellTrapToGY no-ops if already gone.)
  if not link.negated and link.resolveFn then link.resolveFn(link) end
  spendChainLink(link)
 end
 closeChain()
 G.chainResolving=false
 -- onDestroy etc. triggers queued during resolution become a NEW chain (SEGOC).
 flushTriggers()
 if trig and trig.onResolved then
  -- The legacy "consumed" flag (set by Mirror Force) means the original
  -- action is canceled. Migrating callers should instead check game state
  -- inside onResolved (e.g. "is the attacker still on the field?").
  local consumed=G.trapSelect and G.trapSelect.consumed
  if not consumed then trig.onResolved(resolved) end
 end
end

-- Current offering player passes. After two consecutive passes, resolve.
function passChainPriority()
 if not G.chain then return end
 G.chain.passes=G.chain.passes+1
 if G.chain.passes>=2 then
  resolveChain()
 else
  G.chain.offering=3-G.chain.offering
 end
end

-- Minimal chain stack overlay. Renders nothing when chain is empty (open
-- response window with no links yet). When N>=1 links exist, shows a small
-- chip centered above the divider listing each link bottom-to-top.
-- Small banner showing what the current input mode is asking for. Drawn
-- below the chain stack overlay when relevant.
function drawModeBanner()
 local txt=nil
 if G.mode=="sel_discard" and G.discardSel then
  txt=G.discardSel.title or "DISCARD"
 elseif G.mode=="sel_st_target" and G.stTargetSel then
  txt=G.stTargetSel.title or "PICK S/T"
 elseif G.mode=="sel_destroy" and G.destroySel and G.destroySel.title then
  txt=G.destroySel.title
 end
 if not txt then return end
 local w=#txt*4+8
 local x=FA_X+(FA_W-w)//2
 local y=DIV_Y+24
 rect(x,y,w,9,CCR)
 rectb(x,y,w,9,CT)
 print(txt,x+4,y+2,CT,true,1,true)
end

function drawChain()
 if not G.chain then return end
 local links=G.chain.links
 local n=#links
 if n==0 then return end
 local rowH=7
 local h=10+n*rowH
 local w=70
 local x=FA_X+(FA_W-w)//2
 local y=DIV_Y-h//2
 rect(x,y,w,h,CB)
 rectb(x,y,w,h,CT)
 print("CHAIN "..n,x+4,y+2,CCR,true,1,true)
 for i=1,n do
  local lk=links[i]
  local nm=(lk.source and lk.source.name) or "?"
  if #nm>13 then nm=nm:sub(1,13) end
  print(i..":"..nm,x+4,y+9+(i-1)*rowH,CT,true,1,true)
 end
end

-- Does `plr` own a face-down S/T card that could chain onto the current trigger?
-- Returns true if at least one face-down trap in plr's S/T zones has a
-- BEHAVIORS.triggers[event] (or chain_open) predicate that returns true.
-- Note: this only covers face-down S/T responses. Quick Effects from hand
-- (Kuriboh) are evaluated separately via applyDamage's handTrap hook.
function playerHasChainableResponse(plr)
 if not G.chain or not G.chain.trigger then return false end
 local trig=G.chain.trigger
 if not trig.event then return false end
 if plr==1 then
  return hasActivatableTrap(trig.event,trig.ctx)
 end
 return aiHasChainableResponse(trig.event,trig.ctx)
end

-- Find AI's first chainable face-down trap for (event,ctx). Returns
-- (stCol, trap, behavior) or nil. Used by both has-check and activation.
function findAIChainResponder(event,ctx)
 if not event then return nil end
 for i=1,3 do
  if trapCanRespond(G.st[2][i],event,ctx,2) then
   return i,G.st[2][i],behaviorOf(G.st[2][i])
  end
 end
end

function aiHasChainableResponse(event,ctx)
 return findAIChainResponder(event,ctx)~=nil
end

-- Fire AI's first matching face-down trap. If the behavior has a custom
-- `activate` (e.g. needs target picking) it's used; otherwise the standard
-- flip-anim + resolve flow runs.
function aiActivateChainResponse()
 if not G.chain or not G.chain.trigger then return end
 local trig=G.chain.trigger
 local ctx=trig.ctx or {}
 local i,t,b=findAIChainResponder(trig.event,ctx)
 if not i then return end
 if b.activate then
  b.activate{col=i,card=t,zone="st",plr=2,trigCtx=ctx}
 else
  activateAITrapAnim(i,t,function()
   if b.resolve then b.resolve(2,ctx) end
   checkWin()
  end)
 end
end

-- Drive the chain forward: while neither side has (or chooses to use) a response,
-- auto-pass priority until two consecutive passes resolve it.
-- When the player has a response, sets G.mode="opp_trap_select" and returns.
-- When the AI has a response, fires it via aiActivateChainResponse and returns;
-- the trap's flip animation will re-enter advanceChain on completion.
function advanceChain()
 while G.chain and G.chain.passes<2 do
  local offering=G.chain.offering
  if playerHasChainableResponse(offering) then
   if offering==1 then
    -- Synthesize a G.trapSelect if one doesn't exist (e.g. AI-initiated chain
    -- where checkTraps was never called). The existing opp_trap_select UI
    -- reads from G.trapSelect, so we have to populate it.
    if not G.trapSelect then
     local trig=G.chain.trigger or {}
     G.trapSelect={event=trig.event or "chain_open",ctx=trig.ctx or {},consumed=false}
    end
    G.mode="opp_trap_select"
    positionTrapSelectCursor()
    return
   end
   if offering==2 then
    aiActivateChainResponse()
    return
   end
   passChainPriority()
  else
   passChainPriority()
  end
 end
end

-- Move the cursor to a face-down trap that is currently valid to activate.
-- If the current cursor zone already holds a valid trap, leave it; otherwise
-- scan zones in order and snap to the first match.
function positionTrapSelectCursor()
 local ts=G.trapSelect
 if not ts then return end
 local col=(G.cur and G.cur.col) or 1
 if col<1 then col=1 elseif col>3 then col=3 end
 G.cur={side=1,row=2,col=col}
 if trapCanRespond(G.st[1][col],ts.event,ts.ctx,1) then return end
 for i=1,3 do
  if trapCanRespond(G.st[1][i],ts.event,ts.ctx,1) then G.cur.col=i; return end
 end
end

function tickDispLp()
 for p=1,2 do
  local diff=G.lp[p]-G.dispLp[p]
  if diff~=0 then
   local step=math.max(60,math.floor(math.abs(diff)*0.10))
   if diff>0 then G.dispLp[p]=math.min(G.lp[p],G.dispLp[p]+step)
   else        G.dispLp[p]=math.max(G.lp[p],G.dispLp[p]-step) end
  end
 end
end

-- Returns the screen X,Y of a zone for player `plr`.
--   row: "mon" | "st" | "fs" | "ed" | "gy" | "dk" | "hand"
--   col: column index 1..3 for "mon"/"st" (ignored for special / hand zones)
-- If row is "mon"/"st" and col is nil, X is returned as nil (callers that
-- only need the row Y can write `local _,y=zoneXY(plr,"st")`).
-- Encapsulates the player-side mirror (opp uses reflected column indices) in
-- one place so every drawing/animation call site can stop duplicating the
-- `(plr==1) and ... or ...` ternaries.
function zoneXY(plr, row, col)
 local px = (plr==1)
 if     row=="mon"  then return col and (px and COL[col] or COL[4-col]) or nil, px and PY_M or OY_M
 elseif row=="st"   then return col and (px and COL[col] or COL[4-col]) or nil, px and PY_S or OY_S
 elseif row=="fs"   then return px and COL[0]   or COL[4],     px and PY_M or OY_M
 elseif row=="ed"   then return px and COL[4]   or COL[0],     px and PY_M or OY_M
 elseif row=="gy"   then return px and COL[0]   or COL[4],     px and PY_S or OY_S
 elseif row=="dk"   then return px and COL[4]   or COL[0],     px and PY_S or OY_S
 elseif row=="hand" then return nil,                            px and PY_H or OY_H
 end
end

-- Back-compat shim — used by callers that only ever need a monster-zone XY.
function monZoneXY(plr,col) return zoneXY(plr,"mon",col) end

-- Reasons that count as "destruction" and fire onDestroy triggers. "tribute"
-- and "cost" only send the card to GY (per PSCT, tribute is not destruction).
DESTROY_REASONS={battle=true,effect=true,rule=true}

-- Queue a card's onDestroy trigger (only for DESTROY_REASONS reasons).
-- Called by the card-movement helpers in ygo_state; flushTriggers drains it.
function queueTrigger(card,plr,reason)
 if not DESTROY_REASONS[reason] then return end
 G.triggerQueue=G.triggerQueue or {}
 table.insert(G.triggerQueue,{card=card,plr=plr,reason=reason})
end

function flushTriggers()
 if not G.triggerQueue or #G.triggerQueue==0 then checkEquips() return end
 local t=G.triggerQueue; G.triggerQueue={}
 deferEffects(t)
 checkEquips()
end

-- Adds a 25-frame wait anim that fires monster onDestroy effects after destroy flashes finish.
-- Only added when there are effects to trigger (avoids unnecessary input blocking).
function deferEffects(triggered)
 if #triggered==0 then return end
 addAnim(25,function()end,function()
  for _,e in ipairs(triggered) do fireMonHook(e.card,"onDestroy",e.plr) end
  checkEquips()
 end)
end

function animSpellActivation(col,zy,card,plr)
 local zx=zoneXY(plr,"st",col)
 local sc=card.cat=="spell" and CSP or CTR
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,zy,ZW_MAIN,ZH,sc); rectb(zx,zy,ZW_MAIN,ZH,CT) end
 end,function()
  card.facedown=false
  if not G.chain then
   openChain({event="spell_activation",ctx={source=card,controller=plr}},"spell")
  end
  pushChainLink(makeSpellTrapLink(card,plr,"st",plr,col,nil))
  advanceChain()
 end)
end

-- Field-spell activation: the card already sits face-up in G.fs[plr]; flash
-- the FS zone, then push the chain link (sourceLoc zone="fs").
function animFieldSpellActivation(card,plr)
 local zx,zy=zoneXY(plr,"fs")
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,zy,ZW_SPEC,ZH,CSP); rectb(zx,zy,ZW_SPEC,ZH,CT) end
 end,function()
  card.facedown=false
  if not G.chain then
   openChain({event="spell_activation",ctx={source=card,controller=plr}},"spell")
  end
  pushChainLink(makeSpellTrapLink(card,plr,"fs",plr,nil,nil))
  advanceChain()
 end)
end

-- Returns sprId, flip, rotate for an 8-direction sword.
-- Sprite 2 points UP at flip=0; flip=2 (vert) makes it point DOWN.
-- Sprite 4 points UP-RIGHT at flip=0; flip mirrors into other diagonal corners.
function swordParams(dx,dy)
 local adx,ady=math.abs(dx),math.abs(dy)
 if adx<ady*0.414 then   -- cardinal vertical (same column)
  return 2, dy>0 and 2 or 0, 0
 else                     -- diagonal (different column; horizontal never occurs here)
  local fl
  if     dx>=0 and dy<=0 then fl=0   -- ↗ player attacks right col
  elseif dx<0  and dy<=0 then fl=1   -- ↖ player attacks left col
  elseif dx>=0 and dy>0  then fl=2   -- ↘ AI attacks right col
  else                         fl=3  -- ↙ AI attacks left col
  end
  return 4,fl,0
 end
end

