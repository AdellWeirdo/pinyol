-- Oxígeno 48K: estación orbital con carga de cinta y atributos ZX Spectrum.
local ROOM = require("room")
local RW, RH = 28, 16
local PILOT, DATA, COLOURS = 120, 240, 60
local C = {black = 0x000000, blue = 0x0000D7, red = 0xD70000,
  cyan = 0x00D7D7, yellow = 0xD7D700, white = 0xD7D7D7,
  bright_blue = 0x0000FF, bright_red = 0xFF0000,
  bright_cyan = 0x00FFFF, bright_yellow = 0xFFFF00, bright_white = 0xFFFFFF}
local ATTR = {
  ["."] = {1, C.cyan, C.blue}, ["#"] = {2, C.white, C.black},
  ["+"] = {3, C.bright_cyan, C.black}, o = {4, C.bright_yellow, C.blue},
  X = {5, C.bright_white, C.red},
}

state, bottles, air, score = "load", 0, 1, 0
astronaut, robots = {}, {}
local cells, tick_count, blink, ship, bot, floor_tile = {}, 0, false, nil, nil, 0

local function cell(tx, ty)
  if tx < 0 or tx >= RW or ty < 0 or ty >= RH then return "#" end
  return cells[ty * RW + tx + 1]
end

local function paint_cell(tx, ty, c)
  cells[ty * RW + tx + 1] = c
  mset(1, tx, ty, floor_tile | ATTR[c][1] << 12)
end

local function set_colours()
  for c, a in pairs(ATTR) do
    local ink, paper = a[2], a[3]
    if blink and (c == "o" or (c == "X" and bottles == 0)) then
      ink, paper = paper, ink
    end
    pal(a[1] * 16 + 1, ink)
    pal(a[1] * 16 + 2, paper)
    pal(a[1] * 16 + 1, a[2], true)
  end
end

local function reset_mission()
  bg(1, {map = "ROOM", prio = 1, wrap = false})
  floor_tile = mget(1, 1, 1) & 0xFFF
  cells, robots, bottles, air, blink = {}, {}, 0, 1, false
  for ty = 0, RH - 1 do
    local row = ROOM[ty + 1]
    for tx = 0, RW - 1 do
      local c = row:sub(tx + 1, tx + 1)
      if c == "P" then
        astronaut = {x = tx * 8, y = ty * 8, face = 1, invuln = 0}
        c = "."
      elseif c == "r" then
        robots[#robots + 1] = {x = tx * 8, y = ty * 8, dir = 1, axis = #robots == 0 and "x" or "y"}
        c = "."
      elseif c == "o" then
        bottles = bottles + 1
      end
      cells[ty * RW + tx + 1] = c
      local tile = mget(1, tx, ty) & 0xFFF
      mset(1, tx, ty, tile | (ATTR[c] or ATTR["."])[1] << 12)
    end
  end
  set_colours()
end

function _init()
  ship, bot = sheet("ASTRONAUT"), sheet("ROBOT")
  palette("OBJ", true)
  show(0)
  reset_mission()
end

local function blocked(x, y)
  for _, px in ipairs({x + 2, x + 13}) do
    for _, py in ipairs({y + 2, y + 13}) do
      local c = cell(math.floor(px) // 8, math.floor(py) // 8)
      if c == "#" or c == "+" then return true end
    end
  end
  return false
end

local function move_astronaut()
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  local speed = dx ~= 0 and dy ~= 0 and 0.78 or 1.1
  if dx ~= 0 then
    astronaut.face = dx
    local nx = astronaut.x + dx * speed
    if not blocked(nx, astronaut.y) then astronaut.x = nx end
  end
  if dy ~= 0 then
    local ny = astronaut.y + dy * speed
    if not blocked(astronaut.x, ny) then astronaut.y = ny end
  end
  astronaut.invuln = math.max(0, astronaut.invuln - 1)
end

local function move_robots()
  for _, r in ipairs(robots) do
    local nx = r.x + (r.axis == "x" and r.dir * 0.55 or 0)
    local ny = r.y + (r.axis == "y" and r.dir * 0.45 or 0)
    if blocked(nx, ny) then r.dir = -r.dir else r.x, r.y = nx, ny end
    if astronaut.invuln == 0 and math.abs(r.x - astronaut.x) < 10 and math.abs(r.y - astronaut.y) < 10 then
      air = math.max(0, air - 0.22)
      astronaut.invuln = 70
      tone(0, 180, {wave = "square", slide = -220, len = 0.22, volume = 0.18})
    end
  end
end

local function collect()
  for _, point in ipairs({{astronaut.x + 4, astronaut.y + 4}, {astronaut.x + 11, astronaut.y + 4},
                           {astronaut.x + 4, astronaut.y + 11}, {astronaut.x + 11, astronaut.y + 11}}) do
    local tx, ty = math.floor(point[1]) // 8, math.floor(point[2]) // 8
    local c = cell(tx, ty)
    if c == "o" then
      paint_cell(tx, ty, ".")
      bottles, air, score = bottles - 1, math.min(1, air + 0.32), score + 100
      tone(0, 980, {wave = "square", slide = 450, len = 0.11, volume = 0.16})
      if bottles == 0 then set_colours() end
    elseif c == "X" and bottles == 0 then
      state, tick_count = "done", 0
      score = score + math.floor(air * 1000)
      tone(0, 660, {wave = "square", len = 0.3, volume = 0.16})
      return
    end
  end
end

local function play()
  move_astronaut()
  move_robots()
  if air <= 0 then
    state, tick_count = "over", 0
    return
  end
  collect()
  if state ~= "play" then return end
  air = math.max(0, air - 1 / (60 * 38))
  if air <= 0 then
    state, tick_count = "over", 0
    tone(0, 180, {wave = "square", slide = -300, len = 0.5, volume = 0.16})
  elseif tick_count % 180 == 0 and air < 0.3 then
    tone(0, 440, {wave = "square", len = 0.07, volume = 0.1})
  end
  if tick_count % 16 == 0 then blink = not blink; set_colours() end
end

function _update()
  tick_count = tick_count + 1
  if state == "load" then
    if tick_count == 1 then tone(0, 807, {wave = "square", volume = 0.07}) end
    if tick_count == PILOT then tone(0); tone(1, 3000, {wave = "noise", volume = 0.05}) end
    if tick_count == PILOT + DATA + COLOURS then tone(1) end
    if btnp("a") or btnp("start") then
      tone(0); tone(1)
      state, tick_count = "play", 0
      show(ALL)
    end
  elseif state == "play" then
    play()
  elseif (state == "over" or state == "done") and (btnp("a") or btnp("start")) then
    reset_mission()
    state, tick_count, score = "play", 0, 0
  end
end

local function stripes(a, b, height)
  local y, k = -(tick_count * 7 % (height * 2)), 0
  while y < 320 do
    rect(0, y, 480, height, k % 2 == 0 and a or b)
    y, k = y + height, k + 1
  end
end

local function loading()
  if tick_count < PILOT then stripes(C.red, C.cyan, 12)
  elseif tick_count < PILOT + DATA + COLOURS then stripes(C.blue, C.yellow, 3)
  else rect(0, 0, 480, 320, C.black) end
  rect(16, 16, 448, 288, C.bright_white)
  local lines = math.max(0, math.min(144, (tick_count - PILOT) * 144 // DATA))
  local rows = math.max(0, math.min(18, (tick_count - PILOT - DATA) * 18 // COLOURS))
  local run = nil
  for y = 0, 144 do
    local arrived = y < 144 and (y // 48) * 48 + (y % 8) * 6 + (y % 48) // 8 < lines
    if arrived and not run then run = y end
    if not arrived and run then
      clip(16, 16 + run * 2, 448, (y - run) * 2)
      img("LOAD_MONO", 16, 16)
      run = nil
    end
  end
  if rows > 0 then
    clip(16, 16, 448, rows * 16)
    img("LOAD", 16, 16)
  end
  clip()
  if tick_count >= PILOT + DATA + COLOURS then
    rect(24, 224, 432, 80, C.black)
    text("COGE LAS BOTELLAS DE O2", 240, 232, {font = "arcade", align = "center", color = C.bright_cyan})
    text("EVITA LOS ROBOTS", 240, 254, {font = "arcade", align = "center", color = C.bright_yellow})
    if tick_count % 60 < 40 then
      text("PULSA A", 240, 278, {font = "arcade", align = "center", color = C.bright_white})
    end
  end
end

local function bank_at(x, y)
  return (ATTR[cell(math.floor(x + 8) // 8, math.floor(y + 8) // 8)] or ATTR["."])[1]
end

local function status()
  rect(16, 272, 448, 32, C.black)
  rect(16, 272, 448, 16, C.yellow)
  text("OXIGENO 48K", 240, 272, {font = "arcade", align = "center", color = C.black})
  text("AIRE", 20, 288, {font = "arcade", color = C.bright_white})
  rect(82, 292, 168, 8, C.blue)
  rect(82, 292, math.floor(168 * air), 8, air > 0.25 and C.bright_cyan or C.bright_red)
  text("O2 " .. bottles .. "  " .. string.format("%04d", score), 458, 288,
       {font = "arcade", align = "right", color = C.bright_yellow})
end

function _draw()
  if state == "load" then loading(); return end
  backdrop(C.blue)
  scroll(1, -8, -8)
  spr_clear()
  if astronaut.invuln % 6 < 4 then
    local frame = tick_count % 16 < 8 and 0 or 1
    spr(0, ship, frame, 8 + astronaut.x, 8 + astronaut.y,
        prio(0) | bank(bank_at(astronaut.x, astronaut.y)) | (astronaut.face < 0 and FLIP_X or 0))
  end
  for i, r in ipairs(robots) do
    spr(i, bot, tick_count % 20 < 10 and 0 or 1, 8 + r.x, 8 + r.y,
        prio(0) | bank(bank_at(r.x, r.y)))
  end
  status()
  rect(0, 0, 480, 16, C.blue)
  rect(0, 304, 480, 16, C.blue)
  rect(0, 0, 16, 320, C.blue)
  rect(464, 0, 16, 320, C.blue)
  if state == "over" or state == "done" then
    rect(64, 100, 352, 104, C.black)
    text(state == "done" and "MISION CUMPLIDA" or "SIN AIRE", 240, 114,
         {font = "arcade", align = "center", color = state == "done" and C.bright_yellow or C.bright_red})
    text(state == "done" and "ESTAS EN LA ESCLUSA" or "LOS ROBOTS GANAN", 240, 144,
         {font = "arcade", align = "center", color = C.bright_white})
    text("A: OTRA VEZ", 240, 174, {font = "arcade", align = "center", color = C.bright_cyan})
  elseif bottles == 0 then
    text("ESCLUSA ABIERTA", 240, 20, {font = "arcade", align = "center", color = C.bright_yellow})
  end
end
