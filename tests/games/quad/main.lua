-- quad on canvases (tests/quad.script): a picture on four corners must be, where it is straight, the picture itself; the
-- shared diagonal of its two triangles has no hole and no pixel mixed twice; turned a quarter it is the picture turned;
-- lights darken, brighten and blend across; far off the canvas it is clipped. Also drawn on the screen, so the strips
-- are checked against the whole frame.
local N = 16
function rgb(r, g, b) return r << 16 | g << 8 | b end
function _init()
  show(0)
  canvas("SRC", N, N); target("SRC")
  for y = 0, N - 1 do for x = 0, N - 1 do pset(x, y, rgb(x * 16, y * 16, 128)) end end
  canvas("WHITE", N, N); target("WHITE"); cls(0xFFFFFF)
  canvas("HALVES", N, N); target("HALVES"); rect(0, 0, N, N // 2, 0xFF0000); rect(0, N // 2, N, N // 2, 0x00FF00)
  canvas("GREY", N, N); target("GREY"); cls(0x404040)
  canvas("MASK", N, N); target("MASK"); rect(0, 0, 8, N, 0xFFFFFF)
  target()
end
function out(name, f) canvas(name, 32, 32); target(name); f(); target() end
function _draw()
  out("FLAT", function() quad("SRC", 4, 4, 20, 4, 20, 20, 4, 20) end)
  out("PLAIN", function() img("SRC", 4, 4) end)
  out("MIXED", function() quad("WHITE", 4, 4, 20, 4, 20, 20, 4, 20, {quarter = true}) end)
  out("TURNED", function() quad("SRC", 20, 4, 20, 20, 4, 20, 4, 4) end)
  out("DARK", function() quad("WHITE", 4, 4, 20, 4, 20, 20, 4, 20, {light = 0x000000}) end)
  out("NEUTRAL", function() quad("SRC", 4, 4, 20, 4, 20, 20, 4, 20, {light = 0x808080}) end)
  out("BRIGHT", function() quad("GREY", 4, 4, 20, 4, 20, 20, 4, 20, {light = 0xFFFFFF}) end)
  out("RAMP", function() quad("WHITE", 4, 4, 20, 4, 20, 20, 4, 20, {lights = {0x000000, 0x808080, 0x808080, 0x000000}}) end)
  out("MESH", function() rect(0, 0, 32, 32, 0x0000FF); quad("WHITE", 4, 4, 20, 4, 20, 20, 4, 20, {mesh = true}) end)
  out("MESH_MASK", function() rect(0, 0, 32, 32, 0x0000FF); quad("MASK", 4, 4, 20, 4, 20, 20, 4, 20, {mesh = true}) end)
  out("MESH_LIT", function() rect(0, 0, 32, 32, 0x0000FF); quad("WHITE", 4, 4, 20, 4, 20, 20, 4, 20, {mesh = true, light = 0x000000}) end)
  out("MESH_PERSP", function() rect(0, 0, 32, 32, 0x0000FF); quad("WHITE", 4, 4, 20, 4, 24, 20, 0, 20, {mesh = true, persp = true}) end)
  out("FAR", function() quad("SRC", -900, -900, 1500, -700, 1400, 1300, -800, 1100) end)
  -- a floor in perspective: the top edge 100 wide, the bottom 200, a texture red above its middle and green below
  for _, name in ipairs({"P0", "P1", "P8"}) do
    canvas(name, 400, 300) target(name)
    local o = name == "P1" and {persp = true} or name == "P8" and {persp = 8} or nil
    quad("HALVES", 150, 100, 250, 100, 300, 200, 100, 200, o)
    target()
  end
  out("GV", function() grad(0, 0, 32, 32, 0x000000, 0xFFFFFF) end)
  out("GVD", function() grad(0, 0, 32, 32, 0x000000, 0xFFFFFF, {dither = true}) end)
  out("GH", function() grad(0, 0, 32, 32, 0x000000, 0xFFFFFF, {across = true}) end)
  out("GSUB", function() rect(0, 0, 32, 32, 0xFFFFFF); grad(0, 0, 32, 32, 0x000000, 0xFF0000, {sub = true}) end)
  -- on the screen: a tilted quad, lit across, mixed with what is under it
  rect(0, 0, 480, 320, 0x203040)
  quad("SRC", 100, 60, 380, 40, 420, 260, 60, 220, {lights = {0x808080, 0xFFFFFF, 0x808080, 0x402000}, dither = true})
  grad(0, 0, 480, 60, 0x000000, 0x6040A0, {dither = true})
  grad(300, 100, 100, 100, 0x000000, 0xFFC080, {across = true, add = true, alpha = 0.6})
  quad("WHITE", 40, 200, 200, 220, 180, 300, 20, 290, {add = true, alpha = 0.5})
  quad("WHITE", 31, 81, 63, 81, 63, 113, 31, 113, {mesh = true})
end
function same(a, b)
  local bad = 0
  for y = 0, 31 do for x = 0, 31 do if pget(x, y, a) ~= pget(x, y, b) then bad = bad + 1 end end end
  return bad
end
function count(name) -- the pixels drawn, and the greatest and least value among them
  local n, lo, hi = 0, 1e9, -1
  for y = 0, 31 do for x = 0, 31 do
    local c = pget(x, y, name)
    if c then n = n + 1; lo = math.min(lo, c); hi = math.max(hi, c) end
  end end
  return n, lo, hi
end
function turned_wrong()
  local bad = 0
  for y = 4, 19 do for x = 4, 19 do
    if pget(x, y, "TURNED") ~= pget(y - 4, 19 - x, "SRC") then bad = bad + 1 end
  end end
  return bad
end
function grn(name, x, y) return (pget(x, y, name) or 0) >> 8 & 255 end
function red(name, x, y) return (pget(x, y, name) or 0) >> 16 & 255 end
function ramp_wrong() -- plain vertical: the same all along a row, never going down a column, from near black to near white
  local bad = 0
  for y = 0, 31 do
    for x = 1, 31 do if pget(x, y, "GV") ~= pget(0, y, "GV") then bad = bad + 1 end end
    if y > 0 and red("GV", 0, y) < red("GV", 0, y - 1) then bad = bad + 1 end
  end
  return bad
end
function mean(name) local t = 0 for y = 0, 31 do for x = 0, 31 do t = t + red(name, x, y) end end return t / 1024 end
function spread(name, y) local seen, n = {}, 0 for x = 0, 31 do local c = red(name, x, y) if not seen[c] then seen[c] = true n = n + 1 end end return n end
function far_from_plain() local worst = 0 for y = 0, 31 do for x = 0, 31 do worst = math.max(worst, math.abs(red("GVD", x, y) - red("GV", x, y))) end end return worst end
function mesh_wrong()
  local wrong = 0
  for y = 4, 19 do for x = 4, 19 do
    local expected = (x + y) % 2 == 0 and 0xFFFFFF or 0x0000FF
    if pget(x, y, "MESH") ~= expected then wrong = wrong + 1 end
  end end
  return wrong
end
