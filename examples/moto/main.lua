-- Moto costa: a motorbike race, the way a Neo Geo one looks, on two resolutions at once. The road is the 240x160
-- world's Mode 7 floor (carreras' circuit, BG2), doubled; over it, at the screen's full 480x320 from packed
-- pictures (art.py): the coast on the horizon turning with the camera, palms, barriers, boards, rocks and houses along
-- the road, the rivals (the same bike in other colours: img's pal) and the player's bike leaning into the bends.
-- A: throttle. B: brake.

TRACK = require("track") -- global: tests jump to points of the circuit
local ROWS, WAY = TRACK.rows, TRACK.way
local N = #ROWS
local HORIZON, CAM_BACK, CAM_HEIGHT, FOV = 44, 34, 22, 150
local LAPS = 3
local COAST_W = 1024
local PROPS = {palm = 0, barrier = 1, board = 2, rock = 3, house = 4}
local SIDE = 34                        -- how far from the centreline the roadside things stand (map pixels)

state = "count"        -- count, race, done (global: tests/moto.script)
bike = {}              -- the player
rivals = {}
local things = {}      -- roadside: {x, y, kind}
local timer, race_ticks = 0, 0
local finish_order = {}
local look = {}        -- img's options, filled again for each call

local function surface(x, y) -- what is under a point of the map, in pixels
  local tx, ty = math.floor(x / 8), math.floor(y / 8)
  if tx < 0 or ty < 0 or tx >= N or ty >= N then return "." end
  return ROWS[ty + 1]:sub(tx + 1, tx + 1)
end

local function way_point(i) local p = WAY[(i - 1) % #WAY + 1]; return p[1] * 8 + 4, p[2] * 8 + 4 end

local function nearest_way(x, y, from) -- the closest centreline point near the last one known
  local best, bi = 1e9, from
  for k = -3, 6 do
    local i = (from + k - 1) % #WAY + 1
    local px, py = way_point(i)
    local d = (px - x) ^ 2 + (py - y) ^ 2
    if d < best then best, bi = d, i end
  end
  return bi
end

local function new_racer(pal, offset, skill)
  local x, y = way_point(1)
  local nx, ny = way_point(2)
  local ang = math.deg(math.atan(nx - x, -(ny - y)))
  local side = math.rad(ang + 90)
  return {pal = pal, x = x + math.sin(side) * offset, y = y - math.cos(side) * offset - 6, angle = ang, speed = 0,
          way = 1, lap = 0, half = false, skill = skill, turn = 0, lean = 0, done = false}
end

local function start_race()
  bike = new_racer(nil, -8, 0)
  rivals = {new_racer("PAL_BLUE", 8, 0.97), new_racer("PAL_GREEN", -4, 0.91), new_racer("PAL_BLUE", 4, 0.86),
            new_racer("PAL_GREEN", 0, 0.8)}
  for i, r in ipairs(rivals) do -- on the grid behind the player
    local ra = math.rad(r.angle)
    r.x, r.y = r.x - math.sin(ra) * 14 * i, r.y + math.cos(ra) * 14 * i
  end
  state, timer, race_ticks, finish_order = "count", 0, 0, {}
end

function _init()
  bg(2, {map = "TRACK", mode = "affine", prio = 1, wrap = false})
  for y = 0, 159 do line_backdrop(y, y <= HORIZON and rgb(90, 160, 235) or rgb(70, 140, 60)) end
  -- the roadside: along the centreline, on both sides, the kinds in turn (not on the start straight's grid)
  local kinds = {"palm", "barrier", "palm", "board", "rock", "house", "palm", "barrier"}
  for i = 4, #WAY, 2 do
    local x, y = way_point(i)
    local nx, ny = way_point(i + 1)
    local a = math.atan(nx - x, -(ny - y))
    for s = -1, 1, 2 do
      local k = kinds[(i // 2 + (s > 0 and 3 or 0)) % #kinds + 1]
      local px, py = x + math.cos(a) * SIDE * s, y + math.sin(a) * SIDE * s
      if surface(px, py) == "." then things[#things + 1] = {x = px, y = py, kind = PROPS[k], way = i} end
    end
  end
  sound("SFX_COUNT", "blip", 3)
  sound("SFX_GO", "powerup", 4)
  sound("SFX_LAP", "coin", 2)
  sound("SFX_FINISH", "powerup", 9)
  start_race()
end

local function drive(r, steer, gas, brake)
  local s = surface(r.x, r.y)
  local top = (s == "#" or s == "F") and 3.0 or s == "c" and 2.5 or s == "s" and 1.0 or 1.4
  if gas then r.speed = r.speed + 0.05 elseif brake then r.speed = r.speed - 0.12 end
  r.speed = r.speed * 0.99
  if r.speed > top then r.speed = math.max(top, r.speed - 0.08) end
  if r.speed < 0 then r.speed = 0 end
  r.turn = steer
  r.lean = r.lean + (steer - r.lean) * 0.15 -- the body follows the bars, a little late
  r.angle = r.angle + steer * 2.0 * math.min(r.speed / 1.5, 1)
  local a = math.rad(r.angle)
  r.x = math.max(0, math.min(N * 8 - 1, r.x + math.sin(a) * r.speed))
  r.y = math.max(0, math.min(N * 8 - 1, r.y - math.cos(a) * r.speed))
  local w = nearest_way(r.x, r.y, r.way) -- laps: around the centreline, past its far half, then over the start again
  if w > #WAY // 2 - 2 and w < #WAY // 2 + 2 then r.half = true end
  if r.half and w <= 2 and r.way >= #WAY - 2 then
    r.lap, r.half = r.lap + 1, false
    if r == bike and r.lap < LAPS then sfx("SFX_LAP") end
    if r.lap >= LAPS and not r.done then
      r.done = true
      finish_order[#finish_order + 1] = r
    end
  end
  r.way = w
end

local function ai(r)
  local tx, ty = way_point(r.way + 3)
  local want = math.deg(math.atan(tx - r.x, -(ty - r.y)))
  local diff = (want - r.angle + 540) % 360 - 180
  drive(r, diff > 4 and 1 or diff < -4 and -1 or 0, r.speed < 3.0 * r.skill, false)
end

local function progress(r) return r.lap * 1000 + ((r.way - 1) % #WAY) end

function place() -- the player's position in the race
  local p = 1
  for _, r in ipairs(rivals) do if progress(r) > progress(bike) then p = p + 1 end end
  return p
end

function _update()
  timer = timer + 1
  if state == "count" then
    if timer % 60 == 1 and timer < 180 then sfx("SFX_COUNT") end
    if timer >= 180 then state = "race" sfx("SFX_GO") end
  elseif state == "race" then
    race_ticks = race_ticks + 1
    if autopilot then ai(bike) -- (tests and the console's benchmark: the rivals' driver rides the player's bike)
    else drive(bike, (btn("right") and 1 or 0) - (btn("left") and 1 or 0), btn("a"), btn("b")) end
    for _, r in ipairs(rivals) do ai(r) end
    if bike.done then state, timer = "done", 0 sfx("SFX_FINISH") end
  elseif state == "done" then
    for _, r in ipairs(rivals) do ai(r) end
    if timer > 60 and btnp("a") then start_race() end
  end
end

-- ------------------------------------------------------------------ drawing

local MIRROR = {flip_x = true}
local list = {}

local n = 0 -- how many of list are in view this frame (its tables kept from frame to frame)

local function seen(sx, sy, scale, thing, racer)
  n = n + 1
  local it = list[n] or {}
  it.sx, it.sy, it.scale, it.thing, it.racer = sx, sy, scale, thing, racer
  list[n] = it
end

local function lean_frame(l) return l < -0.6 and 0 or l < -0.2 and 1 or l > 0.6 and 4 or l > 0.2 and 3 or 2 end

function _draw()
  local a = math.rad(bike.angle)
  local cx, cy = bike.x - math.sin(a) * CAM_BACK, bike.y + math.cos(a) * CAM_BACK
  mode7(2, cx, cy, bike.angle, CAM_HEIGHT, HORIZON, FOV)

  local x = -(bike.angle * 6) % (2 * COAST_W) -- the coast turns with the camera, every other copy mirrored
  if not nocoast then
    for k = -2, 1 do
      local cx0 = x + k * COAST_W
      if cx0 < 480 and cx0 + COAST_W > 0 then
        if k % 2 == 0 then img("BG_COAST", cx0, 2 * HORIZON - 112) else img("BG_COAST", cx0, 2 * HORIZON - 112, MIRROR) end
      end
    end
  end

  n = 0 -- what is in view, far first: the roadside near the bike's part of the circuit, and the rivals
  if not noprops then
    for _, t in ipairs(things) do
      local ahead = (t.way - bike.way) % #WAY -- only those a little behind to well ahead along the circuit
      if ahead < 40 or ahead > #WAY - 4 then
        local sx, sy, scale, vis = project(2, t.x, t.y)
        if vis and scale > 0.12 then seen(sx, sy, scale, t, nil) end
      end
    end
  end
  for _, r in ipairs(rivals) do
    local sx, sy, scale, vis = project(2, r.x, r.y)
    if vis then seen(sx, sy, scale, nil, r) end
  end
  for i = 2, n do -- far first (by insertion: a handful, and already nearly in order from the last frame)
    local it, j = list[i], i - 1
    while j >= 1 and list[j].scale > it.scale do list[j + 1] = list[j] j = j - 1 end
    list[j + 1] = it
  end
  for i = 1, n do
    local it = list[i]
    local s = it.scale * CAM_BACK / FOV -- 1 at the player's own distance from the camera
    if it.thing then
      local k = math.min(s * 0.9, 2.5)
      look.frame, look.scale, look.pal = it.thing.kind, k, nil
      img("SPR_PROPS", it.sx * 2 - 96 * k, it.sy * 2 - 199 * k, look)
    else
      local k = math.min(s * 0.85, 2)
      look.frame, look.scale, look.pal = lean_frame(it.racer.lean), k, it.racer.pal
      img("SPR_BIKE", it.sx * 2 - 64 * k, it.sy * 2 - 127 * k, look)
    end
  end
  look.scale, look.pal = nil, nil
  look.frame = lean_frame(bike.lean)
  img("SPR_BIKE", 240 - 64, 318 - 127, look)

  local secs = race_ticks / 60
  local board = {font = "marcador", color = 0xFFFFFF, outline = 0x101018}
  text(string.format("VUELTA %d/%d", math.min(bike.lap + 1, LAPS), LAPS), 12, 4, board)
  text(string.format("POS %d", place()), 240, 0, {font = "gran", align = "center", color = 0xFFE070,
                                                 gradient = 0xFF7A10, outline = 0x101018})
  board.align = "right"
  text(string.format("%d:%05.2f", math.floor(secs / 60), secs % 60), 468, 4, board)
  rect(12, 300, math.floor(bike.speed / 3 * 120), 8, 0xFFB040)
  box(12, 300, 120, 8, 0xFFFFFF)
  if state == "count" then
    local c = 3 - timer // 60
    text(c > 0 and tostring(c) or "¡YA!", 240, 120, {font = "gran", scale = 2, align = "center", color = 0xFFFFFF,
                                                     gradient = 0xFFD040, outline = 0x101018})
  elseif state == "done" then
    text(string.format("PUESTO %d", place()), 240, 120, {font = "gran", scale = 2, align = "center", color = 0xFFE070,
                                                        gradient = 0xFF7A10, outline = 0x101018})
    if timer > 60 then text("A: OTRA CARRERA", 240, 170, {font = "marcador", align = "center", color = 0xFF8060}) end
  end
end
