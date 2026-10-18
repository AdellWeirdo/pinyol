-- particles: sparks, smoke, dust, confetti, rain, embers, fire: many small things that fly, fall, shrink and change colour.
--
--   local particles = require("particles")
--   local fx = particles.new()
--   fx:burst(x, y, 30, {speed = 3, colours = {0xFFF0A0, 0xFF8030, 0x803020}, gravity = 0.1, life = 40, size = 3})
--   local fire = fx:emit({x = 120, y = 200, rate = 0.8, angle = -90, spread = 40, speed = 1, life = 40, shape = "glow",
--                         size = 7, colours = {0xFFE080, 0xFF6020, 0x401008}})   -- one every tick or so, for as long as it burns
--   fire:move(x, y)   fire:stop()        -- (or follow = player: it takes that table's x and y, plus ox and oy)
--   in _update: fx:update()        in _draw: fx:draw()
--
-- Options of burst and emit (all optional): speed (pixels a tick, the fastest), angle and spread (degrees: where they go,
-- 0 is right, -90 up; spread 360 is everywhere), gravity (pixels a tick, each tick), wind (the same sideways), drag (0..1 of
-- the speed lost each tick), life (ticks), size (radius at the start), size_end (how big it is at the end, as a part of the
-- start: 0, the default, shrinks to nothing; 2 grows, as smoke does), colours (from the first to the last as they age),
-- shape:
--   "circle", "square", "pixel"   plain, as they are
--   "glow"    a soft round light added to what is under it (a spark, an ember, a flame): light(), the PlayStation's add
--   "shadow"  the same taken away (smoke, a dark vapour)
--   "sprite"  the picture `image` (frame `frame`; size 1 is its own size), opaque where the picture is, or mixed with `blend` =
--             "add", "sub", "quarter" or "alpha"; `fade = true` (and always with "alpha") takes it away as it ages
-- A group keeps 600 at most: the oldest go first. Glows and the scaled sprites cost the frame's few drawing slots (128 for
-- every light, gradient, quad and scaled picture together): a group draws the 64 youngest glows and shadows of a frame, and
-- the 48 youngest sprites that are scaled; the older ones of those shapes are skipped: many small lights are for a few sparks, not
-- for a snowstorm. On the console each particle costs about 50 us of Lua a frame (update and draw) besides its pixels: a camp
-- fire of ~110 (flames, embers, smoke) is 2.5 ms of tick, 3 of drawing and 8 of strips; keep a scene to some 100.
local M = {}
local Group = {}
Group.__index = Group
local Emitter = {}
Emitter.__index = Emitter

local MAX = 600
local GLOWS, SPRITES = 64, 48
local GLOW_OPT, SHADOW_OPT = {intensity = 1}, {intensity = 1, sub = true} -- (one table each, not one a particle: light() copies what it needs)

function M.new() return setmetatable({list = {}, emitters = {}}, Group) end

local function spawn(self, x, y, n, o)
  local speed, angle, spread = o.speed or 2, math.rad(o.angle or -90), math.rad(o.spread or 360)
  local life, colours = o.life or 30, o.colours or {0xFFFFFF}
  for _ = 1, n do
    local a = angle + (math.random() - 0.5) * spread
    local v = speed * (0.3 + 0.7 * math.random())
    local l = math.max(1, math.floor(life * (0.6 + 0.8 * math.random())))
    local p = {x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v, life = l, left = l, size = o.size or 2,
               size_end = o.size_end or 0, gravity = o.gravity or 0, wind = o.wind or 0, drag = o.drag or 0.02,
               colours = colours, nc = #colours, shape = o.shape or "circle", image = o.image, frame = o.frame, blend = o.blend, fade = o.fade}
    if #self.list >= MAX then table.remove(self.list, 1) end
    self.list[#self.list + 1] = p
  end
end

function Group:burst(x, y, n, o) spawn(self, x, y, n, o or {}) end

-- an emitter: `rate` particles a tick (0.25: one every four), from x, y (or following a table), until stop() or `ticks`
function Group:emit(o)
  local e = setmetatable({o = o, x = o.x or 0, y = o.y or 0, acc = 0, left = o.ticks, on = true, group = self}, Emitter)
  self.emitters[#self.emitters + 1] = e
  return e
end

function Emitter:move(x, y) self.x, self.y = x, y end
function Emitter:stop() self.on = false end

function Group:update()
  local es = self.emitters
  for i = #es, 1, -1 do
    local e, o = es[i], es[i].o
    if e.on then
      if o.follow then e.x, e.y = o.follow.x + (o.ox or 0), o.follow.y + (o.oy or 0) end
      e.acc = e.acc + (o.rate or 1)
      local n = math.floor(e.acc)
      e.acc = e.acc - n
      if n > 0 then spawn(self, e.x, e.y, n, o) end
      if e.left then
        e.left = e.left - 1
        if e.left <= 0 then e.on = false end
      end
    end
    if not e.on then table.remove(es, i) end
  end
  local list = self.list
  for i = #list, 1, -1 do
    local p = list[i]
    p.vx, p.vy = p.vx + p.wind, p.vy + p.gravity
    p.vx, p.vy = p.vx * (1 - p.drag), p.vy * (1 - p.drag)
    p.x, p.y = p.x + p.vx, p.y + p.vy
    p.left = p.left - 1
    if p.left <= 0 then list[i] = list[#list] list[#list] = nil end
  end
end

-- how many of the oldest of each kind to leave out so the youngest fit the frame's slots
local function over(list)
  local glows, sprites = 0, 0
  for _, p in ipairs(list) do
    if p.shape == "glow" or p.shape == "shadow" then glows = glows + 1
    elseif p.shape == "sprite" and math.abs(p.size - 1) > 0.05 then sprites = sprites + 1 end
  end
  return math.max(0, glows - GLOWS), math.max(0, sprites - SPRITES)
end

function Group:draw()
  local skip_glows, skip_sprites = over(self.list)
  for _, p in ipairs(self.list) do
    local age = 1 - p.left / p.life
    local ci = 1 + (age * p.nc) // 1
    local c = p.colours[ci > p.nc and p.nc or ci]
    local r = p.size * (1 + (p.size_end - 1) * age) -- how big: from the start's size to size_end times it
    local shape = p.shape
    if shape == "glow" or shape == "shadow" then
      if skip_glows > 0 then skip_glows = skip_glows - 1
      elseif r >= 1 then
        local o = shape == "glow" and GLOW_OPT or SHADOW_OPT
        o.intensity = 1 - age
        light(p.x // 1, p.y // 1, r // 1, c, o)
      end
    elseif shape == "sprite" then
      local w, h = imgsize(p.image)
      if w and r > 0.02 then
        local o = {frame = p.frame}
        if p.blend and p.blend ~= "alpha" then o[p.blend] = true end -- add, sub, quarter
        if p.fade or p.blend == "alpha" then o.alpha = 1 - age end
        local sc = r
        if math.abs(sc - 1) > 0.05 then
          if skip_sprites > 0 then skip_sprites = skip_sprites - 1 sc = nil else o.scale = sc end
        else sc = 1 end
        if sc then img(p.image, p.x - w * (o.scale or 1) / 2, p.y - h * (o.scale or 1) / 2, o) end
      end
    elseif shape == "pixel" or r < 0.75 then pset(p.x, p.y, c)
    elseif shape == "square" then rect(p.x - r, p.y - r, 2 * r, 2 * r, c)
    else circ(p.x, p.y, r, c) end
  end
end

function Group:count() return #self.list end
function Group:emitting() return #self.emitters end
function Group:clear() self.list, self.emitters = {}, {} end

return M
