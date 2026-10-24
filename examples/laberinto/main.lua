-- Laberinto: first person, the way Wolfenstein 3D drew it: raycast() (docs/lua.md "First person") draws the maze
-- seen from inside onto a 240x144 canvas, a column at a time, walls textured and darker far away, the ghosts, gems
-- and lamps standing in it hidden by the walls in front; the game shows it twice as big under a status bar.
-- Up and down walk, left and right turn (with B held, they step sideways). A shoots straight ahead. Take the five
-- gems and find the green door; the ghosts take a life when they reach you.
local lang = require("lang")
local MAP = {
  "################",
  "#......#.......#",
  "#.BBBB.#.WWWW..#",
  "#.B..........W.#",
  "#.B..#####...W.#",
  "#....#...#.....#",
  "###..#...#..####",
  "#....#.......#.#",
  "#.WW.##.###..#.#",
  "#..W.........#.#",
  "#..W..BBBB.....#",
  "#.....B..B..WW.#",
  "#.###.B..B..W..#",
  "#.#...........##",
  "#.#..WWW..#....D",
  "################",
}
local WALLS = {["#"] = "TEX_STONE", B = "TEX_BRICK", W = "TEX_WOOD", D = "TEX_DOOR"}
local FOV = 66

state, lives, gems = "title", 3, 0 -- (global: tests/laberinto.script)
P, ghosts, items = {}, {}, {}
local t, flash, shot_t = 0, 0, 0
local toast_text, toast_t = nil, 0
local how_from, how_angle, how_h, how_wall, how_d = "title", 0, 120, "#", 0
local WALL_KEY = {["#"] = "wall_stone", B = "wall_brick", W = "wall_wood", D = "wall_door"}
local hurt_any = false -- a life lost in this run (for "intacto")
local view = {map = MAP, walls = WALLS, fov = FOV, fog = 12, ceiling = 0x2A2A38, floor = 0x4A4038, sprites = {}}

local function open(x, y) -- a square one can stand in
  local row = MAP[math.floor(y) + 1]
  local c = row and row:sub(math.floor(x) + 1, math.floor(x) + 1) or "#"
  return c == "."
end

local function reset()
  P = {x = 1.5, y = 1.5, a = 0, hurt = 0}
  ghosts = {{x = 10.5, y = 5.5, dir = 1}, {x = 3.5, y = 12.5, dir = -1}, {x = 13.5, y = 9.5, dir = 1}}
  items = {}
  for _, g in ipairs({{6.5, 1.5}, {11.5, 3.5}, {7.5, 7.5}, {1.5, 13.5}, {14.5, 12.5}}) do
    items[#items + 1] = {x = g[1], y = g[2], picture = "GEM", gem = true}
  end
  for _, l in ipairs({{4.5, 5.5}, {12.5, 7.5}, {8.5, 13.5}, {6.5, 10.5}}) do
    items[#items + 1] = {x = l[1], y = l[2], picture = "LAMP"}
  end
  lives, gems, state, hurt_any = 3, 0, "play", false
end

local function earn(id) -- an achievement, with a toast the first time
  if achieve(id) then toast_text, toast_t = lang.tr("ach_" .. id), 170 end
end

local function leave_how()
  P.a, state = how_angle, how_from
end

local function menu() -- the game's own item in the console's menu: how the picture is made
  menuitem()
  menuitem(lang.tr("how"), function()
    if state == "title" or state == "play" then
      how_from, how_angle, state = state, P.a, "how"
      earn("curioso")
    end
  end)
end

function _resume()
  lang.load()
  menu()
end

function _init()
  lang.load()
  menu()
  show(0)
  canvas("VIEW", 240, 144) -- (the status bar covers the rest)
  sound("SFX_SHOT", {wave = "noise", freq = 1200, slide = -2000, sustain = 0.02, decay = 0.15, volume = 0.35})
  sound("SFX_GEM", "coin", 4)
  sound("SFX_HURT", "hit", 3)
  sound("SFX_POOF", {wave = "sine", freq = 300, slide = 900, sustain = 0.05, decay = 0.25, volume = 0.3})
  sound("SFX_WIN", "powerup", 3)
end

local function move(dx, dy) -- slide along walls: each axis on its own, a little room kept from them
  local r = 0.2
  if open(P.x + dx + (dx > 0 and r or -r), P.y) then P.x = P.x + dx end
  if open(P.x, P.y + dy + (dy > 0 and r or -r)) then P.y = P.y + dy end
end

local function shoot()
  shot_t = 8
  sfx("SFX_SHOT")
  view.x, view.y, view.angle = P.x, P.y, P.a -- (the view is only set in _draw: a shot looks from where you are now)
  local wall_d = raycast("VIEW", view) -- what is straight ahead, and how far
  local a = math.rad(P.a)
  for i = #ghosts, 1, -1 do
    local g = ghosts[i]
    local gx, gy = g.x - P.x, g.y - P.y
    local ahead = gx * math.cos(a) + gy * math.sin(a)
    local aside = math.abs(-gx * math.sin(a) + gy * math.cos(a))
    if ahead > 0 and ahead < wall_d and aside < 0.35 then
      table.remove(ghosts, i)
      sfx("SFX_POOF")
      earn("cazafantasmas")
      return
    end
  end
end

local function update_play()
  local fwd = (btn("up") and 1 or 0) - (btn("down") and 1 or 0)
  local side = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local a = math.rad(P.a)
  if btn("b") then move((-math.sin(a)) * side * 0.06, math.cos(a) * side * 0.06)
  else P.a = (P.a + side * 3) % 360 end
  move(math.cos(a) * fwd * 0.07, math.sin(a) * fwd * 0.07)
  if btnp("a") then shoot() end
  if P.hurt > 0 then P.hurt = P.hurt - 1 end
  for _, g in ipairs(ghosts) do -- they drift along the corridors and come for you when near
    local gx, gy = P.x - g.x, P.y - g.y
    local d = math.sqrt(gx * gx + gy * gy)
    local nx, ny = g.x, g.y
    if d < 5 then nx, ny = g.x + gx / d * 0.025, g.y + gy / d * 0.025
    else nx = g.x + g.dir * 0.02 end
    if open(nx, ny) then g.x, g.y = nx, ny else g.dir = -g.dir end
    if d < 0.5 and P.hurt == 0 then
      lives, P.hurt, flash, hurt_any = lives - 1, 90, 10, true
      earn("susto")
      sfx("SFX_HURT")
      if lives <= 0 then state, t = "over", 0 end
    end
  end
  for i = #items, 1, -1 do
    local it = items[i]
    if it.gem and (it.x - P.x) ^ 2 + (it.y - P.y) ^ 2 < 0.25 then
      table.remove(items, i)
      gems = gems + 1
      sfx("SFX_GEM")
      earn("primer_paso")
      if gems == 5 then earn("tesoro") end
    end
  end
  if gems == 5 and P.x > 14.5 and math.floor(P.y) == 14 then state, t = "won", 0 sfx("SFX_WIN") earn("salida") if not hurt_any then earn("intacto") end end -- at the door
end

function _update()
  t = t + 1
  if flash > 0 then flash = flash - 1 end
  if toast_t > 0 then toast_t = toast_t - 1 end
  if shot_t > 0 then shot_t = shot_t - 1 end
  if state == "title" then
    P.x, P.y, P.a = 8, 7.5, (t / 2) % 360
    if btnp("a") or btnp("start") then reset() end
  elseif state == "play" then
    update_play()
  elseif state == "how" then
    P.a = (P.a + 0.5) % 360 -- the view turns by itself: every column is worked out again each frame
    if btnp("b") or btnp("start") then leave_how() end
  elseif t > 60 and btnp("a") then
    state = "title"
  end
end

-- ------------------------------------------------------------------ drawing

function _draw()
  view.x, view.y, view.angle = P.x, P.y, P.a
  local sprites, n = view.sprites, 0
  for _, it in ipairs(items) do n = n + 1 sprites[n] = sprites[n] or {} sprites[n].x, sprites[n].y, sprites[n].picture, sprites[n].frame = it.x, it.y, it.picture, 0 end
  for _, g in ipairs(ghosts) do n = n + 1 sprites[n] = sprites[n] or {} sprites[n].x, sprites[n].y, sprites[n].picture, sprites[n].frame = g.x, g.y, "GHOST", (t // 15) % 2 end
  for i = n + 1, #sprites do sprites[i] = nil end
  raycast("VIEW", view)
  img("VIEW", 0, 0, {scale = 2})
  if flash > 0 and not settings().reduce_flashing then rect(0, 0, 480, 320, 0x800000) end -- (a red flash: not for who asked for less)
  if state == "title" then
    text(lang.tr("title"), 240, 80, {font = "arcade", scale = 3, align = "center", color = 0xFFE070, outline = 0x200808})
    if (t // 30) % 2 == 0 or settings().reduce_flashing then text(lang.tr("press"), 240, 200, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x200808}) end
    return
  end
  if state == "how" then
    local d, wall = raycast("VIEW", view)
    how_d, how_wall = d, wall
    line(240, 0, 240, 130, 0xFFE070) -- the ray whose wall is measured below
    panel(12, 130, 456, 180)
    text(lang.tr("how_title"), 28, 140, {font = "arcade", color = 0x902020})
    local _, h = text(lang.tr("how_body", {cols = 240}), 28, 164, {font = "main", color = 0x201810, width = 420})
    how_h = h or how_h
    text(lang.tr("how_live", {d = string.format("%.1f", d), wall = lang.tr(WALL_KEY[wall] or "wall_stone")}), 28, 164 + how_h + 8, {font = "main", color = 0x105030, width = 420})
    text(lang.tr("how_back"), 452, 288, {font = "main", color = 0x605040, align = "right"})
    return
  end
  if shot_t > 0 then circ(240, 160, 10 - shot_t, 0xFFF0A0) end
  line(234, 160, 246, 160, 0xFFFFFF) line(240, 154, 240, 166, 0xFFFFFF) -- the sight
  rect(0, 288, 480, 32, 0x1A1A2A) -- the status bar
  text(lang.tr("lives", {n = lives}), 12, 296, {font = "arcade", color = 0xFF8080})
  text(lang.tr("gems", {n = gems}), 466, 296, {font = "arcade", align = "right", color = 0x80FFC0})
  if state == "won" then text(lang.tr("won"), 240, 120, {font = "arcade", scale = 3, align = "center", color = 0x80FFC0, outline = 0x082010}) end
  if state == "over" then text(lang.tr("over"), 240, 120, {font = "arcade", scale = 3, align = "center", color = 0xFF6060, outline = 0x200808}) end
  if toast_t > 0 then
    local w = textw(toast_text, {font = "arcade"})
    plate(240 - w // 2 - 8, 8, w + 16, 22, 0x202030)
    text(toast_text, 240, 12, {font = "arcade", align = "center", color = 0xFFE070})
  end
end
