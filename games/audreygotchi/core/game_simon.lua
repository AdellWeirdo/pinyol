-- game_simon: Simón, she meows a run of colours, you play it back (a port of audreygotchi/core/game_simon.py).
--
-- The owner's yes (2026-10-05). Three colours, one per button: A red, B green, C blue. She shows the run (STEP_MS a
-- colour, on screen and on the board's RGB LED), then you repeat it. Right: the next round is one colour longer;
-- wrong: a heart, and the same run again. Win by playing ROUNDS runs; three hearts lost lose. The show runs on the
-- platform's frame tick. Colours are 0-based (0 red, 1 green, 2 blue).
local util = require("core.util")
local M = {}

M.COLOURS = {"red", "green", "blue"}
M.FIRST_LEN = {3, 4, 5}         -- easy, medium, hard
M.STEP_MS = {700, 560, 450}
M.FASTER_MS, M.FASTEST_MS = 70, 300   -- each round won sings the run this much quicker, to this (2026-10-08)
M.ROUNDS, M.HEARTS = 3, 3
M.RESULT_MS = 1300

local function clear(t) for k in pairs(t) do t[k] = nil end end

function M.start(rt, level, now_ms)
  now_ms = now_ms or 0
  clear(rt)
  local n = M.FIRST_LEN[util.int(level) + 1]
  local run = {}
  for _ = 1, n do run[#run + 1] = math.random(0, 2) end
  rt.kind = "simon"
  rt.level = util.int(level)
  rt.run = run
  rt.got = 0
  rt.round = 0
  rt.hearts = M.HEARTS
  rt.phase = "show"
  rt.phase_at = now_ms
  rt.result = nil
  rt.result_seq = 0
  rt.end_at = 0
  rt.last = nil
end

-- a colour's time in her run: quicker as the rounds go (the owner, 2026-10-08)
function M.step_ms(rt)
  return math.max(M.FASTEST_MS, M.STEP_MS[rt.level + 1] - M.FASTER_MS * rt.round)
end

local function show_ms(rt)
  return #rt.run * M.step_ms(rt)
end

-- the colour showing now (0-2), or nil
function M.lit(rt, now_ms)
  if rt.phase ~= "show" then
    return nil
  end
  local ms = M.step_ms(rt)
  local step = (now_ms - rt.phase_at) // ms
  if 0 <= step and step < #rt.run and (now_ms - rt.phase_at) % ms < ms * 3 // 4 then
    return rt.run[step + 1]
  end
  return nil
end

function M.tick(rt, now_ms)
  local since = now_ms - rt.phase_at
  if since < 0 then              -- the frame tick wrapped: this phase starts over
    rt.phase_at, since = now_ms, 0
  end
  if rt.phase == "show" and since >= show_ms(rt) then
    rt.phase, rt.phase_at, rt.got = "input", now_ms, 0
  elseif rt.phase == "result" and since >= M.RESULT_MS and rt.end_at == 0 then
    if rt.result == "round" then          -- right: the next run is one colour longer
      rt.run[#rt.run + 1] = math.random(0, 2)
    end
    rt.phase, rt.phase_at, rt.got = "show", now_ms, 0
  end
end

local function play(rt, colour, now_ms)
  if rt.phase ~= "input" then
    return nil
  end
  rt.last = colour
  if colour == rt.run[rt.got + 1] then
    rt.got = rt.got + 1
    if rt.got < #rt.run then
      return "ok"
    end
    rt.round = rt.round + 1
    rt.result = rt.round >= M.ROUNDS and "won" or "round"
  else
    rt.hearts = rt.hearts - 1
    rt.result = rt.hearts <= 0 and "lost" or "miss"
  end
  rt.result_seq = rt.result_seq + 1
  rt.phase, rt.phase_at = "result", now_ms
  if rt.result == "won" or rt.result == "lost" then
    rt.end_at = now_ms + M.RESULT_MS
  end
  return rt.result
end

function M.left(rt, now_ms)
  return play(rt, 0, now_ms)
end

function M.press(rt, now_ms)
  return play(rt, 1, now_ms)
end

function M.right(rt, now_ms)
  return play(rt, 2, now_ms)
end

function M.over(rt, now_ms)
  local end_at = rt.end_at
  return end_at ~= 0 and (now_ms >= end_at or end_at - now_ms > M.RESULT_MS)   -- far ahead: the tick wrapped
end

function M.won(rt)
  return rt.result == "won"
end

function M.view(rt, now_ms)
  now_ms = now_ms or 0
  local run = {}
  if rt.phase == "show" then run = util.copy(rt.run) end
  return {kind = "simon", level = rt.level, phase = rt.phase, phase_at = rt.phase_at,
          run_len = #rt.run, got = rt.got, round = rt.round, rounds = M.ROUNDS,
          hearts = rt.hearts, result = rt.result, result_seq = rt.result_seq,
          lit = M.lit(rt, now_ms), last = rt.last, step_ms = M.step_ms(rt),
          run = run}
end

function M.self_check()
  local rt = {}
  M.start(rt, 0, 0)
  rt.run = {0, 1, 2}
  M.tick(rt, show_ms(rt))
  assert(M.left(rt, 0) == "ok" and M.press(rt, 0) == "ok" and M.right(rt, 0) == "round")
  return true
end

return M
