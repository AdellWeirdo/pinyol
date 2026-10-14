-- input: the game's own actions, each one or more buttons, so code says "jump" and not "b"; a direction from the
-- d-pad; a jump pressed a moment before landing still jumping (btnb).
--
--   local input = require("input")
--   input.map({jump = {"b"}, fire = {"a", "c"}, pause = {"start"}})
--   if input.pressed("jump") then ... end         -- also input.down, input.released, input.held (ticks)
--   if on_ground and input.buffered("jump") then  -- pressed in the last 6 ticks, not used yet
--   local dx, dy = input.dir()                    -- -1, 0 or 1 each (diagonals too)
-- A name that is not an action is a button: input.down("a") works too.
local M = {}
local actions = {}

function M.map(t)
  for name, buttons in pairs(t) do
    assert(type(buttons) == "table", "input.map: " .. tostring(name) .. " = {buttons}")
  end
  actions = t
end

local function any(name, f, ...)
  local list = actions[name]
  if not list then return f(name, ...) end
  for _, b in ipairs(list) do
    local v = f(b, ...)
    if v then return v end
  end
  return false
end

function M.down(name) return any(name, btn) end
function M.pressed(name, hold, every) return any(name, btnp, hold, every) end
function M.released(name) return any(name, btnr) end
function M.buffered(name, window) return any(name, btnb, window or 6) end

function M.held(name) -- ticks the longest-held of its buttons has been down
  local list, most = actions[name] or {name}, 0
  for _, b in ipairs(list) do most = math.max(most, btnt(b)) end
  return most
end

function M.dir() -- the d-pad: dx, dy; with both held, the last one pressed wins
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  if btn("right") and btn("left") then dx = btnt("right") < btnt("left") and 1 or -1 end
  if btn("down") and btn("up") then dy = btnt("down") < btnt("up") and 1 or -1 end
  return dx, dy
end


return M
