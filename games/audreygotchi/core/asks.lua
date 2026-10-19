-- asks: what she asks you (a port of audreygotchi/core/asks.py). At bedtime, to turn the light off; her whims,
-- asking for you when she needs nothing (events "capricho"); and when she plays the diva (personality.DIVA_LINES),
-- what you do about it: spoil her or scold her, Tamagotchi's discipline, the pampered axis either way.
-- A picks Sí, C picks No, B answers; back, or no answer in time, is a No. The question opens and times out on the
-- simulated second, so a board catching up after a night off asks at 22:00 too.
local util = require("core.util")
local events = require("core.events")
local memory = require("core.memory")
local M = {}

M.BED_FROM = 22              -- her first awake minute from 22:00 to midnight...
M.BED_EVERY_SEC = 12 * 3600  -- ...once a night
M.BED_WAIT_SEC = 30 * 60
M.BED_F = 5.0
M.MORNING = 8                -- tucked in, she does not wake up on her own before 08:00
M.WHIM_WAIT_SEC = 15 * 60    -- a whim left this long is a No
M.WHIM_F = 3.0
M.DIVA_WAIT_SEC = 60         -- her diva no, answered or let go
M.SCOLD_STRESS = 4.0         -- a scolding stings a little

function M.now(s)
  local ts = util.get(s, "_sim_ts", 0)
  if ts ~= 0 then return ts end
  return s.clock:now()
end

function M.start(s, kind, wait_sec)
  s.mode, s.ask, s.ask_yes = "ask", kind, true -- transient: a restart forgets the question
  s.ask_until = M.now(s) + util.int(wait_sec)
  s:mark_dirty()
end

function M.choose(s, yes)
  s.ask_yes = not not yes
  s:mark_dirty()
end

function M.confirm(s, now_ms)
  M.answer(s, s.ask_yes, now_ms)
end

function M.answer(s, yes, now_ms)
  local kind = s.ask
  s.mode, s.ask = "main", nil
  if kind == "bed" and yes then
    s.affection = math.min(100.0, s.affection + M.BED_F)
    s.tucked_at = M.now(s)
    s:enter_sleep(now_ms, "buenas_noches", false)
    s.overlay_text, s.overlay_until = "Buenas noches", now_ms + 1500
  elseif kind == "whim" then -- Mimos spoils her, a No toughens her (the pampered axis)
    memory.remember(s, yes and "whim_yes" or "whim_no")
    if yes then
      s.affection = math.min(100.0, s.affection + M.WHIM_F)
    end
    s:_emit_sound(yes and "mimos" or "cola")
  elseif kind == "diva" then -- spoilt for it, the more a diva; scolded, she sulks and learns
    memory.remember(s, yes and "whim_yes" or "whim_no")
    if yes then
      s.affection = math.min(100.0, s.affection + M.WHIM_F)
    else
      s.stress = s:_clamp_stat(s.stress + M.SCOLD_STRESS)
      s:_log_event("La regañas")
    end
    s:_emit_sound(yes and "mimos" or "regana")
  end
  s:mark_dirty()
end

-- Each simulated minute: a question left too long is a No; at bedtime she asks.
function M.minute(s, now_ms)
  local t = M.now(s)
  if s.mode == "ask" then
    if t >= s.ask_until then
      M.answer(s, false, now_ms)
    end
    return
  end
  if t - s.bed_at >= M.BED_EVERY_SEC and events.able(s) and events.hour(s) >= M.BED_FROM then
    s.bed_at = t
    M.start(s, "bed", M.BED_WAIT_SEC)
    s:_emit_sound("bosteza")
  end
end

-- Tucked in tonight: she sleeps on till the morning.
function M.tucked_in(s)
  if M.now(s) - s.tucked_at >= M.BED_EVERY_SEC then
    return false
  end
  local h = events.hour(s)
  return h >= M.BED_FROM or h < M.MORNING
end

return M
