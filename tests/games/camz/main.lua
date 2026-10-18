-- lib/cam.lua's zoom, turn and punch (tests/camz.script): the scene on a canvas and read back from another
cam = require("cam")
c = cam.new({})
mode = "scene"
function _init() show(0) canvas("OUT", 480, 320) end
function _update() c:update() end
function world()
  rect(0, 0, 240, 320, 0x4060C0)   -- left: blue
  rect(240, 0, 240, 320, 0xC06040) -- right: orange
  rect(230, 150, 20, 20, 0xFFFFFF) -- a white square at the middle
  rect(230, 0, 20, 12, 0xFF0000)   -- a red mark at the top
end
function _draw()
  c:draw(world, "OUT")
  rect(0, 0, 480, 320, 0x000000)
  img("OUT", 0, 0)
end
function px(x, y) return pget(x, y, "OUT") or -1 end
function near(a, b, e) return math.abs(a - b) <= (e or 0.01) end
function cor() local t = {c:corners()} return t end
function same(a, b) -- two colours within what RGB565 loses
  for sh = 0, 16, 8 do if math.abs((a >> sh & 255) - (b >> sh & 255)) > 8 then return false end end
  return true
end
