-- world: the rules. The player walks with tank controls (left and right turn, up walks, down backs away, B runs while the breath lasts) with a torch
-- that lights a cone ahead. The Figure follows at a walk that quickens, stops dead while the light is on it, and turns away if the light stays; it
-- cannot be fought. Find the key on the bench in the plaza, bring it to the lighthouse's door. Nothing here draws.
local Level = require("level")
local rng = require("rng")
local W = {}

local R = 3            -- the player's body, as a radius
local TURN = 3.0       -- degrees a tick
local WALK, RUN, BACK = 0.30, 0.62, 0.14
local CONE, RANGE = 26, 78 -- the torch: half the angle of its cone, how far it reaches

function W.new(seed)
  W.rng = rng.new(seed or 1)
  local st = Level.START
  W.t, W.won, W.caught_t, W.deaths = 0, false, 0, W.deaths or 0
  W.p = {x = st.x, z = st.z, h = st.heading, phase = 0, moving = false, running = false, breath = 1, tired = false, key = false, steps = 0}
  W.check = {x = st.x, z = st.z, h = st.heading}
  W.f = {state = "away", x = 0, z = 0, h = 0, phase = 0, wait = 600, lit_t = 0, lit = false, speed = 0}
  W.key_taken, W.danger, W.lit_ever = false, 0, false
  W.msg = nil
  W.hook = W.hook or function() end
end

local function norm(a) a = a % 360 return a > 180 and a - 360 or a end
local function angle_to(fx, fz, tx, tz) return math.deg(math.atan(tx - fx, tz - fz)) end -- as a heading: forward = (sin, cos)

local function blocked(x, z)
  if math.abs(x) > Level.HALF or z < -58 or (not W.won and z > Level.DOOR.z - 9) then return true end
  for _, s in ipairs(Level.solids) do
    if math.abs(x - s.x) < s.w / 2 + R and math.abs(z - s.z) < s.d / 2 + R then return true end
  end
  return false
end

local function move(p, dx, dz)
  if not blocked(p.x + dx, p.z) then p.x = p.x + dx end
  if not blocked(p.x, p.z + dz) then p.z = p.z + dz end
end

-- is the Figure in the torch's cone
local function in_beam()
  local p, f = W.p, W.f
  local d = math.sqrt((f.x - p.x) ^ 2 + (f.z - p.z) ^ 2)
  if d > RANGE or d < 1 then return false, d end
  return math.abs(norm(angle_to(p.x, p.z, f.x, f.z) - p.h)) < CONE, d
end

local function spawn_figure()
  local p, f = W.p, W.f
  for _ = 1, 12 do -- behind the player, out of the beam, inside the street
    local a = math.rad(p.h + 180 + (W.rng:float() - 0.5) * 110)
    local x, z = p.x + math.sin(a) * 95, p.z + math.cos(a) * 95
    if math.abs(x) <= Level.HALF and z > -56 and z < Level.DOOR.z - 20 then
      f.x, f.z, f.h, f.state, f.lit_t = x, z, angle_to(x, z, p.x, p.z), "stalk", 0
      W.hook("figure")
      return
    end
  end
  f.wait = 120 -- nowhere to stand: a little later
end

function W.say(key) W.msg = {key = key, t = 260} end

-- the lamps that stutter: mostly on, with brief dropouts
local function flicker()
  local ph = W.t % 170
  W.flick = (ph > 20 and ph < 25 or ph > 31 and ph < 34 or ph > 95 and ph < 97) and 0.1 or 1
end

-- the title and the menu: time passes, the lamps flicker, nobody moves
function W.idle() W.t = W.t + 1 flicker() end

-- inp = {turn = -1..1, walk = -1..1, run = held, act = pressed}
function W.update(inp)
  local p, f = W.p, W.f
  W.t = W.t + 1
  flicker()
  if W.msg then W.msg.t = W.msg.t - 1 if W.msg.t <= 0 then W.msg = nil end end
  if W.caught_t > 0 then
    W.caught_t = W.caught_t - 1
    if W.caught_t == 0 then -- back at the last cut, the key still in hand
      p.x, p.z, p.h, p.phase, p.breath, p.tired = W.check.x, W.check.z, W.check.h, 0, 1, false
      f.state, f.wait, f.lit_t = "away", 900, 0
    end
    return
  end
  if W.won then return end
  -- walking
  p.h = (p.h + (inp.turn or 0) * TURN) % 360
  local walk = inp.walk or 0
  p.running = inp.run and walk > 0 and not p.tired and p.breath > 0
  local speed = walk > 0 and (p.running and RUN or WALK) or walk < 0 and -BACK or 0
  local r = math.rad(p.h)
  if speed ~= 0 then
    move(p, math.sin(r) * speed, math.cos(r) * speed)
    p.phase = p.phase + math.abs(speed) * 0.42
  end
  p.moving = speed ~= 0
  if p.running then
    p.breath = math.max(0, p.breath - 0.0055)
    if p.breath <= 0 then p.tired = true W.hook("winded") end
    if p.breath < 0.9 and not W.ran then W.ran = true W.hook("ran") end
  else
    p.breath = math.min(1, p.breath + (p.moving and 0.0022 or 0.0045))
    if p.tired and p.breath > 0.3 then p.tired = false end
  end
  -- the key and the door
  local near_key = not W.key_taken and math.sqrt((p.x - Level.KEY.x) ^ 2 + (p.z - Level.KEY.z) ^ 2) < 14
  local d = Level.DOOR
  local near_door = math.abs(p.x - d.x) < d.w / 2 + 4 and p.z > d.z - 22
  W.prompt = near_key and "take_key" or near_door and (p.key and "open_door" or "locked") or nil
  if inp.act and W.prompt == "take_key" then W.key_taken, p.key = true, true W.hook("key") W.say("got_key")
  elseif inp.act and W.prompt == "locked" then W.say("locked") W.hook("locked")
  elseif inp.act and W.prompt == "open_door" then W.won = true W.hook("door") end
  -- the cut: where the player is decides the camera; coming into a new stretch is a checkpoint
  W.new_cam = nil
  -- the Figure
  local lit, dist = false, 999
  if f.state == "away" then
    f.wait = f.wait - 1
    if f.wait <= 0 and p.z > 30 then spawn_figure() end
    W.danger = 0
  else
    lit, dist = in_beam()
    f.lit = lit
    local pace = math.min(0.44, 0.2 + W.t * 0.00005)
    if lit then
      f.lit_t, f.speed = f.lit_t + 1, 0
      if f.lit_t == 20 then W.hook("lit") end
      if f.lit_t > 75 then -- it turns away into the fog for a while
        f.state, f.wait = "away", 700
        W.hook("repelled")
      end
    else
      f.lit_t = math.max(0, f.lit_t - 2)
      f.speed = f.speed + (pace - f.speed) * 0.1
      f.h = angle_to(f.x, f.z, p.x, p.z)
      local fr = math.rad(f.h)
      f.x, f.z = f.x + math.sin(fr) * f.speed, f.z + math.cos(fr) * f.speed
      f.phase = f.phase + f.speed * 0.5
    end
    if dist < 6.5 and f.state ~= "away" then
      W.deaths = W.deaths + 1
      W.caught_t = 150
      W.hook("caught")
    end
    W.danger = f.state == "away" and 0 or math.max(0, 1 - dist / 120) ^ 1.4
  end
end

-- the cone's numbers, for the picture
W.CONE, W.RANGE = CONE, RANGE

return W
