-- [ygo_state] YGO80 module -- loaded via require() from ygo80.lua

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
  triggerQueue=nil,  -- queued onDestroy / onSummon triggers, drained by flushTriggers()
  statsGen=1,        -- incremented by bumpStats() on any field change; invalidates per-card stat caches
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
 local sx,sy=zoneXY(p,"dk")
 local ex=handX(n,n-1)
 local _,ey=zoneXY(p,"hand")
 addAnim(18,function(t,f)
  local prog=(f-t)/f
  local cx=math.floor(sx+(ex-sx)*prog)
  local cy=math.floor(sy+(ey-sy)*prog)
  drawCardBack(cx,cy,HW,PHH)
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
 local zx,zy=zoneXY(plr,"st",col)
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
-- CARD MOVEMENT  (single source of truth for moving cards)
-- ============================================================
-- All field/hand -> GY movement must go through these helpers so that
-- destroyFlash fires consistently, onDestroy triggers are queued (via
-- queueTrigger, in ygo_chain), and linkedTrap/linkedMon back-pointers are
-- cleared. `reason` is a free-form tag: "battle", "effect", "cost",
-- "tribute", "rule" (self-destruct). Only DESTROY_REASONS tags fire onDestroy
-- triggers (PSCT "by battle/effect" vs non-destruction "tribute"/"cost").

function sendMonsterToGY(plr,col,reason)
 local m=G.mon[plr][col]
 if not m then return nil end
 G.mon[plr][col]=nil
 bumpStats()
 table.insert(G.gy[plr],m)
 if DESTROY_REASONS[reason] then
  local zx,zy=monZoneXY(plr,col)
  destroyFlash(zx,zy)
 end
 -- If this monster was summoned by a linked trap (Call of the Haunted etc.),
 -- destroy that trap too when it leaves the field for any reason. Skipped
 -- while Jinzo is face-up: that trap's continuous effect is negated.
 if m.linkedTrap and not staticActive("blocksTraps") then
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
 bumpStats()
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
 bumpStats()
end

-- Move a player's field spell from the FS zone to their GY (e.g. replaced by
-- a new field spell, or destroyed).
function sendFieldSpellToGY(plr,reason)
 local f=G.fs[plr]
 if not f then return nil end
 G.fs[plr]=nil
 bumpStats()
 table.insert(G.gy[plr],f)
 return f
end

