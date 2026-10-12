-- particles: sparks, smoke, dust, confetti, rain: many small things that fly, fall, shrink and change colour.
--
--   local particles = require("particles")
--   local fx = particles.new()
--   fx:burst(x, y, 30, {speed = 3, colours = {0xFFF0A0, 0xFF8030, 0x803020}, gravity = 0.1, life = 40, size = 3})
--   in _update: fx:update()        in _draw: fx:draw()
--
-- Options of burst (all optional): speed (pixels a tick, the fastest), angle and spread (degrees: where they go,
-- 0 is right, -90 up; spread 360 is everywhere), gravity (pixels a tick, each tick), drag (0..1 of the speed lost
-- each tick), life (ticks), size (radius at the start; they shrink to nothing), colours (from the first to the last
-- as they age), shape ("circle", "square" or "pixel"). A group keeps 600 at most: the oldest go first.
local M = {}
local Group = {}
Group.__index = Group

local MAX = 600

function M.new() return setmetatable({list = {}}, Group) end

function Group:burst(x, y, n, o)
  o = o or {}
  local speed, angle, spread = o.speed or 2, math.rad(o.angle or -90), math.rad(o.spread or 360)
  local life, colours = o.life or 30, o.colours or {0xFFFFFF}
  for _ = 1, n do
    local a = angle + (math.random() - 0.5) * spread
    local v = speed * (0.3 + 0.7 * math.random())
    local l = math.max(1, math.floor(life * (0.6 + 0.8 * math.random())))
    local p = {x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v, life = l, left = l, size = o.size or 2,
               gravity = o.gravity or 0, drag = o.drag or 0.02, colours = colours, shape = o.shape or "circle"}
    if #self.list >= MAX then table.remove(self.list, 1) end
    self.list[#self.list + 1] = p
  end
end

function Group:update()
  local list = self.list
  for i = #list, 1, -1 do
    local p = list[i]
    p.vy = p.vy + p.gravity
    p.vx, p.vy = p.vx * (1 - p.drag), p.vy * (1 - p.drag)
    p.x, p.y = p.x + p.vx, p.y + p.vy
    p.left = p.left - 1
    if p.left <= 0 then list[i] = list[#list] list[#list] = nil end
  end
end

function Group:draw()
  for _, p in ipairs(self.list) do
    local age = 1 - p.left / p.life
    local c = p.colours[math.min(#p.colours, 1 + math.floor(age * #p.colours))]
    local r = p.size * (1 - age)
    if p.shape == "pixel" or r < 0.75 then pset(p.x, p.y, c)
    elseif p.shape == "square" then rect(p.x - r, p.y - r, 2 * r, 2 * r, c)
    else circ(p.x, p.y, r, c) end
  end
end

function Group:count() return #self.list end
function Group:clear() self.list = {} end

return M
