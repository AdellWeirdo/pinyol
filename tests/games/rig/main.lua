-- lib/rig.lua: a character of three pieces, its poses read as numbers and its drawing read back from a canvas (tests/rig.script)
rig = require("rig")
events = {}
hero = rig.new({
  parts = {
    {id = "body", image = "BODY", pivot = {10, 40}},
    {id = "head", parent = "body", image = "HEAD", pivot = {8, 16}, at = {0, -40}, z = 1},
    {id = "arm", parent = "body", image = "ARM", pivot = {3, 2}, at = {8, -34}, z = 2},
  },
  anims = {
    idle = {len = 60, loop = true, tracks = {head = {rot = {{0, 0}, {30, 10}, {60, 0}}}, body = {y = {{0, 0}, {30, -2}, {60, 0}}}}},
    wave = {len = 30, next = "idle", events = {{tick = 15, name = "peak"}, {tick = 30, name = "end"}},
            tracks = {arm = {rot = {{0, 0, "smooth"}, {15, 90, "smooth"}, {30, 0}}}}},
    still = {len = 10, tracks = {arm = {rot = {{0, 45}, {10, 45}}}}},
    swap = {len = 20, loop = true, tracks = {head = {frame = {{0, 0}, {10, 1}}}}},
  },
})
hero:on("peak", function() events[#events + 1] = "peak" end)
hero:on("end", function() events[#events + 1] = "end" end)

function _init()
  show(0)
  canvas("BODY", 20, 40) target("BODY") cls(0xFF0000) target()
  canvas("HEAD", 16, 16) target("HEAD") cls(0x00FF00) target()
  canvas("ARM", 6, 20) target("ARM") cls(0x0000FF) target()
  canvas("R", 480, 320)
  hero:play("idle")
end

function _update() if running then hero:update() end end
running = false
DRAW = {x = 100, y = 200, o = {}}
function _draw()
  target("R") cls(0x000000)
  hero:draw(DRAW.x, DRAW.y, DRAW.o)
  target()
  rect(0, 0, 480, 320, 0x202838)
  img("R", 0, 0)
end
function near(a, b, e) return math.abs(a - b) <= (e or 0.05) end
function pt(id, lx, ly) local x, y = hero:point(id, lx, ly) return x, y end
function ptnear(id, lx, ly, ex, ey, e) local x, y = pt(id, lx, ly) return near(x, ex, e) and near(y, ey, e) end
function px(x, y) return pget(x, y, "R") or -1 end
function nev() return #events end
