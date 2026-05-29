-- [ygo_chain] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- CHAIN-RELATED HELPERS (data + rendering)
-- ============================================================
-- The chain itself lives in ygo_proc.lua (G.proc.chain). This module holds
-- the chainSpeed query + the rendering overlay + drawModeBanner.

-- Derive spell speed from card data so we don't have to annotate every card.
function chainSpeed(card)
 if not card then return 1 end
 local b=behaviorOf(card)
 if b and b.speed then return b.speed end
 if card.cat=="trap"  then return card.subtype=="counter"   and 3 or 2 end
 if card.cat=="spell" then return card.subtype=="quickplay" and 2 or 1 end
 return 1  -- monster default (Ignition / Flip / Trigger)
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
 elseif G.mode=="choose_response" then
  txt="RESPOND? A=YES B=PASS"
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
 if not G.proc or not G.proc.chain then return end
 local links=G.proc.chain.links
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

-- Returns the screen X,Y of a zone for player `plr`.
--   row: "mon" | "st" | "fs" | "ed" | "gy" | "dk" | "hand"
--   col: column index 1..3 for "mon"/"st" (ignored for special / hand zones)
-- If row is "mon"/"st" and col is nil, X is returned as nil (callers that
-- only need the row Y can write `local _,y=zoneXY(plr,"st")`).
-- Encapsulates the player-side mirror (opp uses reflected column indices) in
-- one place so every drawing/animation call site can stop duplicating the
-- `(plr==1) and ... or ...` ternaries.
function zoneXY(plr, row, col)
 local px = (plr==1)
 if     row=="mon"  then return col and (px and COL[col] or COL[4-col]) or nil, px and PY_M or OY_M
 elseif row=="st"   then return col and (px and COL[col] or COL[4-col]) or nil, px and PY_S or OY_S
 elseif row=="fs"   then return px and COL[0]   or COL[4],     px and PY_M or OY_M
 elseif row=="ed"   then return px and COL[4]   or COL[0],     px and PY_M or OY_M
 elseif row=="gy"   then return px and COL[0]   or COL[4],     px and PY_S or OY_S
 elseif row=="dk"   then return px and COL[4]   or COL[0],     px and PY_S or OY_S
 elseif row=="hand" then return nil,                            px and PY_H or OY_H
 end
end

-- Back-compat shim — used by callers that only ever need a monster-zone XY.
function monZoneXY(plr,col) return zoneXY(plr,"mon",col) end

-- Reasons that count as "destruction" and fire EV_DESTROYED. "tribute" and
-- "cost" only send the card to GY (per PSCT: tribute is not destruction).
DESTROY_REASONS={battle=true,effect=true,rule=true}

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

