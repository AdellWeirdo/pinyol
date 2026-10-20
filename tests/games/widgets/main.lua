-- What lib/widgets.lua made of a finger and the d-pad, for tests/widgets.script.
pointer = require("pointer")
widgets = require("widgets")
presses, level, picked = 0, 5, nil
ui = widgets.new()
b = ui:button({x = 20, y = 20, w = 120, h = 40, label = "Jugar", on = function() presses = presses + 1 end})
s = ui:slider({x = 20, y = 80, w = 200, h = 30, min = 0, max = 10, step = 1, value = 5, on = function(v) level = v end})
l = ui:list({x = 20, y = 130, w = 200, h = 84, row_h = 28, items = {"uno", "dos", "tres", "cuatro", "cinco", "seis"},
             on = function(i, item) picked = item end})
function _update()
  pointer.update()
  ui:update()
end
function _draw()
  cls(0x1A1F2E)
  ui:draw()
end
