-- ¡ESQUIVA!: left and right, and none of the rocks may touch you until the time is out. (It leaves a ripple: line_scroll.)
local pad = require("pad")
local G = {verb = "¡ESQUIVA!", time = 4, bg = "BG2", timeout = "win"}
local hero, rocks, speed, t
local sheet_

function G.enter(level, spd)
  sheet_ = sheet("THINGS")
  hero, t = {x = 112}, 0
  speed = (1.4 + 0.2 * level) * spd
  rocks = {}
  for i = 1, math.min(6, 2 + level) do rocks[i] = {x = 12 + math.random(0, 200), y = -math.random(0, 120)} end
end

function G.update()
  t = t + 1
  local dx = (pad.btn("right") and 1 or 0) - (pad.btn("left") and 1 or 0)
  hero.x = math.max(0, math.min(224, hero.x + dx * 2.4))
  for _, r in ipairs(rocks) do
    r.y = r.y + speed
    if r.y > 170 then r.y, r.x = -16, 8 + math.random(0, 208) end
    if math.abs(r.x - hero.x) < 11 and math.abs(r.y - 128) < 12 then return "lose" end
  end
  for y = 0, 159 do line_scroll(3, y, math.floor(math.sin(y / 6 + t / 5) * 4)) end
end

function G.bot(lose)
  if lose then return {} end -- (it stands still, and a rock comes)
  -- the places the hero may not be, for the rocks about to arrive: it goes to the nearest one that is free
  local function free(x)
    for _, r in ipairs(rocks) do
      if r.y > 20 and r.y < 150 and math.abs(r.x - x) < 12 then return false end
    end
    return true
  end
  if free(hero.x) then return {} end
  for d = 2, 224, 2 do
    local right, left = hero.x + d, hero.x - d
    if right <= 224 and free(right) then return {right = true} end
    if left >= 0 and free(left) then return {left = true} end
  end
  return {}
end

function G.draw()
  spr(0, sheet_, 0, math.floor(hero.x), 128, prio(1))
  for i, r in ipairs(rocks) do spr(i, sheet_, 1, math.floor(r.x), math.floor(r.y), prio(1)) end
  for i = #rocks + 1, 8 do spr_off(i) end
end

return G
