-- lights: the lamps of a scene as a list, so a game says where they are and what they are doing, not how to draw them each
-- frame. A baked background is dimmed through its palette (img's dim or mul: free), then each light adds its glow on top
-- (light(): only the pixels it reaches cost), the way PlayStation games lit a pre-rendered room.
--
--   local lights = require("lights")
--   lights.ambient(0.35, 0.40, 0.55)              -- the room's own light, a colour factor each (a blue night); 1 1 1: as drawn
--   local lamp = lights.add({x = 120, y = 90, r = 80, color = 0xFFC060, flicker = 0.15})   -- a candle: its radius and light waver
--   local torch = lights.add({follow = player, ox = 8, oy = 12, r = 110, color = 0xFFFFFF, cone = {angle = 0, width = 60}})
--   lamp.on = false                               -- off; lamp.x, lamp.y, lamp.r, lamp.color, lamp.intensity move it
--   lights.update()                               -- each tick: the flickers
--   img("BG_BAR", 0, 0, {mul = lights.mul()})     -- the background, in the room's light
--   lights.draw()                                 -- then the glows (in _draw, after what they light, before the HUD)
--   lights.clear()                                -- when the room changes
-- A light with `follow` takes its place from that table's x and y (plus ox, oy) and, with `aim`, its beam's direction from
-- follow.dir (1 right, -1 left), `sub = true` makes a pool of shadow instead of light.
local lights = {}
local list, tick = {}, 0
local amb = {1, 1, 1}

function lights.ambient(r, g, b) amb = {r or 1, g or r or 1, b or r or 1} end

function lights.mul() -- for img's mul: the ambient as 0xRRGGBB
  local function c(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return c(amb[1]) << 16 | c(amb[2]) << 8 | c(amb[3])
end

function lights.add(l)
  l.on = l.on ~= false
  l.intensity = l.intensity or 1
  l.seed = #list * 7.3 + 1
  list[#list + 1] = l
  return l
end

function lights.remove(l)
  for i, v in ipairs(list) do if v == l then table.remove(list, i) return end end
end

function lights.clear() list = {} end
function lights.count() return #list end

function lights.update() tick = tick + 1 end

-- a flicker: a few sines that do not line up, so it never repeats evenly
local function wave(seed) return (math.sin(tick * 0.31 + seed) + math.sin(tick * 0.73 + seed * 2.1) * 0.6 + math.sin(tick * 1.9 + seed * 0.7) * 0.3) / 1.9 end

function lights.draw()
  for _, l in ipairs(list) do
    if l.on and l.intensity > 0 then
      local x, y = l.x or 0, l.y or 0
      if l.follow then x, y = l.follow.x + (l.ox or 0), l.follow.y + (l.oy or 0) end
      local k = l.flicker and (1 + wave(l.seed) * l.flicker) or 1
      local cone = l.cone
      if cone and l.aim and l.follow and l.follow.dir then
        cone = {angle = l.follow.dir < 0 and 180 - (cone.angle or 0) or (cone.angle or 0), width = cone.width}
      end
      light(math.floor(x), math.floor(y), math.max(1, math.floor(l.r * (l.flicker and (1 + wave(l.seed + 5) * l.flicker * 0.3) or 1))),
            l.color or 0xFFFFFF, {intensity = l.intensity * k, sub = l.sub, cone = cone})
    end
  end
end

return lights
