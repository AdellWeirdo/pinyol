-- playtest-gate: win   (tests/playtest_gate.py: the perfect player must finish the game; ctest runs it)
-- playtest adapter for Tumba (see docs/playtest.md). The perfect player plays each level's stored solution, one move every 40 ticks (a slide takes less), and the
-- bot's "press A now and then" takes it from the title through the level select and the clears. The solutions are the solver's own: if the game's rules ever
-- differ from gen/rules.py, a level does not clear in its par and this player stops (the `stuck` outcome).
local Levels = require("levels")
local last = -100
PLAYTEST = {
  playing = function() return state == "play" end,
  progress = function() return GAME.level + (state == "win" and 1 or 0) end,
  done = function() if state == "win" then return "win" end end,
  where = function() return "level_" .. GAME.level end,
  probe = function() return {n_level = GAME.level, n_moves = GAME.moves} end,
  perfect = function(pt)
    local out = {}
    local sol = Levels[GAME.level].solution
    local c = sol:sub(GAME.moves + 1, GAME.moves + 1)
    if c ~= "" and pt.t - last >= 40 then
      last = pt.t
      out[({U = "up", D = "down", L = "left", R = "right"})[c]] = true
    end
    return out
  end,
}
