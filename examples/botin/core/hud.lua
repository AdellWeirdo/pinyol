-- hud: hearts, coins, the four pieces of the jewel, the key and, during the escape, the frog's alarm and the time left. All of it sprites (the GBA drew its
-- status line with objects too), drawn first so they take the lowest slots, in front of everything.
local C = require("core.const")
local S = require("core.spr")
local Run = require("core.run")
local H = {}

local function number(n, x, y, digits, id)
  local s = string.format("%0" .. digits .. "d", math.min(n, 10 ^ digits - 1))
  for i = 1, #s do
    S.draw("UI8", "d_" .. s:sub(i, i), x + (i - 1) * 8, y, {prio = 0})
  end
end

function H.draw(hero, t)
  for i = 1, C.HEARTS do
    local x = 4 + (i - 1) * 17
    if i <= hero.hearts then
      S.draw("UI16", "heart_full_" .. ((t // 24 + i) % 2), x, 3, {prio = 0})
    else
      S.draw("UI16", "heart_empty", x, 3, {prio = 0})
    end
  end
  S.draw("UI8", "coin_mini", 190, 5, {prio = 0})
  number(Run.coins, 200, 5, 4)
  for i = 1, Run.level == 5 and 0 or 4 do
    S.draw("UI8", (Run.jewels[i] and "jewel_mini_full_" or "jewel_mini_empty_") .. i, 4 + (i - 1) * 9, 22, {prio = 0})
  end
  if Run.key and Run.level ~= 5 then S.draw("UI8", "key_mini", 42, 22, {prio = 0}) end
  if Run.escape then
    local secs = math.ceil(Run.escape_t / 60)
    local flash = Run.escape_t < 600 and (t // 8) % 2 == 0
    S.draw("UI16", "frog_alarm_" .. ((t // 5) % 4), 112, 2, {prio = 0})
    S.draw("UI8", "clock_mini", 106, 21, {prio = 0})
    if not flash then number(secs, 116, 21, 3) end
  end
end

return H
