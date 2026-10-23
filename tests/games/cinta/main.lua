-- Cinta: a game the way a ZX Spectrum one looked, from the moment it loaded off the tape (art.py, art/make_art.py).
--   The loading: the border in red and cyan stripes while the pilot tone sounds, then blue and yellow as the data
--   comes; the screen's bitmap appears in the Spectrum's own order (a third at a time, one line of each character
--   row before the next), black on white, and then its colours, row by row. A skips it.
--   The room: 8x8 blocks of two colours each (ink and paper: a palette bank per block, as the attributes were); the
--   miner and the guardian are ink only and take the ink of the block they are in, so they change colour as they
--   pass, as Spectrum sprites did; the keys flash (ink and paper swapped, the FLASH attribute); air runs out.
-- Arrows walk; A jumps (straight up or along, and once in the air there is no steering: a Spectrum jump). Take the
-- five keys, then go through the gate. Mind the plants, the guardian, the floors that crumble and long falls.
local ROOM = require("room")
local RW, RH = 28, 16                      -- the room in blocks; two more rows under it for the status
local PILOT, DATA, COLOURS = 120, 240, 60  -- the loading's phases, in ticks
local GRAVITY, JUMP, MAX_FALL, DEADLY = 0.19, -3.4, 3, 36
local B = {black = 0x000000, blue = 0x0000D7, red = 0xD70000, magenta = 0xD700D7, green = 0x00D700, cyan = 0x00D7D7,
           yellow = 0xD7D700, white = 0xD7D7D7, bblue = 0x0000FF, bred = 0xFF0000, bgreen = 0x00FF00,
           byellow = 0xFFFF00, bwhite = 0xFFFFFF}
local ATTR = { -- a block's ink and paper, by the room's character; each one a palette bank
  ["."] = {1, B.bwhite, B.black}, ["#"] = {2, B.red, B.yellow}, ["="] = {3, B.bred, B.black},
  ["-"] = {4, B.red, B.black}, [">"] = {5, B.green, B.black}, ["*"] = {6, B.bgreen, B.black},
  k = {7, B.byellow, B.black}, X = {8, B.byellow, B.blue},
}

state, keys, lives, air, score = "load", 0, 3, 1, 0 -- (global: tests/cinta.script)
M, guard = {}, {}
local t, border, cells, gate_open = 0, B.black, {}, false
local miner_sh, guard_sh
local conveyor, crumble, crumbling = {}, {}, {}

local function char(tx, ty) return cells[ty * RW + tx + 1] or "#" end
local function setc(tx, ty, c) -- a block becomes another, with its tile and its colours
  cells[ty * RW + tx + 1] = c
  local tile = c == "-" and crumble[1] or (c == ">" and conveyor[1] or (c == "." and crumble[4] or nil))
  if tile then mset(1, tx, ty, tile | ATTR[c][1] << 12) end
end

local function colours(flash) -- every bank's two colours; the flashing ones swapped every 16 ticks
  for c, a in pairs(ATTR) do
    local ink, paper = a[2], a[3]
    if flash and (c == "k" or (c == "X" and gate_open)) then ink, paper = paper, ink end
    pal(a[1] * 16 + 1, ink)
    pal(a[1] * 16 + 2, paper)
    pal(a[1] * 16 + 1, a[2], true) -- the sprites' ink, by the same bank
  end
end

local function load_room()
  cells, keys, gate_open, air, crumbling = {}, 0, false, 1, {}
  bg(1, {map = "ROOM", prio = 1, wrap = false})
  conveyor = {mget(1, 13, 9) & 0xFFF, mget(1, 28, 0) & 0xFFF, mget(1, 28, 1) & 0xFFF}
  crumble = {mget(1, 9, 12) & 0xFFF, mget(1, 28, 2) & 0xFFF, mget(1, 28, 3) & 0xFFF, mget(1, 1, 1) & 0xFFF}
  for ty = 0, RH + 1 do
    local row = ROOM[ty + 1]
    for tx = 0, RW - 1 do
      local c = row:sub(tx + 1, tx + 1)
      if c == "P" then M = {x = tx * 8, y = ty * 8, vx = 0, vy = 0, ground = true, face = 1, top = ty * 8, dead = 0} c = "." end
      if c == "g" then guard = {x = tx * 8, y = ty * 8, dir = 1, min = 9 * 8, max = 20 * 8} c = "." end
      cells[ty * RW + tx + 1] = c
      mset(1, tx, ty, (mget(1, tx, ty) & 0xFFF) | (ATTR[c] or ATTR["."])[1] << 12)
    end
  end
  for _, c in ipairs(cells) do if c == "k" then keys = keys + 1 end end
  colours(false)
end

function _init()
  miner_sh, guard_sh = sheet("MINER"), sheet("GUARD")
  palette("OBJ", true)
  show(0) -- the loading is drawn at full resolution; the room's layers come after
  load_room()
end

-- ------------------------------------------------------------------ playing

local function solid(c) return c == "#" end
local function ledge(c) return c == "=" or c == "-" or c == ">" end

local function die()
  if M.dead > 0 then return end
  M.dead = 1
  tone(0, 220, {wave = "square", slide = -300, len = 0.6, volume = 0.2})
end

local function update_miner()
  local onfloor = M.ground
  if onfloor then
    local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    if dx ~= 0 then M.face = dx end
    M.vx = dx
    if btnp("a") then -- a jump: up, or along; no steering once off the ground
      M.vy, M.ground, M.top = JUMP, false, M.y
      tone(0, 400, {wave = "square", slide = 900, len = 0.25, volume = 0.15})
    end
  end
  local nx = M.x + M.vx -- across: walls stop it (the body is x+4 .. x+11)
  local edge = M.vx > 0 and nx + 11 or nx + 4
  if M.vx == 0 or not (solid(char(edge // 8, (M.y + 2) // 8)) or solid(char(edge // 8, (M.y + 13) // 8))) then M.x = nx end
  if M.ground then -- standing: what is under the feet
    local under = char((M.x + 8) // 8, (M.y + 16) // 8)
    if under == ">" then M.x = M.x + 0.6 end
    if under == "-" then
      local k = ((M.y + 16) // 8) * RW + (M.x + 8) // 8 + 1
      crumbling[k] = (crumbling[k] or 0) + 1
      local stage = crumbling[k] // 10
      local tx, ty = (M.x + 8) // 8, (M.y + 16) // 8
      if stage >= 3 then setc(tx, ty, ".") crumbling[k] = nil
      elseif stage > 0 then mset(1, tx, ty, crumble[stage + 1] | ATTR["-"][1] << 12) end
    end
    if not ledge(under) and not solid(under) and not ledge(char((M.x + 4) // 8, (M.y + 16) // 8))
       and not ledge(char((M.x + 11) // 8, (M.y + 16) // 8)) then
      M.ground, M.vy, M.top = false, 0, M.y -- off an edge
    end
    return
  end
  M.vy = math.min(M.vy + GRAVITY, MAX_FALL)
  local old = M.y + 16
  M.y = M.y + M.vy
  if M.vy < 0 and solid(char((M.x + 8) // 8, M.y // 8)) then M.y, M.vy = (M.y // 8 + 1) * 8, 0 end
  if M.vy > 0 then
    for _, px in ipairs({M.x + 4, M.x + 11}) do
      local fy = math.floor(M.y + 16)
      local c, top = char(math.floor(px) // 8, fy // 8), (fy // 8) * 8
      if (solid(c) or ledge(c)) and old <= top + 1 then
        if top - 16 - M.top > DEADLY then die() end -- too long a fall
        M.y, M.vy, M.ground, M.vx = top - 16, 0, true, 0
        return
      end
    end
  end
end

local function update_play()
  if M.dead > 0 then
    M.dead = M.dead + 1
    if M.dead > 60 then
      lives = lives - 1
      if lives <= 0 then state, t = "over", 0 else load_room() end
    end
    return
  end
  update_miner()
  air = air - 1 / (60 * 60)
  if air <= 0 then die() end
  guard.x = guard.x + guard.dir * 0.6
  if guard.x < guard.min or guard.x > guard.max then guard.dir = -guard.dir end
  if math.abs(guard.x - M.x) < 11 and math.abs(guard.y - M.y) < 14 then die() end
  for _, p in ipairs({{M.x + 5, M.y + 4}, {M.x + 10, M.y + 4}, {M.x + 5, M.y + 14}, {M.x + 10, M.y + 14}}) do
    local tx, ty = math.floor(p[1]) // 8, math.floor(p[2]) // 8
    local c = char(tx, ty)
    if c == "*" then die() end
    if c == "k" then
      setc(tx, ty, ".")
      keys, score = keys - 1, score + 100
      tone(1, 1200, {wave = "square", len = 0.08, volume = 0.15})
      if keys == 0 then gate_open = true end
    end
    if c == "X" and gate_open then
      state, t = "done", 0
      score = score + math.floor(air * 1000)
    end
  end
  if M.y > RH * 8 then die() end
end

-- the Hall of the Mountain King (Grieg, 1875), one voice, as the beeper had it
local TUNE = {"B3", "C#4", "D4", "E4", "F#4", "D4", "F#4", 0, "F4", "C#4", "F4", 0, "E4", "C4", "E4", 0,
              "B3", "C#4", "D4", "E4", "F#4", "D4", "F#4", "B4", "A4", "F#4", "D4", "F#4", "A4", 0, 0, 0}
local function beeper()
  if t % 9 == 0 then
    local n = TUNE[(t // 9) % #TUNE + 1]
    if n ~= 0 then tone(2, n, {wave = "square", duty = 0.5, len = 0.1, volume = 0.1}) end
  end
end

function _update()
  t = t + 1
  if state == "load" then
    if t == 1 then tone(0, 807, {wave = "square", volume = 0.08}) end -- the pilot tone
    if t == PILOT then tone(0) tone(3, 3000, {wave = "noise", volume = 0.05}) end -- the data
    if t == PILOT + DATA + COLOURS then tone(3) end
    if btnp("a") then
      if t < PILOT + DATA + COLOURS then t = PILOT + DATA + COLOURS tone(0) tone(3)
      else state, t = "play", 0 show(ALL) end
    end
  elseif state == "play" then
    update_play()
    if t % 16 == 0 then colours((t // 16) % 2 == 1) end
    beeper()
  elseif (state == "over" or state == "done") and t > 60 and btnp("a") then
    lives, score, state, t = 3, 0, "play", 0
    load_room()
  end
end

-- ------------------------------------------------------------------ drawing

local function stripes(a, b, h) -- the border, in bands: the tape's sound as the Spectrum showed it
  local y = -(t * 7 % (2 * h))
  local k = 0
  while y < 320 do
    local hh = h > 4 and h or 1 + (noise(y, t) * 4 + 4) // 1
    rect(0, y, 480, hh, k % 2 == 0 and a or b)
    y, k = y + hh, k + 1
  end
end

local function loading()
  if t < PILOT then stripes(B.red, B.cyan, 12)
  elseif t < PILOT + DATA + COLOURS then stripes(B.blue, B.yellow, 3)
  else rect(0, 0, 480, 320, B.black) end
  rect(16, 16, 448, 288, B.bwhite) -- the paper before anything comes
  local lines = math.max(0, math.min(144, (t - PILOT) * 144 // DATA))
  local rows = math.max(0, math.min(18, (t - PILOT - DATA) * 18 // COLOURS))
  local run = nil -- the bitmap, in the Spectrum's order (a third at a time, a line of each character row before the
  for y = 0, 144 do -- next): line y has come when its place in that order is before `lines`; drawn as runs of lines
    local come = y < 144 and (y // 48) * 48 + (y % 8) * 6 + (y % 48) // 8 < lines
    if come and not run then run = y end
    if not come and run then
      clip(16, 16 + run * 2, 448, (y - run) * 2)
      img("LOAD_MONO", 16, 16)
      run = nil
    end
  end
  if rows > 0 then -- the colours, a row of blocks at a time
    clip(16, 16, 448, rows * 16)
    img("LOAD", 16, 16)
  end
  clip()
  if t >= PILOT + DATA + COLOURS and (t // 30) % 2 == 0 then
    text("PULSA A", 240, 304, {font = "arcade", align = "center", color = B.bwhite})
  end
end

local function status()
  rect(16, 16 + RH * 16, 448, 32, B.black)
  rect(16, 16 + RH * 16, 448, 16, B.yellow)
  text("LA GALERIA", 240, 16 + RH * 16, {font = "arcade", align = "center", color = B.black})
  text("AIRE", 20, 16 + RH * 16 + 16, {font = "arcade", color = B.bwhite})
  rect(88, 16 + RH * 16 + 20, math.floor(200 * air), 8, air > 0.25 and B.bgreen or B.bred)
  text(string.format("%06d x%d", score, lives), 460, 16 + RH * 16 + 16, {font = "arcade", align = "right",
                                                                          color = B.byellow})
end

local function ink_bank(x, y) -- the bank of the block a sprite is in: it takes that block's ink
  return (ATTR[char(math.floor(x + 8) // 8, math.floor(y + 8) // 8)] or ATTR["."])[1]
end

function _draw()
  if state == "load" then loading() return end
  backdrop(border)
  scroll(1, -8, -8)
  spr_clear()
  if M.dead == 0 or (M.dead // 4) % 2 == 0 then
    local f = M.ground and M.vx ~= 0 and (t // 4) % 4 or 0
    spr(0, miner_sh, f, 8 + M.x, 8 + M.y, prio(0) | bank(ink_bank(M.x, M.y)) | (M.face < 0 and FLIP_X or 0))
  end
  spr(1, guard_sh, (t // 10) % 2, 8 + guard.x, 8 + guard.y, prio(0) | bank(ink_bank(guard.x, guard.y)) |
      (guard.dir < 0 and FLIP_X or 0))
  status()
  rect(0, 0, 480, 16, border) -- the border, over the blocks the game keeps outside the room
  rect(0, 304, 480, 16, border)
  rect(0, 0, 16, 320, border)
  rect(464, 0, 16, 320, border)
  if state == "over" then
    rect(112, 120, 256, 48, B.black)
    text("GAME OVER", 240, 136, {font = "arcade", align = "center", color = B.bred})
  elseif state == "done" then
    rect(112, 120, 256, 48, B.black)
    text("¡SALIDA!", 240, 136, {font = "arcade", align = "center", color = B.byellow})
  end
end
