-- Paletes, palas y pelota vectoriales: arriba/abajo mueve la pala; A empieza otra partida.
local FIELD_TOP, FIELD_BOTTOM = 57, 278
local PAD_W, PAD_H, BALL_R = 10, 54, 5
local PLAYER_X, CPU_X = 26, 444
local WHITE, CYAN, ORANGE = 0xDCF8FF, 0x52DBFF, 0xFFAF65
local DARK, DIM = 0x030914, 0x173A50

state, score = "title", {0, 0}
player_y, cpu_y = 168, 168
ball = {x = 240, y = 168, vx = 0, vy = 0}
local serve_ticks, serve_dir, rally = 0, 1, 0

local function clamp(n, lo, hi)
  return math.max(lo, math.min(hi, n))
end

local function new_match()
  score = {0, 0}
  player_y, cpu_y = 168, 168
  serve_dir = 1
  rally = 0
  ball = {x = 240, y = 168, vx = 0, vy = 0}
  serve_ticks = 45
  state = "serve"
end

local function point(side)
  score[side] = score[side] + 1
  sfx("SCORE")
  if score[side] == 7 then
    state = "over"
    ball.vx, ball.vy = 0, 0
    return
  end
  serve_dir = side == 1 and -1 or 1
  ball = {x = 240, y = 168, vx = 0, vy = 0}
  serve_ticks = 50
  rally = 0
  state = "serve"
end

local function paddle_bounce(side, paddle_y)
  local offset = clamp((ball.y - paddle_y) / (PAD_H / 2), -1, 1)
  local speed = math.min(7.6, 4.1 + rally * 0.24)
  ball.vx = (side == 1 and 1 or -1) * speed * (1 - math.abs(offset) * 0.18)
  ball.vy = offset * 4.0
  ball.x = side == 1 and PLAYER_X + PAD_W + BALL_R or CPU_X - BALL_R
  rally = rally + 1
  sfx("HIT")
end

function _init()
  show(0)
  sound("HIT", {wave = "square", freq = 610, slide = -350, decay = 0.09, volume = 0.22})
  sound("WALL", {wave = "triangle", freq = 370, decay = 0.06, volume = 0.2})
  sound("SCORE", {wave = "square", freq = 180, slide = -130, decay = 0.3, volume = 0.28})
end

function _update()
  if state == "title" or state == "over" then
    if btnp("a") or btnp("start") then new_match() end
    return
  end

  local move = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  player_y = clamp(player_y + move * 5.1, FIELD_TOP + PAD_H / 2, FIELD_BOTTOM - PAD_H / 2)

  -- La consola sigue el recorrido de la pelota con velocidad limitada.
  local target = ball.vx > 0 and ball.y + ball.vy * 10 or 168
  local delta = clamp(target - cpu_y, -3.5, 3.5)
  if math.abs(target - cpu_y) > 5 then
    cpu_y = clamp(cpu_y + delta, FIELD_TOP + PAD_H / 2, FIELD_BOTTOM - PAD_H / 2)
  end

  if state == "serve" then
    serve_ticks = serve_ticks - 1
    if serve_ticks <= 0 then
      ball = {x = 240, y = 168, vx = serve_dir * 4.0, vy = (score[1] + score[2]) % 2 == 0 and -1.4 or 1.4}
      state = "play"
    end
    return
  end

  ball.x, ball.y = ball.x + ball.vx, ball.y + ball.vy
  if ball.y - BALL_R < FIELD_TOP then
    ball.y, ball.vy = FIELD_TOP + BALL_R, math.abs(ball.vy)
    sfx("WALL")
  elseif ball.y + BALL_R > FIELD_BOTTOM then
    ball.y, ball.vy = FIELD_BOTTOM - BALL_R, -math.abs(ball.vy)
    sfx("WALL")
  end

  if ball.vx < 0 and ball.x - BALL_R <= PLAYER_X + PAD_W and ball.x > PLAYER_X and
     math.abs(ball.y - player_y) <= PAD_H / 2 + BALL_R then
    paddle_bounce(1, player_y)
  elseif ball.vx > 0 and ball.x + BALL_R >= CPU_X and ball.x < CPU_X + PAD_W and
         math.abs(ball.y - cpu_y) <= PAD_H / 2 + BALL_R then
    paddle_bounce(2, cpu_y)
  elseif ball.x < -BALL_R then
    point(2)
  elseif ball.x > SCREEN_W + BALL_R then
    point(1)
  end
end

local function glow_line(x0, y0, x1, y1, colour)
  line(x0 + 1, y0, x1 + 1, y1, DIM)
  line(x0, y0 + 1, x1, y1 + 1, DIM)
  line(x0, y0, x1, y1, colour)
end

local function draw_field()
  glow_line(14, FIELD_TOP, 466, FIELD_TOP, DIM)
  glow_line(14, FIELD_BOTTOM, 466, FIELD_BOTTOM, DIM)
  for y = FIELD_TOP + 9, FIELD_BOTTOM - 6, 18 do
    rect(239, y, 2, 9, 0x29546A)
  end
end

local function draw_paddle(x, y, colour)
  rect(x - 3, y - PAD_H / 2 - 3, PAD_W + 6, PAD_H + 6, DIM)
  rect(x, y - PAD_H / 2, PAD_W, PAD_H, colour)
  rect(x + 2, y - PAD_H / 2 + 3, 2, PAD_H - 6, WHITE)
end

function _draw()
  cls(DARK)
  draw_field()
  draw_paddle(PLAYER_X, player_y, CYAN)
  draw_paddle(CPU_X, cpu_y, ORANGE)
  if state == "play" or state == "serve" then
    circ(ball.x, ball.y, BALL_R + 3, DIM)
    circ(ball.x, ball.y, BALL_R, WHITE)
  end

  text("TÚ", 146, 11, {font = "bold", color = CYAN, align = "center"})
  text("CPU", 334, 11, {font = "bold", color = ORANGE, align = "center"})
  text(tostring(score[1]), 205, 8, {font = "large_bold", color = WHITE, align = "center"})
  text(tostring(score[2]), 275, 8, {font = "large_bold", color = WHITE, align = "center"})
  text("PRIMERO A 7", 240, 34, {font = "main", color = 0x7895A2, align = "center"})

  if state == "title" then
    rect(99, 105, 282, 95, DARK)
    box(99, 105, 282, 95, DIM)
    text("PALETES", 240, 117, {font = "large_bold", scale = 2, color = WHITE, align = "center"})
    text("PULSA A PARA JUGAR", 240, 175, {font = "main", color = CYAN, align = "center"})
  elseif state == "serve" then
    text("PREPARADOS", 240, 148, {font = "bold", color = WHITE, align = "center"})
  elseif state == "over" then
    rect(92, 106, 296, 98, DARK)
    box(92, 106, 296, 98, DIM)
    local message = score[1] == 7 and "¡HAS GANADO!" or "GANA LA CONSOLA"
    text(message, 240, 122, {font = "large_bold", color = score[1] == 7 and CYAN or ORANGE, align = "center"})
    text("A: OTRA PARTIDA", 240, 174, {font = "main", color = WHITE, align = "center"})
  end
  text("ARRIBA/ABAJO: MOVER   A: EMPEZAR", 240, 293,
       {font = "main", color = 0x7895A2, align = "center"})
end
