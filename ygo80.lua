-- title:   YGO80
-- author:  draovar
-- desc:    Yu-gi-oh Speed duel for tic80
-- version: 0.1
-- script:  lua
--
-- ============================================================
-- TABLE OF CONTENTS
-- ============================================================
--  LAYOUT / COLORS              constants for screen + zone geometry
--  CARD DATABASE                CARDS list, DECK1, DECK2
--  HELPERS                      stat math, shuffle, hand layout
--  STATE                        G global; newGame()
--  CORE GAME                    drawing/anim primitives, LP, damage
--  MUTATIONS                    single-source helpers: send to GY / discard
--  CHAIN STACK                  openChain / pushChainLink / advanceChain
--  BEHAVIORS                    per-card hooks (ADD CARDS HERE)
--  BEHAVIOR DISPATCH            behaviorOf / applyResolve / fireMonHook
--  MENU / INPUT                 buildMenu, execAction, handleInput
--  AUTO PHASE / AI              AI main + battle logic
--  TITLE / DECK BUILDER         menus and persistence
--  RPS / BOOT / TIC             startup, RPS opener, frame entry
--
-- Adding a new card:
--  1) Append to CARDS (with `effect` string keying its behavior).
--  2) Add a BEHAVIORS[effect] entry with the hooks it needs.
--  3) Optional: add to a deck list (DECK1/DECK2) and a sprite.
-- No other file edits should be required for a typical new card.

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
CSP  = 11   -- spell card face                           (dark green)
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

PHASES={"DRAW","STBY","MAIN","BATTLE","END"}
PH_DRAW=1; PH_STBY=2; PH_MAIN=3; PH_BATTLE=4; PH_END=5

-- Gameplay constants
START_LP   = 4000
MAX_DECK   = 20    -- pmem holds 20 IDs (4 slots × 5 at 6 bits); see dbLoad/dbSave
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
 -- ============================================================
 -- MONSTERS
 -- ============================================================

 -- Level 1
 kuriboh={
  name="Kuriboh", cat="monster", type="fiend", attr="dark", effect="kuriboh", atk=300, def=200, lvl=1, spr=256, bg=14,
  desc="If your opponent's monster attacks: You can discard this card; you take no battle damage from that battle."
 },

 -- Level 2
 man_eater_bug={
  name="Man-Eater Bug", cat="monster", type="insect", attr="earth", effect="maneater", atk=450, def=600, lvl=2, spr=258, bg=14,
  desc="FLIP: Target 1 monster on the field; destroy that target."
 },
 a_cat_of_ill_omen={
  name="A Cat of Ill Omen", cat="monster", type="beast", attr="dark", effect="catillomen", atk=500, def=300, lvl=2, spr=356, bg=14,
  desc="FLIP: Search your deck for 1 Trap Card and place it on top of your deck. If 'Necrovalley' is on the field, add it to your hand instead."
 },

 -- Level 3
 sangan={
  name="Sangan", cat="monster", type="fiend", attr="dark", effect="sangan", atk=1000, def=600, lvl=3, spr=260, bg=14,
  desc="When destroyed, add a monster with 1500 or less ATK from your deck to your hand."
  },
 giant_soldier={
  name="Giant Soldier", cat="monster", type="rock", attr="earth", atk=1300, def=2000, lvl=3, spr=262, bg=14,
  desc="A towering stone giant with impenetrable armor and very high defense."
  },
 gravekeeper_curse={
  name="Gravekeeper's Curse", cat="monster", type="spellcaster", attr="dark", effect="gkcurse", atk=800, def=600, lvl=3, spr=354, bg=1,
  desc="Each time this card is Normal or Special Summoned, inflict 800 damage to your opponent."
  },

 -- Level 4
 seven_color_fish={
  name="7 Color Fish", cat="monster", type="fish", attr="water", atk=1800, def=800, lvl=4, spr=264, bg=9,
  desc="A vibrant and powerful fish that traverses all the world's oceans."
 },
 la_jinn={
  name="La Jinn", cat="monster", type="fiend", attr="dark", atk=1800, def=1000, lvl=4, spr=266, bg=14,
  desc="A mystical genie released from an ancient lamp. Commands fearsome power."
 },
 battle_ox={
  name="Battle Ox", cat="monster", type="beast-warrior", attr="earth", atk=1700, def=1000, lvl=4, spr=268, bg=14,
  desc="A savage warrior ox that charges through enemies with brutal force."
 },
 ufo_turtle={
  name="Ufo Turtle", cat="monster", type="machine", attr="fire", effect="ufoturtle", atk=1400, def=1200, lvl=4, spr=270, bg=14,
  desc="When destroyed in battle, special summons a FIRE monster from the deck."
 },
 aqua_madoor={
  name="Aqua Madoor", cat="monster", type="spellcaster", attr="water", atk=1200, def=2000, lvl=4, spr=288, bg=14,
  desc="A powerful water sorcerer who calls upon the deep sea for protection."
 },
 mystical_elf={
  name="Mystical Elf", cat="monster", type="spellcaster", attr="light", atk=800, def=2000, lvl=4, spr=290, bg=14,
  desc="A gentle elf shielded by a sacred barrier. Possesses extreme defense."
 },
 feral_imp={
  name="Feral Imp", cat="monster", type="fiend", attr="dark", atk=1300, def=1400, lvl=4, spr=298, bg=14,
  desc="A fiendish imp that lurks in the shadows, striking with vicious claws."
 },
 rogue_doll={
  name="Rogue Doll", cat="monster", type="spellcaster", attr="light", atk=1600, def=1000, lvl=4, spr=300, bg=14,
  desc="A possessed doll that moves on its own will, wielding powerful magic."
 },
 legion_fiend_jester={
  name="Legion the Fiend Jester", cat="monster", type="fiend", attr="dark", effect="legion", atk=1200, def=0, lvl=4, spr=320, bg=14,
  desc="Once per turn: Tribute Summon 1 Spellcaster in ATK pos, in addition to your Normal Summon. If sent from field to GY: add 1 Spellcaster Normal Monster from Deck or GY to hand."
 },
 the_stern_mystic={
  name="The Stern Mystic", cat="monster", type="spellcaster", attr="light", effect="sternmystic", atk=1500, def=1200, lvl=4, spr=324, bg=14,
  desc="FLIP: Both players reveal all face-down cards on the field. After this, return them to their original positions."
 },
 double_coston={
  name="Double Coston", cat="monster", type="zombie", attr="dark", effect="doublecoston", atk=1700, def=1650, lvl=4, spr=326, bg=3,
  desc="If used as a Tribute for the Tribute Summon of a DARK monster, this card is treated as 2 Tributes."
 },
 vorse_raider={
  name="Vorse Raider", cat="monster", type="beast-warrior", attr="dark", atk=1900, def=1200, lvl=4, spr=330, bg=14,
  desc="This wicked Beast-Warrior does every horrid thing imaginable, and loves it! His axe bears the marks of his countless victims."
 },
 gravekeeper_assailant={
  name="Gravekeeper's Assailant", cat="monster", type="spellcaster", attr="dark", effect="gkassailant", atk=1500, def=1500, lvl=4, spr=352, bg=14,
  desc="If 'Necrovalley' is on the field, when this card attacks: you can change the battle position of 1 monster your opponent controls."
 },
 gravekeeper_spy={
  name="Gravekeeper's Spy", cat="monster", type="spellcaster", attr="dark", effect="gkspy", atk=1200, def=2000, lvl=4, spr=334, bg=14,
  desc="FLIP: Special Summon 1 'Gravekeeper's' monster from your Deck."},

 -- Level 6
 summoned_skull={
  name="Summoned Skull", cat="monster", type="fiend", attr="dark", atk=2500, def=1200, lvl=6, spr=292, bg=14,
  desc="A powerful fiend that rules the darkness. One of the strongest monsters."
 },
 dark_magician_girl={
  name="Dark Magician Girl", cat="monster", type="spellcaster", attr="light", effect="dmgirl", atk=2000, def=1700, lvl=6, spr=302, bg=14,
  desc="Gains 300 ATK for each Dark Magician in either GY."
 },
  jinzo={
  name="Jinzo", cat="monster", type="machine", attr="dark", effect="jinzo", atk=2400, def=1500, lvl=6, spr=328, bg=15,
  desc="While this card is face-up on the field, Trap Cards cannot be activated."},
 gravekeeper_shaman={
  name="Gravekeeper's Shaman", cat="monster", type="spellcaster", attr="dark", effect="gkshaman", atk=1500, def=1500, lvl=6, spr=360, bg=14,
  desc="Gains 200 DEF for each GK in either GY. Negates GY monster effects (not GKs). While Necrovalley: opp can't activate Field Spells."
 },

 -- Level 7
 dark_magician={
  name="Dark Magician", cat="monster", type="spellcaster", attr="dark", atk=2500, def=2100, lvl=7, spr=294, bg=1,
  desc="The ultimate wizard in terms of both attack and defense. A legend."
 },
 red_eyes_b_dragon={
  name="Red Eyes B Dragon", cat="monster", type="dragon", attr="dark", atk=2400, def=2000, lvl=7, spr=296, bg=14,
  desc="A ferocious black dragon with a devastating black fire breath attack."
 },
 buster_blader={
  name="Buster Blader", cat="monster", type="warrior", attr="earth", effect="busterblader", atk=2600, def=2300, lvl=7, spr=322, bg=14,
  desc="Gains 500 ATK for each Dragon-type monster your opponent controls or has in their GY."},

  -- Level 10
 gravekeeper_oracle={
  name="Gravekeeper's Oracle", cat="monster", type="spellcaster", attr="dark", effect="gkoracle", atk=2000, def=1500, lvl=10, spr=358, bg=14,
  desc="Tribute 1 GK or 3 monsters to summon. On Tribute Summon: activate up to [GKs tributed] effects in sequence: +ATK by tributed levels x100; destroy opp set monsters; opp monsters -2000 ATK/DEF."
 },

 -- ============================================================
 -- SPELLS
 -- ============================================================

 -- Normal
 dark_hole={
  name="Dark Hole", cat="spell", subtype="normal", effect="darkhole", spr=448, bg=14,
  desc="Destroy all monsters on the field."
 },
 raigeki={
  name="Raigeki", cat="spell", subtype="normal", effect="raigeki", spr=450, bg=14,
  desc="Destroy all monsters your opponent controls."
 },
 fissure={
  name="Fissure", cat="spell", subtype="normal", effect="fissure", spr=452, bg=14,
  desc="Destroy your opponent's face-up monster with the lowest ATK."
 },
 ookazi={
  name="Ookazi", cat="spell", subtype="normal", effect="ookazi", spr=454, bg=14,
  desc="Inflict 800 points of damage to your opponent's Life Points."
 },
 thousand_knives={
  name="Thousand Knives", cat="spell", subtype="normal", effect="thousandknives", spr=484, bg=1,
  desc="If you control 'Dark Magician': Target 1 monster your opponent controls; destroy that target."
 },
 pot_of_greed={
  name="Pot of Greed", cat="spell", subtype="normal", effect="potofgreed", spr=488, bg=14,
  desc="Draw 2 cards."
 },
 monster_reborn={
  name="Monster Reborn", cat="spell", subtype="normal", effect="monsterreborn", spr=490, bg=14,
  desc="Target 1 monster in either GY; Special Summon it to your field in ATK position."
 },
 gravekeeper_stele={
  name="Gravekeeper's Stele", cat="spell", subtype="normal", effect="gkstele", spr=418, bg=14,
  desc="If you have at least 1 'Gravekeeper's' monster in your GY: Target 2 'Gravekeeper's' monsters in your GY; add them to your hand (1 at a time)."
 },

 -- Equip
 united_we_stand={
  name="United We Stand", cat="spell", subtype="equip", effect="unitedwestand", spr=462, bg=14,
  desc="The equipped monster gains 800 ATK/DEF for each face-up monster you control."},

 -- Quick-Play
 mystical_typhoon={
  name="Mystical Typhoon", cat="spell", subtype="quickplay", effect="mst", spr=480, bg=14,
  desc="Target 1 Spell/Trap on the field; destroy that target."},

 -- Continuous
 swords_of_revealing_light={
  name="Swords of Revealing Light", cat="spell", subtype="continuous", effect="swords", spr=486, bg=1,
  desc="Your opponent's monsters cannot declare an attack. Destroyed during your opponent's 3rd End Phase."},

 -- Field
 necrovalley={
  name="Necrovalley", cat="spell", subtype="field", effect="necrovalley", spr=416, bg=14,
  desc="All 'Gravekeeper's' monsters gain 500 ATK/DEF. Negate any card effect that moves a card from a Graveyard."},

 -- ============================================================
 -- TRAPS
 -- ============================================================

 -- Normal
 mirror_force={
  name="Mirror Force", cat="trap", subtype="normal", effect="mirrorforce", spr=456, bg=14,
  desc="When an opponent's monster declares an attack, destroy all their attack position monsters."
 },
 trap_hole={
  name="Trap Hole", cat="trap", subtype="normal", effect="traphole", spr=458, bg=14,
  desc="When your opponent summons a monster with 1000 or more ATK, destroy it."},

 -- Continuous
 call_of_the_haunted={
  name="Call of Haunted", cat="trap", subtype="continuous", effect="callhaunted", spr=460, bg=1,
  desc="Target 1 monster in your GY; Special Summon it in ATK Pos. When this card leaves the field, destroy that monster. When that monster is destroyed, destroy this card."},

 -- Counter
 magic_jammer={
  name="Magic Jammer", cat="trap", subtype="counter", effect="magicjammer", spr=482, bg=14,
  desc="When a Spell is activated: Discard 1 card; negate that activation, and destroy that card."},

}

-- Auto-generated from CARDS keys: monster < spell < trap, then by level, then by name.
CARD_ORDER={}
for k in pairs(CARDS) do CARD_ORDER[#CARD_ORDER+1]=k end
table.sort(CARD_ORDER,function(a,b)
 local ca,cb=CARDS[a],CARDS[b]
 if ca.cat~=cb.cat then return ca.cat<cb.cat end
 if (ca.lvl or 0)~=(cb.lvl or 0) then return (ca.lvl or 0)<(cb.lvl or 0) end
 return ca.name<cb.name
end)
CARD_NUM={}
for i,id in ipairs(CARD_ORDER) do CARD_NUM[id]=i end

-- ============================================================
-- DECKS
-- ============================================================

DECK1 = {
  -- Monsters
  "dark_magician", "dark_magician_girl", "summoned_skull", "feral_imp", "kuriboh", "sangan", "giant_soldier", "mystical_elf", "legion_fiend_jester", "rogue_doll", "double_coston", "man_eater_bug", "man_eater_bug",
  -- Spells
  "dark_hole", "ookazi", "ookazi", "fissure",
  -- Traps
  "mirror_force", "mirror_force", "trap_hole",
}

-- Opponents

DECK_YUGI = {
  -- Monsters
  "dark_magician_girl", "dark_magician", "summoned_skull", "feral_imp", "kuriboh", "sangan", "giant_soldier", "mystical_elf", "legion_fiend_jester", "rogue_doll", "double_coston", "man_eater_bug", "man_eater_bug",
  -- Spells
  "dark_hole", "ookazi", "ookazi",
  -- Traps
  "mirror_force", "mirror_force", "fissure", "trap_hole",
}

DECK_JOEY = {
  -- Monsters
  "red_eyes_b_dragon", "battle_ox", "la_jinn", "vorse_raider", "seven_color_fish", "ufo_turtle", "man_eater_bug", "man_eater_bug",
  -- Spells
  "raigeki", "ookazi", "ookazi",
  -- Traps
  "trap_hole", "mirror_force", "mirror_force",
}

DECK_KAIBA = {
  -- Monsters
  "summoned_skull", "summoned_skull", "red_eyes_b_dragon", "red_eyes_b_dragon", "battle_ox", "la_jinn", "vorse_raider",
  -- Spells
  "dark_hole", "raigeki", "fissure", "mystical_typhoon", "mystical_typhoon",
  -- Traps
  "trap_hole", "mirror_force", "mirror_force",
}

DECK_MARIK = {
  -- Monsters
  "gravekeeper_oracle", "gravekeeper_shaman", "gravekeeper_spy", "gravekeeper_spy",
  "gravekeeper_assailant", "gravekeeper_assailant", "gravekeeper_curse", "gravekeeper_curse",
  "a_cat_of_ill_omen", "a_cat_of_ill_omen",
  -- Spells
  "dark_hole", "raigeki", "ookazi", "necrovalley", "necrovalley", "gravekeeper_stele", "gravekeeper_stele",
  -- Traps
  "trap_hole", "mirror_force", "mirror_force",
}

-- Selectable opponents. spr = top-left tile of a 32x32 (4x4 tile) portrait.
OPPONENTS={
 {name="YUGI",  spr=384, deck=DECK_YUGI,  quotes={
  "I believe in the Heart of the Cards!",
  "Because I have friends who believe in me, I can fight!"}},
 {name="JOEY",  spr=388, deck=DECK_JOEY,  quotes={
  "I'm gonna take this loser to school!",
  "It's Wheeler time, baby!"}},
 {name="KAIBA", spr=392, deck=DECK_KAIBA, quotes={
  "You're a third-rate duelist with a fourth-rate deck!",
  "Why don't you go look for an opponent you can actually beat? Like an infant, or a monkey."}},
 {name="MARIK", spr=396, deck=DECK_MARIK, quotes={
  "The shadows hunger for your soul.",
  "Is that fear in your eyes? I like to see this side of you.",
  "Mercy is for the weak, like you, my friend."}},
}
OPP_SEL=1

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

-- Tribute worth of monster `m` toward summoning `summonCard`: Double Coston
-- counts as 2 for a DARK Tribute Summon. A nil monster is worth 0.
function tributeValueOf(summonCard,m)
 if not m then return 0 end
 if m.effect=="doublecoston" and summonCard and summonCard.attr=="dark" then return 2 end
 if summonCard and summonCard.effect=="gkoracle" and isGravekeeper(m) then return 3 end
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
function getEquipBonus(card)
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
 return ab,db
end

-- Returns effective ATK, applying continuous and equip bonuses.
function getMonAtk(card)
 local bonus=0
 local b=behaviorOf(card)
 if b and b.atkBonus then bonus=b.atkBonus(card) end
 local ab,_=getEquipBonus(card)
 local nv=(isGravekeeper(card) and necrovalleyActive()) and 500 or 0
 return math.max(0, card.atk+bonus+ab+nv)
end

-- Returns effective DEF, applying equip bonuses and the Necrovalley boost.
function getMonDef(card)
 local bonus=0
 local b=behaviorOf(card)
 if b and b.defBonus then bonus=b.defBonus(card) end
 local _,db=getEquipBonus(card)
 local nv=(isGravekeeper(card) and necrovalleyActive()) and 500 or 0
 return math.max(0, card.def+bonus+db+nv)
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
    table.insert(list,{card=m,kind="mon",zc=zc,
     x=(p==1) and COL[c] or COL[4-c], y=(p==1) and PY_M or OY_M})
   end
   local s=G.st[p][c]
   if s and s.facedown then
    table.insert(list,{card=s,kind="st",zc=zc,
     x=(p==1) and COL[c] or COL[4-c], y=(p==1) and PY_S or OY_S})
   end
  end
 end
 if #list==0 then return end
 addAnim(90,function(t,f)
  for _,e in ipairs(list) do
   if e.kind=="st" then dCardSpell(e.x,e.y,e.card,e.zc)
   elseif e.card.pos==2 then dCardDef(e.x,e.y,e.card,e.zc)
   else dCardAtk(e.x,e.y,e.card,e.zc) end
   if (t//6)%2==0 then rectb(e.x,e.y,ZW_MAIN,ZH,CT) end
  end
 end)
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
  fs ={nil,nil},  -- field spell per player (the FS zone)
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
  chain=nil,
  _pending=nil,
 }
 ANIM={}
end

-- ============================================================
-- CURSOR HELPERS
-- ============================================================
function getHoveredCard()
 local c=G.cur
 if c.row==3 then return G.hand[c.side][c.col+1] end
 if c.row==1 then
  if c.side==1 and c.col==0 then return G.fs[1] end
  if c.side==2 and c.col==4 then return G.fs[2] end
 end
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
  if sel.atk then print("ATK:"..sel.atk.."  DEF:"..(sel.def or 0).."  LV:"..(sel.lvl or 0),listX,SH-24,CT,true,1,false) end
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
  if item then G.mode="free"; G.deckSel=nil; ds.onPick(item.deckIdx,item) end
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
 local lp2=(G.oppName or "OPP").."  "..G.lp[2].." LP"
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

-- Visually destroy a S/T card: if face-down, flip it face-up first and let the
-- player see what it was during a flash; then send to GY. For face-up cards,
-- flash + destroy immediately. The reveal path defers GY-move into the flash's
-- onDone so the revealed card remains visible during the flash.
function revealAndDestroyST(plr,col)
 local card=G.st[plr][col]
 if not card then return end
 local zx=(plr==1) and COL[col] or COL[4-col]
 local zy=(plr==1) and PY_S or OY_S
 if card.facedown then
  card.facedown=false
  addAnim(24,function(t,f) if t//4%2==0 then rect(zx,zy,ZW_MAIN,ZH,CCR) end end,
   function() sendSpellTrapToGY(plr,col,"effect") end)
 else
  destroyFlash(zx,zy)
  sendSpellTrapToGY(plr,col,"effect")
 end
end

-- Monster counterpart: if face-down, reveal it before destroying so the player
-- sees what is being removed. For face-up monsters this is equivalent to
-- sendMonsterToGY (which already calls destroyFlash for destruction reasons).
-- The reveal path defers sendMonsterToGY + flushTriggers into the flash's
-- onDone — meaning onDestroy triggers for revealed face-down monsters fire
-- after the reveal animation, not in lockstep with face-up destructions.
function revealAndDestroyMon(plr,col,reason)
 local m=G.mon[plr][col]
 if not m then return end
 if m.facedown and DESTROY_REASONS[reason] then
  m.facedown=false
  local zx,zy=monZoneXY(plr,col)
  addAnim(24,function(t,f) if t//4%2==0 then rect(zx,zy,ZW_MAIN,ZH,CCR) end end,
   function() sendMonsterToGY(plr,col,reason); flushTriggers() end)
  return
 end
 sendMonsterToGY(plr,col,reason)
end

-- LP change helper: clamps and checks win; dispLp animates toward G.lp each tick
function changeLp(plr,delta)
 G.lp[plr]=math.max(0,G.lp[plr]+delta)
 checkWin()
end

-- Apply battle damage. If a card in `plr`'s hand has a `handTrap` behavior
-- (e.g. Kuriboh), it's offered first (player) or auto-used (AI).
function applyDamage(plr,dmg)
 if dmg<=0 then return end
 for i,card in ipairs(G.hand[plr]) do
  local b=behaviorOf(card)
  if b and b.handTrap then b.handTrap(plr,dmg,i,card); return end
 end
 changeLp(plr,-dmg)
end

-- ============================================================
-- MUTATIONS (single source of truth for moving cards)
-- ============================================================
-- All field/hand -> GY movement must go through these helpers so that:
--  (1) destroyFlash fires consistently
--  (2) onDestroy triggers are queued automatically via G._pending
--  (3) linkedTrap / linkedMon back-pointers are cleared
--  (4) the future chain system has a single seam to hook into
-- `reason` is a free-form tag: "battle", "effect", "cost", "tribute",
-- "rule" (self-destruct, e.g. equip with no target). Triggered effects
-- may inspect it to decide whether they fire (PSCT "by battle" vs
-- "by card effect" distinction).

-- Reasons that count as "destruction" and fire onDestroy triggers.
-- Reasons like "tribute" and "cost" only send the card to GY; they do not
-- fire destruction triggers (per PSCT). A future "onSent" event will cover
-- those if any card ever needs to react to leaving the field for any reason.
DESTROY_REASONS={battle=true,effect=true,rule=true}

function queueTrigger(card,plr,reason)
 if not DESTROY_REASONS[reason] then return end
 G._pending=G._pending or {}
 table.insert(G._pending,{card=card,plr=plr,reason=reason})
end

function flushTriggers()
 if not G._pending or #G._pending==0 then checkEquips() return end
 local t=G._pending; G._pending={}
 deferEffects(t)
 checkEquips()
end

function sendMonsterToGY(plr,col,reason)
 local m=G.mon[plr][col]
 if not m then return nil end
 G.mon[plr][col]=nil
 table.insert(G.gy[plr],m)
 if DESTROY_REASONS[reason] then
  local zx,zy=monZoneXY(plr,col)
  destroyFlash(zx,zy)
 end
 -- If this monster was summoned by a linked trap (Call of the Haunted etc.),
 -- destroy that trap too when it leaves the field for any reason. Skipped
 -- while Jinzo is face-up: that trap's continuous effect is negated.
 if m.linkedTrap and not jinzoActive() then
  for p=1,2 do for c=1,3 do
   if G.st[p][c]==m.linkedTrap then sendSpellTrapToGY(p,c,"rule") end
  end end
 end
 queueTrigger(m,plr,reason)
 return m
end

function sendSpellTrapToGY(plr,col,reason)
 local c=G.st[plr][col]
 if not c then return nil end
 G.st[plr][col]=nil
 if c.linkedMon then c.linkedMon.linkedTrap=nil; c.linkedMon=nil end
 table.insert(G.gy[plr],c)
 return c
end

function discardFromHand(plr,handIdx,reason)
 local c=G.hand[plr][handIdx]
 if not c then return nil end
 table.remove(G.hand[plr],handIdx)
 table.insert(G.gy[plr],c)
 return c
end

function addToGY(plr,card,reason)
 if not card then return end
 table.insert(G.gy[plr],card)
end

-- Move a player's field spell from the FS zone to their GY (e.g. replaced by
-- a new field spell, or destroyed).
function sendFieldSpellToGY(plr,reason)
 local f=G.fs[plr]
 if not f then return nil end
 G.fs[plr]=nil
 table.insert(G.gy[plr],f)
 return f
end

-- ============================================================
-- CHAIN STACK
-- ============================================================
-- The chain is YGO's mechanism for resolving simultaneous/responding
-- effects. LIFO: links push onto the top as players respond, then resolve
-- from top to bottom once both players pass consecutively.
--
-- G.chain is nil when no chain is active. When active:
--   G.chain = {
--     links    = { EffectInstance, ... },   -- index 1 = Link 1 (bottom)
--     offering = 1 | 2,                     -- who currently has priority
--     passes   = 0,                         -- 2 = both passed -> resolve
--     trigger  = { event=, ctx= } | nil,    -- the action that opened this
--     reason   = "spell"|"trap"|"trigger",  -- why this chain exists
--   }
--
-- EffectInstance fields:
--   source     - the card object
--   controller - 1 | 2  (who activated)
--   speed      - 1 | 2 | 3
--   sourceLoc  - { zone, plr, col } cleanup location after resolution
--                  zone = "st" | "hand" | "field" | nil
--   targets    - frozen snapshot at activation (for fizzle checks)
--   resolveFn  - function(self) called when this link resolves
--
-- This file ONLY defines the data model + lifecycle. Existing code paths
-- (spell activation, attack resolution, AI traps) have not been rewired
-- yet -- the game still works as before. Wiring is step 2b.

-- Derive spell speed from card data so we don't have to annotate every card.
function chainSpeed(card)
 if not card then return 1 end
 local b=behaviorOf(card)
 if b and b.speed then return b.speed end
 if card.cat=="trap"  then return card.subtype=="counter"   and 3 or 2 end
 if card.cat=="spell" then return card.subtype=="quickplay" and 2 or 1 end
 return 1  -- monster default (Ignition / Flip / Trigger)
end

function chainTopSpeed()
 if not G.chain or #G.chain.links==0 then return 0 end
 return G.chain.links[#G.chain.links].speed
end

-- True if this card's speed is high enough to add to the current chain.
-- Open-game-state priority is enforced by the caller, not here.
function canRespondToChain(card)
 local s=chainSpeed(card)
 if not G.chain or #G.chain.links==0 then return true end
 return s>=chainTopSpeed()
end

function openChain(trigger,reason)
 G.chain={links={},offering=nil,passes=0,trigger=trigger,reason=reason}
end

function closeChain()
 G.chain=nil
end

function pushChainLink(link)
 if not G.chain then openChain(nil,"spell") end
 link.speed=link.speed or chainSpeed(link.source)
 table.insert(G.chain.links,link)
 G.chain.passes=0
 G.chain.offering=3-link.controller  -- pass priority to opponent
end

-- Build a chain link for a spell or trap card activated from a known location.
-- col may be nil for cards activated from hand (e.g. Quick-Play from hand).
function makeSpellTrapLink(card,controller,zone,plr,col,targets)
 return {
  source     = card,
  controller = controller,
  speed      = chainSpeed(card),
  sourceLoc  = {zone=zone,plr=plr,col=col},
  targets    = targets,
  resolveFn  = function(self)
   local ctx=G.chain and G.chain.trigger and G.chain.trigger.ctx
   applyResolve(self.source,self.controller,ctx)
  end,
 }
end

-- After a link resolves, dispose of its source per card type:
--  - Normal spell/trap on field -> GY
--  - Continuous/equip spell -> stays face-up on field
--  - Card activated from hand -> GY
function spendChainLink(link)
 local loc=link.sourceLoc
 if not loc then return end
 if loc.zone=="st" then
  local c=link.source
  if c.subtype=="continuous" or c.subtype=="equip" then
   c.facedown=false
  else
   sendSpellTrapToGY(loc.plr,loc.col,"effect")
  end
 elseif loc.zone=="fs" then
  -- Field spell stays face-up in the FS zone after resolving.
  link.source.facedown=false
 elseif loc.zone=="hand" then
  for i,h in ipairs(G.hand[loc.plr]) do
   if h==link.source then discardFromHand(loc.plr,i,"effect"); break end
  end
 end
end

-- Called when both players have passed consecutively.
-- Resolves links from top (last pushed) to bottom (first pushed).
-- Sets G.chainResolving=true during the loop so callbacks invoked from
-- resolveFn (e.g. legacy returnToTrapSelect) can detect they're mid-chain
-- and skip flow control they no longer own.
-- If trigger.onResolved is set and trigger.consumed is not, runs the
-- continuation after the chain closes.
function resolveChain()
 if not G.chain then return end
 local trig=G.chain.trigger
 local links=G.chain.links
 local resolved=#links>0
 G.chainResolving=true
 for i=#links,1,-1 do
  local link=links[i]
  -- Negated links (e.g. by Magic Jammer) skip their resolveFn but still
  -- run spendChainLink so the source card goes to GY / cleans up properly.
  -- (The negating effect typically also destroys the source itself, but
  -- spendChainLink is idempotent — sendSpellTrapToGY no-ops if already gone.)
  if not link.negated and link.resolveFn then link.resolveFn(link) end
  spendChainLink(link)
 end
 closeChain()
 G.chainResolving=false
 -- onDestroy etc. triggers queued during resolution become a NEW chain (SEGOC).
 flushTriggers()
 if trig and trig.onResolved then
  -- The legacy "consumed" flag (set by Mirror Force) means the original
  -- action is canceled. Migrating callers should instead check game state
  -- inside onResolved (e.g. "is the attacker still on the field?").
  local consumed=G.trapSelect and G.trapSelect.consumed
  if not consumed then trig.onResolved(resolved) end
 end
end

-- Current offering player passes. After two consecutive passes, resolve.
function passChainPriority()
 if not G.chain then return end
 G.chain.passes=G.chain.passes+1
 if G.chain.passes>=2 then
  resolveChain()
 else
  G.chain.offering=3-G.chain.offering
 end
end

-- Minimal chain stack overlay. Renders nothing when chain is empty (open
-- response window with no links yet). When N>=1 links exist, shows a small
-- chip centered above the divider listing each link bottom-to-top.
-- Small banner showing what the current input mode is asking for. Drawn
-- below the chain stack overlay when relevant.
function drawModeBanner()
 local txt=nil
 if G.mode=="sel_discard" and G.discardSel then
  txt=G.discardSel.title or "DISCARD"
 elseif G.mode=="sel_st_target" and G.stTargetSel then
  txt=G.stTargetSel.title or "PICK S/T"
 elseif G.mode=="sel_destroy" and G.destroySel and G.destroySel.title then
  txt=G.destroySel.title
 end
 if not txt then return end
 local w=#txt*4+8
 local x=FA_X+(FA_W-w)//2
 local y=DIV_Y+24
 rect(x,y,w,9,CCR)
 rectb(x,y,w,9,CT)
 print(txt,x+4,y+2,CT,true,1,true)
end

function drawChain()
 if not G.chain then return end
 local links=G.chain.links
 local n=#links
 if n==0 then return end
 local rowH=7
 local h=10+n*rowH
 local w=70
 local x=FA_X+(FA_W-w)//2
 local y=DIV_Y-h//2
 rect(x,y,w,h,CB)
 rectb(x,y,w,h,CT)
 print("CHAIN "..n,x+4,y+2,CCR,true,1,true)
 for i=1,n do
  local lk=links[i]
  local nm=(lk.source and lk.source.name) or "?"
  if #nm>13 then nm=nm:sub(1,13) end
  print(i..":"..nm,x+4,y+9+(i-1)*rowH,CT,true,1,true)
 end
end

-- Does `plr` own a face-down S/T card that could chain onto the current trigger?
-- Returns true if at least one face-down trap in plr's S/T zones has a
-- BEHAVIORS.triggers[event] (or chain_open) predicate that returns true.
-- Note: this only covers face-down S/T responses. Quick Effects from hand
-- (Kuriboh) are evaluated separately via applyDamage's handTrap hook.
function playerHasChainableResponse(plr)
 if not G.chain or not G.chain.trigger then return false end
 local trig=G.chain.trigger
 if not trig.event then return false end
 if plr==1 then
  return hasActivatableTrap(trig.event,trig.ctx)
 end
 return aiHasChainableResponse(trig.event,trig.ctx)
end

-- Find AI's first chainable face-down trap for (event,ctx). Returns
-- (stCol, trap, behavior) or nil. Used by both has-check and activation.
function findAIChainResponder(event,ctx)
 if not event then return nil end
 for i=1,3 do
  if trapCanRespond(G.st[2][i],event,ctx,2) then
   return i,G.st[2][i],behaviorOf(G.st[2][i])
  end
 end
end

function aiHasChainableResponse(event,ctx)
 return findAIChainResponder(event,ctx)~=nil
end

-- Fire AI's first matching face-down trap. If the behavior has a custom
-- `activate` (e.g. needs target picking) it's used; otherwise the standard
-- flip-anim + resolve flow runs.
function aiActivateChainResponse()
 if not G.chain or not G.chain.trigger then return end
 local trig=G.chain.trigger
 local ctx=trig.ctx or {}
 local i,t,b=findAIChainResponder(trig.event,ctx)
 if not i then return end
 if b.activate then
  b.activate{col=i,card=t,zone="st",plr=2,trigCtx=ctx}
 else
  activateAITrapAnim(i,t,function()
   if b.resolve then b.resolve(2,ctx) end
   checkWin()
  end)
 end
end

-- Drive the chain forward: while neither side has (or chooses to use) a response,
-- auto-pass priority until two consecutive passes resolve it.
-- When the player has a response, sets G.mode="opp_trap_select" and returns.
-- When the AI has a response, fires it via aiActivateChainResponse and returns;
-- the trap's flip animation will re-enter advanceChain on completion.
function advanceChain()
 while G.chain and G.chain.passes<2 do
  local offering=G.chain.offering
  if playerHasChainableResponse(offering) then
   if offering==1 then
    -- Synthesize a G.trapSelect if one doesn't exist (e.g. AI-initiated chain
    -- where checkTraps was never called). The existing opp_trap_select UI
    -- reads from G.trapSelect, so we have to populate it.
    if not G.trapSelect then
     local trig=G.chain.trigger or {}
     G.trapSelect={event=trig.event or "chain_open",ctx=trig.ctx or {},consumed=false}
    end
    G.mode="opp_trap_select"
    positionTrapSelectCursor()
    return
   end
   if offering==2 then
    aiActivateChainResponse()
    return
   end
   passChainPriority()
  else
   passChainPriority()
  end
 end
end

-- Move the cursor to a face-down trap that is currently valid to activate.
-- If the current cursor zone already holds a valid trap, leave it; otherwise
-- scan zones in order and snap to the first match.
function positionTrapSelectCursor()
 local ts=G.trapSelect
 if not ts then return end
 local col=(G.cur and G.cur.col) or 1
 if col<1 then col=1 elseif col>3 then col=3 end
 G.cur={side=1,row=2,col=col}
 if trapCanRespond(G.st[1][col],ts.event,ts.ctx,1) then return end
 for i=1,3 do
  if trapCanRespond(G.st[1][i],ts.event,ts.ctx,1) then G.cur.col=i; return end
 end
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
  for _,e in ipairs(triggered) do fireMonHook(e.card,"onDestroy",e.plr) end
  checkEquips()
 end)
end

function animSpellActivation(col,zy,card,plr)
 local zx=(plr==1) and COL[col] or COL[4-col]
 local sc=card.cat=="spell" and CSP or CTR
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,zy,ZW_MAIN,ZH,sc); rectb(zx,zy,ZW_MAIN,ZH,CT) end
 end,function()
  card.facedown=false
  if not G.chain then
   openChain({event="spell_activation",ctx={source=card,controller=plr}},"spell")
  end
  pushChainLink(makeSpellTrapLink(card,plr,"st",plr,col,nil))
  advanceChain()
 end)
end

-- Field-spell activation: the card already sits face-up in G.fs[plr]; flash
-- the FS zone, then push the chain link (sourceLoc zone="fs").
function animFieldSpellActivation(card,plr)
 local zx=(plr==1) and COL[0] or COL[4]
 local zy=(plr==1) and PY_M or OY_M
 addAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,zy,ZW_SPEC,ZH,CSP); rectb(zx,zy,ZW_SPEC,ZH,CT) end
 end,function()
  card.facedown=false
  if not G.chain then
   openChain({event="spell_activation",ctx={source=card,controller=plr}},"spell")
  end
  pushChainLink(makeSpellTrapLink(card,plr,"fs",plr,nil,nil))
  advanceChain()
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
--   triggers[event]    function(t,ctx) -> bool, predicate for chain response window
--                      events: "summon", "attack", "phase", "chain_open"
--   resolve(plr,ctx)   called when this card's chain link resolves
--   canActivate(card)  predicate gating manual activation (menu / chain)
--   activate(opts)     custom activation flow; opts = {col,card,zone,plr,trigCtx}
--                      when absent, default flow (activateTrapAnim / animSpellActivation)
--   aiCanCast(card)    AI: cast this spell from hand this turn?
--   onDestroy(card,plr) monster hook fired when destroyed
--   onFlip(card,plr)    monster hook fired when flipped face-up
--   onTributed(card,plr) monster hook fired when tributed
--   handTrap(plr,dmg,handIdx,card) hand quick-effect (Kuriboh-style)
--   atkBonus(card)     per-card ATK bonus (Dark Magician Girl, Buster Blader)
--   equipBonus(tgt,eq) per-equip stat bonus -> ab,db
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
  -- Continuous Spell: stays face-up, locks the opponent's attacks. The
  -- swordsCounter (set on resolve) is decremented each of their End Phases
  -- by tickSwords; the card self-destructs after the 3rd.
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
    discardFromHand(2,handIdx,"effect")
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
  -- Counts as 2 Tributes for a DARK Tribute Summon. The tribute-value logic
  -- lives in tributeValueOf(); no hook needed here.
 },
 jinzo={
  -- While face-up, Trap Cards cannot be activated. Enforced by jinzoActive()
  -- in trapCanRespond and buildMenu; no hook needed here.
 },
 gkcurse={
  -- Each time summoned (Normal or Special), burn the opponent for 800.
  onSummon=function(card,plr) changeLp(3-plr,-800) end,
 },
 gkassailant={
  -- Attack-time battle-position change. Driven inline by confirmPlayerAttack /
  -- the sel_atk confirm path (gated on necrovalleyActive); no hook needed here.
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
     if eff==1 then card.atk=card.atk+td.lvlSum*100
     elseif eff==2 then
      for i=1,3 do
       if G.mon[1][i] and G.mon[1][i].facedown then revealAndDestroyMon(1,i,"effect") end
      end
      flushTriggers()
     elseif eff==3 then
      for i=1,3 do
       local m=G.mon[1][i]
       if m then m.atk=math.max(0,m.atk-2000); m.def=math.max(0,m.def-2000) end
      end
     end
     td.gkCount=td.gkCount-1
    end
   end
  end,
 },
}

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

-- True if a face-up Jinzo is on the field (either side): Traps cannot be
-- activated while this holds.
function jinzoActive()
 for p=1,2 do
  for c=1,3 do
   local m=G.mon[p][c]
   if m and m.effect=="jinzo" and not m.facedown then return true end
  end
 end
 return false
end

-- True if either graveyard holds a monster (Monster Reborn target check).
function anyGYMonster()
 for p=1,2 do
  for _,c in ipairs(G.gy[p]) do if c.cat=="monster" then return true end end
 end
 return false
end

-- True if `plr`'s monsters cannot declare an attack: their opponent controls
-- a face-up Swords of Revealing Light.
function swordsBlocks(plr)
 local opp=3-plr
 for c=1,3 do
  local s=G.st[opp][c]
  if s and not s.facedown and s.effect=="swords" then return true end
 end
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

-- True if a face-up Gravekeeper's Shaman is on either player's monster zone.
function shamanActive()
 for p=1,2 do for i=1,3 do
  local m=G.mon[p][i]
  if m and not m.facedown and m.effect=="gkshaman" then return true end
 end end
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
 local b=behaviorOf(card)
 if b and b.onSummon then b.onSummon(card,plr) end
end

-- Returns true if face-down trap `t` on the field can chain to `event`/`ctx`.
-- `controller` = player who owns trap `t` (1 or 2). Trigger functions use it
-- to verify the acting player (ctx.actor) is their opponent.
function trapCanRespond(t,event,ctx,controller)
 if not (t and t.facedown and not t.setThisTurn) then return false end
 if jinzoActive() then return false end  -- Jinzo: Traps cannot be activated
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

-- Opens the sequential Oracle effect picker. `op` holds pick state.
function openOraclePick(op)
 local items={}
 if not op.used[1] then items[#items+1]={"+"..op.lvlSum*100 .." ATK","oracle_e1"} end
 if not op.used[2] then items[#items+1]={"DESTROY SET MONS","oracle_e2"} end
 if not op.used[3] then items[#items+1]={"OPP -2000 ATK/DEF","oracle_e3"} end
 items[#items+1]={"DONE","oracle_done"}
 G.oraclePick=op
 G.menu={open=true,sel=1,items=items}
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
     local b=behaviorOf(card)
     local canActivate
     if card.subtype=="equip" then
      canActivate = emptyZone and (hasMonsters(1) or hasMonsters(2))
     elseif b and b.canActivate then
      canActivate = emptyZone and b.canActivate(card)
     else
      canActivate = true
     end
     if canActivate then table.insert(items,{"ACTIVATE","cast_hand"}) end
     -- Field spells go straight to the FS zone; no face-down Set option.
     if emptyZone and card.subtype~="field" then table.insert(items,{"SET","set_st"}) end
    elseif card.cat=="trap" then
     if firstEmpty(G.st[1]) then table.insert(items,{"SET","set_st"}) end
    elseif not G.normalSummoned then
     local emptyZone=false
     for i=1,3 do
      if not G.mon[1][i] then emptyZone=true end
     end
     local tribNeeded=tribsNeeded(card.lvl or 1)
     -- fieldTributeValue counts Double Coston as 2 for DARK summons.
     local canSummon=(tribNeeded==0 and emptyZone)
                  or (tribNeeded>=1 and fieldTributeValue(card,1)>=tribNeeded)
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
    if G.ph==PH_BATTLE and card.pos==1 and not card.facedown and not card.attacked
       and not swordsBlocks(1) then
     table.insert(items,{"ATTACK","attack"})
    end
   end

  elseif c.row==2 and c.col>=1 and c.col<=3 then  -- spell/trap zone
   local card=G.st[1][c.col]
   -- Only face-down cards may be activated; a face-up card here is an
   -- already-active continuous/equip card and must not be re-activated.
   if card and card.facedown and not card.setThisTurn then
    local b=behaviorOf(card)
    if card.cat=="spell" and isMain then
     local canActivate
     if card.subtype=="equip" then
      canActivate = hasMonsters(1) or hasMonsters(2)
     elseif b and b.canActivate then
      canActivate = b.canActivate(card)
     else
      canActivate = true
     end
     if canActivate then table.insert(items,{"ACTIVATE","activate"}) end
    elseif card.cat=="trap" and not (b and b.responseOnly) and not jinzoActive() then
     if not (b and b.canActivate) or b.canActivate(card) then
      table.insert(items,{"ACTIVATE","activate"})
     end
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
    fireMonHook(card,"onFlip",1)
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
   elseif card.subtype=="field" then
    if fieldSpellBlocked(1) then return end
    -- Field spell: goes straight to the FS zone, replacing any field spell
    -- already there. No zone pick needed (one field zone per player).
    local fcard=copyCard(card)
    fcard.facedown=false
    if G.fs[1] then sendFieldSpellToGY(1,"rule") end
    G.fs[1]=fcard
    table.remove(G.hand[1],handIdx)
    G.mode="free"
    G.cur={side=1,row=1,col=0}
    animFieldSpellActivation(fcard,1)
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
    local b=behaviorOf(card)
    if b and b.activate then
     b.activate{col=col,card=card,zone="st",plr=1}
    elseif card.cat=="trap" then
     activateTrapAnim(col,card,function() applyResolve(card,1) end)
    else
     card.facedown=false
     animSpellActivation(col,PY_S,card,1)
    end
   end
  end

 elseif key=="nextphase" then
  changePhase(G.ph+1)

 elseif key=="endturn" then
  changePhase(PH_END)
  G.autoTimer=1

 elseif key=="oracle_e1" or key=="oracle_e2" or key=="oracle_e3" or key=="oracle_done" then
  local op=G.oraclePick; if not op then return end
  if key~="oracle_done" then
   local eff=({oracle_e1=1,oracle_e2=2,oracle_e3=3})[key]
   op.used[eff]=true
   if eff==1 then
    op.card.atk=op.card.atk+op.lvlSum*100
   elseif eff==2 then
    local opp=3-op.plr
    for i=1,3 do
     if G.mon[opp][i] and G.mon[opp][i].facedown then
      revealAndDestroyMon(opp,i,"effect")
     end
    end
    flushTriggers()
   elseif eff==3 then
    local opp=3-op.plr
    for i=1,3 do
     local m=G.mon[opp][i]
     if m then m.atk=math.max(0,m.atk-2000); m.def=math.max(0,m.def-2000) end
    end
   end
   op.remaining=op.remaining-1
  end
  if key=="oracle_done" or op.remaining<=0 then
   G.oraclePick=nil
  else
   openOraclePick(op)
  end

 elseif key=="ss_atk" or key=="ss_def" then
  local ps=G.pendingSS; G.pendingSS=nil
  if ps then
   local col=firstEmpty(G.mon[ps.plr])
   if col then
    local m=ps.card
    m.pos=(key=="ss_atk") and 1 or 2
    m.facedown=false; m.attacked=false; m.summoned=true; m.posChanged=false
    G.mon[ps.plr][col]=m
    fireSummonHook(m,ps.plr)
   end
  end

 elseif key=="reborn_atk" or key=="reborn_def" then
  -- Monster Reborn: position chosen, now activate. The chain link's resolveFn
  -- special-summons the captured GY monster at the picked position.
  local rs=G.rebornSel; G.rebornSel=nil
  if rs then
   local pos=(key=="reborn_atk") and 1 or 2
   pushActivationLink({card=rs.card,col=rs.col,zone=rs.zone,plr=1},function()
    local emptyCol=firstEmpty(G.mon[1])
    local m=emptyCol and G.gy[rs.gyPlr][rs.gyIdx]
    if not (emptyCol and m and m.cat=="monster") then return end
    table.remove(G.gy[rs.gyPlr],rs.gyIdx)
    m.pos=pos; m.facedown=false; m.attacked=false; m.summoned=false; m.posChanged=false
    m.linkedTrap=nil
    G.mon[1][emptyCol]=m
    fireSummonHook(m,1)
   end)
  end

 elseif key=="assail_yes" then
  -- Gravekeeper's Assailant: pick 1 opponent monster, change its battle
  -- position, then continue the declared attack.
  G.mode="sel_destroy"
  G.destroySel={side=2,title="ASSAILANT: CHANGE POS",onPick=function(side,ti)
   local m=G.mon[side][ti]
   if m then
    if m.facedown then
     m.facedown=false; m.pos=1; fireMonHook(m,"onFlip",2)
    else
     m.pos=(m.pos==1) and 2 or 1
    end
    m.posChanged=true
    checkEquips()
   end
   confirmPlayerAttack()
  end}
  G.cur={side=2,row=1,col=4-(firstOccupied(G.mon[2]) or 1)}

 elseif key=="assail_no" then
  confirmPlayerAttack()
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
   local atkV=getMonAtk(attacker); local tgtV=getMonAtk(target); local tgtDef=getMonDef(target)
   if target.pos==2 then
    if atkV>tgtDef then
     sendMonsterToGY(2,tgtIdx,"battle")
    elseif atkV<tgtDef then
     changeLp(1,-(tgtDef-atkV))
    end
   else
    if atkV>tgtV then
     sendMonsterToGY(2,tgtIdx,"battle")
     applyDamage(2,atkV-tgtV)
    elseif atkV<tgtV then
     sendMonsterToGY(1,atkCol,"battle")
     changeLp(1,-(tgtV-atkV))
    else
     sendMonsterToGY(2,tgtIdx,"battle")
     sendMonsterToGY(1,atkCol,"battle")
    end
   end
   checkWin()
   flushTriggers()
   if wasFlipped then fireMonHook(target,"onFlip",2) end
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

-- Resolve a player-declared attack: run the AI's trap window, then carry out
-- the attack on the target stored in G.pending (set when the attack was
-- confirmed). Used both for normal attacks and after Assailant's effect.
function confirmPlayerAttack()
 local p=G.pending
 if not p then return end
 local tgtIdx=p.tgtIdx
 local function proceedAttack()
  -- Re-check attacker (chain may have destroyed it, e.g. Mirror Force)
  if not p.attacker or G.mon[1][p.atkCol]~=p.attacker then
   G.mode="free"; G.pending=nil; return
  end
  if not hasMonsters(2) then
   resolveAttack(p.attacker,p.atkCol,nil,nil)
  else
   local target=G.mon[2][tgtIdx]
   if target then
    resolveAttack(p.attacker,p.atkCol,target,tgtIdx)
   end
   -- If target is nil (cursor on empty zone), do nothing; player stays in
   -- sel_atk and can re-navigate. Matches pre-chain behavior.
  end
 end
 if not checkAITraps("attack",{att=p.attacker,atkCol=p.atkCol},proceedAttack) then
  proceedAttack()
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

-- Field-spell zone (ZW_SPEC wide): empty shows the "FS" label, occupied shows
-- the field spell card.
function dFieldSpellSlot(x,y,card)
 if not card then
  dZone(x,y,ZW_SPEC,ZH,CFS,"FS")
 elseif card.facedown then
  rect(x,y,ZW_SPEC,ZH,CFS)
  dCardBack(x,y+1,ZW_SPEC,ZH-2,0)
  rectb(x,y,ZW_SPEC,ZH,CD)
 else
  rect(x,y,ZW_SPEC,ZH,CFS)
  rect(x+2,y+1,ZW_SPEC-4,ZH-2,CSP)
  if card.spr then spr(card.spr,x+2,y+2,card.bg,1,0,0,2,2) end
  rectb(x,y,ZW_SPEC,ZH,CD)
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
  if card and card.swordsCounter and not card.facedown then
   print(tostring(card.swordsCounter),COL[c]+ZW_MAIN-7,OY_S+2,CCR,true,1,false)
  end
 end
 dZone(COL[4],OY_S,ZW_SPEC,ZH,CED,"ED")

 dZone(COL[0],OY_M,ZW_SPEC,ZH,CGY,"GY",#G.gy[2])
 for c=1,3 do
  local card=G.mon[2][4-c]
  dFieldSlot(COL[c],OY_M,card,card and card.facedown,COZ)
  if (G.mode=="sel_atk" or (G.mode=="sel_destroy" and (not G.destroySel.side or G.destroySel.side==2))) and card then dDotBorder(COL[c],OY_M,ZW_MAIN,ZH) end
  if G.mode=="sel_equip" and card and not card.facedown then dDotBorder(COL[c],OY_M,ZW_MAIN,ZH,CSP) end
  if G.battleAnim and G.battleAnim.atkCol and (4-c)==G.battleAnim.atkCol then
   dDotBorder(COL[c],OY_M,ZW_MAIN,ZH,CAT)
  end
 end
 dFieldSpellSlot(COL[4],OY_M,G.fs[2])
end

-- Player (divider → bottom):
--   PY_M: [FS][M1][M2][M3][GY]
--   PY_S: [ED][S1][S2][S3][DK]
--   PY_H: face-up hand cards (centered)
function drawPlrSide()
 dFieldSpellSlot(COL[0],PY_M,G.fs[1])
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
  elseif G.mode=="sel_destroy" and G.mon[1][c] and (not G.destroySel.side or G.destroySel.side==1) then
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
  if card and card.swordsCounter and not card.facedown then
   print(tostring(card.swordsCounter),COL[c]+ZW_MAIN-7,PY_S+2,CCR,true,1,false)
  end
  if G.mode=="sel_st" and not card then dDotBorder(COL[c],PY_S,ZW_MAIN,ZH) end
  if G.mode=="opp_trap_select" and G.trapSelect and trapCanRespond(card,G.trapSelect.event,G.trapSelect.ctx,1) then
   dDotBorder(COL[c],PY_S,ZW_MAIN,ZH)
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
  print("TRIBUTE "..(p and tributeTotal(p) or 0).."/".. (p and p.tribNeeded or 0),2,71,CFS,true,1,true)
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
 -- Necrovalley negates moving a card out of the GY: skip GY candidates.
 if not necrovalleyActive() then
  for i,card in ipairs(G.gy[1]) do addItem("gy",card,i) end
 end
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
    discardFromHand(1,ta.handIdx,"cost")
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

 -- Discard picker (e.g. Magic Jammer cost): cursor on player hand
 if G.mode=="sel_discard" and G.discardSel then
  local n=#G.hand[1]
  if n==0 then G.mode="opp_trap_select"; G.discardSel=nil; positionTrapSelectCursor(); return end
  if c.row~=3 then c.row=3; c.col=0 end
  if btnp(2) then c.col=math.max(0,c.col-1)
  elseif btnp(3) then c.col=math.min(n-1,c.col+1)
  elseif btnp(4) then
   local handIdx=c.col+1
   local picked=G.hand[1][handIdx]
   if picked then
    local cb=G.discardSel.onPick
    G.discardSel=nil; G.mode="free"
    cb(handIdx)
   end
  end
  return
 end

 -- S/T target picker (e.g. MST): cycles through every S/T card and field
 -- spell on the board. Any arrow key steps the selection; cursor snaps to it.
 if G.mode=="sel_st_target" and G.stTargetSel then
  local sts=G.stTargetSel
  local tgts=mstTargets(sts.source)
  if #tgts==0 then G.stTargetSel=nil; G.mode="free"; return end
  local idx=sts.idx or 1
  if idx>#tgts then idx=1 end
  if btnp(2) or btnp(0) then idx=((idx-2)%#tgts)+1
  elseif btnp(3) or btnp(1) then idx=(idx%#tgts)+1
  elseif btnp(4) then
   local t=tgts[idx]
   local cb=sts.onPick
   G.stTargetSel=nil; G.mode="free"
   cb(t.side,t.kind,t.di)
   return
  end
  sts.idx=idx
  local t=tgts[idx]
  G.cur={side=t.side,row=t.row,col=t.vcol}
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
   p.tgtIdx=4-c.col
   -- Gravekeeper's Assailant: while Necrovalley is on the field, offer its
   -- battle-position-change effect before the attack resolves.
   if p.attacker and p.attacker.effect=="gkassailant"
      and necrovalleyActive() and hasMonsters(2) then
    G.mode="free"
    G.menu={open=true,sel=1,forced=true,items={
     {"EFFECT","assail_yes"},
     {"NORMALL","assail_no"},
    }}
   else
    confirmPlayerAttack()
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
    if not found and tributeTotal(p)<p.tribNeeded then
     table.insert(p.tributes,col)
    end
    if tributeTotal(p)>=p.tribNeeded then
     local tribs={}
     for _,v in ipairs(p.tributes) do table.insert(tribs,v) end
     local zones={}
     for _,tcol in ipairs(tribs) do
      table.insert(zones,{x=COL[tcol],y=PY_M})
     end
     animTribute(zones,function()
      -- Track GK tribute data for Gravekeeper's Oracle
      if p.card.effect=="gkoracle" then
       local gkN,lvlS=0,0
       for _,tcol in ipairs(tribs) do
        local m=G.mon[1][tcol]
        if m then lvlS=lvlS+(m.lvl or 0); if isGravekeeper(m) then gkN=gkN+1 end end
       end
       G.oracleTribData={gkCount=gkN,lvlSum=lvlS}
      end
      for _,tcol in ipairs(tribs) do
       fireMonHook(G.mon[1][tcol],"onTributed",1)
       sendMonsterToGY(1,tcol,"tribute")
      end
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
    if not card.facedown then fireSummonHook(card,1) end
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
     local b=behaviorOf(card)
     if b and b.activate then
      b.activate{col=col,card=card,zone="st",plr=1}
     else
      animSpellActivation(col,PY_S,card,1)
     end
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

 -- Monster destroy picker (Man-Eater Bug = any; Thousand Knives = side 2 only)
 if G.mode=="sel_destroy" then
  local ds=G.destroySel
  if btnp(2) then c.col=math.max(1,c.col-1)
  elseif btnp(3) then c.col=math.min(3,c.col+1)
  elseif btnp(0) then if c.side==1 and ds.side~=1 then c.side=2 end
  elseif btnp(1) then if c.side==2 and ds.side~=2 then c.side=1 end
  elseif btnp(4) then
   local ti=(c.side==2) and (4-c.col) or c.col
   local grid=(c.side==1) and G.mon[1] or G.mon[2]
   if ti>=1 and ti<=3 and grid[ti] and (not ds.side or ds.side==c.side) then
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
  elseif btnp(5) and not G.menu.forced then  -- B: cancel (forced menus can't)
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
   tickSwords()
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
   animSpellActivationCustom(stCol,(plr==1) and PY_S or OY_S,card,plr,resolveFn)
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
  animSpellActivationCustom(col,(plr==1) and PY_S or OY_S,card,plr,resolveFn)
 end
end

-- Call of the Haunted: pick a GY monster, then push the chain link with the
-- pre-captured target index. Picking happens at activation time (TCG-correct)
-- so chain resolution stays synchronous (no UI mid-resolve).
function pickCallHauntedTargetThenActivate(col,card,ctx)
 local items={}
 for i,c in ipairs(G.gy[1]) do
  if c.cat=="monster" then
   table.insert(items,{deckIdx=i,name=c.name,atk=c.atk,def=c.def,lvl=c.lvl,desc=c.desc})
  end
 end
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
 local items={}
 for p=1,2 do
  for i,c in ipairs(G.gy[p]) do
   if c.cat=="monster" then
    table.insert(items,{gyPlr=p,gyIdx=i,name=c.name,atk=c.atk,def=c.def,lvl=c.lvl,desc=c.desc})
   end
  end
 end
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
 local zx=(plr==1) and COL[col] or COL[4-col]
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
   -- Track GK tribute data for Gravekeeper's Oracle
   if card.effect=="gkoracle" then
    local gkN,lvlS=0,0
    for _,tcol in ipairs(tribs) do
     local m=G.mon[2][tcol]
     if m then lvlS=lvlS+(m.lvl or 0); if isGravekeeper(m) then gkN=gkN+1 end end
    end
    G.oracleTribData={gkCount=gkN,lvlSum=lvlS}
   end
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
 if swordsBlocks(2) then return false end
 for i=G.aiBattleIdx,3 do
  local att=G.mon[2][i]
  if att and att.pos==1 and not att.facedown and not att.attacked then
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
  tickSwords()
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
  if     TITLE_SEL==1 then SCENE="oppselect"
  elseif TITLE_SEL==2 then startDeckBuild()
  end
  -- OPTIONS: placeholder
 elseif btnp(5) then
  SCENE="title"
 end
end

-- ============================================================
-- OPPONENT SELECT
-- ============================================================
function drawOppSelect()
 -- Background: navy playmat + dither + gold border (matches menu)
 cls(CMAT)
 for y=0,SH-1,4 do for x=0,SW-1,4 do pix(x,y,CB) end end
 rectb(0,0,SW,SH,9)

 local t="CHOOSE YOUR OPPONENT"
 print(t,(SW-#t*6)//2+1,13,CB,true,1,false)
 print(t,(SW-#t*6)//2,  12,CCR,true,1,false)

 -- Framed 32x32 portraits in a centered row.
 local ps,pad=32,4          -- portrait size, inner padding
 local bw=ps+pad*2          -- box size (40)
 local gap=12
 local totalW=#OPPONENTS*bw+(#OPPONENTS-1)*gap
 local x0=(SW-totalW)//2
 local cy=46

 for i,opp in ipairs(OPPONENTS) do
  local x=x0+(i-1)*(bw+gap)
  local sel=(i==OPP_SEL)
  -- Picture frame: colored outer border + black mat
  rect(x,cy,bw,bw, sel and 9 or CD)
  rect(x+1,cy+1,bw-2,bw-2,CB)
  spr(opp.spr,x+pad,cy+pad,-1,1,0,0,4,4)
  rectb(x+pad-1,cy+pad-1,ps+2,ps+2, sel and CCR or CMAT)
  -- Pulsing chevrons flank the selected portrait
  if sel and (G.tick//15)%2==0 then
   print(">",x-7,    cy+bw//2-3,10,true,1,false)
   print("<",x+bw+2, cy+bw//2-3,10,true,1,false)
  end
  -- Name below the frame (with shadow)
  local nx=x+(bw-#opp.name*6)//2
  print(opp.name,nx+1,cy+bw+5,CB,true,1,false)
  print(opp.name,nx,  cy+bw+4,sel and CCR or CT,true,1,false)
 end

 local h="ARROWS: select   A: duel   B: back"
 print(h,(SW-#h*4)//2,SH-7,CD,true,1,true)
end

function drawTrans()
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
end

function handleOppSelectInput()
 if btnp(0) or btnp(2) then OPP_SEL=math.max(1,OPP_SEL-1)
 elseif btnp(1) or btnp(3) then OPP_SEL=math.min(#OPPONENTS,OPP_SEL+1)
 elseif btnp(4) then startOppConfirm()
 elseif btnp(5) then SCENE="menu" end
end

-- ============================================================
-- OPPONENT CONFIRM DIALOG
-- ============================================================
CONFIRM_DUR=300  -- frames before the dialog auto-advances to RPS (~5s)

function startOppConfirm()
 local opp=OPPONENTS[OPP_SEL]
 CONFIRM={timer=0, quote=opp.quotes[math.random(#opp.quotes)]}
 SCENE="oppconfirm"
end

function tickOppConfirm()
 CONFIRM.timer=CONFIRM.timer+1
 if CONFIRM.timer>=CONFIRM_DUR then startGame() end
end

function handleOppConfirmInput()
 if btnp(4) then startGame()
 elseif btnp(5) then SCENE="oppselect" end
end

function drawOppConfirm()
 local opp=OPPONENTS[OPP_SEL]
 -- Background (matches opponent select)
 cls(CMAT)
 for y=0,SH-1,4 do for x=0,SW-1,4 do pix(x,y,CB) end end
 rectb(0,0,SW,SH,9)

 -- Centered dialog box: gold border, black interior
 local bw,bh=184,82
 local bx,by=(SW-bw)//2,(SH-bh)//2
 rect(bx,by,bw,bh,9)
 rect(bx+2,by+2,bw-4,bh-4,CB)

 -- Framed 32x32 portrait, top-left of box
 local px,py=bx+8,by+8
 spr(opp.spr,px,py,-1,1,0,0,4,4)
 rectb(px-1,py-1,34,34,CCR)

 -- Opponent name + quote, to the right of the portrait
 local tx=px+40
 local tw=bx+bw-tx-8
 print(opp.name,tx,py+1,CCR,true,1,true)
 printWrap(CONFIRM.quote,tx,py+11,tw,CT,by+bh-18)

 -- Slowly flashing call to action, centered in the lower band
 if (G.tick//30)%2==0 then
  local d="It's time to duel!"
  local dw=print(d,0,-20,0,false,1,false)  -- measure proportional width offscreen
  print(d,bx+(bw-dw)//2,by+bh-26,10,false,1,false)
 end

 -- Controls hint
 local h="A: duel   B: cancel"
 print(h,(SW-#h*4)//2,by+bh-10,CD,true,1,true)
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

-- pmem layout: MAX_DECK card IDs at 6 bits each (so up to 63 unique cards),
-- packed 5 IDs per 32-bit slot across 4 slots (5*4 = 20 = MAX_DECK).
function dbLoad()
 DB.deck={}
 for slot=0,3 do
  local v=pmem(slot)
  for b=0,4 do
   local num=(v>>(b*6))&0x3f
   local slug=CARD_ORDER[num]
   if slug then table.insert(DB.deck,slug) end
  end
 end
end

function dbSave()
 local nums={}
 for i=1,MAX_DECK do nums[i]=CARD_NUM[DB.deck[i]] or 0 end
 for slot=0,3 do
  local v=0
  for b=0,4 do
   local idx=slot*5+b+1
   if idx<=MAX_DECK then v=v|(nums[idx]<<(b*6)) end
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
  if ci>#CARD_ORDER then break end
  local slug=CARD_ORDER[ci]
  local cd=CARDS[slug]
  local iy=9+(i-1)*DB_LIST_RH
  local isSel=(DB.cur.panel==2 and DB.listSel==ci)
  if isSel then rect(DB_LX,iy,SW-DB_LX,DB_LIST_RH-1,CHL) end
  if cd.spr then spr(cd.spr,lx,iy,cd.bg,1,0,0,1,1) end
  local nm=#cd.name>18 and string.sub(cd.name,1,18)..".." or cd.name
  print(nm,lx+9,iy+1,isSel and CB or CT,true,1,false)
  local cnt=dbCountInDeck(slug)
  local cc=(cnt>=MAX_COPIES) and CAT or (cnt>0 and CCR or CD)
  print("x"..cnt,SW-18,iy+1,cc,true,1,false)
 end
 -- Scrollbar (only if list overflows visible area)
 if #CARD_ORDER>DB_LIST_VIS then
  local bh=DB_LIST_VIS*DB_LIST_RH
  local pct=DB.listScr/math.max(1,#CARD_ORDER-DB_LIST_VIS)
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
   DB.listSel=math.min(#CARD_ORDER,DB.listSel+1)
   if DB.listSel>DB.listScr+DB_LIST_VIS then DB.listScr=DB.listScr+1 end
  elseif btnp(2) then c.panel=1
  elseif btnp(4) then
   DB.menu={sel=1,ctx={type="list",cardId=CARD_ORDER[DB.listSel]},items={
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
 local opp=OPPONENTS[OPP_SEL]
 G.oppName=opp.name
 local plrDeck=#DB.deck>0 and DB.deck or DECK1
 for i,id in ipairs(plrDeck) do G.deck[1][i]=id end
 for i,id in ipairs(opp.deck) do G.deck[2][i]=id end
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
 if SCENE=="oppselect" then
  handleOppSelectInput()
  drawOppSelect()
  return
 end
 if SCENE=="oppconfirm" then
  handleOppConfirmInput()
  if SCENE=="oppconfirm" then tickOppConfirm() end
  if SCENE=="oppconfirm" then drawOppConfirm() end
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
  drawTrans()
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
 drawChain()
 drawModeBanner()
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
-- 128:0006000000000606600000000060600000060060aa0000008aa0000008aa0000
-- 129:600000000060000a0000000a0600000a0000000aa00a000aaa0aa00aaa0aaa0a
-- 130:a7006006a7000000a7000600a7000600a7000066870079008700aa0a870aa9aa
-- 131:000006006066000000000660006000000000007a90007aa0a07aa8059aaa7000
-- 132:000000000000aaaa0000aaaa00008aaa00a80aaa00aaaaaa00aaaaaa00aaaaaa
-- 133:0000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-- 134:000000000aaaaa00aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
-- 135:00000000a0000000aa000000aaaa0000aaa80000aaaa0000aaaaa000aaaaa000
-- 136:0000000000000000000000000000000000000000000000000000000800000002
-- 137:0000000000000000000222200022222200222222022222222222222222222222
-- 138:0000000000000000022920002222220022222900222222902222229929999989
-- 139:0000000000000000000000000000000000000000000000000000000090000000
-- 140:0000000ff000000ff000000ffff0000f7ffff00f77ffffff077ff7ff07777f7f
-- 141:f77770fff7770fffff777fffff770fff7f770ff77ff77ff7fff7ff77fff7ff77
-- 142:777ffff777708ff7777787777777777777770770f777000ff77770fff77777ff
-- 143:00000f000000f700000ff70000fff700ffff7700f7ff7700fff77700fff77000
-- 144:0078a00906078a090000780a0560070a600000770007aa7a0aaaa7a7a788709a
-- 145:aa07aaaaaa087aa00a0777aa0a07777aa7aa70007aaa7899aaa70899aa088999
-- 146:877aaa0a87aaaa0a87a08a0a7a078a0aa0008a0a99978aa099978aaa99987a99
-- 147:9aa7000098000600a0006000a0060066aa000000009aaa00aaaa08a0aaa7a078
-- 148:00aaaaaa00aaaaaa00aaaaaa0aaaaaaa0aaaaaaa0aaa8aaaaaa8aaaaaaa888a8
-- 149:aaaaaaaaaaaaaa8aaa8aaa88aa8aaaa8a888a8a8a8a8a88aa8a88a88a8a88888
-- 150:aaaaaaaaaaaaaaaaaa88aaaa8aa88aaa888a888a888888888888888882200008
-- 151:aaaaaa00aaaaaa00aaaaaa0088aaaa00a88888a08a88888a8a88888888a88880
-- 152:0000008200000022000008220000082200008822000888820000088200000888
-- 153:2222922922222222822222828282222282828222880828228882822280280228
-- 154:2992999922222228222282282222828222228282222288828222888282228282
-- 155:9200000022000000229000008280000082880000828980002820000028200000
-- 156:007777ff00777f70ff0777f0f7f777707ff777777777077777777770007700ff
-- 157:ff70f077f7ff7f77f77f7f77f70fff77f0ffff77ffffff07fffff707fff7f7f7
-- 158:f70777f7f7f7777ff7ff777f77ff877777ffff0770fffff7707ffff07f7f7fff
-- 159:f77770077f77070f77777fff777077f77707f777777f777770777777ff077770
-- 160:7700907a0000907a6000907a6600007a0066007a0006607a0000607a00600080
-- 161:a077f999806f00f980606f8980f66f9980000099809999998099999980999999
-- 162:999907009970f66f900606ff990f66f0990000099999999f7099999779999970
-- 163:000787a0008f078a708f00607087066000706600876600000660000066000000
-- 164:a0a888a8a0a888a8a0a888a8a0a888a800a88888000a8888000080880000a088
-- 165:a88a8888a88a8888a8800988a8808f9988a8f99988889909888a999088880999
-- 166:88008f2880f88f2882ff99228999999299999992999999929999992099099922
-- 167:20aa8888220888882288a8082088a80a02888800228888002200088022004880
-- 168:0000080800000029000000290000000900000002000000000000000000000000
-- 169:808088200008088890f400089099299890999900229f090980ff099907ff0999
-- 170:888888028888800088004f090992290999999929099999900999908099999800
-- 171:880000009800000090000000900000000000000000000000000f000007ff0000
-- 172:fffffffffff0f0f770ff0f7f0f70f7f0f70f0f7f07f07700f00070000f000f00
-- 173:ffff8777ff7f0077ff7008200700828207880aaa870f002a000fdf8828228888
-- 174:77707f7f7700fff70280ff70282880ffaaa088f7a20070f888fdf0f088882882
-- 175:ff7fff00f0ff7f007f7f777f77f7f00700700f00f77770ff00770f007077f000
-- 176:0000608000000080000000a0000050a7000000770000000f0000000f00000050
-- 177:80099997a000f999a0008f99a0069809a077ff70007050f770ff007570075075
-- 178:77999700999970009990006697080607077f0777770557775555700755557077
-- 179:0066000066000000000000007f750000f0500000f5500000f550007005000000
-- 180:00000a0800000000000000000000000000000000000000000000000000000000
-- 181:000000990000a000000000000000004400000044000044440000440400044444
-- 182:9999920299999022499922044400824444402244444022444400924440ffff44
-- 183:20444a8044444080444444a0444444404444404444444444044444f444444444
-- 184:0000000f000000f7000000770000000700000007000000770000000700000ff0
-- 185:f7ff099077ff0999707f0099707f0209707f0000777ff0007777f00000000fff
-- 186:099908009990807f9990877f9920077f00000777000007770f000777ff000700
-- 187:7ff00000fff00000fff00000fff00000fff000007f00000077000070000fff07
-- 188:00ff7777077777070000777700ff7707000770770000000000000000000000dd
-- 189:02022222700222227a002222707702227a0788820a0f0220005f5000055f5ddd
-- 190:0222202702228007222200a722207707288077a00220f00700007550dd507550
-- 191:777777ff777000007007000077000000777700000000000000000000d0000000
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
-- 068:55dd5555555dd55555555d57555dd557555d55500055d5570075d55000075551
-- 069:5777755df77777557888f7508888778587087887088870778888771107787111
-- 070:441614641116666c1116666c1116644c114d465c416664fc1111445c11144444
-- 071:cc05c411cdd00cc50ddd0cc1000000c8c00000c540000cc1482004c542224241
-- 072:66ddd6666dddd663dddd66e3dddd60e3dddd60e36dddde776666631766666033
-- 073:66d66ddd36dddddd3e6ddddd3e06dddd3e06dddd77edd6dd713d66d633366666
-- 074:000005770000dd5507772d0007750220075009930705303d002200300500303d
-- 075:757000000750000007ff3300037f00000077f0000277f2000277f2000277f200
-- 076:33b33333b3333d3033333dd133a0dd003adadd0a3dad0990ddf0f114ddf0114f
-- 077:3333b333833d33b310dd33331a0dd33baa090d33a0990dd34411dd0d4f41100d
-- 078:88222822882222f78222227088222778882228098820000382200000820b0000
-- 079:224444f477ffffff90ff4fff984444449244f444024f444402444343b0444333
-- 080:5d5555b55d555559ddd5dd94dddddd11dddddd11dddd9911ddb99199ddb9bddd
-- 081:595bbbdd5995bbdd19599ddd9bbbdddddb999dddd999999d99dddddd9fdddddd
-- 082:4444f79944444f99444449954444795944448555444405554440555544455554
-- 083:5955555455555544555544440955444455955544555555549955555544455555
-- 084:7707557100705510000d008100dd888150080808500888885808888808008880
-- 085:7887711877771118077111801771188807188808878888880888880800008888
-- 086:1f4544241cc502224cc00022cc000005c5000dd0cc00ddd04c50d05c14cccccc
-- 087:24242451544241114484ddd144661111c4d61114c4641d11c466681144646141
-- 088:d6666ae3dd6663a0dd66673ad666a37ad6062a0a737773a27337330a7733770a
-- 089:3ea666660a36666da37666dda73a66dda0a260dd2a377737a0337337a0773377
-- 090:022022300220929d00002200033355200350033303500ddd00d300d3003d3370
-- 091:0335502023d3f0022227f3339227f553922f00303d700000330000003d330000
-- 092:0302014433f331a03333011a3333aa1133d3daa3b3dddd03330dd0333b333333
-- 093:14411033aaa10ff3aa113f33111a33333a003d3b30dddd3333ddddb3b333b333
-- 094:8000000b880b00b088b000008b0000b000000000000000b00000000000000000
-- 095:0044333300444484004ff448004ff244004dd214004fdf12002dd211002dd211
-- 096:5555555d555555d7555555095555fd0055500dd755dfddd155d000775dfd7700
-- 097:d555555570d5555d7755d77707007077707770dd077707dd707777707777077d
-- 098:55555550555e5eb0ee55e50955555b09ee5b77a955b7777a5b77077750770079
-- 099:055555550be555e590055e55995555550a77b555a7777b55777007b59770770e
-- 100:00767677076060677760000676020200760000007760000a7776aaa07776f2f0
-- 101:7770000077770000777777006777777006676677000600770000006700000006
-- 102:dd5555aad54445a855444589554c488858888899583302885833c02455838080
-- 103:aa5555dd8a51115d98511155888121559988888588f82aa5420a82a522008855
-- 104:555555555555555a555555af555555a0fffff5f9ff99fafa57979fff9fff7aaa
-- 105:55555555a5555cc5ff55c55c0a55c55c9a555cc59df5aaaadd9f5aa5aa7a55a5
-- 112:5df070715020070709dd7077d0dd0777ddd77077007700770770177070017701
-- 113:77001117770207dd07909ddd091010dd9010d00d011ddddd101ddddd000ddddd
-- 114:5b772299557707d055b50777e5e507de555507775e5507d7e5557d7755557777
-- 115:992277b57d7077b577705b55ed70e5e57770555e7d70575577d77775777755e5
-- 116:77760f0007760000007600000077600000776000077760000777600000777666
-- 117:00000006000000670000a0670000aa7700000677000006700000670066667700
-- 118:55588880558a8000880070008999000a89990afa589904425890a200d8902a22
-- 119:0028855520020855a4a00888aa029998a0a2999800709985777a09850008098d
-- 120:5fff0a7ff5fff9975ff590fa555f9ffa5555f7ff555fff7f55affff7550aa0ff
-- 121:ffaff5a5017ffa55ff0ffa55afaffa55a0a55a557fff5555ffff5555fffaa555
-- 160:0077999200779992007799920077999200778992000799920077999800779980
-- 161:22222977222229702222297022222090222222972aa2009700a2299700220997
-- 162:555555555555500055550999555509995555097755550999dddd0977d5d50999
-- 163:55555555055555559005555599905555999055559790555599905d5d9790d5d5
-- 164:999992922922229922929292222fe2992ffeee999ff6e6f529e9005029299955
-- 165:22999299ff99929922f29929ffff992955555599540555595555055955555505
-- 176:0077999907777999007778997077708877888888777788880077770800077777
-- 177:2222299722222897902029908888997788889977888899078888897088888770
-- 178:5d5d0979dddd0999dddd09792ddd09992aaa099922a209992222099988888888
-- 179:799055559790dddd999adddd99777ddd99777222997722229997788888008888
-- 180:292111559919111592111110222211ff22922fff99999f229922999299222922
-- 181:55545555555555595450509945050f99fffff222ffff92292992999999922999
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
-- 224:cf0c444c40f440cc00ffccc44004c0f40040f4f00400cf0000004ff0404c40f4
-- 225:00000c00cc44c40c4400cc44444440000004c004444cc440000004c400000004
-- 226:00dddd0d00dddd0d000ddd0d000ddddd0000d00d0000d00d0000d00d000d000d
-- 227:dd0ddd00dddddd00d0ddd000d0ddd000d00dd000d00dd000000d0000000d0000
-- 228:d56778dd0556828d0ddd682d000d66dd5006dddd05675ddd56667f5d56666577
-- 229:7ddddd00df0dd00050770000500ff000dd007780dd000828dd000dd280500d00
-- 230:ddedddeededddedddeddedfddeddeddf0e00e00f0ecce0f00e0cce000ecc0cee
-- 231:eedddeddddedddeddfdeddedfddeddedf00e00e00f0ecce000ecc0e0eec0cce0
-- 232:8888808800005555855883335555a3a350853a3a580555555805303358533003
-- 233:800880085555880833380808a3a308803a3a0088555550003303588830033588
-- 234:cf4fc4cc4cf4ccccfcccccc44fcccf4f4ccfcc4f4ccffc444ffcccf4cff44444
-- 235:fcccc44cccfcc4c44cfccccff4cccfc4f4ccfccf44cfcfcc4fffccfc44444cc4
-- 236:0401000004400040415544552d5445d49d445d4d1d45d4d54245d4d5024554d4
-- 237:2222205422511155ddd11100444d2942ddd25214555d259044450490dd440410
-- 238:9989999998999999899999989999998999999899999989999998990899899981
-- 239:977999998977999899700989991111779111118911111887f1f180091f180099
-- 240:00cc0cf0004040f40040c0f0404000ff04004000c0000000cc00000004c4cccc
-- 241:444400044400000c044004c0400000400000440cf4004ccc004cc404cccc0040
-- 242:0000d0000000d00d5555bb3d553311115b311188553b31115555533355555555
-- 243:d000d000000d000033bd5555111d33558811b3b51113b3553335555555555555
-- 244:dd66ddd5d0ddddd0d0ddd550077f077f5dd077776ddddddddddddddddddddddd
-- 245:728000000020000000000000000080007777900007770220d0009080ddd00000
-- 246:00c0000c0cce00cc0c00eeeccc00000cc00f000cc000000c0000000c0000000c
-- 247:c0000c00cc00ecc0ceee00c0c00000ccc000000cc000f000c0000000c0000000
-- 248:8535333355353311853351998833331988553331800355338885335300855555
-- 249:3333530811335308991533089133338813335500335530803533580055555008
-- 250:4cc44ff4cfccfff44cfcfcf4fccfccf44cccccc4fc4fcf44c4f4cfcc44fcfcfc
-- 251:4ff44ffc4ffffffc4fcffcc44cccffcc4ffcccfc44cfcc4fcc4ccfc44c4cfcfc
-- 252:211124dd92209544990205559929004dd4920104dd9910002222200042205051
-- 253:d45424494d445009dd4041004400400050041024004440142200554520dd4055
-- 254:9899011189911111991111119981111877288880792000009982078998999799
-- 255:1f80789918070999877099997789999878999989099998999999899999989999
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
