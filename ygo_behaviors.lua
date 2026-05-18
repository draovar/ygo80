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
--   triggers[event]    function(t,ctx,controller) -> bool, predicate for chain response window
--                      events: "summon" | "attack" | "phase" | "chain_open"
--                      ("phase" ctx carries toPhase = the phase about to begin)
--   resolve(plr,ctx)   called when this card's chain link resolves
--   canActivate(card)  predicate gating manual activation (menu / chain)
--   activate(opts)     custom activation flow; opts = {col,card,zone,plr,trigCtx}
--                      when absent, default flow (activateTrapAnim / animSpellActivation)
--   aiCanCast(card)    AI: cast this spell from hand this turn?
--   onSummon(card,plr) monster hook fired on normal/special summon
--   onTributeSummon(card,plr,tributed) fired at a Tribute Summon, before the
--                      tributed monsters (passed as a list) leave the field
--   onDestroy(card,plr) monster hook fired when destroyed
--   onFlip(card,plr)    monster hook fired when flipped face-up
--   onTributed(card,plr) monster hook fired when tributed
--   onAttackDeclared(card,plr,resume) fired when this monster declares an
--                      attack; the hook MUST call resume() to continue the
--                      attack (now, or later after a menu/picker via
--                      resumeAttack())
--   handTrap(plr,dmg,handIdx,card) hand quick-effect (Kuriboh-style)
--   atkBonus(card)     per-card ATK bonus (Dark Magician Girl, Buster Blader)
--   defBonus(card)     per-card DEF bonus (Gravekeeper's Shaman)
--   equipBonus(tgt,eq) per-equip stat bonus -> ab,db
--   tributeValue(m,summonCard) -> int|nil  overrides a monster's tribute worth;
--                      hook on the tributed monster (Double Coston) or on the
--                      summon card (Gravekeeper's Oracle). nil = no override.
--   static{flag=...}   continuous ("always-on") capabilities granted while the
--                      card is face-up on the field. The engine queries them
--                      generically via staticActive("flag"[,plr]) — no card
--                      name is hardcoded. Flags in use: blocksTraps (Jinzo),
--                      blocksAttack (Swords), gravityBind (Gravity Bind).
BEHAVIORS={
 -- =============== SPELLS ===============
 darkhole={
  aiCanCast=function() return hasMonsters(1) or hasMonsters(2) end,
  resolve=function(plr)
   for i=1,3 do for p=1,2 do
    if G.mon[p][i] then revealAndDestroyMon(p,i,"effect") end
   end end
   flushTriggers()
  end,
 },
 raigeki={
  aiCanCast=function() return hasMonsters(1) end,
  resolve=function(plr)
   local opp=3-plr
   for i=1,3 do
    if G.mon[opp][i] then revealAndDestroyMon(opp,i,"effect") end
   end
   flushTriggers()
  end,
 },
 fissure={
  aiCanCast=function() return hasMonsters(1) end,
  resolve=function(plr)
   local opp=3-plr
   local low,lowI=math.huge,nil
   for i=1,3 do
    local m=G.mon[opp][i]
    if m and not m.facedown and m.atk<low then low=m.atk; lowI=i end
   end
   if lowI then sendMonsterToGY(opp,lowI,"effect"); flushTriggers() end
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
  activate=function(opts) pickMSTTargetThenActivate(opts.col,opts.card,opts.trigCtx,opts.zone) end,
 },
 potofgreed={
  aiCanCast=function() return #G.deck[2]>0 and #G.hand[2]<MAX_HAND end,
  resolve=function(plr) drawCard(plr); drawCard(plr) end,
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
  -- Needs Dark Magician on your field; destroys 1 opponent monster.
  canActivate=function() return controlsDarkMagician(1) and hasMonsters(2) end,
  aiCanCast =function() return controlsDarkMagician(2) and hasMonsters(1) end,
  activate=function(opts) pickThousandKnivesTarget(opts.col,opts.card,opts.zone) end,
  resolve=function(plr)  -- AI path: destroy opponent's strongest monster
   local opp=3-plr
   local best,bestI=-1,nil
   for i=1,3 do
    local m=G.mon[opp][i]
    if m then
     local s=(m.pos==1 and not m.facedown) and m.atk or m.def
     if s>best then best=s; bestI=i end
    end
   end
   if bestI then revealAndDestroyMon(opp,bestI,"effect"); flushTriggers() end
  end,
 },
 monsterreborn={
  -- Special Summon 1 monster from either GY to your field (ATK position).
  canActivate=function() return firstEmpty(G.mon[1]) and anyGYMonster() and not necrovalleyActive() end,
  aiCanCast =function() return firstEmpty(G.mon[2]) and anyGYMonster() and not necrovalleyActive() end,
  activate=function(opts) pickMonsterRebornTarget(opts.col,opts.card,opts.zone) end,
  resolve=function(plr)  -- AI path: revive the strongest monster available
   if necrovalleyActive() then return end  -- effect negated by Necrovalley
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
    fireSummonHook(m,plr)
   end
  end,
 },

 -- =============== TRAPS ===============
 mirrorforce={
  responseOnly=true,
  -- Only responds to an attack declared by the controller's OPPONENT.
  triggers={attack=function(t,ctx,controller) return ctx and ctx.actor~=controller end},
  resolve=function(plr)
   -- Cancel the original attack continuation (legacy "consumed" mechanism).
   if G.trapSelect then G.trapSelect.consumed=true end
   G.battleAnim=nil
   local opp=3-plr
   for i=1,3 do
    local m=G.mon[opp][i]
    if m and m.pos==1 and not m.facedown then sendMonsterToGY(opp,i,"effect") end
   end
   flushTriggers()
  end,
 },
 traphole={
  responseOnly=true,
  -- Only responds to a summon by the controller's OPPONENT.
  triggers={summon=function(t,ctx,controller)
   return ctx and ctx.actor~=controller
          and not ctx.card.facedown and (ctx.card.atk or 0)>=1000
  end},
  resolve=function(plr,ctx)
   if not ctx then return end
   local opp=3-plr
   if G.mon[opp][ctx.monIdx]==ctx.card then
    sendMonsterToGY(opp,ctx.monIdx,"effect")
    flushTriggers()
   end
  end,
 },
 callhaunted={
  -- Continuous Trap. Manual activation from menu OR chain-response window.
  triggers={
   attack=function(t,ctx) return canReviveMonster(1) end,
   phase =function(t,ctx) return canReviveMonster(1) end,
  },
  canActivate=function(card) return canReviveMonster(1) end,
  activate=function(opts)
   if opts.plr==2 then
    -- AI path: pick best GY monster, resolve inline (no UI).
    activateAITrapAnim(opts.col,opts.card,function()
     aiResolveCallHaunted(opts.col,opts.card); checkWin()
    end)
   else
    pickCallHauntedTargetThenActivate(opts.col,opts.card,opts.trigCtx)
   end
  end,
 },
 magicjammer={
  responseOnly=true,
  triggers={
   chain_open=function(t,ctx)
    if not G.chain or #G.chain.links==0 then return false end
    local top=G.chain.links[#G.chain.links]
    if not (top.source and top.source.cat=="spell") then return false end
    return #G.hand[1]>=1
   end,
  },
  activate=function(opts) pickJammerCostThenActivate(opts.col,opts.card,opts.trigCtx) end,
 },
 gravitybind={
  -- Continuous Trap: Level 4+ monsters on EITHER side cannot declare an
  -- attack. The effect is purely the static flag (no resolve) — it takes
  -- hold the moment the card flips face-up. Activatable from the menu like
  -- any Set trap, or as a chain response at the start of the opponent's
  -- Battle Phase (the phase event whose toPhase is PH_BATTLE), so it locks
  -- down their attacks before any are declared. Negated by Jinzo via
  -- staticActive's trap guard.
  static={gravityBind=true},
  triggers={phase=function(t,ctx) return ctx and ctx.toPhase==PH_BATTLE end},
 },

 -- =============== MONSTERS ===============
 kuriboh={
  speed=2,
  handTrap=function(plr,dmg,handIdx,card)
   if plr==1 then
    G.mode="trap_ask"
    G.trapAsk={fromHand=true,handIdx=handIdx,card=card,
     onYes=function() end,
     onNo =function() changeLp(1,-dmg) end}
   else
    -- AI uses Kuriboh: discard it, then flash a banner. The opponent's hand is
    -- face-down, so without this the negated damage just looks like a glitch.
    discardFromHand(2,handIdx,"effect")
    local msg=card.name:upper()..": NO DAMAGE"
    local w=#msg*4+8
    local bx=FA_X+(FA_W-w)//2
    local by=DIV_Y-4
    addAnim(90,function()
     rect(bx,by,w,9,CCR)
     rectb(bx,by,w,9,CT)
     print(msg,bx+4,by+2,CT,true,1,true)
    end)
   end
  end,
 },
 sangan={
  onDestroy=function(card,plr)
   local items={}
   for i,id in ipairs(G.deck[plr]) do
    local d=CARDS[id]
    if (d.cat or "monster")=="monster" and d.atk and d.atk<=1500 then
     table.insert(items,{deckIdx=i,name=d.name,atk=d.atk,def=d.def,lvl=d.lvl,desc=d.desc})
    end
   end
   if #items==0 then return end
   if plr==2 then
    local bestAtk,bestI=-1,nil
    for _,item in ipairs(items) do
     if item.atk>bestAtk then bestAtk=item.atk; bestI=item.deckIdx end
    end
    if bestI and #G.hand[2]<MAX_HAND then
     table.insert(G.hand[2],makeCard(table.remove(G.deck[2],bestI)))
    end
   else
    G.mode="sel_deck"
    G.deckSel={items=items,sel=1,title="SANGAN  ATK<=1500",
     onPick=function(deckIdx)
      if #G.hand[1]<MAX_HAND then
       table.insert(G.hand[1],makeCard(table.remove(G.deck[1],deckIdx)))
      end
     end}
   end
  end,
 },
 maneater={
  onFlip=function(card,plr)
   local function destroyTarget(tp,ti)
    if not G.mon[tp][ti] then return end
    revealAndDestroyMon(tp,ti,"effect")
    flushTriggers()
   end
   if not (hasMonsters(1) or hasMonsters(2)) then return end
   if plr==2 then
    local best,bestI=-1,nil
    for i=1,3 do
     local m=G.mon[1][i]
     if m then
      local s=(m.pos==1 and not m.facedown) and m.atk or m.def
      if s>best then best=s; bestI=i end
     end
    end
    if bestI then destroyTarget(1,bestI)
    else
     local i=firstOccupied(G.mon[2]); if i then destroyTarget(2,i) end
    end
   else
    G.mode="sel_destroy"
    G.destroySel={onPick=destroyTarget}
    if hasMonsters(2) then
     G.cur={side=2,row=1,col=4-firstOccupied(G.mon[2])}
    else
     G.cur={side=1,row=1,col=firstOccupied(G.mon[1]) or 2}
    end
   end
  end,
 },
 legion={
  onDestroy=function(card,plr) if plr==1 then legionSearch() end end,
  onTributed=function(card,plr)
   if plr==1 and not G.legionSearchUsed then G.legionSearchPending=true end
  end,
 },
 ufoturtle={
  onDestroy=function(card,plr)
   local items={}
   for i,id in ipairs(G.deck[plr]) do
    local d=CARDS[id]
    if (d.cat or "monster")=="monster" and d.attr=="fire" then
     table.insert(items,{deckIdx=i,name=d.name,atk=d.atk,def=d.def,lvl=d.lvl,desc=d.desc})
    end
   end
   if #items==0 then return end
   if not firstEmpty(G.mon[plr]) then return end
   if plr==2 then
    local bestAtk,bestI=-1,nil
    for _,item in ipairs(items) do
     if item.atk>bestAtk then bestAtk=item.atk; bestI=item.deckIdx end
    end
    if bestI then
     local emptyCol=firstEmpty(G.mon[2])
     local m=makeCard(table.remove(G.deck[2],bestI))
     m.pos=1; m.facedown=false; m.attacked=false; m.summoned=true; m.posChanged=false
     G.mon[2][emptyCol]=m
     fireSummonHook(m,2)
    end
   else
    G.mode="sel_deck"
    G.deckSel={items=items,sel=1,title="UFO TURTLE  FIRE",
     onPick=function(deckIdx)
      if firstEmpty(G.mon[1]) then
       local m=makeCard(table.remove(G.deck[1],deckIdx))
       G.pendingSS={card=m,plr=1}
       -- forced: B can't cancel, else the pulled monster would be lost.
       G.menu={open=true,sel=1,forced=true,items={{"ATK POSITION","ss_atk"},{"DEF POSITION","ss_def"}}}
      end
     end}
   end
  end,
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
  onFlip=function(card,plr) animFlashFaceDown() end,
 },
 doublecoston={
  -- Counts as 2 Tributes for the Tribute Summon of a DARK monster.
  tributeValue=function(m,summonCard)
   return (summonCard and summonCard.attr=="dark") and 2 or nil
  end,
 },
 jinzo={
  -- Continuous: while face-up, Trap Cards cannot be activated. Declared as a
  -- static capability; enforced generically via staticActive("blocksTraps")
  -- (see its call sites in trapCanRespond / buildMenu).
  static={blocksTraps=true},
 },
 gkcurse={
  -- Each time summoned (Normal or Special), burn the opponent for 800.
  onSummon=function(card,plr) changeLp(3-plr,-800) end,
 },
 gkassailant={
  -- When this monster declares an attack while Necrovalley is on the field,
  -- the player may change the battle position of 1 opponent monster first.
  -- Opens a forced EFFECT/NORMAL menu; the assail_* keys (execAction) finish
  -- the flow and call resumeAttack() to continue the declared attack.
  onAttackDeclared=function(card,plr,resume)
   if plr~=1 or not (necrovalleyActive() and hasMonsters(2)) then
    resume(); return
   end
   G.mode="free"
   G.attackResume=resume
   G.menu={open=true,sel=1,forced=true,items={
    {"EFFECT","assail_yes"},
    {"NORMAL","assail_no"},
   }}
  end,
 },
 gkspy={
  -- FLIP: Special Summon 1 "Gravekeeper's" monster from the Deck.
  onFlip=function(card,plr)
   if not firstEmpty(G.mon[plr]) then return end
   local items={}
   for i,id in ipairs(G.deck[plr]) do
    local d=CARDS[id]
    if (d.cat or "monster")=="monster" and isGravekeeper(d) and (d.atk or 0)<=1500 then
     table.insert(items,{deckIdx=i,name=d.name,atk=d.atk,def=d.def,lvl=d.lvl,desc=d.desc})
    end
   end
   if #items==0 then return end
   if plr==2 then
    local bestAtk,bestI=-1,nil
    for _,item in ipairs(items) do
     if item.atk>bestAtk then bestAtk=item.atk; bestI=item.deckIdx end
    end
    if bestI then
     local emptyCol=firstEmpty(G.mon[2])
     local m=makeCard(table.remove(G.deck[2],bestI))
     m.pos=1; m.facedown=false; m.attacked=false; m.summoned=true; m.posChanged=false
     G.mon[2][emptyCol]=m
     fireSummonHook(m,2)
    end
   else
    G.mode="sel_deck"
    G.deckSel={items=items,sel=1,title="GRAVEKEEPER'S SPY",
     onPick=function(deckIdx)
      if firstEmpty(G.mon[1]) then
       local m=makeCard(table.remove(G.deck[1],deckIdx))
       G.pendingSS={card=m,plr=1}
       -- forced: B can't cancel, else the pulled monster would be lost.
       G.menu={open=true,sel=1,forced=true,items={{"ATK POSITION","ss_atk"},{"DEF POSITION","ss_def"}}}
      end
     end}
   end
  end,
 },
 necrovalley={
  -- Field Spell. Lives in the FS zone (G.fs). Two static effects, neither
  -- needs a resolve action:
  --  1. +500 ATK/DEF to all "Gravekeeper's" monsters -> applied in
  --     getMonAtk/getMonDef via necrovalleyActive().
  --  2. Negate effects that move a card out of a GY -> gates Monster Reborn
  --     (canActivate/aiCanCast) and Call of Haunted (canReviveMonster), and
  --     hides GY picks in legionSearch.
  aiCanCast=function() return true end,
  resolve=function() end,
 },
 gkshaman={
  -- DEF bonus: +200 for each GK monster in either GY.
  defBonus=function(card)
   local n=0
   for p=1,2 do for _,c in ipairs(G.gy[p]) do
    if isGravekeeper(c) then n=n+200 end
   end end
   return n
  end,
 },
 catillomen={
  -- FLIP: place a trap from deck on top of deck (or hand if Necrovalley active).
  onFlip=function(card,plr)
   local items={}
   for i,id in ipairs(G.deck[plr]) do
    local d=CARDS[id]
    if d.cat=="trap" then
     table.insert(items,{deckIdx=i,name=d.name,desc=d.desc})
    end
   end
   if #items==0 then return end
   if plr==2 then
    -- AI: pick the first trap found
    local bestI=items[1].deckIdx
    local slug=table.remove(G.deck[2],bestI)
    if necrovalleyActive() then
     table.insert(G.hand[2],makeCard(slug))
    else
     table.insert(G.deck[2],slug)  -- back on top (end = top)
    end
   else
    local title=necrovalleyActive() and "CAT: ADD TRAP TO HAND" or "CAT: TRAP ON TOP OF DECK"
    G.mode="sel_deck"
    G.deckSel={items=items,sel=1,title=title,
     onPick=function(deckIdx)
      local slug=table.remove(G.deck[1],deckIdx)
      if necrovalleyActive() then
       table.insert(G.hand[1],makeCard(slug))
      else
       table.insert(G.deck[1],slug)  -- append to end = top of deck
      end
     end}
   end
  end,
 },
 gkstele={
  canActivate=function()
   for _,c in ipairs(G.gy[1]) do if isGravekeeper(c) then return true end end
   return false
  end,
  aiCanCast=function()
   local n=0
   for _,c in ipairs(G.gy[2]) do if isGravekeeper(c) then n=n+1 end end
   return n>=1
  end,
  resolve=function(plr)
   -- Build list of GK monsters in GY
   local function gyItems(p)
    local items={}
    for i,c in ipairs(G.gy[p]) do
     if isGravekeeper(c) then
      table.insert(items,{deckIdx=i,name=c.name,atk=c.atk,def=c.def,lvl=c.lvl,desc=c.desc})
     end
    end
    return items
   end
   if plr==2 then
    -- AI: take up to 2 GKs from GY (highest ATK first)
    local picked=0
    while picked<2 do
     local items=gyItems(2); if #items==0 then break end
     table.sort(items,function(a,b) return (a.atk or 0)>(b.atk or 0) end)
     local slug=table.remove(G.gy[2],items[1].deckIdx)
     table.insert(G.hand[2],slug)
     picked=picked+1
    end
   else
    -- Player picks first card; onPick opens a second sel_deck for the second pick
    local function openPick(picksLeft)
     local items=gyItems(1)
     if #items==0 or picksLeft<=0 then return end
     G.mode="sel_deck"
     G.deckSel={items=items,sel=1,title="STELE: PICK GK ("..picksLeft.." LEFT)",
      onPick=function(gyIdx)
       local slug=table.remove(G.gy[1],gyIdx)
       table.insert(G.hand[1],slug)
       openPick(picksLeft-1)
      end}
    end
    openPick(2)
   end
  end,
 },
 gkoracle={
  -- A "Gravekeeper's" monster counts as 3 Tributes toward summoning this card.
  tributeValue=function(m) return isGravekeeper(m) and 3 or nil end,
  -- Capture how many "Gravekeeper's" were tributed (and their total level) at
  -- Tribute Summon time -- the onSummon picker below needs it.
  onTributeSummon=function(card,plr,tributed)
   local gkN,lvlS=0,0
   for _,m in ipairs(tributed) do
    lvlS=lvlS+(m.lvl or 0)
    if isGravekeeper(m) then gkN=gkN+1 end
   end
   G.oracleTribData={gkCount=gkN,lvlSum=lvlS}
  end,
  -- Tribute Summon trigger: open effect picker for player; auto-resolve for AI.
  onSummon=function(card,plr)
   local td=G.oracleTribData or {gkCount=0,lvlSum=0}
   G.oracleTribData=nil
   if td.gkCount==0 then return end
   if plr==1 then
    openOraclePick({card=card,plr=plr,remaining=td.gkCount,lvlSum=td.lvlSum,used={}})
   else
    -- AI: always activate effects in order E3 → E2 → E1
    local order,used={3,2,1},{}
    for _,eff in ipairs(order) do
     if td.gkCount<=0 then break end
     if eff==1 then card.atkMod=(card.atkMod or 0)+td.lvlSum*100
     elseif eff==2 then
      for i=1,3 do
       if G.mon[1][i] and G.mon[1][i].facedown then revealAndDestroyMon(1,i,"effect") end
      end
      flushTriggers()
     elseif eff==3 then
      for i=1,3 do
       local m=G.mon[1][i]
       if m then
        m.atkMod=(m.atkMod or 0)-2000
        m.defMod=(m.defMod or 0)-2000
       end
      end
     end
     td.gkCount=td.gkCount-1
    end
   end
  end,
 },
}

