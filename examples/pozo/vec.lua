-- vec: strokes, the way a vector monitor draws them. Nothing is filled and nothing is a pixel: the beam goes from one
-- end of a line to the other, lit, and moves on. Every frame the game hands vec the lines it wants; the beam only gets so
-- many in a sixtieth of a second, and past that the extra ones flicker, as on the real machines (unless the player asked
-- for less flashing).
--
--   vec.begin()                         -- at the start of each frame
--   vec.line(x0, y0, x1, y1, colour [, weight])   -- one line; weight 2 and 3 glow, 1 does not
--   vec.shape(points, colour [, weight])          -- a closed outline: {x0, y0, x1, y1, ...}, the last joins the first
--   vec.open(points, colour [, weight])           -- the same, left open
--   vec.hair(points, colour)                      -- a closed outline with no glow, for what does not change (the well)
--   vec.text("POZO", cx, y, k, colour)            -- letters made of strokes, each 4k wide and 6k tall, centred on cx
--   vec.flush()                                   -- at the end: everything is drawn
--
-- What a drawing command costs on the console is its call, not its pixels (found with perf("ops") and perf("lua"): a
-- filled `poly` is some 140 microseconds, a `line` 20, each call from Lua 15 more, and a glow drawn on a picture under
-- the lines cost 4 to 5 ms a frame, more than all the lines), so an outline is ONE `poly` call, the glow of a stroke is
-- the same stroke a pixel over, dimmer (two of them for weight 3), and everything is drawn in two passes: every glow,
-- then every core, so no glow covers another stroke's bright core. (docs/measurements.md, "Vector drawing".)
local M = {}

M.budget = 300          -- strokes the beam draws in a frame before the picture flickers
M.flicker = true        -- false: the player wants less flashing
M.count, M.last = 0, 0  -- strokes this frame (an outline counts its sides), and the one before
M.drop = 0              -- the chance an extra stroke is left out in this frame

local lines, nl = {}, 0           -- this frame's lines: x0, y0, x1, y1, colour, weight
local shapes, nshape = {}, 0      -- this frame's outlines that glow: points, colour, weight
local hairs, nhair = {}, 0        -- and the ones that do not
local old_lines, old_nl = {}, 0   -- last frame's, for the explainer and to take their glow out
local old_shapes, old_nshape = {}, 0
local old_hairs, old_nhair = {}, 0

local function tint(k) -- a colour at k of its brightness, made once for each colour
  return setmetatable({}, {__index = function(t, c)
    local r, g, b = (c >> 16) & 255, (c >> 8) & 255, c & 255
    local v = ((math.floor(r * k)) << 16) | ((math.floor(g * k)) << 8) | math.floor(b * k)
    t[c] = v
    return v
  end})
end
local mid, faint = tint(0.55), tint(0.22)

function M.dim(c, k) -- a colour at k (0..1) of its brightness
  local r, g, b = (c >> 16) & 255, (c >> 8) & 255, c & 255
  return (math.floor(r * k) << 16) | (math.floor(g * k) << 8) | math.floor(b * k)
end

function M.begin()
  M.last = M.count
  M.count = 0
  nl, nshape, nhair = 0, 0, 0
  M.drop = (M.flicker and M.last > M.budget) and (M.last - M.budget) / M.last or 0
end

local function left_out() return M.drop > 0 and math.random() < M.drop end

function M.line(x0, y0, x1, y1, c, weight)
  M.count = M.count + 1
  if left_out() then return end
  if M.wash then c = M.wash end -- the zapper's flash: everything white
  local i = nl * 6
  lines[i + 1], lines[i + 2], lines[i + 3], lines[i + 4], lines[i + 5], lines[i + 6] = x0, y0, x1, y1, c, weight or 2
  nl = nl + 1
end

function M.shape(pts, c, weight)
  M.count = M.count + #pts // 2
  if left_out() then return end
  if M.wash then c = M.wash end
  nshape = nshape + 1
  local i = (nshape - 1) * 3
  shapes[i + 1], shapes[i + 2], shapes[i + 3] = pts, c, weight or 2
end

function M.open(pts, c, weight) -- an open path: the way back along it closes the outline (every side is drawn twice)
  local n, k = #pts // 2, #pts
  local out = {table.unpack(pts)}
  for i = n - 1, 2, -1 do out[k + 1], out[k + 2] = pts[i * 2 - 1], pts[i * 2] k = k + 2 end
  M.shape(out, c, weight)
  M.count = M.count - (#out // 2 - (n - 1)) -- (it counts once, not twice)
end

function M.hair(pts, c)
  M.count = M.count + #pts // 2
  if M.wash then c = M.wash end
  nhair = nhair + 1
  hairs[nhair * 2 - 1], hairs[nhair * 2] = pts, c
end

function M.poly(pts, closed, c, weight)
  if closed then M.shape(pts, c, weight) else M.open(pts, c, weight) end
end

function M.clear_glow() end -- (the glow is part of the lines now: nothing is left behind)

local function shifted(pts, d) -- the same outline moved d pixels down and to the right
  local out = {}
  for i = 1, #pts do out[i] = pts[i] + d end
  return out
end

function M.flush() -- draws what the frame's strokes made: first every glow, then every core over them
  for i = 1, nhair do poly(hairs[i * 2 - 1], hairs[i * 2], false) end
  for i = 0, nshape - 1 do
    local w = shapes[i * 3 + 3]
    if w > 1 then
      local pts, c = shapes[i * 3 + 1], shapes[i * 3 + 2]
      poly(shifted(pts, 1), mid[c], false)
      if w > 2 then poly(shifted(pts, -1), faint[c], false) end
    end
  end
  for i = 0, nl - 1 do
    local j = i * 6
    local w = lines[j + 6]
    if w > 1 then
      local x0, y0, x1, y1, c = lines[j + 1], lines[j + 2], lines[j + 3], lines[j + 4], lines[j + 5]
      line(x0 + 1, y0 + 1, x1 + 1, y1 + 1, mid[c])
      if w > 2 then line(x0 - 1, y0 - 1, x1 - 1, y1 - 1, faint[c]) end
    end
  end
  for i = 0, nshape - 1 do poly(shapes[i * 3 + 1], shapes[i * 3 + 2], false) end
  for i = 0, nl - 1 do
    local j = i * 6
    line(lines[j + 1], lines[j + 2], lines[j + 3], lines[j + 4], lines[j + 5])
  end
  -- this frame becomes the last one (the explainer reads it)
  lines, old_lines = old_lines, lines
  shapes, old_shapes = old_shapes, shapes
  hairs, old_hairs = old_hairs, hairs
  old_nl, old_nshape, old_nhair = nl, nshape, nhair
  nl, nshape, nhair = 0, 0, 0
end

-- the strokes of the frame just drawn, one by one, as the beam would have gone: x0, y0, x1, y1, colour (five numbers each)
function M.snapshot()
  local out, n = {}, 0
  local function add(x0, y0, x1, y1, c)
    local i = n * 5
    out[i + 1], out[i + 2], out[i + 3], out[i + 4], out[i + 5] = x0, y0, x1, y1, c
    n = n + 1
  end
  local function outline(pts, c)
    local m = #pts // 2
    for i = 1, m do
      local j = i % m + 1
      add(pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2], c)
    end
  end
  for i = 1, old_nhair do outline(old_hairs[i * 2 - 1], old_hairs[i * 2]) end
  for i = 0, old_nshape - 1 do outline(old_shapes[i * 3 + 1], old_shapes[i * 3 + 2]) end
  for i = 0, old_nl - 1 do
    local j = i * 6
    add(old_lines[j + 1], old_lines[j + 2], old_lines[j + 3], old_lines[j + 4], old_lines[j + 5])
  end
  return out, n
end

-- ------------------------------------------------------------------ letters made of strokes
-- a glyph is pairs of points on a grid 4 wide and 6 tall; accents are strokes above the capital (y -1 to -3)
local G = {
  A = {0,6,0,2, 0,2,2,0, 2,0,4,2, 4,2,4,6, 0,3,4,3},
  B = {0,0,0,6, 0,0,3,0, 3,0,4,1, 4,1,3,3, 0,3,3,3, 3,3,4,4, 4,4,4,5, 4,5,3,6, 3,6,0,6},
  C = {4,0,0,0, 0,0,0,6, 0,6,4,6},
  D = {0,0,0,6, 0,0,3,0, 3,0,4,2, 4,2,4,4, 4,4,3,6, 3,6,0,6},
  E = {4,0,0,0, 0,0,0,6, 0,6,4,6, 0,3,3,3},
  F = {4,0,0,0, 0,0,0,6, 0,3,3,3},
  G = {4,0,0,0, 0,0,0,6, 0,6,4,6, 4,6,4,3, 4,3,2,3},
  H = {0,0,0,6, 4,0,4,6, 0,3,4,3},
  I = {0,0,4,0, 2,0,2,6, 0,6,4,6},
  J = {4,0,4,6, 4,6,0,6, 0,6,0,4},
  K = {0,0,0,6, 4,0,0,3, 0,3,4,6},
  L = {0,0,0,6, 0,6,4,6},
  M = {0,6,0,0, 0,0,2,2, 2,2,4,0, 4,0,4,6},
  N = {0,6,0,0, 0,0,4,6, 4,6,4,0},
  O = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,6,0,0},
  P = {0,6,0,0, 0,0,4,0, 4,0,4,3, 4,3,0,3},
  Q = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,6,0,0, 2,4,4,6},
  R = {0,6,0,0, 0,0,4,0, 4,0,4,3, 4,3,0,3, 1,3,4,6},
  S = {4,0,0,0, 0,0,0,3, 0,3,4,3, 4,3,4,6, 4,6,0,6},
  T = {0,0,4,0, 2,0,2,6},
  U = {0,0,0,6, 0,6,4,6, 4,6,4,0},
  V = {0,0,2,6, 2,6,4,0},
  W = {0,0,1,6, 1,6,2,3, 2,3,3,6, 3,6,4,0},
  X = {0,0,4,6, 4,0,0,6},
  Y = {0,0,2,3, 4,0,2,3, 2,3,2,6},
  Z = {0,0,4,0, 4,0,0,6, 0,6,4,6},
  ["0"] = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,6,0,0}, ["1"] = {2,0,2,6, 1,1,2,0},
  ["2"] = {0,0,4,0, 4,0,4,3, 4,3,0,3, 0,3,0,6, 0,6,4,6}, ["3"] = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,3,4,3},
  ["4"] = {0,0,0,3, 0,3,4,3, 4,0,4,6}, ["5"] = {4,0,0,0, 0,0,0,3, 0,3,4,3, 4,3,4,6, 4,6,0,6},
  ["6"] = {4,0,0,0, 0,0,0,6, 0,6,4,6, 4,6,4,3, 4,3,0,3}, ["7"] = {0,0,4,0, 4,0,4,6},
  ["8"] = {0,0,4,0, 4,0,4,6, 4,6,0,6, 0,6,0,0, 0,3,4,3}, ["9"] = {4,3,0,3, 0,3,0,0, 0,0,4,0, 4,0,4,6, 4,6,0,6},
  ["."] = {2,5,2,6}, [","] = {2,5,1,7}, ["!"] = {2,0,2,4, 2,5,2,6}, ["¡"] = {2,0,2,1, 2,2,2,6},
  ["?"] = {0,1,1,0, 1,0,3,0, 3,0,4,1, 4,1,4,2, 4,2,2,3, 2,3,2,4, 2,5,2,6},
  ["¿"] = {2,0,2,1, 2,2,2,3, 2,3,0,4, 0,4,0,5, 0,5,1,6, 1,6,3,6, 3,6,4,5},
  ["-"] = {0,3,4,3}, [":"] = {2,1,2,2, 2,4,2,5}, ["/"] = {0,6,4,0}, ["+"] = {0,3,4,3, 2,1,2,5}, ["·"] = {2,3,2,4},
  ["'"] = {2,0,2,2},
}
local ACUTE, GRAVE, UML, TILDE = {1,-1,3,-3}, {1,-3,3,-1}, {0,-2,1,-2, 3,-2,4,-2}, {0,-2,1,-3, 1,-3,3,-2, 3,-2,4,-3}
local CEDILLA = {2,6,2,7, 2,7,1,8}
local ACC = { -- UTF-8 letter: its plain glyph and the mark
  ["Á"] = {"A", ACUTE}, ["É"] = {"E", ACUTE}, ["Í"] = {"I", ACUTE}, ["Ó"] = {"O", ACUTE}, ["Ú"] = {"U", ACUTE},
  ["À"] = {"A", GRAVE}, ["È"] = {"E", GRAVE}, ["Ò"] = {"O", GRAVE}, ["Ï"] = {"I", UML}, ["Ü"] = {"U", UML},
  ["Ñ"] = {"N", TILDE}, ["Ç"] = {"C", CEDILLA},
}
local LOWER = {["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["à"] = "À", ["è"] = "È", ["ò"] = "Ò",
               ["ï"] = "Ï", ["ü"] = "Ü", ["ñ"] = "Ñ", ["ç"] = "Ç"}

function M.text_width(s, k) -- the width of the word, as vec.text sets it
  return (utf8.len(s) * 6 - 2) * k
end

function M.text(s, cx, y, k, c)
  local x = cx - M.text_width(s, k) // 2
  for _, cp in utf8.codes(s) do
    local ch = utf8.char(cp)
    ch = LOWER[ch] or ch:upper()
    local plain = ACC[ch]
    local glyph = plain and G[plain[1]] or G[ch]
    if glyph then
      for i = 1, #glyph, 4 do M.line(x + glyph[i] * k, y + glyph[i + 1] * k, x + glyph[i + 2] * k, y + glyph[i + 3] * k, c, 2) end
      local mark = plain and plain[2]
      if mark then for i = 1, #mark, 4 do M.line(x + mark[i] * k, y + mark[i + 1] * k, x + mark[i + 2] * k, y + mark[i + 3] * k, c, 2) end end
    end
    x = x + 6 * k
  end
end

return M
