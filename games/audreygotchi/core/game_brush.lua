-- game_brush: Cepillarla, a Persian's coat tangles; brush it out with her (a port of audreygotchi/core/game_brush.py).
--
-- The owner's yes (2026-10-05). Five places on her (head, back, tail, paws, belly), each with a few knots of fur
-- (more by level). A and C move the brush, B brushes there: a knot comes out. Brushing where there is none does
-- nothing. Her belly she would rather keep to herself: a brush there may cost her patience (BELLY_SWAT). All knots
-- out: a shiny coat, won; her patience gone: she walks off, lost. Zones are 0-based (`sel`); `knots[sel + 1]` is the
-- count at the zone selected.
local util = require("core.util")
local M = {}

M.ZONES = {"cabeza", "lomo", "cola", "patas", "barriga"}
M.KNOTS = {5, 7, 9}            -- easy, medium, hard: knots spread over the five places
M.PATIENCE = 3
M.BELLY_SWAT = {0.3, 0.45, 0.6}
M.RESULT_MS = 1300

local function clear(t) for k in pairs(t) do t[k] = nil end end

local function any(list) -- Python's any() over numbers
  for _, v in ipairs(list) do
    if v ~= 0 then return true end
  end
  return false
end

function M.start(rt, level, now_ms)
  clear(rt)
  local knots = {}
  for i = 1, #M.ZONES do knots[i] = 0 end
  for _ = 1, M.KNOTS[util.int(level) + 1] do
    local z = math.random(0, #M.ZONES - 1)
    knots[z + 1] = knots[z + 1] + 1
  end
  rt.kind = "brush"
  rt.level = util.int(level)
  rt.knots = knots
  rt.sel = 1
  rt.patience = M.PATIENCE
  rt.result = nil
  rt.result_seq = 0
  rt.end_at = 0
  rt.at = 0
end

function M.left(rt, now_ms)
  if rt.end_at == 0 then
    rt.sel = math.max(0, rt.sel - 1)
  end
end

function M.right(rt, now_ms)
  if rt.end_at == 0 then
    rt.sel = math.min(#M.ZONES - 1, rt.sel + 1)
  end
end

-- B: "knot" (one out), "smooth" (none there), "swat" (her belly), "won", "lost"
function M.press(rt, now_ms)
  if rt.end_at ~= 0 then
    return nil
  end
  local z = rt.sel
  local result
  if M.ZONES[z + 1] == "barriga" and math.random() < M.BELLY_SWAT[rt.level + 1] then
    rt.patience = rt.patience - 1
    result = rt.patience <= 0 and "lost" or "swat"
  elseif rt.knots[z + 1] ~= 0 then
    rt.knots[z + 1] = rt.knots[z + 1] - 1
    result = any(rt.knots) and "knot" or "won"
  else
    result = "smooth"
  end
  rt.result, rt.result_seq, rt.at = result, rt.result_seq + 1, now_ms
  if result == "won" or result == "lost" then
    rt.end_at = now_ms + M.RESULT_MS
  end
  return result
end

function M.tick(rt, now_ms)
  return nil
end

function M.over(rt, now_ms)
  local end_at = rt.end_at
  return end_at ~= 0 and (now_ms >= end_at or end_at - now_ms > M.RESULT_MS)   -- far ahead: the tick wrapped
end

function M.won(rt)
  return not any(rt.knots)
end

function M.view(rt, now_ms)
  return {kind = "brush", level = rt.level, knots = util.copy(rt.knots), zones = util.copy(M.ZONES),
          sel = rt.sel, patience = rt.patience, result = rt.result,
          result_seq = rt.result_seq, at = rt.at}
end

function M.self_check()
  local rt = {}
  M.start(rt, 0, 0)
  rt.knots, rt.sel = {0, 1, 0, 0, 0}, 1
  assert(M.press(rt, 0) == "won")
  return true
end

return M
