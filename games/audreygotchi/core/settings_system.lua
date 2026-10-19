-- settings_system: Ajustes, the technical pages, QA and Modo Sistema (a port of
-- audreygotchi/core/settings_system.py).
local util = require("core.util")
local save_policy = require("core.save_policy")
local lifecycle = require("core.lifecycle")
local M = {}

-- Modo Sistema (v9 §13, D-11): opened by A+B+C held 3 s, which the platform detects
M.SYSTEM_OPTIONS = {"Diagnóstico", "Nueva vida", "Reset total", "Salir"}
M.SYSTEM_DESTRUCTIVE = {"Nueva vida", "Reset total"} -- these need B held 2 s

function M.enter_tech_mode(s, now_ms)
  s.mode = "tech"
  s.tech_page = 0
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Abre diagnóstico")
  s:mark_dirty()
end

function M.exit_tech_mode(s, now_ms)
  s.mode = "main"
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Cierra diagnóstico")
  s:mark_dirty()
end

function M.tech_page_left(s)
  local n = #s.TECH_PAGES
  if n <= 0 then return end
  s.tech_page = (util.int(s.tech_page) - 1) % n
  s:mark_dirty()
end

function M.tech_page_right(s)
  local n = #s.TECH_PAGES
  if n <= 0 then return end
  s.tech_page = (util.int(s.tech_page) + 1) % n
  s:mark_dirty()
end

function M.set_qa_mode(s, enabled, now_ms)
  s.qa_mode = not not enabled
  if s.qa_mode then
    s.overlay_text = string.format("QA ON x%d", util.int(s.QA_TICK_MULTIPLIER))
    s:_log_event("QA ON")
  else
    s.overlay_text = "QA OFF"
    s:_log_event("QA OFF")
  end
  s.overlay_until = now_ms + 900
  s:mark_dirty()
end

function M.toggle_qa_mode(s, now_ms)
  s:set_qa_mode(not s.qa_mode, now_ms)
end

function M.apply_balance_preset(s, preset, now_ms)
  local p = string.lower(tostring(preset or ""):match("^%s*(.-)%s*$"))
  if not util.contains({"ligera", "equilibrada", "robusta"}, p) then
    return false
  end
  s.qa_balance_preset = p
  local r = s:_ideal_weight_range()
  local lo, hi = r[1], r[2]
  local mid = (lo + hi) * 0.5
  if p == "ligera" then
    s.weight_kg = math.max(1.8, mid - 0.45)
    s.energy = math.min(100.0, s.energy + 6.0)
    s.stress = math.max(0.0, s.stress - 4.0)
  elseif p == "robusta" then
    s.weight_kg = math.min(9.5, mid + 0.55)
    s.energy = math.max(0.0, s.energy - 4.0)
    s.stress = math.min(100.0, s.stress + 3.0)
  else
    s.weight_kg = math.max(1.8, math.min(9.5, mid))
    s.energy = math.max(0.0, math.min(100.0, s.energy))
    s.stress = math.max(0.0, math.min(100.0, s.stress))
  end
  s.overlay_text = "Preset QA: " .. p
  s.overlay_until = now_ms + 900
  s:_log_event("Preset QA " .. p)
  s:mark_dirty()
  return true
end

function M.enter_system_mode(s, now_ms)
  -- not from the farewell, a game in progress or a switched-off pet (A+B+C does not wake her)
  if not util.contains({"main", "status", "settings", "tech"}, s.mode) or s.powered_off or s.deep_sleep then
    return
  end
  s.mode = "system"
  s.system_index = 0
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Abre modo sistema")
  s:mark_dirty()
end

function M.system_move(s, step)
  s.system_index = (util.int(s.system_index) + step) % #M.SYSTEM_OPTIONS
  s:mark_dirty()
end

local function say(s, now_ms, msg)
  s.overlay_text = msg
  s.overlay_until = now_ms + 1400
  s:mark_dirty()
end

local function fresh_start(s, now_ms, msg)
  s:_init_fresh() -- back to main, cycle 1, Audrey, default settings
  s._frame_ms = util.int(now_ms)
  save_policy.request_now(s)
  s:_log_event(msg)
  lifecycle.start_birth(s, now_ms) -- a new Audrey arrives: the owner's intro, no words
end

-- Nueva vida: this cycle again from a kitten, device settings kept. Never a way round a farewell already set
-- (v9 §13.4).
local function restart_cycle(s, now_ms)
  if s.farewell_started or util.int(s.farewell_scheduled_day) > 0 then
    say(s, now_ms, "La despedida no se salta")
    return
  end
  local keep = {s.cycle, s.name, s.name_preset_idx, s.brightness_level, s.sound_mode, s.language, s.ui_style,
                s.volume}
  fresh_start(s, now_ms, "Nueva vida")
  s.cycle, s.name, s.name_preset_idx, s.brightness_level, s.sound_mode, s.language, s.ui_style, s.volume =
    keep[1], keep[2], keep[3], keep[4], keep[5], keep[6], keep[7], keep[8]
end

-- B in Modo Sistema: a tap (held false) or B held 2 s (held true)
function M.system_choose(s, now_ms, held)
  local opt = M.SYSTEM_OPTIONS[util.int(s.system_index) % #M.SYSTEM_OPTIONS + 1]
  if util.contains(M.SYSTEM_DESTRUCTIVE, opt) and not held then
    say(s, now_ms, "Mantén B 2 s para confirmar")
    return
  end
  if opt == "Diagnóstico" then
    s:enter_tech_mode(now_ms)
  elseif opt == "Salir" then
    s.mode = "main"
    s:mark_dirty()
  elseif opt == "Nueva vida" then
    restart_cycle(s, now_ms)
  else
    fresh_start(s, now_ms, "Reset total")
  end
end

-- Ajustes > Sonido's steps, {sound_mode, volume}: on at medio, alto, bajo; noche; no
M.SOUND_STEPS = {{0, 1}, {0, 2}, {0, 0}, {2, 1}, {1, 1}}

function M.sound_name(s)
  if util.int(s.sound_mode) == 1 then return "no" end
  if util.int(s.sound_mode) == 2 then return "noche" end
  return ({"bajo", "medio", "alto"})[math.max(0, math.min(2, util.int(s.volume))) + 1]
end

function M.settings_options(s)
  -- v9 §3.3: renaming opens up from cycle 2; Salir last, one A press from where Ajustes opens (the owner,
  -- 2026-10-09: stuck in Ajustes, B held being the only way out)
  -- pinyol: no "Brillo", "Estilo", "Pantalla" nor "WiFi" (the console has no backlight to dim, no board themes,
  -- no screen-off timer, no WiFi); brightness_level, ui_style, screen_off_idx and wifi_seq stay in the state
  local opts = {"Sonido", "Micro", "Amigos", "Idioma"}
  if s:can_edit_name() then opts[#opts + 1] = "Nombre" end
  opts[#opts + 1] = "Guía" -- its buttons' guide again
  opts[#opts + 1] = "Salir"
  return opts
end

function M.enter_settings(s, now_ms)
  s.mode = "settings"
  s.settings_index = 0
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Abre ajustes")
  s:mark_dirty()
end

function M.exit_settings(s, now_ms)
  s.mode = "main"
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Cierra ajustes")
  s:mark_dirty()
end

function M.settings_left(s)
  local opts = s:_settings_options()
  s.settings_index = (util.int(s.settings_index) - 1) % math.max(1, #opts)
  s:mark_dirty()
end

function M.settings_right(s)
  local opts = s:_settings_options()
  s.settings_index = (util.int(s.settings_index) + 1) % math.max(1, #opts)
  s:mark_dirty()
end

local function sound_step_index(s) -- SOUND_STEPS.index((sound_mode, volume)), 0-based; 0 when not there
  local sm, vol = util.int(s.sound_mode), util.int(s.volume)
  for i, st in ipairs(M.SOUND_STEPS) do
    if st[1] == sm and st[2] == vol then return i - 1 end
  end
  return 0
end

function M.settings_confirm(s, now_ms)
  local opts = s:_settings_options()
  local opt = opts[util.int(s.settings_index) % #opts + 1]
  if opt == "Salir" then
    M.exit_settings(s, now_ms)
    return
  end
  if opt == "Guía" then -- the buttons' guide, shown again
    s.mode = "guide"
    s:mark_dirty()
    return
  end
  -- pinyol: "Brillo" (brightness_level), "Estilo" (ui_style) and "Pantalla" (screen_off_idx) are not offered
  if opt == "Sonido" then -- its volume and when it sounds, one option: medio, alto, bajo, noche, no
    local at = sound_step_index(s)
    local st = M.SOUND_STEPS[(at + 1) % #M.SOUND_STEPS + 1]
    s.sound_mode, s.volume = st[1], st[2]
    s.overlay_text = "Sonido " .. M.sound_name(s)
    s.overlay_until = now_ms + 900
    s:mark_dirty()
    return
  end
  if opt == "Micro" then -- she hears (loudness only, never recorded), or not
    s.mic_on = not s.mic_on
    s.overlay_text = "Micro " .. (s.mic_on and "ON" or "OFF")
    s.overlay_until = now_ms + 900
    s:mark_dirty()
    return
  end
  if opt == "Amigos" then -- the radio finds other Audreygotchis nearby, or not
    s.friends_on = not s.friends_on
    s.overlay_text = "Amigos " .. (s.friends_on and "ON" or "OFF")
    s.overlay_until = now_ms + 900
    s:mark_dirty()
    return
  end
  -- pinyol: "WiFi" (wifi_seq) is not offered
  if opt == "Idioma" then
    s.language = (s.language == "es") and "en" or "es"
    s.overlay_text = "Idioma " .. string.upper(s.language)
    s.overlay_until = now_ms + 900
    s:mark_dirty()
    return
  end
  if opt == "Nombre" then
    s:cycle_name_preset()
    s:_log_event("Renombra: " .. tostring(s.name))
  end
end

return M
