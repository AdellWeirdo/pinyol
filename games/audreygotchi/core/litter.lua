-- litter: her litter box, it fills, it smells, you clean it (a port of audreygotchi/core/litter.py).
--
-- The owner, 2026-10-08, from a Tamagotchi's poop and its flush, the cat's way: a sand box in the bathroom that
-- gets a poop every LITTER_EVERY_SEC, up to LITTER_MAX. Two or more and it smells: her coat dirties faster and
-- her need is the bath (needs.lua). Baño opens a choice of two, like Curar: bathe her, or clean the box
-- (BATH_OPTIONS).
local util = require("core.util")
local M = {}

M.LITTER_EVERY_SEC = 3 * 3600
M.LITTER_MAX = 3
M.SMELLS_AT = 2 -- this many and it smells: her need, a faster dirty coat
M.SMELL_DIRT = 1.5 -- how much faster her coat dirties then
M.CLEAN_F, M.CLEAN_STRESS = 2.0, 5.0
M.BATH_OPTIONS = {"Bañarla", "Arenero"}

-- Each simulated second: in time, another poop in the box.
function M.second(s)
  s._litter_sec = util.int(s._litter_sec) + 1
  if s._litter_sec >= M.LITTER_EVERY_SEC then
    s._litter_sec = 0
    if util.int(s.litter) < M.LITTER_MAX then
      s.litter = util.int(s.litter) + 1
      s:mark_dirty()
    end
  end
end

function M.smells(s)
  return util.int(s.litter) >= M.SMELLS_AT
end

-- How fast her coat dirties now, against its usual pace.
function M.dirt_rate(s)
  if M.smells(s) then return M.SMELL_DIRT end
  return 1.0
end

-- Baño: the choice of two, the box picked first when it needs cleaning.
function M.open_bath(s, now_ms)
  s.mode = "action_bath"
  s.bath_choice = util.int(s.litter) ~= 0 and 1 or 0
  s.overlay_text, s.overlay_until = nil, 0
  s:mark_dirty()
end

function M.move(s, step)
  s.bath_choice = (util.int(s.bath_choice) + step) % #M.BATH_OPTIONS
  s:mark_dirty()
end

function M.confirm(s, now_ms)
  s.mode = "main"
  if util.int(s.bath_choice) % #M.BATH_OPTIONS == 0 then
    s:_act_bath(now_ms)
  else
    M.clean(s, now_ms)
  end
  s:compute_mood()
  s:mark_dirty()
end

-- The box cleaned: fresh sand, and she is glad of it.
function M.clean(s, now_ms)
  if util.int(s.litter) == 0 then
    s.overlay_text, s.overlay_until = "¡Si ya está limpio!", util.int(now_ms) + 900
    return
  end
  s.litter, s._litter_sec = 0, 0
  s.affection = math.min(100.0, s.affection + M.CLEAN_F)
  s.stress = s:_clamp_stat(s.stress - M.CLEAN_STRESS)
  s:_emit_sound("limpia")
  s.overlay_text, s.overlay_until = "¡Arenero limpito!", util.int(now_ms) + 900
  s:_log_event("Limpias el arenero")
  s:_register_interaction("Arenero", true)
end

return M
