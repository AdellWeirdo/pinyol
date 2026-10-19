-- game_boxes: Trile de cajas, she climbs into one of three boxes, they shuffle, you say which (a port of
-- audreygotchi/core/game_boxes.py).
--
-- The owner's yes (2026-10-05). She is seen getting in (SHOW_MS), the boxes swap places (SWAPS by level, SWAP_MS
-- each), then A and C move the pointer and B lifts a box. Found: a round won; empty: she peeks out of the right one.
-- Three rounds, two win the game. Turn-based but for the show and the shuffle, which run on the platform's frame tick.
--
-- The board lives in the minigame's runtime table; `view()` is what the snapshot carries, with the frame tick each
-- phase began so the platform can animate the swaps. Boxes are 0-based; a swap is a pair {a, b} of boxes.
local util = require("core.util")
local M = {}

M.SWAPS = {3, 5, 7}            -- easy, medium, hard
M.SWAP_MS = {700, 550, 420}
M.SHOW_MS = 1500
M.RESULT_MS = 1600
M.ROUNDS, M.TO_WIN = 3, 2

local PAIRS = {{0, 1}, {1, 2}, {0, 2}}

local function clear(t) for k in pairs(t) do t[k] = nil end end

-- a round: she shows in a box, `cat` (the one she ended the last round in: she is seen getting back into it, the
-- owner, 2026-10-08), else any, and the boxes' swaps
local function new_round(rt, now_ms, cat)
  local level = rt.level
  local swaps = {}
  for _ = 1, M.SWAPS[level + 1] do
    local p = util.choice(PAIRS)
    swaps[#swaps + 1] = {p[1], p[2]}
  end
  if cat == nil then cat = math.random(0, 2) end
  rt.cat = cat
  rt.swaps = swaps
  rt.phase = "show"
  rt.phase_at = now_ms
  rt.picked = nil
  rt.sel = 1
end

function M.start(rt, level, now_ms)
  now_ms = now_ms or 0
  clear(rt)
  rt.kind = "boxes"
  rt.level = util.int(level)
  rt.round = 0
  rt.found = 0
  rt.result = nil
  rt.result_seq = 0
  rt.end_at = 0
  new_round(rt, now_ms)
end

-- the box she is in once the shuffle is over (public: the tests and the smoke run read it)
function M._where(rt)
  local pos = rt.cat
  for _, sw in ipairs(rt.swaps) do
    local a, b = sw[1], sw[2]
    if pos == a then pos = b elseif pos == b then pos = a end
  end
  return pos
end

function M.tick(rt, now_ms)
  local since = now_ms - rt.phase_at
  if since < 0 then              -- the frame tick wrapped: this phase starts over
    rt.phase_at, since = now_ms, 0
  end
  if rt.phase == "show" and since >= M.SHOW_MS then
    rt.phase, rt.phase_at = "shuffle", now_ms
  elseif rt.phase == "shuffle" and since >= #rt.swaps * M.SWAP_MS[rt.level + 1] then
    rt.phase, rt.phase_at = "pick", now_ms
  elseif rt.phase == "result" and since >= M.RESULT_MS and rt.end_at == 0 then
    new_round(rt, now_ms, M._where(rt))
  end
end

function M.left(rt, now_ms)
  if rt.phase == "pick" then
    rt.sel = math.max(0, rt.sel - 1)
  end
end

function M.right(rt, now_ms)
  if rt.phase == "pick" then
    rt.sel = math.min(2, rt.sel + 1)
  end
end

-- B: "found", "empty", or nil outside the pick
function M.press(rt, now_ms)
  if rt.phase ~= "pick" then
    return nil
  end
  rt.picked, rt.result_seq = rt.sel, rt.result_seq + 1
  rt.result = rt.sel == M._where(rt) and "found" or "empty"
  if rt.result == "found" then rt.found = rt.found + 1 end
  rt.round = rt.round + 1
  rt.phase, rt.phase_at = "result", now_ms
  local lost = rt.round - rt.found > M.ROUNDS - M.TO_WIN
  if rt.found >= M.TO_WIN or lost or rt.round >= M.ROUNDS then
    rt.end_at = now_ms + M.RESULT_MS
  end
  return rt.result
end

function M.over(rt, now_ms)
  local end_at = rt.end_at
  return end_at ~= 0 and (now_ms >= end_at or end_at - now_ms > M.RESULT_MS)   -- far ahead: the tick wrapped
end

function M.won(rt)
  return rt.found >= M.TO_WIN
end

function M.view(rt)
  local reveal = rt.phase == "show" or rt.phase == "result"
  local cat, where = nil, nil
  if rt.phase == "show" then cat = rt.cat end
  if reveal then where = M._where(rt) end
  return {kind = "boxes", level = rt.level, phase = rt.phase, phase_at = rt.phase_at,
          swaps = util.deepcopy(rt.swaps), swap_ms = M.SWAP_MS[rt.level + 1],
          cat = cat, where = where, sel = rt.sel, picked = rt.picked,
          round = rt.round, rounds = M.ROUNDS, found = rt.found, result = rt.result,
          result_seq = rt.result_seq}
end

function M.self_check()
  local rt = {}
  M.start(rt, 0, 0)
  rt.swaps, rt.cat = {{0, 1}}, 0
  M.tick(rt, M.SHOW_MS)
  M.tick(rt, M.SHOW_MS + M.SWAP_MS[1])
  M.right(rt, 0)
  M.left(rt, 0)
  assert(rt.phase == "pick" and M.press(rt, 5000) == "found")
  return true
end

return M
