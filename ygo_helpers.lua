-- [ygo_helpers] YGO80 module -- loaded via require() from ygo80.lua


function shuffle(t)
 for i=#t,2,-1 do
  local j=math.random(i); t[i],t[j]=t[j],t[i]
 end
 return t
end

function makeCard(id)
 local d=CARDS[id]
 return {name=d.name,atk=d.atk,def=d.def,lvl=d.lvl,pos=1,spr=d.spr,bg=d.bg,
         cat=d.cat or "monster",attr=d.attr,type=d.type,subtype=d.subtype,effect=d.effect,desc=d.desc}
end

function printWrap(text,x,y,maxW,col,maxY)
 local chW=4; local lineH=7; local maxCh=math.floor(maxW/chW)
 while #text>0 do
  if maxY and y+lineH>maxY then return y end
  if #text<=maxCh then print(text,x,y,col,true,1,true); return y+lineH end
  local cut=maxCh
  while cut>1 and text:sub(cut,cut)~=" " do cut=cut-1 end
  if cut<=1 then cut=maxCh end
  print(text:sub(1,cut),x,y,col,true,1,true)
  text=text:sub(cut+1); y=y+lineH
 end
 return y
end

-- Tributes required to normal-summon a monster of given level
function tribsNeeded(lvl)
 return (lvl<=4) and 0 or (lvl<=6) and 1 or (lvl<=8) and 2 or 3
end

-- Tribute worth of monster `m` toward summoning `summonCard`. Defaults to 1;
-- cards override via a BEHAVIORS `tributeValue` hook -- checked on the tributed
-- monster first (Double Coston), then on the summon card (Gravekeeper's
-- Oracle). A nil monster is worth 0.
function tributeValueOf(summonCard,m)
 if not m then return 0 end
 local mb=behaviorOf(m)
 if mb and mb.tributeValue then
  local v=mb.tributeValue(m,summonCard)
  if v then return v end
 end
 local sb=behaviorOf(summonCard)
 if sb and sb.tributeValue then
  local v=sb.tributeValue(m,summonCard)
  if v then return v end
 end
 return 1
end

-- Total tribute worth of the columns currently selected in G.pending.tributes.
function tributeTotal(p)
 local n=0
 for _,col in ipairs(p.tributes) do n=n+tributeValueOf(p.card,G.mon[1][col]) end
 return n
end

-- Total tribute worth of all of `plr`'s monsters, for summoning `summonCard`.
function fieldTributeValue(summonCard,plr)
 local n=0
 for c=1,3 do n=n+tributeValueOf(summonCard,G.mon[plr][c]) end
 return n
end

-- AI: pick which monster columns to tribute for `summonCard` (needs `trib`
-- tributes). Prefers a lone monster that covers the whole cost (Double Coston
-- for a DARK Tribute Summon); otherwise sacrifices the weakest monsters.
function aiPickTributes(summonCard,occupied,trib)
 if trib>=2 then
  for _,col in ipairs(occupied) do
   if tributeValueOf(summonCard,G.mon[2][col])>=trib then return {col} end
  end
 end
 local sorted={}
 for _,c in ipairs(occupied) do table.insert(sorted,c) end
 table.sort(sorted,function(a,b) return G.mon[2][a].atk<G.mon[2][b].atk end)
 local tribs,val={},0
 for _,col in ipairs(sorted) do
  table.insert(tribs,col)
  val=val+tributeValueOf(summonCard,G.mon[2][col])
  if val>=trib then break end
 end
 return tribs
end

-- Returns the first card on player's monster row (truthy if any present)
function hasMonsters(plr)
 return G.mon[plr][1] or G.mon[plr][2] or G.mon[plr][3]
end

-- Shallow copy of a card table
function copyCard(card)
 local c={}
 for k,v in pairs(card) do c[k]=v end
 return c
end

-- Scans all spell zones for face-up equip cards targeting `card` (by identity).
-- Returns total ATK bonus, total DEF bonus.
-- Memoized per (card, G.statsGen): cleared whenever bumpStats() runs.
function getEquipBonus(card)
 local gen=G.statsGen or 0
 if card._eqGen==gen then return card._eqA, card._eqD end
 local ab,db=0,0
 for p=1,2 do for c=1,3 do
  local eq=G.st[p][c]
  if eq and not eq.facedown and eq.subtype=="equip" and eq.equippedTo then
   local tp,tc=eq.equippedTo.plr,eq.equippedTo.col
   if G.mon[tp] and G.mon[tp][tc]==card then
    local b=behaviorOf(eq)
    if b and b.equipBonus then
     local a,d=b.equipBonus(card,eq); ab=ab+a; db=db+d
    end
   end
  end
 end end
 card._eqGen, card._eqA, card._eqD = gen, ab, db
 return ab,db
end

-- Bumps the field-state generation, invalidating every card's cached equip
-- bonus (and any future stat caches keyed on G.statsGen). Cheap: one integer
-- increment. Call from any helper that changes which monsters are on the
-- field, what's face-up vs face-down, or what equips point where.
function bumpStats() G.statsGen=(G.statsGen or 0)+1 end

-- Returns effective ATK: base + per-card bonus + equips + Necrovalley + the
-- card.atkMod term. atkMod is a running total of stat changes from effects
-- (e.g. Gravekeeper's Oracle); effects adjust atkMod, never the base card.atk.
function getMonAtk(card)
 local bonus=0
 local b=behaviorOf(card)
 if b and b.atkBonus then bonus=b.atkBonus(card) end
 local ab,_=getEquipBonus(card)
 local nv=(isGravekeeper(card) and necrovalleyActive()) and 500 or 0
 return math.max(0, card.atk+bonus+ab+nv+(card.atkMod or 0))
end

-- Returns effective DEF (see getMonAtk; card.defMod is the effect-modifier term).
function getMonDef(card)
 local bonus=0
 local b=behaviorOf(card)
 if b and b.defBonus then bonus=b.defBonus(card) end
 local _,db=getEquipBonus(card)
 local nv=(isGravekeeper(card) and necrovalleyActive()) and 500 or 0
 return math.max(0, card.def+bonus+db+nv+(card.defMod or 0))
end

-- Destroys any face-up equip cards whose target is gone or face-down.
function checkEquips()
 for p=1,2 do
  for c=1,3 do
   local eq=G.st[p][c]
   if eq and not eq.facedown and eq.subtype=="equip" and eq.equippedTo then
    local tp,tc=eq.equippedTo.plr,eq.equippedTo.col
    local target=G.mon[tp] and G.mon[tp][tc]
    if not target or target.facedown then
     sendSpellTrapToGY(p,c,"rule")
    end
   end
  end
 end
end

-- First index 1..3 where arr[i] is nil (or nil if none)
function firstEmpty(arr)
 for i=1,3 do if not arr[i] then return i end end
end

-- First index 1..3 where arr[i] is non-nil (or nil if none)
function firstOccupied(arr)
 for i=1,3 do if arr[i] then return i end end
end

-- Sword slash animation from (ax,ay) to (tx,ty); onDone fires when finished.
function animSwordSlash(ax,ay,tx,ty,onDone)
 local sp,sf,sr=swordParams(tx-ax,ty-ay)
 addAnim(18,function(t,f)
  local p=1-t/f
  spr(sp,ax+(tx-ax)*p,ay+(ty-ay)*p,0,1,sf,sr,2,2)
 end,onDone)
end

-- Spinning sword above each zone in `zones` (list of {x=,y=}); onDone after 30 frames.
function animTribute(zones,onDone)
 addAnim(30,function(t,f)
  local rot=(4-(t//8)%4)%4
  for _,z in ipairs(zones) do
   spr(SPR_SWORD,z.x+3,z.y+3,0,1,0,rot,2,2)
  end
 end,onDone)
end

-- The Stern Mystic FLIP: briefly reveal every face-down card on the field by
-- drawing each card's face (with a blinking border) on top of its zone.
function animFlashFaceDown()
 local list={}
 for p=1,2 do
  local zc=(p==1) and CZ or COZ
  for c=1,3 do
   local m=G.mon[p][c]
   if m and m.facedown then
    local mx,my=zoneXY(p,"mon",c)
    table.insert(list,{card=m,kind="mon",zc=zc,x=mx,y=my})
   end
   local s=G.st[p][c]
   if s and s.facedown then
    local sx,sy=zoneXY(p,"st",c)
    table.insert(list,{card=s,kind="st",zc=zc,x=sx,y=sy})
   end
  end
 end
 if #list==0 then return end
 addAnim(90,function(t,f)
  for _,e in ipairs(list) do
   if e.kind=="st" then drawCardSpell(e.x,e.y,e.card,e.zc)
   elseif e.card.pos==2 then drawCardDef(e.x,e.y,e.card,e.zc)
   else drawCardAtk(e.x,e.y,e.card,e.zc) end
   if (t//6)%2==0 then rectb(e.x,e.y,ZW_MAIN,ZH,CT) end
  end
 end)
end

