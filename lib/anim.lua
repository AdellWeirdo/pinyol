-- anim: animations with names, as Aseprite tags or a sprite sheet's rows: which frames, how long each, whether it
-- loops, goes back and forth or ends (and what comes after), and events on frames (a footstep, the moment a blow lands).
--
--   local anim = require("anim")
--   local a = anim.new({
--     idle  = {frames = {0}},
--     run   = {frames = {1, 2, 3, 4}, fps = 10},
--     shoot = {frames = {5, 6}, ms = {60, 120}, loop = false, next = "idle", events = {[2] = "fire"}},
--     bob   = {frames = {0, 1, 2}, fps = 8, mode = "pingpong"},
--   })
--   a:on("fire", function() spawn_bullet() end)
--   a:play("run")            -- (already playing it: goes on; a:play("run", true) starts it again)
--   a:update()               -- once a tick
--   img("SPR_HERO", x, y, {frame = a.frame})  or  spr(n, sheet, a.frame, x, y)
-- a.name is the animation playing, a.done true once one that does not loop has ended (and has no next).
local M = {}
local A = {}
A.__index = A

function M.new(defs)
  local self = setmetatable({defs = {}, handlers = {}, name = nil, frame = 0, done = false}, A)
  for name, d in pairs(defs) do
    assert(type(d.frames) == "table" and #d.frames > 0, "anim: " .. tostring(name) .. " has no frames")
    local ticks = {}
    for i = 1, #d.frames do -- how long each frame stays, in ticks (60 a second)
      local ms = d.ms and (type(d.ms) == "table" and d.ms[i] or d.ms) or 1000 / (d.fps or 8)
      ticks[i] = math.max(1, math.floor(ms * 60 / 1000 + 0.5))
    end
    self.defs[name] = {frames = d.frames, ticks = ticks, loop = d.loop ~= false and d.mode ~= "once",
                       pingpong = d.mode == "pingpong", next = d.next, events = d.events or {}}
  end
  return self
end

function A:on(event, fn)
  self.handlers[event] = self.handlers[event] or {}
  table.insert(self.handlers[event], fn)
  return self
end

local function shown(self) -- the frame now shown: its picture and its events
  local d = self.def
  self.frame = d.frames[self.i]
  local e = d.events[self.i]
  if e then for _, fn in ipairs(self.handlers[e] or {}) do fn(self, e) end end
end

function A:play(name, again)
  if self.name == name and not again and not self.done then return self end
  local d = self.defs[name]
  assert(d, "anim: no animation called " .. tostring(name))
  self.name, self.def, self.i, self.t, self.dir, self.done = name, d, 1, 0, 1, false
  shown(self)
  return self
end

function A:update()
  local d = self.def
  if not d or self.done then return end
  self.t = self.t + 1
  if self.t < d.ticks[self.i] then return end
  self.t = 0
  local n = #d.frames
  local i = self.i + self.dir
  if d.pingpong and n > 1 and (i > n or i < 1) then
    self.dir = -self.dir
    i = self.i + self.dir
  elseif i > n then
    if d.next then return self:play(d.next, true) end
    if not d.loop then self.done = true return end
    i = 1
  end
  self.i = i
  shown(self)
end

function A:length(name) -- ticks the animation lasts once through
  local d = self.defs[name or self.name]
  local t = 0
  for _, k in ipairs(d.ticks) do t = t + k end
  return t
end

return M
