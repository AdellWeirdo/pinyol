-- playtest adapter for Malabarista (see docs/playtest.md). A perfect player presses the hand a ball has just reached. The game never ends well: the best is to survive.
-- playtest-gate: survive   (tests/playtest_gate.py: the perfect player must survive to the cap; ctest runs it)
PLAYTEST = {
  playing = function() return state == "play" end,
  progress = function() return score end,
  -- the number of balls the game counts must be the balls on the board (or none, in the pause after a miss): it counted three and showed one
  invariants = function() if state == "play" and #balls ~= 0 and #balls ~= balls_n then return "balls_" .. #balls .. "_of_" .. balls_n end end,
  done = function() if state == "over" then return "lose" end end,
  where = function() return "mode_" .. mode .. "_score_" .. (score // 25) * 25 end,
  probe = function() return {n_score = score, n_misses = misses, n_balls = #balls} end,
  perfect = function()
    local out = {}
    for _, b in ipairs(balls) do
      if b.k == 6 then out[(b.dir == 1 and 2 or 1) == 1 and "left" or "right"] = true end
    end
    return out
  end,
}
