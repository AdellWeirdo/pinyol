-- sheets: a strip of more than 64 frames, which tools/png2asset.py writes in pieces (SPR_HERO, SPR_HERO_2, SPR_HERO_3: 64 frames each), as one.
--
--   local sheets = require("sheets")
--   sheets.spr(0, "HERO", 130, x, y, flags)          -- spr() of frame 130: frame 2 of HERO_3
--   sheets.img("SPR_HERO", x, y, 130, {flip_x = true}) -- img() of it, with any img option
--   local id, f = sheets.piece("HERO", 130)          -- "HERO_3", 2: for anything else (imgsize, preload)
local M = {}

local PER = 64 -- frames a picture holds

function M.piece(id, frame)
  local k = frame // PER
  return k == 0 and id or (id .. "_" .. (k + 1)), frame % PER
end

function M.spr(slot, id, frame, x, y, flags)
  local piece, f = M.piece(id, frame)
  return spr(slot, piece, f, x, y, flags)
end

local look = {}
function M.img(id, x, y, frame, opts)
  local piece, f = M.piece(id, frame or 0)
  for k in pairs(look) do look[k] = nil end
  if opts then for k, v in pairs(opts) do look[k] = v end end
  look.frame = f
  return img(piece, x, y, look)
end

return M
