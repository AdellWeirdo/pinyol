-- warp() and linetint() on canvases (tests/vdp2.script): rows and columns moved, rows given their own colour
local N = 32
function _init()
  show(0)
  canvas("SRC", N, N) target("SRC")
  for y = 0, N - 1 do for x = 0, N - 1 do pset(x, y, (x * 8) << 16 | (y * 8) << 8 | 0x10) end end
  target()
end
local function scene(name, f) canvas(name, 96, 96) target(name) cls() f() target() end
function _draw()
  scene("ROWS", function() warp("SRC", 20, 20, {rows = function(j) return j end}) end)
  scene("COLS", function() warp("SRC", 20, 20, {cols = {0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4, 6, 6, 6, 6, 6, 6, 6, 6}}) end)
  scene("BOTH", function() warp("SRC", 20, 20, {rows = function(j) return j // 4 end, cols = function(i) return i // 8 end}) end)
  scene("WRAP", function() warp("SRC", 20, 20, {rows = function() return 5 end, wrap = true}) end)
  scene("NEG", function() warp("SRC", 20, 20, {rows = function() return -7 end}) end)
  scene("NONE", function() warp("SRC", 20, 20, {}) end)
  scene("EDGE", function() warp("SRC", -10, -10, {rows = function(j) return 4 end}) end)
  canvas("BASE", 8, 40) target("BASE") cls(0x404040) target()
  scene("ADD", function() rect(0, 0, 96, 96, 0x404040) linetint(10, 10, 40, 40, function(j) return j * 4 << 16 end) end)
  scene("SUB", function() rect(0, 0, 96, 96, 0x808080) linetint(10, 10, 40, 40, function(j) return j * 3 << 8 end, {sub = true}) end)
  scene("LAY", function() rect(0, 0, 96, 96, 0x404040) linetint(10, 10, 40, 40, {0xFF0000, 0x00FF00, 0x0000FF}, {lay = true}) end)
  scene("MIX", function() rect(0, 0, 96, 96, 0x000000) linetint(10, 10, 40, 40, function(j) return 0xFFFFFF end, {alpha = 0.5}) end)
  rect(0, 0, 480, 320, 0x101830)
  warp("SRC", 40, 40, {rows = function(j) return math.floor(math.sin(j * 0.4 + 1) * 4) end, cols = function(i) return math.floor(math.sin(i * 0.3) * 3) end})
  linetint(200, 0, 280, 320, function(j) return (j // 2) << 16 | (j // 4) << 8 end)
end
function px(name, x, y) return pget(x, y, name) end
function ch(c) return c >> 16 & 255, c >> 8 & 255, c & 255 end
function red(c) return c >> 16 & 255 end
function green(c) return c >> 8 & 255 end
function blue(c) return c & 255 end
