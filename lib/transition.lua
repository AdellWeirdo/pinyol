-- transition: the ways a game goes from one screen to the next: a fade, a wipe, an iris closing on the hero, blinds, a
-- curtain, blocks that dissolve (the PlayStation's tile dissolve). Each covers the screen (k from 0, nothing, to 1, all of it),
-- the game changes behind it, and it opens again.
--
--   local transition = require("transition")
--   transition.go("iris", 0.8, {cx = hero.x, cy = hero.y, on_mid = function() load_room(2) end})   -- close, change, open
--   in _update: transition.update()           in _draw (last): transition.draw()
--   transition.active()  true while it goes; transition.covered() true while the screen is all covered (the change is now)
--   transition.draw_kind("wipe", 0.5, {dir = "left"})   -- one still frame: for your own timing, or a picture of it
--
-- kinds and their options (all optional): color (0x000000)
--   "fade"     the screen going to the colour, smoothly (a mixed full-screen box: the dearest kind, ~12 ms of a frame)
--   "wipe"     dir = "right" (default), "left", "up" or "down": the colour comes in from that side
--   "curtain"  two halves closing from the sides to the middle (dir = "vertical": from the top and bottom)
--   "blinds"   bars = 8 (how many), dir = "horizontal" (default) or "vertical": each bar growing from its middle
--   "iris"     a circle around (cx, cy) (the screen's middle) closing: the old way to end a cartoon
--   "blocks"   size = 32: square blocks, in the 4x4 pattern's order, each turning to the colour
-- go(kind, seconds, opts): seconds is the whole of it, closing and opening; hold = 0.1: seconds it stays covered.
local M = {}
local W, H = SCREEN_W or 480, SCREEN_H or 320
local run

local BAYER = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5} -- 4x4 ordered: which block goes when

local function cover(kind, k, o)
  local c = o.color or 0x000000
  if k <= 0 then return end
  if k > 1 then k = 1 end
  if kind == "fade" then
    if k >= 1 then rect(0, 0, W, H, c) else grad(0, 0, W, H, c, c, {alpha = k}) end
  elseif kind == "wipe" then
    local dir = o.dir or "right"
    local n = math.ceil(k * ((dir == "up" or dir == "down") and H or W))
    if dir == "right" then rect(0, 0, n, H, c)
    elseif dir == "left" then rect(W - n, 0, n, H, c)
    elseif dir == "down" then rect(0, 0, W, n, c)
    else rect(0, H - n, W, n, c) end
  elseif kind == "curtain" then
    if o.dir == "vertical" then
      local n = math.ceil(k * H / 2)
      rect(0, 0, W, n, c) rect(0, H - n, W, n, c)
    else
      local n = math.ceil(k * W / 2)
      rect(0, 0, n, H, c) rect(W - n, 0, n, H, c)
    end
  elseif kind == "blinds" then
    local bars = math.max(1, math.floor(o.bars or 8))
    local vertical = o.dir == "vertical"
    local len = (vertical and W or H) / bars
    local size = math.ceil(k * len)
    for i = 0, bars - 1 do
      local mid = (i + 0.5) * len
      local a = math.floor(mid - size / 2)
      if vertical then rect(a, 0, size, H, c) else rect(0, a, W, size, c) end
    end
  elseif kind == "iris" then
    local cx, cy = o.cx or W // 2, o.cy or H // 2
    local far = math.max(math.sqrt(cx * cx + cy * cy), math.sqrt((W - cx) ^ 2 + cy * cy),
                         math.sqrt(cx * cx + (H - cy) ^ 2), math.sqrt((W - cx) ^ 2 + (H - cy) ^ 2))
    local r = (1 - k) * far
    if k >= 1 then rect(0, 0, W, H, c) return end
    local band = 4 -- the circle in strips four rows high: 80 of them, two boxes each
    for y = 0, H - 1, band do
      local dy = math.abs(cy - (y + band / 2))
      if dy >= r then rect(0, y, W, band, c)
      else
        local hw = math.floor(math.sqrt(r * r - dy * dy))
        if cx - hw > 0 then rect(0, y, cx - hw, band, c) end
        if cx + hw < W then rect(cx + hw, y, W - cx - hw, band, c) end
      end
    end
  elseif kind == "blocks" then
    local size = math.max(4, math.floor(o.size or 32))
    local level = k * 16
    for by = 0, math.ceil(H / size) - 1 do
      for bx = 0, math.ceil(W / size) - 1 do
        if BAYER[(by % 4) * 4 + (bx % 4) + 1] < level then rect(bx * size, by * size, size, size, c) end
      end
    end
  else
    error("transition: no kind called " .. tostring(kind), 2)
  end
end

local KINDS = {fade = true, wipe = true, curtain = true, blinds = true, iris = true, blocks = true}

function M.draw_kind(kind, k, o)
  if not KINDS[kind] then error("transition: no kind called " .. tostring(kind), 2) end
  camera()
  clip()
  cover(kind, k, o or {})
end

function M.go(kind, seconds, o)
  if not KINDS[kind] then error("transition: no kind called " .. tostring(kind), 2) end
  o = o or {}
  local hold = math.floor((o.hold or 0.1) * 60 + 0.5)
  local half = math.max(1, math.floor((seconds or 0.6) * 60 / 2 + 0.5))
  run = {kind = kind, o = o, half = half, hold = hold, t = 0, changed = false}
end

function M.active() return run ~= nil end
function M.covered() return run ~= nil and run.t >= run.half and run.t < run.half + run.hold end
function M.cancel() run = nil end

function M.update()
  if not run then return end
  run.t = run.t + 1
  if not run.changed and run.t >= run.half then -- covered: the change, once
    run.changed = true
    if run.o.on_mid then run.o.on_mid() end
  end
  if run.t >= run.half * 2 + run.hold then
    local done = run.o.on_done
    run = nil
    if done then done() end
  end
end

function M.draw()
  if not run then return end
  local k
  if run.t < run.half then k = run.t / run.half
  elseif run.t < run.half + run.hold then k = 1
  else k = 1 - (run.t - run.half - run.hold) / run.half end
  M.draw_kind(run.kind, k, run.o)
end

return M
