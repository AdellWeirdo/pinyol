-- lib/light (tests/light.script): a palette's entries lit by a lamp from their normals
light = require("light")
lamp = light.new({bank = 1, obj = true, base = {[1] = 0x808080, [2] = 0x808080, [3] = 0x40C020},
                  normals = {[1] = {0, 0, 1}, [2] = {0, -1, 0}, [3] = {1, 0, 0}}, ambient = 0.2})
function _init() end
function _update() end
function _draw() cls(0) end
