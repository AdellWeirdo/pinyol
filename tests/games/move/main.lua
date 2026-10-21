-- lib/move (actors, solids, the platformer's forgiveness) and lib/autotile, on a level drawn as text (tests/move.script)
move = require("move")
autotile = require("autotile")

LEVEL = {
  "....................",
  "....................",
  "....................",
  "......#.............",
  "....................",
  "....................",
  "..........---.......",
  "#...................",
  "#...................",
  "####################",
}
T = 8
function cell(tx, ty) if ty < 0 or ty >= #LEVEL or tx < 0 or tx >= 20 then return "#" end return LEVEL[ty + 1]:sub(tx + 1, tx + 1) end
function solid(x, y, w, h)
  for ty = y // T, (y + h - 1) // T do
    for tx = x // T, (x + w - 1) // T do if cell(tx, ty) == "#" then return true end end
  end
  return false
end
function oneway(x, y, w, h)
  for ty = y // T, (y + h - 1) // T do
    for tx = x // T, (x + w - 1) // T do if cell(tx, ty) == "-" then return true end end
  end
  return false
end

hero = move.actor(16, 72 - 14, 8, 14, {solid = solid, oneway = oneway})
pl = move.platformer(hero, {speed = 2, accel = 0.5, jump = 4, gravity = 0.25, max_fall = 5, coyote = 6, buffer = 6, corner = 4})
dir, jump_p, jump_h = 0, false, false
lift = nil
jumps, landings = 0, 0

-- autotile on a map kept in a table (mset is the engine's; here the game's own, to look at what it wrote)
grid = {}
function mset(layer, tx, ty, v) grid[ty * 100 + tx] = v end
function mget_(tx, ty) return grid[ty * 100 + tx] end
function is_solid(tx, ty) return cell(tx, ty) == "#" end

function _update()
  if lift then lift:move(lift_dx or 0, lift_dy or 0) end
  pl:update(dir, jump_p, jump_h)
  if pl.jumped then jumps = jumps + 1 end
  if pl.landed then landings = landings + 1 end
  jump_p = false
end
function _draw() cls(0) end
