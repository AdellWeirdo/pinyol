-- The sandbox's limits, exercised by tests/sandbox.script.
local helper = require("lib.helper")
frames = 0
ticks_seen = 0

function spin() while true do end end
function hog() local t = {} for i = 1, 10000000 do t[i] = i end end
function helper_value() return helper.answer end

function _init()
  backdrop(rgb(20, 30, 60))
end

function _update()
  ticks_seen = ticks_seen + 1
end

function _draw()
  frames = frames + 1
  text("sandbox " .. frames, 8, 8)
end
