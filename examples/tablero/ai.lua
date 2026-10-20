-- ai: what a computer-led unit does with its turn: of the cells it can reach, the one from which it hits best and is hit least, else the
-- one nearest the enemy (one `distances` search from all of them), and then the blow. It looks at the state and says what to do; it
-- changes nothing, so the scene plays the answer (an animation, then rules.strike).
local R = require("rules")

local M = {}

-- {x, y, target (a unit id or nil)} for this unit
function M.decide(state, u)
  local enemies, goals = {}, {}
  for _, o in ipairs(state.units) do
    if o.team ~= u.team then enemies[#enemies + 1] = o goals[#goals + 1] = {o.x, o.y} end
  end
  if #goals == 0 then return {x = u.x, y = u.y} end
  local cells = R.reach(state, u)
  local field = R.cost_grid(state):distances(goals)
  local best, best_score
  for _, c in ipairs(cells) do
    local targets = R.targets(state, u, c.x, c.y)
    local def = R.terrain_at(state, c.x, c.y).def
    local score, pick
    if #targets > 0 then
      score = -1e9
      for _, t in ipairs(targets) do
        local dmg = R.damage(u, t, R.terrain_at(state, t.x, t.y).def)
        local kill = dmg >= t.hp and 50 or 0
        local s = 100 + dmg * 3 + kill - (t.hp - dmg) * 0.5 + def * 3
        if s > score then score, pick = s, t end
      end
    else
      score = -(field:get(c.x, c.y) or 99) + def * 0.5
    end
    if not best_score or score > best_score then best, best_score = {x = c.x, y = c.y, target = pick and pick.id}, score end
  end
  return best
end

return M
