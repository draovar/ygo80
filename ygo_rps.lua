-- [ygo_rps] YGO80 module -- loaded via require() from ygo80.lua

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
    music(0,-1,-1,true,true)
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
  drawCardBack(cx0+i*(HW+HG), OY_H, HW, OHH, 0, 0, -11)
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
  drawCardBack(rx,ly,HW,PHH)
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

