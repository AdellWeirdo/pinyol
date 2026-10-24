-- playtest adapter for Pozo (see docs/playtest.md). A perfect claw goes to the lane of the enemy that is closest to the rim and keeps firing.
local W = require("well")
PLAYTEST = {
  playing = function() return state == "play" end,
  progress = function() return G.level end,
  done = function()
    if state == "over" then return "lose" end
    if G.level >= 21 then return "win" end
  end,
  where = function() return "level_" .. G.level end,
  probe = function() return {score = G.score, n_lives = G.lives} end,
  perfect = function(pt)
    local me, want, best = G.me, nil, -1
    for _, f in ipairs(G.foes) do
      if f.d > best then best, want = f.d, f.lane end
    end
    local out = {a = true}
    if best > 0.88 and pt.t % 20 == 0 then out.b = true end -- the zapper when something is about to reach the rim
    if want and want ~= me.lane then
      local d = want - me.lane
      if W.closed and math.abs(d) > W.n / 2 then d = -d end -- round the rim the short way
      if pt.t % 3 == 0 then out[d > 0 and "right" or "left"] = true end -- one lane a press: let go between presses
    end
    return out
  end,
}
