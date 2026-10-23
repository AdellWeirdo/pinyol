-- run: what has happened in the level being played (it starts again with each try). The scene reads it for the screen, the things write it.
local R = {}

function R.reset(level)
  R.level = level
  R.coins = 0
  R.jewels = {false, false, false, false}
  R.key, R.chest = false, false
  R.escape, R.escape_t, R.escape_total = false, 0, 0
  R.t = 0             -- ticks played
  R.hits = 0          -- times hurt (for the clean-run achievement)
  R.broken = 0        -- blocks broken
  R.kills = 0
  R.frog_t = nil
  R.coin_events = {}
end

function R.jewel_count()
  local n = 0
  for i = 1, 4 do if R.jewels[i] then n = n + 1 end end
  return n
end

R.reset(1)

return R
