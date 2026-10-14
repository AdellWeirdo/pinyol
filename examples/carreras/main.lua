-- Carreras: a Mode 7 kart race on pinyol's virtual hardware (docs/lua.md).
--   BG2 is the circuit on an affine layer, seen in perspective from behind the kart (mode7);
--   BG3 is a strip of mountains on the horizon that turns with the camera;
--   the sky is a gradient on the backdrop; the rivals are sprites placed with project() and scaled by a matrix.

TRACK = require("track") -- global: tests jump to points of the circuit
local ROWS, WAY = TRACK.rows, TRACK.way
local N = #ROWS
local HORIZON, CAM_BACK, CAM_HEIGHT, FOV = 44, 34, 22, 150
local LAPS = 3

local sheets = {}
state = "count"        -- count, race, done
kart = {}              -- the player (global for tests)
rivals = {}
local timer, race_ticks = 0, 0
local finish_order = {}

local function surface(x, y) -- what is under a point of the map, in pixels
  local tx, ty = math.floor(x / 8), math.floor(y / 8)
  if tx < 0 or ty < 0 or tx >= N or ty >= N then return "." end
  return ROWS[ty + 1]:sub(tx + 1, tx + 1)
end

local function way_point(i) local p = WAY[(i - 1) % #WAY + 1]; return p[1] * 8, p[2] * 8 end

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

local function new_racer(sheet_id, offset, skill)
  local x, y = way_point(1)
  local nx, ny = way_point(2)
  local ang = math.deg(math.atan(nx - x, -(ny - y)))
  local side = math.rad(ang + 90)
  return {sheet = sheets[sheet_id], x = x + math.sin(side) * offset, y = y - math.cos(side) * offset - 6,
          angle = ang, speed = 0, way = 1, lap = 0, half = false, skill = skill, turn = 0, done = false}
end

local function start_race()
  kart = new_racer("KART_RED", -10, 0)
  rivals = {new_racer("KART_BLUE", 10, 0.96), new_racer("KART_GREEN", -4, 0.9), new_racer("KART_YELLOW", 4, 0.84)}
  for i, r in ipairs(rivals) do -- on the grid behind the player
    local ra = math.rad(r.angle)
    r.x, r.y = r.x - math.sin(ra) * 16 * i, r.y + math.cos(ra) * 16 * i
  end
  state, timer, race_ticks, finish_order = "count", 0, 0, {}
end

function _init()
  for _, id in ipairs({"KART_RED", "KART_BLUE", "KART_GREEN", "KART_YELLOW"}) do sheets[id] = sheet(id) end
  palette("OBJ", true)
  bg(2, {map = "TRACK", mode = "affine", prio = 1, wrap = false})
  bg(3, {map = "SKY", prio = 2})
  for y = 0, H - 1 do -- sky: pale at the horizon, deep blue above; below it, fields beyond the circuit's map
    local k = math.min(y / HORIZON, 1)
    line_backdrop(y, y <= HORIZON and rgb(70 + 120 * k, 120 + 100 * k, 210 + 30 * k) or rgb(60, 132, 56))
  end
  start_race()
end

local function drive(r, steer, gas, brake)
  local s = surface(r.x, r.y)
  local top = (s == "#" or s == "F") and 2.6 or s == "c" and 2.2 or s == "s" and 0.9 or 1.3
  if gas then r.speed = r.speed + 0.045 elseif brake then r.speed = r.speed - 0.1 end
  r.speed = r.speed * 0.99
  if r.speed > top then r.speed = math.max(top, r.speed - 0.08) end
  if r.speed < 0 then r.speed = 0 end
  r.turn = steer
  r.angle = r.angle + steer * 2.2 * math.min(r.speed / 1.5, 1)
  local a = math.rad(r.angle)
  r.x = math.max(0, math.min(N * 8 - 1, r.x + math.sin(a) * r.speed))
  r.y = math.max(0, math.min(N * 8 - 1, r.y - math.cos(a) * r.speed))
  -- laps: around the centreline, past its far half, then over the start again
  local w = nearest_way(r.x, r.y, r.way)
  if w > #WAY // 2 - 2 and w < #WAY // 2 + 2 then r.half = true end
  if r.half and w <= 2 and r.way >= #WAY - 2 then
    r.lap, r.half = r.lap + 1, false
    if r == kart and r.lap < LAPS then sfx("SFX_LAP") end
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
  local steer = diff > 4 and 1 or diff < -4 and -1 or 0
  drive(r, steer, r.speed < 2.6 * r.skill, false)
end

local function progress(r) return r.lap * 1000 + ((r.way - 1) % #WAY) end

function place() -- the player's position in the race
  local p = 1
  for _, r in ipairs(rivals) do if progress(r) > progress(kart) then p = p + 1 end end
  return p
end

function _update()
  timer = timer + 1
  if state == "count" then
    if timer % 60 == 1 and timer < 180 then sfx("SFX_COUNT") end
    if timer >= 180 then state = "race"; sfx("SFX_GO"); music("MUS_RACE") end
  elseif state == "race" then
    race_ticks = race_ticks + 1
    local steer = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    drive(kart, steer, btn("a"), btn("b"))
    for _, r in ipairs(rivals) do ai(r) end
    if kart.done then
      state, timer = "done", 0
      music()
      sfx("SFX_FINISH")
      local best = stored("best_race")
      if not best or race_ticks < best then store("best_race", race_ticks) end
    end
  elseif state == "done" then
    for _, r in ipairs(rivals) do ai(r) end
    if timer > 60 and btnp("a") then start_race() end
  end
end

function _draw()
  local a = math.rad(kart.angle)
  local cx, cy = kart.x - math.sin(a) * CAM_BACK, kart.y + math.cos(a) * CAM_BACK
  mode7(2, cx, cy, kart.angle, CAM_HEIGHT, HORIZON, FOV)
  scroll(3, kart.angle * 2, -(HORIZON - 40)) -- the mountains turn with the camera, sitting on the horizon

  spr_clear()
  local list = {}
  for _, r in ipairs(rivals) do
    local sx, sy, scale, vis = project(2, r.x, r.y)
    if vis then list[#list + 1] = {r = r, sx = sx, sy = sy, scale = scale} end
  end
  table.sort(list, function(p, q) return p.scale > q.scale end) -- the nearest drawn on top
  spr(0, kart.sheet, kart.turn < 0 and 1 or kart.turn > 0 and 2 or 0, W // 2 - 16, H - 30, prio(0))
  for i, it in ipairs(list) do
    if i > 30 then break end
    local s = math.min(it.scale * CAM_BACK / FOV, 1.9) -- 1 at the player's own distance from the camera
    mat(i, 0, s)
    spr(i, it.r.sheet, 0, it.sx - 16, it.sy - 8 * s - 8, prio(0) | spr_mat(i) | DOUBLE)
  end

  local secs = race_ticks / 60
  -- its own look: a scoreboard (fonts/marcador.fnt, gran.fnt) and a chequered flag (FR_META), made by art.py
  local board = {font = "marcador", color = 0xFFFFFF, outline = 0x101018}
  text(string.format("VUELTA %d/%d", math.min(kart.lap + 1, LAPS), LAPS), 12, 4, board)
  text(string.format("POS %d", place()), SCREEN_W // 2, 0, {font = "gran", align = "center", color = 0xFFE070,
                                                          gradient = 0xFF7A10, outline = 0x101018})
  board.align = "right"
  text(string.format("%d:%05.2f", math.floor(secs / 60), secs % 60), SCREEN_W - 12, 4, board)
  rect(12, SCREEN_H - 20, math.floor(kart.speed / 2.6 * 120), 8, 0xFFB040)
  box(12, SCREEN_H - 20, 120, 8, 0xFFFFFF)
  if state == "count" then
    local n = 3 - timer // 60
    text(n > 0 and tostring(n) or "¡YA!", SCREEN_W // 2, 96, {font = "gran", scale = 2, align = "center",
         color = 0xFFFFFF, gradient = 0xFFD040, outline = 0x101018, shadow = 0x000000, shadow_x = 2, shadow_y = 2})
  elseif state == "done" then
    frame("FR_META", 72, 84, 336, 132, 2)
    text(string.format("PUESTO %d", place()), SCREEN_W // 2, 100, {font = "gran", align = "center",
                                                                          color = 0xFFE070, outline = 0x101018})
    local best = stored("best_race")
    text(string.format("Tiempo %.2f s · mejor %.2f s", race_ticks / 60, (best or race_ticks) / 60), SCREEN_W // 2, 146,
         0xD0D8E8, "main", "center")
    if timer > 60 then text("A: OTRA CARRERA", SCREEN_W // 2, 172, 0xFF8060, "marcador", "center") end
  end
end
