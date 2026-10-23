-- world: the rules of the fight. Two fighters on a line (x, tenths of a metre), each a state machine: idle, walk, crouch, jump, attack, block, hurt, blocked,
-- down, getting up, knocked out. A hit is a point in front of the attacker's hips at some heights, against the other's body. The round is timed; two won
-- rounds win the match. The CPU's fighter is steered by a small AI. Nothing here draws; it calls hook(event, ...).
local Moves = require("moves")
local rng = require("rng")
local W = {}

W.HALF = 36                  -- the ring's half width, for a fighter's hips
local WALK, BACKWALK = 0.45, 0.33
local JUMP_V, GRAV = 1.0, 0.0556 -- (tenths of a metre a tick: about nine tenths high, three-fifths of a second in the air)
local SEP = 6.6              -- how near two fighters can stand
local ROUND_T, INTRO_T, KO_T = 3600, 90, 150

local function sign(v) return v < 0 and -1 or v > 0 and 1 or 0 end

local function new_fighter(x, face)
  return {x = x, y = 0, vy = 0, vx = 0, face = face, hp = 100, state = "idle", t = 0, move = nil, hit_done = false, stun = 0, phase = 0, combo = 0,
          crouch = false, chain_ok = false, wins = 0, hits_taken = 0, blocking = false, pushed = 0}
end

function W.new(difficulty)
  W.rng = rng.new(ticks and ticks() or 1)
  W.diff = difficulty or 2
  W.round, W.timer, W.phase, W.phase_t = 1, ROUND_T, "intro", INTRO_T
  W.p = new_fighter(-14, 1)
  W.c = new_fighter(14, -1)
  W.p.wins, W.c.wins = 0, 0
  W.winner = nil
  W.combo_p, W.combo_t = 0, 0 -- the player's combo on the CPU
  W.hook = W.hook or function() end
  W.ai, W.ai_p = {t = 0, act = nil, hold = 0}, {t = 0, act = nil, hold = 0}
  W.round_clean = true
end

function W.new_round()
  local p, c = W.p, W.c
  local pw, cw = p.wins, c.wins
  W.p, W.c = new_fighter(-14, 1), new_fighter(14, -1)
  W.p.wins, W.c.wins = pw, cw
  W.timer, W.phase, W.phase_t = ROUND_T, "intro", INTRO_T
  W.round_clean = true
  W.ai, W.ai_p = {t = 0, act = nil, hold = 0}, {t = 0, act = nil, hold = 0}
end

local function span(o) -- the heights a fighter's body covers
  if o.state == "down" or o.state == "ko" then return o.y, o.y + 3 end
  if o.crouch then return o.y, o.y + 10 end
  return o.y, o.y + 18
end

local function actionable(f) return f.state == "idle" or f.state == "walk" or f.state == "crouch" or f.state == "block" end

-- an attack's point reaches the other: returns "hit", "block" or nil
local function connects(f, o, m)
  local d = (o.x - f.x) * f.face
  if d < 0.5 or d > m.reach + 2.4 then return nil end
  local lo, hi = span(o)
  if not (m.hh[1] + f.y < hi and m.hh[2] + f.y > lo) then return nil end
  if (m.level == "low") and o.y > 3.5 then return nil end -- a jump clears a sweep
  if o.state == "down" or o.state == "ko" or o.state == "getup" then return nil end
  return true
end

local function guarding(o, m, f) -- is the other holding back, so that this is blocked
  if not o.back_held or not (actionable(o) or o.state == "blocked") then return false end
  if m.level == "low" then return o.crouch end         -- a low attack is stopped crouching
  if m.level == "high" or m.level == "mid" or m.level == "air" then return true end
  return false
end

local function start_move(f, m)
  f.state, f.move, f.t, f.hit_done, f.chain_ok = "attack", m, 0, false, false
  W.hook("whoosh", f, m)
end

local function land_hit(f, o, m)
  local blocked = guarding(o, m, f)
  W.hook(blocked and "blocked" or "hit", f, o, m)
  f.hit_done = true
  f.chain_ok = m.chain or false
  if blocked then
    o.state, o.t, o.stun = "blocked", 0, m.blockstun
    o.vx = f.face * m.knock * 0.1
  else
    o.hp = math.max(0, o.hp - m.dmg)
    o.hits_taken = o.hits_taken + 1
    f.combo = f.combo + 1
    o.state, o.t, o.stun = "hurt", 0, m.hitstun
    o.low_hit = m.level == "low"
    o.vx = f.face * m.knock * 0.2
    if m.down or o.hp <= 0 or o.y > 0.5 then
      o.state, o.t = o.hp <= 0 and "ko" or "down", 0
      o.vy = 0.7 -- thrown a little up
      o.vx = f.face * (m.knock + 0.8) * 0.2
    end
    if f == W.p then W.combo_p, W.combo_t = W.combo_p + 1, 90 end
  end
  o.crouch = false
end

local function step_fighter(f, o, inp)
  local grounded = f.y <= 0 and f.vy <= 0
  f.t = f.t + 1
  -- facing: toward the other, whenever it is free to turn
  if grounded and (actionable(f)) then f.face = (o.x >= f.x) and 1 or -1 end
  f.back_held = inp and ((inp.left and f.face == 1) or (inp.right and f.face == -1)) or false
  local st = f.state
  if st == "idle" or st == "walk" or st == "crouch" or st == "block" then
    f.crouch = inp.down and grounded
    local dir = (inp.right and 1 or 0) - (inp.left and 1 or 0)
    if inp.up and grounded and not f.crouch then
      f.state, f.vy, f.t = "jump", JUMP_V, 0
      f.vx = dir * 0.7
      W.hook("jump", f)
    elseif inp.b_p and not f.crouch then start_move(f, Moves.kick)
    elseif inp.b_p and f.crouch then start_move(f, Moves.sweep)
    elseif inp.a_p and not f.crouch then start_move(f, Moves.punch)
    elseif inp.a_p and f.crouch then start_move(f, Moves.punch)
    elseif f.crouch then f.state, f.vx = "crouch", 0
    elseif dir ~= 0 then
      local fwd = dir == f.face
      f.state = "walk"
      f.vx = dir * (fwd and WALK or BACKWALK)
      f.phase = f.phase + 0.28
    else
      f.state, f.vx = "idle", 0
    end
    if f.back_held and (f.state == "idle" or f.state == "walk" or f.state == "crouch") and f.state ~= "jump" then f.blocking = true else f.blocking = false end
  elseif st == "jump" then
    f.vy = f.vy - GRAV
    f.y = f.y + f.vy
    if inp.b_p and not f.move then f.move = Moves.jkick f.hit_done, f.t = false, 0 end
    if f.y <= 0 then f.y, f.vy, f.vx, f.state, f.move, f.t = 0, 0, 0, "idle", nil, 0 W.hook("land", f) end
    if f.move then -- the jump kick: it can hurt all the while it is out
      local m = f.move
      if not f.hit_done and f.t >= m.startup and f.t <= m.startup + m.active and connects(f, o, m) then land_hit(f, o, m) end
    end
  elseif st == "attack" then
    local m = f.move
    if m.air then f.state = "jump" return end
    if not f.hit_done and f.t > m.startup and f.t <= m.startup + m.active and connects(f, o, m) then land_hit(f, o, m) end
    -- a punch that landed may be followed by another before the recovery is over
    if f.chain_ok and f.t > m.startup + m.active and (inp.a_p or inp.b_p) then
      start_move(f, inp.b_p and Moves.kick or Moves.punch)
      return
    end
    if f.t >= m.startup + m.active + m.rec then f.state, f.move, f.t = "idle", nil, 0 end
  elseif st == "hurt" or st == "blocked" then
    if f.t >= f.stun then f.state, f.t, f.combo = "idle", 0, 0 end
  elseif st == "down" then
    f.vy = f.vy - GRAV
    f.y = math.max(0, f.y + f.vy)
    if f.y <= 0 then f.vy = 0 end
    if f.t > 52 then f.state, f.t = "getup", 0 end
  elseif st == "getup" then
    if f.t > 14 then f.state, f.t = "idle", 0 end
  elseif st == "ko" then
    f.vy = f.vy - GRAV
    f.y = math.max(0, f.y + f.vy)
    if f.y <= 0 then f.vy = 0 end
  end
  -- the ground and the walls
  f.x = f.x + f.vx
  if st == "hurt" or st == "blocked" or st == "down" or st == "ko" then f.vx = f.vx * 0.86 end
  f.x = math.max(-W.HALF, math.min(W.HALF, f.x))
end

-- two bodies do not overlap: the one that is pushing gives way (both, half each)
local function separate()
  local p, c = W.p, W.c
  local gap = (c.x - p.x)
  if math.abs(gap) < SEP and p.y < 6 and c.y < 6 then
    local push = (SEP - math.abs(gap)) / 2 * (gap >= 0 and 1 or -1)
    p.x, c.x = p.x - push, c.x + push
    p.x, c.x = math.max(-W.HALF, math.min(W.HALF, p.x)), math.max(-W.HALF, math.min(W.HALF, c.x))
  end
end

-- a fighter's fingers when a machine steers it: it looks at the distance and what the other is doing, and presses
local function think(f, o, a)
  local inp = {left = false, right = false, up = false, down = false, a = false, b = false, a_p = false, b_p = false}
  local d = (o.x - f.x) * f.face -- in front of it
  local dist = math.abs(o.x - f.x)
  a.t = a.t - 1
  -- seeing a blow coming: block it, as often as the level lets it
  local incoming = o.state == "attack" and o.move and o.t <= o.move.startup + 1 and dist < o.move.reach + 3
  if incoming and a.react_t ~= o.t and W.rng:chance(0.18 + 0.2 * W.diff) then
    a.act, a.t = "block", 14 + W.rng:int(0, 8)
    a.low = o.move.level == "low"
  end
  if a.t <= 0 and actionable(f) then
    local r = W.rng:float()
    local aggression = 0.5 + 0.18 * W.diff
    if dist > 15 then a.act, a.t = (r < 0.8) and "approach" or "wait", 8 + W.rng:int(0, 12)
    elseif dist > 9.5 then
      if r < 0.30 * aggression then a.act = "kick" elseif r < 0.42 * aggression then a.act = "jump" elseif r < 0.55 then a.act = "approach" else a.act = "wait" end
      a.t = 6 + W.rng:int(0, 10)
    else
      if r < 0.34 * aggression then a.act = "punch" elseif r < 0.5 * aggression then a.act = "kick" elseif r < 0.62 * aggression then a.act = "sweep"
      elseif r < 0.8 then a.act = "back" else a.act = "block" end
      a.t = 8 + W.rng:int(0, 14)
    end
  end
  local fwd, back = f.face == 1 and "right" or "left", f.face == 1 and "left" or "right"
  local act = a.act
  if act == "approach" then inp[fwd] = true
  elseif act == "back" then inp[back] = true
  elseif act == "block" then inp[back] = true inp.down = a.low or false
  elseif act == "jump" then inp.up, inp[fwd] = true, true a.act = "wait"
  elseif act == "punch" then inp.a_p = true a.act = "wait"
  elseif act == "kick" then inp.b_p = true a.act = "wait"
  elseif act == "sweep" then inp.down, inp.b_p = true, true a.act = "wait" end
  return inp
end

function W.ai_input() return think(W.c, W.p, W.ai) end
function W.ai_input_p() W.ai_p = W.ai_p or {t = 0, hold = 0} return think(W.p, W.c, W.ai_p) end

-- one tick. p_inp: the player's {left, right, up, down, a, b, a_p, b_p}
function W.update(p_inp)
  local p, c = W.p, W.c
  if W.phase == "intro" then
    W.phase_t = W.phase_t - 1
    if W.phase_t == INTRO_T - 50 then W.hook("round", W.round) end
    if W.phase_t <= 0 then W.phase = "fight" W.hook("fight") end
    step_fighter(p, c, {}) step_fighter(c, p, {})
    return
  end
  if W.phase == "fight" then
    W.timer = W.timer - 1
    if W.combo_t > 0 then W.combo_t = W.combo_t - 1 if W.combo_t == 0 then W.combo_p = 0 end end
    step_fighter(p, c, p_inp)
    step_fighter(c, p, W.ai_input())
    separate()
    if p.hits_taken == 0 then W.round_clean = true else W.round_clean = false end
    if p.hp <= 0 or c.hp <= 0 or W.timer <= 0 then
      W.phase, W.phase_t = "ko", KO_T
      local w = (p.hp > c.hp) and p or (c.hp > p.hp) and c or nil
      W.round_winner = w
      if w then w.wins = w.wins + 1 end
      W.hook("round_over", w, W.timer <= 0 and p.hp > 0 and c.hp > 0)
      if w then w.state, w.t, w.crouch = "win", 0, false end
    end
    return
  end
  if W.phase == "ko" then
    W.phase_t = W.phase_t - 1
    step_fighter(p, c, {}) step_fighter(c, p, {})
    if p.state == "win" or p.state == "idle" then p.vx = 0 end
    if W.phase_t <= 0 then
      if p.wins >= 2 or c.wins >= 2 then
        W.phase, W.winner = "match_over", (p.wins >= 2) and "p" or "c"
        W.hook("match_over", W.winner)
      else
        W.round = W.round + 1
        W.new_round()
      end
    end
  end
end

W.ROUND_T = ROUND_T
return W
