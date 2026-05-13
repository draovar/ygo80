-- title:   YGO80
-- author:  draovar
-- desc:    Yu-gi-oh Speed duel for tic80
-- version: 0.1
-- script:  lua

-- ============================================================
-- LAYOUT
-- ============================================================
SW,SH=240,136

-- Zone heights (all rows same)
ZH=22

-- Zone widths by column type:
--   col 0 & 4 → special (GY/FS/ED/DK): 20px wide
--   col 1-3   → main (monster/spell): 22x22 square (fits defense position)
ZW_SPEC=20
ZW_MAIN=22
ZG=2  -- gap between columns

-- Panel / field split
PANEL_W=85         -- info panel (x=0..84)
SEP_X  =85         -- separator line x
FA_X   =86         -- field area start
FA_W   =154        -- field area width (240-86)

-- Field columns, centered in FA_W
-- total field width = 2*ZW_SPEC + 3*ZW_MAIN + 4*ZG = 40+66+8 = 114
-- margin = (154-114)//2 = 20
do
 local b=FA_X+20  -- =106, left edge of col 0
 COL={[0]=b,
      [1]=b+ZW_SPEC+ZG,
      [2]=b+ZW_SPEC+ZG+ZW_MAIN+ZG,
      [3]=b+ZW_SPEC+ZG+2*(ZW_MAIN+ZG),
      [4]=b+ZW_SPEC+ZG+3*(ZW_MAIN+ZG)}
end
-- COL = {106,128,152,176,200}  rightmost end = 200+20 = 220, right margin = 20 ✓

-- Column width helper
function colW(c) return (c==0 or c==4) and ZW_SPEC or ZW_MAIN end

-- Hand cards: both 20px wide; player full height, opponent half
HW   =20   -- width (matches ZW_SPEC)
PHH  =22   -- player  hand height (= ZH, full card)
OHH  =11   -- opponent hand height (half card, face-down)
HG   =1    -- gap between hand cards

MAX_HAND=7

-- Centered hand card X for index i given hand size n
function handX(n,i)
 local tw=n*HW+(n-1)*HG       -- total hand width
 local sx=FA_X+(FA_W-tw)//2   -- centered start
 return sx+i*(HW+HG)
end

-- Row Y positions
-- opp hand(11)+1+opp S(22)+1+opp M(22)+2+[div@60]+2+plr M(22)+1+plr S(22)+1+plr H(22) = ends 131, bottom=5px
OY_H =1    -- opp hand      h=OHH=11  ends y=11
OY_S =13   -- opp spells    h=ZH=22   ends y=34
OY_M =36   -- opp monsters  h=ZH=22   ends y=57
DIV_Y=60   -- divider line
PY_M =63   -- plr monsters  h=ZH=22   ends y=84
PY_S =86   -- plr spells    h=ZH=22   ends y=107
PY_H =109  -- plr hand      h=PHH=22  ends y=130

-- Colors (TIC-80 palette index 0-15; change any value here to retheme that element)
-- Backgrounds & chrome
CB   = 0   -- screen background, LP bar bg              (black)
CD   = 15  -- divider lines, panel borders              (white)
CT   = 15  -- general text                              (white)
CHL  = 7   -- UI row highlight, phase-bar bg, buttons   (grey)
-- Field zones
CZ   = 7   -- player zone tiles                         (grey)
COZ  = 7   -- opponent zone tiles                       (grey)
CGY  = 5   -- graveyard zone                            (dark navy)
CDK  = 8   -- deck zone                                 (brown)
CFS  = 3   -- field spell zone                          (dark green)
CED  = 2   -- extra deck zone                           (orange)
-- Card faces
CCA  = 9   -- normal monster face                       (tan)
CME  = 2   -- effect monster face                       (orange)
CSP  = 3   -- spell card face                           (dark green)
CTR  = 13  -- trap card face                            (purple)
CCB  = 8   -- card back                                 (brown)
-- HUD & cursor
CLP  = 4   -- LP bar fill                               (blue)
CCR  = 2   -- active phase bar fill, action labels      (orange)
CSEL = 12  -- selection cursor dotted border            (medium blue)
-- Combat
CAT  = 1   -- attack flash, damage highlight            (dark red)
-- Field
CMAT = 5   -- duel field "playmat" background

-- Effects that can only be activated in response to an opponent action, never from the player menu
RESPONSE_ONLY_EFFECTS={mirrorforce=true,traphole=true}

PHASES={"DRAW","STBY","MAIN","BATTLE","END"}
PH_DRAW=1; PH_STBY=2; PH_MAIN=3; PH_BATTLE=4; PH_END=5

-- Gameplay constants
START_LP   = 4000
MAX_DECK   = 20    -- pmem can hold up to 24 IDs (4 slots × 6); see dbLoad/dbSave
MAX_COPIES = 3     -- max copies of a single card in one deck

NAME_SCROLL_PAUSE= 300  -- frames to hold at start/end of name scroll

-- Sprite IDs
SPR_SWORD    = 6    -- spinning sword (tribute anim)
SPR_CARDBACK = 32   -- 3x3 card back
SPR_FRAME    = 35   -- 3x3 card border
SPR_STAR     = 96   -- 5x5 level star

-- Attribute icon (8x8): monster attributes + spell/trap markers
ATTR_SPR = {dark=80, earth=81, fire=82, light=83, water=84, wind=85,
            spell=86, trap=87}

-- Spell/trap kind icon (8x8, drawn at 2x in info panel)
KIND_SPR = {normal=88, continuous=89, counter=90, equip=91, field=92, quick=93, ritual=94}

TITLE_ITEMS={"DUEL","DECK","OPTIONS"}
SCENE="title"
TITLE_SEL=1

ANIM={}
DB={}

-- ============================================================
-- CARD DATABASE
-- ============================================================
CARDS={
 -- monsters
 {name="Kuriboh",       cat="monster", type="fiend",         attr="dark",  effect="kuriboh",  atk=300,  def=200,  lvl=1, spr=256, bg=14,
  desc="If your opponent's monster attacks: You can discard this card; you take no battle damage from that battle."},
 {name="Man-Eater Bug",  cat="monster", type="insect",        attr="earth", effect="maneater", atk=450,  def=600,  lvl=2, spr=258, bg=14,
  desc="FLIP: Target 1 monster on the field; destroy that target."},
 {name="Sangan",        cat="monster", type="fiend",         attr="dark",  effect="sangan",   atk=1000, def=600,  lvl=3, spr=260, bg=14,
  desc="When destroyed, add a monster with 1500 or less ATK from your deck to your hand."},
 {name="Giant Soldier",  cat="monster", type="rock",          attr="earth", atk=1300, def=2000, lvl=3, spr=262, bg=14,
  desc="A towering stone giant with impenetrable armor and very high defense."},
 {name="7 Color Fish",   cat="monster", type="fish",          attr="water", atk=1800, def=800,  lvl=4, spr=264, bg=9,
  desc="A vibrant and powerful fish that traverses all the world's oceans."},
 {name="La Jinn",       cat="monster", type="fiend",         attr="dark",  atk=1800, def=1000, lvl=4, spr=266, bg=14,
  desc="A mystical genie released from an ancient lamp. Commands fearsome power."},
 {name="Battle Ox",     cat="monster", type="beast-warrior", attr="earth", atk=1700, def=1000, lvl=4, spr=268, bg=14,
  desc="A savage warrior ox that charges through enemies with brutal force."},
 {name="Ufo Turtle",    cat="monster", type="machine",       attr="fire",  effect="ufoturtle", atk=1400, def=1200, lvl=4, spr=270, bg=14,
  desc="When destroyed in battle, special summons a FIRE monster from the deck."},
 {name="Aqua Madoor",   cat="monster", type="spellcaster",   attr="water", atk=1200, def=2000, lvl=4, spr=288, bg=14,
  desc="A powerful water sorcerer who calls upon the deep sea for protection."},
 {name="Mystical Elf",  cat="monster", type="spellcaster",   attr="light", atk=800,  def=2000, lvl=4, spr=290, bg=14,
  desc="A gentle elf shielded by a sacred barrier. Possesses extreme defense."},
 {name="Summoned Skull", cat="monster", type="fiend",         attr="dark",  atk=2500, def=1200, lvl=6, spr=292, bg=14,
  desc="A powerful fiend that rules the darkness. One of the strongest monsters."},
 {name="Dark Magician",  cat="monster", type="spellcaster",   attr="dark",  atk=2500, def=2100, lvl=7, spr=294, bg=1,
  desc="The ultimate wizard in terms of both attack and defense. A legend."},
 {name="Red Eyes B Dragon",cat="monster",type="dragon",       attr="dark",  atk=2400, def=2000, lvl=7, spr=296, bg=14,
  desc="A ferocious black dragon with a devastating black fire breath attack."},
 {name="Feral Imp",      cat="monster", type="fiend",         attr="dark",  atk=1300, def=1400, lvl=4, spr=298, bg=14,
  desc="A fiendish imp that lurks in the shadows, striking with vicious claws."},
 {name="Rogue Doll",     cat="monster", type="spellcaster",   attr="light", atk=1600, def=1000, lvl=4, spr=300, bg=14,
  desc="A possessed doll that moves on its own will, wielding powerful magic."},
 {name="Dark Magician Girl",cat="monster",type="spellcaster", attr="light", effect="dmgirl",  atk=2000, def=1700, lvl=6, spr=302, bg=14,
  desc="Gains 300 ATK for each Dark Magician in either GY."},
 {name="Legion the Fiend Jester",cat="monster",type="fiend",  attr="dark",  effect="legion",  atk=1200, def=0,    lvl=4, spr=320, bg=14,
  desc="Once per turn: Tribute Summon 1 Spellcaster in ATK pos, in addition to your Normal Summon. If sent from field to GY: add 1 Spellcaster Normal Monster from Deck or GY to hand."},
 -- spells
 {name="Dark Hole",      cat="spell", subtype="normal", effect="darkhole", spr=448, bg=14,
  desc="Destroy all monsters on the field."},
 {name="Raigeki",        cat="spell", subtype="normal", effect="raigeki",  spr=450, bg=14,
  desc="Destroy all monsters your opponent controls."},
 {name="Fissure",        cat="spell", subtype="normal", effect="fissure",  spr=452, bg=14,
  desc="Destroy your opponent's face-up monster with the lowest ATK."},
 {name="Ookazi",         cat="spell", subtype="normal", effect="ookazi",   spr=454, bg=14,
  desc="Inflict 800 points of damage to your opponent's Life Points."},
 {name="United We Stand",cat="spell", subtype="equip",  effect="unitedwestand", spr=462, bg=14,
  desc="The equipped monster gains 800 ATK/DEF for each face-up monster you control."},
 -- traps
 {name="Mirror Force",   cat="trap", subtype="normal",     effect="mirrorforce", spr=456, bg=14,
  desc="When an opponent's monster declares an attack, destroy all their attack position monsters."},
 {name="Trap Hole",      cat="trap", subtype="normal",     effect="traphole",    spr=458, bg=14,
  desc="When your opponent summons a monster with 1000 or more ATK, destroy it."},
 {name="Call of Haunted",cat="trap", subtype="continuous", effect="callhaunted", spr=460, bg=1,
  desc="Target 1 monster in your GY; Special Summon it in ATK Pos. When this card leaves the field, destroy that monster. When that monster is destroyed, destroy this card."},
 {name="Buster Blader",  cat="monster", type="warrior",   attr="earth", effect="busterblader", atk=2600, def=2300, lvl=7, spr=322, bg=14,
  desc="Gains 500 ATK for each Dragon-type monster your opponent controls or has in their GY."},
}
-- IDs above are pmem-stable: only append new cards, never reorder.

DECK1={1,1,1, 3,3,3, 2,2, 2,5, 25,25,25, 24,24, 24,12, 14,15,18}
--  Kuriboh x3, Sangan x3, GiantSoldier x2, 7ColorFish x2,
--  La Jinn x3, SummonedSkull x2, DarkMagician x2,
--  Dark Hole, Raigeki, Mirror Force  (total=20)

DECK2={2,2, 3,3, 4,4, 9,9, 10, 11, 13,
       18, 19, 20, 21, 21,
       }
--  Man-EaterBug x2(flip), Sangan x2(effect), GiantSoldier x2(highDEF),
--  AquaMadoor x2(highDEF), MysticalElf x1(highDEF),
--  SummonedSkull x1(tribute1), RedEyesBDragon x1(tribute2)  [10 monsters]
--  DarkHole, Raigeki, Fissure, Ookazi x2                    [5 spells]
--  MirrorForce x2, TrapHole x3                              [5 traps]
--  total=20

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
 return (lvl<=4) and 0 or (lvl<=6) and 1 or 2
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
function getEquipBonus(card)
 local ab,db=0,0
 for p=1,2 do
  for c=1,3 do
   local eq=G.st[p][c]
   if eq and not eq.facedown and eq.subtype=="equip" and eq.equippedTo then
    local tp,tc=eq.equippedTo.plr,eq.equippedTo.col
    if G.mon[tp] and G.mon[tp][tc]==card then
     if eq.effect=="unitedwestand" then
      local n=0
      for i=1,3 do if G.mon[tp][i] and not G.mon[tp][i].facedown then n=n+1 end end
      ab=ab+n*800; db=db+n*800
     end
    end
   end
  end
 end
 return ab,db
end

-- Returns effective ATK, applying continuous and equip bonuses.
function getMonAtk(card)
 local bonus=0
 if card.effect=="dmgirl" then
  for p=1,2 do
   for _,c in ipairs(G.gy[p]) do
    if c.name=="Dark Magician" then bonus=bonus+300 end
   end
  end
 elseif card.effect=="busterblader" then
  local opp=nil
  for p=1,2 do
   for i=1,3 do if G.mon[p][i]==card then opp=3-p; break end end
   if opp then break end
  end
  if opp then
   for i=1,3 do
    local m=G.mon[opp][i]
    if m and not m.facedown and m.type=="dragon" then bonus=bonus+500 end
   end
   for _,c in ipairs(G.gy[opp]) do
    if c.type=="dragon" then bonus=bonus+500 end
   end
  end
 end
 local ab,_=getEquipBonus(card)
 return card.atk+bonus+ab
end

-- Returns effective DEF, applying equip bonuses.
function getMonDef(card)
 local _,db=getEquipBonus(card)
 return card.def+db
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
     G.st[p][c]=nil; table.insert(G.gy[p],eq)
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

-- ============================================================
-- GAME STATE
-- ============================================================
G={}

function newGame()
 G={
  turn=1, ph=1, active=1, firstPlayer=1, tick=0,
  lp={START_LP,START_LP},
  dispLp={START_LP,START_LP},
  mon={{nil,nil,nil},{nil,nil,nil}},
  st ={{nil,nil,nil},{nil,nil,nil}},
  hand={{},{}},
  gy  ={{},{}},
  deck={{},{}},
  cur={side=1,row=1,col=2},
  menu={open=false,items={},sel=1},
  mode="free",
  infoCard=nil,
  nameScroll={card=nil,offset=0,pause=NAME_SCROLL_PAUSE,atEnd=false},
  pending=nil,
  normalSummoned=false,
  aiTimer=0,
  aiBattleIdx=1,
  autoTimer=50,
 }
 ANIM={}
end

-- ============================================================
-- CURSOR HELPERS
-- ============================================================
function getHoveredCard()
 local c=G.cur
 if c.row==3 then return G.hand[c.side][c.col+1] end
 if c.col==0 or c.col==4 then return nil end
 if c.side==1 then
  return c.row==1 and G.mon[1][c.col] or G.st[1][c.col]
 else
  return c.row==1 and G.mon[2][4-c.col] or G.st[2][4-c.col]
 end
end

function clampToHand(side)
 G.cur.col=math.min(G.cur.col,math.max(0,#G.hand[side]-1))
end

function checkWin()
 if G.lp[1]<=0 and not G.winner then G.winner=2; G.winTick=G.tick
 elseif G.lp[2]<=0 and not G.winner then G.winner=1; G.winTick=G.tick
 end
end

function drawGYView()
 local gv=G.gyView
 local gy=G.gy[gv.plr]
 rect(0,0,SW,SH,CB)
 rectb(0,0,SW,SH,CD)
 local title=(gv.plr==1) and "YOUR GRAVEYARD" or "OPP GRAVEYARD"
 print(title,4,3,CCR,true,1,false)
 print("("..#gy..")",SW-#tostring(#gy)*6-14,3,CT,true,1,false)
 line(0,13,SW-1,13,CD)
 if #gy==0 then
  print("Empty",(SW-30)//2,SH//2-3,CT,true,1,false)
  print("B:close",4,SH-8,CD,true,1,true)
  return
 end
 local listX=4
 local listY=15
 local rowH=10
 local maxVis=9
 local dispSel=#gy-gv.sel+1
 local scrollTop=math.max(1,math.min(dispSel-maxVis//2,math.max(1,#gy-maxVis+1)))
 for row=1,maxVis do
  local dispIdx=scrollTop+row-1
  if dispIdx>#gy then break end
  local cardIdx=#gy-dispIdx+1
  local card=gy[cardIdx]
  local iy=listY+(row-1)*rowH
  local isSel=(cardIdx==gv.sel)
  if isSel then rect(0,iy-1,SW,9,CHL) end
  local tc=isSel and CB or CT
  print(dispIdx..".",listX,iy,isSel and CB or CD,true,1,false)
  print(string.sub(card.name or "?",1,22),listX+14,iy,tc,true,1,false)
  if card.cat=="spell" then
   print("SPELL",SW-38,iy,isSel and CB or CSP,true,1,false)
  elseif card.cat=="trap" then
   print("TRAP",SW-32,iy,isSel and CB or CTR,true,1,false)
  elseif card.atk then
   print("ATK "..card.atk,SW-52,iy,isSel and CB or CD,true,1,false)
  end
 end
 if #gy>maxVis then
  local barH=maxVis*rowH
  local pct=(scrollTop-1)/math.max(1,#gy-maxVis)
  local markY=listY+math.floor(pct*(barH-4))
  rect(SW-4,listY,3,barH,CB)
  rect(SW-4,markY,3,4,CD)
 end
 local sel=gy[gv.sel]
 line(0,SH-28,SW-1,SH-28,CD)
 if sel then
  if sel.cat=="monster" then
   print("ATK:"..sel.atk.."  DEF:"..sel.def.."  LV:"..sel.lvl,listX,SH-24,CT,true,1,false)
  end
  if sel.desc then
   print(string.sub(sel.desc,1,math.floor((SW-8)/4)),listX,SH-16,CD,true,1,true)
  end
 end
 print("UP/DN: browse     B: close",listX,SH-8,CD,true,1,true)
end

function drawDeckSelect()
 local ds=G.deckSel
 rect(0,0,SW,SH,CB)
 rectb(0,0,SW,SH,CD)
 print(ds.title,4,3,CCR,true,1,true)
 print("("..#ds.items..")",SW-#tostring(#ds.items)*6-14,3,CT,true,1,false)
 line(0,13,SW-1,13,CD)
 local listX,listY,rowH,maxVis=4,15,10,9
 local scrollTop=math.max(1,math.min(ds.sel-maxVis//2,math.max(1,#ds.items-maxVis+1)))
 for row=1,maxVis do
  local idx=scrollTop+row-1
  if idx>#ds.items then break end
  local item=ds.items[idx]
  local iy=listY+(row-1)*rowH
  local isSel=(idx==ds.sel)
  if isSel then rect(0,iy-1,SW,9,CHL) end
  local tc=isSel and CB or CT
  print(idx..".",listX,iy,isSel and CB or CD,true,1,false)
  print(string.sub(item.name or "?",1,18),listX+14,iy,tc,true,1,false)
  if item.atk then print("ATK "..item.atk,SW-52,iy,isSel and CB or CD,true,1,false) end
 end
 if #ds.items>maxVis then
  local barH=maxVis*rowH
  local pct=(scrollTop-1)/math.max(1,#ds.items-maxVis)
  local markY=listY+math.floor(pct*(barH-4))
  rect(SW-4,listY,3,barH,CB); rect(SW-4,markY,3,4,CD)
 end
 local sel=ds.items[ds.sel]
 line(0,SH-28,SW-1,SH-28,CD)
 if sel then
  print("ATK:"..sel.atk.."  DEF:"..sel.def.."  LV:"..sel.lvl,listX,SH-24,CT,true,1,false)
  if sel.desc then
   print(string.sub(sel.desc,1,math.floor((SW-8)/4)),listX,SH-16,CD,true,1,true)
  end
 end
 print("UP/DN: browse     A: pick",listX,SH-8,CD,true,1,true)
end

function handleDeckSelectInput()
 local ds=G.deckSel
 if btnp(0) then ds.sel=math.max(1,ds.sel-1)
 elseif btnp(1) then ds.sel=math.min(#ds.items,ds.sel+1)
 elseif btnp(4) then
  local item=ds.items[ds.sel]
  if item then ds.onPick(item.deckIdx); G.mode="free"; G.deckSel=nil end
 end
end

function drawGameOver()
 -- dim overlay
 for y=0,SH-1,2 do rect(0,y,SW,1,CB) end
 -- box
 local bx,by,bw,bh=40,30,160,76
 rect(bx,by,bw,bh,CB)
 rectb(bx,by,bw,bh,CD)
 rectb(bx+1,by+1,bw-2,bh-2,CD)
 -- result
 local win=(G.winner==1)
 local msg=win and "YOU WIN!" or "YOU LOSE!"
 local col=win and CCR or CAT
 print(msg,(SW-#msg*12)//2,by+8,col,true,2,false)
 -- final LP
 local lp1="YOU  "..G.lp[1].." LP"
 local lp2="OPP  "..G.lp[2].." LP"
 print(lp1,(SW-#lp1*6)//2,by+34,win and CLP or CAT,true,1,false)
 print(lp2,(SW-#lp2*6)//2,by+44,win and CAT or CLP,true,1,false)
 -- blinking prompt (only after 90 frame delay)
 local elapsed=G.tick-(G.winTick or 0)
 if elapsed>90 and (elapsed//30)%2==0 then
  local sub="A: PLAY AGAIN"
  print(sub,(SW-#sub*6)//2,by+60,CT,true,1,false)
 end
end

function drawCard(p,noAnim)
 if #G.deck[p]>0 and #G.hand[p]<MAX_HAND then
  table.insert(G.hand[p],makeCard(table.remove(G.deck[p])))
  if not noAnim then animDrawCard(p) end
 end
end

function animDrawCard(p)
 local n=#G.hand[p]
 local sx=(p==1) and COL[4] or COL[0]
 local sy=(p==1) and PY_S or OY_S
 local ex=handX(n,n-1)
 local ey=(p==1) and PY_H or OY_H
 addAnim(18,function(t,f)
  local prog=(f-t)/f
  local cx=math.floor(sx+(ex-sx)*prog)
  local cy=math.floor(sy+(ey-sy)*prog)
  dCardBack(cx,cy,HW,PHH)
 end)
end

function changePhase(ph)
 if ph==PH_BATTLE and G.turn==1 and G.active==G.firstPlayer then ph=PH_END end
 G.ph=ph
end

function addAnim(frames,fn,onDone)
 table.insert(ANIM,{frames=frames,t=frames,fn=fn,onDone=onDone})
end

function tickAnims()
 for i=#ANIM,1,-1 do
  ANIM[i].t=ANIM[i].t-1
  if ANIM[i].t<=0 then
   local cb=ANIM[i].onDone
   table.remove(ANIM,i)
   if cb then cb() end
  end
 end
end

function drawAnims()
 for _,a in ipairs(ANIM) do a.fn(a.t,a.frames) end
end

function destroyFlash(x,y)
 addAnim(24,function(t,f) if t//4%2==0 then rect(x,y,ZW_MAIN,ZH,CCR) end end)
end

-- LP change helper: clamps and checks win; dispLp animates toward G.lp each tick
function changeLp(plr,delta)
 G.lp[plr]=math.max(0,G.lp[plr]+delta)
 checkWin()
end

-- Apply battle damage, checking for Kuriboh in hand first.
-- plr=1: prompt player to activate Kuriboh. plr=2: AI auto-uses it.
function applyDamage(plr,dmg)
 if dmg<=0 then return end
 for i,card in ipairs(G.hand[plr]) do
  if card.effect=="kuriboh" then
   if plr==1 then
    G.mode="trap_ask"
    G.trapAsk={fromHand=true,handIdx=i,card=card,
     onYes=function() end,
     onNo =function() changeLp(1,-dmg) end}
   else
    table.remove(G.hand[2],i); table.insert(G.gy[2],card)
   end
   return
  end
 end
 changeLp(plr,-dmg)
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

-- Returns the screen XY of a monster zone (used when triggering destroy anims from effects)
function monZoneXY(plr,col)
 return (plr==1) and COL[col] or COL[4-col],
        (plr==1) and PY_M or OY_M
end

-- Adds a 25-frame wait anim that fires monster onDestroy effects after destroy flashes finish.
-- Only added when there are effects to trigger (avoids unnecessary input blocking).
function deferEffects(triggered)
 if #triggered==0 then return end
 addAnim(25,function()end,function()
  for _,e in ipairs(triggered) do triggerMonEffect(e.card,"onDestroy",e.plr) end
  checkEquips()
 end)
end

function animSpellActivation(col,zy,card,plr)
 local zx=(plr==1) and COL[col] or COL[4-col]
 local sc=card.cat=="spell" and CSP or CTR
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,zy,ZW_MAIN,ZH,sc); rectb(zx,zy,ZW_MAIN,ZH,CT) end
 end,function()
  if card.subtype=="continuous" or card.subtype=="equip" then
   card.facedown=false
  else
   G.st[plr][col]=nil; table.insert(G.gy[plr],card)
  end
  applyEffect(card,plr,col)
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

EFFECTS={
 darkhole=function(plr)
  local triggered={}
  for i=1,3 do
   for p=1,2 do
    local m=G.mon[p][i]
    if m then
     local zx,zy=monZoneXY(p,i)
     table.insert(G.gy[p],m); G.mon[p][i]=nil
     destroyFlash(zx,zy)
     table.insert(triggered,{card=m,plr=p})
    end
   end
  end
  deferEffects(triggered)
 end,
 raigeki=function(plr)
  local opp=3-plr
  local triggered={}
  for i=1,3 do
   local m=G.mon[opp][i]
   if m then
    local zx,zy=monZoneXY(opp,i)
    table.insert(G.gy[opp],m); G.mon[opp][i]=nil
    destroyFlash(zx,zy)
    table.insert(triggered,{card=m,plr=opp})
   end
  end
  deferEffects(triggered)
 end,
 fissure=function(plr)
  local opp=3-plr
  local low,lowI=math.huge,nil
  for i=1,3 do
   local m=G.mon[opp][i]
   if m and not m.facedown and m.atk<low then low=m.atk; lowI=i end
  end
  if lowI then
   local m=G.mon[opp][lowI]
   local zx,zy=monZoneXY(opp,lowI)
   table.insert(G.gy[opp],m); G.mon[opp][lowI]=nil
   destroyFlash(zx,zy)
   deferEffects({{card=m,plr=opp}})
  end
 end,
 ookazi=function(plr)
  changeLp(3-plr,-800)
 end,
 mirrorforce=function(plr)
  local opp=3-plr
  local triggered={}
  for i=1,3 do
   local m=G.mon[opp][i]
   if m and m.pos==1 and not m.facedown then
    local zx,zy=monZoneXY(opp,i)
    table.insert(G.gy[opp],m); G.mon[opp][i]=nil
    destroyFlash(zx,zy)
    table.insert(triggered,{card=m,plr=opp})
   end
  end
  deferEffects(triggered)
 end,
 traphole=function(plr)
  local opp=3-plr
  local high,highI=-1,nil
  for i=1,3 do
   local m=G.mon[opp][i]
   if m and m.atk>=1000 and m.atk>high then high=m.atk; highI=i end
  end
  if highI then
   local m=G.mon[opp][highI]
   local zx,zy=monZoneXY(opp,highI)
   table.insert(G.gy[opp],m); G.mon[opp][highI]=nil
   destroyFlash(zx,zy)
   deferEffects({{card=m,plr=opp}})
  end
 end,
 callhaunted=function(plr,col)
  if plr==1 then
   callHauntedActivate(G.st[1][col])
  else
   local best,bestI=-1,nil
   for i,c in ipairs(G.gy[2]) do
    if c.cat=="monster" and c.atk and c.atk>best then best=c.atk; bestI=i end
   end
   local emptyCol=firstEmpty(G.mon[2])
   if bestI and emptyCol then
    local m=table.remove(G.gy[2],bestI)
    m.pos=1; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
    G.mon[2][emptyCol]=m
    local trap=G.st[2][col]
    if trap then trap.linkedMon=m; m.linkedTrap=trap end
   end
  end
 end,
}

function applyEffect(card,plr,col)
 local fn=EFFECTS[card.effect]
 if fn then fn(plr,col) end
end

-- ============================================================
-- MONSTER EFFECTS
-- ============================================================
-- Each entry is a table of event handlers: onDestroy, onFlip, etc.
-- triggerMonEffect(card, event, plr) dispatches the right handler.
MON_EFFECTS={
 sangan={
  onDestroy=function(card,plr)
   -- Build list of eligible monsters (ATK<=1500) in owner's deck
   local items={}
   for i,id in ipairs(G.deck[plr]) do
    local d=CARDS[id]
    if (d.cat or "monster")=="monster" and d.atk and d.atk<=1500 then
     table.insert(items,{deckIdx=i,name=d.name,atk=d.atk,def=d.def,lvl=d.lvl,desc=d.desc})
    end
   end
   if #items==0 then return end
   if plr==2 then
    -- AI: auto-pick highest ATK among eligible
    local bestAtk,bestI=-1,nil
    for _,item in ipairs(items) do
     if item.atk>bestAtk then bestAtk=item.atk; bestI=item.deckIdx end
    end
    if bestI and #G.hand[2]<MAX_HAND then
     table.insert(G.hand[2],makeCard(table.remove(G.deck[2],bestI)))
    end
   else
    -- Player: open deck selection screen
    G.mode="sel_deck"
    G.deckSel={
     items=items, sel=1,
     title="SANGAN  ATK<=1500",
     onPick=function(deckIdx)
      if #G.hand[1]<MAX_HAND then
       table.insert(G.hand[1],makeCard(table.remove(G.deck[1],deckIdx)))
      end
     end,
    }
   end
  end,
 },
 maneater={
  onFlip=function(card,plr)
   local function destroyTarget(tp,ti)
    local m=G.mon[tp][ti]
    if not m then return end
    local zx,zy=monZoneXY(tp,ti)
    table.insert(G.gy[tp],m); G.mon[tp][ti]=nil
    destroyFlash(zx,zy)
    deferEffects({{card=m,plr=tp}})
   end
   -- check if any monster exists to target
   if not (hasMonsters(1) or hasMonsters(2)) then return end
   if plr==2 then
    -- AI: destroy player's highest-value monster
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
    -- Player: open target-select UI
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
  onDestroy=function(card,plr)
   if plr==1 then legionSearch() end
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
   local emptyCol=firstEmpty(G.mon[plr])
   if not emptyCol then return end
   if plr==2 then
    local bestAtk,bestI=-1,nil
    for _,item in ipairs(items) do
     if item.atk>bestAtk then bestAtk=item.atk; bestI=item.deckIdx end
    end
    if bestI then
     local m=makeCard(table.remove(G.deck[2],bestI))
     m.pos=1; m.facedown=false; m.attacked=false; m.summoned=true; m.posChanged=false
     G.mon[2][emptyCol]=m
    end
   else
    G.mode="sel_deck"
    G.deckSel={
     items=items, sel=1,
     title="UFO TURTLE  FIRE",
     onPick=function(deckIdx)
      local col=firstEmpty(G.mon[1])
      if col then
       local m=makeCard(table.remove(G.deck[1],deckIdx))
       G.pendingSS={card=m,plr=1}
       G.menu={open=true,sel=1,items={{"ATK POSITION","ss_atk"},{"DEF POSITION","ss_def"}}}
      end
     end,
    }
   end
  end,
 },
}

function triggerMonEffect(card,event,plr)
 if event=="onDestroy" and card.linkedTrap then
  local trap=card.linkedTrap
  card.linkedTrap=nil; trap.linkedMon=nil
  for p=1,2 do
   for c=1,3 do
    if G.st[p][c]==trap then
     G.st[p][c]=nil; table.insert(G.gy[p],trap); break
    end
   end
  end
 end
 if not card.effect then return end
 local me=MON_EFFECTS[card.effect]
 if me and me[event] then me[event](card,plr) end
end

function startMonsterPlacement(handIdx,action)
 local card=G.hand[1][handIdx]
 if not card then return end
 local tribNeeded=tribsNeeded(card.lvl or 1)
 G.pending={handIdx=handIdx,card=card,action=action,tribNeeded=tribNeeded,tributes={}}
 if tribNeeded>0 then
  G.mode="sel_tribute"
  G.cur={side=1,row=1,col=firstOccupied(G.mon[1]) or 1}
 else
  G.mode="sel_mon"
  G.cur={side=1,row=1,col=firstEmpty(G.mon[1]) or 1}
 end
end

-- Build context-sensitive menu items for the current cursor position.
-- Returns a list of {label, actionKey} or nil if no menu should open.
function buildMenu()
 local c=G.cur
 local isMain=(G.ph==PH_MAIN)
 local items={}

 if c.side==1 and G.active==1 then  -- player's own stuff, player's turn

  if c.row==3 then  -- hand card
   local card=G.hand[1][c.col+1]
   if card and isMain then
    if card.cat=="spell" then
     local emptyZone=firstEmpty(G.st[1])~=nil
     local hasTarget=hasMonsters(1) or hasMonsters(2)
     if card.subtype~="equip" or (emptyZone and hasTarget) then
      table.insert(items,{"ACTIVATE","cast_hand"})
     end
     if emptyZone then table.insert(items,{"SET","set_st"}) end
    elseif card.cat=="trap" then
     if firstEmpty(G.st[1]) then table.insert(items,{"SET","set_st"}) end
    elseif not G.normalSummoned then
     local monCount,emptyZone=0,false
     for i=1,3 do
      if G.mon[1][i] then monCount=monCount+1 else emptyZone=true end
     end
     local tribNeeded=tribsNeeded(card.lvl or 1)
     local canSummon=(tribNeeded==0 and emptyZone)
                  or (tribNeeded>=1 and monCount>=tribNeeded)
     if canSummon then table.insert(items,{"SUMMON","summon"}) end
     if canSummon then table.insert(items,{"SET","set"}) end
    end
    -- Legion extra tribute summon (separate from normal summon slot)
    if isMain and G.extraSpellcasterSummon and card.cat=="monster" and card.type=="spellcaster" then
     local monCount,emptyZone=0,false
     for i=1,3 do
      if G.mon[1][i] then monCount=monCount+1 else emptyZone=true end
     end
     local tribNeeded=tribsNeeded(card.lvl or 1)
     if tribNeeded>=1 and monCount>=tribNeeded then
      table.insert(items,{"EXTRA SUMMON","summon_extra"})
     end
    end
   end

  elseif c.row==1 and c.col>=1 and c.col<=3 then  -- monster zone
   local card=G.mon[1][c.col]
   if card then
    if isMain and not card.summoned and not card.posChanged then
     table.insert(items,{"CHG POS","chgpos"})
    end
    if isMain and not card.facedown and card.effect=="legion" and not G.legionSummonUsed and not G.extraSpellcasterSummon then
     table.insert(items,{"EXTRA SUMMON","legion_extra"})
    end
    if G.ph==PH_BATTLE and card.pos==1 and not card.facedown and not card.attacked then
     table.insert(items,{"ATTACK","attack"})
    end
   end

  elseif c.row==2 and c.col>=1 and c.col<=3 then  -- spell/trap zone
   local card=G.st[1][c.col]
   if card and not card.setThisTurn then
    if card.cat=="spell" and isMain then
     local canActivate=card.subtype~="equip" or (hasMonsters(1) or hasMonsters(2))
     if canActivate then table.insert(items,{"ACTIVATE","activate"}) end
    elseif card.cat=="trap" and not RESPONSE_ONLY_EFFECTS[card.effect] then
     table.insert(items,{"ACTIVATE","activate"})
    end
   end
  end

 end

 local hovCard=getHoveredCard()
 if hovCard and hovCard.desc and not (G.cur.side==2 and hovCard.facedown) then
  table.insert(items,{"INFO","info"})
 end
 if #items==0 then return nil end  -- nothing to do, don't open
 table.insert(items,{"CANCEL","cancel"})
 return items
end

-- Execute a menu action.
function execAction(key)
 local c=G.cur
 G.menu.open=false  -- close menu first; specific actions may reopen or change state

 if key=="cancel" then
  -- nothing

 elseif key=="info" then
  G.infoCard=getHoveredCard()

 elseif key=="chgpos" then
  local card=G.mon[1][c.col]
  if card then
   if card.facedown then
    card.facedown=false; card.pos=1
    triggerMonEffect(card,"onFlip",1)
   else
    card.pos=(card.pos==1) and 2 or 1
   end
   card.posChanged=true
   checkEquips()
  end

 elseif key=="summon" then
  startMonsterPlacement(G.cur.col+1,"summon")
 elseif key=="summon_extra" then
  startMonsterPlacement(G.cur.col+1,"summon_extra")
 elseif key=="set" then
  startMonsterPlacement(G.cur.col+1,"set")
 elseif key=="legion_extra" then
  G.extraSpellcasterSummon=true; G.legionSummonUsed=true
 elseif key=="attack" then
  local atkCol=c.col
  local attacker=G.mon[1][atkCol]
  if attacker then
   G.pending={attacker=attacker,atkCol=atkCol,action="attack"}
   G.mode="sel_atk"
   G.cur={side=2,row=1,col=2}
   for i=1,3 do
    if G.mon[2][i] then G.cur.col=4-i; break end
   end
  end
 elseif key=="set_st" then
  local handIdx=G.cur.col+1
  local card=G.hand[1][handIdx]
  if card then
   G.pending={handIdx=handIdx,card=card,action="set_st"}
   G.mode="sel_st"
   G.cur={side=1,row=2,col=firstEmpty(G.st[1]) or 1}
  end
 elseif key=="cast_hand" then
  local handIdx=G.cur.col+1
  local card=G.hand[1][handIdx]
  if card then
   if card.subtype=="equip" then
    G.pending={handIdx=handIdx,card=card,action="cast_equip"}
    G.mode="sel_equip"
    local startCol=firstOccupied(G.mon[1]) or firstOccupied(G.mon[2]) or 1
    G.cur={side=1,row=1,col=startCol}
   else
    G.pending={handIdx=handIdx,card=card,action="cast_hand"}
    G.mode="sel_st"
    G.cur={side=1,row=2,col=firstEmpty(G.st[1]) or 1}
   end
  end
 elseif key=="activate" then
  local col=c.col
  local card=G.st[1][col]
  if card then
   if card.subtype=="equip" then
    G.pending={stCol=col,card=card,action="activate_equip"}
    G.mode="sel_equip"
    local startCol=firstOccupied(G.mon[1]) or firstOccupied(G.mon[2]) or 1
    G.cur={side=1,row=1,col=startCol}
   else
    card.facedown=false
    animSpellActivation(col,PY_S,card,1)
   end
  end

 elseif key=="nextphase" then
  changePhase(G.ph+1)

 elseif key=="endturn" then
  changePhase(PH_END)
  G.autoTimer=1

 elseif key=="ss_atk" or key=="ss_def" then
  local ps=G.pendingSS; G.pendingSS=nil
  if ps then
   local col=firstEmpty(G.mon[ps.plr])
   if col then
    local m=ps.card
    m.pos=(key=="ss_atk") and 1 or 2
    m.facedown=false; m.attacked=false; m.summoned=true; m.posChanged=false
    G.mon[ps.plr][col]=m
   end
  end
 end
end

function resolveAttack(attacker,atkCol,target,tgtIdx)
 attacker.attacked=true
 G.mode="free"; G.pending=nil
 G.cur={side=1,row=1,col=atkCol}

 local ax=COL[atkCol]+ZW_MAIN//2-8
 local ay=PY_M+ZH//2-8

 if not target then
  local tx=FA_X+FA_W//2-8; local ty=OY_S+ZH//2-8
  animSwordSlash(ax,ay,tx,ty,function() applyDamage(2,getMonAtk(attacker)) end)
  return
 end

 local tx=COL[4-tgtIdx]+ZW_MAIN//2-8
 local ty=OY_M+ZH//2-8
 local wasFlipped=target.facedown

 local function doSlash()
  animSwordSlash(ax,ay,tx,ty,function()
   local dPlr=false; local dOpp=false
   local triggered={}
   local atkV=getMonAtk(attacker); local tgtV=getMonAtk(target); local tgtDef=getMonDef(target)
   if target.pos==2 then
    if atkV>tgtDef then
     table.insert(G.gy[2],target); G.mon[2][tgtIdx]=nil; dOpp=true
     table.insert(triggered,{card=target,plr=2})
    elseif atkV<tgtDef then
     changeLp(1,-(tgtDef-atkV))
    end
   else
    if atkV>tgtV then
     table.insert(G.gy[2],target); G.mon[2][tgtIdx]=nil
     applyDamage(2,atkV-tgtV); dOpp=true
     table.insert(triggered,{card=target,plr=2})
    elseif atkV<tgtV then
     table.insert(G.gy[1],attacker); G.mon[1][atkCol]=nil
     changeLp(1,-(tgtV-atkV)); dPlr=true
     table.insert(triggered,{card=attacker,plr=1})
    else
     table.insert(G.gy[2],target); G.mon[2][tgtIdx]=nil
     table.insert(G.gy[1],attacker); G.mon[1][atkCol]=nil
     dOpp=true; dPlr=true
     table.insert(triggered,{card=target,plr=2})
     table.insert(triggered,{card=attacker,plr=1})
    end
   end
   if dOpp then destroyFlash(COL[4-tgtIdx],OY_M) end
   if dPlr then destroyFlash(COL[atkCol],PY_M) end
   checkWin()
   deferEffects(triggered)
   if wasFlipped then triggerMonEffect(target,"onFlip",2) end
  end)
 end

 if wasFlipped then
  target.facedown=false
  local zx=COL[4-tgtIdx]
  addAnim(24,function(t,f)
   if (t//4)%2==0 then rect(zx,OY_M,ZW_MAIN,ZH,COZ); rectb(zx,OY_M,ZW_MAIN,ZH,CT) end
  end,doSlash)
 else
  doSlash()
 end
end

-- ============================================================
-- DRAW PRIMITIVES
-- ============================================================

-- Generic zone box (any size); optional cnt draws a number below the label
function dZone(x,y,w,h,c,lbl,cnt)
 rect(x,y,w,h,c)
 rectb(x,y,w,h,CD)
 if lbl then
  local ly=cnt and y+3 or y+(h-6)//2
  print(lbl,x+(w-#lbl*6)//2,ly,CT,true,1,false)
  if cnt then
   local cs=tostring(cnt)
   print(cs,x+(w-#cs*6)//2,y+13,CT,true,1,false)
  end
 end
end

-- Attack position: card upright, portrait 20x22 inside 22x22 (1px left/right margin)
function dCardAtk(x,y,card,zc)
 local fc=card.effect and CME or CCA
 rect(x,y,ZW_MAIN,ZH,zc)
 rect(x+2,y+1,ZW_MAIN-4,ZH-2,fc)
 if card.spr then spr(card.spr,x+3,y+2,card.bg,1,0,0,2,2) end
 clip(x+1,y,ZW_MAIN-2,ZH)
 spr(SPR_FRAME,x+1,y,15,1,0,0,3,3)
 clip()
end

-- Defense position: card sideways, landscape 22x20 inside 22x22 (1px top/bottom margin)
function dCardDef(x,y,card,zc)
 local fc=card.effect and CME or CCA
 rect(x,y,ZW_MAIN,ZH,zc)
 rect(x+1,y+2,ZW_MAIN-2,ZH-4,fc)
 if card.spr then spr(card.spr,x+4,y+3,card.bg,1,0,1,2,2) end
 clip(x,y+1,ZW_MAIN,ZH-2)
 spr(SPR_FRAME,x-2,y+1,15,1,0,1,3,3)
 clip()
end

-- Spell/trap face-up: colored tint + sprite frame
function dCardSpell(x,y,card,zc)
 local c=(card.cat=="trap") and CTR or CSP
 rect(x,y,ZW_MAIN,ZH,zc)
 rect(x+2,y+1,ZW_MAIN-4,ZH-2,c)
 if card.spr then spr(card.spr,x+3,y+2,card.bg,1,0,0,2,2) end
 clip(x+1,y,ZW_MAIN-2,ZH)
 spr(SPR_FRAME,x+1,y,15,1,0,0,3,3)
 clip()
end

-- Card back, face-down (variable size: field facedown, opp hand)
-- rot: 0=normal, 1=90CW (defense pos)   fl: 0=normal, 2=vertical flip (opp hand)
function dCardBack(x,y,w,h,rot,fl,syOff)
 rot=rot or 0; fl=fl or 0; syOff=syOff or 0
 local sx=x+(w-20)//2 - (rot==1 and 3 or 0)
 local sy=y + syOff
 clip(x,y,w,h)
 spr(SPR_CARDBACK,sx,sy,15,1,fl,rot,3,3)
 clip()
end

-- Player hand card (HW x PHH = 20x22, face-up)
function dHandPlr(x,y,card)
 local fc
 if card.cat=="spell" or card.cat=="trap" then
  fc=card.cat=="spell" and CSP or CTR
 else
  fc=card.effect and CME or CCA
 end
 rect(x+1,y+1,HW-2,PHH-2,fc)
 if card.spr then spr(card.spr,x+2,y+2,card.bg,1,0,0,2,2) end
 clip(x,y,HW,PHH)
 spr(SPR_FRAME,x,y,15,1,0,0,3,3)
 clip()
end

-- Animated dotted red border for selectable zones (marching ants)
function dDotBorder(x,y,w,h,col)
 col=col or CSEL
 local o=G.tick//15%2
 for i=0,w-1 do
  if (i+o)%2==0 then pix(x+i,y,col); pix(x+i,y+h-1,col) end
 end
 for i=1,h-2 do
  if (i+o)%2==0 then pix(x,y+i,col); pix(x+w-1,y+i,col) end
 end
end

-- Dispatch: empty zone or face-down or attack/defense card (main zones only)
function dFieldSlot(x,y,card,facedown,zoneColor)
 if not card then
  dZone(x,y,ZW_MAIN,ZH,zoneColor)
 elseif facedown then
  if card.pos==2 then
   rect(x,y,ZW_MAIN,ZH,zoneColor)
   dCardBack(x,y+1,ZW_MAIN,ZH-2,1)
  else
   dCardBack(x,y,ZW_MAIN,ZH)
  end
 elseif card.cat=="spell" or card.cat=="trap" then
  dCardSpell(x,y,card,zoneColor)
 elseif card.pos==2 then
  dCardDef(x,y,card,zoneColor)
 else
  dCardAtk(x,y,card,zoneColor)
 end
end

-- Cursor highlight (dotted red border outside)
function dCursor(x,y,w,h,col)
 dDotBorder(x-1,y-1,w+2,h+2,col)
end

-- LP bar (filled left-to-right)
function dLPBar(x,y,w,lp)
 rect(x,y,w,9,CB)
 rect(x,y,w*lp//START_LP,9,CLP)
 rectb(x,y,w,9,CD)
 print(lp,x+2,y+2,CT,true,1,true)
end

-- ============================================================
-- FIELD RENDERER
-- ============================================================

-- Opponent (top → divider):
--   OY_H: face-down hand cards (centered)
--   OY_S: [DK][S3][S2][S1][ED]
--   OY_M: [GY][M3][M2][M1][FS]
function drawOppSide()
 local oh=math.min(#G.hand[2],MAX_HAND)
 for i=0,oh-1 do
  dCardBack(handX(oh,i),OY_H,HW,OHH,0,0,-11)
 end

 dZone(COL[0],OY_S,ZW_SPEC,ZH,CDK,"DK",#G.deck[2])
 for c=1,3 do
  local card=G.st[2][4-c]
  dFieldSlot(COL[c],OY_S,card,not card or card.facedown,COZ)
 end
 dZone(COL[4],OY_S,ZW_SPEC,ZH,CED,"ED")

 dZone(COL[0],OY_M,ZW_SPEC,ZH,CGY,"GY",#G.gy[2])
 for c=1,3 do
  local card=G.mon[2][4-c]
  dFieldSlot(COL[c],OY_M,card,card and card.facedown,COZ)
  if (G.mode=="sel_atk" or G.mode=="sel_destroy") and card then dDotBorder(COL[c],OY_M,ZW_MAIN,ZH) end
  if G.mode=="sel_equip" and card and not card.facedown then dDotBorder(COL[c],OY_M,ZW_MAIN,ZH,CSP) end
  if G.battleAnim and G.battleAnim.atkCol and (4-c)==G.battleAnim.atkCol then
   dDotBorder(COL[c],OY_M,ZW_MAIN,ZH,CAT)
  end
 end
 dZone(COL[4],OY_M,ZW_SPEC,ZH,CFS,"FS")
end

-- Player (divider → bottom):
--   PY_M: [FS][M1][M2][M3][GY]
--   PY_S: [ED][S1][S2][S3][DK]
--   PY_H: face-up hand cards (centered)
function drawPlrSide()
 dZone(COL[0],PY_M,ZW_SPEC,ZH,CFS,"FS")
 for c=1,3 do
  local zc
  local isTrib=false
  if G.mode=="sel_tribute" and G.pending then
   for _,t in ipairs(G.pending.tributes) do
    if t==c then isTrib=true; break end
   end
  end
  zc=isTrib and CFS or CZ
  local card=G.mon[1][c]
  dFieldSlot(COL[c],PY_M,card,card and card.facedown,zc)
  if G.mode=="sel_tribute" and G.mon[1][c] and not isTrib then
   dDotBorder(COL[c],PY_M,ZW_MAIN,ZH)
  elseif G.mode=="sel_mon" and not G.mon[1][c] then
   dDotBorder(COL[c],PY_M,ZW_MAIN,ZH)
  elseif G.mode=="sel_destroy" and G.mon[1][c] then
   dDotBorder(COL[c],PY_M,ZW_MAIN,ZH)
  elseif G.mode=="sel_atk" and G.pending and c==G.pending.atkCol then
   dDotBorder(COL[c],PY_M,ZW_MAIN,ZH,CCR)
  elseif G.mode=="sel_equip" and card and not card.facedown then
   dDotBorder(COL[c],PY_M,ZW_MAIN,ZH,CSP)
  end
  if G.battleAnim and G.battleAnim.tgtCol==c then
   dDotBorder(COL[c],PY_M,ZW_MAIN,ZH,CAT)
  end
 end
 dZone(COL[4],PY_M,ZW_SPEC,ZH,CGY,"GY",#G.gy[1])

 dZone(COL[0],PY_S,ZW_SPEC,ZH,CED,"ED")
 for c=1,3 do
  local card=G.st[1][c]
  dFieldSlot(COL[c],PY_S,card,card and card.facedown,CZ)
  if G.mode=="sel_st" and not card then dDotBorder(COL[c],PY_S,ZW_MAIN,ZH) end
  if G.mode=="opp_trap_select" and G.trapSelect and card and card.facedown and not card.setThisTurn then
   for _,check in ipairs(TRAP_CHECKS[G.trapSelect.event] or {}) do
    if card.effect==check.effect and check.trigger(card,G.trapSelect.ctx) then
     dDotBorder(COL[c],PY_S,ZW_MAIN,ZH); break
    end
   end
  end
 end
 dZone(COL[4],PY_S,ZW_SPEC,ZH,CDK,"DK",#G.deck[1])

 local ph=math.min(#G.hand[1],MAX_HAND)
 for i=0,ph-1 do
  dHandPlr(handX(ph,i),PY_H,G.hand[1][i+1])
 end
end

-- Cursor overlay
function drawCursor()
 local c=G.cur
 local cx,cy,cw,ch

 if c.row==3 then
  local n=#G.hand[c.side]
  if n==0 or c.col>=n then return end
  cx=handX(math.min(n,MAX_HAND),c.col)
  cy=(c.side==1) and PY_H or OY_H
  cw=HW
  ch=(c.side==1) and PHH or OHH
 elseif c.side==1 then
  cx,cy=COL[c.col],(c.row==1) and PY_M or PY_S
  cw,ch=colW(c.col),ZH
 else
  cx,cy=COL[c.col],(c.row==1) and OY_M or OY_S
  cw,ch=colW(c.col),ZH
 end

 local curCol=(G.mode=="sel_atk") and CAT or CSEL
 dCursor(cx,cy,cw,ch,curCol)
end

-- ============================================================
-- INFO PANEL (x=0..PANEL_W-1)
-- ============================================================
function drawPanel()
 line(SEP_X,0,SEP_X,SH-1,CD)
 local pw=PANEL_W-4

 -- Opponent LP
 dLPBar(2,0,pw,G.dispLp[2])

 -- Hovered card info
 local c=G.cur
 local card=getHoveredCard()
 local facedown=(c.side==2 and c.row==3)
 if c.side==2 and card and card.facedown then facedown=true end

 -- Card type label + color (used in name/type/desc)
 local function cardTypeInfo(cd)
  if cd.cat=="spell" then return "SPELL",CSP end
  if cd.cat=="trap"  then return "TRAP",CTR end
  if cd.effect then return "EFFECT MONSTER",CME end
  return "NORMAL MONSTER",CCA
 end

 -- Section 1: name, stars, portrait+stats (y=10..56)
 if card and not facedown then
  -- Name: scroll if too wide to fit before attribute icon
  local nameStr=card.name or "?"
  local nameAvail=PANEL_W-12  -- 73px before attr icon
  local nameW=#nameStr*4
  if nameW<=nameAvail then
   print(nameStr,2,11,CT,true,1,true)
  else
   local ns=G.nameScroll
   if ns.card~=card then ns.card=card; ns.offset=0; ns.pause=NAME_SCROLL_PAUSE; ns.atEnd=false end
   if ns.pause>0 then
    ns.pause=ns.pause-1
   elseif ns.atEnd then
    ns.offset=0; ns.atEnd=false; ns.pause=NAME_SCROLL_PAUSE
   elseif G.tick%3==0 then
    ns.offset=ns.offset+1
    if ns.offset>nameW-nameAvail then
     ns.offset=nameW-nameAvail; ns.atEnd=true; ns.pause=NAME_SCROLL_PAUSE//2
    end
   end
   clip(2,11,nameAvail,7)
   print(nameStr,2-ns.offset,11,CT,true,1,true)
   clip()
  end
  -- Attribute icon: monster attribute, or spell/trap marker
  local attrKey=(card.cat=="monster") and card.attr or card.cat
  local attrSpr=attrKey and ATTR_SPR[attrKey]
  if attrSpr then spr(attrSpr,PANEL_W-10,10,0,1,0,0,1,1) end
  -- Level stars (monster only), 1px gap between
  if card.cat=="monster" and card.lvl then
   for i=1,card.lvl do spr(SPR_STAR,2+(i-1)*6,18,0,1,0,0,1,1) end
  end
  -- Portrait 32x32 (spell/trap shift up since there are no stars above)
  local artY=(card.cat=="monster") and 24 or 21
  if card.spr then spr(card.spr,2,artY,card.bg,2,0,0,2,2) end
  -- Right pane: stats (monster) or subtype icon+label (spell/trap)
  if card.cat=="monster" then
   local onField=(c.row==1)
   local effAtk=onField and getMonAtk(card) or card.atk
   local atkCol=CT
   if onField then
    if effAtk>card.atk then atkCol=3 elseif effAtk<card.atk then atkCol=1 end
   end
   local effDef=onField and getMonDef(card) or card.def
   local defCol=CT
   if onField then
    if effDef>card.def then defCol=3 elseif effDef<card.def then defCol=1 end
   end
   print("ATK "..effAtk,38,27,atkCol,true,1,true)
   print("DEF "..effDef,38,34,defCol,true,1,true)
   print((card.pos==2) and "DEF POS" or "ATK POS",38,41,CT,true,1,true)
   if card.type then print(card.type:upper(),38,48,CD,true,1,true) end
  elseif card.cat=="spell" or card.cat=="trap" then
   local k=card.subtype or "normal"
   local sp=KIND_SPR[k]
   if sp then spr(sp,51,artY+2,0,2,0,0,1,1) end  -- 16x16, aligned with art
   local lbl=k:upper()
   print(lbl,38+(45-#lbl*4)//2,artY+22,CT,true,1,true)
  end
 elseif facedown and card then
  print("???",2,11,CT,true,1,true)
 end
 line(0,57,PANEL_W-1,57,CD)

 -- Section 2: turn + phase (big font, one row)
 print("TURN "..G.turn,2,60,CT,true,1,false)
 local phase=PHASES[G.ph]
 local phCol=(G.active==1) and CCR or CT
 print(phase,PANEL_W-2-#phase*6,60,phCol,true,1,false)
 line(0,68,PANEL_W-1,68,CD)

 -- Section 3: description / mode hints / menu (y=71+)
 if G.mode=="sel_atk" then
  local hasOppMon=hasMonsters(2)
  print(hasOppMon and "SELECT TARGET" or "DIRECT ATK",2,71,CCR,true,1,true)
  print("A: attack",2,79,CD,true,1,true)
  print("B: cancel",2,86,CD,true,1,true)
 elseif G.mode=="sel_tribute" then
  local p=G.pending
  print("TRIBUTE "..(p and #p.tributes or 0).."/".. (p and p.tribNeeded or 0),2,71,CFS,true,1,true)
  print("A: pick",2,79,CD,true,1,true)
  print("B: cancel",2,86,CD,true,1,true)
 elseif G.mode=="sel_mon" then
  print("SELECT ZONE",2,71,CLP,true,1,true)
  print("A: place",2,79,CD,true,1,true)
  print("B: cancel",2,86,CD,true,1,true)
 elseif G.mode=="sel_st" then
  print("SET ZONE",2,71,CLP,true,1,true)
  print("A: place",2,79,CD,true,1,true)
  print("B: cancel",2,86,CD,true,1,true)
 elseif G.mode=="trap_ask" and G.trapAsk then
  print("ACTIVATE?",2,71,CTR,true,1,true)
  print(string.sub(G.trapAsk.card.name,1,20),2,79,CT,true,1,true)
  print("A: yes",2,87,CD,true,1,true)
  print("B: no",2,94,CD,true,1,true)
 elseif G.mode=="opp_trap_select" then
  print("ACTIVATE TRAP?",2,71,CTR,true,1,true)
  local sel=G.st[1][G.cur.col]
  if sel and sel.facedown then print(string.sub(sel.name,1,20),2,79,CT,true,1,true) end
  print("A: activate",2,87,CD,true,1,true)
  print("B: pass",2,94,CD,true,1,true)
 elseif G.mode=="free" and card and not facedown then
  local tLabel,tCol=cardTypeInfo(card)
  print(tLabel,2,71,tCol,true,1,true)
  if card.desc then printWrap(card.desc,2,79,pw,CD,SH-10) end
 elseif G.menu.hint then
  print("no action",2,71,CD,true,1,true)
  G.menu.hint=nil
 end

 -- Action menu (covers description area)
 if G.menu.open then
  rect(0,70,PANEL_W,57,CB)
  for i,item in ipairs(G.menu.items) do
   local iy=72+(i-1)*8
   if i==G.menu.sel then
    rect(0,iy-1,PANEL_W-1,8,CDK)
    print(">"..item[1],2,iy,CCR,true,1,false)
   else
    print(" "..item[1],2,iy,CT,true,1,false)
   end
  end
  line(0,72+(#G.menu.items)*8,PANEL_W-1,72+(#G.menu.items)*8,CD)
 end

 -- Player LP (no separator)
 dLPBar(2,SH-9,pw,G.dispLp[1])
end

-- ============================================================
-- INPUT
-- ============================================================
function resetTurnFlags()
 for i=1,3 do
  if G.mon[1][i] then G.mon[1][i].attacked=false;G.mon[1][i].summoned=false;G.mon[1][i].posChanged=false end
  if G.mon[2][i] then G.mon[2][i].attacked=false;G.mon[2][i].summoned=false;G.mon[2][i].posChanged=false end
  if G.st[1][i] then G.st[1][i].setThisTurn=false end
  if G.st[2][i] then G.st[2][i].setThisTurn=false end
 end
 G.legionSummonUsed=false
 G.legionSearchUsed=false
 G.extraSpellcasterSummon=false
 G.legionSearchPending=false
end

function legionSearch(onDone)
 if G.legionSearchUsed then if onDone then onDone() end; return end
 G.legionSearchUsed=true
 local captured={}
 local items={}
 local function addItem(source,card,realIdx)
  if card.type=="spellcaster" and not card.effect then
   local n=#captured+1
   captured[n]={source=source,realIdx=realIdx}
   table.insert(items,{deckIdx=n,name=card.name,atk=card.atk,def=card.def,lvl=card.lvl,desc=card.desc})
  end
 end
 for i,id in ipairs(G.deck[1]) do addItem("deck",CARDS[id],i) end
 for i,card in ipairs(G.gy[1])  do addItem("gy",card,i) end
 if #items==0 then if onDone then onDone() end; return end
 G.mode="sel_deck"
 G.deckSel={
  items=items,sel=1,title="LEGION  SPELLCASTER",
  onPick=function(idx)
   local src=captured[idx]
   if src.source=="deck" then
    table.insert(G.hand[1],makeCard(table.remove(G.deck[1],src.realIdx)))
   else
    table.insert(G.hand[1],table.remove(G.gy[1],src.realIdx))
   end
   if onDone then onDone() end
  end,
 }
end

function handleInput()
 if G.winner then
  local elapsed=G.tick-(G.winTick or 0)
  if elapsed>90 and btnp(4) then sync(3,0,false); SCENE="menu"; TITLE_SEL=1; G={tick=G.tick} end
  return
 end
 if #ANIM>0 then return end
 if G.infoCard then
  if btnp(5) or btnp(4) then G.infoCard=nil end
  return
 end
 local c=G.cur

 -- Deck selection (Sangan etc.)
 if G.mode=="sel_deck" and G.deckSel then
  handleDeckSelectInput()
  return
 end

 -- Graveyard viewer
 if G.mode=="gy_view" and G.gyView then
  local gv=G.gyView
  local gy=G.gy[gv.plr]
  if btnp(0) then gv.sel=math.min(#gy,gv.sel+1)
  elseif btnp(1) then gv.sel=math.max(1,gv.sel-1)
  elseif btnp(5) then G.mode="free"; G.gyView=nil end
  return
 end

 -- Trap activation prompt (fires during opponent's turn)
 if G.mode=="trap_ask" and G.trapAsk then
  if btnp(4) then
   local ta=G.trapAsk
   G.mode="free"; G.trapAsk=nil
   if ta.fromHand then
    table.remove(G.hand[1],ta.handIdx)
    table.insert(G.gy[1],ta.card)
    ta.onYes()
   else
    activateTrapAnim(ta.col,ta.card,ta.onYes)
   end
  elseif btnp(5) then
   local ta=G.trapAsk
   G.mode="free"; G.trapAsk=nil
   if ta.onNo then ta.onNo() end
  end
  return
 end

 -- Opponent-turn trap activation menu
 if G.mode=="opp_trap_select" and G.trapSelect then
  handleOppTrapSelectInput()
  return
 end

 -- Attack target selection: cursor on opponent's monster zones
 if G.mode=="sel_atk" then
  local hasOppMon=hasMonsters(2)
  if btnp(2) then
   c.col=math.max(1,c.col-1)
  elseif btnp(3) then
   c.col=math.min(3,c.col+1)
  elseif btnp(4) then  -- A: confirm attack
   local p=G.pending
   if checkAITraps("attack",{}) then
    G.mode="free"; G.pending=nil
   elseif not hasOppMon then
    resolveAttack(p.attacker,p.atkCol,nil,nil)
   else
    local tgtIdx=4-c.col
    local target=G.mon[2][tgtIdx]
    if target then
     resolveAttack(p.attacker,p.atkCol,target,tgtIdx)
    end
   end
  elseif btnp(5) then  -- B: cancel
   local col=G.pending and G.pending.atkCol or 2
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=1,col=col}
  end
  return
 end

 -- Tribute-select mode: pick monsters to tribute before summoning
 if G.mode=="sel_tribute" then
  if btnp(2) then
   for col=c.col-1,1,-1 do if G.mon[1][col] then c.col=col; break end end
  elseif btnp(3) then
   for col=c.col+1,3 do if G.mon[1][col] then c.col=col; break end end
  elseif btnp(4) then  -- A: toggle tribute selection
   local p=G.pending
   local col=c.col
   if col>=1 and col<=3 and G.mon[1][col] then
    local found=false
    for i,t in ipairs(p.tributes) do
     if t==col then table.remove(p.tributes,i); found=true; break end
    end
    if not found and #p.tributes<p.tribNeeded then
     table.insert(p.tributes,col)
    end
    if #p.tributes==p.tribNeeded then
     local tribs={}
     for _,v in ipairs(p.tributes) do table.insert(tribs,v) end
     local zones={}
     for _,tcol in ipairs(tribs) do
      table.insert(zones,{x=COL[tcol],y=PY_M})
     end
     animTribute(zones,function()
      local legionTributed=false
      for _,tcol in ipairs(tribs) do
       local m=G.mon[1][tcol]
       if m and m.effect=="legion" then legionTributed=true end
       table.insert(G.gy[1],m); G.mon[1][tcol]=nil
      end
      if legionTributed and not G.legionSearchUsed then G.legionSearchPending=true end
      G.mode="sel_mon"
      G.cur={side=1,row=1,col=firstEmpty(G.mon[1]) or 1}
     end)
    end
   end
  elseif btnp(5) then  -- B: cancel
   local idx=G.pending and G.pending.handIdx-1 or 0
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=3,col=idx}
  end
  return
 end

 -- Zone-select mode: cursor locked to valid target zones
 if G.mode=="sel_mon" then
  if btnp(2) then  -- left: skip to prev empty zone
   for col=c.col-1,1,-1 do
    if not G.mon[1][col] then c.col=col; break end
   end
  elseif btnp(3) then  -- right: skip to next empty zone
   for col=c.col+1,3 do
    if not G.mon[1][col] then c.col=col; break end
   end
  elseif btnp(4) then  -- A: place card
   local col=c.col
   if col>=1 and col<=3 and not G.mon[1][col] then
    local p=G.pending
    local card=p.card
    if p.action=="set" then
     card=copyCard(p.card)
     card.pos=2; card.facedown=true
    end
    G.mon[1][col]=card
    card.summoned=true
    table.remove(G.hand[1],p.handIdx)
    if p.action=="summon" or p.action=="set" then G.normalSummoned=true end
    if p.action=="summon_extra" then G.extraSpellcasterSummon=false end
    G.mode="free"; G.pending=nil
    G.cur={side=1,row=1,col=col}
    if G.legionSearchPending then
     G.legionSearchPending=false; legionSearch()
    end
    checkAITraps("summon",{card=card,monIdx=col})
   end
  elseif btnp(5) then  -- B: cancel, return cursor to the hand card
   local idx=G.pending and G.pending.handIdx-1 or 0
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=3,col=idx}
  end
  return
 end

 -- Spell/trap zone-select mode
 if G.mode=="sel_st" then
  if btnp(2) then
   for col=c.col-1,1,-1 do if not G.st[1][col] then c.col=col; break end end
  elseif btnp(3) then
   for col=c.col+1,3 do if not G.st[1][col] then c.col=col; break end end
  elseif btnp(4) then
   local col=c.col
   if col>=1 and col<=3 and not G.st[1][col] then
    local p=G.pending
    local card=copyCard(p.card)
    if p.action=="cast_hand" then
     card.facedown=false
     G.st[1][col]=card
     table.remove(G.hand[1],p.handIdx)
     G.mode="free"; G.pending=nil
     G.cur={side=1,row=2,col=col}
     animSpellActivation(col,PY_S,card,1)
    else
     card.facedown=true; card.setThisTurn=true
     G.st[1][col]=card
     table.remove(G.hand[1],p.handIdx)
     G.mode="free"; G.pending=nil
     G.cur={side=1,row=2,col=col}
    end
   end
  elseif btnp(5) then
   local idx=G.pending and G.pending.handIdx-1 or 0
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=3,col=idx}
  end
  return
 end

 -- Equip spell: pick a face-up monster target
 if G.mode=="sel_equip" then
  if btnp(2) then c.col=math.max(1,c.col-1)
  elseif btnp(3) then c.col=math.min(3,c.col+1)
  elseif btnp(0) then if c.side==2 then c.side=1 end
  elseif btnp(1) then if c.side==1 then c.side=2 end
  elseif btnp(4) then
   local ti=(c.side==2) and (4-c.col) or c.col
   local target=G.mon[c.side][ti]
   if target and not target.facedown then
    local p=G.pending; G.mode="free"; G.pending=nil
    local card=p.card
    card.equippedTo={plr=c.side,col=ti}
    if p.action=="cast_equip" then
     local stCol=firstEmpty(G.st[1])
     if stCol then
      card.facedown=false
      G.st[1][stCol]=card
      table.remove(G.hand[1],p.handIdx)
      animSpellActivation(stCol,PY_S,card,1)
     end
    else  -- activate_equip (already in zone)
     card.facedown=false
     animSpellActivation(p.stCol,PY_S,card,1)
    end
    G.cur={side=1,row=2,col=firstOccupied(G.st[1]) or 1}
   end
  elseif btnp(5) then
   local idx=G.pending and G.pending.handIdx and G.pending.handIdx-1 or G.pending and G.pending.stCol or 0
   G.mode="free"; G.pending=nil
   G.cur={side=1,row=3,col=idx}
  end
  return
 end

 -- Man-EaterBug FLIP: pick any monster to destroy
 if G.mode=="sel_destroy" then
  if btnp(2) then c.col=math.max(1,c.col-1)
  elseif btnp(3) then c.col=math.min(3,c.col+1)
  elseif btnp(0) then if c.side==1 then c.side=2 end
  elseif btnp(1) then if c.side==2 then c.side=1 end
  elseif btnp(4) then
   local ti=(c.side==2) and (4-c.col) or c.col
   local grid=(c.side==1) and G.mon[1] or G.mon[2]
   if ti>=1 and ti<=3 and grid[ti] then
    local ds=G.destroySel
    G.mode="free"; G.destroySel=nil
    ds.onPick(c.side,ti)
   end
  end
  return
 end

 -- Menu open: route all input into the menu
 if G.menu.open then
  if btnp(0) then  -- up
   G.menu.sel=math.max(1,G.menu.sel-1)
  elseif btnp(1) then  -- down
   G.menu.sel=math.min(#G.menu.items,G.menu.sel+1)
  elseif btnp(4) then  -- A: confirm
   execAction(G.menu.items[G.menu.sel][2])
  elseif btnp(5) then  -- B: cancel
   G.menu.open=false
  end
  return
 end

 if btnp(0) then  -- up (toward opponent)
  local wasHand=(c.row==3)
  if c.side==1 then
   if    c.row==3 then c.row=2
   elseif c.row==2 then c.row=1
   else  c.side=2;c.row=1 end
  else
   if    c.row==1 then c.row=2
   elseif c.row==2 then c.row=3 end
  end
  if c.row==3 then clampToHand(c.side)
  elseif wasHand then c.col=math.min(c.col,4) end
 end

 if btnp(1) then  -- down (toward player)
  local wasHand=(c.row==3)
  if c.side==2 then
   if    c.row==3 then c.row=2
   elseif c.row==2 then c.row=1
   else  c.side=1;c.row=1 end
  else
   if    c.row==1 then c.row=2
   elseif c.row==2 then c.row=3 end
  end
  if c.row==3 then clampToHand(c.side)
  elseif wasHand then c.col=math.min(c.col,4) end
 end

 if btnp(2) then  -- left
  c.col=math.max(0,c.col-1)
 end

 if btnp(3) then  -- right
  if c.row==3 then
   c.col=math.min(math.max(0,#G.hand[c.side]-1),c.col+1)
  else
   c.col=math.min(4,c.col+1)
  end
 end

 if btnp(4) then
  if c.row==1 and c.col==4 and c.side==1 then  -- player GY
   if #G.gy[1]>0 then G.mode="gy_view"; G.gyView={plr=1,sel=#G.gy[1]} end
  elseif c.row==1 and c.col==0 and c.side==2 then  -- opp GY
   if #G.gy[2]>0 then G.mode="gy_view"; G.gyView={plr=2,sel=#G.gy[2]} end
  else
   local items=buildMenu()
   if items then
    G.menu={open=true,items=items,sel=1}
   else
    G.menu={open=false,items={},sel=1,hint=true}
   end
  end
 end

 -- B: open phase menu (player turn, free mode, no menu already open)
 if btnp(5) and G.active==1 and not G.menu.open then
  G.menu={open=true,sel=1,items={
   {"NEXT PHASE","nextphase"},
   {"END TURN",  "endturn"},
  }}
 end
end

-- ============================================================
-- AUTO-PHASE (player DRAW and STBY advance automatically)
-- ============================================================
function autoPhase()
 if G.active~=1 or G.winner or #ANIM>0 then return end
 if G.ph~=PH_DRAW and G.ph~=PH_STBY and G.ph~=PH_END then return end
 G.autoTimer=G.autoTimer-1
 if G.autoTimer<=0 then
  G.autoTimer=50
  if G.ph==PH_END then
   G.turn=G.turn+1; G.active=2; changePhase(PH_DRAW)
   G.normalSummoned=false; drawCard(2)
   resetTurnFlags(); G.aiTimer=AI_DELAY
  else
   changePhase(G.ph+1)
  end
 end
end

-- ============================================================
-- TRAP PROMPT HELPERS
-- ============================================================
function promptTrap(col,card,onYes,onNo)
 G.mode="trap_ask"
 G.trapAsk={col=col,card=card,onYes=onYes,onNo=onNo}
end

function callHauntedActivate(trap,onDone)
 local items={}
 for i,c in ipairs(G.gy[1]) do
  if c.cat=="monster" then
   table.insert(items,{deckIdx=i,name=c.name,atk=c.atk,def=c.def,lvl=c.lvl,desc=c.desc})
  end
 end
 if #items==0 then if onDone then onDone() end; return end
 G.mode="sel_deck"
 G.deckSel={
  items=items,sel=1,title="CALL OF THE HAUNTED",
  onPick=function(gyIdx)
   local emptyCol=firstEmpty(G.mon[1])
   if emptyCol then
    local m=table.remove(G.gy[1],gyIdx)
    m.pos=1; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
    G.mon[1][emptyCol]=m
    for c=1,3 do
     if G.st[1][c]==trap then trap.linkedMon=m; m.linkedTrap=trap; break end
    end
   end
   if onDone then onDone() end
  end,
 }
end

-- Flip-up animation for an AI trap in G.st[2][stCol], then calls onDone.
function activateAITrapAnim(stCol,card,onDone)
 card.facedown=false
 local zx=COL[4-stCol]
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,OY_S,ZW_MAIN,ZH,CTR); rectb(zx,OY_S,ZW_MAIN,ZH,CT) end
 end,function()
  G.st[2][stCol]=nil; table.insert(G.gy[2],card)
  onDone()
 end)
end

-- Auto-activate the first matching AI face-down trap against a player action.
function checkAITraps(event,ctx)
 if event=="summon" then
  -- Trap Hole: fires on a face-up summon with ATK >= 1000
  if not ctx.card.facedown and (ctx.card.atk or 0)>=1000 then
   for i=1,3 do
    local t=G.st[2][i]
    if t and t.facedown and not t.setThisTurn and t.effect=="traphole" then
     activateAITrapAnim(i,t,function()
      if G.mon[1][ctx.monIdx]==ctx.card then
       destroyFlash(COL[ctx.monIdx],PY_M)
       table.insert(G.gy[1],ctx.card); G.mon[1][ctx.monIdx]=nil
       deferEffects({{card=ctx.card,plr=1}})
       checkWin()
      end
     end)
     return true
    end
   end
  end
 elseif event=="attack" then
  -- Mirror Force: fires on any attack declaration
  for i=1,3 do
   local t=G.st[2][i]
   if t and t.facedown and not t.setThisTurn and t.effect=="mirrorforce" then
    activateAITrapAnim(i,t,function()
     applyEffect(t,2)  -- mirrorforce(2) destroys all player ATK monsters
     checkWin()
    end)
    return true
   end
  end
 end
 return false
end

TRAP_CHECKS={
 summon={
  {effect="traphole",
   trigger=function(t,ctx) return not ctx.card.facedown and (ctx.card.atk or 0)>=1000 end,
   onYes=function(t,ctx)
    if G.mon[2][ctx.monIdx]==ctx.card then
     table.insert(G.gy[2],ctx.card); G.mon[2][ctx.monIdx]=nil
    end
    returnToTrapSelect()
   end},
 },
 attack={
  {effect="mirrorforce",
   trigger=function(t,ctx) return true end,
   onYes=function(t,ctx)
    G.trapSelect.consumed=true; G.battleAnim=nil; applyEffect(t,1); returnToTrapSelect() end},
  {effect="callhaunted",
   trigger=function(t,ctx)
    for _,c in ipairs(G.gy[1]) do if c.cat=="monster" then
     return firstEmpty(G.mon[1])~=nil end end return false end,
   onYes=function(t,ctx) callHauntedActivate(t,returnToTrapSelect) end},
 },
 phase={
  {effect="callhaunted",
   trigger=function(t,ctx)
    for _,c in ipairs(G.gy[1]) do if c.cat=="monster" then
     return firstEmpty(G.mon[1])~=nil end end return false end,
   onYes=function(t,ctx) callHauntedActivate(t,returnToTrapSelect) end},
 },
}

function activateTrapAnim(col,card,onYes)
 card.facedown=false
 local zx=COL[col]
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,PY_S,ZW_MAIN,ZH,CTR); rectb(zx,PY_S,ZW_MAIN,ZH,CT) end
 end,function()
  if card.subtype~="continuous" then G.st[1][col]=nil; table.insert(G.gy[1],card) end
  onYes()
 end)
end

function hasActivatableTrap(event,ctx)
 local checks=TRAP_CHECKS[event]
 if not checks then return false end
 for _,check in ipairs(checks) do
  for i=1,3 do
   local t=G.st[1][i]
   if t and t.facedown and not t.setThisTurn and t.effect==check.effect and check.trigger(t,ctx) then
    return true
   end
  end
 end
 return false
end

function returnToTrapSelect()
 if not G.trapSelect then return end
 if hasActivatableTrap(G.trapSelect.event,G.trapSelect.ctx) then
  G.mode="opp_trap_select"
  -- move cursor to first valid trap if current is no longer activatable
  local col=G.cur.col
  local valid=false
  for _,check in ipairs(TRAP_CHECKS[G.trapSelect.event] or {}) do
   local t=G.st[1][col]
   if t and t.facedown and not t.setThisTurn and t.effect==check.effect and check.trigger(t,G.trapSelect.ctx) then
    valid=true; break
   end
  end
  if not valid then
   for _,check in ipairs(TRAP_CHECKS[G.trapSelect.event] or {}) do
    for i=1,3 do
     local t=G.st[1][i]
     if t and t.facedown and not t.setThisTurn and t.effect==check.effect and check.trigger(t,G.trapSelect.ctx) then
      G.cur={side=1,row=2,col=i}; return
     end
    end
   end
  end
 else
  finishTrapSelect()
 end
end

function finishTrapSelect()
 local ts=G.trapSelect
 G.mode="free"; G.trapSelect=nil
 if not ts.consumed then
  if ts.ctx.doAttack then ts.ctx.doAttack()
  elseif ts.ctx.proceed then ts.ctx.proceed()
  end
 end
end

function checkTraps(event,ctx)
 if not hasActivatableTrap(event,ctx) then return false end
 G.trapSelect={event=event,ctx=ctx,consumed=false}
 G.mode="opp_trap_select"
 for _,check in ipairs(TRAP_CHECKS[event] or {}) do
  for i=1,3 do
   local t=G.st[1][i]
   if t and t.facedown and not t.setThisTurn and t.effect==check.effect and check.trigger(t,ctx) then
    G.cur={side=1,row=2,col=i}; return true
   end
  end
 end
 return true
end

function handleOppTrapSelectInput()
 local ts=G.trapSelect
 if btnp(2) then G.cur.col=math.max(1,G.cur.col-1)
 elseif btnp(3) then G.cur.col=math.min(3,G.cur.col+1)
 elseif btnp(4) then
  local col=G.cur.col
  local card=G.st[1][col]
  if card and card.facedown and not card.setThisTurn then
   for _,check in ipairs(TRAP_CHECKS[ts.event] or {}) do
    if card.effect==check.effect and check.trigger(card,ts.ctx) then
     G.mode="free"
     activateTrapAnim(col,card,function() check.onYes(card,ts.ctx) end)
     return
    end
   end
  end
 elseif btnp(5) then
  finishTrapSelect()
 end
end

-- ============================================================
-- AI
-- ============================================================
AI_DELAY=40  -- frames between AI actions (~0.67s at 60fps)

function aiDoMain()
 local plrHasMon=hasMonsters(1)
 -- Activate direct-damage / board-wipe spells (one per tick)
 for i=#G.hand[2],1,-1 do
  local card=G.hand[2][i]
  if card.cat=="spell" then
   local ef=card.effect
   local doIt=(ef=="ookazi")
           or ((ef=="raigeki" or ef=="fissure" or ef=="darkhole") and plrHasMon)
   if doIt then
    table.remove(G.hand[2],i)
    local stIdx=nil
    for j=1,3 do if not G.st[2][j] then stIdx=j; break end end
    if stIdx then
     G.st[2][stIdx]=card
     animSpellActivation(stIdx,OY_S,card,2)
    else
     table.insert(G.gy[2],card); applyEffect(card,2)
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
         or (trib==1 and #occupied>=1)
         or (trib==2 and #occupied>=2)
   if ok and card.atk>bestAtk then bestAtk=card.atk; bestIdx=i end
  end
 end
 if not bestIdx then return false end
 local card=G.hand[2][bestIdx]
 local trib=tribsNeeded(card.lvl)
 -- Set face-down DEF when defense stat exceeds attack stat
 local useDefPos=(card.def or 0)>card.atk
 if trib>0 then
  table.sort(occupied,function(a,b) return G.mon[2][a].atk<G.mon[2][b].atk end)
  local tribs={}
  for i=1,trib do table.insert(tribs,occupied[i]) end
  table.remove(G.hand[2],bestIdx); G.normalSummoned=true
  local zones={}
  for _,tcol in ipairs(tribs) do
   table.insert(zones,{x=COL[4-tcol],y=OY_M})
  end
  animTribute(zones,function()
   for _,tcol in ipairs(tribs) do
    table.insert(G.gy[2],G.mon[2][tcol]); G.mon[2][tcol]=nil
   end
   local empI=firstEmpty(G.mon[2])
   card.summoned=true
   if useDefPos then card.pos=2; card.facedown=true end
   G.mon[2][empI]=card
   checkTraps("summon",{card=card,monIdx=empI})
  end)
  return true
 end
 table.remove(G.hand[2],bestIdx)
 card.summoned=true
 if useDefPos then card.pos=2; card.facedown=true end
 G.mon[2][empty[1]]=card; G.normalSummoned=true
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
   local dPlr=false; local dOpp=false
   local triggered={}
   local atkV=getMonAtk(attacker); local tgtV=getMonAtk(target); local tgtDef=getMonDef(target)
   if target.pos==2 then
    if atkV>tgtDef then
     table.insert(G.gy[1],target); G.mon[1][tgtCol]=nil; dPlr=true
     table.insert(triggered,{card=target,plr=1})
    elseif atkV<tgtDef then
     changeLp(2,-(target.def-atkV))
    end
   else
    if atkV>tgtV then
     table.insert(G.gy[1],target); G.mon[1][tgtCol]=nil
     applyDamage(1,atkV-tgtV); dPlr=true
     table.insert(triggered,{card=target,plr=1})
    elseif atkV<tgtV then
     table.insert(G.gy[2],attacker); G.mon[2][atkCol]=nil
     changeLp(2,-(tgtV-atkV)); dOpp=true
     table.insert(triggered,{card=attacker,plr=2})
    else
     table.insert(G.gy[1],target); G.mon[1][tgtCol]=nil
     table.insert(G.gy[2],attacker); G.mon[2][atkCol]=nil
     dPlr=true; dOpp=true
     table.insert(triggered,{card=target,plr=1})
     table.insert(triggered,{card=attacker,plr=2})
    end
   end
   if dPlr then destroyFlash(COL[tgtCol],PY_M) end
   if dOpp then destroyFlash(COL[4-atkCol],OY_M) end
   G.battleAnim=nil
   checkWin()
   deferEffects(triggered)
   if wasFlipped then triggerMonEffect(target,"onFlip",1) end
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
   if t.pos==2 then s=getMonDef(t); ok=(attAtk>s)
   else          s=getMonAtk(t);   ok=(attAtk>=s) end
   if ok and s<bestScore then bestScore=s; bestCol=j end
  end
 end
 return bestCol
end

function aiDoNextAttack()
 for i=G.aiBattleIdx,3 do
  local att=G.mon[2][i]
  if att and att.pos==1 and not att.facedown and not att.attacked then
   G.aiBattleIdx=i+1
   local hasPlr=hasMonsters(1)
   local tgtCol=hasPlr and aiBestTarget(att) or nil
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
 return false
end

function aiTick()
 if G.active~=2 or G.winner or #ANIM>0 or G.menu.open or G.infoCard or G.mode=="trap_ask" or G.mode=="sel_deck" or G.mode=="sel_destroy" or G.mode=="opp_trap_select" then return end
 G.aiTimer=G.aiTimer-1
 if G.aiTimer>0 then return end
 G.aiTimer=AI_DELAY
 if G.ph==PH_DRAW then
  local function go() changePhase(PH_STBY) end
  if not checkTraps("phase",{proceed=go}) then go() end
 elseif G.ph==PH_STBY then
  local function go() changePhase(PH_MAIN) end
  if not checkTraps("phase",{proceed=go}) then go() end
 elseif G.ph==PH_MAIN then
  if not aiDoMain() then
   local function go() G.aiBattleIdx=1; changePhase(PH_BATTLE) end
   if not checkTraps("phase",{proceed=go}) then go() end
  end
 elseif G.ph==PH_BATTLE then
  if not aiDoNextAttack() then
   local function go() changePhase(PH_END) end
   if not checkTraps("phase",{proceed=go}) then go() end
  end
 elseif G.ph==PH_END then
  G.turn=G.turn+1; G.active=1; changePhase(PH_DRAW)
  G.normalSummoned=false; drawCard(1); G.autoTimer=50
  resetTurnFlags()
 end
end

-- ============================================================
-- TITLE SCREEN / MENU
-- ============================================================
function drawTitle()
 cls(CB)
 rect(0,0,SW,8,CB)
 spr(128,-8,0,0,2,0,0,16,8)
 if (G.tick//30)%2==0 then
  local t="PRESS A TO CONTINUE"
  print(t,(SW-#t*6)//2,SH-8,CT,true,1,false)
 end
end

-- Face-up card colors for each menu option
MENU_COLORS={CCA, 4, 13}  -- DUEL=tan, DECK=blue, OPTIONS=purple

function drawMenu()
 -- Background: navy playmat + dither + gold border (matches duel)
 cls(CMAT)
 for y=0,SH-1,4 do for x=0,SW-1,4 do pix(x,y,CB) end end
 rectb(0,0,SW,SH,9)

 -- Logo sprite (16x7 tiles, centered)
 spr(256,(SW-128)//2,0,4,1,0,0,16,7)

 -- Card buttons: visible card content is 20x22 -> scale 2 -> 40x44.
 -- Centering uses the visible size, not the 24x24 sprite-tile size.
 local cw,ch,gap=40,44,16
 local totalW=#TITLE_ITEMS*cw + (#TITLE_ITEMS-1)*gap
 local cx0=(SW-totalW)//2
 local cy=60

 for i,label in ipairs(TITLE_ITEMS) do
  local x=cx0+(i-1)*(cw+gap)
  local sel=(i==TITLE_SEL)
  if sel then
   -- Face-up: colored fill + card frame outline
   rect(x+2,cy+2,cw-4,ch-4,MENU_COLORS[i])
   spr(SPR_FRAME,x,cy,15,2,0,0,3,3)
   spr(8+i*2,x+4,cy+3,14,2,0,0,2,2)
   for j=1,i do spr(SPR_STAR,x+(cw-(i*6-1))//2+(j-1)*6,cy+36,0,1,0,0,1,1) end
   -- Pulsing chevrons flanking the card
   if (G.tick//15)%2==0 then
    print(">",x-6,    cy+ch//2-3,10,true,1,false)
    print("<",x+cw+1, cy+ch//2-3,10,true,1,false)
   end
  else
   -- Face-down: card back sprite
   spr(SPR_CARDBACK,x,cy,15,2,0,0,3,3)
  end
  -- Label below the card (with shadow)
  local lx=x+(cw-#label*6)//2
  print(label,lx+1,cy+ch+5,CB,true,1,false)
  print(label,lx,  cy+ch+4,sel and CCR or CT,true,1,false)
 end

 -- Hint
 local h="ARROWS: select   A: confirm   B: back"
 print(h,(SW-#h*4)//2,SH-7,CD,true,1,true)
end

function handleTitleInput()
 if btnp(4) then SCENE="menu" end
end

function handleMenuInput()
 if btnp(0) or btnp(2) then TITLE_SEL=math.max(1,TITLE_SEL-1)
 elseif btnp(1) or btnp(3) then TITLE_SEL=math.min(#TITLE_ITEMS,TITLE_SEL+1)
 elseif btnp(4) then
  if     TITLE_SEL==1 then startGame()
  elseif TITLE_SEL==2 then startDeckBuild()
  end
  -- OPTIONS: placeholder
 elseif btnp(5) then
  SCENE="title"
 end
end

-- ============================================================
-- DECK BUILDER
-- ============================================================
DB_COLS=4; DB_ROWS=5
DB_CW=20; DB_CH=22; DB_CG=1
DB_LX=87       -- x where right panel starts
DB_LIST_RH=10  -- list row height
DB_LIST_VIS=11 -- visible list rows

function dbGridX(c) return 2+c*(DB_CW+DB_CG) end
function dbGridY(r) return 10+r*(DB_CH+DB_CG) end

function dbCountInDeck(id)
 local n=0
 for _,v in ipairs(DB.deck) do if v==id then n=n+1 end end
 return n
end

-- pmem layout: MAX_DECK card IDs at 5 bits each (so up to 31 unique cards),
-- packed 6 IDs per 32-bit slot. Slots 0..2 hold 6 IDs, slot 3 holds 2.
function dbLoad()
 DB.deck={}
 for slot=0,3 do
  local v=pmem(slot)
  local maxB=(slot<3) and 5 or 1
  for b=0,maxB do
   local id=(v>>(b*5))&0x1f
   if id>0 and id<=#CARDS then
    table.insert(DB.deck,id)
   end
  end
 end
end

function dbSave()
 local ids={}
 for i=1,MAX_DECK do ids[i]=DB.deck[i] or 0 end
 for slot=0,3 do
  local v=0
  local maxB=(slot<3) and 5 or 1
  for b=0,maxB do
   local idx=slot*6+b+1
   if idx<=MAX_DECK then v=v|(ids[idx]<<(b*5)) end
  end
  pmem(slot,v)
 end
end

function startDeckBuild()
 sync(3,1,false)
 DB={deck={},cur={panel=1,row=0,col=0},listSel=1,listScr=0,menu=nil,info=nil}
 dbLoad()
 SCENE="deckbuild"
end

function drawDBInfo(cd)
 local bx,by,bw,bh=20,10,200,116
 rect(bx,by,bw,bh,CB)
 rectb(bx,by,bw,bh,CD)
 rectb(bx+1,by+1,bw-2,bh-2,CD)

 -- Name (big font), top-left
 print(string.sub(cd.name or "?",1,25),bx+5,by+5,CT,true,1,false)

 -- Attribute icon (16x16 = 8x8 scale 2), top-right
 local attrKey=(cd.cat=="monster") and cd.attr or cd.cat
 local attrSpr=attrKey and ATTR_SPR[attrKey]
 if attrSpr then spr(attrSpr,bx+bw-21,by+4,0,2,0,0,1,1) end

 -- Level stars (monster only), 1px gap
 if cd.cat=="monster" and cd.lvl then
  for i=1,cd.lvl do spr(SPR_STAR,bx+5+(i-1)*6,by+13,0,1,0,0,1,1) end
 end

 -- Portrait 32x32 (shifted up for spell/trap since no stars above)
 local artY=(cd.cat=="monster") and by+22 or by+19
 if cd.spr then spr(cd.spr,bx+5,artY,cd.bg,2,0,0,2,2) end

 -- Right of portrait: stats (monster) or subtype icon+label (spell/trap)
 if cd.cat=="monster" then
  print("ATK: "..cd.atk,bx+42,by+20,CT,true,1,false)
  print("DEF: "..cd.def,bx+42,by+30,CT,true,1,false)
  print("LV : "..cd.lvl,bx+42,by+40,CT,true,1,false)
  if cd.type then print(cd.type:upper(),bx+42,by+50,CD,true,1,false) end
 elseif cd.cat=="spell" or cd.cat=="trap" then
  local k=cd.subtype or "normal"
  local sp=KIND_SPR[k]
  if sp then spr(sp,bx+42,artY+2,0,2,0,0,1,1) end  -- 16x16
  print(k:upper(),bx+62,artY+8,CT,true,1,false)
 end

 -- Divider
 line(bx+2,by+58,bx+bw-3,by+58,CD)

 -- Category label (colored, in card's own color)
 local function typeInfo(c)
  if c.cat=="spell" then return "SPELL",CSP end
  if c.cat=="trap"  then return "TRAP",CTR end
  if c.effect then return "EFFECT MONSTER",CME end
  return "NORMAL MONSTER",CCA
 end
 local lbl,col=typeInfo(cd)
 print(lbl,bx+5,by+62,col,true,1,false)

 -- Description (small font, wrapped)
 if cd.desc then printWrap(cd.desc,bx+5,by+72,bw-10,CD,by+bh-10) end

 print("B:close",bx+bw-46,by+bh-8,CD,true,1,true)
end

function drawDeckBuild()
 cls(CB)
 -- Left panel header
 print("DECK "..(#DB.deck).."/"..MAX_DECK,2,1,CT,true,1,false)
 line(0,8,DB_LX-2,8,CD)
 -- Deck grid (4x5 = 20 slots)
 for r=0,DB_ROWS-1 do
  for c=0,DB_COLS-1 do
   local si=r*DB_COLS+c+1
   local x,y=dbGridX(c),dbGridY(r)
   local id=DB.deck[si]
   if id then
    dHandPlr(x,y,makeCard(id))
   else
    rect(x,y,DB_CW,DB_CH,CHL)
    rectb(x,y,DB_CW,DB_CH,CD)
   end
   if DB.cur.panel==1 and DB.cur.row==r and DB.cur.col==c then
    dCursor(x,y,DB_CW,DB_CH)
   end
  end
 end
 -- Panel separator
 line(DB_LX-1,0,DB_LX-1,SH-9,CD)
 -- Right panel header
 print("CARDS",DB_LX+2,1,CCR,true,1,false)
 line(DB_LX,8,SW-1,8,CD)
 -- Card list
 local lx=DB_LX+1
 for i=1,DB_LIST_VIS do
  local ci=DB.listScr+i
  if ci>#CARDS then break end
  local cd=CARDS[ci]
  local iy=9+(i-1)*DB_LIST_RH
  local isSel=(DB.cur.panel==2 and DB.listSel==ci)
  if isSel then rect(DB_LX,iy,SW-DB_LX,DB_LIST_RH-1,CHL) end
  if cd.spr then spr(cd.spr,lx,iy,cd.bg,1,0,0,1,1) end
  local nm=#cd.name>18 and string.sub(cd.name,1,18)..".." or cd.name
  print(nm,lx+9,iy+1,isSel and CB or CT,true,1,false)
  local cnt=dbCountInDeck(ci)
  local cc=(cnt>=MAX_COPIES) and CAT or (cnt>0 and CCR or CD)
  print("x"..cnt,SW-18,iy+1,cc,true,1,false)
 end
 -- Scrollbar (only if list overflows visible area)
 if #CARDS>DB_LIST_VIS then
  local bh=DB_LIST_VIS*DB_LIST_RH
  local pct=DB.listScr/math.max(1,#CARDS-DB_LIST_VIS)
  rect(SW-3,9,2,bh,CB)
  rect(SW-3,9+math.floor(pct*(bh-4)),2,4,CD)
 end
 -- Bottom hint bar
 line(0,SH-8,SW-1,SH-8,CD)
 if not DB.menu then
  print("arrows:move  A:action  B:save",2,SH-6,CD,true,1,true)
 end
 -- Action/save menu overlay (centered)
 if DB.menu then
  local mw=84
  local mh=8+#DB.menu.items*12
  local mx,my=(SW-mw)//2,(SH-mh)//2
  rect(mx,my,mw,mh,CB)
  rectb(mx,my,mw,mh,CD)
  for i,item in ipairs(DB.menu.items) do
   local iy=my+4+(i-1)*12
   if i==DB.menu.sel then
    rect(mx+1,iy-1,mw-2,10,CCR)
    print(item[1],mx+4,iy+1,CB,true,1,false)
   else
    print(item[1],mx+4,iy+1,CT,true,1,false)
   end
  end
 end
 -- Info overlay
 if DB.info then drawDBInfo(DB.info) end
end

function dbExecAction(key,ctx)
 if key=="cancel" then return
 elseif key=="remove" and ctx then
  if ctx.slotIdx then table.remove(DB.deck,ctx.slotIdx) end
 elseif key=="addtodeck" and ctx then
  local id=ctx.cardId
  if id and #DB.deck<MAX_DECK and dbCountInDeck(id)<MAX_COPIES then
   table.insert(DB.deck,id)
  end
 elseif key=="info" and ctx then
  if ctx.cardId then DB.info=CARDS[ctx.cardId] end
 elseif key=="saveexit" then
  dbSave(); sync(3,0,false); SCENE="menu"; TITLE_SEL=2
 elseif key=="exit" then
  sync(3,0,false); SCENE="menu"; TITLE_SEL=2
 end
end

function handleDeckBuildInput()
 if DB.info then
  if btnp(5) then DB.info=nil end
  return
 end
 if DB.menu then
  if btnp(0) then DB.menu.sel=math.max(1,DB.menu.sel-1)
  elseif btnp(1) then DB.menu.sel=math.min(#DB.menu.items,DB.menu.sel+1)
  elseif btnp(4) then
   local item=DB.menu.items[DB.menu.sel]
   local ctx=DB.menu.ctx
   DB.menu=nil
   dbExecAction(item[2],ctx)
  elseif btnp(5) then DB.menu=nil end
  return
 end
 local c=DB.cur
 local function openSaveMenu()
  DB.menu={sel=1,ctx={type="save"},items={
   {"SAVE & EXIT","saveexit"},
   {"EXIT",       "exit"},
   {"CANCEL",     "cancel"},
  }}
 end
 if c.panel==1 then
  if btnp(0,20,4) then c.row=math.max(0,c.row-1)
  elseif btnp(1,20,4) then c.row=math.min(DB_ROWS-1,c.row+1)
  elseif btnp(2) then c.col=math.max(0,c.col-1)
  elseif btnp(3) then
   if c.col<DB_COLS-1 then c.col=c.col+1 else c.panel=2 end
  elseif btnp(4) then
   local si=c.row*DB_COLS+c.col+1
   local id=DB.deck[si]
   if id then
    DB.menu={sel=1,ctx={type="deck",slotIdx=si,cardId=id},items={
     {"REMOVE",  "remove"},
     {"INFO",    "info"},
     {"CANCEL",  "cancel"},
    }}
   end
  elseif btnp(5) then openSaveMenu() end
 else
  if btnp(0,20,4) then
   DB.listSel=math.max(1,DB.listSel-1)
   if DB.listSel<=DB.listScr then DB.listScr=math.max(0,DB.listScr-1) end
  elseif btnp(1,20,4) then
   DB.listSel=math.min(#CARDS,DB.listSel+1)
   if DB.listSel>DB.listScr+DB_LIST_VIS then DB.listScr=DB.listScr+1 end
  elseif btnp(2) then c.panel=1
  elseif btnp(4) then
   DB.menu={sel=1,ctx={type="list",cardId=DB.listSel},items={
    {"ADD TO DECK","addtodeck"},
    {"INFO",       "info"},
    {"CANCEL",     "cancel"},
   }}
  elseif btnp(5) then openSaveMenu() end
 end
end

-- ============================================================
-- ROCK PAPER SCISSORS (determines first player)
-- ============================================================
RPS_NAMES={[1]="ROCK",[2]="PAPER",[3]="SCISSORS"}
RPS_SPRS ={[1]=38,    [2]=40,     [3]=42}
RPS_COLS ={[1]=CME,   [2]=CSP,    [3]=CTR}

function rpsResult(p,ai)
 if p==ai then return 0 end
 if (p==1 and ai==3) or (p==2 and ai==1) or (p==3 and ai==2) then return 1 end
 return 2
end

function startRPS()
 RPS={sel=2, phase="select", playerChoice=nil, aiChoice=nil, winner=0, timer=0}
end

function handleRPSInput()
 if RPS.phase=="select" then
  if btnp(2) then RPS.sel=math.max(1,RPS.sel-1)
  elseif btnp(3) then RPS.sel=math.min(3,RPS.sel+1)
  elseif btnp(4) then
   RPS.playerChoice=RPS.sel
   RPS.aiChoice=math.random(1,3)
   RPS.winner=rpsResult(RPS.playerChoice,RPS.aiChoice)
   RPS.phase="reveal"; RPS.timer=50
  end
 elseif RPS.phase=="result" then
  if btnp(4) then
   if RPS.winner==0 then
    RPS.phase="select"; RPS.sel=2
   else
    G.active=RPS.winner; G.firstPlayer=RPS.winner
    if RPS.winner==2 then G.aiTimer=AI_DELAY end
    TRANS={t=0}
    SCENE="trans"
   end
  end
 end
end

function tickRPS()
 if RPS.phase=="reveal" then
  RPS.timer=RPS.timer-1
  if RPS.timer<=0 then RPS.phase="result" end
 end
end

function drawRPS()
 cls(CMAT)
 for y=0,SH-1,4 do for x=0,SW-1,4 do pix(x,y,CB) end end
 rectb(0,0,SW,SH,9)

 local tw=3*HW+2*HG
 local cx0=(SW-tw)//2

 -- Opponent's 3 face-down half-cards at top (no label)
 for i=0,2 do
  dCardBack(cx0+i*(HW+HG), OY_H, HW, OHH, 0, 0, -11)
 end

 -- Player's 3 face-up RPS cards at bottom (selected sinks down, no label)
 local pcy=PY_H
 for i=0,2 do
  local x=cx0+i*(HW+HG)
  local sel=(i+1==RPS.sel and RPS.phase=="select")
  local y=sel and pcy-5 or pcy
  local fc=RPS_COLS[i+1]
  rect(x+1,y+1,HW-2,PHH-2,fc)
  spr(RPS_SPRS[i+1],x+2,y+2,14,1,0,0,2,2)
  clip(x,y,HW,PHH)
  spr(SPR_FRAME,x,y,15,1,0,0,3,3)
  clip()
 end

 -- Select phase: title + big 2x card preview + flashing name
 -- Preview by=30, size 40x44, bottom=74; name at 77; gap to player cards (pcy=109) is 32px
 if RPS.phase=="select" then
  local t="WHO GOES FIRST?"
  print(t,(SW-#t*6)//2,21,CT,true,1,false)
  local bx=(SW-HW*2)//2; local by=30
  rect(bx+2,by+2,HW*2-4,PHH*2-4,RPS_COLS[RPS.sel])
  spr(RPS_SPRS[RPS.sel],bx+4,by+4,14,2,0,0,2,2)
  clip(bx,by,HW*2,PHH*2)
  spr(SPR_FRAME,bx,by,15,2,0,0,3,3)
  clip()
  local nm=RPS_NAMES[RPS.sel]
  if (G.tick//18)%2==0 then
   print(nm,(SW-#nm*6)//2,77,CCR,true,1,false)
  end
  return
 end

 -- Reveal / Result: chosen cards side by side
 line(4,21,SW-5,21,5)
 local ly=25
 local lx=SW//4-HW//2
 rect(lx+1,ly+1,HW-2,PHH-2,RPS_COLS[RPS.playerChoice])
 spr(RPS_SPRS[RPS.playerChoice],lx+2,ly+2,14,1,0,0,2,2)
 clip(lx,ly,HW,PHH); spr(SPR_FRAME,lx,ly,15,1,0,0,3,3); clip()
 local pn=RPS_NAMES[RPS.playerChoice]
 print("YOU",lx+(HW-3*4)//2,ly+PHH+2,CCR,true,1,true)
 print(pn,lx+(HW-#pn*4)//2,ly+PHH+9,CCR,true,1,true)

 print("VS",SW//2-6,ly+PHH//2-3,CT,true,1,false)

 local rx=3*SW//4-HW//2
 if RPS.phase=="result" then
  rect(rx+1,ly+1,HW-2,PHH-2,RPS_COLS[RPS.aiChoice])
  spr(RPS_SPRS[RPS.aiChoice],rx+2,ly+2,14,1,0,0,2,2)
  clip(rx,ly,HW,PHH); spr(SPR_FRAME,rx,ly,15,1,0,0,3,3); clip()
  local an=RPS_NAMES[RPS.aiChoice]
  print("CPU",rx+(HW-3*4)//2,ly+PHH+2,CD,true,1,true)
  print(an,rx+(HW-#an*4)//2,ly+PHH+9,CD,true,1,true)
 else
  dCardBack(rx,ly,HW,PHH)
  print("CPU",rx+(HW-3*4)//2,ly+PHH+2,CD,true,1,true)
  print("???",rx+(HW-3*4)//2,ly+PHH+9,5,true,1,true)
 end

 if RPS.phase=="result" then
  line(4,63,SW-5,63,5)
  local msg,col
  if RPS.winner==1 then msg="YOU WIN!"; col=CCR
  elseif RPS.winner==2 then msg="CPU WINS!"; col=CT
  else msg="TIE!"; col=9 end
  if (G.tick//15)%2==0 or RPS.winner==0 then
   print(msg,(SW-#msg*6)//2,68,col,true,1,false)
  end
  local sub
  if RPS.winner==1 then sub="YOU GO FIRST!"
  elseif RPS.winner==2 then sub="CPU GOES FIRST!"
  else sub="PICK AGAIN" end
  print(sub,(SW-#sub*4)//2,80,col,true,1,true)
  if RPS.winner==0 and (G.tick//20)%2==0 then
   print("A: TRY AGAIN",(SW-12*4)//2,91,CD,true,1,true)
  end
 end
end

-- ============================================================
-- ENTRY POINTS
-- ============================================================
function startGame()
 sync(3,1,false)
 newGame()
 dbLoad()
 local plrDeck=#DB.deck>0 and DB.deck or DECK1
 for i,id in ipairs(plrDeck) do G.deck[1][i]=id end
 for i,id in ipairs(DECK2) do G.deck[2][i]=id end
 shuffle(G.deck[1]); shuffle(G.deck[2])
 for _=1,4 do drawCard(1,true); drawCard(2,true) end
 startRPS()
 SCENE="rps"
end

function BOOT()
 G={tick=0}
 SCENE="title"
 TITLE_SEL=1
end

function TIC()
 G.tick=G.tick+1
 if SCENE=="title" then
  handleTitleInput()
  drawTitle()
  return
 end
 if SCENE=="menu" then
  handleMenuInput()
  drawMenu()
  return
 end
 if SCENE=="deckbuild" then
  handleDeckBuildInput()
  drawDeckBuild()
  return
 end
 if SCENE=="rps" then
  tickRPS()
  handleRPSInput()
  drawRPS()
  return
 end
 if SCENE=="trans" then
  TRANS.t=TRANS.t+1
  tickAnims()
  tickDispLp()
  -- Draw full game board
  cls(CB)
  rect(FA_X,0,FA_W,SH,CMAT)
  for y=0,SH-1,4 do for x=FA_X,SW-1,4 do pix(x,y,CB) end end
  rectb(FA_X,0,FA_W,SH,9)
  drawOppSide()
  line(COL[0],DIV_Y,COL[4]+ZW_SPEC-1,DIV_Y,CD)
  drawPlrSide()
  drawPanel()
  -- Phase 1 (t=1..40): panel slides in from left, field hidden
  -- Phase 2 (t=41..70): panel fixed, field wipes in from left
  local T1,T2=40,30
  if TRANS.t<=T1 then
   local revealW=(PANEL_W*TRANS.t)//T1
   rect(revealW,0,PANEL_W-revealW+1,SH,0)
   rect(FA_X,0,FA_W,SH,0)
  else
   local frev=(FA_W*(TRANS.t-T1))//T2
   if frev<FA_W then
    rect(FA_X+frev,0,FA_W-frev,SH,0)
   else
    SCENE="game"
   end
  end
  return
 end
 handleInput()
 if SCENE~="game" then return end
 autoPhase()
 aiTick()
 tickAnims()
 tickDispLp()
 cls(CB)
 rect(FA_X,0,FA_W,SH,CMAT)
 -- Playmat dither: sparse darker dots for subtle texture
 for y=0,SH-1,4 do
  for x=FA_X,SW-1,4 do
   pix(x,y,CB)
  end
 end
 -- Ornamental field border (gold)
 rectb(FA_X,0,FA_W,SH,9)
 drawOppSide()
 line(COL[0],DIV_Y,COL[4]+ZW_SPEC-1,DIV_Y,CD)
 drawPlrSide()
 drawCursor()
 drawAnims()
 drawPanel()
 if G.mode=="gy_view" and G.gyView then drawGYView() end
 if G.mode=="sel_deck" and G.deckSel then drawDeckSelect() end
 if G.infoCard then drawDBInfo(G.infoCard) end
 if G.winner then drawGameOver() end
end

-- <TILES>
-- 002:000000000000000f0000000f0000000f0000000f0000000f0000000f0000000f
-- 003:0000000000000000700000007000000070000000700000007000000070000000
-- 004:000000000000000000000000000000000000000000000000000000000000000f
-- 005:000000000000000000000000000070000007000000770000f770000077000000
-- 006:000aaaaa00aaaaaa0aaaa0000aaa0000aaa00000aaa00000aaa00000a0a00000
-- 007:aaaaaaa000000aaa0000000a0000000a0000000a0000000a0000000a0000000a
-- 008:00044444004000000440000044000000400000004000c000400cc000400c0000
-- 009:400000004444400000004400000004400000004000c0004400cc0004000c0004
-- 010:eaaaaaaaafffffffaff77fffaff777ffafff777faffff777afffff77afffff7f
-- 011:aaaaaaaefffffffafff77ffaff777ffaf777fffa777ffffaf7fffffa77fffffa
-- 012:eaaaaaaaafffffffafffffffa2222222a7288888a7728808a7772880af777288
-- 013:aaaaaaaefffffffafffffffa2ffffffa82fffffa882ffffa8882fffa08882ffa
-- 014:eaaaaaaaafffffffafffffffaf000fffa07770ff07777700a0007777afff0f7f
-- 015:aaaaaaaefffffffafffffffafff000faff07770a007777707777000af770fffa
-- 018:0000000f0000000f0000000f0000008800000008000000080000000000000000
-- 019:7000000070000000700000008800000080000000800000000000000000000000
-- 020:000000f700000f770008f7700000870000080800008000000000000000000000
-- 021:7000000000000000000000000000000000000000000000000000000000000000
-- 022:a0a00000a0a00000aaa000000aaa000000aa00000000aaa00000aaaa000000aa
-- 023:0000000a000000aa000000aa00000aaa0000aa0a00aaa00aaaa000a0aaaaaaa0
-- 024:400cc00040000000440000000440000000440000000444000000044400000000
-- 025:000c000400cc004400c000400cc0004000000040000004404404440004440000
-- 026:affff777afff777fa87777ffaf877fffa8887fff888f8fff88ffffffeaaaaaaa
-- 027:777ffffaf777fffaff77778afff778fafff7888afff8f888ffffff88aaaaaaae
-- 028:aff77728afff7772affff777afffff77affffff7afffffffafffffffeaaaaaaa
-- 029:888882fa2222222a7777777a7777777a7777777afffffffafffffffaaaaaaaae
-- 030:a000777707777700a07770ffaf000fffafffffffafffffffafffffffeaaaaaaa
-- 031:7777000a00777770ff07770afff000fafffffffafffffffafffffffaaaaaaaae
-- 032:f222222228888888288888882888888828888888288888882888888828888888
-- 033:2222222288888888888888888888888888888888888888888008888800008888
-- 034:222fffff8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff
-- 035:f88888888fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff
-- 036:88888888ffffffffffffffffffffffffffffffffffffffffffffffffffffffff
-- 037:888ffffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8ffff
-- 038:0000000000000000000008800088899808998998089989980899899808998998
-- 039:0000000000000000880880009989980099899800998998009989980088888800
-- 040:0000000000000888008889980099899808998998089989980899899808998999
-- 041:8800000099888000998998009989980099899800998998009989980099999800
-- 042:0000008900000089000000090000000800888998089989980899899808998998
-- 043:9000899898008990990089909908998099099900998998009989980099899800
-- 048:2888888828888880288888802888888028888880288888882888888828888888
-- 049:0000888800000888000008880000088800000888000088880000888880088888
-- 050:8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff
-- 051:8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff
-- 052:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
-- 053:fff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8ffff
-- 054:0899899808889888089999990899999908999999008999990089999900089999
-- 055:9999998099999980888899809999998099999800999998009999800099980000
-- 056:0899899808999998089999980899999908999999089999990089999900899999
-- 057:8888880099999980999999808888998099999980999998009999980099998000
-- 058:0899899808998998089998880899999908999999089999990089999900899999
-- 059:8888880099999980999999808888998099999980999998009999980099998000
-- 064:2888888828888888288888882888888828888888f2222222ffffffffffffffff
-- 065:888888888888888888888888888888888888888822222222ffffffffffffffff
-- 066:8882ffff8882ffff8882ffff8882ffff8882ffff222fffffffffffffffffffff
-- 067:8fffffff8fffffff8fffffff8fffffff8ffffffff8888888ffffffffffffffff
-- 068:ffffffffffffffffffffffffffffffffffffffff88888888ffffffffffffffff
-- 069:fff8fffffff8fffffff8fffffff8fffffff8ffff888fffffffffffffffffffff
-- 080:00dddd000de666d0defff66dddfe6f6dddfdefedddfffedd0dddddd000dddd00
-- 081:00333300033bb33033bffb333bbf33333bbff3333b3f3333033ff33000333300
-- 082:0011110001122110112ff211122f1111122ff111121f1111011f111000111100
-- 083:0022220002a99a20299f99a2299f99a2229f99a2222f2922022ff22000222200
-- 084:00555500054ccc505f4ccfc55f5fcfc55f5f4f4555f5f4550555555000555500
-- 085:0033330003bccc303fbccfc33f3fcfc33f3fbfb333f3fb330333333000333300
-- 086:0055550005544550555fff4555f54445544ff44555544f4505fff45000555500
-- 087:00dddd000d6666d0d66fffddd666f6edd666fdddd666fddd0ddefdd000dddd00
-- 088:00ffff000f0000f0f0f00f0ff0ff0f0ff0f0ff0ff0f00f0f0f0000f000ffff00
-- 089:00ffff000f0000f0f070070ff70f707ff70f707ff070070f0f0000f000ffff00
-- 090:00ffff000f0000f0f00f070ff0f7070fff777f0ff077000f0f0700f000ffff00
-- 091:00ffff000f07f0f0f007f00ffffffffff777f77ff007f00f0f07f0f000ffff00
-- 092:00ffff000f0700f0f007000ff00f777ff777f00ff000700f0f0070f000ffff00
-- 093:00ffff000f07f0f0f07f000ff007f00ff0007f0ff007f00f0f7f00f000ffff00
-- 094:00ffff000f0f00f0f07ff00ff077ff0ff007700ff07ff70f0f0770f000ffff00
-- 096:011100001a1a100011a110001a1a100001110000000000000000000000000000
-- 134:0000000000000000000000000000000800000880000808080009880800088880
-- 135:000000000000800108888888888880100088880080000100008100001000009a
-- 136:10000000000000000108888008888888001088800000800800018100aa200000
-- 137:0000000000000000000000008800000008080000880800008088000000898000
-- 149:0000000000000000000000000000000000000000000000000000000000000008
-- 150:0088888808988800088808109888809f0888870a0888920b8888899077882999
-- 151:080009280100098000000120f9ffff9f22aaaaa8aaa2a2a20aa292090a29880a
-- 152:82a0000100a0001002200000f999ff9f89aaaaa28a2aa2a2201a82aa800882a0
-- 153:888888000008888001100888f90788872f088890a09998880998888899998887
-- 154:0000000000000000000000000000000000000000000000008000000080000000
-- 162:0000000000000000000000000000005500000000000000000000000000000000
-- 163:000000000000000000000000000000005000000005005222055005990055005f
-- 164:00000000000000000000000000000000000000002222225099999a00ffffff25
-- 165:000000080000000800000588000054444004000000000522045002a9055052ff
-- 166:88999999888829998888299944444444000000002222222099999950ffff9500
-- 167:f0aa08a09f0aa2889f02228a4440222200000202005550800599902259ffff01
-- 168:89a02aa0802229098882a8098a880044280000000880555522099999207fffff
-- 169:9999998899997888999928884444444500000005555005009940050095005052
-- 170:8800000080000000000000005000000000000000522222222fffffffffffffff
-- 171:0000000000000050000004000000000500000052222222aff99f9ffffffffff9
-- 172:455555550000000000000000522250059f000040f20005009500050150054089
-- 173:5550000050000000500000000000000000000000000000000000000000000000
-- 178:000000000000000000000000000000ff00000fff0000ffff009ffcf509fffcf5
-- 179:0005000500004005957005000c7000504f0f0055c0700005cf000000f700fccf
-- 180:9fffff998ffffffa52ffffff059fffff0089ffff5052ffff50002fff040059ff
-- 181:000029ff5005afff2002ffff2582ffff9889fffff22ffff2ffffff25fffff850
-- 182:fff25004fff50059ff50059f950004ff800004ff500004ff005004ff040004ff
-- 183:9ffffff7fffffffffffff455ffff5000fff40055fff40000fff40000fff40000
-- 184:0ffffff9cffffff55555555000000000555555000000000055555544ffffffff
-- 185:500005af005002ff000059ff500059ff550059ff000059ff445059ffff5059ff
-- 186:fffffffffffffffffff45555ff450000ff450550ff450004ff450004ff450004
-- 187:fffffff2fffffff254fffff2054fffff004fffff054fffff054fffff054fffff
-- 188:50550881504002015000d0019000700190001008700510009000005d90000055
-- 189:00000000000000d200000d5a00d005e90dd598d0055502dd255dd89118dedd80
-- 190:9990000080800000010000000000000020000000000000000000000000000000
-- 193:00000000000000090000000f0000009f000000ff000009f0000009fc0000095f
-- 194:0fffcc70ffccc47fff00c0f7fcc0f0f4f00f5fff7ff72974c8709800ff020077
-- 195:f890c77c0070ffff00fc000f7ff07755740777774500207c5ff5020770002205
-- 196:705002ffc05505f2fc0505f2ff0505f95f0505f2750505f2550505f2750505f2
-- 197:fffff000222220042222200599222005aa222005222220052222200422222004
-- 198:550004ff00000444000004440000044400000444000005f50005005f00055005
-- 199:fff4000044f4000044f40000ffff50004445f50044445ffff4444444f5444444
-- 200:fffffffff44444445555f4440005fcff0005f444fffff4444444444444444444
-- 201:ff5059ff4f505f224f505f22cf505f994f505fa24f505922cc000599f5000059
-- 202:ff4500042245000422450004224500042245004422ff50002222f55522222ff5
-- 203:054fffff0542222f0542222f0549922f054a222f0542222f0042222f5542222f
-- 204:70000dd5700005559000555d9000555d9000528d700010827005122070000220
-- 205:088ddd50d0a00000ddd00000dddd5500eddd5500dddd55002885080009922800
-- 209:000009f000000000000000000000000000000000000000000000000000000000
-- 210:f0009f7700f10750008807000002f00000ff7000000000000000000000000000
-- 211:09998207988990579878905790020f7020027f040002c0500082000000004505
-- 212:704505f27500022205000f2240082222005922f9002f998502f9250022250000
-- 213:2222200422222005222f2004ff85000455000055000005500004500005500000
-- 214:0000550000000050000000500000000000000009002222820002228200022209
-- 215:5fffffff00000000000000002f999f80229992922a08222929008229229992a8
-- 216:ffffffff0000000000000000002999990922aaa2022a0082022a0002022a0202
-- 217:5005500500500500005005000000005598000000290222002902120029021000
-- 218:9f222222002f22220050ff220000552f55000000055500000000500000000055
-- 219:ff92222f2222222f2222222f2222222f29f222f20579729700552f2f0000052f
-- 220:70000227700512877000828770005280005005898054050820055555f2005005
-- 221:50002000fff00000ff780d70f08800dd008d905528888708d8810022ddd00000
-- 222:0000000000000000000000005800000009100000280000000000000000000000
-- 226:0000000000000000000000000000000000000000000000050000005000000055
-- 227:0005000200050028055002005000000550000045000555000550000050000ccc
-- 228:200000550000055000555000550000005000000000000000000000000c0cc000
-- 229:000000000000000000000000000000000000000000000000000000000ccc0ccc
-- 230:000022090000228200022282000222820002220900222200000000000000f0f0
-- 231:22aaa2982a80222a2a00022a22aaa22a222222208aaaaa0000000000f00f000f
-- 232:022a0202022a0202022a00020222aaa209222222008aaaaa00000000ff0ff000
-- 233:29029000290290002a0210002a0110009001220000222200000000000ff00f00
-- 234:00000000000000000000000000000000000000000000000000000000f000fff0
-- 235:550000050555000000005500000000050000000000000000000000000f00f00f
-- 236:827005550520005000020005500000005500000000555000000000550fff0005
-- 237:d8800000d8000000000000000000000040000000000000000550000055500000
-- 243:000000c0000000c0000000c0000000c000000000000000000000000000000000
-- 244:000c00000c0c00000c0c00cc0c0cc00000000000000000000000000000000000
-- 245:0c0c0c0c0ccc0c0c0c0c0c0c0ccc0ccc00000000000000000000000000000000
-- 246:0000f0f000000f0000000f0000000f0000000000000000000000000000000000
-- 247:f00f000ff00f070ff00f000f0ff0000f00000000000000000000000000000000
-- 248:00000000000ff0700f0ff000ff0ff00000000000000000000000000000000000
-- 249:f00f0f00f00f0ffff00f0f000ff00f0000000000000000000000000000000000
-- 250:f000f000f000f000f000f0f0f000fff000000000000000000000000000000000
-- 251:fff0f00ff0f0fffffff0f00ff0f0f00f00000000000000000000000000000000
-- 252:0f0500000fff50000f0050000fff000000000000000000000000000000000000
-- </TILES>

-- <TILES1>
-- 000:0f7770000f7770900ff770090ff7775000f7770500ff7755000f7755000f7799
-- 001:0000000055090000999000000550050055055550555900505550000059955000
-- 002:000000000000000f0000000f0000000f0000000f0000000f0000000f0000000f
-- 003:0000000000000000700000007000000070000000700000007000000070000000
-- 004:000000000000000000000000000000000000000000000000000000000000000f
-- 005:000000000000000000000000000070000007000000770000f770000077000000
-- 006:000aaaaa00aaaaaa0aaaa0000aaa0000aaa00000aaa00000aaa00000a0a00000
-- 007:aaaaaaa000000aaa0000000a0000000a0000000a0000000a0000000a0000000a
-- 008:00044444004000000440000044000000400000004000c000400cc000400c0000
-- 009:400000004444400000004400000004400000004000c0004400cc0004000c0004
-- 010:fffffffffffffffffff77ffffff777ffffff777ffffff777ffffff77ffffff7f
-- 011:fffffffffffffffffff77fffff777ffff777ffff777ffffff7ffffff77ffffff
-- 012:fffffffffffffffffffffffff2222222f7288888f7728808f7772880ff777288
-- 013:ffffffffffffffffffffffff2fffffff82ffffff882fffff8882ffff08882fff
-- 014:fffff0ffffff070ffff0770ffff0770ffff07770ffff0777fffff077fffff07f
-- 015:f0ffffff070fffff0770ffff0770ffff7770ffff770fffff70ffffff70ffffff
-- 016:0000f79900000f9900000995000f795900078555ff3305553ff0555533355555
-- 017:59555050505555005555300009553700559555005555555395555555f0555555
-- 018:0000000f0000000f0000000f0000008800000008000000080000000000000000
-- 019:7000000070000000700000008800000080000000800000000000000000000000
-- 020:000000f700000f770008f7700000870000080800008000000000000000000000
-- 021:7000000000000000000000000000000000000000000000000000000000000000
-- 022:a0a00000a0a00000aaa000000aaa000000aa00000000aaa00000aaaa000000aa
-- 023:0000000a000000aa000000aa00000aaa0000aa0a00aaa00aaaa000a0aaaaaaa0
-- 024:400cc00040000000440000000440000000440000000444000000044400000000
-- 025:000c000400cc004400c000400cc0004000000040000004404404440004440000
-- 026:fffff777ffff777ff87777ffff877ffff8887fff888f8fff88ffffffffffffff
-- 027:777ffffff777ffffff77778ffff778fffff7888ffff8f888ffffff88ffffffff
-- 028:fff77728ffff7772fffff777ffffff77fffffff7ffffffffffffffffffffffff
-- 029:888882ff2222222f7777777f7777777f7777777fffffffffffffffffffffffff
-- 030:fffff07ffffff077ffff077ffff07770fff0770ffff0770fffff070ffffff0ff
-- 031:70ffffff70ffffff770fffff7770ffff0770ffff0770ffff070ffffff0ffffff
-- 032:f222222228888888288888882888888828888888288888882888888828888888
-- 033:2222222288888888888888888888888888888888888888888008888800008888
-- 034:222fffff8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff
-- 035:f88888888fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff
-- 036:88888888ffffffffffffffffffffffffffffffffffffffffffffffffffffffff
-- 037:888ffffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8ffff
-- 038:0000000000000000000008800088899808998998089989980899899808998998
-- 039:0000000000000000880880009989980099899800998998009989980088888800
-- 040:0000000000000888008889980099899808998998089989980899899808998999
-- 041:8800000099888000998998009989980099899800998998009989980099999800
-- 042:0000008900000089000000090000000800888998089989980899899808998998
-- 043:9000899898008990990089909908998099099900998998009989980099899800
-- 048:2888888828888880288888802888888028888880288888882888888828888888
-- 049:0000888800000888000008880000088800000888000088880000888880088888
-- 050:8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff8882ffff
-- 051:8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff
-- 052:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
-- 053:fff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8fffffff8ffff
-- 054:0899899808889888089999990899999908999999008999990089999900089999
-- 055:9999998099999980888899809999998099999800999998009999800099980000
-- 056:0899899808999998089999980899999908999999089999990089999900899999
-- 057:8888880099999980999999808888998099999980999998009999980099998000
-- 058:0899899808998998089998880899999908999999089999990089999900899999
-- 059:8888880099999980999999808888998099999980999998009999980099998000
-- 064:2888888828888888288888882888888828888888f2222222ffffffffffffffff
-- 065:888888888888888888888888888888888888888822222222ffffffffffffffff
-- 066:8882ffff8882ffff8882ffff8882ffff8882ffff222fffffffffffffffffffff
-- 067:8fffffff8fffffff8fffffff8fffffff8ffffffff8888888ffffffffffffffff
-- 068:ffffffffffffffffffffffffffffffffffffffff88888888ffffffffffffffff
-- 069:fff8fffffff8fffffff8fffffff8fffffff8ffff888fffffffffffffffffffff
-- 080:00dddd000de666d0defff66dddfe6f6dddfdefedddfffedd0dddddd000dddd00
-- 081:00333300033bb33033bffb333bbf33333bbff3333b3f3333033ff33000333300
-- 082:0011110001122110112ff211122f1111122ff111121f1111011f111000111100
-- 083:0022220002a99a20299f99a2299f99a2229f99a2222f2922022ff22000222200
-- 084:00555500054ccc505f4ccfc55f5fcfc55f5f4f4555f5f4550555555000555500
-- 085:0033330003bccc303fbccfc33f3fcfc33f3fbfb333f3fb330333333000333300
-- 086:0055550005544550555fff4555f54445544ff44555544f4505fff45000555500
-- 087:00dddd000d6666d0d66fffddd666f6edd666fdddd666fddd0ddefdd000dddd00
-- 088:00ffff000f0000f0f0f00f0ff0ff0f0ff0f0ff0ff0f00f0f0f0000f000ffff00
-- 089:00ffff000f0000f0f070070ff70f707ff70f707ff070070f0f0000f000ffff00
-- 090:00ffff000f0000f0f00f070ff0f7070fff777f0ff077000f0f0700f000ffff00
-- 091:00ffff000f07f0f0f007f00ffffffffff777f77ff007f00f0f07f0f000ffff00
-- 092:00ffff000f0700f0f007000ff00f777ff777f00ff000700f0f0070f000ffff00
-- 093:00ffff000f07f0f0f07f000ff007f00ff0007f0ff007f00f0f7f00f000ffff00
-- 094:00ffff000f0f00f0f07ff00ff077ff0ff007700ff07ff70f0f0770f000ffff00
-- 096:011100001a1a100011a110001a1a100001110000000000000000000000000000
-- 134:0000000000000000000000000000000800000880000808080009880800088880
-- 135:000000000000800108888888888880100088880080000100008100001000009a
-- 136:10000000000000000108888008888888001088800000800800018100aa200000
-- 137:0000000000000000000000008800000008080000880800008088000000898000
-- 149:0000000000000000000000000000000000000000000000000000000000000008
-- 150:0088888808988800088808109888809f0888870a0888920b8888899077882999
-- 151:080009280100098000000120f9ffff9f22aaaaa8aaa2a2a20aa292090a29880a
-- 152:82a0000100a0001002200000f999ff9f89aaaaa28a2aa2a2201a82aa800882a0
-- 153:888888000008888001100888f90788872f088890a09998880998888899998887
-- 154:0000000000000000000000000000000000000000000000008000000080000000
-- 162:0000000000000000000000000000005500000000000000000000000000000000
-- 163:000000000000000000000000000000005000000005005222055005990055005f
-- 164:00000000000000000000000000000000000000002222225099999a00ffffff25
-- 165:000000080000000800000588000054444004000000000522045002a9055052ff
-- 166:88999999888829998888299944444444000000002222222099999950ffff9500
-- 167:f0aa08a09f0aa2889f02228a4440222200000202005550800599902259ffff01
-- 168:89a02aa0802229098882a8098a880044280000000880555522099999207fffff
-- 169:9999998899997888999928884444444500000005555005009940050095005052
-- 170:8800000080000000000000005000000000000000522222222fffffffffffffff
-- 171:0000000000000050000004000000000500000052222222aff99f9ffffffffff9
-- 172:455555550000000000000000522250059f000040f20005009500050150054089
-- 173:5550000050000000500000000000000000000000000000000000000000000000
-- 178:000000000000000000000000000000ff00000fff0000ffff009ffcf509fffcf5
-- 179:0005000500004005957005000c7000504f0f0055c0700005cf000000f700fccf
-- 180:9fffff998ffffffa52ffffff059fffff0089ffff5052ffff50002fff040059ff
-- 181:000029ff5005afff2002ffff2582ffff9889fffff22ffff2ffffff25fffff850
-- 182:fff25004fff50059ff50059f950004ff800004ff500004ff005004ff040004ff
-- 183:9ffffff7fffffffffffff455ffff5000fff40055fff40000fff40000fff40000
-- 184:0ffffff9cffffff55555555000000000555555000000000055555544ffffffff
-- 185:500005af005002ff000059ff500059ff550059ff000059ff445059ffff5059ff
-- 186:fffffffffffffffffff45555ff450000ff450550ff450004ff450004ff450004
-- 187:fffffff2fffffff254fffff2054fffff004fffff054fffff054fffff054fffff
-- 188:50550881504002015000d0019000700190001008700510009000005d90000055
-- 189:00000000000000d200000d5a00d005e90dd598d0055502dd255dd89118dedd80
-- 190:9990000080800000010000000000000020000000000000000000000000000000
-- 193:00000000000000090000000f0000009f000000ff000009f0000009fc0000095f
-- 194:0fffcc70ffccc47fff00c0f7fcc0f0f4f00f5fff7ff72974c8709800ff020077
-- 195:f890c77c0070ffff00fc000f7ff07755740777774500207c5ff5020770002205
-- 196:705002ffc05505f2fc0505f2ff0505f95f0505f2750505f2550505f2750505f2
-- 197:fffff000222220042222200599222005aa222005222220052222200422222004
-- 198:550004ff00000444000004440000044400000444000005f50005005f00055005
-- 199:fff4000044f4000044f40000ffff50004445f50044445ffff4444444f5444444
-- 200:fffffffff44444445555f4440005fcff0005f444fffff4444444444444444444
-- 201:ff5059ff4f505f224f505f22cf505f994f505fa24f505922cc000599f5000059
-- 202:ff4500042245000422450004224500042245004422ff50002222f55522222ff5
-- 203:054fffff0542222f0542222f0549922f054a222f0542222f0042222f5542222f
-- 204:70000dd5700005559000555d9000555d9000528d700010827005122070000220
-- 205:088ddd50d0a00000ddd00000dddd5500eddd5500dddd55002885080009922800
-- 209:000009f000000000000000000000000000000000000000000000000000000000
-- 210:f0009f7700f10750008807000002f00000ff7000000000000000000000000000
-- 211:09998207988990579878905790020f7020027f040002c0500082000000004505
-- 212:704505f27500022205000f2240082222005922f9002f998502f9250022250000
-- 213:2222200422222005222f2004ff85000455000055000005500004500005500000
-- 214:0000550000000050000000500000000000000009002222820002228200022209
-- 215:5fffffff00000000000000002f999f80229992922a08222929008229229992a8
-- 216:ffffffff0000000000000000002999990922aaa2022a0082022a0002022a0202
-- 217:5005500500500500005005000000005598000000290222002902120029021000
-- 218:9f222222002f22220050ff220000552f55000000055500000000500000000055
-- 219:ff92222f2222222f2222222f2222222f29f222f20579729700552f2f0000052f
-- 220:70000227700512877000828770005280005005898054050820055555f2005005
-- 221:50002000fff00000ff780d70f08800dd008d905528888708d8810022ddd00000
-- 222:0000000000000000000000005800000009100000280000000000000000000000
-- 226:0000000000000000000000000000000000000000000000050000005000000055
-- 227:0005000200050028055002005000000550000045000555000550000050000ccc
-- 228:200000550000055000555000550000005000000000000000000000000c0cc000
-- 229:000000000000000000000000000000000000000000000000000000000ccc0ccc
-- 230:000022090000228200022282000222820002220900222200000000000000f0f0
-- 231:22aaa2982a80222a2a00022a22aaa22a222222208aaaaa0000000000f00f000f
-- 232:022a0202022a0202022a00020222aaa209222222008aaaaa00000000ff0ff000
-- 233:29029000290290002a0210002a0110009001220000222200000000000ff00f00
-- 234:00000000000000000000000000000000000000000000000000000000f000fff0
-- 235:550000050555000000005500000000050000000000000000000000000f00f00f
-- 236:827005550520005000020005500000005500000000555000000000550fff0005
-- 237:d8800000d8000000000000000000000040000000000000000550000055500000
-- 243:000000c0000000c0000000c0000000c000000000000000000000000000000000
-- 244:000c00000c0c00000c0c00cc0c0cc00000000000000000000000000000000000
-- 245:0c0c0c0c0ccc0c0c0c0c0c0c0ccc0ccc00000000000000000000000000000000
-- 246:0000f0f000000f0000000f0000000f0000000000000000000000000000000000
-- 247:f00f000ff00f070ff00f000f0ff0000f00000000000000000000000000000000
-- 248:00000000000ff0700f0ff000ff0ff00000000000000000000000000000000000
-- 249:f00f0f00f00f0ffff00f0f000ff00f0000000000000000000000000000000000
-- 250:f000f000f000f000f000f0f0f000fff000000000000000000000000000000000
-- 251:fff0f00ff0f0fffffff0f00ff0f0f00f00000000000000000000000000000000
-- 252:0f0500000fff50000f0050000fff000000000000000000000000000000000000
-- </TILES1>

-- <SPRITES>
-- 000:4444444444444444444444444444444444444444444444444444444444444444
-- 001:4444444444444444444444444444444444444444444444414444411144444111
-- 002:4444444444444444444444444444444444444444114444441114444411144444
-- 003:4444444444444444444444444444444444444444444444444441114444411144
-- 004:4444444444444444444444444444444444444444444444444444444444444444
-- 005:4444444444444444444444444444444444444444444444444444444444444444
-- 006:4444444444444444444444444444444444444444444444444444444444444444
-- 007:4444444444444444444444444444444444444444444444444444444444444444
-- 008:4444444444444444444444444444444444444444444444444441114444411184
-- 009:4444444444444444444444444444444444444444444444444444444444444444
-- 010:4444444444444444444444444444444444444444444444444444444444444444
-- 011:4444444444444444444444444444444444444444444444444444444444444444
-- 012:4444444444444444444444444444444444444444444444444444444444444444
-- 013:4444444444444444444444444444444444444444444444444444444444444444
-- 014:4444444444444444444444444444444444444444444444444444444444444444
-- 015:4444444444444444444444444444444444444444444444444444444444444444
-- 016:4444444444444444411114441111144411188444111444111884441184444411
-- 017:4444411144444111444441114444411141111118111111111111111111111111
-- 018:1114444411144444184444411844444144444411111144411111448111111111
-- 019:4411114441111111111111111111111111111111111111111111111111111111
-- 020:4444444444444444111111141111111411111114111118441111188411111111
-- 021:4444444444444441444444414444444144444444444444444444444444444441
-- 022:4444111111111111111111111111111141111111444444114444441111111111
-- 023:1444444411111111111111111111111111111111111144441111488411111114
-- 024:4441111414411114144111141441111444411114444411118884111111141111
-- 025:4444444444444111444111114441111144411111844441188444418884444444
-- 026:444444441444444414444444144444441444444444444444844444441aaa1444
-- 027:4444444444444441444444114444441144444411444444114444447144444441
-- 028:4444444411111111111111111111111111111111111111111111111161111111
-- 029:4444444411111111111111111111111111111111111111111111111111111111
-- 030:4444444411111111111111111111111111111111111111111111111111118888
-- 031:4444444411144444111144441111844411118444111184441118844488844444
-- 032:4444411144444111444444114111144411111444111884441184444411444444
-- 033:11110000111100001111000a4481000044811880448111104481111141111114
-- 034:000000000000000077777700aa777770aaa77770000aff701100aaf01100aaf7
-- 035:1111000011110000110000771100000011111000011110000111000070000000
-- 036:0000000100000001777700017000000170001111000011140111444401111111
-- 037:444444114444441144444411444444414444444144444441444444411114441a
-- 038:11111aaa11111aaa111aa00011aa007711a007771a077700aa077000a0077000
-- 039:a1111111a11111110aa1110afff010a0777f0aa0077f0aa0000f000a00000000
-- 040:11111111111111110001111177701111fff78811fff700110000001100001111
-- 041:11aaaaaa11aaaaaa1a0000001a00007711a000f711a000ff11a000ff11a000ff
-- 042:a0001111a00011110000000077777770777777770000000f0000000f0011000f
-- 043:11111100111111000000aa000aaa7700aaa8ff00a77fff000aaaff00000aff00
-- 044:811aa000811aa000811aa00081111a0081111a0081111a00811111aa811111aa
-- 045:000000000000000077777000ff77700077777000007770000077700100ff0001
-- 046:0111444408114444011444441114444418844444184444441111111111111111
-- 047:4444444444444444444444444444444444444444444444441114444411144444
-- 048:8844444444444444441114444411144411111411111111111184411188444111
-- 049:4111118411118444111184411111844111184441184441111444111184441111
-- 050:1100aaf7111000af1111000a1111880a11111100111411001114110011141100
-- 051:70000000f7000000ff700000af770a770af70a770af700aa0af700aa0af700aa
-- 052:01111111111111110000000070000ff770000ff770000ff770000ff770000ff7
-- 053:1111441a1111111a000000a0000000a0000000a0000777a0000000a0000000a0
-- 054:a0077000a00f7000000f7011000f7011000f7011000f7000000f7700000ff700
-- 055:00000000111000011000000080077000007f70000777f0000000f0000000f000
-- 056:00001111000111110000000077700000a7f00077a7f00077a7f00000a7f00000
-- 057:11a000ff11a000ff00a000ff00a000ff77a000ff77a000ff00a000ff00a000ff
-- 058:0011000f0011000f0011000f0011000f0011000f0011000f0011000f0011000f
-- 059:000aff00000aff00000aff00110aff00110aff00000a777f000a7777000a777a
-- 060:811111aa8111111a0000001a0080001a00700011fff00011a7f00011aaf00011
-- 061:00ff000100ff000100ff0001a0ff0881a0ff0111a0ff0111a0770111a0770111
-- 062:1111111111111111111111111111111111111111888888884444444444444444
-- 063:1114444411144444114444441144444488444444444444444444444444444444
-- 064:4444488844414444444144444411184444111844481118441111111811111111
-- 065:4444111144411111441111114411111144111114411111148111111111111111
-- 066:184411004444110044441100444411004441110044411100111100001110000a
-- 067:0af700aa0af700aa0af700aa0af700aa0af700000af700000af70000af000000
-- 068:70000ff7f0000ff7f0000ff7f7770ff7af770ff7aff70ff70000000f00000000
-- 069:000000a00811111a0811111a0000001100001111000011117700184100001844
-- 070:000fff0080000f77a0000f771a0000ff1a0000001a00000011aa0000441aa000
-- 071:0000f0000007f0000007f0007007f0007000f0007000f0000000700000000000
-- 072:a7f00000a7701111a7701111a7701111a7701111a7701111a770111100001111
-- 073:00a000ff11a0007711a0007711a00000111aa000181aa00084111a00848111a8
-- 074:0011000f00000000000000007000000007770000077700000000000000000aa0
-- 075:000a77a0000a7700000a7700000a7700000a7700000a7700000a770000000000
-- 076:8af000008af000778af000778af000008af770a88af770a8000000aa000000aa
-- 077:a07701110a8011110a701111a00001110fff00010fff00010000000000000001
-- 078:4444444444444444444444444444444418444444184444441111444411111111
-- 079:4444444444444444444444444444444444444444444444444444444411444444
-- 080:1111111111111111111111111111111181188888488444444444444444444444
-- 081:1111111111111111111111111111111188888888444444444444444444444444
-- 082:8880000f00000000111111111111111111111111888811114444811144444481
-- 083:f000000000000000111111111111111111111111111111111111111111111111
-- 084:0000000000000000111100001111111111111111111111111111111111111111
-- 085:0001884400014444081844411114441111144411111144111118441111144411
-- 086:44881a0044481a00111111001111118a111111aa111118881888844484444444
-- 087:0a1800000aa10000a11111111111111111111118888888844444444444444444
-- 088:0000111800001844111118441111184488118444448844444444444444444444
-- 089:4481111144811111444811114448111144481111444811114444481144444811
-- 090:a000a8a0a000a0001aaa11111111111111111111111111111111111111111111
-- 091:0000000000000000111111111111111111111111111111111111111181111118
-- 092:0000001100000011110001111111111111111111111888881184444444444444
-- 093:a0000811a00001111a8011111111111111111111888888884444444444444444
-- 094:1111111111111111111111111111111111111111111111118888881144444411
-- 095:1111114411111114111111141111111111111111111111111111111111111111
-- 096:4444444444444444444444444444444444444444444444444444444444444444
-- 097:4444444444444444444444444444444444444444444444444444444444444444
-- 098:4444444844444444444444444444444444444444444444444444444444444444
-- 099:8111111141111111448811114448111144448888444444444444444444444444
-- 100:1111111111111111111111111111118888888444444444444444444444444444
-- 101:1184448888444444444444444444444444444444444444444444444444444444
-- 102:8444444444444444444444444444444444444444444444444444444444444444
-- 103:4444444444444444444444444444444444444444444444444444444444444444
-- 104:4444444444444444444444444444444444444444444444444444444444444444
-- 105:4444481144444811444444114444448144444444444444444444444444444444
-- 106:1111111811111184111184441111844488884444444444444444444444444444
-- 107:4881118444488844444444444444444444444444444444444444444444444444
-- 108:4444444444444444444444444444444444444444444444444444444444444444
-- 109:4444444444444444444444444444444444444444444444444444444444444444
-- 110:4444448844444444444444444444444444444444444444444444444444444444
-- 111:8111111148881184444488444444444444444444444444444444444444444444
-- 112:4444444444444444000000000000000000000000000000000000000000000000
-- 113:4444444444444444000000000000000000000000000000000000000000000000
-- 114:4444444444444444000000000000000000000000000000000000000000000000
-- 115:4444444444444444000000000000000000000000000000000000000000000000
-- 116:4444444444444444000000000000000000000000000000000000000000000000
-- 117:4444444444444444000000000000000000000000000000000000000000000000
-- 118:4444444444444444000000000000000000000000000000000000000000000000
-- 119:4444444444444444000000000000000000000000000000000000000000000000
-- 120:4444444444444444000000000000000000000000000000000000000000000000
-- 121:4444444444444444000000000000000000000000000000000000000000000000
-- 122:4444444444444444000000000000000000000000000000000000000000000000
-- 123:4444444444444444000000000000000000000000000000000000000000000000
-- 124:4444444444444444000000000000000000000000000000000000000000000000
-- 125:4444444444444444000000000000000000000000000000000000000000000000
-- 126:4444444444444444000000000000000000000000000000000000000000000000
-- 127:4444444444444444000000000000000000000000000000000000000000000000
-- 234:0000000800000080000000880000088900008998000890890008908900890890
-- 235:8000000008000000880000009880000089980000980980009809800009809800
-- 236:0000000000000000000000000000000000000008000008890000899900089999
-- 237:0000000000000000000000000000000080000000988000009998000099998000
-- 238:0000000000000000000000000000008800000899088888988a89999908999988
-- 239:00000000000000000000000080000000980000009888880099998a8089999800
-- 250:0089899a00088888000890000080899000900889009009080090090000000900
-- 251:a998980088888000000980000998080098800900809009000090090000900000
-- 252:00089988008998aa008999a0000898aa00089988000089990000088900000008
-- 253:88998000aa8998000a999800aa89800088998000999800009880000080000000
-- 254:089988aa008999a0000898aa0008998800008999000008980000008a00000008
-- 255:a8899800a9998000a89800008998000099800000980000008000000000000000
-- </SPRITES>

-- <SPRITES1>
-- 000:ff7450544cc48808cc500888545888285588888250888888c08885d8c0888258
-- 001:08550544888805478888007528288844828888848888885585d8888782588800
-- 002:000007303030030030008000300080083000000033b330003333330033b00300
-- 003:0380000008000000803000000080000008008030000000300030000000300008
-- 004:5455585545555888558888825558882a55888882588822285333a2a833333128
-- 005:8555554588585554228855552a8833351283333388ba2a5a88a2a03588282855
-- 006:177111110770001718770077ff8f0887770777707708f77f7780077808870770
-- 007:01111111f0111701778077018f80780007f770777077807f8f7807ff87787fff
-- 008:3aa3088603ba3d66036d66883aab8850abb300443330ccc44054c4cc400c4c4c
-- 009:6dd04444ddd404440d4d045444dd044544440444445504444500444400000454
-- 010:22222222288020202bbb3b3000bb0bb0bbbb3b932bb333a02003a9bb202bb3bb
-- 011:70732222bbbb3322babb30b3bbbb3b03bbb3233b3330233bb333233bb3332b03
-- 012:5555555255555592555558995552218282881119522821818255228188282028
-- 013:2555555592155555828155552888855581112982118829821228255520218821
-- 014:44444407444440f744440777444077774407ff7744077fff40079f770707aa77
-- 015:f0444444ff0444447ff044447fff04447ffff044ffff90447fffa0049afff040
-- 016:70038888503b3888c49a9888450000885505000855053000505b30c045099cc5
-- 017:88883b008888bbb588889a95808008050080505400005544003845550cb9a555
-- 018:300003b00f30000078003800f7000008800303300000033b0000033b08000333
-- 019:0030000008033000003303008000008303330000b333000033300000b3300080
-- 020:a5a8a88853080f8f55888081555888f14555888854535588553333555a5a5a54
-- 021:088808558f8f088511808555f1f8885588885554885535455533335545a5a5a5
-- 022:00087777788787777788888877808808788780ff88777fff077777f0007ffff7
-- 023:7777877f7777777088887800807087880700708807f700877ff88707fff07007
-- 024:504cc433404733334073337740333333440333334440333f5444003845544400
-- 025:337770458f316200331f8f18318881853f118180f81f1f18ff83118038f08004
-- 026:202b33332022a93222220333220223332003000023b330222230222222222222
-- 027:03b320302bbb30992b33bb32bb20b332b030332220332222bb322292b22b2222
-- 028:81221002882820801222008822882080298122880888820f0081120f0001111f
-- 029:0021282f00120fff8087ffff00fff7ff0fff7ffffff7fff7ff7ffff8f7fff988
-- 030:07777f7707777f774007777703b77770bbb0000bbb3003333330400040444444
-- 031:a9f000007f033330703a7dd00bb3dd30bb33330b333000bb0004033344444404
-- 032:444440704055455544455555444055554444005544449955444999004499995f
-- 033:445045555005550455555500555557745505554405055044ffff54441ff10944
-- 034:555555555555f5725550f2225557ff27555778ef555722c7555522c8555522cc
-- 035:557555552f755555227f5555f2ff55557f7f55557c8755557c875555cc255555
-- 036:2228550822857708280f777f885055ff85ff08838ffff8d78fffff0d2ffffff7
-- 037:8f08828877052228ff7058887f5755887350ff88f877fff80ffffff8fff00ff8
-- 038:000006090000658800b8569700b55d5d03b059550b66d965bb5655d0bbb0d558
-- 039:53000000bbb30000b33bb30050bbbb0060003b300000bbb000000bb3997c4bbb
-- 040:550fffff550fffff5550f0005550fff055550000555500ff0555550005055500
-- 041:fff0fff00000ff05100ff05500fff05505f0055555505555f550055500000055
-- 042:00000d800000bb000000b300000ababb0b3bb3bb03333ba0003dba3b0003a33b
-- 043:08d0000000bb3000000bd000bbaba300bb3bbb330bab3d30b33a3d00b3ba0300
-- 044:11125ff011125f0211227fd91120d009150ddd0d50dddd09300ddd00090ddd09
-- 045:0ff5211120f521119df72211900d0211d0dddd5190dd0c2500ddd10390ddd133
-- 046:1119aa1119aa11111a1444449a1444dda11aaa44a11a47d41144d44a114d4a7a
-- 047:11a4471111444a91444441a1dd4de1a94d44711a44d4111a4a711111aaaa2111
-- 048:4999909599999595909990957977999597779775777707757779779577777077
-- 049:fff09094fff59099777099099779075709005070099759757707577577770770
-- 050:555522cc5555828c5555228c5558227c575228cc5f57ccc75f5ccc7c5ff7cc7c
-- 051:cc285555c8285555c8285555c8285555cc885f55cccc5775cccc5ff57cccfff5
-- 052:ffffffff000d07dd5f0d0fff0fff50f08ffd25808f0d02878ffd028d8ffdf8dd
-- 053:f77700f0ff7ffd78dd08fd88ddf800080ff007f870f870f20f0875f2ddd007f8
-- 054:bccccc0c3bb000550b3b005503bb005500bbb055003b656500006b50000000b0
-- 055:997cc3bb56555bb355650bb0d56d50305565500000b050505556000003005600
-- 056:050500007070000f777707777777777077777700777777007777777077777700
-- 057:000000050000f00000007f0f00000fff0070007f777700770777707777777007
-- 058:0003a30b0ab33b330bb03333033b3bb30003b3b000d333b000dddab300000000
-- 059:b0ba000033b33ba033be3bb333b333b003bb30000b3b3d000abaedd000000000
-- 060:30200dd0330930dd3309330d330900dd3330dddd3330ddd233000d0233333d32
-- 061:0dd00133dd033033d0330903dd009133dddd11332ddd013320d0013323d33133
-- 062:114daa991144a9ffa11aaaa9a11aaaa99a11aaa91a111a4419aae5441119a447
-- 063:aaaaa2219aaaaaaa9a4944a19a94dd419edd44414dde749e444d71e9454d711e
-- 064:0055411505545515555445515555555a55555551555555595555555955555b1b
-- 065:55000000555050555550555555555555155555559bbb55559b5455555555555d
-- 066:4f7744444f7774944ff774494ff7745044f7770d44ff7755444f7755444f7799
-- 067:4444444455494444999444445544454455455554555955545555554459955544
-- 080:5d5555b55d555559ddd5dd94dddddd11dddddd11dddd9911ddb99199ddb9bddd
-- 081:595bbbdd5995bbdd19599ddd9bbbdddddb999dddd999999d99dddddd9fdddddd
-- 082:4444f79944444f99444449954444795944448555444405554440555544455554
-- 083:5955555455555544555544440955444455955544555555549955555544455555
-- 192:000070050000500000500000000005000500000005000000000000055000005f
-- 193:0005550005057775000000500550000000000505000000057c505770fc700700
-- 194:5555522f555552af555552af2555552f555550af2555502f2255555f5055555f
-- 195:f2555055f2555255a5555255a5555255a555505522555525a255505522555255
-- 196:555555555555555555555555555554f0544444004444444244ccccc0ccccccc9
-- 197:f5555555855f5555225055442220844c2022ccc92280c9992029999008800000
-- 198:00000000000000005005055500000500000020888000202720022a2820009222
-- 199:0000000020000000552555552228555522088888028222002200822022000700
-- 200:5f5555555f55c55c5f55c55c55c55ccc55cc5ccc555ccccc555ccc9c9555f99c
-- 201:c55f555555f555555555f55555c5f55fcccc55c5ccc5c555ccccc555ccc555f5
-- 202:cccccc88cf99ccc0c9f9ccc8cfffccc8cccccc88cccccc808ccc80888080f800
-- 203:80000888800000888000008880000008800899808089999800889798009f9898
-- 204:ddee7dd7dee80000deee0ddddeeedeeedd50eeee8d00deee0050055d555555dd
-- 205:eeeeeeee07eeeeeeee777eeeeeddd7eded0dd7edeededd807eeedd007eee5555
-- 206:727a7f777727af777ff77777f77f77777777777787777fff40aa7994440a4008
-- 207:af7777727777f7777777777f777f7a7777f7a777f77777700a77772988822899
-- 208:05000cff55500577050000000500000050000050055500555005505507000550
-- 209:fc00055050005507005050000055000005505055550005055075505750000057
-- 210:5525552f0552552f522552fa55555af255525af25555aaf255552fff552aaffa
-- 211:5255525552502552555255255555555520552525222a2555aaf22255ffa25555
-- 212:cccc9999cc9999709c990000990000000000000000000000000002f00000ff00
-- 213:0220000002200000082000000880000000000000000000000000000000000000
-- 214:00092227002a02220000022a002082220000000820a8020800222020220222a2
-- 215:2022820022822280228282002282220222008202888800000000000200820020
-- 216:5995faac999aaffa5222999c2299292c29929925992259959722599555255995
-- 217:fccccc552cccf555ccc55555cc5cc55fcfc5555555cf55555555fccc55555555
-- 218:8088888000088980000099800000088000000090000000880000008800000088
-- 219:00f0998000099088000000880000088800008888000888880008888888888888
-- 220:5555d7775555deee05555dde00577057507ff07f507ff8ff507ff7fffeffffff
-- 221:eeee5555d5555555d5555555e7f755507ff75555dff7e7f5fff7fff7ffffffff
-- 222:54aa4495aa5444447775444477785454f7779959777f7995ff7f7777a77f7777
-- 223:499990884829997940490000843087774007777777777777777f7777f777277f
-- </SPRITES1>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000304000000000
-- </SFX>

-- <TRACKS>
-- 000:100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </TRACKS>

-- <PALETTE>
-- 000:0e0e0eaa0000ce5d143469100075d2182875e9258c7d7d7d653010ffc671ffee307dc22053e4f77114b2ee81eaeeeeee
-- </PALETTE>

-- <PALETTE1>
-- 000:0e0e0eaa0000ce5d143469100075d2182875e9258c7d7d7d653010ffc671ffee307dc22053e4f77114b2ee81eaeeeeee
-- </PALETTE1>

