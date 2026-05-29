-- [ygo_deckbuild] YGO80 module -- loaded via require() from ygo80.lua

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
 if cd.spr then spr(cd.spr,bx+5,artY,-1,2,0,0,2,2) end

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

 -- Description (small font, wrapped, scrollable with UP/DN). cd~=G.infoShown
 -- detection isn't needed here -- scroll is reset to 0 by the close handlers.
 local scrollable=false
 if cd.desc then
  local dx,dy,dmaxY,lineH=bx+5,by+71,by+bh-10,7  -- by+71 (not +72) so 35px fits exactly 5 rows
  local visN=math.floor((dmaxY-dy)/lineH)
  local lines=wrapLines(cd.desc,bw-16)  -- -16 leaves a right gutter for the scroll arrows
  local maxScroll=math.max(0,#lines-visN)
  scrollable=maxScroll>0
  local off=math.max(0,math.min(G.infoScroll or 0,maxScroll))
  G.infoScroll=off
  for i=1,visN do
   local li=off+i
   if li>#lines then break end
   print(lines[li],dx,dy+(i-1)*lineH,CD,true,1,true)
  end
  -- scroll indicators: up/down triangles at the right edge of the desc area
  local ax=bx+bw-9
  if off>0       then tri(ax,dy+1,ax+5,dy+1,ax+2,dy-2,CT) end
  if off<maxScroll then tri(ax,dmaxY-3,ax+5,dmaxY-3,ax+2,dmaxY,CT) end
 end

 if scrollable then print("UP/DN scroll  B close",bx+5,by+bh-8,CLEG,true,1,true)
 else                print("B:close",bx+bw-46,by+bh-8,CLEG,true,1,true) end
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
    drawHandPlr(x,y,makeCard(id))
   else
    rect(x,y,DB_CW,DB_CH,CHL)
    rectb(x,y,DB_CW,DB_CH,CD)
   end
   if DB.cur.panel==1 and DB.cur.row==r and DB.cur.col==c then
    drawCursorRect(x,y,DB_CW,DB_CH)
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
  if cd.spr then spr(cd.spr,lx,iy,-1,1,0,0,1,1) end
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
  if btnp(0) then G.infoScroll=(G.infoScroll or 0)-1
  elseif btnp(1) then G.infoScroll=(G.infoScroll or 0)+1
  elseif btnp(5) then DB.info=nil; G.infoScroll=0 end
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

