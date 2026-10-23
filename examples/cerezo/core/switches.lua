-- switches: cells that something toggles: an eye in the wall a pinyol hits, a plate the hero stands on.
local Game = require("core.game")
local W = require("core.world")
local Sound = require("core.sound")
local Sw = {}

-- a pinyol hit the cell gx, gy (which is a solid with the "switch" flag): the flag in the area's switch list is set
function Sw.hit(gx, gy)
  for _, def in ipairs(W.area.things) do
    if def.kind == "eye" and def.cx == gx and def.cy == gy then
      Game.flags[def.flag] = true
      W.set(gx, gy, def.on or "eye_on")
      Sound.play("secret")
      return
    end
  end
end

return Sw
