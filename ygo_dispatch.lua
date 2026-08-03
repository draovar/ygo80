-- [ygo_dispatch] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- BEHAVIOR DISPATCH
-- ============================================================
function behaviorOf(card) return card and card.effect and BEHAVIORS[card.effect] end

-- Run a card's chain-link resolve function (does nothing if no behavior).
-- Defaults ctx to {source=card} when nil — cards (e.g. Swords of Revealing
-- Light setting swordsCounter on its own card) can rely on ctx.source being
-- the resolving card without callers having to populate it.
function applyResolve(card,plr,ctx)
 local b=behaviorOf(card)
 if b and b.resolve then b.resolve(plr, ctx or {source=card}) end
end

-- Helper: does `plr` have a monster in GY and a free zone to revive into?
function canReviveMonster(plr)
 if staticActive("blocksGYMoves") then return false end
 if not firstEmpty(G.mon[plr]) then return false end
 for _,c in ipairs(G.gy[plr]) do if c.cat=="monster" then return true end end
 return false
end

-- True if `plr` controls a monster named "Dark Magician" (Thousand Knives).
function controlsDarkMagician(plr)
 for c=1,3 do
  local m=G.mon[plr][c]
  if m and m.name=="Dark Magician" then return true end
 end
 return false
end

function controlsDragon(plr)
 for c=1,3 do
  local m=G.mon[plr][c]
  if m and m.type=="dragon" and not m.facedown then return true end
 end
 return false
end

-- Raw field scan: true if any face-up card grants `flag`. `plr` restricts to
-- one side; `skipTraps` excludes face-up Trap cards. No negation logic here —
-- staticActive layers that on top.
-- Static values may be either `true` (unconditional) or a function that
-- returns truthy when the flag should be active (gkshaman's blocksFieldSpells
-- only kicks in while Necrovalley is up).
local function scanStatic(flag,plr,skipTraps)
 local function check(card)
  if not card or card.facedown then return false end
  if skipTraps and card.cat=="trap" then return false end
  local b=behaviorOf(card)
  if not (b and b.static) then return false end
  local v=b.static[flag]
  if type(v)=="function" then v=v(card) end
  return v and true or false
 end
 for p=(plr or 1),(plr or 2) do
  for c=1,3 do
   if check(G.mon[p][c]) or check(G.st[p][c]) then return true end
  end
  if check(G.fs[p]) then return true end
 end
 return false
end

-- A "static" capability is a continuous ability a card grants while it sits
-- face-up on the field. Cards declare these in BEHAVIORS as static={flag=true};
-- the engine queries them generically here instead of hardcoding card names.
-- Returns true if any face-up card grants `flag`; pass `plr` to scan one side.
-- Jinzo (blocksTraps) negates the effects of face-up Trap Cards, so a
-- continuous trap's static capability is excluded from the scan while Jinzo is
-- up. The blocksTraps probe scans monsters anyway, so there is no recursion.
function staticActive(flag,plr)
 local trapsNegated = flag~="blocksTraps" and scanStatic("blocksTraps")
 return scanStatic(flag,plr,trapsNegated)
end

-- Targeting protection: face-up Dragons are immune while Lord of D. is face-up
-- (dragonProtect). Face-down monsters have no known type and are targetable.
function canTargetMon(card)
 if not card then return false end
 if not card.facedown and card.type=="dragon" and staticActive("dragonProtect") then
  return false
 end
 return true
end

function hasTargetableMon(plr)
 for c=1,3 do if canTargetMon(G.mon[plr][c]) then return true end end
 return false
end

-- True if either graveyard holds a monster (Monster Reborn target check).
function anyGYMonster()
 for p=1,2 do
  for _,c in ipairs(G.gy[p]) do if c.cat=="monster" then return true end end
 end
 return false
end

-- True if monster `card` controlled by `plr` cannot declare an attack: the
-- opponent controls a face-up Swords of Revealing Light, or a face-up Gravity
-- Bind (either side) locks down monsters of Level 4 or higher.
function attackBlocked(card,plr)
 if staticActive("blocksAttack",3-plr) then return true end
 if getMonLvl(card)>=4 and staticActive("gravityBind") then return true end
 return false
end

-- True if `card` (controlled by `ctrl`) is currently immune to destruction by
-- battle. Consults the monster's `battleImmune` behavior hook, which may
-- condition on whose turn it is (Rocket Warrior: only during ctrl's own turn).
function battleIndestructible(card,ctrl)
 local b=behaviorOf(card)
 return (b and b.battleImmune and b.battleImmune(card,ctrl)) or false
end

-- True if battles involving `card` deal no battle damage to its controller
-- `ctrl`. Consults the monster's `noBattleDamage` behavior hook.
function battleDamageImmune(card,ctrl)
 local b=behaviorOf(card)
 return (b and b.noBattleDamage and b.noBattleDamage(card,ctrl)) or false
end

-- Fusion-summon helpers (Polymerization). Materials are matched by card ID
-- (CARDS key) via the `id` field set by makeCard. Counts own hand + own
-- monster zones (face-up OR face-down) as eligible sources. Face-down own
-- monsters are visible to their controller, so using them as material is
-- legal (and doesn't flip them — they go straight to GY).
function fusionMaterialsAvailable(fusion,plr)
 if not (fusion and fusion.materials) then return false end
 local need={}
 for _,nm in ipairs(fusion.materials) do need[nm]=(need[nm] or 0)+1 end
 local have={}
 for _,c in ipairs(G.hand[plr]) do
  if c.cat=="monster" and c.id then have[c.id]=(have[c.id] or 0)+1 end
 end
 for col=1,3 do
  local m=G.mon[plr][col]
  if m and m.cat=="monster" and m.id then have[m.id]=(have[m.id] or 0)+1 end
 end
 for nm,n in pairs(need) do
  if (have[nm] or 0)<n then return false end
 end
 return true
end

-- Returns the list of indices into G.extra[plr] for Fusion Monsters whose
-- materials are all currently available in plr's hand + face-up field.
function polyValidTargets(plr)
 local out={}
 for i,c in ipairs(G.extra[plr] or {}) do
  if c.cat=="monster" and c.subtype=="fusion" and fusionMaterialsAvailable(c,plr) then
   out[#out+1]=i
  end
 end
 return out
end

-- Spinning-sword "tribute" animation over the picked Polymerization materials,
-- visually matching the tribute-summon anim. Blocks via waitAnim, so call this
-- inside a procActivate resolveFn (works for both player and AI paths since
-- they share the same coroutine context at chain resolution). `picks` is the
-- list of {kind="hand"|"field", hi=<handIdx> | fc=<fieldCol>} captured during
-- material selection. Field materials animate over the monster row, hand
-- materials over the hand row.
function playMaterialTributeAnim(plr,picks)
 local zones={}
 local hand=G.hand[plr]
 local fieldY=(plr==1) and PY_M or OY_M
 local handY =(plr==1) and PY_H or OY_H
 for _,p in ipairs(picks) do
  if p.kind=="field" then
   local x=(plr==1) and COL[p.fc] or COL[4-p.fc]
   zones[#zones+1]={x=x,y=fieldY}
  else
   local x=handX(#hand,p.hi-1)
   zones[#zones+1]={x=x,y=handY}
  end
 end
 if #zones==0 then return end
 waitAnim(playAnim(45,function(t,f)
  local rot=(4-(t//8)%4)%4
  for _,z in ipairs(zones) do
   spr(SPR_FUSE,z.x+3,z.y+3,0,1,0,rot,2,2)
  end
 end))
end

-- Decrement Swords of Revealing Light counters at an End Phase. Swords belongs
-- to the opponent of the player whose turn is ending; destroyed after that
-- opponent's 3rd End Phase. Call this before G.active flips.
function tickSwords()
 local controller=3-G.active
 for c=1,3 do
  local s=G.st[controller][c]
  if s and not s.facedown and s.effect=="swords" and s.swordsCounter then
   s.swordsCounter=s.swordsCounter-1
   if s.swordsCounter<=0 then sendSpellTrapToGY(controller,c,"rule") end
  end
 end
end

-- True if `card` belongs to the "Gravekeeper's" archetype (name prefix match).
function isGravekeeper(card)
 return card and card.name and card.name:sub(1,13)=="Gravekeeper's"
end


-- Gravekeeper's Oracle: pick up to `n` of the three effects, one per loop,
-- each usable once. Runs as a coroutine — choose() yields until the player
-- picks; the AI takes them highest-impact first (E3 → E2 → E1).
function oraclePickLoop(card,plr,n,lvlSum)
 local opp=3-plr
 local used={}
 while n>0 do
  local items={}
  if not used[1] then items[#items+1]={"add "..lvlSum*100 .." ATK","e1"} end
  if not used[2] then items[#items+1]={"dstry set mons","e2"} end
  if not used[3] then items[#items+1]={"opp -2000 stats","e3"} end
  items[#items+1]={"DONE","done"}
  local key=choose{
   kind="menu",plr=plr,items=items,
   aiPick=function(req)
    for _,want in ipairs({"e3","e2","e1"}) do
     for _,it in ipairs(req.items) do if it[2]==want then return want end end
    end
    return "done"
   end,
  }
  if not key or key=="done" then return end
  local eff=({e1=1,e2=2,e3=3})[key]
  used[eff]=true
  if eff==1 then
   card.atkMod=(card.atkMod or 0)+lvlSum*100
  elseif eff==2 then
   for i=1,3 do
    if G.mon[opp][i] and G.mon[opp][i].facedown then
     revealAndDestroyMon(opp,i,"effect")
    end
   end
   checkEquips()
  else
   for i=1,3 do
    local m=G.mon[opp][i]
    if m then
     m.atkMod=(m.atkMod or 0)-2000
     m.defMod=(m.defMod or 0)-2000
    end
   end
  end
  n=n-1
 end
end

-- Call of the Haunted's revive body. Shared by activate + listens.ATTACK
-- and listens.PHASE. Runs as a coroutine — choose() yields
-- until the player picks (or AI auto-resolves via aiAnswer's aiPickCard).
-- self = listener self {card=trap,plr,controller,zone="st",col}.
function cohSpecialSummon(self)
 local plr=self.plr
 local target=choose{
  kind="card",from="gy",plr=plr,
  filter=function(c) return c.cat=="monster" end,
  title="CALL OF THE HAUNTED",
 }
 if not target then return end
 local emptyCol=firstEmpty(G.mon[plr])
 if not emptyCol then return end
 local m=G.gy[plr][target.idx]
 if not (m and m.cat=="monster") then return end
 table.remove(G.gy[plr],target.idx)
 m.pos=1; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
 G.mon[plr][emptyCol]=m
 self.card.linkedMon=m; m.linkedTrap=self.card
 summonEvent(m,plr,emptyCol,"special",nil)
end

