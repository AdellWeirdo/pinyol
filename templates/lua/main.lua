-- A starting point: walk around a room bigger than the screen and pick up the gems.
-- Everything np2d@2 can do is in docs/lua.md, step by step in docs/tutorial.md; the examples show more of it.
--
--   room.lua  the room, as text: what is solid comes from it, and art.py draws the picture from it
--   art.py    draws art/*.png and audio/*.wav by code (--draw) and converts them into assets/
--
-- _init runs once, _update 60 times a second (input and rules), _draw before every frame (what to show).

ROOM = require("room") -- global, so tests can look at it
local TILE, SPEED = 8, 1.2
local SOLID = {["#"] = true, ["T"] = true, ["~"] = true}
local W_TILES, H_TILES = #ROOM[1], #ROOM

player = {x = 0, y = 0, dir = 2, step = 0} -- global too: tests move it around
gems = {}
local hero_sheet, gem_sheet
state = "play"         -- "play" or "done"
local timer, cam_x, cam_y = 0, 0, 0

local function tile_at(px, py) -- the character of the room under a pixel
  local tx, ty = math.floor(px / TILE), math.floor(py / TILE)
  if tx < 0 or ty < 0 or tx >= W_TILES or ty >= H_TILES then return "#" end
  return ROOM[ty + 1]:sub(tx + 1, tx + 1)
end

local function blocked(x, y) -- the player's feet: a 10x6 box at the bottom of its 16x16 sprite
  return SOLID[tile_at(x + 3, y + 10)] or SOLID[tile_at(x + 12, y + 10)] or
         SOLID[tile_at(x + 3, y + 15)] or SOLID[tile_at(x + 12, y + 15)]
end

local function start() -- the gems and the player where room.lua puts them
  gems, state, timer = {}, "play", 0
  for ty, row in ipairs(ROOM) do
    for tx = 1, #row do
      local ch = row:sub(tx, tx)
      if ch == "*" then gems[#gems + 1] = {x = (tx - 1) * TILE, y = (ty - 1) * TILE} end
      if ch == "@" then player.x, player.y = (tx - 1) * TILE - 4, (ty - 1) * TILE - 8 end
    end
  end
end

function _init()
  hero_sheet, gem_sheet = sheet("HERO"), sheet("GEM")
  palette("OBJ", true)                                -- the sprites' colours
  bg(1, {map = "ROOM", wrap = false})                 -- the room's picture on layer 1 (its palette comes with it)
  backdrop(rgb(20, 30, 40))
  start()
end

function _update()
  timer = timer + 1
  if state ~= "play" then
    if btnp("a") then start() end
    return
  end
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  if dx ~= 0 then player.dir = dx > 0 and 1 or 3 end   -- 0 up, 1 right, 2 down, 3 left
  if dy ~= 0 then player.dir = dy > 0 and 2 or 0 end
  -- move one axis at a time, so walls let you slide along them
  if not blocked(player.x + dx * SPEED, player.y) then player.x = player.x + dx * SPEED end
  if not blocked(player.x, player.y + dy * SPEED) then player.y = player.y + dy * SPEED end
  player.step = (dx ~= 0 or dy ~= 0) and player.step + 1 or 0

  for i = #gems, 1, -1 do                             -- pick up the gems you touch
    local g = gems[i]
    if math.abs(player.x + 8 - (g.x + 4)) < 9 and math.abs(player.y + 10 - (g.y + 4)) < 9 then
      table.remove(gems, i)
      sfx("SFX_GEM")
      if #gems == 0 then
        state = "done"
        sfx("SFX_DONE")
        local best = stored("best", 0)
        if best == 0 or timer < best then store("best", timer) end
      end
    end
  end
end

function _draw()
  -- the camera follows the player, without showing past the room's edges
  cam_x = math.max(0, math.min(W_TILES * TILE - W, player.x + 8 - W // 2))
  cam_y = math.max(0, math.min(H_TILES * TILE - H, player.y + 8 - H // 2))
  scroll(1, cam_x, cam_y)

  spr_clear()
  local frame = player.dir * 2 + (player.step // 10) % 2 -- two walking frames per direction
  spr(0, hero_sheet, frame, player.x - cam_x, player.y - cam_y)
  for i, g in ipairs(gems) do
    spr(i, gem_sheet, (ticks() // 8 + i) % 4, g.x - cam_x, g.y - cam_y)
  end

  -- text and panels are drawn at the screen's full 480x320, over the world
  plate(8, 8, 150, 30, 0xFFF4D6)
  text("Gemas: " .. #gems, 20, 12, 0x3A2A1E, "bold")
  if state == "done" then
    panel(90, 110, 300, 100)
    text("¡Todas!", SCREEN_W // 2, 126, 0x203040, "large_bold", "center")
    text(string.format("%.1f s · récord %.1f s", timer / 60, stored("best", timer) / 60), SCREEN_W // 2, 160,
         0x506070, "main", "center")
    text("A: otra vez", SCREEN_W // 2, 186, 0xC04030, "bold", "center")
  end
end
