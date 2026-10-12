-- juice: what makes a game feel alive, after "Juice it or lose it" (Jonasson and Purho) and "The art of
-- screenshake" (Nijman): things move with an ease instead of jumping, the screen shakes on a hit, a moment freezes
-- when a blow lands, a flash.
--
--   local juice = require("juice")
--   juice.tween(door, {y = 40}, 0.5, "out_bounce")   -- door.y goes to 40 in half a second, bouncing at the end
--   juice.shake(6)                                    -- the screen shakes 6 pixels, and calms down
--   juice.freeze(5)                                   -- five ticks frozen: the hit lands
--   juice.flash(0xFFFFFF, 3)                          -- three ticks of white
--   in _update:  if juice.update() then return end    -- true while frozen: skip the game's tick
--   in _draw:    camera(juice.offset()) ... camera()  then juice.draw() last, for the flash
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

local tweens = {}
local shake, frozen, flash_colour, flash_left = 0, 0, 0, 0

-- tween(obj, {field = target, ...}, seconds [, ease [, done]]): the fields move from where they are to the targets;
-- a field already moving stops its old move. done(obj) is called at the end. Returns the tween (to cancel it).
function M.tween(obj, to, seconds, ease, done)
  local f = type(ease) == "function" and ease or M.ease[ease or "out_quad"]
  assert(f, "juice.tween: no ease called " .. tostring(ease))
  for _, tw in ipairs(tweens) do
    if tw.obj == obj then for k in pairs(to) do tw.to[k] = nil end end
  end
  local tw = {obj = obj, from = {}, to = {}, t = 0, len = math.max(1, math.floor(seconds * 60 + 0.5)), ease = f,
              done = done}
  for k, v in pairs(to) do tw.from[k], tw.to[k] = obj[k], v end
  tweens[#tweens + 1] = tw
  return tw
end

function M.cancel(what) -- a tween, or every tween of an object
  for i = #tweens, 1, -1 do
    if tweens[i] == what or tweens[i].obj == what then table.remove(tweens, i) end
  end
end

function M.shake(px) shake = math.max(shake, px) end
function M.freeze(ticks) frozen = math.max(frozen, ticks) end
function M.flash(colour, ticks) flash_colour, flash_left = colour or 0xFFFFFF, ticks or 3 end
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
    tw.t = tw.t + 1
    local k = tw.ease(math.min(1, tw.t / tw.len))
    for f, target in pairs(tw.to) do tw.obj[f] = tw.from[f] + (target - tw.from[f]) * k end
    if tw.t >= tw.len then
      table.remove(tweens, i)
      for f, target in pairs(tw.to) do tw.obj[f] = target end
      if tw.done then tw.done(tw.obj) end
    end
  end
  shake = shake > 0.5 and shake * 0.85 or 0
  return false
end

function M.offset() -- where the screen is pushed this frame: camera(juice.offset())
  if shake == 0 then return 0, 0 end
  return math.floor((math.random() * 2 - 1) * shake + 0.5), math.floor((math.random() * 2 - 1) * shake + 0.5)
end

function M.draw() -- the flash, over everything
  if flash_left > 0 then rect(0, 0, SCREEN_W, SCREEN_H, flash_colour) end
end

function M.reset() tweens, shake, frozen, flash_left = {}, 0, 0, 0 end

return M
