-- spr: drawing frames of the sheets (data/sheets.lua, made by gen/build.py). A frame is found by its name; its anchor (the feet) is placed at x, y; a sheet cut in pieces
-- (so the console never needs one big block of memory) is found by frame number. `Spr.count` is how many pictures the frame drew (the explainer).
-- A hero's second colours are the sheet "<id>_b" borrowed as a palette (img's pal): the same pixels, other colours.
local D = require("data.sheets")
local S = {}

S.count = 0
S.sheets = D.sheets
S.backs = D.backs
local look = {}
local counts = {}

-- how many frames a sheet has of a run named prefix_0, prefix_1...
function S.n(sheet, prefix)
  local key = sheet .. "." .. prefix
  local n = counts[key]
  if not n then
    n = 0
    while D.sheets[sheet].frames[prefix .. "_" .. n] do n = n + 1 end
    counts[key] = n
  end
  return n
end

function S.seq(sheet, prefix, i)
  local n = S.n(sheet, prefix)
  return prefix .. "_" .. (i % math.max(1, n))
end

function S.has(sheet, frame) return D.sheets[sheet] ~= nil and D.sheets[sheet].frames[frame] ~= nil end

-- S.draw(sheet, frame, x, y [, {flip, tint, alpha, dx, dy, alt, outline, dim, scale}]): x, y is the anchor's place on the screen
function S.draw(name, frame, x, y, o)
  local sh = D.sheets[name]
  local idx = sh.frames[frame]
  if not idx then error("no frame " .. tostring(name) .. "." .. tostring(frame), 2) end
  local id, pal = sh.id, nil
  local piece
  if sh.pieces then
    piece = idx // sh.per
    id = id .. "_C" .. piece
    idx = idx % sh.per
  end
  if o and o.alt then
    local b = D.sheets[name .. "_b"]
    if b then pal = b.pieces and (b.id .. "_C" .. piece) or b.id end
  end
  local flip = o and o.flip
  local left = flip and x - (sh.w - sh.ax) or x - sh.ax
  look.frame, look.flip_x, look.pal = idx, flip or false, pal
  look.tint, look.alpha = o and o.tint or nil, o and o.alpha or nil
  look.scale, look.dim, look.mul, look.angle = o and o.scale, o and o.dim, o and o.mul, o and o.angle
  look.outline = o and o.outline or nil
  img(id, math.floor(left + (o and o.dx or 0)), math.floor(y - sh.ay + (o and o.dy or 0)), look)
  S.count = S.count + 1
end

-- a wide picture cut in columns (so only the ones on the screen are in memory); `flip` mirrors the whole picture
function S.back(name, x, y, flip)
  local b = D.backs[name]
  look.frame, look.tint, look.alpha, look.scale, look.dim, look.mul, look.angle, look.pal, look.outline = nil, nil, nil, nil, nil, nil, nil, nil, nil
  look.flip_x = flip or false
  for _, sl in ipairs(b.slices) do
    local dx = flip and (x + b.w - sl.x - sl.w) or (x + sl.x)
    if dx < 480 and dx + sl.w > 0 then
      img(sl.id, dx, y or 0, look)
      S.count = S.count + 1
    end
  end
end

function S.back_size(name) local b = D.backs[name] return b.w, b.h end

return S
