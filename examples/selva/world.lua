-- world: the rules. The fox runs on by itself along +z; the player steers it, makes it jump (and stomp crates), and spins it. Crates break
-- when landed on or spun into, fruit is picked up by touch, a pit swallows what runs over it, spikes cost a life. What lies ahead is made
-- a stretch at a time from a seeded stream, so a run can be played again the same. Nothing here draws.
local rng = require("rng")
local W = {}

W.HALF = 38           -- how far to the side the fox's middle may go
local CRATE, TOP = 13, 18 -- a crate: half a width of touch, its top
local BUFFER, COYOTE = 7, 6   -- ticks a jump pressed too early waits for the ground; ticks the pit's edge still holds the fox
local LANES = {-24, 0, 24}

local function clamp(v, a, b) return v < a and a or v > b and b or v end

function W.new(seed)
  W.rng = rng.new(seed or 7)
  W.fox = {x = 0, y = 0, vy = 0, vx = 0, z = 112, spin = 0, spin_t = 0, phase = 0, lean = 0, blink = 0, bump = 0, state = "run", fall_t = 0,
           buffer = 0, coyote = COYOTE, cut = false, landed = 0}
  W.items, W.next_z = {}, 260
  W.dist, W.fruit, W.lives, W.combo, W.best_combo, W.crates, W.speed, W.t, W.over = 0, 0, 3, 0, 0, 0, 2.4, 0, false
  W.streak_t, W.streak = 0, 0 -- fruit picked in quick succession (the pitch of the sound climbs)
  W.hook = W.hook or function() end
  W.spawn_to(700)
end

local function add(k, x, z, y) W.items[#W.items + 1] = {k = k, x = x, z = z, y = y or 0, alive = true} end

-- one stretch of the way, a pattern chosen by how far the run has got; returns its length
local function chunk(z)
  local r = W.rng
  local hard = clamp(W.dist / 3000, 0, 1)
  local pick = r:int(1, hard < 0.15 and 3 or hard < 0.5 and 5 or 6)
  if pick == 1 then -- a line of fruit down a lane
    local x = r:pick(LANES)
    for i = 0, 5 do add("fruit", x, z + i * 14, 4) end
    return 100
  elseif pick == 2 then -- a crate on each lane but one (fruit in the free lane)
    local free = r:int(1, 3)
    for i, x in ipairs(LANES) do
      if i ~= free then add("crate", x, z) end
    end
    for i = 0, 3 do add("fruit", LANES[free], z - 12 + i * 12, 4) end
    return 90
  elseif pick == 3 then -- a crate with fruit hanging over it: land on it
    local x = r:pick(LANES)
    add("crate", x, z + 20)
    add("fruit", x, z + 20, 34)
    for i = 0, 2 do add("fruit", x, z + 50 + i * 12, 4) end
    return 90
  elseif pick == 4 then -- a pit across the way, fruit in an arc over it
    add("pit", 0, z + 10)
    for i = 0, 4 do add("fruit", 0, z + 12 + i * 8, 6 + 26 * math.sin(math.pi * i / 4)) end
    return 110
  elseif pick == 5 then -- spikes on two lanes, fruit between
    local a, b = r:int(1, 3), r:int(1, 3)
    add("spike", LANES[a], z + 20); if b ~= a then add("spike", LANES[b], z + 50) end
    for i = 0, 4 do add("fruit", LANES[(a % 3) + 1], z + 6 + i * 14, 4) end
    return 100
  else -- a slalom of crates
    for i = 0, 3 do add("crate", i % 2 == 0 and -20 or 20, z + i * 34) end
    for i = 0, 3 do add("fruit", i % 2 == 0 and 20 or -20, z + i * 34 + 17, 4) end
    return 130
  end
end

-- more way ahead: a stretch at a time, its things put in order of z (the rules and the drawing then look only at what is near)
function W.spawn_to(z)
  while W.next_z < z do
    local first = #W.items + 1
    W.next_z = W.next_z + chunk(W.next_z) + 40
    local new = {}
    for i = first, #W.items do new[#new + 1] = W.items[i] end
    table.sort(new, function(a, b) return a.z < b.z end)
    for i, it in ipairs(new) do W.items[first + i - 1] = it end
  end
end

local function lose_life(why)
  local f = W.fox
  W.lives = W.lives - 1
  W.hook(why)
  if W.lives <= 0 then
    W.over, f.state = true, "dead"
    W.hook("over")
    return
  end
  f.blink, f.bump = 100, 0
  if why == "fall" then -- back on the way, a little before the pit
    local back = f.z - 50
    for _, it in ipairs(W.items) do if it.k == "pit" and it.z <= f.z and it.z + 40 >= f.z - 30 then back = math.min(back, it.z - 30) end end
    f.z, f.x, f.y, f.vy, f.state = back, 0, 0, 0, "run"
  else
    f.vy, f.coyote = 3.6, 0 -- a hop out of the spikes
  end
end

local function over_pit(f)
  for _, it in ipairs(W.items) do
    if it.k == "pit" and f.z > it.z + 2 and f.z < it.z + 38 then return true end
  end
  return false
end

-- inp = {dx = -1..1, jump = pressed, hold = held (a short press makes a short jump), spin = pressed}
function W.update(inp)
  local f = W.fox
  W.t = W.t + 1
  if f.blink > 0 then f.blink = f.blink - 1 end
  if W.over then return end
  if f.state == "fall" then
    f.vy, f.lean = f.vy - 0.32, 0
    f.y = f.y + f.vy
    f.fall_t = f.fall_t + 1
    if f.y < -70 then lose_life("fall") end
    return
  end
  -- on: faster the further it has got, slower while it is bumped
  local target = 2.4 + math.min(1.3, W.dist / 5000)
  if f.bump > 0 then f.bump = f.bump - 1; W.speed = 0.5 else W.speed = W.speed + (target - W.speed) * 0.08 end
  f.z, W.dist = f.z + W.speed, W.dist + W.speed
  local dx = inp.dx or 0
  f.vx = f.vx + (dx * 2.1 - f.vx) * 0.28 -- the sideways speed eases in and out
  f.x = clamp(f.x + f.vx, -W.HALF, W.HALF)
  if math.abs(f.x) >= W.HALF then f.vx = 0 end
  f.lean = f.lean + (f.vx * -7 - f.lean) * 0.2
  f.phase = f.phase + W.speed * 0.16
  if f.landed > 0 then f.landed = f.landed - 1 end
  local was_air = f.y > 0.01
  W.streak_t = W.streak_t > 0 and W.streak_t - 1 or 0
  if W.streak_t == 0 then W.streak = 0 end
  -- jump and gravity: a press a little early is kept, a little late still counts (the ground just ended), a short press cuts the jump
  if inp.jump then f.buffer = BUFFER elseif f.buffer > 0 then f.buffer = f.buffer - 1 end
  local grounded = (f.y <= 0 and f.vy <= 0) or f.coyote > 0 and f.vy <= 0
  if f.buffer > 0 and grounded then
    f.vy, f.buffer, f.coyote, f.cut = 5.2, 0, 0, false
    W.hook("jump")
  end
  if f.vy > 2.2 and not inp.hold and not f.cut and f.y > 0 then f.vy, f.cut = f.vy * 0.55, true end
  f.vy = f.vy - 0.28
  f.y = f.y + f.vy
  -- spin
  if inp.spin and f.spin_t == 0 then f.spin_t = 24; W.hook("spin") end
  if f.spin_t > 0 then
    f.spin_t = f.spin_t - 1
    f.spin = f.spin_t == 0 and 0 or (24 - f.spin_t) / 24 * 720
  end
  -- things on the way
  for _, it in ipairs(W.items) do
    if it.z > f.z + 40 then break end -- (in order of z: nothing further on is within reach)
    if it.alive and it.z > f.z - 40 then
      local ax, az = math.abs(f.x - it.x), math.abs(f.z - it.z)
      if it.k == "fruit" then
        if ax < 11 and az < 10 and math.abs(f.y + 8 - it.y) < 16 then
          it.alive = false
          W.fruit = W.fruit + 1
          W.streak, W.streak_t = W.streak + 1, 45
          W.hook("fruit", it)
        end
      elseif it.k == "crate" and ax < CRATE and az < CRATE then
        if f.vy < 0 and f.y >= TOP - 6 then -- landed on it: a higher bounce while A is held
          it.alive, f.vy, f.cut, f.coyote = false, inp.hold and 5.6 or 4.2, false, 0
          W.crates, W.combo = W.crates + 1, W.combo + 1
          W.best_combo = math.max(W.best_combo, W.combo)
          W.fruit = W.fruit + 1
          W.hook("crate", it); W.hook("stomp", it)
        elseif f.spin_t > 0 then
          it.alive = false
          W.crates = W.crates + 1
          W.fruit = W.fruit + 1
          W.hook("crate", it)
        elseif f.y < TOP - 4 then -- run into it
          f.z, f.bump = it.z - CRATE, 16
          W.hook("bump", it)
        end
      elseif it.k == "spike" and ax < 15 and math.abs(f.z - (it.z + 7)) < 10 and f.y < 6 and f.blink == 0 then
        lose_life("hurt")
        if W.over then return end
      end
    end
  end
  -- the ground, or no ground over a pit (the edge holds a moment: the coyote's time)
  if f.y <= 0 then
    if f.vy <= 0 and over_pit(f) then
      f.coyote = f.coyote - 1
      if f.coyote < 0 then
        f.state, f.fall_t = "fall", 0
        W.hook("falling")
        return
      end
      f.y = 0
    else
      if was_air then f.landed = 8; W.hook("land") end
      f.y, f.vy, f.coyote = 0, 0, COYOTE
      W.combo = 0
    end
  end
  -- more way ahead, less behind
  W.spawn_to(f.z + 560)
  while W.items[1] and W.items[1].z < f.z - 90 do table.remove(W.items, 1) end
end

-- what an attract-mode player presses: after the fruit, over pits, onto crates, round spikes
function W.ai_input()
  local f = W.fox
  local want, jump = nil, false
  local avoid
  for _, it in ipairs(W.items) do
    local d = it.z - f.z
    if d > 120 then break end
    if it.alive and d > -6 then
      if it.k == "fruit" and not want and d < 100 and it.y < 12 then want = it.x end
      if it.k == "pit" and d < 52 and d > -36 then jump = true end
      if (it.k == "spike" or it.k == "crate") and d > 0 and d < 56 and math.abs(it.x - f.x) < 22 then avoid = it end
    end
  end
  if avoid then
    if avoid.k == "crate" and avoid.z - f.z < 34 then jump = true end -- onto it
    if avoid.k == "spike" or avoid.z - f.z > 34 then want = avoid.x <= f.x and 24 or -24 end
    if avoid.k == "crate" and avoid.z - f.z < 34 then want = avoid.x end
  end
  local dx = 0
  if want then dx = clamp((want - f.x) / 8, -1, 1) end
  jump = jump and f.y <= 0
  return {dx = dx, jump = jump, hold = jump or f.vy > 0.5, spin = false}
end

return W
