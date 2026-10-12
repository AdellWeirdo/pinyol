-- Inventos: juguetes que no son de ningún género, hechos con lo más básico. Lienzos que el juego pinta mientras
-- corre (canvas, target), líneas, círculos y triángulos, borrar a transparente (CLEAR), leer un píxel (pget), ruido
-- (noise), cámara y recorte (camera, clip). Ningún dibujo hecho de antemano: todo sale del código.
--   ‹ › con START o C: cambia de juguete

local CX, CY = SCREEN_W // 2, SCREEN_H // 2
local TOYS = {"Pintar", "Terreno", "Estela", "3D", "Dos jugadores"}
toy = 1 -- globals: the test looks at them
local t = 0

-- ------------------------------------------------------------------ Pintar: a canvas the size of the screen
local ink = {0xE8443A, 0xF2B233, 0x3FA34D, 0x2F7FD0, 0x8E4FC2, 0x202020, 0xF4F0E6}
brush = {x = CX, y = CY, colour = 1, size = 6}

local function paint_update()
  local tx, ty, down = touch()
  local dx = (btn("right") and 3 or 0) - (btn("left") and 3 or 0)
  local dy = (btn("down") and 3 or 0) - (btn("up") and 3 or 0)
  local x0, y0 = brush.x, brush.y
  if down then brush.x, brush.y = tx * 2, ty * 2 else brush.x, brush.y = brush.x + dx, brush.y + dy end
  brush.x, brush.y = math.max(0, math.min(SCREEN_W - 1, brush.x)), math.max(0, math.min(SCREEN_H - 1, brush.y))
  if btnp("b") then brush.colour = brush.colour % #ink + 1 end
  if down or btn("a") then -- a stroke: circles along the line from where the brush was
    target("PAPER")
    local steps = math.max(1, math.floor(math.max(math.abs(brush.x - x0), math.abs(brush.y - y0)) / 2))
    for i = 0, steps do
      circ(x0 + (brush.x - x0) * i / steps, y0 + (brush.y - y0) * i / steps, brush.size, ink[brush.colour])
    end
    target()
  end
end

local function paint_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0xF4F0E6)
  img("PAPER", 0, 0)
  circ(brush.x, brush.y, brush.size + 2, 0x202020, false)
  for i, c in ipairs(ink) do circ(20 + i * 22, SCREEN_H - 18, i == brush.colour and 9 or 6, c) end
  text("A o el dedo: pinta · B: color", SCREEN_W - 12, SCREEN_H - 30, 0x606060, "main", "right")
end

-- ------------------------------------------------------------------ Terreno: hills from noise, holes by CLEAR
ball = {x = 60, y = 10, vx = 0.6, vy = 0}
local booms = {}

local function terrain_make()
  canvas("LAND", 240, 160) -- world-sized: each pixel shown 2x2
  target("LAND")
  for x = 0, 239 do
    local h = 90 + math.floor(noise(x / 40, 1.5) * 40 + noise(x / 11, 7.2) * 8)
    line(x, h, x, 159, 0x6B4A2E)
    line(x, h, x, h + 3, 0x5DA840)
  end
  target()
end

local function solid(x, y) return pget(math.floor(x), math.floor(y), "LAND") ~= nil end

local function terrain_update()
  ball.vy = ball.vy + 0.08
  local nx, ny = ball.x + ball.vx, ball.y + ball.vy
  if solid(nx, ny + 3) then -- landed: roll down the slope
    ball.vy = 0
    if not solid(nx + 1, ny + 3) then ball.vx = ball.vx + 0.05 elseif not solid(nx - 1, ny + 3) then ball.vx = ball.vx - 0.05 end
    while solid(nx, ny + 2) and ny > 0 do ny = ny - 1 end
    ball.vx = ball.vx * 0.98
  end
  ball.x, ball.y = (nx + 240) % 240, math.min(ny, 170)
  if ball.y >= 170 then ball.x, ball.y, ball.vx, ball.vy = 30 + math.random(180), 0, 0.6, 0 end
  if btnp("a") then -- a bomb under the ball: a hole in the land
    target("LAND")
    circ(ball.x, ball.y + 6, 14, CLEAR)
    for a = 0, 6.28, 0.05 do -- scorched edges, only where land is left
      local x, y = ball.x + math.cos(a) * 15, ball.y + 6 + math.sin(a) * 15
      if solid(x, y) then pset(x, y, 0x3A2A1A) end
    end
    target()
    booms[#booms + 1] = {x = ball.x, y = ball.y + 6, t = 0}
  end
  if btnp("b") then terrain_make() end
  for i = #booms, 1, -1 do booms[i].t = booms[i].t + 1 if booms[i].t > 20 then table.remove(booms, i) end end
end

local function terrain_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x9CD3F0)
  img("LAND", 0, 0, 0, 2)
  circ(ball.x * 2, ball.y * 2, 6, 0xE8443A)
  for _, b in ipairs(booms) do circ(b.x * 2, b.y * 2, 8 + b.t * 2, b.t < 10 and 0xFFE070 or 0xFF8030, false) end
  text("A: bomba · B: tierra nueva", 12, SCREEN_H - 30, 0x2A4060, "main")
end

-- ------------------------------------------------------------------ Estela: a flow field painted with fading trails
local walkers = {}

local function trail_make()
  canvas("TRAIL", 240, 160)
  target("TRAIL")
  cls(0x0B0E1C)
  target()
  walkers = {}
  for i = 1, 160 do walkers[i] = {x = math.random(0, 239), y = math.random(0, 159), c = i % 3} end
end

local TRAIL_INK = {[0] = 0x55E0FF, 0xFF5AC8, 0xFFE070}

local function trail_update()
  target("TRAIL")
  if t % 6 == 0 then shade(0, 0, 240, 160) end -- old trails fade
  for _, w in ipairs(walkers) do
    local a = noise(w.x / 60, w.y / 60, t / 300) * 6.3
    local nx, ny = w.x + math.cos(a), w.y + math.sin(a)
    line(w.x, w.y, nx, ny, TRAIL_INK[w.c])
    w.x, w.y = nx, ny
    if w.x < 0 or w.x >= 240 or w.y < 0 or w.y >= 160 then w.x, w.y = math.random(0, 239), math.random(0, 159) end
  end
  target()
  if btnp("a") then trail_make() end
end

local function trail_draw()
  img("TRAIL", 0, 0, 0, 2)
  text("A: otra vez", 12, SCREEN_H - 30, 0xA0A8C0, "main")
end

-- ------------------------------------------------------------------ 3D: an object turned in space, from triangles
local V = {{-1, -1, -1}, {1, -1, -1}, {1, 1, -1}, {-1, 1, -1}, {-1, -1, 1}, {1, -1, 1}, {1, 1, 1}, {-1, 1, 1},
           {0, -2, 0}}
local FACES = {{1, 2, 3, 0xE8443A}, {1, 3, 4, 0xE8443A}, {6, 5, 8, 0x3FA34D}, {6, 8, 7, 0x3FA34D},
               {5, 1, 4, 0x2F7FD0}, {5, 4, 8, 0x2F7FD0}, {2, 6, 7, 0xF2B233}, {2, 7, 3, 0xF2B233},
               {4, 3, 7, 0x8E4FC2}, {4, 7, 8, 0x8E4FC2}, {1, 5, 9, 0xF4F0E6}, {5, 6, 9, 0xD0CCC4},
               {6, 2, 9, 0xF4F0E6}, {2, 1, 9, 0xD0CCC4}} -- a box with a roof
local spin = {a = 0, b = 0.4}

local function shadeby(c, k) -- a colour darker by k (0..1)
  local r, g, b = c >> 16 & 255, c >> 8 & 255, c & 255
  return math.floor(r * k) << 16 | math.floor(g * k) << 8 | math.floor(b * k)
end

local function cube_update()
  spin.a = spin.a + 0.02 + ((btn("right") and 0.04 or 0) - (btn("left") and 0.04 or 0))
  spin.b = spin.b + ((btn("down") and 0.03 or 0) - (btn("up") and 0.03 or 0))
end

local function cube_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x14182A)
  local ca, sa, cb, sb = math.cos(spin.a), math.sin(spin.a), math.cos(spin.b), math.sin(spin.b)
  local p = {}
  for i, v in ipairs(V) do
    local x, z = v[1] * ca - v[3] * sa, v[1] * sa + v[3] * ca
    local y, z2 = v[2] * cb - z * sb, v[2] * sb + z * cb
    local d = 220 / (z2 + 5)
    p[i] = {CX + x * d, CY + y * d, z2}
  end
  local order = {}
  for i, f in ipairs(FACES) do order[i] = {f = f, z = p[f[1]][3] + p[f[2]][3] + p[f[3]][3]} end
  table.sort(order, function(a, b) return a.z > b.z end) -- far first: the near ones paint over them
  for _, o in ipairs(order) do
    local a, b, c = p[o.f[1]], p[o.f[2]], p[o.f[3]]
    local cross = (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
    if cross < 0 then -- facing us: lit by how much it faces us
      local light = 0.45 + 0.55 * math.min(1, -o.z / 9 + 0.6)
      tri(a[1], a[2], b[1], b[2], c[1], c[2], shadeby(o.f[4], math.max(0.3, math.min(1, light))))
    end
  end
  text("cruceta: gira", 12, SCREEN_H - 30, 0x8890B0, "main")
end

-- ------------------------------------------------------------------ Dos jugadores: one world, two views
p1, p2 = {x = 100, y = 100}, {x = 300, y = 200}
local STARS = {}

local function world(cam, me)
  rect(cam.x - 240, cam.y - 160, 960, 640, 0x0E1A2E) -- the world, as seen from cam
  for _, s in ipairs(STARS) do pset(s[1], s[2], s[3]) end
  for gx = 0, 600, 100 do line(gx, 0, gx, 400, 0x24324E) end
  for gy = 0, 400, 100 do line(0, gy, 600, gy, 0x24324E) end
  circ(p1.x, p1.y, 10, 0xFF5A5A)
  circ(p2.x, p2.y, 10, 0x5AB0FF)
  circ(me.x, me.y, 14, 0xFFFFFF, false)
end

local function split_update()
  p1.x = p1.x + (btn("right") and 2 or 0) - (btn("left") and 2 or 0)
  p1.y = p1.y + (btn("down") and 2 or 0) - (btn("up") and 2 or 0)
  local tx, ty, down = touch() -- the second player: a finger on the right half
  if down and tx * 2 > CX then
    local wx, wy = p2.x - 120 + (tx * 2 - CX), p2.y - 160 + ty * 2
    p2.x, p2.y = p2.x + (wx - p2.x) * 0.05, p2.y + (wy - p2.y) * 0.05
  end
end

local function split_draw()
  for i, me in ipairs({p1, p2}) do
    local left = (i - 1) * CX
    local cam = {x = me.x - left - CX // 2, y = me.y - CY}
    clip(left, 0, CX, SCREEN_H)
    camera(cam.x, cam.y)
    world({x = me.x, y = me.y}, me)
    camera()
    clip()
  end
  line(CX, 0, CX, SCREEN_H, 0xFFFFFF)
  text("cruceta: rojo · dedo: azul", CX, SCREEN_H - 30, 0xC0C8E0, "main", "center")
end

-- ------------------------------------------------------------------ the toy box
local UPDATE = {paint_update, terrain_update, trail_update, cube_update, split_update}
local DRAW = {paint_draw, terrain_draw, trail_draw, cube_draw, split_draw}

function _init()
  show(0) -- nothing from the 240x160 world: every pixel here comes from the drawing calls
  canvas("PAPER", SCREEN_W, SCREEN_H)
  terrain_make()
  trail_make()
  for i = 1, 200 do STARS[i] = {math.random(0, 600), math.random(0, 400), i % 5 == 0 and 0xFFE070 or 0x8090B0} end
end

function _update()
  t = t + 1
  if btnp("c") or btnp("start") then toy = toy % #TOYS + 1 end
  UPDATE[toy]()
end

function _draw()
  DRAW[toy]()
  text(toy .. "/" .. #TOYS .. "  " .. TOYS[toy], 12, 8, 0xFFFFFF, "bold")
end
