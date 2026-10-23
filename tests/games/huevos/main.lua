-- Huevos: a game the way a pocket LCD game looked: every figure is a fixed shape printed on the screen that is either
-- on (black) or off (a faint ghost you can still see), over a picture printed in colour behind the glass; things move
-- a step at a time with a beep, faster as the score grows; the score in seven-segment digits. All drawn with
-- polygons: the glass, the printed picture and every ghost once on a canvas, then each frame only what is on.
-- Arrows: the cook holds the pan at one of four corners (left or right, up or down). Catch the eggs that roll down the
-- four ramps; three broken eggs and it is over.
local LCD, GHOST, ON = 0xBEC4AC, 0xAEB49C, 0x1E2418
local PANS = {{186, 150}, {186, 206}, {294, 150}, {294, 206}} -- top-left, bottom-left, top-right, bottom-right
local RAMPS = {{{70, 96}, {176, 140}}, {{70, 152}, {176, 196}}, {{410, 96}, {304, 140}}, {{410, 152}, {304, 196}}}
local STEPS = 5 -- egg positions on a ramp; the next is the pan

state, score, misses, pose = "title", 0, 0, 1 -- (global: tests/huevos.script)
eggs = {}
local t, tick_at, step_ticks, broken, chick = 0, 0, 30, nil, 0

-- ------------------------------------------------------------------ the shapes

local function egg_at(r, k) -- the k-th place of an egg on ramp r
  local a, b = RAMPS[r][1], RAMPS[r][2]
  return a[1] + (b[1] - a[1]) * (k - 1) / (STEPS - 1), a[2] + (b[2] - a[2]) * (k - 1) / (STEPS - 1) - 8
end

local function egg(x, y, c) circ(math.floor(x), math.floor(y), 6, c) circ(math.floor(x), math.floor(y) - 3, 5, c) end

local function cook(p, c) -- the cook, facing the side of the pan, and the pan at corner p
  local left, px, py = p <= 2, PANS[p][1], PANS[p][2]
  poly({222, 176, 258, 176, 266, 250, 214, 250}, c)                       -- the body
  circ(240, 156, 13, c)                                                   -- the head
  rect(228, 124, 24, 16, c) circ(240, 124, 9, c)                          -- the hat
  local sx = left and 226 or 254                                          -- the arm, to the pan
  poly({sx, 182, sx + (left and -4 or 4), 188, px + (left and 14 or -14), py + 4, px + (left and 16 or -16), py - 2}, c)
  rect(px - 18, py, 36, 6, c)                                             -- the pan
  rect(left and px + 18 or px - 30, py + 1, 12, 3, c)                     -- its handle
end

local function chick_at(side, k, c) -- a chick running off after an egg broke
  local x = side == 1 and 150 - k * 34 or 330 + k * 34
  circ(x, 278, 7, c) circ(x + (side == 1 and -6 or 6), 270, 5, c)
  rect(x - 3, 285, 2, 6, c) rect(x + 2, 285, 2, 6, c)
end

local function broken_egg(side, c)
  local x = side == 1 and 150 or 330
  poly({x - 14, 290, x + 14, 290, x + 10, 280, x + 4, 286, x - 2, 278, x - 8, 285}, c)
end

local SEG = {a = {2, 0, 14, 3}, b = {16, 2, 3, 14}, c = {16, 18, 3, 14}, d = {2, 32, 14, 3}, e = {-1, 18, 3, 14},
             f = {-1, 2, 3, 14}, g = {2, 16, 14, 3}}
local DIGIT = {[0] = "abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"}
local function digit(x, y, n, c) -- seven segments; n nil: all of them (the ghost)
  for s in (n and DIGIT[n] or "abcdefg"):gmatch(".") do local r = SEG[s] rect(x + r[1], y + r[2], r[3], r[4], c) end
end

local function glass() -- drawn once: the screen, the picture printed behind it, every figure as a ghost
  canvas("LCD", 480, 320)
  target("LCD")
  cls(LCD)
  rect(0, 298, 480, 22, 0x8C7A58) -- the printed picture: the floor, the hen houses, the ramps
  for r, ramp in ipairs(RAMPS) do
    local a, b = ramp[1], ramp[2]
    for w = 0, 3 do line(a[1], a[2] + w, b[1], b[2] + w, 0x9A6A3A) end
    local hx = a[1] < 240 and a[1] - 40 or a[1] + 10
    rect(hx, a[2] - 34, 30, 30, 0xC8A060) poly({hx - 4, a[2] - 34, hx + 15, a[2] - 50, hx + 34, a[2] - 34}, 0xA04030)
    circ(hx + 15, a[2] - 18, 8, 0xF0F0E0) circ(hx + 15 + (a[1] < 240 and 6 or -6), a[2] - 22, 3, 0xD03020)
  end
  for p = 1, 4 do cook(p, GHOST) end
  for r = 1, 4 do for k = 1, STEPS do local x, y = egg_at(r, k) egg(x, y, GHOST) end end
  for side = 1, 2 do broken_egg(side, GHOST) for k = 1, 3 do chick_at(side, k, GHOST) end end
  for i = 0, 3 do digit(200 + i * 22, 14, nil, GHOST) end
  for i = 1, 3 do circ(420 + i * 16, 26, 6, GHOST) end
  target()
end

-- ------------------------------------------------------------------ playing

function _init()
  show(0)
  glass()
  sound("SFX_STEP", {wave = "square", freq = 1760, sustain = 0.01, decay = 0.02, volume = 0.2})
  sound("SFX_CATCH", {wave = "square", freq = 2100, sustain = 0.03, decay = 0.05, volume = 0.25})
  sound("SFX_BREAK", {wave = "square", freq = 330, sustain = 0.25, decay = 0.1, volume = 0.3, vibrato = 0.5,
                      vibrato_speed = 12})
end

local function start()
  state, score, misses, eggs, broken, chick, step_ticks, tick_at = "play", 0, 0, {}, nil, 0, 30, t + 30
end

local function step() -- every egg rolls one place; one that reaches the end is caught, or breaks
  sfx("SFX_STEP")
  for i = #eggs, 1, -1 do
    local e = eggs[i]
    e.k = e.k + 1
    if e.k > STEPS then
      table.remove(eggs, i)
      if pose == e.r then
        score = score + 1
        sfx("SFX_CATCH")
      else
        misses, broken, chick = misses + 1, (e.r <= 2) and 1 or 2, 1
        sfx("SFX_BREAK")
        if misses >= 3 then state = "over" end
      end
    end
  end
  local busy = {}
  for _, e in ipairs(eggs) do busy[e.r * 10 + e.k] = true end
  if #eggs < 1 + score // 15 and math.random() < 0.55 then -- a new egg at the top of a ramp
    local r = math.random(4)
    if not busy[r * 10 + 1] then eggs[#eggs + 1] = {r = r, k = 1} end
  end
  step_ticks = math.max(10, 30 - score // 5)
end

function _update()
  t = t + 1
  local side = pose <= 2 and 1 or 2
  local low = pose == 2 or pose == 4
  if btn("left") then side = 1 elseif btn("right") then side = 2 end
  if btn("up") then low = false elseif btn("down") then low = true end
  pose = (side - 1) * 2 + (low and 2 or 1)
  if state == "title" or state == "over" then
    if btnp("a") or btnp("start") then start() end
    return
  end
  if chick > 0 then -- after an egg broke, the chick runs off and the game waits
    if t % 12 == 0 then chick = chick + 1 end
    if chick > 3 then chick, broken = 0, nil end
    return
  end
  if t >= tick_at then step() tick_at = t + step_ticks end
end

-- ------------------------------------------------------------------ drawing: only what is on

function _draw()
  img("LCD", 0, 0)
  cook(pose, ON)
  for _, e in ipairs(eggs) do local x, y = egg_at(e.r, e.k) egg(x, y, ON) end
  if broken then broken_egg(broken, ON) if chick > 0 then chick_at(broken, math.min(chick, 3), ON) end end
  local s = string.format("%04d", score % 10000)
  for i = 1, 4 do digit(200 + (i - 1) * 22, 14, tonumber(s:sub(i, i)), ON) end
  for i = 1, misses do circ(420 + i * 16, 26, 6, ON) end
  if state == "title" and (t // 30) % 2 == 0 then text("PULSA A", 240, 60, {font = "arcade", align = "center", color = ON}) end
  if state == "over" then text("FIN", 240, 60, {font = "arcade", align = "center", color = ON}) end
end
