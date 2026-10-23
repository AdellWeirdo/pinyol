-- tools: what the buttons do. A is for talking, reading, opening, and then the pala (it cuts, digs and fights); B is
-- the item chosen (the tirachinas, the lantern); C changes which. All the rules about reach and hits are here.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local E = require("core.ents")
local Game = require("core.game")
local FX = require("core.fx")
local Combat = require("core.combat")
local Sound = require("core.sound")
local Pick = require("core.pickups")
local Interact = require("core.interact")
local Tools = {}

local Hero -- core.hero is loaded first and requires this file: it is fetched on first use
local function hero() Hero = Hero or require("core.hero") return Hero end

-- the rectangle the pala's blade covers in the strike, in the area's pixels: 14 x 14, 12 pixels in front of his middle
function Tools.pala_rect(h)
  local d = U.DIRS[h.face]
  local cx, cy = h.x + 8 + d[1] * 12, h.y + 9 + d[2] * 12
  return cx - 7, cy - 7, 14, 14
end

function Tools.slash_frame(h)
  return "slash_" .. hero().view(h) .. "_" .. (h.st < 6 and 0 or 1)
end

-- every tick of the strike: grass is cut, enemies are hit (each once a swing)
function Tools.pala_hit(h)
  local x, y, w, rh = Tools.pala_rect(h)
  Combat.strike(x, y, w, rh, 1, h.face, h.seen, h)
  local x0, y0 = math.floor(x / C.T), math.floor(y / C.T)
  local x1, y1 = math.floor((x + w - 1) / C.T), math.floor((y + rh - 1) / C.T)
  for gy = y0, y1 do
    for gx = x0, x1 do
      local f = W.cell_flags(gx, gy)
      if f and f.cut then Tools.cut(gx, gy, f) end
    end
  end
end

-- cuts a cell: it turns into what it becomes, leaves fly, something may be left behind
function Tools.cut(gx, gy, f)
  W.set(gx, gy, f.becomes or "grass_a")
  FX.leaves(gx * C.T + 8, gy * C.T + 8, 3)
  Sound.play("cut")
  Game.stats.cut = Game.stats.cut + 1
  Pick.roll({{"cherry", 22}, {"heart", 8}, {"pinyoles", 8}}, gx * C.T + 8, gy * C.T + 10)
  if Game.stats.cut == 1 then achieve("primera_hierba") end
end

-- A in front of something: talk, read, open; or a diggable cell: dig; or swing
function Tools.press_a(h)
  if Interact.try(h) then return end
  local fx, fy = hero().front(h, 10)
  local gx, gy = math.floor(fx / C.T), math.floor(fy / C.T)
  local f = W.cell_flags(gx, gy)
  if f and f.dig then
    hero().set(h, "dig", gx, gy)
    return
  end
  hero().set(h, "swing")
end

function Tools.dig(h)
  local gx, gy = h.dig_cell[1], h.dig_cell[2]
  local f = W.cell_flags(gx, gy)
  if not (f and f.dig) then return end
  W.set(gx, gy, f.becomes or "hole_dug")
  FX.particle({x = gx * C.T + 4, y = gy * C.T + 2, vy = -1.5, vx = 0.4, grav = 0.15, frames = {"dirt_clod"}, life = 16})
  FX.particle({x = gx * C.T + 6, y = gy * C.T + 2, vy = -1.2, vx = -0.4, grav = 0.15, frames = {"dirt_clod"}, life = 14})
  Sound.play("dig")
  Game.stats.dug = Game.stats.dug + 1
  Interact.dug(gx, gy)
end

-- B: what is chosen
function Tools.press_b(h)
  local item = Game.b
  if item == "tirachinas" then
    if Game.pinyoles > 0 then
      hero().set(h, "shoot")
    else
      Sound.play("deny")
    end
  elseif item == "linterna" then
    Game.lantern_on = not Game.lantern_on
    Sound.play("select")
    hero().set(h, "lantern")
  end
end

function Tools.fire(h)
  Game.add_pinyoles(-1)
  Sound.play("shoot")
  local d = U.DIRS[h.face]
  local sx, sy = h.x + 4 + d[1] * 8, h.y + 4 + d[2] * 8
  local Shot = require("core.shot")
  Shot.new(sx, sy, d[1] * 3.5, d[2] * 3.5)
end

-- the lantern, lit, burns what is burnable within reach (a cobweb across a gap)
function Tools.lantern_tick(h)
  if not (Game.lantern_on and Game.has("linterna")) then return end
  local cx, cy = h.x + 8, h.y + 10
  for gy = math.floor((cy - 20) / C.T), math.floor((cy + 20) / C.T) do
    for gx = math.floor((cx - 20) / C.T), math.floor((cx + 20) / C.T) do
      local f = W.cell_flags(gx, gy)
      if f and f.burn and U.dist(cx, cy, gx * C.T + 8, gy * C.T + 8) < 22 then
        W.set(gx, gy, f.becomes or "floor_a")
        FX.particle({x = gx * C.T + 4, y = gy * C.T + 4, vy = -0.5, frames = {"flame_0", "flame_1", "flame_0", "flame_1"}, speed = 5, sort = 40})
        FX.particle({x = gx * C.T + 10, y = gy * C.T + 6, vy = -0.4, frames = {"flame_1", "flame_0", "flame_1"}, speed = 5, sort = 40})
        Sound.play("secret")
      end
    end
  end
end

-- C: the next item of those he has, in the order they were found
local ORDER = {"tirachinas", "linterna"}
function Tools.cycle_b()
  local have = {}
  for _, n in ipairs(ORDER) do if Game.has(n) then have[#have + 1] = n end end
  if #have < 2 then return end
  local at = 0
  for i, n in ipairs(have) do if n == Game.b then at = i end end
  Game.b = have[at % #have + 1]
  Sound.play("select")
end

return Tools
