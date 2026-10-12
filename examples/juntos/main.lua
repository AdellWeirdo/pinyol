-- Juntos: juegos entre consolas que están cerca y juegan al mismo juego (link). Sin router ni internet: en la
-- consola van por ESP-NOW; en el ordenador, entre simuladores de la misma red; en el navegador, entre pestañas.
--   Pizarra: lo que dibuja cada uno sale en todas, cada consola con su color.
--   Pasa la pelota: las consolas se ponen en fila; la pelota sale por un lado de una pantalla y entra por la otra.
--   C o START: cambia de juego
-- Los mensajes pueden perderse por el aire: por eso se envía a menudo lo que hay, más que una vez lo que cambia.

local CX, CY = SCREEN_W // 2, SCREEN_H // 2
local GAMES = {"Pizarra", "Pasa la pelota"}
game = 1 -- globals: the test looks at them
local t = 0
local INK = {0xE8443A, 0x2F7FD0, 0x3FA34D, 0xF2B233, 0x8E4FC2, 0x20A0A0, 0xE070B0, 0x404040}

local function ink_of(id) return INK[id % #INK + 1] end

-- ------------------------------------------------------------------ Pizarra
cursor = {x = CX, y = CY, down = false}
others = {}         -- id -> {x, y, seen}: the other consoles' cursors
local pending = {}  -- line pieces drawn here, not sent yet: x0, y0, x1, y1, ...

local function stroke(p, colour) -- line pieces onto the board, thick
  target("BOARD")
  for i = 1, #p - 3, 4 do
    local x0, y0, x1, y1 = p[i], p[i + 1], p[i + 2], p[i + 3]
    local n = math.max(1, math.floor(math.max(math.abs(x1 - x0), math.abs(y1 - y0)) / 2))
    for k = 0, n do circ(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n, 3, colour) end
  end
  target()
end

local function board_update()
  local tx, ty, down = touch()
  local x0, y0 = cursor.x, cursor.y
  if down then cursor.x, cursor.y = tx * 2, ty * 2
  else
    cursor.x = math.max(0, math.min(SCREEN_W - 1, cursor.x + (btn("right") and 3 or 0) - (btn("left") and 3 or 0)))
    cursor.y = math.max(0, math.min(SCREEN_H - 1, cursor.y + (btn("down") and 3 or 0) - (btn("up") and 3 or 0)))
  end
  local drawing = down or btn("a")
  if drawing and cursor.down then -- a piece from where it was
    local p = {x0, y0, cursor.x, cursor.y}
    stroke(p, ink_of(link.id()))
    for _, v in ipairs(p) do pending[#pending + 1] = v end
  end
  cursor.down = drawing
  if btnp("b") then
    target("BOARD") cls() target()
    link.send({clear = true})
  end
  if t % 4 == 0 then -- where my cursor is, and up to ten pieces: 15 messages a second, under the share of 20
    local s = {}
    for i = 1, math.min(#pending, 40) do s[i] = pending[i] end
    if link.send({x = cursor.x, y = cursor.y, s = s}) then
      for _ = 1, #s do table.remove(pending, 1) end
    end
  end
  for from, m in link.recv do
    if type(m) == "table" then
      if m.clear then target("BOARD") cls() target() end
      if type(m.x) == "number" and type(m.y) == "number" then others[from] = {x = m.x, y = m.y, seen = t} end
      if type(m.s) == "table" then stroke(m.s, ink_of(from)) end
    end
  end
  for id, o in pairs(others) do if t - o.seen > 120 then others[id] = nil end end
end

local function board_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0xF4F0E6)
  img("BOARD", 0, 0)
  for id, o in pairs(others) do circ(o.x, o.y, 7, ink_of(id), false) end
  circ(cursor.x, cursor.y, 5, ink_of(link.id()))
  local n = #link.peers()
  text(n == 0 and "Sola: enciende otra consola con este juego" or (n + 1) .. " consolas", SCREEN_W - 12, SCREEN_H - 30,
       0x606060, "main", "right")
  text("A o el dedo: dibuja · B: borra", 12, SCREEN_H - 30, 0x606060, "main")
end

-- ------------------------------------------------------------------ Pasa la pelota
ball = {x = CX, y = CY, vx = 3, vy = 2} -- nil while it is on another console

local function row() -- all the consoles, smallest id first: everyone agrees on who is next to whom
  local all = link.peers()
  all[#all + 1] = link.id()
  table.sort(all)
  for i, id in ipairs(all) do if id == link.id() then return all, i end end
  return all, 1
end

local function ball_update()
  for from, m in link.recv do -- the ball coming in, from the side it went out of on the other screen
    if type(m) == "table" and type(m.b) == "table" and type(m.b[1]) == "number" and type(m.b[2]) == "number" then
      local vx = m.b[2]
      ball = {x = vx > 0 and 0 or SCREEN_W - 1, y = m.b[1], vx = vx, vy = tonumber(m.b[3]) or 0}
    end
  end
  if not ball then return end
  ball.x, ball.y = ball.x + ball.vx, ball.y + ball.vy
  if ball.y < 8 or ball.y > SCREEN_H - 8 then ball.vy = -ball.vy end
  local tx, ty, down = touch()
  if down and math.abs(tx * 2 - ball.x) < 30 and math.abs(ty * 2 - ball.y) < 30 then -- a finger pushes it back
    ball.vx = -ball.vx
  end
  if btnp("a") then ball.vx = -ball.vx end
  if ball.x < 0 or ball.x >= SCREEN_W then -- out: to the console on that side (around the row, and to itself alone)
    local all, me = row()
    local next = all[(me - 1 + (ball.vx > 0 and 1 or -1)) % #all + 1]
    if next == link.id() then ball.x = ball.vx > 0 and 0 or SCREEN_W - 1
    elseif link.send({b = {ball.y, ball.vx, ball.vy}}, next) then ball = nil end
  end
end

local function ball_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x14304A)
  local all, me = row()
  for i = 1, #all do -- the row of consoles, this one lit
    local x = CX - #all * 14 + (i - 1) * 28
    rect(x, 16, 22, 14, i == me and 0xF2B233 or 0x4A6A8A)
  end
  if ball then circ(ball.x, ball.y, 8, 0xFFFFFF) end
  text(#all == 1 and "Sola: la pelota vuelve por el otro lado" or "Consola " .. me .. " de " .. #all, CX, SCREEN_H - 30,
       0xA0C0E0, "main", "center")
end

-- ------------------------------------------------------------------ both
function _init()
  show(0)
  canvas("BOARD", SCREEN_W, SCREEN_H)
end

function _update()
  t = t + 1
  if btnp("c") or btnp("start") then game = game % #GAMES + 1 end
  if game == 1 then board_update() else ball_update() end
end

function _draw()
  if game == 1 then board_draw() else ball_draw() end
  text(GAMES[game], 12, 8, game == 1 and 0x303030 or 0xFFFFFF, "bold")
end
