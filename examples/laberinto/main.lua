-- Laberinto: first person, the way Wolfenstein 3D drew it: raycast() (docs/lua.md "First person") draws the maze
-- seen from inside onto a 240x160 canvas, a column at a time, walls textured and darker far away, the ghosts, gems
-- and lamps standing in it hidden by the walls in front; the game shows it twice as big under a status bar.
-- Up and down walk, left and right turn (with B held, they step sideways). A shoots straight ahead. Take the five
-- gems and find the green door; the ghosts take a life when they reach you.
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
  lives, gems, state = 3, 0, "play"
end

function _init()
  show(0)
  canvas("VIEW", 240, 160)
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
      lives, P.hurt, flash = lives - 1, 90, 10
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
    end
  end
  if gems == 5 and P.x > 14.5 and math.floor(P.y) == 14 then state, t = "won", 0 sfx("SFX_WIN") end -- at the door
end

function _update()
  t = t + 1
  if flash > 0 then flash = flash - 1 end
  if shot_t > 0 then shot_t = shot_t - 1 end
  if state == "title" then
    P.x, P.y, P.a = 8, 7.5, (t / 2) % 360
    if btnp("a") or btnp("start") then reset() end
  elseif state == "play" then
    update_play()
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
  if flash > 0 then rect(0, 0, 480, 320, 0x800000) end
  if state == "title" then
    text("LABERINTO", 240, 80, {font = "arcade", scale = 3, align = "center", color = 0xFFE070, outline = 0x200808})
    if (t // 30) % 2 == 0 then text("PULSA A", 240, 200, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x200808}) end
    return
  end
  if shot_t > 0 then circ(240, 160, 10 - shot_t, 0xFFF0A0) end
  line(234, 160, 246, 160, 0xFFFFFF) line(240, 154, 240, 166, 0xFFFFFF) -- the sight
  rect(0, 288, 480, 32, 0x1A1A2A) -- the status bar
  text("VIDAS " .. lives, 12, 296, {font = "arcade", color = 0xFF8080})
  text("GEMAS " .. gems .. "/5", 330, 296, {font = "arcade", color = 0x80FFC0})
  if state == "won" then text("¡FUERA!", 240, 120, {font = "arcade", scale = 3, align = "center", color = 0x80FFC0, outline = 0x082010}) end
  if state == "over" then text("FIN", 240, 120, {font = "arcade", scale = 3, align = "center", color = 0xFF6060, outline = 0x200808}) end
end
