-- The sandbox's limits, exercised by tests/sandbox.script.
local helper = require("lib.helper")
frames = 0
ticks_seen = 0

function spin() while true do end end
function escape() while true do pcall(function() while true do end end) end end -- pcall must not save it
function tailspin() local function f() return f() end return f() end -- every kind of endless loop the VM can run
function forspin() for i = 1, math.huge do end end
function genspin() for _ in function() return 1 end do end end
function repspin() repeat until false end
function gotospin() ::again:: goto again end
function cospin() while true do coroutine.resume(coroutine.create(function() while true do end end)) end end
function busy() local s = 0 for i = 1, 2000000 do s = s + i end return s end -- long, and within the budget
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
