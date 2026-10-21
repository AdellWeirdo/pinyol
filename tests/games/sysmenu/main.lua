-- The console's menu over a game (tests/sysmenu.script): ticks counted, an item of the game's own, _pause and _resume,
-- a crash on demand, and what the buttons say (A and B can be swapped by the console).
n, rang, paused, resumed, last, crash = 0, false, 0, 0, nil, false
function _init()
  n, rang = 0, false
  menuitem("Sonar", function() rang = true end)
end
function _pause() paused = paused + 1 end
function _resume() resumed = resumed + 1 end
function _update()
  if crash then error("boom at tick " .. ticks()) end
  n = n + 1
  if btnp("a") then last = "a" elseif btnp("b") then last = "b" end
  if read_menu and btn("menu") then held_menu = true end
end
function _draw()
  cls(0x203040)
  text("n " .. n, 10, 10)
  rect(100, 100, 280, 120, 0xFF8000)
end
