-- care: the care score of a simulated minute (a port of audreygotchi/core/care.py).
local util = require("core.util")
local M = {}

function M.care_score_minute(s)
  local score = 1.0

  local good = 0
  if s.hunger >= 55 then
    good = good + 1
  end
  if s.energy >= 55 then
    good = good + 1
  end
  if s.health >= 70 then
    good = good + 1
  end
  if s.affection >= 60 then
    good = good + 1
  end

  score = score + good * 1.2

  if s.sick then
    score = score - 2.8
  end
  if s.in_critical then
    score = score - 4.2
  end
  if s.dirt > 75 then
    score = score - 1.5
  end

  if util.contains(s.quirks, "Dormilona") and s.sleeping then
    score = score + 0.4
  end
  if util.contains(s.quirks, "Glotona") and s.hunger < 35 then
    score = score - 0.6
  end
  if util.contains(s.quirks, "Huidiza") and s.hidden then
    score = score - 0.3
  end

  score = score + (s.trust_bond - 50.0) / 100.0
  score = score - (s.stress - 50.0) / 120.0

  return math.max(-6.0, math.min(8.0, score))
end

return M
