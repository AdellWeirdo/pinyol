-- Horizonte: un día entero sobre el mar. El arte usa muy pocos colores (el cielo es uno, el mar tres) y el juego los cambia línea a línea
-- con line_pal y line_pal_obj, como las consolas de antes escribían la paleta en cada HBlank: el cielo se oscurece hacia arriba,
-- las nubes se encienden abajo, el mar brilla donde está el sol y la vela del barco se pinta de atardecer.
--   Izquierda y derecha: la hora.   A: paleta por línea sí o no.   B: el brillo del agua.   START: pausa.
local I = require("index")
local ui = require("ui")

phase, per_line, shimmer, paused, hud = 0.18, true, true, false, true -- (globals: the tests look at them)

local KEYS = { -- the day, by p from 0 (noon) to 1 (night): the sky at the top and at the horizon, the cloud, the sea and the sun
  {0.00, top = {60, 135, 235}, hor = {175, 215, 250}, cloud = {255, 255, 255}, sea = {44, 108, 200}, sun = {255, 250, 205}},
  {0.45, top = {80, 120, 220}, hor = {250, 205, 150}, cloud = {255, 240, 225}, sea = {58, 100, 190}, sun = {255, 225, 140}},
  {0.60, top = {70, 55, 140}, hor = {255, 120, 70}, cloud = {255, 190, 150}, sea = {110, 70, 120}, sun = {255, 150, 80}},
  {0.78, top = {16, 18, 66}, hor = {110, 52, 112}, cloud = {170, 120, 150}, sea = {40, 36, 90}, sun = {255, 90, 50}},
  {1.00, top = {5, 8, 30}, hor = {22, 30, 86}, cloud = {90, 100, 150}, sea = {8, 18, 58}, sun = {255, 90, 50}},
}
local SKY_LINES, SEA_FROM, BOAT_H, SUN_R = 100, 100, 28, 20

local function lerp(a, b, k) return a + (b - a) * k end
local function mix(a, b, k) return {lerp(a[1], b[1], k), lerp(a[2], b[2], k), lerp(a[3], b[3], k)} end
local function col(c, f) f = f or 1 return rgb(math.min(255, math.floor(c[1] * f)), math.min(255, math.floor(c[2] * f)), math.min(255, math.floor(c[3] * f))) end

local function day(p) -- the colours at p: between the two keys it lies between
  for i = 1, #KEYS - 1 do
    local a, b = KEYS[i], KEYS[i + 1]
    if p <= b[1] then
      local k = (p - a[1]) / (b[1] - a[1])
      return {top = mix(a.top, b.top, k), hor = mix(a.hor, b.hor, k), cloud = mix(a.cloud, b.cloud, k), sea = mix(a.sea, b.sea, k), sun = mix(a.sun, b.sun, k)}
    end
  end
  return KEYS[#KEYS]
end

local boat_sh, sun_sh, time_
function _init()
  palette("WORLD")
  palette("OBJ", true)
  boat_sh, sun_sh = sheet("BOAT"), sheet("SUN")
  bg(3, {map = "SKY", prio = 3})
  bg(2, {map = "FRONT", prio = 1, wrap = false})
  backdrop(0)
  time_ = 0
end

local function sun_pos(p) -- the sun's centre, or nil once it is down
  if p > 0.66 then return nil end
  local k = p / 0.66
  return 36 + 150 * k, 100 - 76 * math.cos(k * math.pi / 2) + 0 * k -- up high at noon, on the horizon at the end
end

local function paint_flat(d)
  pal(I.bg.sky, col(mix(d.top, d.hor, 0.5)))
  pal(I.bg.cloud, col(d.cloud))
  pal(I.bg.shade, col(d.cloud, 0.85))
  pal(I.bg.hills, col(d.hor, 0.4))
  for i = 0, 2 do pal(I.bg.sea1 + i, col(d.sea, 0.92 + 0.08 * i)) end
  pal(I.obj.sail, col({245, 240, 230}), "obj")
  pal(I.obj.core, col(d.sun), "obj")
  pal(I.obj.glow1, col(d.sun, 0.9), "obj")
  pal(I.obj.glow2, col(d.sun, 0.75), "obj")
end

local function paint_lines(d, sx, sy, bx, by)
  for y = 0, SKY_LINES - 1 do
    local k = y / (SKY_LINES - 1)
    local sky = mix(d.top, d.hor, k ^ 1.5)
    local cloud = mix(d.cloud, d.hor, k * 0.55) -- the clouds are lit from below
    line_pal(y, I.bg.sky, col(sky), col(cloud), col(cloud, 0.82 - 0.1 * (1 - k)), col(mix(d.hor, {10, 12, 30}, 0.6)))
  end
  local sun_up = sx ~= nil
  for y = SEA_FROM, 159 do
    local depth = (y - SEA_FROM) / 59
    local c1, c2, c3 = col(d.sea, 0.92), col(d.sea, 1.0), col(d.sea, 1.08)
    if shimmer and sun_up then
      local glint = math.max(0, math.sin(y * 0.85 + time_ * 0.07)) * (1 - depth * 0.55) * math.min(1, (112 - sy) / 40 + 0.4)
      c1, c2, c3 = col(mix(d.sea, d.sun, glint * 0.7), 0.92), col(mix(d.sea, d.sun, glint * 0.85)), col(mix(d.sea, d.sun, glint * 0.55), 1.08)
    end
    line_pal(y, I.bg.sea1, c1, c2, c3)
  end
  for y = by, by + BOAT_H - 1 do -- the sail: lit by the sun's colour, darker towards the water
    local k = (y - by) / BOAT_H
    line_pal_obj(y, I.obj.sail, col(mix({250, 246, 238}, d.hor, 0.55 * (1 - k * 0.4)), 1 - 0.25 * k))
  end
  if sun_up then
    for y = math.max(0, sy - SUN_R), math.min(159, sy + SUN_R - 1) do -- the sun, redder as it goes down, a gradient of its own
      local k = (y - (sy - SUN_R)) / (2 * SUN_R)
      local c = mix(d.sun, {255, 70, 40}, k * (0.3 + 0.5 * (sy / 100)))
      line_pal_obj(y, I.obj.core, col(c), col(c, 0.92), col(c, 0.8))
    end
  end
end

function _update()
  if not paused then time_ = time_ + 1 end -- (a pause stops the waves and the clouds too)
  if btn("left") then phase = (phase - 0.006) % 2 elseif btn("right") then phase = (phase + 0.006) % 2 end
  if btnp("start") then paused = not paused end
  if btnp("a") then per_line = not per_line end
  if btnp("b") then shimmer = not shimmer end
  if not paused and not btn("left") and not btn("right") then phase = (phase + 0.00028) % 2 end
end

function _draw()
  local p = phase < 1 and phase or 2 - phase -- noon, then dusk, then night, and back
  local d = day(p)
  local sx, sy = sun_pos(p)
  local bx, by = 150, math.floor(112 + 2 * math.sin(time_ / 22))
  scroll(3, math.floor(time_ * 0.15), 0)
  if per_line then
    paint_lines(d, sx, sy and math.floor(sy), bx, by)
  else
    line_off()
    paint_flat(d)
  end
  spr(0, boat_sh, 0, bx, by, prio(0))
  if sx then spr(1, sun_sh, 0, math.floor(sx - SUN_R), math.floor(sy - SUN_R), prio(2)) else spr_off(1) end
  if hud then
    ui.box(8, 8, 330, 52)
    text(string.format("HORIZONTE   %s", p < 0.3 and "mediodía" or p < 0.7 and "atardecer" or "noche"), 18, 16, {font = "bold", color = ui.SEL})
    text(string.format("paleta por línea: %s   brillo: %s", per_line and "sí" or "no", shimmer and "sí" or "no"), 18, 38, {font = "main", color = ui.INK})
    text("izq/der: hora   A: paleta   B: brillo", 14, 296, {font = "main", color = 0xFFFFFF})
  end
end
