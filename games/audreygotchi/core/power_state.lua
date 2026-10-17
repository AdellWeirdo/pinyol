-- power_state: the light, sleep, deep sleep and waking by a button (a port of audreygotchi/core/power_state.py).
local M = {}

function M.act_light(s, now_ms)
  if s.powered_off then
    s:wake_by_button(now_ms, "Luz")
    return
  end

  s.light_on = not s.light_on

  if not s.light_on then
    s.overlay_text = "¡A oscuras!"
    s:_log_event("Apaga luz")
    s:enter_sleep(now_ms, "light_off", false)
  else
    s.overlay_text = "¡Hágase la luz!"
    if s.deep_sleep then
      s.deep_sleep = false
    end
    s.sleeping = false
    s:_log_event("Enciende luz")
  end
  s.overlay_until = now_ms + 900
  s:_register_interaction("Luz", true)
end

function M.can_wake_now(s)
  return (s.clock:now() - s._last_wake_ts) >= s.WAKE_MIN_INTERVAL_SEC
end

function M.enter_sleep(s, now_ms, reason, show_overlay)
  if reason == nil then reason = "manual" end
  if show_overlay == nil then show_overlay = true end
  if s.powered_off then
    return false
  end
  s.deep_sleep = false
  s.sleeping = true
  s.light_on = false
  s._awake_sec = 0 -- waking her later starts the grace from zero
  s._nap_sec = 0
  if s.mode ~= "farewell" then
    s.mode = "main" -- she falls asleep: the screen goes back to her
  end
  if show_overlay then
    s.overlay_text = "A soñar con atún"
    s.overlay_until = now_ms + 900
  end
  s:_log_event("Sleep " .. tostring(reason))
  s:compute_mood()
  s:mark_dirty()
  return true
end

function M.request_deep_sleep(s, now_ms, source)
  if source == nil then source = "auto" end
  if s.powered_off or s.deep_sleep then
    return false
  end
  s.deep_sleep = true
  s.sleeping = false
  s.light_on = false
  s.mode = "main"
  s.overlay_text = "Sueño profundo..."
  s.overlay_until = now_ms + 900
  s:_log_event("Entra sleep profundo (" .. tostring(source) .. ")")
  s:compute_mood()
  s:mark_dirty()
  return true
end

-- Waking by a button. First: OFF -> ON; then DEEP_SLEEP -> awake.
function M.wake_by_button(s, now_ms, source)
  if source == nil then source = "botón" end
  if not s:_can_wake_now() then
    return false
  end

  if s.powered_off then
    s.powered_off = false
    s.deep_sleep = false
    s.sleeping = false
    s.light_on = true
    s.mode = "main"
    s.energy = math.max(4.0, s.energy)
    s._last_wake_ts = s.clock:now()
    s.overlay_text = "Arrancando motores..."
    s.overlay_until = now_ms + 900
    s:_log_event("Wake (" .. tostring(source) .. ")")
    s:compute_mood()
    s:mark_dirty()
    return true
  end

  if s.deep_sleep then
    s.deep_sleep = false
    s.sleeping = false
    s.light_on = true
    s.mode = "main"
    s._last_wake_ts = s.clock:now()
    s.overlay_text = "Bostezo y voy..."
    s.overlay_until = now_ms + 900
    s:_log_event("Wake (" .. tostring(source) .. ")")
    s:compute_mood()
    s:mark_dirty()
    return true
  end

  return false
end

return M
