-- [ygo_activation] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- TRAP & SPELL ACTIVATION
-- ============================================================
-- Flip-up animation for an AI trap in G.st[2][stCol]. After animation, pushes
-- a chain link whose resolveFn is `resolveFn` (the trap-specific resolution).
-- Source disposal (GY for normal, face-up for continuous) is handled by
-- spendChainLink at chain resolve time.
function activateAITrapAnim(stCol,card,resolveFn)
 card.facedown=false
 local zx=COL[4-stCol]
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,OY_S,ZW_MAIN,ZH,CTR); rectb(zx,OY_S,ZW_MAIN,ZH,CT) end
 end,function()
  if not G.chain then openChain(nil,"trap") end
  pushChainLink({
   source=card, controller=2, speed=chainSpeed(card),
   sourceLoc={zone="st",plr=2,col=stCol}, targets=nil,
   resolveFn=resolveFn,
  })
  advanceChain()
 end)
end

-- Open a chain window for a player action that the AI may respond to. If AI
-- has a chainable response, opens chain and drives it (animation will resume
-- the chain asynchronously). After chain resolves, runs onResolved.
-- Returns true if a chain was opened (caller should NOT immediately proceed
-- with the original action; the continuation will), false if AI had no
-- response and the caller should proceed inline.
function checkAITraps(event,ctx,onResolved)
 if ctx then ctx.actor=1 end  -- player performed the action
 if not aiHasChainableResponse(event,ctx) then return false end
 openChain({event=event,ctx=ctx,onResolved=onResolved},"event")
 G.chain.offering=2  -- AI gets first chance to respond
 advanceChain()
 return true
end

-- Flip-up animation for a player trap. After animation, pushes a chain link
-- whose resolveFn is `resolveFn`. Source disposal (GY for normal, face-up for
-- continuous) is handled by spendChainLink at chain resolve time.
function activateTrapAnim(col,card,resolveFn)
 card.facedown=false
 local zx=COL[col]
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,PY_S,ZW_MAIN,ZH,CTR); rectb(zx,PY_S,ZW_MAIN,ZH,CT) end
 end,function()
  if not G.chain then openChain(nil,"trap") end
  pushChainLink({
   source=card, controller=1, speed=chainSpeed(card),
   sourceLoc={zone="st",plr=1,col=col}, targets=nil,
   resolveFn=resolveFn,
  })
  advanceChain()
 end)
end

-- True if the player has a face-down trap that can chain to (event,ctx).
function hasActivatableTrap(event,ctx)
 for i=1,3 do if trapCanRespond(G.st[1][i],event,ctx,1) then return true end end
 return false
end

-- Called from inside trap onYes/resolveFn callbacks. During chain resolution
-- (G.chainResolving=true), do nothing — advanceChain owns flow control now and
-- will prompt or resolve based on remaining responses after each link.
function returnToTrapSelect()
 if not G.trapSelect then return end
 if G.chainResolving then return end
 -- Legacy fallback for any path that bypasses the chain. Shouldn't normally
 -- be reached now that checkTraps always opens a chain.
 if hasActivatableTrap(G.trapSelect.event,G.trapSelect.ctx) then
  G.mode="opp_trap_select"
  positionTrapSelectCursor()
 else
  finishTrapSelect()
 end
end

-- Clean up trap-select UI state. The continuation (ctx.proceed/doAttack) is
-- run from resolveChain via chain.trigger.onResolved, not here.
function finishTrapSelect()
 G.mode="free"
 G.trapSelect=nil
end

function checkTraps(event,ctx)
 if ctx then ctx.actor=2 end  -- AI performed the action
 if not hasActivatableTrap(event,ctx) then return false end
 -- Open a chain window with the caller's continuation; chain.trigger.onResolved
 -- runs after both players pass (and the chain has fully resolved LIFO).
 local cont=ctx and (ctx.doAttack or ctx.proceed)
 openChain({event=event,ctx=ctx,onResolved=cont},"event")
 G.chain.offering=1  -- player gets first chance to respond
 G.trapSelect={event=event,ctx=ctx,consumed=false}
 G.mode="opp_trap_select"
 positionTrapSelectCursor()
 return true
end

-- Bounce back to the opp_trap_select UI when an activation aborts (e.g. picker
-- found no valid target). Re-snaps cursor to a valid trap; falls back to "free"
-- mode if no chain response window is active.
local function abortToTrapSelect()
 if G.trapSelect then
  G.mode="opp_trap_select"; positionTrapSelectCursor()
 else
  G.mode="free"
 end
end

-- Push a chain link for an activation. Handles the three flow variants so the
-- per-card pickers don't repeat the anim + chain-link-push boilerplate.
--   zone="st", cat="trap"   -> activateTrapAnim
--   zone="st", cat="spell"  -> animSpellActivationCustom (card already in zone)
--   zone="hand", cat="spell"-> place in first free S/T (or push from hand to GY)
function pushActivationLink(opts,resolveFn)
 local card,col,zone = opts.card, opts.col, opts.zone
 local plr = opts.plr or 1
 if zone=="hand" and card.cat=="spell" then
  local stCol=firstEmpty(G.st[plr])
  if stCol then
   G.st[plr][stCol]=card; card.facedown=false
   for i,h in ipairs(G.hand[plr]) do
    if h==card then table.remove(G.hand[plr],i); break end
   end
   local _,sy=zoneXY(plr,"st")
   animSpellActivationCustom(stCol,sy,card,plr,resolveFn)
  else
   addToGY(plr,card,"effect")
   if not G.chain then
    openChain({event="spell_activation",ctx={source=card,controller=plr}},"spell")
   end
   pushChainLink({source=card,controller=plr,speed=chainSpeed(card),
    sourceLoc=nil,targets=opts.targets,resolveFn=resolveFn})
   advanceChain()
  end
 elseif card.cat=="trap" then
  activateTrapAnim(col,card,resolveFn)
 else
  local _,sy=zoneXY(plr,"st")
  animSpellActivationCustom(col,sy,card,plr,resolveFn)
 end
end

-- Build a sel_deck item list of the monster cards in graveyard(s). `plr` = 1
-- or 2 for one GY, or nil for both. Each item carries gyPlr/gyIdx, plus
-- deckIdx (an alias of gyIdx) for single-GY callbacks that take the raw index.
function gyMonsterItems(plr)
 local items={}
 for p=(plr or 1),(plr or 2) do
  for i,c in ipairs(G.gy[p]) do
   if c.cat=="monster" then
    table.insert(items,{gyPlr=p,gyIdx=i,deckIdx=i,
     name=c.name,atk=c.atk,def=c.def,lvl=c.lvl,desc=c.desc})
   end
  end
 end
 return items
end

-- Call of the Haunted: pick a GY monster, then push the chain link with the
-- pre-captured target index. Picking happens at activation time (TCG-correct)
-- so chain resolution stays synchronous (no UI mid-resolve).
function pickCallHauntedTargetThenActivate(col,card,ctx)
 local items=gyMonsterItems(1)
 if #items==0 then abortToTrapSelect(); return end
 G.mode="sel_deck"
 G.deckSel={items=items,sel=1,title="CALL OF THE HAUNTED",
  onPick=function(gyIdx)
   pushActivationLink({card=card,col=col,zone="st",plr=1},function()
    local emptyCol=firstEmpty(G.mon[1])
    local m=emptyCol and G.gy[1][gyIdx]
    if not (emptyCol and m and m.cat=="monster") then return end
    table.remove(G.gy[1],gyIdx)
    m.pos=1; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
    G.mon[1][emptyCol]=m
    card.linkedMon=m; m.linkedTrap=card
    fireSummonHook(m,1)
   end)
  end}
end

-- Magic Jammer: pay the discard cost at activation, then push a link that
-- negates the chain link directly below it (the spell being responded to).
function pickJammerCostThenActivate(col,card,ctx)
 if #G.hand[1]==0 then abortToTrapSelect(); return end
 G.mode="sel_discard"
 G.discardSel={title="MAGIC JAMMER COST",prompt="Pick a card to discard",
  onPick=function(handIdx)
   discardFromHand(1,handIdx,"cost")
   pushActivationLink({card=card,col=col,zone="st",plr=1},function(self)
    local links=G.chain.links
    for i=#links,1,-1 do
     if links[i]==self then
      if i<=1 then return end
      local target=links[i-1]
      target.negated=true
      local loc=target.sourceLoc
      if loc and loc.zone=="st" then revealAndDestroyST(loc.plr,loc.col)
      elseif loc and loc.zone=="fs" then sendFieldSpellToGY(loc.plr,"effect") end
      return
     end
    end
   end)
  end}
 G.cur={side=1,row=3,col=0}  -- cursor onto hand
end

-- Ordered list of valid MST targets: every S/T card plus either player's field
-- spell, excluding the MST card itself. Each entry carries the screen cursor
-- position (side,row,vcol) and the data locator (kind "st"/"fs", di).
function mstTargets(source)
 local list={}
 for vc=1,3 do
  if G.st[1][vc] and G.st[1][vc]~=source then
   table.insert(list,{side=1,row=2,vcol=vc,kind="st",di=vc})
  end
 end
 if G.fs[1] and G.fs[1]~=source then
  table.insert(list,{side=1,row=1,vcol=0,kind="fs",di=1})
 end
 for vc=1,3 do
  local di=4-vc
  if G.st[2][di] and G.st[2][di]~=source then
   table.insert(list,{side=2,row=2,vcol=vc,kind="st",di=di})
  end
 end
 if G.fs[2] and G.fs[2]~=source then
  table.insert(list,{side=2,row=1,vcol=4,kind="fs",di=2})
 end
 return list
end

-- MST: pick a face-up/face-down S/T card or a field spell, then push the link.
-- zone="st" if activating from field, "hand" if from hand (quick-play).
function pickMSTTargetThenActivate(col,card,ctx,zone)
 local tgts=mstTargets(card)
 if #tgts==0 then
  if zone=="hand" then G.mode="free" else abortToTrapSelect() end
  return
 end
 G.mode="sel_st_target"
 G.stTargetSel={title=(zone=="hand") and "MST" or "MST (CHAINED)",
  source=card,zone=zone,col=col,idx=1,
  onPick=function(targetPlr,kind,targetDi)
   pushActivationLink({card=card,col=col,zone=zone,plr=1,
                        targets={plr=targetPlr,kind=kind,col=targetDi}},function()
    if kind=="fs" then
     if G.fs[targetPlr] then sendFieldSpellToGY(targetPlr,"effect") end
    elseif G.st[targetPlr][targetDi] then
     revealAndDestroyST(targetPlr,targetDi)
    end
   end)
  end}
 local t=tgts[1]
 G.cur={side=t.side,row=t.row,col=t.vcol}
end

-- Thousand Knives: pick 1 opponent monster, then push the chain link with the
-- pre-captured target (picking at activation keeps chain resolution synchronous).
function pickThousandKnivesTarget(col,card,zone)
 if not hasMonsters(2) then G.mode="free"; return end
 G.mode="sel_destroy"
 G.destroySel={side=2,onPick=function(tp,ti)
  pushActivationLink({card=card,col=col,zone=zone,plr=1},function()
   if G.mon[tp][ti] then revealAndDestroyMon(tp,ti,"effect"); flushTriggers() end
  end)
 end}
 G.cur={side=2,row=1,col=4-(firstOccupied(G.mon[2]) or 1)}
end

-- Monster Reborn: pick 1 monster from either GY, then push the chain link.
function pickMonsterRebornTarget(col,card,zone)
 local items=gyMonsterItems()
 if #items==0 then G.mode="free"; return end
 G.mode="sel_deck"
 G.deckSel={items=items,sel=1,title="MONSTER REBORN",
  onPick=function(_,item)
   -- Monster picked; now choose a battle position. The forced menu cannot be
   -- B-cancelled (the card is already committed to the S/T zone).
   G.rebornSel={col=col,card=card,zone=zone,gyPlr=item.gyPlr,gyIdx=item.gyIdx}
   G.menu={open=true,sel=1,forced=true,items={
    {"ATK POSITION","reborn_atk"},
    {"DEF POSITION","reborn_def"},
   }}
  end}
end

-- Variant of animSpellActivation that uses a custom resolveFn (for targeting
-- spells like MST). Identical animation/flow as animSpellActivation but the
-- chain link's resolveFn is whatever the caller provides.
function animSpellActivationCustom(col,zy,card,plr,resolveFn)
 local zx=zoneXY(plr,"st",col)
 local sc=card.cat=="spell" and CSP or CTR
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,zy,ZW_MAIN,ZH,sc); rectb(zx,zy,ZW_MAIN,ZH,CT) end
 end,function()
  card.facedown=false
  if not G.chain then
   openChain({event="spell_activation",ctx={source=card,controller=plr}},"spell")
  end
  pushChainLink({
   source=card, controller=plr, speed=chainSpeed(card),
   sourceLoc={zone="st",plr=plr,col=col}, targets=nil,
   resolveFn=resolveFn,
  })
  advanceChain()
 end)
end

function handleOppTrapSelectInput()
 local ts=G.trapSelect
 -- Defensive: ensure cursor is on player's S/T row in case any prior path
 -- (picker bounce-back, special-zone col) left it elsewhere.
 G.cur.side=1; G.cur.row=2
 if G.cur.col<1 then G.cur.col=1 elseif G.cur.col>3 then G.cur.col=3 end
 if btnp(2) then G.cur.col=math.max(1,G.cur.col-1)
 elseif btnp(3) then G.cur.col=math.min(3,G.cur.col+1)
 elseif btnp(4) then
  local col=G.cur.col
  local card=G.st[1][col]
  if trapCanRespond(card,ts.event,ts.ctx) then
   G.mode="free"
   local b=behaviorOf(card)
   if b and b.activate then
    b.activate{col=col,card=card,zone="st",plr=1,trigCtx=ts.ctx}
   else
    activateTrapAnim(col,card,function() applyResolve(card,1,ts.ctx) end)
   end
  end
 elseif btnp(5) then
  -- Player passes priority. If a chain is open, advance it (may resolve, may
  -- pass to AI then prompt player again — keep G.trapSelect alive in case).
  if G.chain then
   passChainPriority()
   advanceChain()
   if not G.chain then finishTrapSelect() end
  else
   finishTrapSelect()
  end
 end
end

