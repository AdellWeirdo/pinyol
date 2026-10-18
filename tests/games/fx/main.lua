-- lib/particles.lua (glows, sprites, emitters) and lib/transition.lua, drawn onto canvases and read back (tests/fx.script)
transition = require("transition")
particles = require("particles")
scene = require("scene")

local W, H = 480, 320
local CASES = { -- name, kind, k, options
  {"fade0", "fade", 0, {}}, {"fade5", "fade", 0.5, {}}, {"fade1", "fade", 1, {}},
  {"wipe_r", "wipe", 0.5, {}}, {"wipe_u", "wipe", 0.25, {dir = "up"}}, {"wipe_l", "wipe", 0.5, {dir = "left"}},
  {"curtain", "curtain", 0.5, {}}, {"curtain_v", "curtain", 0.5, {dir = "vertical"}},
  {"blinds", "blinds", 0.5, {}}, {"blinds_v", "blinds", 0.5, {dir = "vertical", bars = 4}},
  {"iris", "iris", 0.5, {}}, {"iris_at", "iris", 0.5, {cx = 100, cy = 100}}, {"iris1", "iris", 1, {}}, {"iris0", "iris", 0, {}},
  {"blocks", "blocks", 0.5, {}}, {"blocks0", "blocks", 0, {}}, {"blocks1", "blocks", 1, {}},
  {"colour", "wipe", 1, {color = 0xFF0000}},
}
fx = particles.new()
where, mid_calls, done_calls = "A", 0, 0
sceneA, sceneB = {}, {}
function sceneA.draw() rect(0, 0, W, H, 0x0C1020) end
function sceneB.draw() rect(0, 0, W, H, 0xA04020) end
function sceneA.enter() where = "A" end
function sceneB.enter() where = "B" end

function _init()
  show(0)
  canvas("SPR", 16, 16) target("SPR") cls(0xFF0000) target()
  scene.go(sceneA)
end

function _update()
  scene.update()
  transition.update()
  fx:update()
end

CUR = CASES[1][1]
function use(name) CUR = name end
function _draw()
  for _, c in ipairs(CASES) do
    if c[1] == CUR then
      canvas("T", W, H) target("T") cls(0xFFFFFF)
      transition.draw_kind(c[2], c[3], c[4])
      target()
    end
  end
  canvas("P", W, H) target("P") cls(0x000000) fx:draw() target()
  scene.draw()
  fx:draw()
  transition.draw()
end

function px(canvas_name, x, y) return pget(x, y, canvas_name) or -1 end
function red(c, x, y) return (px(c, x, y) >> 16) & 255 end
function blu(c, x, y) return px(c, x, y) & 255 end
function black(x, y) return px("T", x, y) == 0 end
function white(x, y) return px("T", x, y) == 0xFFFFFF end
function black_share() -- the part of a coarse grid that is black
  local n, b = 0, 0
  for y = 8, H - 1, 16 do for x = 8, W - 1, 16 do n = n + 1 if black(x, y) then b = b + 1 end end end
  return b / n
end
