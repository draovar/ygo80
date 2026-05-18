-- [ygo_render] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- DRAW PRIMITIVES
-- ============================================================

-- Generic zone box (any size); optional cnt draws a number below the label
function drawZone(x,y,w,h,c,lbl,cnt)
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
function drawCardAtk(x,y,card,zc)
 local fc=card.effect and CME or CCA
 rect(x,y,ZW_MAIN,ZH,zc)
 rect(x+2,y+1,ZW_MAIN-4,ZH-2,fc)
 if card.spr then spr(card.spr,x+3,y+2,card.bg,1,0,0,2,2) end
 clip(x+1,y,ZW_MAIN-2,ZH)
 spr(SPR_FRAME,x+1,y,15,1,0,0,3,3)
 clip()
end

-- Defense position: card sideways, landscape 22x20 inside 22x22 (1px top/bottom margin)
function drawCardDef(x,y,card,zc)
 local fc=card.effect and CME or CCA
 rect(x,y,ZW_MAIN,ZH,zc)
 rect(x+1,y+2,ZW_MAIN-2,ZH-4,fc)
 if card.spr then spr(card.spr,x+4,y+3,card.bg,1,0,1,2,2) end
 clip(x,y+1,ZW_MAIN,ZH-2)
 spr(SPR_FRAME,x-2,y+1,15,1,0,1,3,3)
 clip()
end

-- Spell/trap face-up: colored tint + sprite frame
function drawCardSpell(x,y,card,zc)
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
function drawCardBack(x,y,w,h,rot,fl,syOff)
 rot=rot or 0; fl=fl or 0; syOff=syOff or 0
 local sx=x+(w-20)//2 - (rot==1 and 3 or 0)
 local sy=y + syOff
 clip(x,y,w,h)
 spr(SPR_CARDBACK,sx,sy,15,1,fl,rot,3,3)
 clip()
end

-- Player hand card (HW x PHH = 20x22, face-up)
function drawHandPlr(x,y,card)
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
function drawDotBorder(x,y,w,h,col)
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
function drawFieldSlot(x,y,card,facedown,zoneColor)
 if not card then
  drawZone(x,y,ZW_MAIN,ZH,zoneColor)
 elseif facedown then
  if card.pos==2 then
   rect(x,y,ZW_MAIN,ZH,zoneColor)
   drawCardBack(x,y+1,ZW_MAIN,ZH-2,1)
  else
   drawCardBack(x,y,ZW_MAIN,ZH)
  end
 elseif card.cat=="spell" or card.cat=="trap" then
  drawCardSpell(x,y,card,zoneColor)
 elseif card.pos==2 then
  drawCardDef(x,y,card,zoneColor)
 else
  drawCardAtk(x,y,card,zoneColor)
 end
end

-- Field-spell zone (ZW_SPEC wide): empty shows the "FS" label, occupied shows
-- the field spell card.
function drawFieldSpellSlot(x,y,card)
 if not card then
  drawZone(x,y,ZW_SPEC,ZH,CFS,"FS")
 elseif card.facedown then
  rect(x,y,ZW_SPEC,ZH,CFS)
  drawCardBack(x,y+1,ZW_SPEC,ZH-2,0)
  rectb(x,y,ZW_SPEC,ZH,CD)
 else
  rect(x,y,ZW_SPEC,ZH,CFS)
  rect(x+2,y+1,ZW_SPEC-4,ZH-2,CSP)
  if card.spr then spr(card.spr,x+2,y+2,card.bg,1,0,0,2,2) end
  rectb(x,y,ZW_SPEC,ZH,CD)
 end
end

-- Cursor highlight (dotted red border outside)
function drawCursorRect(x,y,w,h,col)
 drawDotBorder(x-1,y-1,w+2,h+2,col)
end

-- LP bar (filled left-to-right)
function drawLPBar(x,y,w,lp)
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
  drawCardBack(handX(oh,i),OY_H,HW,OHH,0,0,-11)
 end

 drawZone(COL[0],OY_S,ZW_SPEC,ZH,CDK,"DK",#G.deck[2])
 for c=1,3 do
  local card=G.st[2][4-c]
  drawFieldSlot(COL[c],OY_S,card,not card or card.facedown,COZ)
  if card and card.swordsCounter and not card.facedown then
   print(tostring(card.swordsCounter),COL[c]+ZW_MAIN-7,OY_S+2,CCR,true,1,false)
  end
 end
 drawZone(COL[4],OY_S,ZW_SPEC,ZH,CED,"ED")

 drawZone(COL[0],OY_M,ZW_SPEC,ZH,CGY,"GY",#G.gy[2])
 for c=1,3 do
  local card=G.mon[2][4-c]
  drawFieldSlot(COL[c],OY_M,card,card and card.facedown,COZ)
  if (G.mode=="sel_atk" or (G.mode=="sel_destroy" and (not G.destroySel.side or G.destroySel.side==2))) and card then drawDotBorder(COL[c],OY_M,ZW_MAIN,ZH) end
  if G.mode=="sel_equip" and card and not card.facedown then drawDotBorder(COL[c],OY_M,ZW_MAIN,ZH,CSP) end
  if G.battleAnim and G.battleAnim.atkCol and (4-c)==G.battleAnim.atkCol then
   drawDotBorder(COL[c],OY_M,ZW_MAIN,ZH,CAT)
  end
 end
 drawFieldSpellSlot(COL[4],OY_M,G.fs[2])
end

-- Player (divider → bottom):
--   PY_M: [FS][M1][M2][M3][GY]
--   PY_S: [ED][S1][S2][S3][DK]
--   PY_H: face-up hand cards (centered)
function drawPlrSide()
 drawFieldSpellSlot(COL[0],PY_M,G.fs[1])
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
  drawFieldSlot(COL[c],PY_M,card,card and card.facedown,zc)
  if G.mode=="sel_tribute" and G.mon[1][c] and not isTrib then
   drawDotBorder(COL[c],PY_M,ZW_MAIN,ZH)
  elseif G.mode=="sel_mon" and not G.mon[1][c] then
   drawDotBorder(COL[c],PY_M,ZW_MAIN,ZH)
  elseif G.mode=="sel_destroy" and G.mon[1][c] and (not G.destroySel.side or G.destroySel.side==1) then
   drawDotBorder(COL[c],PY_M,ZW_MAIN,ZH)
  elseif G.mode=="sel_atk" and G.pending and c==G.pending.atkCol then
   drawDotBorder(COL[c],PY_M,ZW_MAIN,ZH,CCR)
  elseif G.mode=="sel_equip" and card and not card.facedown then
   drawDotBorder(COL[c],PY_M,ZW_MAIN,ZH,CSP)
  end
  if G.battleAnim and G.battleAnim.tgtCol==c then
   drawDotBorder(COL[c],PY_M,ZW_MAIN,ZH,CAT)
  end
 end
 drawZone(COL[4],PY_M,ZW_SPEC,ZH,CGY,"GY",#G.gy[1])

 drawZone(COL[0],PY_S,ZW_SPEC,ZH,CED,"ED")
 for c=1,3 do
  local card=G.st[1][c]
  drawFieldSlot(COL[c],PY_S,card,card and card.facedown,CZ)
  if card and card.swordsCounter and not card.facedown then
   print(tostring(card.swordsCounter),COL[c]+ZW_MAIN-7,PY_S+2,CCR,true,1,false)
  end
  if G.mode=="sel_st" and not card then drawDotBorder(COL[c],PY_S,ZW_MAIN,ZH) end
  if G.mode=="opp_trap_select" and G.trapSelect and trapCanRespond(card,G.trapSelect.event,G.trapSelect.ctx,1) then
   drawDotBorder(COL[c],PY_S,ZW_MAIN,ZH)
  end
 end
 drawZone(COL[4],PY_S,ZW_SPEC,ZH,CDK,"DK",#G.deck[1])

 local ph=math.min(#G.hand[1],MAX_HAND)
 for i=0,ph-1 do
  drawHandPlr(handX(ph,i),PY_H,G.hand[1][i+1])
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
 drawCursorRect(cx,cy,cw,ch,curCol)
end

-- ============================================================
-- INFO PANEL (x=0..PANEL_W-1)
-- ============================================================
function drawPanel()
 line(SEP_X,0,SEP_X,SH-1,CD)
 local pw=PANEL_W-4

 -- Opponent LP
 drawLPBar(2,0,pw,G.dispLp[2])

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
 drawLPBar(2,SH-9,pw,G.dispLp[1])
end

