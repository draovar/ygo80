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
--   resolve(plr,ctx)   default react body for direct activations (the chain
--                      link's react = applyResolve(card,plr,nil) when no
--                      explicit react is supplied to procActivate)
--   canActivate(card)  predicate gating manual activation from the menu
--   activate(opts)     custom activation flow (target-pickers etc.);
--                      opts = {col,card,zone,plr,trigCtx}.
--                      When absent, the default flow runs procActivate.
--   aiCanCast(card)    AI: cast this spell from hand this turn?
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

BEHAVIORS={
 -- =============== SPELLS ===============
 darkhole={
  aiCanCast=function() return hasMonsters(1) or hasMonsters(2) end,
  resolve=function(plr)
   for i=1,3 do for p=1,2 do
    if G.mon[p][i] then revealAndDestroyMon(p,i,"effect") end
   end end
   checkEquips()
  end,
 },
 raigeki={
  aiCanCast=function() return hasMonsters(1) end,
  resolve=function(plr)
   local opp=3-plr
   for i=1,3 do
    if G.mon[opp][i] then revealAndDestroyMon(opp,i,"effect") end
   end
   checkEquips()
  end,
 },
 fissure={
  canActivate=function() return hasTargetableMon(2) end,
  aiCanCast=function() return hasTargetableMon(1) end,
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
  aiCanCast=function() return true end,
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
 mst={
  -- Quick-Play Spell (speed 2 derived from subtype=quickplay).
  canActivate=function(card) return #mstTargets(card)>0 end,
  activate=function(opts)
   pickSTOrFSThenActivate(opts.col,opts.card,opts.trigCtx,opts.zone,{
    title=(opts.zone=="hand") and "MST" or "MST (CHAINED)",
    resolveFn=function(tplr,kind,di)
     if kind=="fs" then
      if G.fs[tplr] then sendFieldSpellToGY(tplr,"effect",1) end
     elseif G.st[tplr][di] then revealAndDestroyST(tplr,di) end
    end,
   })
  end,
 },
 stampingdestruction={
  canActivate=function(card) return controlsDragon(1) and #mstTargets(card)>0 end,
  aiCanCast=function()
   if not controlsDragon(2) then return false end
   for c=1,3 do if G.st[1][c] then return true end end
   return G.fs[1]~=nil
  end,
  activate=function(opts)
   pickSTOrFSThenActivate(opts.col,opts.card,opts.trigCtx,opts.zone,{
    title="STAMPING DESTRUCTION",
    resolveFn=function(tplr,kind,di)
     if kind=="fs" then
      if G.fs[tplr] then
       sendFieldSpellToGY(tplr,"effect",1); changeLp(tplr,-500)
      end
     elseif G.st[tplr][di] then
      revealAndDestroyST(tplr,di); changeLp(tplr,-500)
     end
    end,
   })
  end,
  resolve=function(plr)  -- AI: destroy first opp S/T, else opp FS
   local opp=3-plr
   for c=1,3 do
    if G.st[opp][c] then
     revealAndDestroyST(opp,c); changeLp(opp,-500); return
    end
   end
   if G.fs[opp] then
    sendFieldSpellToGY(opp,"effect",plr); changeLp(opp,-500)
   end
  end,
 },
 potofgreed={
  aiCanCast=function() return #G.deck[2]>0 and #G.hand[2]<MAX_HAND end,
  resolve=function(plr) drawCard(plr); drawCard(plr) end,
 },
 gracefuldice={
  canActivate=function() return hasMonsters(1) end,
  aiCanCast =function() return hasMonsters(2) end,
  resolve=function(plr)
   local r=choose{kind="dice"}
   if not r then return end
   local boost=r*100
   for c=1,3 do
    local m=G.mon[plr][c]
    if m and not m.facedown then
     addTurnMod(m,"atk",boost); addTurnMod(m,"def",boost)
    end
   end
  end,
 },
 gianttrunade={
  aiCanCast=function()
   for p=1,2 do
    for c=1,3 do if G.st[p][c] then return true end end
    if G.fs[p] then return true end
   end
   return false
  end,
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
  -- Requires 2 empty monster zones to activate (per real card).
  canActivate=function()
   local n=0; for c=1,3 do if not G.mon[1][c] then n=n+1 end end
   return n>=2
  end,
  aiCanCast=function()
   local n=0; for c=1,3 do if not G.mon[2][c] then n=n+1 end end
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
  -- Cost is discarded at resolution time (consistent with MJ).
  -- Need ≥2 hand cards: 1 to discard, ≥1 monster left to reduce.
  canActivate=function()
   if #G.hand[1]<2 then return false end
   local mons=0
   for _,c in ipairs(G.hand[1]) do if c.cat=="monster" then mons=mons+1 end end
   return mons>=1
  end,
  aiCanCast=function()
   if #G.hand[2]<2 then return false end
   for _,c in ipairs(G.hand[2]) do
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
  -- Continuous Spell: stays face-up, locks the opponent's attacks (the
  -- blocksAttack static capability — enforced via staticActive). The
  -- swordsCounter (set on resolve) is decremented each of their End Phases
  -- by tickSwords; the card self-destructs after the 3rd.
  static={blocksAttack=true},
  aiCanCast=function() return hasMonsters(1) end,
  resolve=function(plr,ctx)
   if ctx and ctx.source then ctx.source.swordsCounter=3 end
  end,
 },
 thousandknives={
  canActivate=function() return controlsDarkMagician(1) and hasTargetableMon(2) end,
  aiCanCast =function() return controlsDarkMagician(2) and hasTargetableMon(1) end,
  activate=function(opts)
   if opts.plr==2 then
    procActivate(opts.card,2,opts.zone,opts.col)
    return
   end
   if not hasTargetableMon(2) then G.mode="free"; return end
   local card,col,zone=opts.card,opts.col,opts.zone
   procPushFrame(function()
    local target=choose{
     kind="zone",plr=1,side=2,row="mon",title="THOUSAND KNIVES",
     filter=function(c) return canTargetMon(c) end,
    }
    if not target then return end
    procActivate(card,1,zone,col,function()
     if G.mon[target.plr][target.col] then
      revealAndDestroyMon(target.plr,target.col,"effect"); checkEquips()
     end
    end)
   end)
  end,
  resolve=function(plr)  -- AI path: destroy opponent's strongest targetable monster
   local opp=3-plr
   local best,bestI=-1,nil
   for i=1,3 do
    local m=G.mon[opp][i]
    if m and canTargetMon(m) then
     local s=(m.pos==1 and not m.facedown) and m.atk or m.def
     if s>best then best=s; bestI=i end
    end
   end
   if bestI then revealAndDestroyMon(opp,bestI,"effect"); checkEquips() end
  end,
 },
 monsterreborn={
  -- Special Summon 1 monster from either GY to your field.
  -- Player path: choose target (cross-GY) then ATK/DEF position then activate.
  -- AI path: falls through to BEHAVIORS.resolve below (revives strongest).
  canActivate=function() return firstEmpty(G.mon[1]) and anyGYMonster() and not staticActive("blocksGYMoves") end,
  aiCanCast =function() return firstEmpty(G.mon[2]) and anyGYMonster() and not staticActive("blocksGYMoves") end,
  activate=function(opts)
   local card,col,zone=opts.card,opts.col,opts.zone
   procPushFrame(function()
    local items=gyMonsterItems()
    if #items==0 then return end
    local ans=choose{kind="card",plr=1,items=items,title="MONSTER REBORN"}
    if not ans then return end
    local gyPlr,gyIdx=ans.item.gyPlr,ans.item.gyIdx
    local key=choose{
     kind="menu",plr=1,forced=true,
     items={{"ATK POSITION","ss_atk"},{"DEF POSITION","ss_def"}},
    }
    local pos=(key=="ss_def") and 2 or 1
    procActivate(card,1,zone,col,function()
     local emptyCol=firstEmpty(G.mon[1])
     local m=emptyCol and G.gy[gyPlr][gyIdx]
     if not (emptyCol and m and m.cat=="monster") then return end
     table.remove(G.gy[gyPlr],gyIdx)
     m.pos=pos; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
     m.linkedTrap=nil
     G.mon[1][emptyCol]=m
     summonEvent(m,1,emptyCol,"special",nil)
    end)
   end)
  end,
  resolve=function(plr)  -- AI path: revive the strongest monster available
   if staticActive("blocksGYMoves") then return end
   local emptyCol=firstEmpty(G.mon[plr])
   if not emptyCol then return end
   local best,bp,bi=-1,nil,nil
   for p=1,2 do for i,c in ipairs(G.gy[p]) do
    if c.cat=="monster" and (c.atk or 0)>best then best=c.atk; bp=p; bi=i end
   end end
   if bi then
    local m=table.remove(G.gy[bp],bi)
    m.pos=1; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
    m.linkedTrap=nil
    G.mon[plr][emptyCol]=m
    summonEvent(m,plr,emptyCol,"special",nil)
   end
  end,
 },
 fluteofdragon={
  -- Lord of D. required on field at activation AND at resolution.
  canActivate=function()
   if not staticActive("dragonProtect",1) or not firstEmpty(G.mon[1]) then return false end
   for _,c in ipairs(G.hand[1]) do if c.type=="dragon" then return true end end
   return false
  end,
  aiCanCast=function()
   if not staticActive("dragonProtect",2) or not firstEmpty(G.mon[2]) then return false end
   for _,c in ipairs(G.hand[2]) do if c.type=="dragon" then return true end end
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
  -- Attack cancellation falls out naturally because INTENTS.DECLARE_ATTACK's
  -- continuation re-checks attacker survival after the chain resolves.
  responseOnly=true,
  listens={
   ATTACK={
    optional=true,
    speed=2,
    when=function(self,ctx) return ctx.actor~=self.controller end,
    react=function(self,ctx)
     -- Destroy all face-up ATK-position monsters on the attacking side
     -- (opp = the side opposite the trap's controller).
     local opp=3-self.plr
     G.battleAnim=nil
     for i=1,3 do
      local m=G.mon[opp][i]
      if m and m.pos==1 and not m.facedown then sendMonsterToGY(opp,i,"effect") end
     end
    end,
   },
  },
 },
 kunaichain={
  -- Pick one or both: change the attacker to DEF (cancels attack via the
  -- pos check in DECLARE_ATTACK's continuation), and/or convert this card
  -- into an equip on a face-up own monster (+500 ATK). The subtype mutation
  -- makes spendLink keep the card face-up so it persists as an equip.
  responseOnly=true,
  equipBonus=function() return 500,0 end,
  listens={
   ATTACK={
    optional=true,
    speed=2,
    when=function(self,ctx) return ctx.actor~=self.controller end,
    react=function(self,ctx)
     local hasOwn=false
     for c=1,3 do
      local m=G.mon[self.plr][c]
      if m and not m.facedown then hasOwn=true; break end
     end
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
 },
 traphole={
  responseOnly=true,
  listens={
   SUMMON={
    optional=true,
    speed=2,
    when=function(self,ctx)
     -- Fires on Normal Summon AND Tribute Summon (both are NS variants);
     -- skips Special Summons. Set monsters don't fire EV_SUMMON at all.
     return ctx.kind~="special" and not ctx.facedown
        and (ctx.card.atk or 0)>=1000
        and ctx.actor~=self.controller
        and canTargetMon(ctx.card)
    end,
    react=function(self,ctx)
     -- Safety: refuse to destroy own controller's summon. Defense in depth
     -- against a one-off bug where TH fired on its controller's own summon
     -- despite the when() check. If the trace fires in normal play, investigate.
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
 },
 callhaunted={
  -- Continuous Trap. Manual activate or chain-response. Both paths share
  -- cohSpecialSummon. Negation by Jinzo: onNegate kills the anchor monster,
  -- onResume self-destructs if the anchor is gone.
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
  canActivate=function(card) return canReviveMonster(1) end,
  activate=function(opts)
   if opts.plr==2 then
    -- AI path: pick best GY monster, resolve inline (no UI).
    procActivate(opts.card,2,"st",opts.col,function()
     aiResolveCallHaunted(opts.col,opts.card); checkWin()
    end)
   else
    -- Player path: choose GY monster, then activate with captured gyIdx.
    local card,col=opts.card,opts.col
    procPushFrame(function()
     local ans=choose{
      kind="card",plr=1,from="gy",title="CALL OF THE HAUNTED",
      filter=function(c) return c.cat=="monster" end,
     }
     if not ans then return end
     local gyIdx=ans.idx
     procActivate(card,1,"st",col,function()
      local emptyCol=firstEmpty(G.mon[1])
      local m=emptyCol and G.gy[1][gyIdx]
      if not (emptyCol and m and m.cat=="monster") then return end
      table.remove(G.gy[1],gyIdx)
      m.pos=1; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
      G.mon[1][emptyCol]=m
      card.linkedMon=m; m.linkedTrap=card
      summonEvent(m,1,emptyCol,"special",nil)
     end)
    end)
   end
  end,
 },
 magicjammer={
  -- Counter Trap (SS3): chain to a spell activation, discard 1 to negate +
  -- destroy. Cost-at-activation timing is approximated by paying the discard
  -- at chain-resolve (close enough for this game).
  responseOnly=true,
  listens={
   ACTIVATE={
    optional=true,
    speed=3,
    when=function(self,ctx)
     return ctx.card and ctx.card.cat=="spell" and #G.hand[self.plr]>=1
    end,
    react=function(self,ctx)
     local ans=choose{
      kind="card",plr=self.plr,from="hand",title="MAGIC JAMMER COST",
     }
     if not ans then return end
     discardFromHand(self.plr,ans.idx,"cost")
     -- Find this MJ link on the chain, negate the one directly below it
     -- (the spell we chained to), and send the negated source to GY.
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
 seventools={
  -- Counter Trap (SS3): chain to a trap activation, pay 1000 LP to negate +
  -- destroy. Cost paid at chain-resolve (matches MJ's approximation).
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
     local links=G.proc.chain.links
     local myIdx=nil
     for i=#links,1,-1 do
      if links[i].source==self.card then myIdx=i; break end
     end
     if not myIdx or myIdx<=1 then return end
     local target=links[myIdx-1]
     target.negated=true
     local loc=target.sourceLoc
     if loc and loc.zone=="st" then revealAndDestroyST(loc.plr,loc.col) end
    end,
   },
  },
 },
 negateattack={
  -- Counter Trap (SS3): force the active player to End Phase. The attack
  -- continuation in INTENTS.DECLARE_ATTACK sees G.ph~=PH_BATTLE and bails;
  -- aiTick/autoPhase carry the active player through PH_END from there.
  responseOnly=true,
  listens={
   ATTACK={
    optional=true,
    speed=3,
    when=function(self,ctx) return ctx.actor~=self.controller end,
    react=function() doAdvancePhase(PH_END) end,
   },
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
    react=function(self,ctx) end,  -- effect is purely the static flag
   },
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
      filter=function(c,p,col) return canTargetMon(c) end,
      -- AI: strongest targetable opp, else own weakest targetable.
      aiPick=function(req)
       local best,bestK=-1,nil
       for c=1,3 do
        local m=G.mon[opp][c]
        if m and canTargetMon(m) then
         local s=(m.pos==1 and not m.facedown) and m.atk or m.def
         if s>best then best=s; bestK={plr=opp,col=c} end
        end
       end
       if bestK then return bestK end
       for c=1,3 do
        if canTargetMon(G.mon[self.plr][c]) then return {plr=self.plr,col=c} end
       end
       return nil
      end,
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
  -- Ignition is plr==1 only: the extra-summon flag is consumed by player UI
  -- and INTENTS.SUMMON's `extra` branch; AI has no path to use it yet.
  ignition={
   label="EXTRA SUMMON",
   canActivate=function(_,plr)
    return plr==1 and not G.legionSummonUsed and not G.extraSpellcasterSummon
   end,
   activate=function() G.extraSpellcasterSummon=true; G.legionSummonUsed=true end,
  },
  listens={
   DESTROYED={
    when=function(self,ctx) return ctx.card==self.card and self.plr==1 end,
    react=function(self,ctx) legionSearch() end,
   },
   TRIBUTED={
    when=function(self,ctx) return ctx.card==self.card and self.plr==1 end,
    react=function(self,ctx) legionSearch() end,
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
  -- Once per turn (per copy). Win: wipe opp board. Lose: wipe own board +
  -- self-damage equal to half the total ATK of own monsters destroyed.
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
  -- Each time summoned (Normal or Special), burn the opponent for 800.
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
     return ctx.attacker==self.card and self.plr==1
        and staticActive("necrovalley") and hasTargetableMon(2)
    end,
    react=function(self,ctx)
     local key=choose{
      kind="menu",plr=1,forced=true,
      items={{"EFFECT","yes"},{"NORMAL","no"}},
     }
     if key~="yes" then return end
     local target=choose{
      kind="zone",plr=1,side=2,title="ASSAILANT: CHANGE POS",
      filter=function(c) return canTargetMon(c) end,
     }
     if not target then return end
     local m=G.mon[target.plr] and G.mon[target.plr][target.col]
     if not m then return end
     if m.facedown then
      m.facedown=false; m.pos=1
      flipEvent(m,target.plr,target.col)
     else
      m.pos=(m.pos==1) and 2 or 1
     end
     m.posChanged=true
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
 necrovalley={
  -- Field Spell. Two static effects, no resolve action:
  --  1. necrovalley flag — presence query referenced by GK cards (gkassailant,
  --     gkshaman conditional, catillomen mode switch, +500 ATK/DEF in
  --     getMonAtk/getMonDef).
  --  2. blocksGYMoves — negates GY-move effects (Monster Reborn, Call of the
  --     Haunted, Legion's GY search).
  static={necrovalley=true, blocksGYMoves=true},
  aiCanCast=function() return true end,
  resolve=function() end,
 },
 sogen={
  -- Field Spell. Warrior + Beast-Warrior monsters on the field (either side)
  -- gain 400 ATK/DEF. Applied inline in getMonAtk/getMonDef via the `sogen`
  -- static flag (parallels Necrovalley's +500 to Gravekeeper's monsters).
  static={sogen=true},
  aiCanCast=function() return true end,
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
  -- isGravekeeper is a name-prefix check; restrict to monsters here.
  canActivate=function()
   for _,c in ipairs(G.gy[1]) do
    if isGravekeeper(c) and c.cat=="monster" then return true end
   end
   return false
  end,
  aiCanCast=function()
   for _,c in ipairs(G.gy[2]) do
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
  -- staging needed). For now the player path still calls the legacy openOraclePick
  -- UI -- it migrates to CHOOSE in phase 9.
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
     if self.plr==1 then
      openOraclePick({card=self.card,plr=1,remaining=gkN,lvlSum=lvlS,used={}})
     else
      -- AI: always activate effects in order E3 → E2 → E1
      for _,eff in ipairs({3,2,1}) do
       if gkN<=0 then break end
       if eff==1 then self.card.atkMod=(self.card.atkMod or 0)+lvlS*100
       elseif eff==2 then
        for i=1,3 do
         if G.mon[1][i] and G.mon[1][i].facedown then revealAndDestroyMon(1,i,"effect") end
        end
        checkEquips()
       elseif eff==3 then
        for i=1,3 do
         local m=G.mon[1][i]
         if m then
          m.atkMod=(m.atkMod or 0)-2000
          m.defMod=(m.defMod or 0)-2000
         end
        end
       end
       gkN=gkN-1
      end
     end
    end,
   },
  },
 },
}

