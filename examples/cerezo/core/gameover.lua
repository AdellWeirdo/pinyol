-- gameover: he has fallen. The island fades, a short sad tune, and a choice: go on from the last place saved, or the title.
local Pal = require("core.pal")
local Sound = require("core.sound")
local Music = require("core.music")
local lang = require("lang")
local Save = require("core.save")
local Game = require("core.game")
local O = {}

O.t, O.sel = 0, 1

function O.enter()
  O.t, O.sel = 0, 1
  Game.deaths = Game.deaths + 1
  Music.play("jingle_gameover", 0)
end

-- returns "continue" or "title"
function O.update()
  O.t = O.t + 1
  if O.t < 40 then Pal.fade("dark", math.min(3, O.t // 10)) return end
  if O.t == 40 then Pal.fade("dark", 0) end
  if btnp("up") or btnp("down") then O.sel = 3 - O.sel Sound.play("select") end
  if btnp("a") or btnp("start") then
    Sound.play("confirm")
    return O.sel == 1 and "continue" or "title"
  end
end

function O.draw()
  cls(Pal.tone(1))
  local ink = Pal.tone(4)
  if O.t < 40 then return end
  text(lang.tr("gameover"), 240, 100, {font = "ps", color = ink, align = "center", scale = 2})
  for i, k in ipairs({"gameover_continue", "gameover_title"}) do
    local y = 190 + (i - 1) * 28
    if i == O.sel then tri(130, y + 3, 130, y + 15, 138, y + 9, ink) end
    text(lang.tr(k), 150, y, {font = "ps", color = ink})
  end
end

return O
