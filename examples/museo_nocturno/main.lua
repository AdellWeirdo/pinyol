-- Museo de Medianoche: infiltracion en primera persona.
-- Arriba/abajo caminan, izquierda/derecha giran, B + direccion se desplaza,
-- C anda sigilosamente y A recupera cuadros o abre la salida.
local MAP = {
  "################",
  "#......#.......#",
  "#.MMMM.#.GGGG..#",
  "#.M..........G.#",
  "#.M..#####...G.#",
  "#....#...#.....#",
  "###..#...#..####",
  "#....#.......#.#",
  "#.GG.##.###..#.#",
  "#..G.........#.#",
  "#..G..MMMM.....#",
  "#.....M..M..GG.#",
  "#.###.M..M..G..#",
  "#.#...........##",
  "#.#..GGG..#....E",
  "################",
}
local WALLS = {["#"] = "TEX_STONE", M = "TEX_MARBLE", G = "TEX_GALLERY", E = "TEX_EXIT"}
local PAINTING_SPOTS = {{6.5, 1.5}, {11.5, 3.5}, {7.5, 7.5}, {1.5, 13.5}, {14.5, 12.5}}
local GUARD_SPOTS = {{10.5, 5.5, 12.5, 5.5}, {5.5, 12.5, 5.5, 13.5}, {11.5, 9.5, 12.5, 9.5}}

state, found, strikes = "title", 0, 0
P, paintings, guards = {}, {}, {}
local clock, message, message_time, alarm = 0, "", 0, 0
local view = {map = MAP, walls = WALLS, fov = 66, fog = 10,
  ceiling = 0x161D2A, floor = 0x35303A, sprites = {}}

local function open(x, y)
  local row = MAP[math.floor(y) + 1]
  return row and row:sub(math.floor(x) + 1, math.floor(x) + 1) == "."
end

local function clear_sight(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local steps = math.ceil(math.sqrt(dx * dx + dy * dy) * 10)
  for i = 1, steps - 1 do
    if not open(x1 + dx * i / steps, y1 + dy * i / steps) then return false end
  end
  return true
end

local function distance(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

local function set_message(s, duration)
  message, message_time = s, duration or 120
end

local function reset()
  P = {x = 1.5, y = 1.5, a = 0}
  paintings, guards = {}, {}
  for i, spot in ipairs(PAINTING_SPOTS) do
    paintings[i] = {x = spot[1], y = spot[2], frame = i - 1, taken = false}
  end
  for i, spot in ipairs(GUARD_SPOTS) do
    guards[i] = {x = spot[1], y = spot[2], x0 = spot[1], y0 = spot[2],
      x1 = spot[3], y1 = spot[4], patrol = 1, chase = 0,
      face_x = spot[3] - spot[1], face_y = spot[4] - spot[2]}
  end
  found, strikes, alarm, state = 0, 0, 0, "play"
  set_message("CINCO CUADROS. UNA SALIDA.", 180)
end

function _init()
  show(0)
  canvas("VIEW", 240, 144)
  P = {x = 1.5, y = 1.5, a = 0}
  sound("TAKE", "coin", 5)
  sound("SEEN", "hit", 2)
  sound("DOOR", "powerup", 3)
end

local function move_body(body, dx, dy, radius)
  local edge_x = dx > 0 and radius or -radius
  local edge_y = dy > 0 and radius or -radius
  if dx ~= 0 and open(body.x + dx + edge_x, body.y) then body.x = body.x + dx end
  if dy ~= 0 and open(body.x, body.y + dy + edge_y) then body.y = body.y + dy end
end

local function interact()
  local a = math.rad(P.a)
  for _, art in ipairs(paintings) do
    local dx, dy = art.x - P.x, art.y - P.y
    local d = math.sqrt(dx * dx + dy * dy)
    if not art.taken and d < 0.95 and d > 0 and
       (dx * math.cos(a) + dy * math.sin(a)) / d > 0.55 and
       clear_sight(P.x, P.y, art.x, art.y) then
      art.taken = true
      found = found + 1
      sfx("TAKE")
      if found == 5 then set_message("TODOS. VUELVE A LA SALIDA.", 180)
      else set_message("CUADRO RECUPERADO", 90) end
      return
    end
  end
  if P.x > 14.2 and P.y > 14 and P.y < 15 and (P.a < 90 or P.a > 270) then
    if found == 5 then
      state = "won"
      message_time = 0
      sfx("DOOR")
    else
      set_message("FALTAN " .. (5 - found) .. " CUADROS", 100)
    end
  else
    set_message("ACERCATE Y MIRA EL CUADRO", 70)
  end
end

local function caught()
  strikes = strikes + 1
  alarm = 45
  sfx("SEEN")
  if strikes >= 3 then
    state = "over"
    set_message("TE HAN ATRAPADO", 180)
  else
    P.x, P.y, P.a = 1.5, 1.5, 0
    for _, guard in ipairs(guards) do
      guard.x, guard.y, guard.chase = guard.x0, guard.y0, 0
      guard.face_x, guard.face_y = guard.x1 - guard.x0, guard.y1 - guard.y0
    end
    set_message("TE DEVUELVEN A LA ENTRADA", 140)
  end
end

local function update_guard(guard)
  local d = distance(guard.x, guard.y, P.x, P.y)
  if d < 0.45 then caught() return end
  local facing = ((P.x - guard.x) * guard.face_x + (P.y - guard.y) * guard.face_y) / d
  local sight_range = btn("c") and 1.5 or 4.3
  if d < sight_range and (facing > 0.25 or d < 0.8) and
     clear_sight(guard.x, guard.y, P.x, P.y) then
    guard.chase = 90
  elseif guard.chase > 0 then
    guard.chase = guard.chase - 1
  end
  local tx, ty, speed
  if guard.chase > 0 then
    tx, ty, speed = P.x, P.y, 0.031
    alarm = math.max(alarm, 8)
  else
    tx, ty, speed = guard.x1, guard.y1, 0.018
    if guard.patrol == 0 then tx, ty = guard.x0, guard.y0 end
    if distance(guard.x, guard.y, tx, ty) < 0.1 then
      guard.patrol = 1 - guard.patrol
    end
  end
  local travel = distance(guard.x, guard.y, tx, ty)
  if travel > 0.01 then
    guard.face_x, guard.face_y = (tx - guard.x) / travel, (ty - guard.y) / travel
    move_body(guard, guard.face_x * speed, guard.face_y * speed, 0.17)
  end
  if distance(guard.x, guard.y, P.x, P.y) < 0.45 then caught() end
end

local function update_play()
  local turn = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local forward = (btn("up") and 1 or 0) - (btn("down") and 1 or 0)
  local a = math.rad(P.a)
  local speed = btn("c") and 0.037 or 0.07
  if btn("b") then
    move_body(P, -math.sin(a) * turn * speed, math.cos(a) * turn * speed, 0.19)
  else
    P.a = (P.a + turn * 3) % 360
  end
  move_body(P, math.cos(a) * forward * speed, math.sin(a) * forward * speed, 0.19)
  if btnp("a") then interact() end
  if state ~= "play" then return end
  for _, guard in ipairs(guards) do
    update_guard(guard)
    if state ~= "play" or alarm == 45 then break end
  end
end

function _update()
  clock = clock + 1
  if message_time > 0 then message_time = message_time - 1 end
  if alarm > 0 then alarm = alarm - 1 end
  if state == "title" then
    P.x, P.y, P.a = 8, 7.5, (clock / 2) % 360
    if btnp("a") or btnp("start") then reset() end
  elseif state == "play" then
    update_play()
  elseif btnp("a") and clock > 60 then
    reset()
  end
end

function _draw()
  view.x, view.y, view.angle = P.x, P.y, P.a
  local sprites = {}
  for _, art in ipairs(paintings) do
    if not art.taken then
      sprites[#sprites + 1] = {x = art.x, y = art.y, picture = "PAINTINGS", frame = art.frame, scale = 0.85}
    end
  end
  for _, guard in ipairs(guards) do
    sprites[#sprites + 1] = {x = guard.x, y = guard.y, picture = "GUARD", frame = (clock // 18) % 2}
  end
  view.sprites = sprites
  raycast("VIEW", view)
  img("VIEW", 0, 0, {scale = 2})
  rect(0, 288, 480, 32, 0x11151F)
  rect(0, 286, 480, 2, 0xA9864D)
  if state == "title" then
    shade(0, 0, 480, 286)
    text("MUSEO DE", 240, 37, {font = "arcade", align = "center", color = 0xF5DA9B,
      outline = 0x14121C, scale = 2})
    text("MEDIANOCHE", 240, 75, {font = "arcade", align = "center", color = 0xF5DA9B,
      outline = 0x14121C, scale = 2})
    text("RECUPERA CINCO CUADROS", 240, 119, {font = "arcade", align = "center", color = 0xFFFFFF})
    text("ESQUIVA A LOS VIGILANTES", 240, 142, {font = "arcade", align = "center", color = 0xE4B0A5})
    text("A: RECOGER  C: SIGILO", 240, 190, {font = "arcade", align = "center", color = 0xD5D9E2})
    text("B+FLECHAS: PASO LATERAL", 240, 211, {font = "arcade", align = "center", color = 0xD5D9E2})
    if (clock // 30) % 2 == 0 then text("PULSA A", 240, 252, {font = "arcade", align = "center", color = 0xFFD890}) end
    return
  end
  if alarm > 0 then box(4, 4, 472, 278, 0xCB4E48) end
  line(234, 143, 246, 143, 0xE8D9B4)
  line(240, 137, 240, 149, 0xE8D9B4)
  text("ARTE " .. found .. "/5", 12, 297, {font = "arcade", color = 0xF5D58B})
  text("AVISOS " .. strikes .. "/3", 468, 297, {font = "arcade", align = "right", color = 0xE69B8B})
  if message_time > 0 then
    plate(49, 250, 382, 29, 0x202532)
    text(message, 240, 257, {font = "arcade", align = "center", color = 0xF7E9CF})
  end
  if state == "won" or state == "over" then
    shade(0, 0, 480, 286)
    local label = state == "won" and "ESCAPASTE" or "ATRAPADO"
    text(label, 240, 103, {font = "arcade", align = "center", color = state == "won" and 0xF4D88F or 0xFF8F81,
      outline = 0x10131E, scale = 2})
    if state == "won" then text("CON EL ARTE", 240, 141, {font = "arcade", align = "center", color = 0xF4D88F}) end
    text(state == "won" and "A: JUGAR OTRA VEZ" or "A: REINTENTAR", 240, 181,
      {font = "arcade", align = "center", color = 0xFFFFFF})
  end
end
