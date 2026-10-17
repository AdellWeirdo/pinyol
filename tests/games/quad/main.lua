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
  canvas("GREY", N, N); target("GREY"); cls(0x404040)
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
  out("FAR", function() quad("SRC", -900, -900, 1500, -700, 1400, 1300, -800, 1100) end)
  -- on the screen: a tilted quad, lit across, mixed with what is under it
  rect(0, 0, 480, 320, 0x203040)
  quad("SRC", 100, 60, 380, 40, 420, 260, 60, 220, {lights = {0x808080, 0xFFFFFF, 0x808080, 0x402000}, dither = true})
  quad("WHITE", 40, 200, 200, 220, 180, 300, 20, 290, {add = true, alpha = 0.5})
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
function red(name, x, y) return (pget(x, y, name) or 0) >> 16 & 255 end
