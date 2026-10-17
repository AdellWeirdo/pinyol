-- game_knots: Quita nudos, her paws under a knot with three ends; pull the right one to loosen it (a port of
-- audreygotchi/core/game_knots.py).
--
-- The owner's design (2026-10-04). A and C pick an end (left, middle, right), B pulls it. The right end loosens the
-- knot, which shows as a looser drawing; the wrong one tightens it and costs a heart. Three good pulls free it, three
-- misses lose. The result stays on screen for END_MS, then the game ends. The level picks the drawings (the platform
-- shows how plainly the right end glows); the knots are numbered 1 (loosest) to 6, and 0 is free.
--
-- The board lives in the minigame's runtime table; `view()` is what the snapshot carries. Ends are 0-based.
local util = require("core.util")
local M = {}

M.KNOTS = {{3, 2, 1}, {5, 4, 3}, {6, 4, 2}}   -- the drawings, pull by pull: easy, medium, hard
M.HEARTS = 3
M.END_MS = 1500

local function clear(t) for k in pairs(t) do t[k] = nil end end

function M.start(rt, level)
  clear(rt)
  rt.kind = "knots"
  rt.level = util.int(level)
  rt.step = 0
  rt.sel = 1
  rt.good = math.random(0, 2)
  rt.hearts = M.HEARTS
  rt.result = nil
  rt.result_seq = 0
  rt.pulled = nil
  rt.end_at = 0
end

function M.move(rt, step)
  if rt.end_at == 0 then
    rt.sel = math.max(0, math.min(2, rt.sel + step))
  end
end

-- B: "ok", "miss", "free" (won), "lost", or nil while the result shows
function M.pull(rt, now_ms)
  if rt.end_at ~= 0 then
    return nil
  end
  rt.pulled, rt.result_seq = rt.sel, rt.result_seq + 1
  if rt.sel == rt.good then
    rt.step = rt.step + 1
    rt.result = rt.step >= #M.KNOTS[1] and "free" or "ok"
    rt.good = math.random(0, 2)
  else
    rt.hearts = rt.hearts - 1
    rt.result = rt.hearts <= 0 and "lost" or "miss"
  end
  if rt.result == "free" or rt.result == "lost" then
    rt.end_at = now_ms + M.END_MS
  end
  return rt.result
end

-- true once the result has shown long enough
function M.over(rt, now_ms)
  local end_at = rt.end_at
  return end_at ~= 0 and (now_ms >= end_at or end_at - now_ms > M.END_MS)   -- far ahead: the tick wrapped
end

function M.view(rt)
  local step = rt.step
  local knot = 0
  if step < #M.KNOTS[1] then knot = M.KNOTS[rt.level + 1][step + 1] end
  return {kind = "knots", level = rt.level, knot = knot, step = step,
          steps = #M.KNOTS[1], sel = rt.sel, good = rt.good, hearts = rt.hearts,
          result = rt.result, result_seq = rt.result_seq, pulled = rt.pulled}
end

function M.self_check()
  local rt = {}
  M.start(rt, 2)
  rt.good = 0
  M.move(rt, -1)
  assert(M.pull(rt, 0) == "ok" and M.view(rt).knot == 4)
  return true
end

return M
