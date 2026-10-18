-- rig: a character as pieces that hang on each other (a torso, a head on it, an arm on that), moved by animations of keyframes:
-- cut-out animation, the way Guardian Heroes, Vanillaware and a good part of the Saturn's 2D games made big characters move with
-- few pictures. Each piece is a picture drawn with a quad, turned about its pivot, so a lamp's light can tint it a corner at a time
-- and every piece keeps the PlayStation's look.
--
--   local rig = require("rig")
--   local hero = rig.new({
--     parts = {                                   -- parents before their children
--       {id = "body", image = "P_BODY", pivot = {10, 40}},                          -- pivot: where it is hung, in its picture
--       {id = "head", parent = "body", image = "P_HEAD", pivot = {8, 16}, at = {0, -40}, z = 1},   -- at: from its parent's pivot
--       {id = "arm",  parent = "body", image = "P_ARM",  pivot = {3, 2},  at = {8, -34}, z = 2},   -- z: in front of the rest
--     },
--     anims = {
--       idle = {len = 60, loop = true, tracks = {head = {rot = {{0, 0}, {30, 4}, {60, 0}}}, body = {y = {{0, 0}, {30, -1}, {60, 0}}}}},
--       wave = {len = 30, next = "idle", events = {{tick = 15, name = "peak"}},
--               tracks = {arm = {rot = {{0, 0, "smooth"}, {15, 90, "smooth"}, {30, 0}}}}},
--     },
--   })
--   hero:on("peak", function() sfx("WHOOSH") end)
--   hero:play("idle")                             -- again with the same name: it goes on; hero:play("wave", {restart = true})
--   in _update: hero:update()                     in _draw: hero:draw(x, y)      (x, y: where its origin, the feet, stands)
--   hero:draw(x, y, {flip = true, scale = 2, light = 0xC0C0FF, lights = {...}, dither = true})   -- the options of quad go through
--   hero:point("arm", 0, 18)                      -- where a point of a piece (from its pivot) is on the screen, as drawn last: the hand
--
-- A track is a list of keys {tick, value [, "smooth" | "step"]} for what changes in a piece: rot (degrees, clockwise on the screen), x and y (added to `at`),
-- sx and sy (scale, 1), frame (the picture's frame, never blended: it changes at its key). Between two keys the value goes
-- in a straight line, or eased ("smooth": slow at both ends), or stays ("step"). An animation: len (ticks), loop, next (what
-- follows when it ends), events (a name fired once when its tick passes), speed (1). play(name, {fade = ticks}) blends from
-- the pose it was in (6 ticks): without it a change of animation would jump. hero.name is the animation playing, hero.done
-- true once one that does not loop has ended with nothing after it.
local M = {}
local Rig = {}
Rig.__index = Rig

local DEFAULT_FADE = 6

local function sample(keys, t, default)
  if not keys or #keys == 0 then return default end
  if t <= keys[1][1] then return keys[1][2] end
  for i = 2, #keys do
    local b = keys[i]
    if t <= b[1] then
      local a = keys[i - 1]
      local u = b[1] > a[1] and (t - a[1]) / (b[1] - a[1]) or 1
      if a[3] == "step" then u = 0 elseif a[3] == "smooth" then u = u * u * (3 - 2 * u) end
      return a[2] + (b[2] - a[2]) * u
    end
  end
  return keys[#keys][2]
end

local function sample_frame(keys, t) -- the key before t: a picture changes, it is not blended
  if not keys or #keys == 0 then return nil end
  local f = keys[1][2]
  for _, k in ipairs(keys) do if k[1] <= t then f = k[2] end end
  return f
end

local function pose_of(self, anim, t)
  local pose = {}
  for _, part in ipairs(self.parts) do
    local tr = anim and anim.tracks and anim.tracks[part.id] or {}
    pose[part.id] = {rot = sample(tr.rot, t, 0), x = sample(tr.x, t, 0), y = sample(tr.y, t, 0),
                     sx = sample(tr.sx, t, 1), sy = sample(tr.sy, t, 1), frame = sample_frame(tr.frame, t)}
  end
  return pose
end

local function blend(a, b, k) -- k 0 is a, 1 is b
  local out = {}
  for id, p in pairs(b) do
    local q = a[id] or p
    out[id] = {rot = q.rot + (p.rot - q.rot) * k, x = q.x + (p.x - q.x) * k, y = q.y + (p.y - q.y) * k,
               sx = q.sx + (p.sx - q.sx) * k, sy = q.sy + (p.sy - q.sy) * k, frame = p.frame}
  end
  return out
end

function M.new(def)
  assert(type(def) == "table" and type(def.parts) == "table", "rig.new: parts is a list of pieces")
  local self = setmetatable({parts = {}, anims = def.anims or {}, handlers = {}, t = 0, speed = 1, by_id = {}}, Rig)
  for i, p in ipairs(def.parts) do
    assert(p.id and not self.by_id[p.id], "rig.new: every piece has its own id")
    assert(not p.parent or self.by_id[p.parent], "rig.new: " .. p.id .. "'s parent comes before it in parts")
    local part = {id = p.id, parent = p.parent, image = p.image, pivot = p.pivot, at = p.at or {0, 0}, z = p.z or 0, frame = p.frame, order = i}
    self.parts[i], self.by_id[p.id] = part, part
  end
  self.order = {} -- drawn back to front: by z, then as listed (the pieces never change z)
  for i, part in ipairs(self.parts) do self.order[i] = part end
  table.sort(self.order, function(p, q) if p.z ~= q.z then return p.z < q.z end return p.order < q.order end)
  self.q = {}
  self.pose = pose_of(self, nil, 0)
  return self
end

function Rig:on(name, fn) self.handlers[name] = fn end

function Rig:play(name, o)
  o = o or {}
  local anim = self.anims[name]
  assert(anim, "rig: no animation called " .. tostring(name))
  if self.name == name and not o.restart then return end
  local fade = self.anim and (o.fade or DEFAULT_FADE) or 0 -- (the first one has nothing to blend from)
  if fade > 0 then self.from = self.pose else self.pose, self.from = pose_of(self, anim, 0), nil end
  self.fade, self.fade_left = fade, fade
  self.name, self.anim, self.t, self.done = name, anim, 0, false
  self.speed = o.speed or anim.speed or 1
end

function Rig:update()
  local anim = self.anim
  if anim and not self.done then
    local prev = self.t
    local t = prev + self.speed
    local len = anim.len or 1
    local function fire(a, b) -- events with a < tick <= b
      for _, e in ipairs(anim.events or {}) do
        if e.tick > a and e.tick <= b and self.handlers[e.name] then self.handlers[e.name](self) end
      end
    end
    if t >= len then
      fire(prev, len)
      if anim.loop then
        t = t - len
        fire(-1, t)
      elseif anim.next then
        self:play(anim.next) -- blended from the pose this one ends on
        t, anim = 0, self.anim
      else
        t, self.done = len, true
      end
    else
      fire(prev, t)
    end
    self.t = t
    local pose = pose_of(self, anim, t)
    if self.fade_left and self.fade_left > 0 and self.from then
      self.fade_left = self.fade_left - 1
      pose = blend(self.from, pose, 1 - self.fade_left / self.fade)
    end
    self.pose = pose
  end
end

-- the pieces placed on the screen: each one's affine matrix (x' = a x + c y + e, y' = b x + d y + f)
function Rig:place(x, y, o)
  o = o or {}
  local s = o.scale or 1
  local base = {a = o.flip and -s or s, b = 0, c = 0, d = s, e = x, f = y}
  local world = {}
  for _, part in ipairs(self.parts) do
    local p = self.pose[part.id] or {rot = 0, x = 0, y = 0, sx = 1, sy = 1}
    local par = part.parent and world[part.parent] or base
    local r = math.rad(p.rot)
    local cs, sn = math.cos(r), math.sin(r)
    -- local matrix: translate(at + pose) * rotate * scale; then the parent's on top
    local la, lb, lc, ld = cs * p.sx, sn * p.sx, -sn * p.sy, cs * p.sy
    local lx, ly = part.at[1] + p.x, part.at[2] + p.y
    world[part.id] = {
      a = par.a * la + par.c * lb, b = par.b * la + par.d * lb,
      c = par.a * lc + par.c * ld, d = par.b * lc + par.d * ld,
      e = par.a * lx + par.c * ly + par.e, f = par.b * lx + par.d * ly + par.f,
    }
  end
  self.world, self.opts = world, o
end

function Rig:point(id, lx, ly)
  local m = assert(self.world and self.world[id], "rig:point: draw or place it first, and use a piece's id")
  return m.a * lx + m.c * ly + m.e, m.b * lx + m.d * ly + m.f
end

function Rig:draw(x, y, o)
  self:place(x, y, o)
  o = o or {}
  local q, world, pose = self.q, self.world, self.pose
  for k in pairs(q) do q[k] = nil end -- one options table for every piece (quad reads what it needs)
  for k, v in pairs(o) do if k ~= "flip" and k ~= "scale" then q[k] = v end end
  for _, part in ipairs(self.order) do
    local image = part.image
    local w, h
    if image then w, h = imgsize(image) end
    if w then
      local m = world[part.id]
      local pv = part.pivot
      local px, py = pv and pv[1] or w / 2, pv and pv[2] or h / 2
      local a, b, c, d, e, f = m.a, m.b, m.c, m.d, m.e, m.f
      local l, t, r, bt = -px, -py, w - px, h - py -- the picture's corners from its pivot
      local p = pose[part.id]
      q.frame = p and p.frame or part.frame or 0
      quad(image, a * l + c * t + e, b * l + d * t + f, a * r + c * t + e, b * r + d * t + f,
           a * r + c * bt + e, b * r + d * bt + f, a * l + c * bt + e, b * l + d * bt + f, q)
    end
  end
end

return M
