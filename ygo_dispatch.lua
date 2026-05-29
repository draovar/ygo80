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


-- AI Call of the Haunted resolve: revive AI's highest-ATK GY monster.
-- Used by BEHAVIORS.callhaunted.activate when opts.plr==2 (AI manually
-- activates from menu). The chain-response path uses cohSpecialSummon below.
function aiResolveCallHaunted(stCol,trap)
 local best,bestI=-1,nil
 for i,c in ipairs(G.gy[2]) do
  if c.cat=="monster" and c.atk and c.atk>best then best=c.atk; bestI=i end
 end
 local emptyCol=firstEmpty(G.mon[2])
 if bestI and emptyCol then
  local m=table.remove(G.gy[2],bestI)
  m.pos=1; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
  G.mon[2][emptyCol]=m
  trap.linkedMon=m; m.linkedTrap=trap
  summonEvent(m,2,emptyCol,"special",nil)
 end
end

-- Call of the Haunted's react body. Shared by listens.ATTACK and
-- listens.PHASE. Runs as a coroutine — choose() yields
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

