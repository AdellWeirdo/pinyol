-- Pinball: la mesa entera en pantalla, tres bolas. Izquierda o A: aleta izquierda. Derecha o B: aleta derecha.
-- Abajo (mantenido) tensa el muelle y al soltarlo sale la bola. Usa physics (bolas, topes, paredes) y w:drive (las aletas).
local physics = require("physics")

local X0, X1 = 130, 350          -- la mesa por dentro, de pared a pared
local BALL_R, SPEED_MAX = 4, 12  -- una pared tiene 12 de grosor: a más velocidad la bola la atravesaría
local GRAVITY = 0.2
local BALLS, SAVER_TICKS, MULT_EVERY, MULT_MAX = 3, 12 * 60, 10, 5
local LANE_X, LANE_Y = 344, 296  -- donde espera la bola, en el carril del muelle
local FLIP_LEN, FLIP_REST, FLIP_UP, FLIP_SPEED_UP, FLIP_SPEED_DOWN = 50, 28, -24, 12, 8
local DARK, TABLE, RIM, GLOW = 0x050A18, 0x0B1630, 0x2B4E8C, 0x142A55
local AMBER, CYAN, PINK, WHITE, DIM = 0xFFB84A, 0x4DE1FF, 0xFF5C8A, 0xF2F7FF, 0x7F93B8

local w, flippers, bumpers
local saver, fresh, charge, still_ticks, flash_until -- fresh: la bola aún no ha sido salvada
state, score, balls_left, bumper_hits, ball = "title", 0, BALLS, 0, nil -- (globales: los scripts de prueba los miran)
local best = stored("best", 0)

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
local function multiplier() return math.min(MULT_MAX, 1 + bumper_hits // MULT_EVERY) end

local function wall(x, y, bw, bh) return w:box(x, y, bw, bh, {static = true, bounce = 0.5}) end
local function slab(pts) return w:poly(0, 0, pts, {static = true, bounce = 0.4, friction = 0.2}) end

-- Una aleta: un polígono estático que gira alrededor de su extremo (px, py). dir = 1 la izquierda, -1 la derecha.
local function flipper(px, py, dir)
  local pts = {0, -6, dir * FLIP_LEN, -3, dir * FLIP_LEN, 3, 0, 6}
  local f = w:poly(px, py, pts, {static = true, bounce = 0.45, friction = 0.6})
  return {body = f, dir = dir, px = px, py = py, angle = dir * FLIP_REST, up = false}
end

local function build()
  w = physics.world({gravity = GRAVITY})
  wall(X0 - 12, 0, 12, 320); wall(X1, 0, 12, 320); wall(X0, 0, X1 - X0, 10) -- paredes y techo
  wall(326, 76, 12, 244)                                                     -- la pared del carril del muelle
  wall(338, 308, 12, 12)                                                     -- el fondo del carril
  slab({X0, 10, X0, 64, X0 + 54, 10}); slab({X1, 10, X1, 64, X1 - 54, 10})  -- esquinas de arriba: dan la vuelta a la bola
  slab({X0, 232, X0 + 54, 275, X0 + 54, 320, X0, 320})                       -- las guías: acaban dentro de la aleta, sin vértice libre
  slab({326, 232, 326 - 54, 275, 326 - 54, 320, 326, 320})
  bumpers = {}
  for _, p in ipairs({{258, 84}, {204, 100}, {160, 150}, {262, 150}}) do
    local b = w:circle(p[1], p[2], 12, {static = true, bounce = 0.9})
    b.data, bumpers[#bumpers + 1] = {bumper = true, lit = 0}, b
  end
  flippers = {flipper(X0 + 48, 276, 1), flipper(326 - 48, 276, -1)}
  for _, f in ipairs(flippers) do w:drive(f.body, f.angle, f.px, f.py) end
  ball = w:circle(LANE_X, LANE_Y, BALL_R, {bounce = 0.6, friction = 0.2})
  w:step() -- las aletas ya en su sitio
end

local function ready() -- la bola, esperando en el muelle
  ball.x, ball.y, ball.vx, ball.vy = LANE_X, LANE_Y, 0, 0
  state, charge, still_ticks = "ready", 0, 0
end

local function new_game()
  score, balls_left, bumper_hits, saver, fresh = 0, BALLS, 0, 0, true
  build()
  ready()
end

function _init()
  show(0)
  sound("BUMP", {wave = "square", freq = 520, slide = 700, decay = 0.07, volume = 0.3})
  sound("FLIP", {wave = "noise", freq = 900, decay = 0.03, volume = 0.18})
  sound("LAUNCH", {wave = "triangle", freq = 160, slide = 900, decay = 0.25, volume = 0.3})
  sound("DRAIN", {wave = "saw", freq = 330, slide = -260, decay = 0.5, volume = 0.3})
  sound("SAVED", {wave = "square", freq = 440, slide = 440, decay = 0.2, volume = 0.25})
  score, balls_left, bumper_hits, saver, fresh, flash_until = 0, BALLS, 0, 0, true, 0
  build()
  ready()
  state = "title"
end

local function bump(b, speed)
  local dx, dy = ball.x - b.x, ball.y - b.y
  local d = math.max(0.001, math.sqrt(dx * dx + dy * dy))
  ball.vx, ball.vy = ball.vx + dx / d * 3, ball.vy + dy / d * 3 -- un tope empuja: no solo rebota
  b.data.lit = 8
  score, bumper_hits = score + 100 * multiplier(), bumper_hits + 1
  sfx("BUMP", clamp(speed / 6, 0.4, 1), {pitch = 0.9 + 0.1 * (bumper_hits % 4)})
  led(AMBER); flash_until = ticks() + 6
end

local function drain()
  if saver > 0 then -- la bola salvada: vuelve al muelle sin gastar una (y sin segunda salvada)
    sfx("SAVED")
    fresh, saver = false, 0
  else
    balls_left, fresh = balls_left - 1, true
    sfx("DRAIN")
    if balls_left == 0 then
      best = math.max(best, score)
      store("best", best)
      ready() -- la bola aparcada en el muelle mientras se ve la pantalla de fin
      state = "over"
      return
    end
  end
  ready()
end

local function steer_flippers()
  local held = {btn("left") or btn("a"), btn("right") or btn("b")}
  for i, f in ipairs(flippers) do
    local target = f.dir * (held[i] and FLIP_UP or FLIP_REST)
    if held[i] and not f.up then sfx("FLIP") end
    f.up = held[i]
    local step = held[i] and FLIP_SPEED_UP or FLIP_SPEED_DOWN
    f.angle = f.angle + clamp(target - f.angle, -step, step)
    w:drive(f.body, f.angle)
  end
end

local function play()
  steer_flippers()
  w:step()
  for _, h in ipairs(w:hits()) do
    local other = h[1] == ball and h[2] or h[2] == ball and h[1] or nil
    if other and other.data and other.data.bumper then bump(other, h[3]) end
  end
  local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2)
  if speed > SPEED_MAX then ball.vx, ball.vy = ball.vx * SPEED_MAX / speed, ball.vy * SPEED_MAX / speed end
  if saver > 0 then saver = saver - 1 end
  still_ticks = (speed < 0.3 and ball.x < 326) and still_ticks + 1 or 0
  if still_ticks > 120 then ball.vx, ball.vy, still_ticks = (228 - ball.x) / 40, -3, 0 end -- se ha parado: un empujón hacia el centro
  if ball.x > 326 and ball.y > LANE_Y - 6 and speed < 0.5 then ready() end -- un tiro flojo: cayó de vuelta al muelle
  if ball.y > 330 then drain() end
end

function _update()
  for _, b in ipairs(bumpers) do b.data.lit = math.max(0, b.data.lit - 1) end
  if flash_until > 0 and ticks() >= flash_until then led(); flash_until = 0 end
  if state == "title" or state == "over" then
    if btnp("start") or btnp("a") then new_game() end
    steer_flippers() -- (para jugar con ellas mientras tanto)
    w:step()
    return
  end
  if state == "ready" then
    steer_flippers()
    charge = btn("down") and math.min(1, charge + 1 / 45) or charge
    if btnr("down") and charge > 0.1 then
      ball.vy, state, saver = -(8 + 4.5 * charge), "play", fresh and SAVER_TICKS or 0
      sfx("LAUNCH")
    elseif not btn("down") then
      charge = 0
    end
    w:step()
    return
  end
  play()
end

local function glow_poly(pts, fill, edge)
  poly(pts, fill, true)
  poly(pts, edge, false)
end

local function draw_table()
  rect(X0, 0, X1 - X0, 320, TABLE)
  for _, b in ipairs(w.bodies) do
    if b.static and b.kind == "poly" and not b.kin and b ~= flippers[1].body and b ~= flippers[2].body then
      glow_poly(w:corners(b), GLOW, RIM)
    end
  end
  rect(X0 - 12, 0, 12, 320, DARK); rect(X1, 0, 12, 320, DARK)
  line(X0, 0, X0, 320, RIM); line(X1, 0, X1, 320, RIM); line(X0, 10, X1, 10, RIM)
  rect(326, 76, 12, 244, GLOW); box(326, 76, 12, 244, RIM)
  local spring = LANE_Y + BALL_R + 2 + charge * 10 -- el muelle se comprime con la carga
  for y = spring, 306, 4 do line(340, y, 348, y + 2, charge > 0.8 and PINK or DIM) end
  for _, b in ipairs(bumpers) do
    local lit = b.data.lit
    circ(b.x, b.y, b.r + 4 + lit * 0.6, lit > 0 and AMBER or GLOW, false)
    circ(b.x, b.y, b.r, lit > 0 and AMBER or PINK)
    circ(b.x, b.y, b.r - 5, lit > 0 and WHITE or DARK)
  end
  for _, f in ipairs(flippers) do glow_poly(w:corners(f.body), f.up and AMBER or CYAN, WHITE) end
  circ(ball.x, ball.y, BALL_R + 3, GLOW)
  circ(ball.x, ball.y, BALL_R, WHITE)
end

local function draw_hud()
  text("PUNTOS", 62, 40, {font = "main", color = DIM, align = "center"})
  text(tostring(score), 62, 56, {font = "large_bold", color = WHITE, align = "center"})
  text("MEJOR", 62, 110, {font = "main", color = DIM, align = "center"})
  text(tostring(best), 62, 126, {font = "bold", color = CYAN, align = "center"})
  text("BOLAS", 418, 40, {font = "main", color = DIM, align = "center"})
  for i = 1, BALLS do circ(380 + i * 22, 70, 5, i <= balls_left and WHITE or GLOW) end
  text("x" .. multiplier(), 418, 110, {font = "large_bold", color = multiplier() > 1 and AMBER or DIM, align = "center"})
  if saver > 0 and state == "play" then text("SALVADA", 418, 160, {font = "main", color = PINK, align = "center"}) end
end

local function banner(title, line1, line2)
  rect(X0 + 10, 100, X1 - X0 - 20, 108, DARK)
  box(X0 + 10, 100, X1 - X0 - 20, 108, RIM)
  text(title, 240, 112, {font = "large_bold", color = AMBER, align = "center"})
  text(line1, 240, 156, {font = "main", color = WHITE, align = "center"})
  text(line2, 240, 178, {font = "main", color = DIM, align = "center"})
end

function _draw()
  cls(DARK)
  draw_table()
  draw_hud()
  if state == "title" then
    banner("PINBALL", "A: EMPEZAR", "IZQ/A  DER/B: ALETAS")
  elseif state == "over" then
    banner("FIN", score .. " PUNTOS", "A: OTRA PARTIDA")
  elseif state == "ready" then
    text("ABAJO: MUELLE", 418, 190, {font = "main", color = charge > 0 and AMBER or DIM, align = "center"})
  end
end
