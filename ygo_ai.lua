-- [ygo_ai] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- AI
-- ============================================================
AI_DELAY=40  -- frames between AI actions (~0.67s at 60fps)

function aiDoMain()
 -- Activate direct-damage / board-wipe spells (one per tick).
 -- A spell is castable iff its BEHAVIORS entry has aiCanCast(card) returning true.
 for i=#G.hand[2],1,-1 do
  local card=G.hand[2][i]
  if card.cat=="spell" then
   local b=behaviorOf(card)
   local doIt=b and b.aiCanCast and b.aiCanCast(card)
   if doIt then
    table.remove(G.hand[2],i)
    if card.subtype=="field" then
     if fieldSpellBlocked(2) then table.insert(G.hand[2],i,card); break end
     -- Field spell: straight to the FS zone, replacing any existing one.
     if G.fs[2] then sendFieldSpellToGY(2,"rule") end
     G.fs[2]=card
     animFieldSpellActivation(card,2)
    else
     local stIdx=nil
     for j=1,3 do if not G.st[2][j] then stIdx=j; break end end
     if stIdx then
      G.st[2][stIdx]=card
      animSpellActivation(stIdx,OY_S,card,2)
     else
      -- No S/T zone free: card resolves directly from hand to GY.
      addToGY(2,card,"effect")
      if not G.chain then openChain(nil,"spell") end
      pushChainLink({
       source=card, controller=2, speed=chainSpeed(card),
       sourceLoc=nil, targets=nil,
       resolveFn=function(self)
        applyResolve(self.source,self.controller,nil)
       end,
      })
      advanceChain()
     end
    end
    return true
   end
  end
 end
 -- Set one trap card face-down per tick
 local stEmpty=firstEmpty(G.st[2])
 if stEmpty then
  for i=#G.hand[2],1,-1 do
   local card=G.hand[2][i]
   if card.cat=="trap" then
    local c=copyCard(card)
    c.facedown=true; c.setThisTurn=true
    G.st[2][stEmpty]=c
    table.remove(G.hand[2],i)
    return true
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
   local trib=tribsNeeded(card.lvl or 1)
   local ok=(trib==0 and #empty>0)
         or (trib>=1 and #empty>0 and fieldTributeValue(card,2)>=trib)
   if ok and card.atk>bestAtk then bestAtk=card.atk; bestIdx=i end
  end
 end
 if not bestIdx then return false end
 local card=G.hand[2][bestIdx]
 local trib=tribsNeeded(card.lvl)
 -- Set face-down DEF when defense stat exceeds attack stat
 local useDefPos=(card.def or 0)>card.atk
 if trib>0 then
  local tribs=aiPickTributes(card,occupied,trib)
  table.remove(G.hand[2],bestIdx); G.normalSummoned=true
  local zones={}
  for _,tcol in ipairs(tribs) do
   table.insert(zones,{x=COL[4-tcol],y=OY_M})
  end
  animTribute(zones,function()
   fireTributeSummonHook(card,2,tribs)
   for _,tcol in ipairs(tribs) do
    sendMonsterToGY(2,tcol,"tribute")
   end
   local empI=firstEmpty(G.mon[2])
   card.summoned=true
   if useDefPos then card.pos=2; card.facedown=true end
   G.mon[2][empI]=card
   if not card.facedown then fireSummonHook(card,2) end
   checkTraps("summon",{card=card,monIdx=empI})
  end)
  return true
 end
 table.remove(G.hand[2],bestIdx)
 card.summoned=true
 if useDefPos then card.pos=2; card.facedown=true end
 G.mon[2][empty[1]]=card; G.normalSummoned=true
 if not card.facedown then fireSummonHook(card,2) end
 checkTraps("summon",{card=card,monIdx=empty[1]})
 return true
end

function aiResolveAttack(attacker,atkCol,target,tgtCol)
 attacker.attacked=true

 local ax=COL[4-atkCol]+ZW_MAIN//2-8
 local ay=OY_M+ZH//2-8
 local tx=COL[tgtCol]+ZW_MAIN//2-8
 local ty=PY_M+ZH//2-8
 local wasFlipped=target.facedown

 local function doSlash()
  animSwordSlash(ax,ay,tx,ty,function()
   local atkV=getMonAtk(attacker); local tgtV=getMonAtk(target); local tgtDef=getMonDef(target)
   if target.pos==2 then
    if atkV>tgtDef then
     sendMonsterToGY(1,tgtCol,"battle")
    elseif atkV<tgtDef then
     changeLp(2,-(target.def-atkV))
    end
   else
    if atkV>tgtV then
     sendMonsterToGY(1,tgtCol,"battle")
     applyDamage(1,atkV-tgtV)
    elseif atkV<tgtV then
     sendMonsterToGY(2,atkCol,"battle")
     changeLp(2,-(tgtV-atkV))
    else
     sendMonsterToGY(1,tgtCol,"battle")
     sendMonsterToGY(2,atkCol,"battle")
    end
   end
   G.battleAnim=nil
   checkWin()
   flushTriggers()
   if wasFlipped then fireMonHook(target,"onFlip",1) end
  end)
 end

 if wasFlipped then
  target.facedown=false
  local zx=COL[tgtCol]
  addAnim(24,function(t,f)
   if (t//4)%2==0 then rect(zx,PY_M,ZW_MAIN,ZH,CZ); rectb(zx,PY_M,ZW_MAIN,ZH,CT) end
  end,doSlash)
 else
  doSlash()
 end
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
   -- show declaration indicator for 30 frames, then open trap window
   G.battleAnim={atkCol=i,tgtCol=tgtCol}
   addAnim(30,function()end,function()
    local function doSword()
     -- re-evaluate target in case trap changed the field
     local hasPlrNow=hasMonsters(1)
     local tgtNow=hasPlrNow and aiBestTarget(att) or nil
     G.battleAnim={atkCol=i,tgtCol=tgtNow}
     if not hasPlrNow then
      local aax=COL[4-i]+ZW_MAIN//2-8; local aay=OY_M+ZH//2-8
      local dmg=getMonAtk(att); att.attacked=true
      animSwordSlash(aax,aay,FA_X+FA_W//2-8,PY_S+ZH//2-8,
       function() G.battleAnim=nil; applyDamage(1,dmg) end)
     elseif tgtNow then
      aiResolveAttack(att,i,G.mon[1][tgtNow],tgtNow)
     else
      G.battleAnim=nil; att.attacked=true  -- no profitable attack, skip
     end
    end
    if not checkTraps("attack",{att=att,atkCol=i,hasTarget=tgtCol~=nil,proceed=doSword}) then doSword() end
   end)
   return true
   end
  end
 end
 return false
end

function aiTick()
 if G.active~=2 or G.winner or #ANIM>0 or G.menu.open or G.infoCard or G.mode=="trap_ask" or G.mode=="sel_deck" or G.mode=="sel_destroy" or G.mode=="opp_trap_select" or G.mode=="sel_discard" or G.mode=="sel_st_target" then return end
 G.aiTimer=G.aiTimer-1
 if G.aiTimer>0 then return end
 G.aiTimer=AI_DELAY
 if G.ph==PH_DRAW then
  local function go() changePhase(PH_STBY) end
  if not checkTraps("phase",{proceed=go,toPhase=PH_STBY}) then go() end
 elseif G.ph==PH_STBY then
  local function go() changePhase(PH_MAIN) end
  if not checkTraps("phase",{proceed=go,toPhase=PH_MAIN}) then go() end
 elseif G.ph==PH_MAIN then
  if not aiDoMain() then
   local function go() G.aiBattleIdx=1; changePhase(PH_BATTLE) end
   if not checkTraps("phase",{proceed=go,toPhase=PH_BATTLE}) then go() end
  end
 elseif G.ph==PH_BATTLE then
  if not aiDoNextAttack() then
   local function go() changePhase(PH_END) end
   if not checkTraps("phase",{proceed=go,toPhase=PH_END}) then go() end
  end
 elseif G.ph==PH_END then
  tickSwords()
  G.turn=G.turn+1; G.active=1; changePhase(PH_DRAW)
  G.normalSummoned=false; drawCard(1); G.autoTimer=50
  resetTurnFlags()
 end
end

