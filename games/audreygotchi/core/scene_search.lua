-- scene_search: hide and seek, and what A+C finds her doing (a port of audreygotchi/core/scene_search.py).
local util = require("core.util")
local events = require("core.events")
local memory = require("core.memory")
local M = {}

M.REPLY_MS = 600       -- her answer to A+C comes after the search sound
M.REPLY_LATE_MS = 3000 -- or later, when she takes her time

-- She hides: in one of the rooms (HIDING_ROOMS), any of them, the one on screen included; there she peeks out
-- until found or until she comes out.
function M.hide(s, now_ms)
  s.hidden = true
  s.hidden_scene = util.int(util.choice(s.HIDING_ROOMS)) -- a room index, 0-based
  s.seek_misses, s.seek_searched = 0, 0 -- a new round
  s.seek_play = false                   -- of her own accord, unless Play started it
  s:_emit_sound("escondida")
  s:mark_dirty()
end

-- Of her own accord (an event, a fright, her answer to A+C), not before HIDE_REST_MS out of hiding; Play's Síguela
-- is asked for, so it never waits. A puppy never does (the owner, 2026-10-06).
function M.may_hide(s, now_ms)
  if s.phase == "Cachorro" then
    return false
  end
  local until_ms, now = util.int(s._hide_cd_until_ms), util.int(now_ms)
  return now >= until_ms or until_ms - now > s.HIDE_REST_MS -- far ahead: the tick wrapped
end

function M.unhide(s, now_ms)
  if now_ms ~= nil then
    s._hide_cd_until_ms = util.int(now_ms) + s.HIDE_REST_MS
  end
  s.hidden = false
  s.hidden_scene = -1
  s.seek_play = false
  s:mark_dirty()
end

-- Play > Siguela por la casa: she hides at once, and finding her is that game won.
function M.play_seek(s, now_ms)
  if s.energy <= 10 then
    s:_register_interaction("Juego", false) -- as every game she is too tired for
    s:exit_action_minigame(now_ms, "Me quedé sin pilas")
    return
  end
  s:exit_action_minigame(now_ms, "¡A que no me encuentras!")
  M.hide(s, now_ms)
  s.seek_play = true
end

-- A or C while she hides: walk to the next room, without searching it.
function M.look(s, step)
  s.current_scene = (util.int(s.current_scene) + step) % #s.scenarios
  s:mark_dirty()
end

-- B while she hides: look in the room on screen. True when she is there.
function M.search_here(s, now_ms)
  if util.int(s.current_scene) == util.int(s.hidden_scene) then
    local found, from_play = util.int(s.seek_misses) == 0, not not s.seek_play
    s.seek_found = s.seek_found + 1
    memory.remember(s, "found") -- searching makes her curious (Bible §5.1)
    memory.first(s, "found")
    if found then s.seek_first_try = s.seek_first_try + 1 end
    M.unhide(s, now_ms)
    s:_emit_sound("encontrada")
    s.overlay_text = "¡Aquí estoy!"
    s:_log_event("Encontrado")
    if from_play then -- a game of Play: what every game gives (v9 §7.2), and its stars
      s:_minigame_apply(now_ms, "Juego:SiguelaCasa", 1.0)
      local minigames = require("core.minigames") -- here, as the Python imports it
      minigames.record_result(s, "Siguela por la casa", 3 - math.min(2, util.int(s.seek_misses)), true)
    else
      local f = s.SEEK_FOUND_F
      if found then f = s.SEEK_FIRST_TRY_F end
      s.affection = math.min(100.0, s.affection + f)
    end
    s:compute_mood()
  else
    s.seek_misses = s.seek_misses + 1
    s.seek_searched = s.seek_searched | (1 << util.int(s.current_scene))
    s:_emit_sound("buscar")
    s.overlay_text = "¡Frío, frío!"
  end
  s.overlay_until = now_ms + 900
  s:mark_dirty()
  return not s.hidden
end

-- Bible §18: what A+C finds her doing, by stage, mood, temperament, energy and hour. can_hide defaults to true.
-- ponytail: feel weights; tune by watching her.
function M.reply(s, can_hide)
  if can_hide == nil then can_hide = true end
  local e, mood, phase = s.energy, s.mood, tostring(s.phase)
  local social, curious, active = s:_pf("sociability"), s:_pf("curiosity"), s:_pf("activity")
  local h = events.hour(s)
  local evening = h >= 20 or h < 7
  local old = phase == "Senior" or phase == "Extra"
  local low = util.contains(events.LOW, mood)

  local hide_w = 0.0
  if can_hide then
    hide_w = (util.contains(s.quirks, "Huidiza") and 0.3 or 0.1)
      + (s.stress >= 70.0 and 0.3 or 0.0) + (phase == "Juvenil" and 0.2 or 0.0)
  end
  local play_w = 0.0
  if not (e < 40) then
    play_w = (0.2 + 0.6 * active) * ((old or evening) and 0.5 or 1.0)
  end
  local options = {
    {"se_esconde", hide_w},
    {"aparece", (0.5 + social) * (phase == "Cachorro" and 1.5 or 1.0) * (low and 0.5 or 1.0)},
    {"otra_sala", 0.3 + 0.4 * (1.0 - social)},
    {"juega_sola", play_w},
    {"investiga", (0.1 + 0.6 * curious) * (evening and 0.6 or 1.0)},
    {"trae_algo", 0.05 + 0.25 * curious},
    {"pillada", phase == "Juvenil" and 0.4 or 0.1}, -- as if it was not her
    {"tarda", (0.1 + 0.4 * (1.0 - social)) * ((e < 30 or old or low) and 1.5 or 1.0)},
  }
  local total = 0
  for _, o in ipairs(options) do total = total + o[2] end
  local r = math.random() * total
  for _, o in ipairs(options) do
    r = r - o[2]
    if r < 0 then
      return o[1]
    end
  end
  return options[#options][1]
end

function M.search(s, now_ms)
  if s.powered_off or s.deep_sleep then
    s:wake_by_button(now_ms, "A+C")
    return
  end

  if s.mode ~= "main" then
    return
  end

  if s.sleeping then
    s.overlay_text = "Shhh... ¡que duerme!"
    s.overlay_until = now_ms + 900
    s:_log_event("Buscar: dormida")
    s:mark_dirty()
    return
  end

  if util.int(s.sitter_until) ~= 0 then -- away with Sancho: nobody to look for
    return
  end
  if s.hidden then
    -- the owner's game: A+C looks in the room on screen; not here, on to the next room
    if not M.search_here(s, now_ms) then
      M.look(s, 1)
      s:_log_event("Busca en " .. tostring(s.scenarios[s.current_scene + 1]))
    end
    return
  end
  s:_emit_sound("buscar")
  local answer = M.reply(s, M.may_hide(s, now_ms))
  if answer == "se_esconde" then
    M.hide(s, now_ms)
    s._hide_cd_until_ms = now_ms + 12000 -- she disappears: no text needed
    s:_log_event("Se esconde")
  elseif answer == "otra_sala" then -- she was elsewhere: the room she is in
    s.current_scene = (s.current_scene + 1) % #s.scenarios
    s.overlay_text = tostring(s.scenarios[s.current_scene + 1])
    s.overlay_until = now_ms + 900
    s:_log_event("Va a " .. tostring(s.scenarios[s.current_scene + 1]))
  else
    if answer == "trae_algo" then
      memory.remember(s, "found") -- what she brings makes her curious
    end
    local late = M.REPLY_MS
    if answer == "tarda" then late = M.REPLY_LATE_MS end
    events.later(s, now_ms + late, answer) -- she comes (aparece), or late (tarda)...
    s:_log_event("Buscar: " .. answer)
  end
  s:mark_dirty()
end

return M
