-- Horizonte: un día entero sobre el mar. El arte usa muy pocos colores (el cielo es uno, el mar tres) y el juego los cambia línea a línea
-- con line_pal y line_pal_obj, como las consolas de antes escribían la paleta en cada HBlank: el cielo se oscurece hacia arriba,
-- las nubes se encienden abajo, el mar brilla donde está el sol y la vela del barco se pinta de atardecer.
--   Izquierda y derecha: la hora.   A: paleta por línea sí o no.   B: el brillo del agua.   START: pausa.
local I = require("index")
local ui = require("ui")

phase, per_line, shimmer, paused, hud = 0.18, true, true, false, true -- (globals: the tests look at them)

-- The day, by p from 0 (noon) to 1 (night): each key is p and then fifteen numbers: the sky at the top (r, g, b), at the horizon, the cloud, the sea, the sun.
-- Everything here is numbers in tables made once, and the gradients are line_ramp: a table made, or a call into C, for each of the
-- hundred and sixty lines every frame is what the console cannot keep up with (the first horizonte ran at 14 fps for it).
local KEYS = {
  {0.00, 60, 135, 235, 175, 215, 250, 255, 255, 255, 44, 108, 200, 255, 250, 205},
  {0.45, 80, 120, 220, 250, 205, 150, 255, 240, 225, 58, 100, 190, 255, 225, 140},
  {0.60, 70, 55, 140, 255, 120, 70, 255, 190, 150, 110, 70, 120, 255, 150, 80},
  {0.78, 16, 18, 66, 110, 52, 112, 170, 120, 150, 40, 36, 90, 255, 90, 50},
  {1.00, 5, 8, 30, 22, 30, 86, 90, 100, 150, 8, 18, 58, 255, 90, 50},
}
local SKY_LINES, SEA_FROM, BOAT_H, SUN_R = 100, 100, 28, 20
local D = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0} -- the colours at this p: filled in place by day()
local floor, min, sin, sqrt = math.floor, math.min, math.sin, math.sqrt

local pk = rgb -- (a colour from numbers: none of the mixes here goes past 255, and rgb takes the fractions: one call, not seven)

local function day(p)
  local a, b = KEYS[#KEYS - 1], KEYS[#KEYS]
  for i = 1, #KEYS - 1 do
    if p <= KEYS[i + 1][1] then a, b = KEYS[i], KEYS[i + 1] break end
  end
  local k = (p - a[1]) / (b[1] - a[1])
  for j = 1, 15 do D[j] = a[j + 1] + (b[j + 1] - a[j + 1]) * k end
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
  return 36 + 150 * k, 100 - 76 * math.cos(k * math.pi / 2) -- up high at noon, on the horizon at the end
end

local function paint_flat()
  pal(I.bg.sky, pk((D[1] + D[4]) / 2, (D[2] + D[5]) / 2, (D[3] + D[6]) / 2))
  pal(I.bg.cloud, pk(D[7], D[8], D[9]))
  pal(I.bg.shade, pk(D[7] * 0.85, D[8] * 0.85, D[9] * 0.85))
  pal(I.bg.hills, pk(D[4] * 0.4, D[5] * 0.4, D[6] * 0.4))
  for i = 0, 2 do
    local f = 0.92 + 0.08 * i
    pal(I.bg.sea1 + i, pk(D[10] * f, D[11] * f, D[12] * f))
  end
  pal(I.obj.sail, rgb(245, 240, 230), "obj")
  pal(I.obj.core, pk(D[13], D[14], D[15]), "obj")
  pal(I.obj.glow1, pk(D[13] * 0.9, D[14] * 0.9, D[15] * 0.9), "obj")
  pal(I.obj.glow2, pk(D[13] * 0.75, D[14] * 0.75, D[15] * 0.75), "obj")
end

-- the sky and its clouds and hills, each a ramp of one palette entry down the hundred lines of the sky (line_ramp: one call each)
local function paint_sky()
  local tr, tg, tb, hr, hg, hb, cr, cg, cb = D[1], D[2], D[3], D[4], D[5], D[6], D[7], D[8], D[9]
  local last = SKY_LINES - 1
  line_ramp(0, last, I.bg.sky, pk(tr, tg, tb), pk(hr, hg, hb), 1.5)
  local lr, lg, lb = cr + (hr - cr) * 0.55, cg + (hg - cg) * 0.55, cb + (hb - cb) * 0.55 -- the clouds are lit from below
  line_ramp(0, last, I.bg.cloud, pk(cr, cg, cb), pk(lr, lg, lb))
  line_ramp(0, last, I.bg.shade, pk(cr * 0.72, cg * 0.72, cb * 0.72), pk(lr * 0.82, lg * 0.82, lb * 0.82))
  local hill = pk(hr * 0.4 + 6, hg * 0.4 + 7, hb * 0.4 + 18)
  line_ramp(0, last, I.bg.hills, hill, hill)
end

local function paint_sea(sun_up, sy)
  local sr, sg, sb, nr, ng, nb = D[10], D[11], D[12], D[13], D[14], D[15]
  local up = shimmer and sun_up
  local reach = up and min(1, (112 - sy) / 40 + 0.4) or 0
  for y = SEA_FROM, 159 do
    local depth = (y - SEA_FROM) / 59
    local glint = up and math.max(0, sin(y * 0.85 + time_ * 0.07)) * (1 - depth * 0.55) * reach or 0
    local g1, g2, g3 = glint * 0.7, glint * 0.85, glint * 0.55
    line_pal(y, I.bg.sea1,
      pk((sr + (nr - sr) * g1) * 0.92, (sg + (ng - sg) * g1) * 0.92, (sb + (nb - sb) * g1) * 0.92),
      pk(sr + (nr - sr) * g2, sg + (ng - sg) * g2, sb + (nb - sb) * g2),
      pk((sr + (nr - sr) * g3) * 1.08, (sg + (ng - sg) * g3) * 1.08, (sb + (nb - sb) * g3) * 1.08))
  end
end

local BOAT_TOP = 110 -- the boat bobs between 110 and 114: the sail's rows are the ones from 110 to 142, a fixed range

local function paint_sail() -- the sail: lit by the sun's colour, darker towards the water
  local hr, hg, hb = D[4], D[5], D[6]
  line_ramp(BOAT_TOP, BOAT_TOP + BOAT_H + 3, I.obj.sail, pk(250 + (hr - 250) * 0.55, 246 + (hg - 246) * 0.55, 238 + (hb - 238) * 0.55),
            pk((250 + (hr - 250) * 0.33) * 0.75, (246 + (hg - 246) * 0.33) * 0.75, (238 + (hb - 238) * 0.33) * 0.75), "obj")
end

local function paint_sun(sy) -- the sun, redder as it goes down, a gradient of its own
  local y0, y1 = math.max(0, sy - SUN_R), min(159, sy + SUN_R - 1)
  local k = 0.3 + 0.5 * (sy / 100)
  local r, g, b = D[13] + (255 - D[13]) * k, D[14] + (70 - D[14]) * k, D[15] + (40 - D[15]) * k
  line_ramp(y0, y1, I.obj.core, pk(D[13], D[14], D[15]), pk(r, g, b), "obj")
  line_ramp(y0, y1, I.obj.glow1, pk(D[13] * 0.92, D[14] * 0.92, D[15] * 0.92), pk(r * 0.92, g * 0.92, b * 0.92), "obj")
  line_ramp(y0, y1, I.obj.glow2, pk(D[13] * 0.8, D[14] * 0.8, D[15] * 0.8), pk(r * 0.8, g * 0.8, b * 0.8), "obj")
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
  day(p)
  local sx, sy = sun_pos(p)
  sy = sy and floor(sy)
  local bx, by = 150, floor(112 + 2 * sin(time_ / 22))
  scroll(3, floor(time_ * 0.15), 0)
  if per_line then
    line_off() -- (each frame from nothing: the ramps are a few calls, and the sun moves)
    paint_sky()
    paint_sail()
    if sx then paint_sun(sy) end
    paint_sea(sx ~= nil, sy)
  else
    line_off()
    paint_flat()
  end
  spr(0, boat_sh, 0, bx, by, prio(0))
  if sx then spr(1, sun_sh, 0, floor(sx - SUN_R), floor(sy - SUN_R), prio(2)) else spr_off(1) end
  if hud then
    ui.box(8, 8, 330, 52)
    text(string.format("HORIZONTE   %s", p < 0.3 and "mediodía" or p < 0.7 and "atardecer" or "noche"), 18, 16, {font = "bold", color = ui.SEL})
    text(string.format("paleta por línea: %s   brillo: %s", per_line and "sí" or "no", shimmer and "sí" or "no"), 18, 38, {font = "main", color = ui.INK})
    text("izq/der: hora   A: paleta   B: brillo", 14, 296, {font = "main", color = 0xFFFFFF})
  end
end
