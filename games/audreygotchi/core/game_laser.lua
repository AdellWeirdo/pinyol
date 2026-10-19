-- game_laser: Puntero láser, you move the red dot, she stalks it, you tell her when to pounce (a port of
-- audreygotchi/core/game_laser.py).
--
-- The owner's yes (2026-10-05). Five spots on the floor. A and C move the dot one spot; after each move she shifts
-- her aim one spot towards the dot, or, as cats do, not quite (FOLLOW by level). B: she pounces where she aims; on
-- the dot it is a catch, off it a miss and a heart. Three catches win; three misses lose. Too many moves without a
-- pounce (BORED) and she loses interest: a heart. Spots are 0-based.
local util = require("core.util")
local M = {}

M.SPOTS = 5
M.FOLLOW = {0.85, 0.65, 0.5}   -- easy, medium, hard: how often her aim steps towards the dot
M.CATCHES, M.HEARTS = 3, 3
M.BORED = 6
M.RESULT_MS = 1100

local AIM_OFFSETS = {-2, 2}
local NUDGES = {-1, 1}

local function clear(t) for k in pairs(t) do t[k] = nil end end

function M.start(rt, level, now_ms)
  clear(rt)
  local dot = math.random(0, M.SPOTS - 1)
  local aim = (dot + util.choice(AIM_OFFSETS)) % M.SPOTS
  rt.kind = "laser"
  rt.level = util.int(level)
  rt.dot = dot
  rt.aim = aim
  rt.caught = 0
  rt.hearts = M.HEARTS
  rt.moves = 0
  rt.result = nil
  rt.cause = nil
  rt.result_seq = 0
  rt.end_at = 0
  rt.at = 0
end

local function stalk(rt)
  if math.random() < M.FOLLOW[rt.level + 1] then
    rt.aim = rt.aim + ((rt.dot > rt.aim and 1 or 0) - (rt.dot < rt.aim and 1 or 0))
  else
    rt.aim = math.max(0, math.min(M.SPOTS - 1, rt.aim + util.choice(NUDGES)))
  end
end

local function settle(rt, cause, now_ms)
  local result = cause
  if result == "catch" then
    rt.caught = rt.caught + 1
    if rt.caught >= M.CATCHES then
      result = "won"
    end
  else
    rt.hearts = rt.hearts - 1
    if rt.hearts <= 0 then
      result = "lost"
    end
  end
  rt.result, rt.cause, rt.result_seq, rt.moves, rt.at = result, cause, rt.result_seq + 1, 0, now_ms
  if result == "won" or result == "lost" then
    rt.end_at = now_ms + M.RESULT_MS
  else   -- the dot darts off somewhere else, never right under her
    local spots = {}
    for spot = 0, M.SPOTS - 1 do
      if spot ~= rt.aim then spots[#spots + 1] = spot end
    end
    rt.dot = util.choice(spots)
  end
  return result
end

local function move(rt, step, now_ms)
  if rt.end_at ~= 0 then
    return nil
  end
  rt.dot = math.max(0, math.min(M.SPOTS - 1, rt.dot + step))
  rt.moves = rt.moves + 1
  stalk(rt)
  if rt.moves > M.BORED then
    return settle(rt, "bored", now_ms)
  end
  return nil
end

function M.left(rt, now_ms)
  return move(rt, -1, now_ms)
end

function M.right(rt, now_ms)
  return move(rt, 1, now_ms)
end

-- B: she pounces: "catch", "miss", "won", "lost"
function M.press(rt, now_ms)
  if rt.end_at ~= 0 then
    return nil
  end
  return settle(rt, rt.aim == rt.dot and "catch" or "miss", now_ms)
end

function M.tick(rt, now_ms)
  return nil
end

function M.over(rt, now_ms)
  local end_at = rt.end_at
  return end_at ~= 0 and (now_ms >= end_at or end_at - now_ms > M.RESULT_MS)   -- far ahead: the tick wrapped
end

function M.won(rt)
  return rt.caught >= M.CATCHES
end

function M.view(rt, now_ms)
  return {kind = "laser", level = rt.level, dot = rt.dot, aim = rt.aim,
          spots = M.SPOTS, caught = rt.caught, catches = M.CATCHES, hearts = rt.hearts,
          result = rt.result, cause = rt.cause, result_seq = rt.result_seq,
          at = rt.at}
end

function M.self_check()
  local rt = {}
  M.start(rt, 0, 0)
  rt.dot, rt.aim = 2, 2
  assert(M.press(rt, 0) == "catch" and rt.caught == 1)
  return true
end

return M
