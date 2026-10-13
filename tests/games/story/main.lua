-- A story as a game tells it (lib/story.lua), checked by tests/story.script.
story = require("story")
events = {}
function avisar(what) events[#events + 1] = what end

function _init()
  show(0)
  s = story.new(file("story/es.txt"), {name = "es.txt", vars = stored("story")})
  s:go("inicio")
end

function _update()
  if s:update() == "done" then ended = true end
end

function _draw()
  cls(0x182030)
  text("Bajopueblo", 240, 40, {font = "large", align = "center", color = 0xE8D8B0})
  s:draw()
end

function nch() local c = s:choices() return c and select("#", table.unpack(c)) or 0 end -- (scripts: # is a comment)
