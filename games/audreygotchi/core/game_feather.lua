-- game_feather: Palito con plumas, the feather comes down a step each turn and she moves under it (a port of
-- audreygotchi/core/game_feather.py).
--
-- The owner's design (2026-10-04). Each press is a turn: A a step left, C a step right, B stays; then the feather
-- comes down a row along its path. On the bottom row she catches it if she is under it. Three feathers, a heart lost
-- per miss: two catches win, two misses lose. The level sets the columns, how far a step can drift and how much of
-- the path shows. The last landing stays on screen for END_MS (her jump), or CATCH_END_MS when she caught it (her
-- jump, then she turns to you with it in her mouth), then the game ends.
--
-- The board lives in the minigame's runtime table; `view()` is what the snapshot carries. Columns are 0-based.
local util = require("core.util")
local M = {}

M.COLS = {3, 5, 6}               -- columns: easy, medium, hard
M.ROWS = 5                       -- the feather starts on row 5 and lands on row 1
M.FEATHERS, M.GOAL = 3, 2        -- three feathers, two catches win
M.WIDE_DRIFT = {0.0, 0.15, 0.3}  -- chance a step drifts two columns, by level
M.END_MS = 1500
M.CATCH_END_MS = 3300            -- the owner, 2026-10-09: the game ended before "lo tengo" showed

local STEPS = {-1, 0, 1}

local function clear(t) for k in pairs(t) do t[k] = nil end end

-- the feather's column on each row, top first; it bounces off the board's edges
function M.new_path(level)
  local cols = M.COLS[level + 1]
  local col = math.random(0, cols - 1)
  local path = {col}
  for _ = 1, M.ROWS - 1 do
    local step = util.choice(STEPS)
    if step ~= 0 and math.random() < M.WIDE_DRIFT[level + 1] then
      step = step * 2
    end
    col = col + step
    if not (0 <= col and col < cols) then
      col = col - 2 * step
    end
    col = math.max(0, math.min(cols - 1, col))
    path[#path + 1] = col
  end
  return path
end

function M.start(rt, level)
  clear(rt)
  rt.kind = "feather_path"
  rt.level = util.int(level)
  rt.cols = M.COLS[rt.level + 1]
  rt.round = 1
  rt.caught = 0
  rt.missed = 0
  rt.result = nil
  rt.result_seq = 0
  rt.landed = nil
  rt.end_at = 0
  M.next_feather(rt)
end

function M.next_feather(rt)
  rt.path, rt.step, rt.cat = M.new_path(rt.level), 0, rt.cols // 2
end

-- one press: "catch" or "miss" when the feather lands, else nil
function M.turn(rt, move)
  rt.cat = math.max(0, math.min(rt.cols - 1, rt.cat + move))
  rt.step = rt.step + 1
  if rt.step < M.ROWS - 1 then
    return nil
  end
  local hit = rt.cat == rt.path[#rt.path]
  rt.landed = rt.cat
  if hit then rt.caught = rt.caught + 1 else rt.missed = rt.missed + 1 end
  rt.result = hit and "catch" or "miss"
  rt.result_seq = rt.result_seq + 1
  return rt.result
end

-- "win", "lose", or nil while the game goes on
function M.outcome(rt)
  if rt.caught >= M.GOAL then
    return "win"
  end
  if rt.missed > M.FEATHERS - M.GOAL then
    return "lose"
  end
  return nil
end

-- true once the last landing has shown long enough
function M.over(rt, now_ms)
  local end_at = rt.end_at
  return end_at ~= 0 and (now_ms >= end_at or end_at - now_ms > M.CATCH_END_MS)   -- far ahead: the tick wrapped
end

function M.view(rt)
  local step, path, level = rt.step, rt.path, rt.level
  local col, upcoming = path[step + 1], util.slice(path, step + 1)
  local hint = {}                                   -- where it goes next (owner, 2026-10-06); hard: none
  if level < 2 then hint = util.slice(upcoming, 0, 1) end
  local sway = nil
  if level == 2 and #upcoming > 0 then
    sway = (upcoming[1] > col and 1 or 0) - (upcoming[1] < col and 1 or 0)
  end
  return {kind = "feather", level = level, cols = rt.cols, rows = M.ROWS, row = M.ROWS - step,
          col = col, cat = rt.cat, hint = hint, sway = sway,
          hearts = M.FEATHERS - rt.missed, caught = rt.caught, goal = M.GOAL,
          round = rt.round, result = rt.result, result_seq = rt.result_seq,
          landed = rt.landed}
end

function M.self_check()
  local rt = {}
  M.start(rt, 0)
  rt.path = {1, 1, 2, 2, 2}
  assert(M.turn(rt, 1) == nil and M.turn(rt, 0) == nil and M.turn(rt, 0) == nil and M.turn(rt, 0) == "catch")
  assert(M.outcome(rt) == nil and M.view(rt).caught == 1)
  return true
end

return M
