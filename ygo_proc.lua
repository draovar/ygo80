-- [ygo_proc] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- COROUTINE PROCESSOR
-- ============================================================
-- Owns: G.proc.chain (the chain stack), the coroutine frame stack, the
-- choose()/waitAnim() yield protocol, and the event-raise plumbing.
--
-- Model: G.proc.frames is a stack of Lua coroutine frames. Card effects
-- run as coroutines. When an effect needs to wait (animation, player
-- decision, chain response), it yields a signal. The processor freezes
-- the stack until the wait is satisfied, then resumes with the result.
--
-- Listener shape in BEHAVIORS:
--   listens = {
--    SUMMON = {
--     optional=bool,            -- true = goes through chain priority window
--     speed=1|2|3,              -- chain speed; default chainSpeed(card)
--     when=function(self,ctx),  -- predicate; default true
--     react=function(self,ctx), -- coroutine body
--    },
--    ...
--   }
-- self = {card, plr, controller, zone="mon"|"st"|"fs"|"hand", col}

-- ============================================================
-- EVENT CONSTANTS
-- ============================================================
EV_PHASE      ="PHASE"
EV_SUMMON     ="SUMMON"
EV_FLIP       ="FLIP"
EV_ATTACK     ="ATTACK"
EV_BEFORE_DMG ="BEFORE_DAMAGE"
EV_DESTROYED  ="DESTROYED"
EV_TRIBUTED   ="TRIBUTED"
EV_ACTIVATE   ="ACTIVATE"

-- ============================================================
-- INIT
-- ============================================================
-- Call once at game start (after newGame). Adds the proc sub-state.
function procInit()
 G.proc={
  frames={},          -- coroutine stack; top = frames[#frames]
  chain={links={}},   -- shared chain stack (replaces G.chain)
  pending={},         -- events raised during resolution; flushed when idle
  currentChoice=nil,  -- exposed for ygo_input to read player CHOOSE requests
 }
end

-- ============================================================
-- FRAME STACK
-- ============================================================
function procPushFrame(body)
 table.insert(G.proc.frames,{co=coroutine.create(body),wait=nil})
end

function procTopFrame() return G.proc.frames[#G.proc.frames] end

-- True if no frames running and no pending events.
function procIdle()
 return #G.proc.frames==0 and #G.proc.pending==0
end

-- True if the processor has anything in flight: a coroutine running, a
-- waiting frame, a pending event queue, or a player choice being shown.
-- aiTick / autoPhase / etc. MUST gate on this so the game doesn't advance
-- while an effect chain is mid-resolution or the player is being prompted.
function procBusy()
 if not G.proc then return false end
 if #G.proc.frames>0 then return true end
 if #G.proc.pending>0 then return true end
 if G.proc.currentChoice then return true end
 return false
end

-- ============================================================
-- TICK  (call once per TIC frame, before drawChain/drawModeBanner)
-- ============================================================
function procTick()
 -- Drive the stack as far as it goes this frame. Bounded so a buggy
 -- coroutine can't hang the game; 64 resumes per frame is generous.
 -- Remove a frame from G.proc.frames by identity (a body may have pushed
 -- child frames before dying/erroring, so the dying frame isn't always on
 -- top -- popping the last element would orphan the children).
 local function dropFrame(target)
  for i=#G.proc.frames,1,-1 do
   if G.proc.frames[i]==target then table.remove(G.proc.frames,i); return end
  end
 end
 for _=1,64 do
  local f=procTopFrame()
  if not f then
   if #G.proc.pending>0 then procFlushPending(); return end
   return
  end
  -- Still waiting?
  if f.wait then
   if f.wait.kind=="anim"   and not (f.wait.done and f.wait.done.value) then return end
   if f.wait.kind=="choose" and f.wait.result==nil                       then return end
  end
  local fed=nil
  if f.wait and f.wait.kind=="choose" then
   fed=f.wait.result; if fed==false then fed=nil end
  end
  f.wait=nil
  local ok,sig=coroutine.resume(f.co,fed)
  if not ok then
   trace("PROC ERROR: "..tostring(sig))
   dropFrame(f)
  elseif coroutine.status(f.co)=="dead" then
   dropFrame(f)
  elseif type(sig)=="table" then
   if     sig.kind=="anim"   then f.wait=sig
   elseif sig.kind=="choose" then f.wait=sig; procRouteChoice(f.wait)
   elseif sig.kind=="push"   then procPushFrame(sig.body)
   end
  end
 end
end

-- ============================================================
-- YIELD HELPERS  (used inside coroutine bodies)
-- ============================================================
-- Block until an addAnim callback fires. Pair with playAnim().
function waitAnim(doneBox)
 return coroutine.yield{kind="anim",done=doneBox}
end

-- Ask for a decision. Returns the answer when the player/AI provides one.
-- See CHOOSE REQUEST KINDS below.
function choose(req)
 return coroutine.yield{kind="choose",req=req}
end

-- Push a child coroutine and continue (does NOT yield the current frame).
-- The child runs to completion before this frame resumes — that's just how
-- the processor's "top-frame wins" loop works.
function subroutine(body)
 return coroutine.yield{kind="push",body=body}
end

-- ============================================================
-- ANIMATION INTEGRATION
-- ============================================================
-- Wrap an addAnim call so the processor can wait on it. The done-box's
-- .value flips to true when the anim's onDone fires.
--   waitAnim(playAnim(60, function(t,f) -- draw frame end))
function playAnim(frames,tickFn)
 local box={value=false}
 addAnim(frames,tickFn,function() box.value=true end)
 return box
end

-- ============================================================
-- CHOOSE REQUEST KINDS
-- ============================================================
-- All six kinds carry plr (who is being asked). Cards may set aiPick (a
-- function or named-policy string) to override the default AI behavior.
--
--   {kind="zone",     plr, side=1|2|"any", row="mon"|"st", filter=fn,
--    title=str}                                     -> {plr,col} | nil
--   {kind="zones",    plr, side=, row=, count=N,
--    filter=fn, title}                              -> { {plr,col}, ... }
--   {kind="card",     plr, from="hand"|"gy"|"deck",
--    filter=fn, title}                              -> {idx} | nil
--   {kind="menu",     plr, items={ {label,key}, ... },
--    forced=bool, title}                            -> key | nil
--   {kind="yes_no",   plr, prompt=str}              -> true | false
--   {kind="response", plr, event, ctx,
--    options=[listener,...]}                        -> {optionIdx} | nil

-- ============================================================
-- CHOICE ROUTING
-- ============================================================
-- For plr==2 (AI), the answer is computed inline and stuffed into the
-- wait so the next tick resumes immediately (no actual frame delay).
-- For plr==1 (player), G.proc.currentChoice is exposed; ygo_input reads
-- it, drives the UI, and calls procAnswerChoice(answer) on confirm.
function procRouteChoice(waitObj)
 local req=waitObj.req
 -- Random kinds (coin/dice) play a popup animation and feed the result back
 -- via the addAnim onDone callback. Same path for both players — the popup
 -- is visual feedback, not interactive.
 -- 60 frames tumble + 120 frames settle = 180 frames total.
 if req.kind=="coin" then
  local result=math.random(0,1)
  G.popup={type="coin",result=result,t=180,frames=180}
  addAnim(180,
   function(t,f) G.popup.t=t end,
   function() G.popup=nil; waitObj.result=result end)
  return
 elseif req.kind=="dice" then
  local result=math.random(1,6)
  G.popup={type="dice",result=result,t=180,frames=180,displayed=result}
  addAnim(180,
   function(t,f)
    G.popup.t=t
    local elapsed=f-t
    if elapsed<60 and elapsed%4==0 then G.popup.displayed=math.random(1,6)
    elseif elapsed>=60 then G.popup.displayed=result end
   end,
   function() G.popup=nil; waitObj.result=result end)
  return
 end
 if req.plr==2 then
  local ans=aiAnswer(req)
  waitObj.result=(ans==nil) and false or ans   -- false != nil
  G.proc.currentChoice=nil
 else
  G.proc.currentChoice=req
  -- For response windows, snap cursor to the first eligible responder so
  -- the player sees what's available.
  if req.kind=="response" and req.options and #req.options>0 then
   G.mode="choose_response"
   for _,opt in ipairs(req.options) do
    if opt.self.plr==1 then
     local s=opt.self
     local row=(s.zone=="mon" and 1) or (s.zone=="hand" and 3) or 2
     local col=(s.zone=="hand") and (s.col-1) or s.col
     G.cur={side=1,row=row,col=col}
     break
    end
   end
  elseif req.kind=="card" then
   -- Bridge kind="card" to the sel_deck picker UI. Two modes:
   --  * Pool mode (req.from="hand"|"gy"|"deck") -- auto-builds items from the
   --    requested pool applying req.filter. ans.idx is the pool index.
   --  * Items mode (req.items=...) -- caller supplies a pre-built list. Useful
   --    for cross-pool picks (Monster Reborn picks from either GY, legionSearch
   --    picks from deck + GY). The caller's items have whatever opaque locator
   --    fields they need (gyPlr, gyIdx, source, etc.); ans.item is fed back so
   --    the caller can dispatch.
   local items
   if req.items then
    items=req.items
   else
    local pool=(req.from=="hand" and G.hand[req.plr])
            or (req.from=="gy"   and G.gy[req.plr])
            or (req.from=="deck" and G.deck[req.plr])
    items={}
    if pool then
     for i,c in ipairs(pool) do
      local card=(type(c)=="table") and c or CARDS[c]
      if not req.filter or req.filter(card,i) then
       table.insert(items,{
        deckIdx=i,card=card,name=card.name,atk=card.atk,def=card.def,
        lvl=card.lvl,desc=card.desc,
       })
      end
     end
    end
   end
   if #items==0 then
    -- No valid targets — auto-respond with nil so the coroutine can bail.
    waitObj.result=false
    G.proc.currentChoice=nil
    return
   end
   G.mode="sel_deck"
   G.deckSel={
    items=items,sel=1,title=req.title or "PICK CARD",
    onPick=function(deckIdx,item) procAnswerChoice({idx=deckIdx,item=item}) end,
   }
  elseif req.kind=="menu" then
   -- Bridge kind="menu" to the G.menu UI.
   -- The menu input handler in ygo_input dispatches via G.menu.onChoose
   -- when set, calling procAnswerChoice with the picked key (or nil on
   -- B-cancel if not forced).
   --
   -- Force G.mode="free" so the menu input handler in handleInput takes
   -- precedence -- otherwise an in-flight sel_* mode (e.g. sel_atk while
   -- gkassailant's react fires mid-attack-declaration) keeps stealing
   -- input from the menu.
   G.mode="free"
   G.menu={
    open=true,sel=1,items=req.items,forced=req.forced or false,
    onChoose=function(key) procAnswerChoice(key) end,
   }
  elseif req.kind=="zone" then
   -- Bridge kind="zone" to the sel_destroy picker. Currently only
   -- monster-row picking is implemented (row="mon"); add S/T row later
   -- if needed. req.side restricts to one player (1, 2) or nil/"any".
   -- The sel_destroy confirm check uses `(not ds.side or ds.side==c.side)`,
   -- so "any" must be normalized to nil for the check to allow either side.
   -- Don't use the `X and nil or Y` ternary idiom here -- Lua falls through
   -- to Y when the "then" branch is nil.
   local sideFilter=req.side
   if sideFilter=="any" then sideFilter=nil end
   G.mode="sel_destroy"
   G.destroySel={
    side=sideFilter,title=req.title,
    onPick=function(side,col) procAnswerChoice({plr=side,col=col}) end,
   }
   if req.side==2 then
    G.cur={side=2,row=1,col=4-(firstOccupied(G.mon[2]) or 1)}
   elseif req.side==1 then
    G.cur={side=1,row=1,col=firstOccupied(G.mon[1]) or 2}
   else
    G.cur={side=1,row=1,col=2}
   end
  end
 end
end

-- Called by ygo_input once the player picks (or cancels with nil/false).
function procAnswerChoice(answer)
 local f=procTopFrame()
 if not f or not f.wait or f.wait.kind~="choose" then return end
 f.wait.result=(answer==nil) and false or answer
 G.proc.currentChoice=nil
end

-- ============================================================
-- AI POLICY  (default per CHOOSE kind; cards override via req.aiPick)
-- ============================================================
function aiAnswer(req)
 if req.aiPick then
  if type(req.aiPick)=="function" then return req.aiPick(req) end
  return aiNamedPolicy(req.aiPick,req)
 end
 if req.kind=="zone"     then return aiPickZone(req) end
 if req.kind=="zones"    then return aiPickZones(req) end
 if req.kind=="card"     then return aiPickCard(req) end
 if req.kind=="menu"     then return req.items[1][2] end   -- pick first
 if req.kind=="yes_no"   then return false end
 if req.kind=="response" then
  -- Default policy: activate the first matching responder. Refined per-card
  -- via req.aiPick if a smarter policy is needed.
  if req.options and #req.options>0 then return {optionIdx=1} end
  return false
 end
 return nil
end

-- Highest-scoring zone matching filter. "Score" is ATK for monsters, 0 for S/T.
function aiPickZone(req)
 local sides={1,2}
 if     req.side==1 then sides={1}
 elseif req.side==2 then sides={2} end
 local best,bestK=-1,nil
 for _,p in ipairs(sides) do
  local arr=(req.row=="st") and G.st[p] or G.mon[p]
  for c=1,3 do
   local card=arr[c]
   if card and (not req.filter or req.filter(card,p,c)) then
    local s=card.atk or 0
    if s>best then best=s; bestK={plr=p,col=c} end
   end
  end
 end
 return bestK
end

-- Multi-pick: lowest-ATK first (tribute selection default).
function aiPickZones(req)
 local cands={}
 for c=1,3 do
  local m=G.mon[req.plr][c]
  if m and (not req.filter or req.filter(m,req.plr,c)) then
   table.insert(cands,{plr=req.plr,col=c,score=m.atk or 0})
  end
 end
 table.sort(cands,function(a,b) return a.score<b.score end)
 local out={}
 for i=1,math.min(req.count or 1,#cands) do
  table.insert(out,{plr=cands[i].plr,col=cands[i].col})
 end
 return #out>0 and out or nil
end

-- Pick highest-ATK card matching filter (or first matching for non-monsters).
-- Handles both pool mode (req.from=...) and items mode (req.items=...).
function aiPickCard(req)
 if req.items then
  local best,bestI=-1,nil
  for i,it in ipairs(req.items) do
   local s=it.atk or 0
   if s>best then best=s; bestI=i end
  end
  if not bestI then return nil end
  local pick=req.items[bestI]
  return {idx=pick.deckIdx,item=pick}
 end
 local pool=(req.from=="hand" and G.hand[req.plr])
         or (req.from=="gy"   and G.gy[req.plr])
         or (req.from=="deck" and G.deck[req.plr])
 if not pool or #pool==0 then return nil end
 local best,bestI=-1,nil
 for i,c in ipairs(pool) do
  local card=(type(c)=="table") and c or CARDS[c]
  if not req.filter or req.filter(card,i) then
   local s=card.atk or 0
   if s>best then best=s; bestI=i end
  end
 end
 return bestI and {idx=bestI} or nil
end

-- Named policies. Extend this table as cards need new AI behaviors.
function aiNamedPolicy(name,req)
 if name=="lowestAtkOpp" then     -- Fissure: opp monster, lowest ATK
  local opp=3-req.plr
  local low,lowK=math.huge,nil
  for c=1,3 do
   local m=G.mon[opp][c]
   if m and (m.atk or 0)<low then low=m.atk; lowK={plr=opp,col=c} end
  end
  return lowK
 end
 -- Fallback: default policy for the kind.
 local r={}; for k,v in pairs(req) do r[k]=v end; r.aiPick=nil
 return aiAnswer(r)
end

-- ============================================================
-- EVENTS  (raise + listener collection)
-- ============================================================
-- raise(event,ctx):
--   - If the stack is busy (mid-resolution), queue onto G.proc.pending.
--   - Else fire immediately: collect listeners, push mandatory triggers
--     as frames (SEGOC order: turn-player pushed LAST -> resolves FIRST),
--     and run a chain response window if optional responders exist.
function raise(event,ctx)
 ctx=ctx or {}; ctx.event=event
 if #G.proc.frames>0 then
  table.insert(G.proc.pending,{event=event,ctx=ctx})
  return
 end
 raiseNow(event,ctx)
end

function raiseNow(event,ctx)
 local mand,opt=collectListeners(event,ctx)
 -- Turn-player's mandatory triggers go on top -> resolve first.
 table.sort(mand,function(a,b)
  if a.plr==b.plr then return false end
  return a.plr==G.active
 end)
 -- Push mandatory triggers in reverse so SEGOC order is correct on the stack.
 for i=#mand,1,-1 do
  local L=mand[i]
  procPushFrame(function() L.react(L.self,ctx) end)
 end
 if #opt>0 then
  procPushFrame(function() runResponseWindow(event,ctx) end)
 end
end

-- Flush queued events. Called from procTick when the stack drains.
function procFlushPending()
 local q=G.proc.pending; G.proc.pending={}
 for _,e in ipairs(q) do raiseNow(e.event,e.ctx) end
end

-- Walk every face-up field card + both hands; return (mandatory, optional)
-- listener lists for this event.
function collectListeners(event,ctx)
 local m,o={},{}
 -- Cards already on the chain (mid-activation) can't be activated again in
 -- the same response window — once flipped face-up by activateListener /
 -- procActivate, a card cannot chain to itself.
 local function alreadyOnChain(card)
  if not G.proc.chain then return false end
  for _,L in ipairs(G.proc.chain.links) do
   if L.source==card then return true end
  end
  return false
 end
 local function consider(card,plr,zone,col)
  if not card or alreadyOnChain(card) then return end
  local b=BEHAVIORS[card.effect]
  if not b or not b.listens then return end
  local L=b.listens[event]
  if not L then return end
  -- Trap cards never fire from hand — they must be Set on the field first.
  -- (Fixes a bug where Trap Hole / Mirror Force / etc. in hand triggered
  -- response prompts on AI summons / attacks even though the player can't
  -- actually activate a trap from hand.)
  if card.cat=="trap" and zone=="hand" then return end
  local self={card=card,plr=plr,controller=plr,zone=zone,col=col}
  if L.when and not L.when(self,ctx) then return end
  local entry={
   self=self,react=L.react,plr=plr,
   speed=L.speed or chainSpeed(card),
  }
  if L.optional then table.insert(o,entry) else table.insert(m,entry) end
 end
 -- Apply the face-down S/T response rules: cards Set this turn can't respond,
-- and face-down Traps can't respond while Jinzo (blocksTraps) is on the field.
-- (Face-up continuous traps still listen — staticActive's own Jinzo guard
-- handles those at query time.)
 local trapsBlocked=staticActive("blocksTraps")
 local function considerST(card,p,c)
  if not card then return end
  if card.facedown then
   if card.setThisTurn then return end
   if card.cat=="trap" and trapsBlocked then return end
  end
  consider(card,p,"st",c)
 end
 for p=1,2 do
  for c=1,3 do
   local m1=G.mon[p][c]
   if m1 and not m1.facedown then consider(m1,p,"mon",c) end
   considerST(G.st[p][c],p,c)
  end
  if G.fs[p] and not G.fs[p].facedown then consider(G.fs[p],p,"fs",nil) end
  for i,h in ipairs(G.hand[p]) do consider(h,p,"hand",i) end
 end
 -- Also consider ctx.card if it's no longer on the field — handles the
 -- "when this card is destroyed/tributed" patterns where the trigger source
 -- has just been moved to GY. The field-scan loop above already covered
 -- on-field sources, so we add ctx.card only if it wasn't matched.
 if ctx and ctx.card then
  local found=false
  for p=1,2 do
   if G.fs[p]==ctx.card then found=true; break end
   for c=1,3 do
    if G.mon[p][c]==ctx.card or G.st[p][c]==ctx.card then found=true; break end
   end
   if not found then
    for _,h in ipairs(G.hand[p]) do if h==ctx.card then found=true; break end end
   end
   if found then break end
  end
  if not found then consider(ctx.card,ctx.plr or 1,"gy",nil) end
 end
 return m,o
end

-- ============================================================
-- EVENT WRAPPERS  (call from engine sites to raise the corresponding event)
-- ============================================================
-- Each one bumps stats / filters set-face-down / fills the ctx, then raises.
-- Cards listen via BEHAVIORS.listens.X.

-- Call AFTER the monster lands in G.mon[plr][col]. Skips Set (facedown).
function summonEvent(card,plr,col,kind,tributed)
 if not card or card.facedown then return end
 bumpStats()
 raise(EV_SUMMON,{
  card=card,plr=plr,col=col,kind=kind or "normal",
  facedown=false,tributed=tributed or {},actor=plr,
 })
end

-- Call AFTER card.facedown has been set to false.
function flipEvent(card,plr,col)
 if not card or card.facedown then return end
 bumpStats()
 raise(EV_FLIP,{card=card,plr=plr,col=col,actor=plr})
end

-- Call AFTER the card has been moved to the GY. Only DESTROY_REASONS reasons
-- fire the event ("tribute"/"cost" remain silent per PSCT).
function destroyEvent(card,plr,reason)
 if not card or not DESTROY_REASONS[reason] then return end
 raise(EV_DESTROYED,{card=card,plr=plr,reason=reason,actor=plr})
end

-- ============================================================
-- RESPONSE WINDOW
-- ============================================================
-- Alternates priority between players. Each pass: if the offering side has
-- a valid responder, ask them; if they activate, push the activation and
-- restart the loop with the new top-of-stack speed in mind.
-- Two consecutive passes -> resolveChainStack.
function runResponseWindow(event,ctx)
 local passes=0
 local offering=3-(ctx.actor or G.active)   -- non-actor goes first
 -- After link 1, further chain links only respond to the activation itself
 -- (EV_ACTIVATE) -- the original trigger window has closed.
 local curEvent,curCtx=event,ctx
 while passes<2 do
  local _,opt=collectListeners(curEvent,curCtx)
  local top=chainTopSpeed()
  local mine={}
  for _,e in ipairs(opt) do
   if e.plr==offering and e.speed>=math.max(top,2) then
    table.insert(mine,e)
   end
  end
  if #mine==0 then
   passes=passes+1
  else
   local ans=choose{
    kind="response",plr=offering,
    event=curEvent,ctx=curCtx,options=mine,
   }
   if not ans then
    passes=passes+1
   else
    passes=0
    local picked=mine[ans.optionIdx or 1]
    subroutine(function() activateListener(picked,curEvent,curCtx) end)
    local newLink=G.proc.chain.links[#G.proc.chain.links]
    curEvent=EV_ACTIVATE
    curCtx={card=picked.self.card,controller=picked.plr,
            actor=picked.plr,link=newLink}
   end
  end
  offering=3-offering
 end
 resolveChainStack()
end

-- Current top-of-stack speed (0 if empty).
function chainTopSpeed()
 local L=G.proc.chain.links
 return (#L>0) and L[#L].speed or 0
end

-- ============================================================
-- CHAIN LINK OPERATIONS
-- ============================================================
-- pushLink(link)  -- card author calls this during activation, after costs
--                    are paid and frozen targets are picked.
-- resolveChainStack() -- LIFO; called when both players pass.
function pushLink(link)
 link.negated=link.negated or false
 link.speed=link.speed or chainSpeed(link.source)
 table.insert(G.proc.chain.links,link)
end

-- Shared activation animation: 60-frame red zone flash + steady card-name
-- banner above the divider. Coroutine helper -- yields until the anim
-- completes. Used by procActivate (direct activations) and activateListener
-- (response-window activations). For zone="hand" only the banner runs
-- (hand cards have no fixed on-field position to flash).
function playActivateAnim(card,plr,zone,col)
 local msg=(card.name or "?"):upper()
 local w=#msg*4+8
 local bx=FA_X+(FA_W-w)//2
 local by=DIV_Y-4
 if zone=="hand" then
  waitAnim(playAnim(60,function(t,f)
   rect(bx,by,w,9,CCR); rectb(bx,by,w,9,CT)
   print(msg,bx+4,by+2,CT,true,1,true)
  end))
  return
 end
 local zx,zy=zoneXY(plr,zone,col)
 local sc=(card.cat=="trap") and CTR or CSP
 local zw=(zone=="fs") and ZW_SPEC or ZW_MAIN
 waitAnim(playAnim(60,function(t,f)
  if (t//6)%2==0 then rect(zx,zy,zw,ZH,sc); rectb(zx,zy,zw,ZH,CT) end
  rect(bx,by,w,9,CCR); rectb(bx,by,w,9,CT)
  print(msg,bx+4,by+2,CT,true,1,true)
 end))
end

-- Direct activation entry point. Pushes a frame that plays the activation
-- animation, pushes the link onto G.proc.chain, then drives a response
-- window for EV_ACTIVATE so the chain resolves (and Magic Jammer / chained
-- effects can fire). Call from any sync code (menu handlers, AI, pickers).
--
-- reactFn(link) is invoked at chain-resolve time; the `link` arg is the
-- actual on-chain link reference (needed by cards like Magic Jammer that
-- iterate G.proc.chain.links to find themselves). Default react is
-- applyResolve(card,plr,nil) when reactFn is nil.
function procActivate(card,plr,zone,col,reactFn)
 procPushFrame(function()
  card.facedown=false
  playActivateAnim(card,plr,zone,col)
  local link={
   source=card,controller=plr,speed=chainSpeed(card),
   sourceLoc={zone=zone,plr=plr,col=col},
  }
  link.react=function()
   if reactFn then reactFn(link) else applyResolve(card,plr,nil) end
  end
  pushLink(link)
  -- Drive the chain to resolution. With no listens.ACTIVATE responders
  -- this auto-passes twice and resolveChainStack fires immediately.
  runResponseWindow(EV_ACTIVATE,{card=card,controller=plr,actor=plr,link=link})
 end)
end

-- Activation wrapper used by activate-hooks that need the from-hand fallback.
-- Three flow variants:
--   zone="st", cat="trap"   -> procActivate (face-down trap flips up)
--   zone="st", cat="spell"  -> procActivate (card already in zone)
--   zone="hand", cat="spell"-> place in first free S/T then procActivate
--                              (or send straight to GY when no S/T free)
-- resolveFn(link) runs at chain-resolve; link is the actual on-chain link.
function pushActivationLink(opts,resolveFn)
 local card,col,zone = opts.card, opts.col, opts.zone
 local plr = opts.plr or 1
 if zone=="hand" and card.cat=="spell" then
  local stCol=firstEmpty(G.st[plr])
  if stCol then
   G.st[plr][stCol]=card
   for i,h in ipairs(G.hand[plr]) do
    if h==card then table.remove(G.hand[plr],i); break end
   end
   procActivate(card,plr,"st",stCol,resolveFn)
  else
   -- No S/T zone free: card goes straight to GY. Push the frame manually
   -- with sourceLoc=nil so spendLink leaves the GY'd card alone.
   addToGY(plr,card,"effect")
   procPushFrame(function()
    playActivateAnim(card,plr,"hand",nil)
    local link={source=card,controller=plr,speed=chainSpeed(card),sourceLoc=nil}
    link.react=function()
     if resolveFn then resolveFn(link) else applyResolve(card,plr,nil) end
    end
    pushLink(link)
    runResponseWindow(EV_ACTIVATE,{card=card,controller=plr,actor=plr,link=link})
   end)
  end
 else
  procActivate(card,plr,zone,col,resolveFn)
 end
end

-- ============================================================
-- S/T + FS PICKER  (card-specific picker with its own sel_* UI -- the target
-- set is a mix of S/T zones + FS zones that doesn't map cleanly to choose{}.)
-- ============================================================
-- Ordered list of valid S/T + FS targets, excluding `source`. Each entry
-- carries the cursor position (side,row,vcol) and the data locator (kind,di).
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

-- Generic picker: opts = {title, resolveFn(targetPlr,kind,targetDi)}.
function pickSTOrFSThenActivate(col,card,ctx,zone,opts)
 local tgts=mstTargets(card)
 if #tgts==0 then G.mode="free"; return end
 G.mode="sel_st_target"
 G.stTargetSel={title=opts.title,source=card,zone=zone,col=col,idx=1,
  onPick=function(targetPlr,kind,targetDi)
   pushActivationLink({card=card,col=col,zone=zone,plr=1,
                        targets={plr=targetPlr,kind=kind,col=targetDi}},function()
    opts.resolveFn(targetPlr,kind,targetDi)
   end)
  end}
 local t=tgts[1]
 G.cur={side=t.side,row=t.row,col=t.vcol}
end

-- Convert a listener (from collectListeners) into a chain link and push it.
-- Called by runResponseWindow when a player chooses to activate a responder.
-- The animation matches procActivate so direct activations and chained
-- responses look identical on screen.
function activateListener(listener,event,ctx)
 local card=listener.self.card
 local zone=listener.self.zone
 local plr=listener.self.plr
 local col=listener.self.col
 if card.facedown and zone=="st" then card.facedown=false end
 playActivateAnim(card,plr,zone,col)
 pushLink{
  source=card,
  controller=listener.plr,
  speed=listener.speed,
  sourceLoc={zone=zone,plr=plr,col=col},
  react=function() listener.react(listener.self,ctx) end,
 }
end

function resolveChainStack()
 local links=G.proc.chain.links
 for i=#links,1,-1 do
  local L=links[i]
  if not L.negated then
   subroutine(L.react)
  end
  -- (Cleanup is invoked after react completes; we do it inline here
  -- because spendLink only touches G state, not the processor.)
  spendLink(L)
 end
 G.proc.chain.links={}
end

-- Cleanup a resolved link's source per type:
--  - normal spell/trap on field -> GY
--  - continuous/equip spell -> stays face-up
--  - field spell -> stays face-up in FS
--  - cast from hand -> GY
function spendLink(link)
 local loc=link.sourceLoc; if not loc then return end
 if loc.zone=="st" then
  local c=link.source
  if c.subtype=="continuous" or c.subtype=="equip" then c.facedown=false
  else sendSpellTrapToGY(loc.plr,loc.col,"effect") end
 elseif loc.zone=="fs" then
  link.source.facedown=false
 elseif loc.zone=="hand" then
  for i,h in ipairs(G.hand[loc.plr]) do
   if h==link.source then discardFromHand(loc.plr,i,"effect"); break end
  end
 end
end

-- ============================================================
-- PRIMITIVES  (state changes; each raises one event after committing)
-- ============================================================
-- Card behaviors should call these instead of writing to G.* directly.
-- That keeps event-raising automatic and exhaustive: if state changes
-- without going through a primitive, no event fires.

function primSummon(card,plr,col,kind,tributed)
 G.mon[plr][col]=card
 card.facedown=(kind=="set")
 card.attacked=false
 card.posChanged=false
 card.summoned=true
 card.summonedTurn=G.turn
 -- Tributes are paid (raise TRIBUTED) before the summon event fires.
 if tributed then
  for _,t in ipairs(tributed) do primTribute(t.card,t.plr,t.col) end
 end
 raise(EV_SUMMON,{
  card=card,plr=plr,col=col,kind=kind,
  facedown=card.facedown,tributed=tributed or {},
  actor=plr,
 })
end

function primFlip(card,plr,col)
 if not card or not card.facedown then return end
 card.facedown=false
 raise(EV_FLIP,{card=card,plr=plr,col=col})
end

function primDestroy(card,plr,col,reason)
 if not (card and G.mon[plr] and G.mon[plr][col]==card) then return end
 sendMonsterToGY(plr,col,reason or "effect")
 raise(EV_DESTROYED,{card=card,plr=plr,reason=reason or "effect"})
end

function primTribute(card,plr,col)
 sendMonsterToGY(plr,col,"tribute")
 raise(EV_TRIBUTED,{card=card,plr=plr})
end

-- ============================================================
-- HIGH-LEVEL HELPERS  (used inside react coroutine bodies)
-- ============================================================
-- These wrap primitive + animation + waitAnim so card authors write
-- straight-line code. Each one is safe to call from any coroutine; the
-- yields propagate up to procTick.

-- Play the standard destroy flash, then send to GY.
function destroy(target,reason)
 if not target then return end
 local card=G.mon[target.plr] and G.mon[target.plr][target.col]
 if not card then return end
 -- TODO migration: integrate destroyFlash anim once we port battle.
 -- For now the destroy is instant; flashes still come from sendMonsterToGY.
 primDestroy(card,target.plr,target.col,reason or "effect")
end

function flipTarget(target)
 local card=G.mon[target.plr] and G.mon[target.plr][target.col]
 if card then primFlip(card,target.plr,target.col) end
end

-- ============================================================
-- WORKED EXAMPLES  (commented; not active until migration writes them)
-- ============================================================
-- These show what BEHAVIORS entries look like under the new model. They
-- replace ~30-line player+AI branched implementations with 4-8 lines.

-- Maneater Bug: when flipped, destroy 1 monster on either side.
--
-- maneater = {
--  listens = { FLIP = { react = function(self, ctx)
--   if not (hasMonsters(1) or hasMonsters(2)) then return end
--   local pick = choose{
--    kind="zone", plr=self.plr, row="mon", side="any",
--    title="MANEATER: PICK 1",
--    filter=function(card,p,c) return card~=nil end,
--   }
--   destroy(pick, "effect")
--  end } },
-- }
--
-- Notes:
--  * No `if plr==2 then ... else ...` branch. choose() routes to UI vs
--    aiPickZone() based on req.plr.
--  * No G.mode="sel_destroy", no G.destroySel, no onPick closure.
--  * No checkEquips() — DESTROYED event auto-fires from primDestroy.

-- Trap Hole: optional response to opponent's Normal Summon of ATK>=1000.
--
-- traphole = {
--  listens = { SUMMON = {
--   optional = true,   speed = 2,
--   when = function(self, ctx)
--    return ctx.kind=="normal" and not ctx.facedown
--       and (ctx.card.atk or 0)>=1000 and ctx.actor ~= self.controller
--   end,
--   react = function(self, ctx) destroy({plr=ctx.plr,col=ctx.col},"effect") end,
--  } },
-- }
--
-- Notes:
--  * Optional + speed=2 -> goes through chain priority window.
--  * Engine never special-cases trap-vs-monster-effect; it's all listens.

-- gkcurse: burn opponent 800 each time this is summoned (mandatory).
--
-- gkcurse = {
--  listens = { SUMMON = {
--   when = function(self,ctx) return ctx.card == self.card end,
--   react = function(self,ctx) primChangeLp(3-self.plr,-800) end,
--  } },
-- }
--
-- Notes:
--  * Not optional -> SS1 mandatory trigger, auto-pushed at SUMMON.
--  * "when ctx.card == self.card" pattern is how a card recognizes
--    its own summon vs any other summon.
