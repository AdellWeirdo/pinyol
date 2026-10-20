-- field: the meadow. You walk, the tall grass hides fights (a step in it now and then), START shows the party.
-- The hero and the party are in `game` (main.lua), so a fight and the scene after it find them as they were.
local scene = require("scene")
local ui = require("ui")
local R = require("rules")
local ppu = require("ppu")
local MAP = require("data")

local F = {}
local T = MAP.tile
local SPEED = 1.2
local GRASS_STEPS, FIGHT_CHANCE = 4, 0.16 -- steps in tall grass before a fight can start, and the chance at each one after
local walker
local cam_x, cam_y = 0, 0
local last_cell, grass_steps, walk = nil, 0, 0

local function cell_at(px, py)
  local row = MAP.grid[py // T + 1]
  return row and row[px // T + 1]
end

local function solid_at(px, py)
  local c = cell_at(px, py)
  return c == nil or MAP.solid[c] == true
end

local function blocked(x, y) -- the hero's feet: the bottom of the 16 x 16 sprite
  return solid_at(x + 3, y + 10) or solid_at(x + 12, y + 10) or solid_at(x + 3, y + 15) or solid_at(x + 12, y + 15)
end

local function place_camera(g)
  cam_x = math.max(0, math.min(MAP.w * T - SCREEN_W // 2, g.x - 112))
  cam_y = math.max(0, math.min(MAP.h * T - SCREEN_H // 2, g.y - 72))
end

function F.camera() return cam_x, cam_y end
function F.hero_on_screen() return game.x - cam_x + 8, game.y - cam_y + 8 end

function F.enter()
  ppu.reset()
  walker = sheet("WALKER")
  palette("WORLD")
  palette("OBJ", true)
  bg(0)
  bg(1)
  bg(3)
  bg(2, {map = "FIELD", prio = 2, wrap = false, mosaic = true})
  backdrop(rgb(20, 40, 24))
  place_camera(game)
  last_cell, grass_steps = nil, 0
end

function F.resume() F.enter() end -- (back from the party's screen)

local function step_into(cx, cy)
  if cell_at(cx * T, cy * T) ~= MAP.tall then grass_steps = 0 return end
  grass_steps = grass_steps + 1
  if grass_steps >= GRASS_STEPS and math.random() < FIGHT_CHANCE then
    grass_steps = 0
    F.encounter(game.x < MAP.w * T / 2 and "west" or "east")
  end
end

function F.encounter(zone)
  scene.push(require("swirl"), {zone = zone})
end

function F.update()
  if btnp("start") then scene.push(require("status")) return end
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  if dx ~= 0 and dy ~= 0 then dx, dy = dx * 0.75, dy * 0.75 end
  if dx ~= 0 or dy ~= 0 then
    game.dir = dx ~= 0 and (dx > 0 and 1 or 3) or (dy > 0 and 2 or 0)
    if not blocked(game.x + dx * SPEED, game.y) then game.x = game.x + dx * SPEED end
    if not blocked(game.x, game.y + dy * SPEED) then game.y = game.y + dy * SPEED end
    walk = walk + 1
    local cx, cy = (game.x + 8) // T, (game.y + 12) // T
    if last_cell ~= cx * 1000 + cy then
      last_cell = cx * 1000 + cy
      step_into(cx, cy)
    end
  else
    walk = 0
  end
  place_camera(game)
end

function F.draw()
  scroll(2, cam_x, cam_y)
  local frame = game.dir * 2 + ((walk // 8) % 2)
  spr(0, walker, frame, math.floor(game.x - cam_x), math.floor(game.y - cam_y), prio(1) | MOSAIC)
  local g = game.party
  ui.box(8, 8, 230, 18 + 20 * #g)
  for i, m in ipairs(g) do
    text(string.format("%s  Nv%d  %d/%d", m.name, m.lv, m.hp, m.maxhp), 18, 16 + 20 * (i - 1), {font = "main", color = ui.INK})
  end
end

return F
