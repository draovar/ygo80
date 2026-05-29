-- [ygo_layout] YGO80 module -- loaded via require() from ygo80.lua

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
CLEG = 7   -- control-hint / legend text                (grey)
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

