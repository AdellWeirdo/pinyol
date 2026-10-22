-- Rocas: a game the way a vector arcade machine drew it: nothing but bright lines on black, every frame, at the
-- screen's full resolution, with a soft glow round each line (a dim copy one pixel to each side, then the line), even
-- the letters, made of strokes. No pictures at all.
-- Arrows: turn (left, right) and thrust (up). A fires, B jumps into hyperspace. Rocks split in two, then again.
local GLOW, LINE = 0x3070B0, 0xE0F8FF -- the glow, and the line's own colour
local SHIP = {{0, -12}, {8, 10}, {0, 5}, {-8, 10}}

state, score, lives, rocks, shots = "title", 0, 3, {}, {} -- (global: tests/rocas.script)
S = {}
local timer, wave, bursts = 0, 0, {}

-- ------------------------------------------------------------------ strokes

local function stroke(x0, y0, x1, y1, c) -- a line with its glow
  local g = GLOW
  line(x0 + 1, y0, x1 + 1, y1, g)
  line(x0, y0 + 1, x1, y1 + 1, g)
  line(x0, y0, x1, y1, c)
end

local function shape(pts, x, y, a, k, c) -- a closed shape turned by a and scaled by k, at x, y
  local ca, sa = math.cos(a), math.sin(a)
  local px, py
  for i = 1, #pts + 1 do
    local p = pts[(i - 1) % #pts + 1]
    local qx, qy = x + (p[1] * ca - p[2] * sa) * k, y + (p[1] * sa + p[2] * ca) * k
    if px then stroke(math.floor(px), math.floor(py), math.floor(qx), math.floor(qy), c or LINE) end
    px, py = qx, qy
  end
end

-- letters as strokes on a 4x6 grid: each pair of points a line
local FONT = {
  A = {0,6,0,2, 0,2,2,0, 2,0,4,2, 4,2,4,6, 0,3,4,3}, B = {0,0,0,6, 0,0,3,0, 3,0,4,1, 4,1,3,3, 0,3,3,3, 3,3,4,4, 4,4,4,5, 4,5,3,6, 3,6,0,6},
  C = {4,0,0,0, 0,0,0,6, 0,6,4,6}, D = {0,0,0,6, 0,0,3,0, 3,0,4,2, 4,2,4,4, 4,4,3,6, 3,6,0,6},
  E = {4,0,0,0, 0,0,0,6, 0,6,4,6, 0,3,3,3}, F = {4,0,0,0, 0,0,0,6, 0,3,3,3},
  G = {4,0,0,0, 0,0,0,6, 0,6,4,6, 4,6,4,3, 4,3,2,3}, H = {0,0,0,6, 4,0,4,6, 0,3,4,3},
  I = {0,0,4,0, 2,0,2,6, 0,6,4,6}, L = {0,0,0,6, 0,6,4,6}, M = {0,6,0,0, 0,0,2,2, 2,2,4,0, 4,0,4,6},
  N = {0,6,0,0, 0,0,4,6, 4,6,4,0}, O = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,6,0,0},
  P = {0,6,0,0, 0,0,4,0, 4,0,4,3, 4,3,0,3}, R = {0,6,0,0, 0,0,4,0, 4,0,4,3, 4,3,0,3, 1,3,4,6},
  S = {4,0,0,0, 0,0,0,3, 0,3,4,3, 4,3,4,6, 4,6,0,6}, T = {0,0,4,0, 2,0,2,6},
  U = {0,0,0,6, 0,6,4,6, 4,6,4,0}, V = {0,0,2,6, 2,6,4,0}, Z = {0,0,4,0, 4,0,0,6, 0,6,4,6},
  ["0"] = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,6,0,0}, ["1"] = {2,0,2,6}, ["2"] = {0,0,4,0, 4,0,4,3, 4,3,0,3, 0,3,0,6, 0,6,4,6},
  ["3"] = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,3,4,3}, ["4"] = {0,0,0,3, 0,3,4,3, 4,0,4,6},
  ["5"] = {4,0,0,0, 0,0,0,3, 0,3,4,3, 4,3,4,6, 4,6,0,6}, ["6"] = {4,0,0,0, 0,0,0,6, 0,6,4,6, 4,6,4,3, 4,3,0,3},
  ["7"] = {0,0,4,0, 4,0,4,6}, ["8"] = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,6,0,0, 0,3,4,3},
  ["9"] = {4,3,0,3, 0,3,0,0, 0,0,4,0, 4,0,4,6, 4,6,0,6},
}
local function say(s, cx, y, k) -- a line of letters, centred on cx, each 4k wide and 6k tall
  local x = cx - (#s * 6 - 2) * k // 2
  for ch in s:gmatch(".") do
    local g = FONT[ch]
    if g then for i = 1, #g, 4 do stroke(x + g[i] * k, y + g[i + 1] * k, x + g[i + 2] * k, y + g[i + 3] * k, LINE) end end
    x = x + 6 * k
  end
end

-- ------------------------------------------------------------------ playing

local function rock(x, y, size) -- a rough round shape of 9 to 12 corners, its own for each rock
  local pts, n = {}, 9 + math.random(3)
  for i = 1, n do
    local a, r = i / n * 2 * math.pi, size * (0.75 + math.random() * 0.35)
    pts[i] = {math.cos(a) * r, math.sin(a) * r}
  end
  local a = math.random() * 2 * math.pi
  return {x = x, y = y, vx = math.cos(a) * (2.6 - size / 20), vy = math.sin(a) * (2.6 - size / 20), size = size,
          pts = pts, a = 0, spin = (math.random() - 0.5) * 0.05}
end

local function next_wave()
  wave = wave + 1
  for i = 1, 3 + wave do
    local side = i % 2 == 0
    rocks[#rocks + 1] = rock(side and math.random(480) or 0, side and 0 or math.random(320), 32)
  end
end

local function new_ship() S = {x = 240, y = 160, vx = 0, vy = 0, a = 0, safe = 120, dead = 0} end

local function reset()
  score, lives, rocks, shots, bursts, wave = 0, 3, {}, {}, {}, 0
  new_ship()
  next_wave()
  state = "play"
end

local function wrap(o) o.x, o.y = o.x % 480, o.y % 320 end

local function burst(x, y, n)
  for i = 1, n do
    local a, v = math.random() * 2 * math.pi, 1 + math.random() * 2.5
    bursts[#bursts + 1] = {x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v, life = 20 + math.random(20)}
  end
end

function _init()
  show(0) -- no 240x160 world: only lines at the screen's resolution
  sound("SFX_FIRE", {wave = "square", freq = 1400, slide = -5000, sustain = 0.02, decay = 0.08, volume = 0.2})
  sound("SFX_BANG", {wave = "noise", freq = 300, slide = -400, sustain = 0.05, decay = 0.4, volume = 0.4})
  sound("SFX_SMALL", {wave = "noise", freq = 900, slide = -900, sustain = 0.02, decay = 0.2, volume = 0.3})
end

local function update_play()
  if S.dead > 0 then
    S.dead = S.dead + 1
    if S.dead > 90 then if lives > 0 then new_ship() else state, timer = "over", 0 end end
  else
    if btn("left") then S.a = S.a - 0.08 end
    if btn("right") then S.a = S.a + 0.08 end
    S.thrust = btn("up")
    if S.thrust then S.vx, S.vy = S.vx + math.sin(S.a) * 0.12, S.vy - math.cos(S.a) * 0.12 end
    S.vx, S.vy = S.vx * 0.99, S.vy * 0.99
    S.x, S.y = S.x + S.vx, S.y + S.vy
    wrap(S)
    if S.safe > 0 then S.safe = S.safe - 1 end
    if btnp("a") and #shots < 6 then
      shots[#shots + 1] = {x = S.x + math.sin(S.a) * 12, y = S.y - math.cos(S.a) * 12,
                           vx = S.vx + math.sin(S.a) * 6, vy = S.vy - math.cos(S.a) * 6, life = 50}
      sfx("SFX_FIRE")
    end
    if btnp("b") then S.x, S.y, S.vx, S.vy, S.safe = math.random(480), math.random(320), 0, 0, 30 end -- hyperspace
  end
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.x, s.y, s.life = s.x + s.vx, s.y + s.vy, s.life - 1
    wrap(s)
    if s.life <= 0 then table.remove(shots, i) end
  end
  for i = #rocks, 1, -1 do
    local r = rocks[i]
    r.x, r.y, r.a = r.x + r.vx, r.y + r.vy, r.a + r.spin
    wrap(r)
    local hit = false
    for j = #shots, 1, -1 do
      local s = shots[j]
      if (s.x - r.x) ^ 2 + (s.y - r.y) ^ 2 < r.size ^ 2 then hit = true table.remove(shots, j) break end
    end
    if hit then
      table.remove(rocks, i)
      score = score + (r.size > 30 and 20 or (r.size > 15 and 50 or 100))
      burst(r.x, r.y, r.size // 3)
      sfx(r.size > 15 and "SFX_BANG" or "SFX_SMALL")
      if r.size > 10 then for _ = 1, 2 do rocks[#rocks + 1] = rock(r.x, r.y, r.size // 2) end end
    elseif S.dead == 0 and S.safe == 0 and (S.x - r.x) ^ 2 + (S.y - r.y) ^ 2 < (r.size + 6) ^ 2 then
      S.dead, lives = 1, lives - 1
      burst(S.x, S.y, 30)
      sfx("SFX_BANG")
    end
  end
  if #rocks == 0 then next_wave() end
end

function _update()
  timer = timer + 1
  for i = #bursts, 1, -1 do
    local b = bursts[i]
    b.x, b.y, b.life = b.x + b.vx, b.y + b.vy, b.life - 1
    if b.life <= 0 then table.remove(bursts, i) end
  end
  if state == "title" then
    if #rocks == 0 then for _ = 1, 5 do rocks[#rocks + 1] = rock(math.random(480), math.random(320), 32) end end
    for _, r in ipairs(rocks) do r.x, r.y, r.a = r.x + r.vx, r.y + r.vy, r.a + r.spin wrap(r) end
    if btnp("a") or btnp("start") then reset() end
  elseif state == "play" then
    update_play()
  elseif state == "over" and timer > 60 and btnp("a") then
    rocks = {}
    state = "title"
  end
end

-- ------------------------------------------------------------------ drawing

function _draw()
  cls(0x000000)
  for _, r in ipairs(rocks) do shape(r.pts, r.x, r.y, r.a, 1) end
  for _, s in ipairs(shots) do stroke(math.floor(s.x), math.floor(s.y), math.floor(s.x + 1), math.floor(s.y + 1), LINE) end
  for _, b in ipairs(bursts) do pset(math.floor(b.x), math.floor(b.y), b.life > 12 and LINE or GLOW) end
  if state == "play" and S.dead == 0 and (S.safe == 0 or timer % 8 < 5) then
    shape(SHIP, S.x, S.y, S.a, 1)
    if S.thrust and timer % 4 < 2 then shape({{-4, 10}, {0, 18}, {4, 10}}, S.x, S.y, S.a, 1) end
  end
  if state == "title" then
    say("ROCAS", 240, 100, 8)
    if (timer // 30) % 2 == 0 then say("PULSA A", 240, 220, 3) end
  else
    say(tostring(score), 70, 14, 3)
    for i = 1, lives do shape(SHIP, 400 + i * 20, 26, 0, 0.8) end
    if state == "over" then say("FIN", 240, 130, 7) end
  end
end
