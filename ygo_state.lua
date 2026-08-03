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
  extra={{},{}},  -- Extra Deck per player (populated at startGame; max 4 for now)
  hand={{},{}},
  gy  ={{},{}},
  deck={{},{}},
  cur={side=1,row=1,col=2},
  menu={open=false,items={},sel=1},
  mode="free",
  infoCard=nil,
  infoScroll=0,  -- vertical line offset for the scrollable drawDBInfo description
  nameScroll={card=nil,offset=0,pause=NAME_SCROLL_PAUSE,atEnd=false},
  pending=nil,
  popup=nil,
  normalSummoned=false,
  aiTimer=0,
  aiBattleIdx=1,
  autoTimer=50,
  statsGen=1,        -- incremented by bumpStats() on any field change; invalidates per-card stat caches
 }
 ANIM={}
 procInit()
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
 -- Same footprint + border as the card-info popup / card picker.
 local bx,by,bw,bh=20,10,200,116
 rect(bx,by,bw,bh,CB)
 rectb(bx,by,bw,bh,CD)
 rectb(bx+1,by+1,bw-2,bh-2,CD)

 -- Header: which graveyard + card count
 local title=(gv.plr==1) and "YOUR GRAVEYARD" or "OPP GRAVEYARD"
 print(title,bx+4,by+4,CCR,true,1,false)
 local cnt="("..#gy..")"
 print(cnt,bx+bw-4-#cnt*6,by+4,CT,true,1,false)
 line(bx+2,by+12,bx+bw-3,by+12,CD)

 if #gy==0 then
  print("Empty",bx+(bw-30)//2,by+bh//2-3,CT,true,1,false)
  print("B close",bx+4,by+bh-8,CLEG,true,1,true)
  return
 end

 -- Scrollable list (most-recent on top): number + name (+ ATK or SPELL/TRAP)
 local listX,listY,rowH,nameX,atkX=bx+4,by+15,10,bx+18,bx+bw-52
 local botDiv=by+bh-19
 local maxVis=math.floor((botDiv-listY)/rowH)
 local dispSel=#gy-gv.sel+1
 local scrollTop=math.max(1,math.min(dispSel-maxVis//2,math.max(1,#gy-maxVis+1)))
 for row=1,maxVis do
  local dispIdx=scrollTop+row-1
  if dispIdx>#gy then break end
  local cardIdx=#gy-dispIdx+1
  local card=gy[cardIdx]
  local iy=listY+(row-1)*rowH
  local isSel=(cardIdx==gv.sel)
  if isSel then rect(bx+2,iy-1,bw-4,9,CHL) end
  local tc=isSel and CB or CT
  local dc=isSel and CB or CD
  print(dispIdx..".",listX,iy,dc,true,1,false)
  print(string.sub(card.name or "?",1,card.cat=="monster" and 21 or 24),nameX,iy,tc,true,1,false)
  if card.cat=="spell" then
   print("SPELL",bx+bw-34,iy,isSel and CB or CSP,true,1,false)
  elseif card.cat=="trap" then
   print("TRAP",bx+bw-28,iy,isSel and CB or CTR,true,1,false)
  elseif card.atk then
   print("ATK "..card.atk,atkX,iy,dc,true,1,false)
  end
 end
 -- Scrollbar
 if #gy>maxVis then
  local barH=maxVis*rowH
  local pct=(scrollTop-1)/math.max(1,#gy-maxVis)
  local markY=listY+math.floor(pct*(barH-4))
  rect(bx+bw-4,listY,2,barH,CB); rect(bx+bw-4,markY,2,4,CD)
 end

 -- Bottom: compact stats for the highlighted card (no description; X = info)
 line(bx+2,botDiv,bx+bw-3,botDiv,CD)
 local sel=gy[gv.sel]
 if sel then
  if sel.cat=="monster" then
   print("ATK:"..(sel.atk or 0).."  DEF:"..(sel.def or 0).."  LV:"..(sel.lvl or 0),bx+4,by+bh-16,CT,true,1,false)
  else
   print(((sel.cat or ""):upper()).." - "..((sel.subtype or "normal"):upper()),bx+4,by+bh-16,CT,true,1,false)
  end
 end
 print("UP/DN browse   B close   X info",bx+4,by+bh-8,CLEG,true,1,true)
end

-- Extra-Deck viewer. Same footprint and controls as drawGYView; lists ED
-- cards (all fusion monsters in V1) in natural index order (1..N).
function drawEDView()
 local ev=G.edView
 local ex=G.extra[ev.plr]
 local bx,by,bw,bh=20,10,200,116
 rect(bx,by,bw,bh,CB)
 rectb(bx,by,bw,bh,CD)
 rectb(bx+1,by+1,bw-2,bh-2,CD)

 local title=(ev.plr==1) and "YOUR EXTRA DECK" or "OPP EXTRA DECK"
 print(title,bx+4,by+4,CFU,true,1,false)
 local cnt="("..#ex..")"
 print(cnt,bx+bw-4-#cnt*6,by+4,CT,true,1,false)
 line(bx+2,by+12,bx+bw-3,by+12,CD)

 if #ex==0 then
  print("Empty",bx+(bw-30)//2,by+bh//2-3,CT,true,1,false)
  print("B close",bx+4,by+bh-8,CLEG,true,1,true)
  return
 end

 local listX,listY,rowH,nameX,atkX=bx+4,by+15,10,bx+18,bx+bw-52
 local botDiv=by+bh-19
 local maxVis=math.floor((botDiv-listY)/rowH)
 local scrollTop=math.max(1,math.min(ev.sel-maxVis//2,math.max(1,#ex-maxVis+1)))
 for row=1,maxVis do
  local idx=scrollTop+row-1
  if idx>#ex then break end
  local card=ex[idx]
  local iy=listY+(row-1)*rowH
  local isSel=(idx==ev.sel)
  if isSel then rect(bx+2,iy-1,bw-4,9,CHL) end
  local tc=isSel and CB or CT
  local dc=isSel and CB or CD
  print(idx..".",listX,iy,dc,true,1,false)
  print(string.sub(card.name or "?",1,21),nameX,iy,tc,true,1,false)
  if card.atk then print("ATK "..card.atk,atkX,iy,dc,true,1,false) end
 end
 if #ex>maxVis then
  local barH=maxVis*rowH
  local pct=(scrollTop-1)/math.max(1,#ex-maxVis)
  local markY=listY+math.floor(pct*(barH-4))
  rect(bx+bw-4,listY,2,barH,CB); rect(bx+bw-4,markY,2,4,CD)
 end

 line(bx+2,botDiv,bx+bw-3,botDiv,CD)
 local sel=ex[ev.sel]
 if sel then
  print("ATK:"..(sel.atk or 0).."  DEF:"..(sel.def or 0).."  LV:"..(sel.lvl or 0),bx+4,by+bh-16,CT,true,1,false)
 end
 print("UP/DN browse   B close   X info",bx+4,by+bh-8,CLEG,true,1,true)
end

function drawDeckSelect()
 local ds=G.deckSel
 -- Same footprint + border as the card-info popup (drawDBInfo): a centered
 -- 200x116 box, so the field shows around the edges while picking.
 local bx,by,bw,bh=20,10,200,116
 rect(bx,by,bw,bh,CB)
 rectb(bx,by,bw,bh,CD)
 rectb(bx+1,by+1,bw-2,bh-2,CD)

 -- Header: calling card's name (left) + available count (right)
 print(string.sub(ds.title or "?",1,26),bx+4,by+4,CCR,true,1,false)
 local cnt="("..#ds.items..")"
 print(cnt,bx+bw-4-#cnt*6,by+4,CT,true,1,false)
 line(bx+2,by+12,bx+bw-3,by+12,CD)

 -- Scrollable list: number + name (+ right-aligned ATK)
 local listX,listY,rowH,nameX,atkX=bx+4,by+15,10,bx+18,bx+bw-52
 local botDiv=by+bh-19
 local maxVis=math.floor((botDiv-listY)/rowH)
 local scrollTop=math.max(1,math.min(ds.sel-maxVis//2,math.max(1,#ds.items-maxVis+1)))
 for row=1,maxVis do
  local idx=scrollTop+row-1
  if idx>#ds.items then break end
  local item=ds.items[idx]
  local iy=listY+(row-1)*rowH
  local isSel=(idx==ds.sel)
  if isSel then rect(bx+2,iy-1,bw-4,9,CHL) end
  local tc=isSel and CB or CT
  local dc=isSel and CB or CD
  print(idx..".",listX,iy,dc,true,1,false)
  print(string.sub(item.name or "?",1,item.atk and 21 or 28),nameX,iy,tc,true,1,false)
  if item.atk then print("ATK "..item.atk,atkX,iy,dc,true,1,false) end
 end
 -- Scrollbar
 if #ds.items>maxVis then
  local barH=maxVis*rowH
  local pct=(scrollTop-1)/math.max(1,#ds.items-maxVis)
  local markY=listY+math.floor(pct*(barH-4))
  rect(bx+bw-4,listY,2,barH,CB); rect(bx+bw-4,markY,2,4,CD)
 end

 -- Bottom: compact stats for the highlighted card. No description here --
 -- press X to open the full scrollable card info.
 line(bx+2,botDiv,bx+bw-3,botDiv,CD)
 local sc=ds.items[ds.sel] and ds.items[ds.sel].card
 if sc then
  if sc.cat=="monster" then
   print("ATK:"..(sc.atk or 0).."  DEF:"..(sc.def or 0).."  LV:"..(sc.lvl or 0),bx+4,by+bh-16,CT,true,1,false)
  else
   print(((sc.cat or ""):upper()).." - "..((sc.subtype or "normal"):upper()),bx+4,by+bh-16,CT,true,1,false)
  end
 end
 print("UP/DN browse   A pick   X info",bx+4,by+bh-8,CLEG,true,1,true)
end

function handleDeckSelectInput()
 local ds=G.deckSel
 if btnp(0) then ds.sel=math.max(1,ds.sel-1)
 elseif btnp(1) then ds.sel=math.min(#ds.items,ds.sel+1)
 elseif btnp(4) then
  local item=ds.items[ds.sel]
  if item then G.mode="free"; G.deckSel=nil; ds.onPick(item.deckIdx,item) end
 elseif btnp(6) then
  local item=ds.items[ds.sel]
  if item and item.card then G.infoCard=item.card end
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

function addAnim(frames,fn,onDone)
 -- Simulation runs headless: fire the completion callback now so effect
 -- bodies that waitAnim() on it resume immediately instead of stalling.
 if G.sim then
  if onDone then onDone() end
  return
 end
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
-- For revealed face-down monsters the GY move + EV_DESTROYED raise happen
-- inside the flash's onDone, so listeners fire after the reveal animation.
function revealAndDestroyMon(plr,col,reason)
 local m=G.mon[plr][col]
 if not m then return end
 if m.facedown and DESTROY_REASONS[reason] then
  m.facedown=false
  local zx,zy=monZoneXY(plr,col)
  addAnim(24,function(t,f) if t//4%2==0 then rect(zx,zy,ZW_MAIN,ZH,CCR) end end,
   function() sendMonsterToGY(plr,col,reason); checkEquips() end)
  return
 end
 sendMonsterToGY(plr,col,reason)
end

-- LP change helper: clamps and checks win; dispLp animates toward G.lp each tick
function changeLp(plr,delta)
 G.lp[plr]=math.max(0,G.lp[plr]+delta)
 checkWin()
end

-- Apply battle damage. Raises EV_BEFORE_DMG so hand-traps (Kuriboh via
-- listens.BEFORE_DAMAGE) can mutate ctx.negated to cancel the damage.
function applyDamage(plr,dmg)
 if dmg<=0 then return end
 -- Push-then-raiseNow: the changeLp continuation goes on the proc stack
 -- BEFORE EV_BEFORE_DMG is raised, so hand-traps (Kuriboh) can mutate
 -- ctx.negated during the chain to cancel the damage.
 local ctx={plr=plr,dmg=dmg,actor=3-plr,negated=false}
 procPushFrame(function()
  if not ctx.negated then changeLp(plr,-ctx.dmg) end
 end)
 raiseNow(EV_BEFORE_DMG,ctx)
end

-- ============================================================
-- CARD MOVEMENT  (single source of truth for moving cards)
-- ============================================================
-- All field/hand -> GY movement must go through these helpers so that
-- destroyFlash fires consistently, EV_DESTROYED is raised, and linkedTrap/
-- linkedMon back-pointers are cleared. `reason` is a free-form tag:
-- "battle", "effect", "cost", "tribute", "rule" (self-destruct). Only
-- DESTROY_REASONS tags raise EV_DESTROYED (PSCT "by battle/effect" vs
-- non-destruction "tribute"/"cost").

function sendMonsterToGY(plr,col,reason)
 local m=G.mon[plr][col]
 if not m then return nil end
 G.mon[plr][col]=nil
 bumpStats()
 -- Tokens vanish on leaving the field (real YGO ruling).
 if not m.isToken then table.insert(G.gy[plr],m) end
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
 destroyEvent(m,plr,reason)
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

-- Return an S/T card to its controller's hand (Giant Trunade etc.). Severs
-- linkedMon back-pointer and equip target. CoH-style: if a linked monster
-- exists, it's destroyed (the anchor is leaving the field). G.st[plr][col]
-- is cleared BEFORE the cascade so sendMonsterToGY's linkedTrap-destruction
-- branch doesn't find this card and route it to GY instead of hand.
function returnSTToHand(plr,col)
 local c=G.st[plr][col]
 if not c then return nil end
 G.st[plr][col]=nil
 bumpStats()
 if c.linkedMon then
  local m=c.linkedMon
  m.linkedTrap=nil; c.linkedMon=nil
  for mp=1,2 do for mc=1,3 do
   if G.mon[mp][mc]==m then sendMonsterToGY(mp,mc,"effect") end
  end end
 end
 c.facedown=false; c.setThisTurn=false
 if c.subtype=="equip" then c.equippedTo=nil end
 table.insert(G.hand[plr],c)
 return c
end

function returnMonsterToHand(plr,col)
 local m=G.mon[plr][col]
 if not m then return nil end
 G.mon[plr][col]=nil
 bumpStats()
 -- If summoned by a linked trap (CoH), destroy the trap too.
 if m.linkedTrap and not staticActive("blocksTraps") then
  for p=1,2 do for c=1,3 do
   if G.st[p][c]==m.linkedTrap then sendSpellTrapToGY(p,c,"rule") end
  end end
 end
 m.facedown=false; m.attacked=false; m.summoned=false
 m.posChanged=false; m.linkedTrap=nil
 m.borrowedFrom=nil; m.borrowedAtTurn=nil
 table.insert(G.hand[plr],m)
 return m
end

function returnFSToHand(plr)
 local f=G.fs[plr]
 if not f then return nil end
 G.fs[plr]=nil
 bumpStats()
 table.insert(G.hand[plr],f)
 return f
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

-- Move a player's field spell from the FS zone to their GY (replaced, or
-- destroyed). `actor` (optional) is the side doing the destroying. Opp-effect
-- destruction is refused while the controller has gkshaman+Necrovalley
-- (staticActive blocksFieldSpells). Self-destroy and "rule" replacement pass.
function sendFieldSpellToGY(plr,reason,actor)
 local f=G.fs[plr]
 if not f then return nil end
 if reason=="effect" and actor and actor~=plr and staticActive("blocksFieldSpells",plr) then
  return nil
 end
 G.fs[plr]=nil
 bumpStats()
 table.insert(G.gy[plr],f)
 return f
end

