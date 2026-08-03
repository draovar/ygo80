-- [ygo_behaviors] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- BEHAVIORS  (per-card hooks — single source of truth)
-- ============================================================
-- One entry per card `effect` key. Every per-card branch in the engine reads
-- from here. To add a new card, add a CARDS entry plus a BEHAVIORS entry —
-- never sprinkle effect names across the rest of the file.
--
-- Possible fields (all optional):
--   speed              chain speed override (else derived from cat/subtype)
--   responseOnly       true => cannot be activated from menu, only as chain response
--   listens[EVENT]     {optional, speed, when, react} -- the shape for any card
--                      that responds to a game event. See ygo_proc.lua for the
--                      8 events (PHASE/SUMMON/FLIP/ATTACK/BEFORE_DAMAGE/
--                      DESTROYED/TRIBUTED/ACTIVATE) and the coroutine protocol.
--   resolve(plr,ctx)   effect with no decisions taken at activation time; the
--                      chain link's default react. May still choose{} from
--                      inside (it runs in a coroutine frame -- see flute).
--   canActivate(card)  predicate gating manual activation from the menu
--   activate(opts)     effect with decisions taken AT activation, so the chain
--                      link can carry a target. opts = {col,card,zone,plr}.
--                      Drives choose{} for opts.plr and must never name
--                      player 1 -- the AI runs this same hook.
--   Never both: a card carrying resolve AND activate is mid-migration and the
--   AI stays on resolve (see dispatchActivate in ygo_intent.lua).
--   ai{}               NOT needed for the AI to use a card. The AI picks moves
--                      by simulating them through this same code and scoring
--                      the resulting board (ygo_sim.lua), so a card becomes
--                      AI-usable the moment it works for the player.
--                      One hook remains:
--                        scoreActivate(card,plr,ctx,event,eventCtx)
--                      Used only when the AI must answer a response window
--                      that replay cannot reproduce -- i.e. the opponent chose
--                      to chain into it. Optional; no hook = never activated
--                      on that fallback path.
--   atkBonus(card)     per-card ATK bonus (Dark Magician Girl, Buster Blader)
--   defBonus(card)     per-card DEF bonus (Gravekeeper's Shaman)
--   equipBonus(tgt,eq) per-equip stat bonus -> ab,db
--   tributeValue(m,summonCard) -> int|nil  overrides a monster's tribute worth;
--                      hook on the tributed monster (Double Coston) or on the
--                      summon card (Gravekeeper's Oracle). nil = no override.
--   static{flag=...}   continuous ("always-on") capabilities granted while the
--                      card is face-up on the field. Queried by staticActive.
--                      Flags: blocksTraps, blocksAttack, gravityBind,
--                      blocksFieldSpells, necrovalley, blocksGYMoves.
--   onNegate(card,p,c) trap-only. Fires when Jinzo enters and negates a face-up
--                      trap. Use to tear down lingering state (CoH's anchor).
--   onResume(card,p,c) trap-only. Fires when Jinzo leaves and a face-up trap's
--                      effect resumes. Use to self-destruct if precondition gone.

-- ============================================================
-- BEHAVIOR HELPERS  (data utilities used by per-card hooks below)
-- ============================================================
-- Build a sel_deck item list of the monster cards in graveyard(s). `plr` = 1
-- or 2 for one GY, or nil for both. Each item carries gyPlr/gyIdx + deckIdx
-- (an alias of gyIdx) for single-GY callbacks that take the raw index.
-- Used by monsterreborn (cross-GY) and any future GY-picking card.
function gyMonsterItems(plr)
 local items={}
 for p=(plr or 1),(plr or 2) do
  for i,c in ipairs(G.gy[p]) do
   if c.cat=="monster" then
    table.insert(items,{gyPlr=p,gyIdx=i,deckIdx=i,card=c,
     name=c.name,atk=c.atk,def=c.def,lvl=c.lvl,desc=c.desc})
   end
  end
 end
 return items
end

-- Fire BEHAVIORS.onNegate / onResume on every face-up trap. Used when Jinzo
-- enters or leaves; continuous traps with lingering state (CoH's linkedMon)
-- implement these hooks. Pure-static traps (Gravity Bind) need neither.
function sweepTrapHook(name)
 for p=1,2 do for c=1,3 do
  local t=G.st[p][c]
  if t and t.cat=="trap" and not t.facedown then
   local b=BEHAVIORS[t.effect]
   if b and b[name] then b[name](t,p,c) end
  end
 end end
end

-- Quick-play / generic-response listener helper. Builds a single shared
-- `entry` and registers it for all 4 opp-action events (SUMMON/FLIP/ATTACK/
-- ACTIVATE) — the pattern used by Enemy Controller, Ring of Destruction, MST,
-- Graceful Dice. Each card still defines its own `when` (typically checking
-- G.active==opp + per-card validity).
function quickPlayListens(entry)
 return {SUMMON=entry,FLIP=entry,ATTACK=entry,ACTIVATE=entry}
end

-- Toggle ATK <-> DEF position and mark posChanged (blocks the once-per-turn
-- CHANGE_POS intent the same turn). Used by Enemy Controller, Gravekeeper's
-- Assailant. No effect on facedown monsters — callers should gate face-down
-- via flipEvent path instead.
function togglePosition(m)
 m.pos=(m.pos==1) and 2 or 1
 m.posChanged=true
end

-- Boolean variant of mstTargets — early-exits on the first valid S/T or FS
-- target excluding `source`. Cheaper than building the full target list when
-- only a yes/no answer is needed (MST listener `when`, etc.).
function mstHasTarget(source)
 for p=1,2 do
  for c=1,3 do
   if G.st[p][c] and G.st[p][c]~=source then return true end
  end
  if G.fs[p] and G.fs[p]~=source then return true end
 end
 return false
end

-- Shared AI policy for "bounce/destroy one monster, prefer opp's strongest,
-- fall back to own weakest targetable". Used by Maneater Bug and GK Guard.
-- score(m) defaults to facedown=3000 (speculative) else (pos==1) atk else def.
function aiPickBounceTarget(selfPlr,opp,scoreFn)
 scoreFn=scoreFn or function(m)
  return m.facedown and 3000 or ((m.pos==1) and (m.atk or 0) or (m.def or 0))
 end
 local best,bestK=-1,nil
 for c=1,3 do
  local m=G.mon[opp][c]
  if m and canTargetMon(m) then
   local s=scoreFn(m)
   if s>best then best=s; bestK={plr=opp,col=c} end
  end
 end
 if bestK then return bestK end
 for c=1,3 do
  if canTargetMon(G.mon[selfPlr][c]) then return {plr=selfPlr,col=c} end
 end
end

BEHAVIORS={
 -- =============== SPELLS ===============
 darkhole={
  resolve=function(plr)
   for i=1,3 do for p=1,2 do
    if G.mon[p][i] then revealAndDestroyMon(p,i,"effect") end
   end end
   checkEquips()
  end,
 },
 raigeki={
  resolve=function(plr)
   local opp=3-plr
   for i=1,3 do
    if G.mon[opp][i] then revealAndDestroyMon(opp,i,"effect") end
   end
   checkEquips()
  end,
 },
 fissure={
  canActivate=function(card,plr) return hasTargetableMon(3-(plr or 1)) end,
  resolve=function(plr)
   local opp=3-plr
   local low,lowI=math.huge,nil
   for i=1,3 do
    local m=G.mon[opp][i]
    if m and not m.facedown and canTargetMon(m) and m.atk<low then
     low=m.atk; lowI=i
    end
   end
   if lowI then sendMonsterToGY(opp,lowI,"effect"); checkEquips() end
  end,
 },
 ookazi={
  resolve=function(plr) changeLp(3-plr,-800) end,
 },
 unitedwestand={
  -- Equip Spell. Activation handled by sel_equip flow; bonus computed here.
  equipBonus=function(target,equip)
   local tp=equip.equippedTo.plr
   local n=0
   for i=1,3 do if G.mon[tp][i] and not G.mon[tp][i].facedown then n=n+1 end end
   return n*800,n*800
  end,
 },
 mst=(function()
  -- Quick-Play. Player manual cast OR set face-down + chained response on
  -- opp's turn. AI casts via ai.scoreCast (uses field state) when own turn.
  local function applyDestroy(tplr,kind,di,actor)
   if kind=="fs" then
    if G.fs[tplr] then sendFieldSpellToGY(tplr,"effect",actor) end
   elseif G.st[tplr][di] then revealAndDestroyST(tplr,di) end
   end
  local function mstWhen(self,ctx)
   return G.active==(3-self.plr) and mstHasTarget(self.card)
  end
  local function mstReact(self,ctx)
   local ans=choose{kind="st_or_fs",plr=self.plr,source=self.card,title="MST (CHAINED)"}
   if not ans then return end
   applyDestroy(ans.plr,ans.kind,ans.col,self.plr)
  end
  return {
   canActivate=function(card,plr) return mstHasTarget(card) end,
   activate=function(opts)
    local card,col,zone=opts.card,opts.col,opts.zone
    local plr=opts.plr or 1
    procPushFrame(function()
     local ans=choose{kind="st_or_fs",plr=plr,source=card,
      title=(zone=="hand") and "MST" or "MST (CHAINED)"}
     if not ans then return end
     pushActivationLink({card=card,col=col,zone=zone,plr=plr},function()
      applyDestroy(ans.plr,ans.kind,ans.col,plr)
     end)
    end)
   end,
   listens=quickPlayListens{optional=true,speed=2,when=mstWhen,react=mstReact},
   ai={
    scoreActivate=function(card,plr,ctx,event,eventCtx)
     local oppSt=0
     for c=1,3 do if G.st[3-plr][c] then oppSt=oppSt+1 end end
     return 100+oppSt*80+(G.fs[3-plr] and 100 or 0)
    end,
   },
  }
 end)(),
 stampingdestruction={
  canActivate=function(card,plr) return controlsDragon(plr or 1) and mstHasTarget(card) end,
  activate=function(opts)
   local card,col,zone=opts.card,opts.col,opts.zone
   local plr=opts.plr or 1
   procPushFrame(function()
    local ans=choose{kind="st_or_fs",plr=plr,source=card,
     title="STAMPING DESTRUCTION"}
    if not ans then return end
    pushActivationLink({card=card,col=col,zone=zone,plr=plr},function()
     if ans.kind=="fs" then
      if G.fs[ans.plr] then
       sendFieldSpellToGY(ans.plr,"effect",plr); changeLp(ans.plr,-500)
      end
     elseif G.st[ans.plr][ans.col] then
      revealAndDestroyST(ans.plr,ans.col); changeLp(ans.plr,-500)
     end
    end)
   end)
  end,
 },
 potofgreed={
  canActivate=function(card,plr) plr=plr or 1; return #G.deck[plr]>0 and #G.hand[plr]<MAX_HAND end,
  resolve=function(plr) drawCard(plr); drawCard(plr) end,
 },
 gracefuldice=(function()
  -- Quick-Play. Roll d6, add result*100 to own face-up monsters' ATK/DEF
  -- (turn-scoped). Player activates via menu (own turn) OR via response
  -- window during opp's action (set face-down quick-play timing).
  local function applyBuff(plr)
   local r=choose{kind="dice"}
   if not r then return end
   local boost=r*100
   for c=1,3 do
    local m=G.mon[plr][c]
    if m and not m.facedown then
     addTurnMod(m,"atk",boost); addTurnMod(m,"def",boost)
    end
   end
  end
  local function gdWhen(self,ctx)
   return G.active==(3-self.plr) and hasMonsters(self.plr)
  end
  return {
   canActivate=function(card,plr) return hasMonsters(plr or 1) end,
   resolve=function(plr) applyBuff(plr) end,
   listens=quickPlayListens{optional=true,speed=2,when=gdWhen,
    react=function(self,ctx) applyBuff(self.plr) end},
   ai={
    scoreActivate=function(card,plr,ctx,event,eventCtx)
     return ctx.ownFaceUp>0 and 250 or 0
    end,
   },
  }
 end)(),
 enemycontroller=(function()
  -- Quick-Play. Two activation paths share the picker/applier helpers:
  --   * activate(opts) - manual cast on own turn, either player. Pre-picks +
  --     procActivate with target on link (lets Dark Illusion negate).
  --   * listens entry - set face-down EC offered as a response during any opp
  --     action on opp's turn (SUMMON/FLIP/ATTACK/ACTIVATE). Chains at SS2; on
  --     opp's attack, flipping the attacker to DEF cancels via DECLARE_ATTACK's
  --     `attacker.pos~=1` re-check. Listener chain link has target=nil (picked
  --     in react), so Dark Illusion can't negate this path.
  local function ecPick(plr)
   local opp=3-plr
   local items={{"CHANGE POS","pos"}}
   if hasMonsters(plr) then items[#items+1]={"TAKE CONTROL","control"} end
   local effect=choose{kind="menu",plr=plr,forced=true,items=items}
   if not effect then return nil end
   if effect=="pos" then
    local target=choose{
     kind="zone",plr=plr,side=opp,row="mon",title="EC: CHANGE POS",
     filter=function(c) return c and not c.facedown end,
    }
    if not target then return nil end
    local targetCard=G.mon[target.plr][target.col]
    if not targetCard or targetCard.facedown then return nil end
    return effect,{targetPlr=target.plr,targetCol=target.col,targetCard=targetCard}
   else
    local trib=choose{
     kind="zone",plr=plr,side=plr,row="mon",title="EC: TRIBUTE",
     filter=function(c) return c~=nil end,
    }
    if not trib then return nil end
    local target=choose{
     kind="zone",plr=plr,side=opp,row="mon",title="EC: TAKE CONTROL",
     filter=function(c) return c and not c.facedown end,
    }
    if not target then return nil end
    local targetCard=G.mon[opp][target.col]
    if not targetCard or targetCard.facedown then return nil end
    return effect,{tribCol=trib.col,targetCol=target.col,targetCard=targetCard}
   end
  end
  local function ecApply(plr,effect,p)
   local opp=3-plr
   if effect=="pos" then
    local m=G.mon[p.targetPlr] and G.mon[p.targetPlr][p.targetCol]
    if m==p.targetCard and not m.facedown then togglePosition(m) end
   else
    local tribCard=G.mon[plr][p.tribCol]
    if tribCard then
     sendMonsterToGY(plr,p.tribCol,"tribute")
     raise(EV_TRIBUTED,{card=tribCard,plr=plr,actor=plr})
    end
    local m=G.mon[opp][p.targetCol]
    if m==p.targetCard and not m.facedown then
     G.mon[opp][p.targetCol]=nil
     local landCol=firstEmpty(G.mon[plr])
     if not landCol then table.insert(G.gy[opp],m); return end
     m.borrowedFrom=opp; m.borrowedAtTurn=G.turn
     G.mon[plr][landCol]=m
    end
   end
  end
  local function ecWhen(self,ctx)
   local opp=3-self.plr
   return G.active==opp and hasFaceUpMonster(opp)
  end
  -- targetPick runs at activation (before link push) so link.target carries
  -- the picked monster → Dark Illusion can negate when targeting a DARK mon.
  local function ecTargetPick(self,ctx)
   local effect,p=ecPick(self.plr)
   if not effect then return nil end
   return {target=p.targetCard,params={effect=effect,p=p}}
  end
  local function ecReact(self,ctx,params) ecApply(self.plr,params.effect,params.p) end
  return {
   canActivate=function(card,plr) return hasFaceUpMonster(3-(plr or 1)) end,
   activate=function(opts)
    local card,col,zone=opts.card,opts.col,opts.zone
    local plr=opts.plr or 1
    procPushFrame(function()
     local effect,p=ecPick(plr)
     if not effect then return end
     procActivate(card,plr,zone,col,function()
      ecApply(plr,effect,p)
     end,p.targetCard)
    end)
   end,
   listens=quickPlayListens{optional=true,speed=2,when=ecWhen,
    targetPick=ecTargetPick,react=ecReact},
   ai={
    scoreActivate=function(card,plr,ctx,event,eventCtx)
     local bestSave=0
     for _,o in ipairs(ctx.oppMons) do
      local m=o.card
      if not m.facedown and m.pos==1 then
       local save=(getMonAtk(m) or 0)-(getMonDef(m) or 0)
       if save>bestSave then bestSave=save end
      end
     end
     return 150+bestSave/4
    end,
   },
  }
 end)(),
 gianttrunade={
  resolve=function(plr,ctx)
   local self_card=ctx and ctx.source
   for p=1,2 do
    for c=1,3 do
     if G.st[p][c] and G.st[p][c]~=self_card then returnSTToHand(p,c) end
    end
    returnFSToHand(p)
   end
   checkEquips()
  end,
 },
 straylambs={
  -- Requires 2 empty monster zones (per real card).
  canActivate=function(card,plr)
   plr=plr or 1
   local n=0; for c=1,3 do if not G.mon[plr][c] then n=n+1 end end
   return n>=2
  end,
  resolve=function(plr)
   for _=1,2 do
    local col=firstEmpty(G.mon[plr])
    if not col then return end
    local tok=makeToken("Lamb Token","beast","earth",1,0,0,390)
    tok.pos=2
    G.mon[plr][col]=tok
    summonEvent(tok,plr,col,"special",nil)
   end
  end,
 },
 costdown={
  canActivate=function(card,plr)
   plr=plr or 1
   if #G.hand[plr]<2 then return false end
   for _,c in ipairs(G.hand[plr]) do
    if c.cat=="monster" and tribsNeeded(getMonLvl(c)-2)<tribsNeeded(getMonLvl(c)) then
     return true
    end
   end
   return false
  end,
  resolve=function(plr)
   if #G.hand[plr]==0 then return end
   local ans=choose{
    kind="card",plr=plr,from="hand",title="COST DOWN: DISCARD",
    aiPick=function(req)
     for i,c in ipairs(G.hand[req.plr]) do
      if c.cat~="monster" then return {idx=i} end
     end
     local lowI,lowAtk=nil,math.huge
     for i,c in ipairs(G.hand[req.plr]) do
      if (c.atk or 0)<lowAtk then lowAtk=c.atk; lowI=i end
     end
     return lowI and {idx=lowI} or nil
    end,
   }
   if not ans then return end
   discardFromHand(plr,ans.idx,"cost")
   for _,c in ipairs(G.hand[plr]) do
    if c.cat=="monster" then addTurnMod(c,"lvl",-2) end
   end
  end,
 },
 swords={
  static={blocksAttack=true},
  resolve=function(plr,ctx)
   if ctx and ctx.source then ctx.source.swordsCounter=3 end
  end,
 },
 thousandknives={
  canActivate=function(card,plr) plr=plr or 1; return controlsDarkMagician(plr) and hasTargetableMon(3-plr) end,
  activate=function(opts)
   local card,col,zone=opts.card,opts.col,opts.zone
   local plr=opts.plr or 1
   local opp=3-plr
   if not hasTargetableMon(opp) then return end
   procPushFrame(function()
    local target=choose{
     kind="zone",plr=plr,side=opp,row="mon",title="THOUSAND KNIVES",
     filter=function(c) return canTargetMon(c) end,
     -- Default zone policy scores raw ATK; face-down/DEF monsters need
     -- their DEF weighed instead.
     aiPick=function(req)
      local best,bestK=-1,nil
      for c=1,3 do
       local m=G.mon[opp][c]
       if m and canTargetMon(m) then
        local s=(m.pos==1 and not m.facedown) and m.atk or m.def
        if s>best then best=s; bestK={plr=opp,col=c} end
       end
      end
      return bestK
     end,
    }
    if not target then return end
    local targetCard=G.mon[target.plr][target.col]
    procActivate(card,plr,zone,col,function()
     if G.mon[target.plr][target.col]==targetCard then
      revealAndDestroyMon(target.plr,target.col,"effect"); checkEquips()
     end
    end,targetCard)
   end)
  end,
 },
 monsterreborn={
  canActivate=function(card,plr) plr=plr or 1; return firstEmpty(G.mon[plr]) and anyGYMonster() and not staticActive("blocksGYMoves") end,
  activate=function(opts)
   local card,col,zone=opts.card,opts.col,opts.zone
   local plr=opts.plr or 1
   procPushFrame(function()
    local items=gyMonsterItems()
    if #items==0 then return end
    local ans=choose{kind="card",plr=plr,items=items,title="MONSTER REBORN"}
    if not ans then return end
    local gyPlr,gyIdx=ans.item.gyPlr,ans.item.gyIdx
    local key=choose{
     kind="menu",plr=plr,forced=true,
     items={{"ATK POSITION","ss_atk"},{"DEF POSITION","ss_def"}},
    }
    local pos=(key=="ss_def") and 2 or 1
    procActivate(card,plr,zone,col,function()
     -- Re-checked here: a Necrovalley chained to this can lock the GY
     -- between the pick and the summon.
     if staticActive("blocksGYMoves") then return end
     local emptyCol=firstEmpty(G.mon[plr])
     local m=emptyCol and G.gy[gyPlr][gyIdx]
     if not (emptyCol and m and m.cat=="monster") then return end
     table.remove(G.gy[gyPlr],gyIdx)
     m.pos=pos; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
     m.linkedTrap=nil
     G.mon[plr][emptyCol]=m
     summonEvent(m,plr,emptyCol,"special",nil)
    end)
   end)
  end,
 },
 polymerization={
  canActivate=function(card,plr) plr=plr or 1; return firstEmpty(G.mon[plr]) and #polyValidTargets(plr)>0 end,
  activate=function(opts)
   local card,col,zone=opts.card,opts.col,opts.zone
   local plr=opts.plr or 1
   procPushFrame(function()
    -- 1) Pick the fusion target from valid ED entries.
    local targets=polyValidTargets(plr)
    if #targets==0 then return end
    local fItems={}
    for _,idx in ipairs(targets) do
     local c=G.extra[plr][idx]
     fItems[#fItems+1]={extraIdx=idx,card=c,name=c.name,atk=c.atk,def=c.def,lvl=c.lvl,desc=c.desc}
    end
    local fAns=choose{kind="card",plr=plr,items=fItems,title="POLYMERIZATION"}
    if not fAns then return end
    local fusionIdx=fAns.item.extraIdx
    local fusionCard=G.extra[plr][fusionIdx]
    -- 2) Pick each material in turn. Track consumed copies so duplicates can't
    --    be selected twice (e.g. for hypothetical "X+X" fusions).
    local picks={}
    local consumed={hand={},field={}}
    for _,matName in ipairs(fusionCard.materials) do
     local mItems={}
     for hi,c in ipairs(G.hand[plr]) do
      if c.id==matName and not consumed.hand[hi] then
       mItems[#mItems+1]={kind="hand",hi=hi,card=c,
        name=c.name.." (H)",atk=c.atk,def=c.def,lvl=c.lvl,desc=c.desc}
      end
     end
     for fc=1,3 do
      local m=G.mon[plr][fc]
      if m and m.id==matName and not consumed.field[fc] then
       local tag=m.facedown and (" (F"..fc.." SET)") or (" (F"..fc..")")
       mItems[#mItems+1]={kind="field",fc=fc,card=m,
        name=m.name..tag,atk=m.atk,def=m.def,lvl=m.lvl,desc=m.desc}
      end
     end
     if #mItems==0 then return end
     local mAns=choose{kind="card",plr=plr,items=mItems,
      title="POLY MATERIAL: "..(CARDS[matName] and CARDS[matName].name:upper() or matName:upper()),
      -- Prefer a hand copy over a field copy: spending the board costs more.
      aiPick=function(req)
       for _,it in ipairs(req.items) do
        if it.kind=="hand" then return {idx=it.deckIdx,item=it} end
       end
       return {idx=req.items[1].deckIdx,item=req.items[1]}
      end}
     if not mAns then return end
     picks[#picks+1]={kind=mAns.item.kind,hi=mAns.item.hi,fc=mAns.item.fc}
     if mAns.item.kind=="hand" then consumed.hand[mAns.item.hi]=true
     else consumed.field[mAns.item.fc]=true end
    end
    -- 3) Pick position. (The land zone is auto-picked via firstEmpty at resolve
    --    time -- the existing kind="zone" CHOOSE bridge uses the sel_destroy UI,
    --    which only allows picking cards-on-field, not empty zones. Matches the
    --    convention used by Monster Reborn / gkspy / Call of the Haunted.)
    local key=choose{kind="menu",plr=plr,forced=true,
     items={{"ATK POSITION","ss_atk"},{"DEF POSITION","ss_def"}}}
    local pos=(key=="ss_def") and 2 or 1
    -- 4) Activate the Polymerization chain link; at resolve, send materials
    --    and Special Summon the Fusion. Hand picks sorted descending so the
    --    table.remove inside discardFromHand doesn't shift earlier indices.
    --    Materials are sent FIRST so the freed field slot can host the fusion
    --    (e.g. when one of the materials came from a field zone).
    procActivate(card,plr,zone,col,function()
     -- Tribute-style sword animation over the picked materials, then send.
     playMaterialTributeAnim(plr,picks)
     local handIdxs,fieldCols={},{}
     for _,p in ipairs(picks) do
      if p.kind=="hand" then handIdxs[#handIdxs+1]=p.hi
      else fieldCols[#fieldCols+1]=p.fc end
     end
     table.sort(handIdxs,function(a,b) return a>b end)
     for _,hi in ipairs(handIdxs) do discardFromHand(plr,hi,"effect") end
     for _,fc in ipairs(fieldCols) do sendMonsterToGY(plr,fc,"effect") end
     local landCol=firstEmpty(G.mon[plr])
     if not landCol then return end
     local m=table.remove(G.extra[plr],fusionIdx)
     if not m then return end
     m.pos=pos; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
     G.mon[plr][landCol]=m
     summonEvent(m,plr,landCol,"special",nil)
    end)
   end)
  end,
 },
 fluteofdragon={
  -- Lord of D. required on field at activation AND at resolution.
  canActivate=function(card,plr)
   plr=plr or 1
   if not staticActive("dragonProtect",plr) or not firstEmpty(G.mon[plr]) then return false end
   for _,c in ipairs(G.hand[plr]) do if c.type=="dragon" then return true end end
   return false
  end,
  resolve=function(plr)
   if not staticActive("dragonProtect",plr) then return end
   for i=1,2 do
    local emptyCol=firstEmpty(G.mon[plr])
    if not emptyCol then return end
    local hasDragon=false
    for _,c in ipairs(G.hand[plr]) do
     if c.type=="dragon" then hasDragon=true; break end
    end
    if not hasDragon then return end
    local ans=choose{
     kind="card",plr=plr,from="hand",
     title="FLUTE: PICK DRAGON ("..(3-i).." LEFT)",
     filter=function(c) return c.type=="dragon" end,
    }
    if not ans then return end
    local key=choose{
     kind="menu",plr=plr,forced=true,
     items={{"ATK POSITION","atk"},{"DEF POSITION","def"}},
    }
    local pos=(key=="def") and 2 or 1
    emptyCol=firstEmpty(G.mon[plr])
    if not emptyCol then return end
    local card=table.remove(G.hand[plr],ans.idx)
    card.pos=pos; card.facedown=false; card.attacked=false
    card.summoned=false; card.posChanged=false
    G.mon[plr][emptyCol]=card
    summonEvent(card,plr,emptyCol,"special",nil)
   end
  end,
 },

 -- =============== TRAPS ===============
 mirrorforce={
  responseOnly=true,
  listens={
   ATTACK={
    optional=true,
    speed=2,
    when=function(self,ctx) return ctx.actor~=self.controller end,
    react=function(self,ctx)
     local opp=3-self.plr
     G.battleAnim=nil
     for i=1,3 do
      local m=G.mon[opp][i]
      if m and m.pos==1 and not m.facedown then sendMonsterToGY(opp,i,"effect") end
     end
    end,
   },
  },
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx)
    local opp=3-plr
    local total=0
    local score=0
    for c=1,3 do
     local m=G.mon[opp][c]
     if m and not m.facedown and m.pos==1 then
      total=total+(getMonAtk(m) or 0)
     end
    end
    score = total/10
    score = score - ctx.oppHandSize*10 
    if ctx.ownLP<=total then score=score+50 end
    return score
   end,
  },
 },
 kunaichain={
  -- Pick one or both: change attacker to DEF, and/or convert to equip on own
  -- monster (+500 ATK). subtype mutation makes spendLink keep it face-up as
  -- an equip. when() subtype="normal" guard prevents re-firing post-equip.
  responseOnly=true,
  equipBonus=function() return 500,0 end,
  listens={
   ATTACK={
    optional=true,
    speed=2,
    when=function(self,ctx)
     return self.card.subtype=="normal" and ctx.actor~=self.controller
    end,
    react=function(self,ctx)
     local hasOwn=hasFaceUpMonster(self.plr)
     local items={}
     if hasOwn then table.insert(items,{"BOTH","both"}) end
     table.insert(items,{"CHANGE POS","pos"})
     if hasOwn then table.insert(items,{"EQUIP","equip"}) end
     local key=choose{kind="menu",plr=self.plr,forced=true,items=items}
     if key=="pos" or key=="both" then
      if ctx.attacker then ctx.attacker.pos=2 end
     end
     if key=="equip" or key=="both" then
      local target=choose{
       kind="zone",plr=self.plr,side=self.plr,row="mon",
       title="KUNAI: EQUIP TARGET",
       filter=function(c) return c and not c.facedown end,
      }
      if target and G.st[self.plr][self.col]==self.card then
       self.card.subtype="equip"
       self.card.equippedTo={plr=target.plr,col=target.col}
      end
     end
    end,
   },
  },
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx)
    return getMonAtk(eventCtx.attacker) or eventCtx.attacker.atk or 0
   end,
  },
 },
 traphole={
  responseOnly=true,
  listens={
   SUMMON={
    optional=true,
    speed=2,
    when=function(self,ctx)
     return ctx.kind~="special" and not ctx.facedown
        and (ctx.card.atk or 0)>=1000
        and ctx.actor~=self.controller
        and canTargetMon(ctx.card)
    end,
    targetCard=function(self,ctx) return ctx.card end,
    react=function(self,ctx)
     if ctx.actor==self.controller then
      trace("TH REACT BAILED (actor==controller) — when() was bypassed somehow")
      return
     end
     if G.mon[ctx.plr] and G.mon[ctx.plr][ctx.col]==ctx.card then
      sendMonsterToGY(ctx.plr,ctx.col,"effect")
     end
    end,
   },
  },
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx)
    score=0
    score = eventCtx.card.atk/10 - ctx.oppHandSize*10
    if ctx.ownLP<=eventCtx.card.atk then score = score + 50 end
    return score
   end,
  },
 },
 callhaunted={
  -- Continuous Trap. Manual activate or chain-response. Both paths share
  -- cohSpecialSummon. Jinzo: onNegate kills anchor, onResume self-destructs.
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx)
    return aiBestGyMonsterAtk(plr)
   end,
  },
  onNegate=function(card)
   if not card.linkedMon then return end
   local m=card.linkedMon
   for mp=1,2 do for mc=1,3 do
    if G.mon[mp][mc]==m then sendMonsterToGY(mp,mc,"effect") end
   end end
   card.linkedMon=nil
  end,
  onResume=function(card,p,c)
   if not card.linkedMon then sendSpellTrapToGY(p,c,"rule") end
  end,
  listens={
   ATTACK={
    optional=true,
    speed=2,
    when=function(self,ctx)
     return self.card.facedown
        and ctx.actor~=self.controller and canReviveMonster(self.plr)
    end,
    react=function(self,ctx) cohSpecialSummon(self) end,
   },
   PHASE={
    optional=true,
    speed=2,
    when=function(self,ctx)
     return self.card.facedown
        and ctx.actor~=self.controller and canReviveMonster(self.plr)
    end,
    react=function(self,ctx) cohSpecialSummon(self) end,
   },
  },
  canActivate=function(card,plr) return canReviveMonster(plr or 1) end,
  activate=function(opts)
   local card,col=opts.card,opts.col
   local plr=opts.plr or 1
   procActivate(card,plr,"st",col,function()
    cohSpecialSummon{card=card,plr=plr,zone="st",col=col}
   end)
  end,
 },
 magicjammer={
  responseOnly=true,
  listens={
   ACTIVATE={
    optional=true,
    speed=3,
    when=function(self,ctx)
     return ctx.card and ctx.card.cat=="spell" and #G.hand[self.plr]>=1
    end,
    react=function(self,ctx)
     local ans=choose{kind="card",plr=self.plr,from="hand",title="MAGIC JAMMER COST"}
     if not ans then return end
     discardFromHand(self.plr,ans.idx,"cost")
     negateLinkBelow(self.card,self.plr)
    end,
   },
  },
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx)
    local sid=eventCtx.card.id
    local s
    if sid=="dark_hole" or sid=="raigeki" then s=500
    elseif sid=="monster_reborn" then s=350
    elseif sid=="polymerization" then s=400
    elseif sid=="thousand_knives" or sid=="stamping_destruction" then s=350
    elseif sid=="swords_of_revealing_light" or sid=="necrovalley" then s=300
    elseif sid=="pot_of_greed" then s=150
    else s=200
    end
    if #G.hand[plr]<=2 then s=s-100 end
    return s
   end,
  },
 },
 seventools={
  responseOnly=true,
  listens={
   ACTIVATE={
    optional=true,
    speed=3,
    when=function(self,ctx)
     return ctx.card and ctx.card.cat=="trap" and G.lp[self.plr]>=1000
    end,
    react=function(self,ctx)
     changeLp(self.plr,-1000)
     negateLinkBelow(self.card,self.plr)
    end,
   },
  },
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx)
    local tid=eventCtx.card.id
    local s
    if tid=="mirror_force" or tid=="ring_of_destruction" then s=400
    elseif tid=="gravity_bind" or tid=="negate_attack" then s=300
    else s=200
    end
    if ctx.ownLP<=1500 then s=s-200 end
    return s
   end,
  },
 },
 negateattack={
  responseOnly=true,
  listens={
   ATTACK={
    optional=true,
    speed=3,
    when=function(self,ctx) return ctx.actor~=self.controller end,
    react=function() doAdvancePhase(PH_END) end,
   },
  },
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx)
    local atkVal=getMonAtk(eventCtx.attacker) or eventCtx.attacker.atk or 0
    local s=atkVal
    if ctx.ownLP<=atkVal then s=s+500 end
    return s
   end,
  },
 },
 ringdestruction=(function()
  -- Normal Trap. Offered as a response after any opp action on opp's turn
  -- (SUMMON/FLIP/ATTACK/ACTIVATE). targetPick captures the picked monster
  -- at activation → link.target carries it → Dark Illusion can negate when
  -- the targeted monster is DARK. React just applies destroy + half-ATK
  -- damage (self first, then opp if alive). Uses changeLp (not applyDamage)
  -- so Kuriboh can't chain (effect damage, not battle damage). The LP gate
  -- guarantees opp survives → no draw possible.
  local function when(self,ctx)
   local opp=3-self.plr
   if G.active~=opp then return false end
   local cap=G.lp[opp]
   return hasFaceUpMonster(opp,function(m) return (m.atk or 0)<=cap end)
  end
  local function targetPick(self,ctx)
   local opp=3-self.plr
   local cap=G.lp[opp]
   local t=choose{
    kind="zone",plr=self.plr,side=opp,row="mon",title="RING OF DESTRUCTION",
    filter=function(c) return c and not c.facedown and (c.atk or 0)<=cap end,
   }
   if not t then return nil end
   local m=G.mon[t.plr][t.col]
   if not m or m.facedown then return nil end
   return {target=m,params={plr=t.plr,col=t.col,dmg=(m.atk or 0)//2}}
  end
  local function react(self,ctx,params)
   local opp=3-self.plr
   sendMonsterToGY(params.plr,params.col,"effect")
   changeLp(self.plr,-params.dmg)
   if G.lp[self.plr]>0 then changeLp(opp,-params.dmg) end
  end
  return {
   responseOnly=true,
   listens=quickPlayListens{optional=true,speed=2,when=when,
    targetPick=targetPick,react=react},
   ai={
    scoreActivate=function(card,plr,ctx,event,eventCtx) return 300 end,
   },
  }
 end)(),
 darkillusion={
  -- Counter Trap (SS3): chain to an activation whose link.target is a face-up
  -- DARK monster (either side). Catches cards via targetPick (EC, Ring), via
  -- procActivate's target arg (Thousand Knives, EC menu), or targetCard
  -- shortcut (Trap Hole). Maneater/gkassailant pick at react-time, uncaught.
  responseOnly=true,
  listens={
   ACTIVATE={
    optional=true,
    speed=3,
    when=function(self,ctx)
     local t=ctx.link and ctx.link.target
     return t and not t.facedown and t.attr=="dark"
    end,
    react=function(self,ctx) negateLinkBelow(self.card,self.plr) end,
   },
  },
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx)
    return 200+(eventCtx.link.target.atk or 0)//4
   end,
  },
 },
 gravitybind={
  static={gravityBind=true},
  listens={
   PHASE={
    optional=true,
    speed=2,
    when=function(self,ctx)
     return self.card.facedown
        and ctx.toPhase==PH_BATTLE and ctx.actor~=self.controller
    end,
    react=function(self,ctx) end,
   },
  },
  ai={
   scoreActivate=function(card,plr,ctx,event,eventCtx) return 250 end,
  },
 },

 -- =============== MONSTERS ===============
 kuriboh={
  -- Hand-trap (Quick Effect, SS2). React sets ctx.negated=true; applyDamage's
  -- continuation skips the changeLp call when negated. spendLink's "hand"
  -- branch discards Kuriboh automatically.
  speed=2,
  listens={
   BEFORE_DAMAGE={
    optional=true,
    speed=2,
    when=function(self,ctx)
     return self.zone=="hand" and ctx.plr==self.plr and (ctx.dmg or 0)>0
    end,
    react=function(self,ctx)
     ctx.negated=true
    end,
   },
  },
 },
 sangan={
  -- DESTROYED: search deck for a monster ATK<=1500 and add to hand.
  listens={
   DESTROYED={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx)
     local plr=self.plr
     if #G.hand[plr]>=MAX_HAND then return end
     local ans=choose{
      kind="card",plr=plr,from="deck",title="SANGAN  ATK<=1500",
      filter=function(card)
       return (card.cat or "monster")=="monster" and card.atk and card.atk<=1500
      end,
     }
     if not ans then return end
     table.insert(G.hand[plr],makeCard(table.remove(G.deck[plr],ans.idx)))
    end,
   },
  },
 },
 thunderdragon={
  handIgnition={
   label="DISCARD: SEARCH",
   canActivate=function(card,plr)
    for _,id in ipairs(G.deck[plr]) do
     if id=="thunder_dragon" then return true end
    end
    return false
   end,
   activate=function(card,plr,handIdx)
    discardFromHand(plr,handIdx,"effect")
    local added=0
    for i=#G.deck[plr],1,-1 do
     if added>=2 or #G.hand[plr]>=MAX_HAND then break end
     if G.deck[plr][i]=="thunder_dragon" then
      table.insert(G.hand[plr],makeCard(table.remove(G.deck[plr],i)))
      added=added+1
     end
    end
   end,
  },
 },
 maneater={
  -- FLIP: destroy 1 monster on either side.
  listens={
   FLIP={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx)
     if not (hasTargetableMon(1) or hasTargetableMon(2)) then return end
     local opp=3-self.plr
     local target=choose{
      kind="zone",plr=self.plr,row="mon",side="any",title="MAN-EATER",
      filter=canTargetMon,
      -- AI: strongest targetable opp (atk-aware), else own weakest targetable.
      aiPick=function(req) return aiPickBounceTarget(self.plr,opp,function(m)
       return (m.pos==1 and not m.facedown) and m.atk or m.def
      end) end,
     }
     if not target then return end
     if not (G.mon[target.plr] and G.mon[target.plr][target.col]) then return end
     revealAndDestroyMon(target.plr,target.col,"effect")
     checkEquips()
    end,
   },
  },
 },
 legion={
  -- The ignition sets a flag and changes nothing visible, so it only pays off
  -- via the follow-up it unlocks -- aiEnumerateMain emits that extra summon,
  -- and the enabler pass is what connects the two.
  ignition={
   label="EXTRA SUMMON",
   canActivate=function(_,plr)
    return not G.legionSummonUsed and not G.extraSpellcasterSummon
   end,
   activate=function() G.extraSpellcasterSummon=true; G.legionSummonUsed=true end,
  },
  listens={
   DESTROYED={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx) legionSearch(self.plr) end,
   },
   TRIBUTED={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx) legionSearch(self.plr) end,
   },
  },
 },
 ufoturtle={
  -- DESTROYED: Special Summon a FIRE monster from deck.
  -- AI defaults to ATK position (menu bridge picks items[1] when plr=2);
  -- player gets the ATK/DEF choice via kind="menu",forced=true.
  listens={
   DESTROYED={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx)
     local plr=self.plr
     if not firstEmpty(G.mon[plr]) then return end
     local ans=choose{
      kind="card",plr=plr,from="deck",title="UFO TURTLE  FIRE",
      filter=function(c) return (c.cat or "monster")=="monster" and c.attr=="fire" end,
     }
     if not ans then return end
     local key=choose{
      kind="menu",plr=plr,forced=true,
      items={{"ATK POSITION","ss_atk"},{"DEF POSITION","ss_def"}},
     }
     local emptyCol=firstEmpty(G.mon[plr])
     if not emptyCol then return end
     local m=makeCard(table.remove(G.deck[plr],ans.idx))
     m.pos=(key=="ss_def") and 2 or 1
     m.facedown=false; m.attacked=false; m.summoned=true; m.posChanged=false
     G.mon[plr][emptyCol]=m
     summonEvent(m,plr,emptyCol,"special",nil)
    end,
   },
  },
 },
 dmgirl={
  atkBonus=function(card)
   local b=0
   for p=1,2 do for _,c in ipairs(G.gy[p]) do
    if c.name=="Dark Magician" then b=b+300 end
   end end
   return b
  end,
 },
 busterblader={
  atkBonus=function(card)
   local opp=nil
   for p=1,2 do for i=1,3 do if G.mon[p][i]==card then opp=3-p; break end end
    if opp then break end end
   if not opp then return 0 end
   local b=0
   for i=1,3 do
    local m=G.mon[opp][i]
    if m and not m.facedown and m.type=="dragon" then b=b+500 end
   end
   for _,c in ipairs(G.gy[opp]) do
    if c.type=="dragon" then b=b+500 end
   end
   return b
  end,
 },
 darkpaladin={
  -- Fusion (Dark Magician + Buster Blader). Negates opp Spells like Magic
  -- Jammer; gains 500 ATK per Dragon on the field or in either GY.
  atkBonus=function(card)
   local b=0
   for p=1,2 do
    for i=1,3 do
     local m=G.mon[p][i]
     if m and not m.facedown and m.type=="dragon" then b=b+500 end
    end
    for _,c in ipairs(G.gy[p]) do
     if c.type=="dragon" then b=b+500 end
    end
   end
   return b
  end,
  listens={
   ACTIVATE={
    optional=true,
    speed=2,
    when=function(self,ctx)
     return ctx.card and ctx.card.cat=="spell"
        and ctx.actor and ctx.actor~=self.plr
        and #G.hand[self.plr]>=1
    end,
    react=function(self,ctx)
     local ans=choose{kind="card",plr=self.plr,from="hand",title="DARK PALADIN COST"}
     if not ans then return end
     discardFromHand(self.plr,ans.idx,"cost")
     local links=G.proc.chain.links
     local myIdx=nil
     for i=#links,1,-1 do
      if links[i].source==self.card then myIdx=i; break end
     end
     if not myIdx or myIdx<=1 then return end
     local target=links[myIdx-1]
     target.negated=true
     local loc=target.sourceLoc
     if loc and loc.zone=="st" then revealAndDestroyST(loc.plr,loc.col)
     elseif loc and loc.zone=="fs" then sendFieldSpellToGY(loc.plr,"effect",self.plr) end
    end,
   },
  },
 },
 sternmystic={
  -- FLIP: briefly reveal every face-down card on the field.
  listens={
   FLIP={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx) animFlashFaceDown() end,
   },
  },
 },
 doublecoston={
  -- Counts as 2 Tributes for the Tribute Summon of a DARK monster.
  tributeValue=function(m,summonCard)
   return (summonCard and summonCard.attr=="dark") and 2 or nil
  end,
 },
 lordofd={
  static={dragonProtect=true},
 },
 speardragon={
  piercing=true,
  onAfterAttack=function(card) card.pos=2 end,
 },
 gearfried={
  -- When any Equip is activated targeting this card, negate + destroy the
  -- equip via negateLinkBelow. Mandatory (no prompt) — runResponseWindow
  -- auto-fires mandatory listeners on EV_ACTIVATE before offering optionals.
  listens={
   ACTIVATE={
    speed=2,
    when=function(self,ctx)
     return ctx.card and ctx.card.subtype=="equip"
        and ctx.link and ctx.link.target==self.card
    end,
    react=function(self,ctx) negateLinkBelow(self.card,self.plr) end,
   },
  },
 },
 rocketwarrior={
  -- "Rocket mode" while it's the controller's turn: during your turn it can't
  -- be destroyed by battle and you take no battle damage from its battles.
  -- These only matter when it attacks (it can only be in battle on your turn
  -- as the attacker; on the opponent's turn G.active~=ctrl so the guards lift,
  -- and it defends as a normal monster). Queried in runAttackBattle via
  -- battleIndestructible / battleDamageImmune.
  battleImmune  =function(card,ctrl) return G.active==ctrl end,
  noBattleDamage=function(card,ctrl) return G.active==ctrl end,
  -- After it attacks a monster that survived, that target loses 500 ATK until
  -- end of turn (turnMods are cleared at the End Phase).
  onAfterAttack=function(card,plr,atkCol,target,tgtCol,opp)
   if target and opp and tgtCol and G.mon[opp][tgtCol]==target then
    addTurnMod(target,"atk",-500)
   end
  end,
 },
 timewizard={
  -- Once per turn per copy. Win: wipe opp board. Lose: wipe own + half-total
  -- ATK self-damage.
  ignition={
   label="TIME ROULETTE",
   canActivate=function(card) return card.timeWizardUsed~=G.turn end,
   activate=function(card,plr,col)
    card.timeWizardUsed=G.turn
    procPushFrame(function()
     local r=choose{kind="coin"}
     if r==1 then
      for c=1,3 do
       if G.mon[3-plr][c] then sendMonsterToGY(3-plr,c,"effect") end
      end
     else
      local total=0
      for c=1,3 do
       local m=G.mon[plr][c]
       if m then total=total+getMonAtk(m) end
      end
      for c=1,3 do
       if G.mon[plr][c] then sendMonsterToGY(plr,c,"effect") end
      end
      changeLp(plr,-math.floor(total/2))
     end
     checkEquips()
    end)
   end,
  },
 },
 kaibaman={
  ignition={
   label="SS BLUE-EYES",
   canActivate=function(_,plr)
    for _,c in ipairs(G.hand[plr]) do
     if c.name=="Blue-Eyes W Dragon" then return true end
    end
    return false
   end,
   activate=function(_,plr,col)
    procPushFrame(function()
     local bewIdx=nil
     for i,c in ipairs(G.hand[plr]) do
      if c.name=="Blue-Eyes W Dragon" then bewIdx=i; break end
     end
     if not bewIdx then return end
     local key=choose{
      kind="menu",plr=plr,forced=true,
      items={{"ATK POSITION","atk"},{"DEF POSITION","def"}},
     }
     local pos=(key=="def") and 2 or 1
     sendMonsterToGY(plr,col,"tribute")
     local bew=table.remove(G.hand[plr],bewIdx)
     bew.pos=pos; bew.facedown=false; bew.attacked=false
     bew.summoned=false; bew.posChanged=false
     G.mon[plr][col]=bew
     summonEvent(bew,plr,col,"special",nil)
    end)
   end,
  },
 },
 jinzo={
  static={blocksTraps=true},
  listens={
   SUMMON   ={when=function(self,ctx) return ctx.card==self.card end,
              react=function() sweepTrapHook("onNegate") end},
   FLIP     ={when=function(self,ctx) return ctx.card==self.card end,
              react=function() sweepTrapHook("onNegate") end},
   DESTROYED={when=function(self,ctx) return ctx.card==self.card end,
              react=function()
               if not staticActive("blocksTraps") then sweepTrapHook("onResume") end
              end},
   TRIBUTED ={when=function(self,ctx) return ctx.card==self.card end,
              react=function()
               if not staticActive("blocksTraps") then sweepTrapHook("onResume") end
              end},
  },
 },
 gkcurse={
  listens={
   SUMMON={
    when =function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx) changeLp(3-self.plr,-800) end,
   },
  },
 },
 gkassailant={
  -- When this monster declares an attack while Necrovalley is on the field,
  -- the player may change the battle position of 1 opponent monster first.
  -- The attack continuation (in INTENTS.DECLARE_ATTACK) automatically runs
  -- after this react via the push-continuation + raiseNow(EV_ATTACK) flow.
  listens={
   ATTACK={
    when=function(self,ctx)
     return ctx.attacker==self.card
        and staticActive("necrovalley") and hasTargetableMon(3-self.plr)
    end,
    react=function(self,ctx)
     local plr=self.plr
     local key=choose{
      kind="menu",plr=plr,forced=true,
      items={{"EFFECT","yes"},{"NORMAL","no"}},
     }
     if key~="yes" then return end
     local target=choose{
      kind="zone",plr=plr,side=3-plr,title="ASSAILANT: CHANGE POS",
      filter=function(c) return canTargetMon(c) end,
     }
     if not target then return end
     local m=G.mon[target.plr] and G.mon[target.plr][target.col]
     if not m then return end
     if m.facedown then
      m.facedown=false; m.pos=1; m.posChanged=true
      flipEvent(m,target.plr,target.col)
     else
      togglePosition(m)
     end
     checkEquips()
    end,
   },
  },
 },
 gkspy={
  -- FLIP: Special Summon a "Gravekeeper's" monster (ATK<=1500) from the Deck.
  listens={
   FLIP={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx)
     local plr=self.plr
     if not firstEmpty(G.mon[plr]) then return end
     local ans=choose{
      kind="card",plr=plr,from="deck",title="GRAVEKEEPER'S SPY",
      filter=function(c)
       return (c.cat or "monster")=="monster" and isGravekeeper(c) and (c.atk or 0)<=1500
      end,
     }
     if not ans then return end
     local key=choose{
      kind="menu",plr=plr,forced=true,
      items={{"ATK POSITION","ss_atk"},{"DEF POSITION","ss_def"}},
     }
     local emptyCol=firstEmpty(G.mon[plr])
     if not emptyCol then return end
     local m=makeCard(table.remove(G.deck[plr],ans.idx))
     m.pos=(key=="ss_def") and 2 or 1
     m.facedown=false; m.attacked=false; m.summoned=true; m.posChanged=false
     G.mon[plr][emptyCol]=m
     summonEvent(m,plr,emptyCol,"special",nil)
    end,
   },
  },
 },
 gkguard={
  -- FLIP: target 1 monster on either side; return it to its owner's hand.
  listens={
   FLIP={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx)
     if not (hasTargetableMon(1) or hasTargetableMon(2)) then return end
     local opp=3-self.plr
     local target=choose{
      kind="zone",plr=self.plr,row="mon",side="any",title="GK GUARD",
      filter=canTargetMon,
      aiPick=function(req) return aiPickBounceTarget(self.plr,opp) end,
     }
     if not target then return end
     if G.mon[target.plr][target.col] then
      returnMonsterToHand(target.plr,target.col)
     end
    end,
   },
  },
 },
 necrovalley={
  -- Field Spell. necrovalley flag (presence query) + blocksGYMoves (rule mod).
  static={necrovalley=true, blocksGYMoves=true},
  resolve=function() end,
 },
 sogen={
  -- Field Spell. +400 ATK/DEF to Warrior + Beast-Warrior on either side.
  static={sogen=true},
  resolve=function() end,
 },
 gkshaman={
  -- Continuous: while face-up AND Necrovalley active, opponent can't activate
  -- a field spell. The conditional is part of the static value itself — the
  -- engine queries it generically via staticActive("blocksFieldSpells").
  -- DEF bonus: +200 for each GK monster in either GY.
  static={blocksFieldSpells=function() return staticActive("necrovalley") end},
  defBonus=function(card)
   local n=0
   for p=1,2 do for _,c in ipairs(G.gy[p]) do
    if isGravekeeper(c) then n=n+200 end
   end end
   return n
  end,
 },
 catillomen={
  -- FLIP: place a trap from deck on top of deck (or add to hand if Necrovalley
  -- is active).
  listens={
   FLIP={
    when=function(self,ctx) return ctx.card==self.card end,
    react=function(self,ctx)
     local plr=self.plr
     local nv=staticActive("necrovalley")
     local ans=choose{
      kind="card",plr=plr,from="deck",
      title=nv and "CAT: ADD TRAP TO HAND" or "CAT: TRAP ON TOP OF DECK",
      filter=function(c) return c.cat=="trap" end,
      -- AI uses default aiPickCard which sorts by ATK; for traps that's 0,
      -- so it picks the first matching trap.
     }
     if not ans then return end
     local slug=table.remove(G.deck[plr],ans.idx)
     if nv then
      table.insert(G.hand[plr],makeCard(slug))
     else
      table.insert(G.deck[plr],slug)  -- append = top of deck
     end
    end,
   },
  },
 },
 gkstele={
  canActivate=function(card,plr)
   plr=plr or 1
   for _,c in ipairs(G.gy[plr]) do
    if isGravekeeper(c) and c.cat=="monster" then return true end
   end
   return false
  end,
  resolve=function(plr)
   for i=1,2 do
    local hasAny=false
    for _,c in ipairs(G.gy[plr]) do
     if isGravekeeper(c) and c.cat=="monster" then hasAny=true; break end
    end
    if not hasAny then return end
    local ans=choose{
     kind="card",plr=plr,from="gy",
     title="STELE: PICK GK ("..(3-i).." LEFT)",
     filter=function(c) return isGravekeeper(c) and c.cat=="monster" end,
    }
    if not ans then return end
    table.insert(G.hand[plr],table.remove(G.gy[plr],ans.idx))
   end
  end,
 },
 gkoracle={
  -- A "Gravekeeper's" monster counts as 3 Tributes toward summoning this card.
  tributeValue=function(m) return isGravekeeper(m) and 3 or nil end,
  -- Migrated to listens.SUMMON 2026-05-20 (phase 2). onTributeSummon + onSummon
  -- fused into one reaction; the tributed list comes from ctx (no G.oracleTribData
  -- staging needed).
  listens={
   SUMMON={
    when=function(self,ctx)
     return ctx.card==self.card and ctx.kind=="tribute"
    end,
    react=function(self,ctx)
     local gkN,lvlS=0,0
     for _,t in ipairs(ctx.tributed) do
      local m=t.card
      lvlS=lvlS+(m.lvl or 0)
      if isGravekeeper(m) then gkN=gkN+1 end
     end
     if gkN==0 then return end
     oraclePickLoop(self.card,self.plr,gkN,lvlS)
    end,
   },
  },
 },
}

