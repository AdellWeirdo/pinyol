-- scenefx: what a room does to the picture, the way the Game Boy did it with its window and its line interrupts.
--   dark rooms: everything is hidden but a circle of light round the hero (the lantern makes it bigger) and round a lit
--   torch: the window layer cut to a circle with one span a line;
--   waves: the rows of sea sway sideways, each line scrolled by a sine: the console's per-line scroll.
-- A screen asks for them in the area's notes: dark = {["sx,sy"] = true}, waves = {["sx,sy"] = {y0, y1}} (lines of the playfield).
local C = require("core.const")
local W = require("core.world")
local E = require("core.ents")
local Game = require("core.game")
local F = {}

local lines_on = false

local function in_notes(key)
  local n = W.area.notes or {}
  return n.dark and n.dark[key], n.waves and n.waves[key]
end

-- is the screen shown now (or the slide's target) a dark one, with no lantern?
function F.dark_now()
  local dark = in_notes(W.sx .. "," .. W.sy)
  return dark and true or false
end

local function circle(k, cx, cy, r)
  local top, bot = math.max(0, cy - r), math.min(C.H - 1, cy + r)
  for y = top, bot do
    local dy = y - cy
    local dx = math.floor(math.sqrt(math.max(0, r * r - dy * dy)))
    line_window(k, y, cx - dx, cx + dx)
  end
  return top, bot
end

function F.apply(t)
  local key = W.sx .. "," .. W.sy
  local dark, waves = in_notes(key)
  local sliding = require("core.play").slide ~= nil
  if lines_on then line_off() lines_on = false end
  if dark and not sliding then
    local h = E.hero
    local hx, hy = h.x + 8 - W.cam_x, h.y + 10 - W.cam_y + C.HUD
    local r = Game.lantern_on and Game.has("linterna") and 46 or 20
    -- the room's lit torches: the nearest one lights a second circle
    local tx, ty
    for _, def in ipairs(W.area.things) do
      if def.kind == "torch" and math.floor(def.cx / C.SW) == W.sx and math.floor(def.cy / C.SH) == W.sy then
        tx, ty = def.cx * C.T + 8 - W.cam_x, def.cy * C.T + 8 - W.cam_y + C.HUD
        break
      end
    end
    window(0, 0, 0, C.W - 1, C.H - 1, ALL)
    window_out(BG0 | BACK)
    circle(0, hx, hy, r)
    if tx then
      window(1, 0, 0, C.W - 1, C.H - 1, ALL)
      circle(1, tx, ty, 26)
    end
    lines_on = true
  else
    window_off(0) window_off(1)
  end
  if waves and not sliding then
    for y = waves[1], waves[2] do
      line_scroll(1, y + C.HUD, W.cam_x + W.shake_x + math.floor(math.sin(y / 5 + t / 14) * 1.6 + 0.5), W.cam_y - C.HUD + W.shake_y + 0)
    end
    lines_on = true
  end
end

return F
