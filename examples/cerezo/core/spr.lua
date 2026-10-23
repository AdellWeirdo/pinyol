-- spr: the sprites of the frame. Every picture of a character is a frame of a sheet with a name (data/frames.lua), so
-- the game says S.draw("HERO", "walk_down_1", x, y) and never counts. Slots are handed out in the order of drawing:
-- the first drawn is in front, so entities are drawn from the nearest to the screen's bottom up. What is drawn is
-- kept (S.rects) so the explainer can count it the way the console's video chip would: 8x16 pieces, ten to a line.
local F = require("data.frames")
local S = {}

local handles = {}
local slot = 0
S.rects = {}
S.n = 0

function S.begin()
  spr_clear()
  slot = 0
  S.n = 0
  for i = #S.rects, 1, -1 do S.rects[i] = nil end
end

local function handle(id)
  local h = handles[id]
  if not h then
    h = sheet(id)
    handles[id] = h
  end
  return h
end

-- S.draw(sheet, frame, x, y [, {flip, prio, bank, hidden}]): x, y on the screen (the sprite's top-left)
function S.draw(id, name, x, y, o)
  local sh = F[id]
  local frame = sh and sh[name]
  if not frame then error("no frame " .. tostring(id) .. "." .. tostring(name), 2) end
  o = o or {}
  local flags = prio(o.prio or 1) | bank(o.bank or (sh.banks and sh.banks[name]) or sh.bank or 0)
  if o.flip then flags = flags | FLIP_X end
  x, y = math.floor(x), math.floor(y)
  spr(slot, handle(id), frame, x, y, flags)
  slot = slot + 1
  S.n = S.n + 1
  S.rects[#S.rects + 1] = {x, y, sh.w, sh.h}
end

function S.slots() return slot end

return S
