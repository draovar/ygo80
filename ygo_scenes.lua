-- [ygo_scenes] YGO80 module -- loaded via require() from ygo80.lua

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

