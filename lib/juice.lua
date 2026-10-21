-- juice: what makes a game feel alive, after "Juice it or lose it" (Jonasson and Purho) and "The art of
-- screenshake" (Nijman): things move with an ease instead of jumping, the screen shakes on a hit, a moment freezes
-- when a blow lands, a flash.
--
--   local juice = require("juice")
--   juice.tween(door, {y = 40}, 0.5, "out_bounce")   -- door.y goes to 40 in half a second, bouncing at the end
--   juice.shake(6)                                    -- the screen shakes 6 pixels, and calms down
--   juice.trauma(0.5)                                 -- a hit's trauma, 0..1: the shake is its square (Eiserloh, GDC 2016), sampled from
--                                                     -- smooth noise, so a big blow shakes hard and a small one hardly; it wears off
--   juice.kick(0, -6)                                 -- a push in one direction (a shot's recoil), that eases back
--   local s = juice.spring(3, 0.5, 0)                 -- a second-order follower (frequency Hz, damping, response; t3ssel8r):
--   x = s:update(target)                              -- it chases target with overshoot or anticipation, a value a tick
--   juice.squash(hero, 0.3)                           -- hero.sx, hero.sy: squashed 30% (wider, lower) and springing back
--   juice.freeze(5)                                   -- five ticks frozen: the hit lands
--   juice.flash(0xFFFFFF, 3)                          -- three ticks of white
--   in _update:  if juice.update() then return end    -- true while frozen: skip the game's tick
--   in _draw:    camera(juice.offset()) ... camera()  then juice.draw() last, for the flash
--
-- Time: juice.after(1.5, fn) once, juice.every(0.5, fn [, times]) again and again (fn returning false stops it), and
-- juice.script(fn): fn runs as a scene that waits, juice.wait(seconds), juice.wait_until(test), juice.wait_for(tween):
--   juice.script(function()
--     juice.tween(hero, {x = 200}, 1) juice.wait(1)  say("¡Hola!")  juice.wait_until(function() return btnp("a") end)
--   end)
-- Tweens chain and repeat: juice.tween(...):delay(0.2):loops(3):yoyo():after(other, {y = 0}, 0.5):on_done(fn).
-- juice.cancel(handle) stops a tween, a timer or a script; juice.cancel(obj) every tween of obj.
local M = {}

-- easing curves: t from 0 to 1 -> how far along, 0 to 1 (some go past it and come back)
local function out_bounce(t)
  if t < 1 / 2.75 then return 7.5625 * t * t end
  if t < 2 / 2.75 then t = t - 1.5 / 2.75 return 7.5625 * t * t + 0.75 end
  if t < 2.5 / 2.75 then t = t - 2.25 / 2.75 return 7.5625 * t * t + 0.9375 end
  t = t - 2.625 / 2.75
  return 7.5625 * t * t + 0.984375
end
M.ease = {
  linear = function(t) return t end,
  in_quad = function(t) return t * t end,
  out_quad = function(t) return 1 - (1 - t) * (1 - t) end,
  in_out_quad = function(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end,
  in_cubic = function(t) return t * t * t end,
  out_cubic = function(t) return 1 - (1 - t) ^ 3 end,
  in_out_cubic = function(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end,
  in_back = function(t) return 2.70158 * t * t * t - 1.70158 * t * t end,
  out_back = function(t) return 1 + 2.70158 * (t - 1) ^ 3 + 1.70158 * (t - 1) ^ 2 end,
  out_elastic = function(t)
    if t == 0 or t == 1 then return t end
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1
  end,
  out_bounce = out_bounce,
  in_bounce = function(t) return 1 - out_bounce(1 - t) end,
}

local tweens, timers, scripts = {}, {}, {}
local shake, frozen, flash_colour, flash_left = 0, 0, 0, 0
local trauma, kick_x, kick_y, shake_t = 0, 0, 0, 0
local squashes = {}
local Tween = {}
Tween.__index = Tween

local function ticks(seconds) return math.max(1, math.floor(seconds * 60 + 0.5)) end

local function begin(tw) -- it starts moving: from where the fields are now; it takes them from older moves
  for _, o in ipairs(tweens) do
    if o.to and o.obj == tw.obj and o ~= tw then for k in pairs(tw.target) do o.to[k] = nil end end
  end
  tw.from, tw.to = {}, {}
  for k, v in pairs(tw.target) do tw.from[k], tw.to[k] = tw.obj[k], v end
  tw.started = true
end

local function make(obj, to, seconds, ease, done)
  local f = type(ease) == "function" and ease or M.ease[ease or "out_quad"]
  assert(f, "juice.tween: no ease called " .. tostring(ease))
  return setmetatable({obj = obj, target = to, t = 0, len = ticks(seconds), ease = f, done = done, wait = 0,
                       loops_left = 0, back = false}, Tween)
end

-- tween(obj, {field = target, ...}, seconds [, ease [, done]]): the fields move from where they are to the targets;
-- a field already moving stops its old move. done(obj) is called at the end. Returns the tween (to chain or cancel).
function M.tween(obj, to, seconds, ease, done)
  local tw = make(obj, to, seconds, ease, done)
  begin(tw)
  tweens[#tweens + 1] = tw
  return tw
end

function Tween:delay(seconds) -- it waits first (where the fields are when it starts is where it starts from)
  self.wait, self.started = ticks(seconds), false
  return self
end
function Tween:loops(n) self.loops_left = n or -1 return self end -- n more times (-1: for ever)
function Tween:yoyo() self.back = true if self.loops_left == 0 then self.loops_left = 1 end return self end -- and back
function Tween:on_done(fn) self.done = fn return self end
function Tween:after(obj, to, seconds, ease, done) -- the next move, once this one ends; returns it
  local nxt = make(obj, to, seconds, ease, done)
  self.next = nxt
  return nxt
end

function M.after(seconds, fn)
  local t = {left = ticks(seconds), fn = fn, every = nil}
  timers[#timers + 1] = t
  return t
end

function M.every(seconds, fn, times)
  local n = ticks(seconds)
  local t = {left = n, fn = fn, every = n, times = times}
  timers[#timers + 1] = t
  return t
end

-- script(fn [, ...]): fn runs as a coroutine, a tick at a time, waiting where it says; returns its handle
function M.script(fn, ...)
  local s = {co = coroutine.create(fn), args = table.pack(...), first = true}
  scripts[#scripts + 1] = s
  return s
end

function M.wait(seconds) -- (inside a script) let that much time pass
  local n = ticks(seconds or 0)
  for _ = 1, n do coroutine.yield() end
end
function M.wait_until(test) while not test() do coroutine.yield() end end
function M.wait_for(tw) while M.running(tw) do coroutine.yield() end end
function M.running(tw) -- a tween still moving or waiting (or what comes after it)
  for _, o in ipairs(tweens) do if o == tw then return true end end
  return tw.next ~= nil and M.running(tw.next) or false
end

function M.cancel(what) -- a tween (and what was to come after it), a timer, a script, or every tween of an object
  if getmetatable(what) == Tween then what.cancelled = true end
  for i = #tweens, 1, -1 do
    if tweens[i] == what or tweens[i].obj == what then table.remove(tweens, i) end
  end
  for _, tw in ipairs(tweens) do -- moves of the object waiting in a chain
    local n = tw.next
    while n do
      if n.obj == what then n.cancelled = true end
      n = n.next
    end
  end
  for i = #timers, 1, -1 do if timers[i] == what then table.remove(timers, i) end end
  for i = #scripts, 1, -1 do if scripts[i] == what then table.remove(scripts, i) end end
end

function M.shake(px) shake = math.max(shake, px) end
function M.trauma(amount) trauma = math.min(1, trauma + (amount or 0.3)) end -- adds up; the shake is trauma^2 * 16 px
function M.kick(dx, dy) kick_x, kick_y = kick_x + dx, kick_y + dy end

-- spring(f, z, r [, x0]): a value that follows a target as a mass on a spring (second-order dynamics, after t3ssel8r's
-- "Giving personality to procedural animations"): f, how fast it moves (Hz); z, damping (0: rings for ever, 1: no
-- overshoot); r, response (0: eases in, 1: reacts at once, > 1 overshoots, < 0 anticipates the other way first).
-- s:update(target) once a tick returns the value; s.x and s.v are where it is and how fast it goes.
local Spring = {}
Spring.__index = Spring
function M.spring(f, z, r, x0)
  local w = 2 * math.pi * (f or 1)
  return setmetatable({x = x0 or 0, v = 0, prev = x0 or 0, k1 = (z or 1) / (math.pi * (f or 1)), k2 = 1 / (w * w),
                       k3 = (r or 0) * (z or 1) / w}, Spring)
end
function Spring:update(target, dt)
  dt = dt or 1 / 60
  local xd = (target - self.prev) / dt -- the target's own speed
  self.prev = target
  local k2 = math.max(self.k2, dt * dt / 2 + dt * self.k1 / 2, dt * self.k1) -- stable however stiff
  self.x = self.x + dt * self.v
  self.v = self.v + dt * (target + self.k3 * xd - self.x - self.k1 * self.v) / k2
  return self.x
end
function Spring:set(x) self.x, self.v, self.prev = x, 0, x return self end

-- squash(obj, amount [, ticks]): obj.sx and obj.sy go to 1 + amount and 1 / (1 + amount) (the area kept: wider and lower
-- on a landing; a negative amount stretches, taller and thinner, for a jump) and spring back to 1 over ticks (8)
function M.squash(obj, amount, ticks)
  obj.sx, obj.sy = 1 + amount, 1 / (1 + amount)
  for _, q in ipairs(squashes) do if q.obj == obj then q.left, q.len = ticks or 8, ticks or 8 return end end
  squashes[#squashes + 1] = {obj = obj, left = ticks or 8, len = ticks or 8}
end
function M.freeze(ticks) frozen = math.max(frozen, ticks) end
function M.flash(colour, ticks) -- (none at all when the console is set to less flashing)
  if settings and settings().reduce_flashing then return end
  flash_colour, flash_left = colour or 0xFFFFFF, ticks or 3
end
function M.busy(obj) -- is it moving?
  for _, tw in ipairs(tweens) do if tw.obj == obj then return true end end
  return false
end

-- once a tick: true while frozen (the game should skip its own tick then)
function M.update()
  if flash_left > 0 then flash_left = flash_left - 1 end
  if frozen > 0 then frozen = frozen - 1 return true end
  for i = #tweens, 1, -1 do
    local tw = tweens[i]
    if not tw then break end -- (juice.reset() from a done)
    if tw.wait > 0 then
      tw.wait = tw.wait - 1
    else
      if not tw.started then begin(tw) end
      tw.t = tw.t + 1
      local k = tw.ease(math.min(1, tw.t / tw.len))
      for f, target in pairs(tw.to) do tw.obj[f] = tw.from[f] + (target - tw.from[f]) * k end
      if tw.t >= tw.len then
        for f, target in pairs(tw.to) do tw.obj[f] = target end
        if tw.loops_left ~= 0 then -- again (back the other way, for a yoyo)
          if tw.loops_left > 0 then tw.loops_left = tw.loops_left - 1 end
          if tw.back then tw.from, tw.to = tw.to, tw.from
          else for f in pairs(tw.to) do tw.obj[f] = tw.from[f] end end
          tw.t = 0
        else
          table.remove(tweens, i)
          if tw.done then tw.done(tw.obj) end
          if tw.next and not tw.next.cancelled then tw.next.started = false tweens[#tweens + 1] = tw.next end
        end
      end
    end
  end
  for i = #timers, 1, -1 do
    local t = timers[i]
    if not t then break end
    t.left = t.left - 1
    if t.left <= 0 then
      local again = t.every and t.fn() ~= false
      if t.every and again and t.times then t.times = t.times - 1 again = t.times > 0 end
      if not t.every then t.fn() end
      if again then t.left = t.every
      else for j = #timers, 1, -1 do if timers[j] == t then table.remove(timers, j) end end end
    end
  end
  for i = #scripts, 1, -1 do
    local s = scripts[i]
    if not s then break end
    local ok, err
    if s.first then s.first = false ok, err = coroutine.resume(s.co, table.unpack(s.args, 1, s.args.n))
    else ok, err = coroutine.resume(s.co) end
    if not ok then error(err, 0) end
    if coroutine.status(s.co) == "dead" then
      for j = #scripts, 1, -1 do if scripts[j] == s then table.remove(scripts, j) end end
    end
  end
  shake = shake > 0.5 and shake * 0.85 or 0
  trauma = trauma > 0.02 and trauma - 0.025 or 0 -- gone in two thirds of a second from a full hit
  kick_x, kick_y = kick_x * 0.8, kick_y * 0.8
  if math.abs(kick_x) < 0.3 then kick_x = 0 end
  if math.abs(kick_y) < 0.3 then kick_y = 0 end
  shake_t = shake_t + 1
  for i = #squashes, 1, -1 do
    local q = squashes[i]
    q.left = q.left - 1
    local k = q.left / q.len -- back to 1 with a little ring
    local a = (q.obj.sx - 1) * k * (1 + 0.3 * math.sin(k * math.pi * 2))
    q.obj.sx, q.obj.sy = 1 + a, 1 / (1 + a)
    if q.left <= 0 then q.obj.sx, q.obj.sy = 1, 1 table.remove(squashes, i) end
  end
  return false
end

function M.offset() -- where the screen is pushed this frame: camera(juice.offset()); a third value, the angle in degrees
  local ox, oy, ang = 0, 0, 0
  if shake > 0 then ox, oy = (math.random() * 2 - 1) * shake, (math.random() * 2 - 1) * shake end
  if trauma > 0 then -- smooth noise, not random: the screen swings instead of jittering (Eiserloh)
    local t, s = shake_t * 0.6, trauma * trauma
    ox, oy = ox + noise(t, 0.5) * 16 * s, oy + noise(t, 7.5) * 16 * s
    ang = noise(t, 13.5) * 6 * s
  end
  return math.floor(ox + kick_x + 0.5), math.floor(oy + kick_y + 0.5), ang
end

function M.draw() -- the flash, over everything
  if flash_left > 0 then rect(0, 0, SCREEN_W, SCREEN_H, flash_colour) end
end

function M.reset()
  tweens, timers, scripts, shake, frozen, flash_left = {}, {}, {}, 0, 0, 0
  trauma, kick_x, kick_y, squashes = 0, 0, 0, {}
end

return M
