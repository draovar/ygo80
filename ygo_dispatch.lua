-- [ygo_dispatch] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- BEHAVIOR DISPATCH
-- ============================================================
function behaviorOf(card) return card and card.effect and BEHAVIORS[card.effect] end

-- Run a card's chain-link resolve function (does nothing if no behavior).
function applyResolve(card,plr,ctx)
 local b=behaviorOf(card); if b and b.resolve then b.resolve(plr,ctx) end
end

-- Fire a monster event hook (onDestroy/onFlip/onTributed).
function fireMonHook(card,event,plr)
 local b=behaviorOf(card); if b and b[event] then b[event](card,plr) end
end

-- Helper: does `plr` have a monster in GY and a free zone to revive into?
function canReviveMonster(plr)
 if necrovalleyActive() then return false end  -- Necrovalley negates GY revival
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

-- Raw field scan: true if any face-up card grants `flag`. `plr` restricts to
-- one side; `skipTraps` excludes face-up Trap cards. No negation logic here —
-- staticActive layers that on top.
local function scanStatic(flag,plr,skipTraps)
 for p=(plr or 1),(plr or 2) do
  for c=1,3 do
   local m=G.mon[p][c]
   if m and not m.facedown then
    local b=behaviorOf(m)
    if b and b.static and b.static[flag] then return true end
   end
   local s=G.st[p][c]
   if s and not s.facedown and not (skipTraps and s.cat=="trap") then
    local b=behaviorOf(s)
    if b and b.static and b.static[flag] then return true end
   end
  end
  local f=G.fs[p]
  if f and not f.facedown then
   local b=behaviorOf(f)
   if b and b.static and b.static[flag] then return true end
  end
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
 if (card.lvl or 0)>=4 and staticActive("gravityBind") then return true end
 return false
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

-- True if a face-up "Necrovalley" occupies either player's field spell zone.
function necrovalleyActive()
 for p=1,2 do
  local f=G.fs[p]
  if f and not f.facedown and f.effect=="necrovalley" then return true end
 end
 return false
end

-- True if opponent `plr` is blocked from activating a field spell
-- (Shaman + Necrovalley both on the field).
function fieldSpellBlocked(plr)
 if not necrovalleyActive() then return false end
 for i=1,3 do
  local m=G.mon[3-plr][i]
  if m and not m.facedown and m.effect=="gkshaman" then return true end
 end
 return false
end

-- Fire a monster's onSummon hook. Call this at every Normal/Special Summon
-- placement site, immediately after the monster lands face-up on the field.
function fireSummonHook(card,plr)
 bumpStats()
 local b=behaviorOf(card)
 if b and b.onSummon then b.onSummon(card,plr) end
end

-- Fire a monster's onTributeSummon hook. Call from each Tribute Summon path
-- AFTER the tributes are chosen but BEFORE they are sent to the GY -- the hook
-- inspects the tributed monsters. `tribCols` = list of monster-zone columns.
function fireTributeSummonHook(card,plr,tribCols)
 local b=behaviorOf(card)
 if not (b and b.onTributeSummon) then return end
 local tributed={}
 for _,tcol in ipairs(tribCols) do
  local m=G.mon[plr][tcol]
  if m then tributed[#tributed+1]=m end
 end
 b.onTributeSummon(card,plr,tributed)
end

-- Fire an attacker's onAttackDeclared hook at attack-declaration time, before
-- the attack resolves. The hook MUST eventually call resume() to continue the
-- attack -- immediately for a synchronous effect, or later (via resumeAttack)
-- after an interactive flow. With no hook, resume() runs directly.
-- NOTE: wired into the player attack path only; the AI attack path does not
-- fire this yet (no AI-piloted card needs it).
function declareAttack(attacker,plr,resume)
 local b=behaviorOf(attacker)
 if b and b.onAttackDeclared then
  b.onAttackDeclared(attacker,plr,resume)
 else
  resume()
 end
end

-- Continue an attack that an onAttackDeclared hook paused for an interactive
-- flow. The hook stashes its resume callback in G.attackResume; the menu or
-- picker that finishes the flow calls this.
function resumeAttack()
 local r=G.attackResume
 G.attackResume=nil
 if r then r() end
end

-- Returns true if face-down trap `t` on the field can chain to `event`/`ctx`.
-- `controller` = player who owns trap `t` (1 or 2). Trigger functions use it
-- to verify the acting player (ctx.actor) is their opponent.
function trapCanRespond(t,event,ctx,controller)
 if not (t and t.facedown and not t.setThisTurn) then return false end
 if staticActive("blocksTraps") then return false end  -- Jinzo: Traps cannot be activated
 local b=behaviorOf(t); if not b or not b.triggers then return false end
 -- Event-trigger traps (Trap Hole, Mirror Force, Call of Haunted) respond
 -- directly to the triggering action, so they may only be activated as the
 -- FIRST link of the chain. Once a link exists they cannot be chained on
 -- (prevents chaining Trap Hole to Trap Hole / two Mirror Forces, and a
 -- trap responding to your own action via a later chain link).
 if not G.chain or #G.chain.links==0 then
  local fn=b.triggers[event]
  if fn and fn(t,ctx,controller) then return true end
 else
  -- chain_open responders (Magic Jammer) fire only once a link exists.
  local co=b.triggers.chain_open
  if co and co(t,ctx,controller) then return true end
 end
 return false
end

-- AI Call of the Haunted resolve: revive AI's highest-ATK GY monster.
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
  fireSummonHook(m,2)
 end
end

