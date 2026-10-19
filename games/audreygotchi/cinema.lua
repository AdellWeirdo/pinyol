-- cinema: the scenes the core times and the board drew by time (platforms/esp32s3/screens.py, grow_screen.py,
-- animation.py): her birth, her growing up, Sancho meeting her and taking her for the day, and the farewell with its
-- credits and her memories. The sky and the farewell are drawn whole, the board's scene in a 320x320 frame in the
-- middle of the screen (art.py's C_ pictures and cinema-scale sets); the rest in the room as the game shows it.
local ui = require("ui")
local hud = require("hud")
local anim = require("anim")
local actor = require("actor")
local strings = require("strings")
local T = ui.T
local S = strings.T
local M = {}

-- ------------------------------------------------------------------ the frame

local function cx(x) return 80 + x * 4 // 3 end         -- a board scene point in the cinema frame
local function cy(y) return (y + 20) * 4 // 3 end
local FLOOR = cy(214)                                    -- her floor in the cinema's room

local function cine_bg(name)
  cls(T[4])
  local id = "C_" .. name:gsub("^bg_", ""):upper()
  if imgsize(id) then img(id, 80, 0, {scale = 2}) end
end

local function set_frame(name, frame)
  local id = "A_" .. name:upper()
  local w, h, n = imgsize(id)
  if not w then return nil end
  return id, w, h, math.max(0, math.min(frame, n - 1))
end

local ANCHOR = { -- the farewell's sets: their anchor in the board's screen pixels
  rocket_star_appear = {24, 25}, rocket_star_descend = {24, 64}, rocket_star_descend_near = {48, 126},
  audrey_star_remains = {24, 25}, rocket_star_reveal = {80, 60}, rocket_hover_window = {80, 132},
  rocket_window_audrey = {80, 132}, rocket_door_open = {80, 132}, rocket_takeoff = {90, 145},
  audrey_board_rocket = {112, 140}, audrey_star_fall = {44, 36},
}

local function put(name, frame, px, py) -- a set's frame with its anchor on board scene point (px, py)
  local id, w, h, f = set_frame(name, frame)
  if not id then return end
  local a = ANCHOR[name] or {w * 3 // 4, h * 3 // 4}
  img(id, cx(px) - a[1] * 4 // 3, cy(py) - a[2] * 4 // 3, {frame = f, scale = 2})
end

local function her(name, frame, x, dy) -- one of her sets on the cinema room's floor, centred on board x
  local id, w, h, f = set_frame(name, frame)
  if not id then id, w, h, f = set_frame("cachorro", 0) end
  if not id then return end
  img(id, cx(x) - w, FLOOR - h * 2 + (dy or 0), {frame = f, scale = 2})
end

local TWINKLE = {{12, 26, 0}, {54, 8, 5}, {96, 18, 2}, {118, 46, 7}, {148, 22, 4}, {28, 50, 3}, {88, 64, 6},
                 {204, 70, 1}, {150, 100, 5}, {104, 134, 3}, {218, 104, 0}, {186, 132, 6}, {70, 46, 2}}

local function twinkles(now, shown)
  for i, st in ipairs(TWINKLE) do
    if not shown or shown(i - 1) then
      local k = (now // 110 + st[3] * 3) % 10
      local x, y = cx(st[1]), cy(st[2] - 20)
      if k == 9 then rect(x - 4, y - 1, 10, 2, T[1]) rect(x, y - 5, 2, 10, T[1])
      elseif k > 0 then rect(x, y, 2, 2, k >= 7 and T[1] or T[2]) end
    end
  end
end

local function panel(top, h) ui.box(16, top, 448, h) end

-- ------------------------------------------------------------------ her birth

local STAR_AT = {120, 70}

function M.birth(snap, now)
  local step = snap.birth_step or "negro"
  local t, length = snap.birth_t or 0, math.max(1, snap.birth_len or 1)
  if step == "negro" then cls(0x000000) return end
  local dark = snap.dark
  local shots = dark and "nace_" or "nace_dia_"
  if step == "cielo" or step == "estrella" or step == "fugaz" then
    cine_bg("bg_" .. shots .. "0")
    if dark then twinkles(now, step == "cielo" and function(i) return t >= 300 + i * 180 end or nil) end
    if step == "estrella" then
      put("audrey_star_remains", 1 + math.min(3, t * 4 // length), STAR_AT[1], STAR_AT[2])
    elseif step == "fugaz" then
      local p = t * 100 // length
      local e = p * p // 100
      put("audrey_star_fall", (t // 110) % 5, STAR_AT[1] + 140 * e // 100, STAR_AT[2] + 180 * e // 100)
    end
    return
  end
  -- the camera pulls back over the room's drawing, easing in and out, then the room itself
  local p = t * 100 // length
  local k = step == "zoom" and p * p * (300 - 2 * p) // 10000 or 100
  local shot = k * 17 // 101
  if shot < 16 then cine_bg("bg_" .. shots .. shot) else cine_bg(dark and "bg_living_noche" or "bg_living") end
  if step == "zoom" or step == "espera" then return end
  local mid = 120
  if step == "cae" then -- falling into the room, then down
    local fall = length * 7 // 10
    if t < fall then
      local kk = t * 100 // fall
      her("nace_cae", (t // 90) % 3, mid, -(FLOOR) * (100 - kk * kk // 100) // 100)
    else
      her("nace_cae", t < (fall + length) // 2 and 3 or 4, mid)
    end
  elseif step == "silencio" then her("nace_rebota", 4, mid)
  elseif step == "mira" then
    local blink = length * 2 // 5
    if t < blink then her("nace_parpadea", t * 5 // blink, mid)
    else her("nace_mira", (t - blink) * 5 // (length - blink), mid) end
  elseif step == "idle" or step == "logo" then
    her("cachorro", 0, mid)
    if step == "logo" then -- the logo pops over her
      local w, h = imgsize("TITLE_LOGO")
      local s = math.min(2, 1 + t * 2 / length)
      img("TITLE_LOGO", 240 - math.floor(w * s / 2), 40, {scale = s})
    end
  else
    her("nace_" .. step, t * 5 // length, mid)
  end
end

-- ------------------------------------------------------------------ her growing up

local GROW = {glow = 1600, flash = 5000, reveal = 5600, fade_in = 900, burst = {150, 300}, flash_lit = 80}

local function stage_set(name) return name == "Cachorro" and "cachorro" or "idle" end

local function silhouette(name, x, bottom, light) -- her shape in light, its outline dark
  local id, w, h = set_frame(name, 0)
  if not id then return end
  local left, top = x - w, bottom - h * 2
  for _, d in ipairs({{-2, 0}, {2, 0}, {0, -2}, {0, 2}}) do
    img(id, left + d[1], top + d[2], {scale = 2, tint = T[4]})
  end
  img(id, left, top, {scale = 2, tint = light and T[1] or T[2]})
end

function M.grow(snap, now, room)
  local t = snap.grow_t or 0
  local grow = require("core.scene_grow")
  local x, floor = 240, hud.FLOOR
  local mid = floor - 92
  room.background(snap)
  local old, new = stage_set(snap.grow_from), stage_set(snap.grow_to)
  if t < GROW.reveal and anim.has("crece_aura") then
    local id, w, h, f = set_frame("crece_aura", (t // 160) % 5)
    img(id, x - w, floor - h * 2 + 24, {frame = f, scale = 2})
  end
  if t >= GROW.reveal then -- her new self, celebrating
    local k = (t - GROW.reveal) // 220
    local name = k < 5 and "celebra" or "presume"
    if k >= 5 then k = k - 5 end
    if not anim.has(name) then name, k = new, 0 end
    local id, w, h, f = set_frame(name, k)
    if id then img(id, x - w, floor - h * 2, {frame = f, scale = 2}) end
  elseif t >= GROW.flash then silhouette(new, x, floor, true)
  elseif t >= GROW.glow then
    local switches = 0
    for _, at in ipairs(grow.flicker_times()) do if at <= t then switches = switches + 1 end end
    silhouette(switches % 2 == 1 and new or old, x, floor, true)
  elseif t >= GROW.fade_in + (GROW.glow - GROW.fade_in) // 2 or (t >= GROW.fade_in and (t // 70) % 2 == 1) then
    silhouette(old, x, floor, true)
  else
    local id, w, h = set_frame(old, 0)
    if id then img(id, x - w, floor - h * 2, {scale = 2}) end
  end
  if t < GROW.reveal then -- sparkles spiralling in, circling, flung out
    local r, spin
    if t < GROW.glow then local p = t / GROW.glow r, spin = 236 - 108 * p * p, 1.6 * p
    elseif t < GROW.flash then local u = (t - GROW.glow) / 1000 r, spin = 128 + 12 * math.sin(u * 9), 1.6 + 1.2 * u + 0.9 * u * u
    else local u = (t - GROW.flash) / (GROW.reveal - GROW.flash) r, spin = 128 + 180 * u, 7.0 + 2 * u end
    for i = 0, 9 do
      local a = i * 2 * math.pi / 10 + spin
      local sx, sy = x + math.floor(r * math.cos(a)), mid + math.floor(r * 0.62 * math.sin(a))
      if sy > hud.TOP_H and sy < floor and (t // 90 + i) % 3 ~= 0 then actor.icon("IC_FX_SPARKLE", sx, sy) end
    end
  end
  if t >= GROW.flash and t < GROW.reveal + 500 then -- the burst of light
    local dt = t - GROW.flash
    if dt >= GROW.burst[2] and dt < GROW.burst[2] + GROW.flash_lit then rect(0, 0, 480, 320, T[1]) end
    local i = t < GROW.reveal and (dt < GROW.burst[1] and 0 or dt < GROW.burst[2] and 1 or 2)
              or math.min(4, 3 + (t - GROW.reveal) // 250)
    local id, w, h, f = set_frame("crece_destello", i)
    if id then img(id, x - w, mid - h, {frame = f, scale = 2}) end
  end
  if t >= GROW.reveal + 300 then
    local lines = {S.grow_title:format(snap.name or "Audrey"), S.grow_stage[snap.grow_to or ""] or ""}
    ui.box(16, hud.CONTENT_Y, 448, 68)
    ui.text(lines[1], 240, hud.CONTENT_Y + 14, T[4], "center")
    ui.text(lines[2], 240, hud.CONTENT_Y + 40, T[3], "center")
  end
end

-- ------------------------------------------------------------------ Sancho

local intro = {step = nil, at = 0}

function M.sancho_intro(snap, tick, room, hud_menu)
  local step = snap.intro_step or "llega"
  if step ~= intro.step then intro.step, intro.at = step, tick end
  local t = tick - intro.at
  room.background(snap)
  local floor, her_x, his_x = hud.FLOOR, 240 - 110, 240 + 124
  local hers, his = {"idle", 0}, {"sancho_anda_izq", 0}
  if step == "llega" then
    local walk = 480 + 140 - t * 32 -- in from the right, to beside her
    if walk > his_x then his_x, his = walk, {"sancho_anda_izq", t}
    else hers = {"happy_wiggle", t} end
  elseif step == "saluda" then
    hers, his = {"enamorada", math.min(t // 2, 4)}, {"sancho_saluda", t // 2}
    for _, d in ipairs({{-42, 46}, {44, 38}, {6, 26}}) do actor.icon("IC_FX_HEART", her_x + d[1] * actor.K, floor - 180 + d[2] * actor.K) end
  elseif step == "explica" then his = {"sancho_te_mira", t // 3} end
  if anim.puppy(snap) then hers[1] = anim.puppy_once(hers[1]) or "cachorro" end
  for _, part in ipairs({{hers, her_x}, {his, his_x}}) do
    local name, frame = part[1][1], part[1][2]
    if not anim.has(name) then name, frame = "sancho_anda_izq", 0 end
    local id, w, h, f = set_frame(name, frame % (select(3, imgsize("A_" .. name:upper())) or 1))
    if id then img(id, part[2] - w, floor - h * 2, {frame = f, scale = 2}) end
  end
  local lines = (step == "explica" or step == "menu") and S["intro_" .. step] or nil
  if lines then
    ui.box(16, hud.CONTENT_Y, 448, 24 * #lines + 20)
    for i, l in ipairs(lines) do ui.text(l, 240, hud.CONTENT_Y + 12 + (i - 1) * 24, T[4], "center") end
  end
  hud_menu(step)
end

-- his visit: he walks across and she follows him out; back, both walk in and he walks on (animation._SANCHO_CUTS):
-- segments of {ticks, her part, her dx from, to, his part, his dx from, to}; a part is a set or {set, frames}
local CUTS = {
  sancho = {{9, "idle", 0, 0, "sancho_anda_izq", 210, 34},
            {4, {"vuelta", {0, 0, 1, 1}}, 0, 0, "sancho_anda_izq", 12, -54},
            {12, "anda_izq", 0, -242, "sancho_anda_izq", -76, -318}},
  vuelve = {{12, "anda_altiva", -242, 0, "sancho_anda", -150, 92},
            {7, "idle", 0, 0, "sancho_anda", 114, 246}},
}
local PUPPY_CUT = {idle = "cachorro", vuelta = "cachorro_pata", anda_izq = "cachorro_anda_izq", anda_altiva = "cachorro_anda"}
local cut = nil

function M.start_cut(name, tick) if CUTS[name] then cut = {name = name, at = tick} end end

function M.draw_cut(snap, tick, mid, floor) -- true while his visit plays
  if not cut then return false end
  local t = tick - cut.at
  local small = anim.puppy(snap)
  for _, seg in ipairs(CUTS[cut.name]) do
    local n = seg[1]
    if t < n then
      local u = n > 1 and t / (n - 1) or 1
      for _, p in ipairs({{seg[2], seg[3], seg[4], true}, {seg[5], seg[6], seg[7], false}}) do
        local part, picks = p[1], nil
        if type(part) == "table" then part, picks = part[1], part[2] end
        if small and p[4] then part = PUPPY_CUT[part] or part end
        local id, w, h, nf = "A_" .. part:upper(), imgsize("A_" .. part:upper())
        if w then
          local frame = picks and picks[math.min(t + 1, #picks)] or t % nf
          img(id, mid + math.floor((p[2] + (p[3] - p[2]) * u) * 2) - w, floor - h * 2, {frame = frame % nf, scale = 2})
        end
      end
      return true
    end
    t = t - n
  end
  cut = nil
  return false
end

-- ------------------------------------------------------------------ the farewell

local ROOM_STEPS = {habitacion = true, calma = true, nota = true, mira = true, entiende = true, despide = true, anda = true}
local BALCONY = {llega = true, presenta = true}
local NEAR = {puerta = true, sube = true, ventanita = true, prepara = true, despega = true}
local HER = {habitacion = "sleep", calma = "cansada", nota = "audrey_look_window", mira = "audrey_look_window",
             entiende = "audrey_tender_rocket", despide = "audrey_look_home"}
local STAR_SKY, STAR_MID, STAR_HOUSE = {150, 45}, {125, 110}, {95, 175}
local HOVER, NEAR_AT, BOARD_FOOT, BALCONY_OUT = {150, 178}, {120, 168}, {120, 220}, {118, 140}

local function credits(snap, t, length)
  local name = snap.name or "Audrey"
  local lines = S.farewell_credits
  local each = length // (#lines + 2)
  local top = 320 - (22 * #lines + 16) - 8
  panel(top, 22 * #lines + 16)
  for i, l in ipairs(lines) do
    if l ~= "" and t >= (i - 1) * each then ui.text(l:format(name), 240, top + 10 + (i - 1) * 22, T[4], "center") end
  end
end

local function thanks(snap)
  local name = snap.name or "Audrey"
  panel(180, 104)
  for i, l in ipairs(S.farewell_thanks) do
    text(l:format(name), 240, 192 + (i - 1) * 30, {font = "gb", color = T[4], align = "center", scale = 1})
  end
end

local function authors(t, length)
  local cards = S.farewell_authors
  local last = #cards
  local each = math.max(1, (length * 7 // 10) // (last - 1))
  local i = math.min(last, t // each + 1)
  local role, name = cards[i][1], cards[i][2]
  local rows = {}
  for r in (role .. "\n"):gmatch("(.-)\n") do rows[#rows + 1] = r end
  panel(176, 120)
  local y = 196 + 12 * (2 - #rows)
  for j, r in ipairs(rows) do ui.text(r, 240, y + (j - 1) * 22, i == last and T[4] or T[3], "center") end
  ui.text(name, 240, y + #rows * 22 + 12, T[4], "center")
end

local function dawn() -- a new day, in bands as a Game Boy drew a sky: dark above, light at the horizon, the sun
  local bands = {{0, 4}, {40, 3}, {90, 2}, {150, 1}}
  for i, b in ipairs(bands) do
    local y1 = bands[i + 1] and bands[i + 1][1] or 320
    rect(0, b[1], 480, y1 - b[1], T[b[2]])
    if i > 1 then -- a dithered edge between two bands
      for x = 0, 478, 4 do rect(x + (x // 4 % 2) * 2, b[1] - 2, 2, 2, T[b[2]]) end
    end
  end
  circ(240, 330, 70, T[1]) circ(240, 330, 72, T[2], false)
  for k = 0, 2 do rect(0, 250 + k * 20, 480, 2, T[2]) end
end

local function memories(snap)
  dawn()
  local screens = require("screens")
  local lines = {S.memories_days:format(snap.age_days or 0)}
  for _, l in ipairs(screens.who_she_is(snap)) do lines[#lines + 1] = l end
  local legacy = snap.legacy or {}
  local item = legacy[#legacy]
  if item and S.legacy_items[item] then lines[#lines + 1] = S.memories_left:format(S.legacy_items[item]) end
  local rows = {}
  for _, l in ipairs(lines) do for _, r in ipairs(ui.wrap(l, 26)) do if #rows < 10 then rows[#rows + 1] = r end end end
  ui.box(16, 16, 448, 72 + #rows * 22)
  ui.text(snap.name or "Audrey", 240, 30, T[4], "center")
  for i, r in ipairs(rows) do ui.text(r, 32, 60 + (i - 1) * 22, T[4]) end
  ui.text("B: volver", 240, 64 + #rows * 22, T[3], "center")
end

local function logo(snap, t)
  dawn()
  local w, h = imgsize("TITLE_LOGO")
  local s = snap.farewell_step == "silencio" and 2 or math.min(2, 0.5 + t / 800)
  img("TITLE_LOGO", 240 - math.floor(w * s / 2), 60, {scale = s})
  if snap.farewell_done then
    local labels = {S.new_life_button, S.memories_button}
    local picked = snap.farewell_choice == "recuerdos" and 2 or 1
    for i, l in ipairs(labels) do
      local y = 188 + (i - 1) * 52
      if i == picked then rect(132, y - 4, 216, 44, T[4]) end
      ui.box(136, y, 208, 36)
      if i == picked then ui.cursor(150, y + 10) end
      ui.text(l, 250, y + 10, T[4], "center")
    end
  end
end

function M.farewell(snap, now)
  if snap.farewell_memories then memories(snap) return end
  local step = snap.farewell_step or "habitacion"
  local t, length = snap.farewell_t or 0, math.max(1, snap.farewell_len or 1)
  if step == "logo" or step == "silencio" then logo(snap, t) return end
  local p = math.min(100, t * 100 // length)
  local play = math.min(4, t * 5 // length)
  local loop = now // 140
  local ease = p * p * (300 - 2 * p) // 10000
  local mid = 120
  if step == "ventana" then -- the camera into the window and up: the birth's zoom backwards
    local zoom = {"bg_living_noche"}
    for i = 15, 1, -1 do zoom[#zoom + 1] = "bg_nace_" .. i end
    zoom[#zoom + 1] = "bg_nace_0"
    cine_bg(zoom[math.min(#zoom, ease * #zoom // 101 + 1)])
  elseif ROOM_STEPS[step] then
    cine_bg("bg_living_noche")
    if step == "anda" then her("anda_despedida", now // 250, mid + p * 2)
    elseif step == "mira" then her(HER[step], (p >= 40 and p < 60) and 4 or 3, mid)
    else her(HER[step], play, mid) end
  elseif BALCONY[step] then
    cine_bg("bg_balcony_open")
    if step == "llega" then
      local e = 100 - (100 - p) ^ 2 // 100
      put("rocket_hover_window", loop, 330 - (330 - HOVER[1]) * e // 100, HOVER[2])
    else
      put("rocket_hover_window", loop, HOVER[1], HOVER[2])
    end
    local id = set_frame("bg_balcony_front", 0) -- the wall and the railing in front of it
    if id then img(id, 80, cy(0), {scale = 2}) end
  elseif NEAR[step] then
    cine_bg("bg_nace_0")
    twinkles(now)
    if step == "puerta" then put("rocket_door_open", play, NEAR_AT[1], NEAR_AT[2])
    elseif step == "sube" then put("audrey_board_rocket", play, BOARD_FOOT[1], BOARD_FOOT[2])
    elseif step == "ventanita" then put("rocket_window_audrey", play, NEAR_AT[1], NEAR_AT[2])
    elseif step == "prepara" then put("rocket_takeoff", (now // 200) % 2, NEAR_AT[1] + (now // 60) % 3 - 1, NEAR_AT[2])
    else
      local e = p * p // 100
      put("rocket_takeoff", 2 + math.min(2, t * 3 // length), NEAR_AT[1] + 70 * e // 100, NEAR_AT[2] - 260 * e // 100)
    end
  elseif step == "aleja" then
    cine_bg("bg_casa_noche")
    local e = p * p // 100
    put("audrey_star_remains", 0, BALCONY_OUT[1] + 80 * e // 100, BALCONY_OUT[2] - 160 * e // 100)
  else
    cine_bg("bg_nace_0")
    twinkles(now)
    if step == "estrella" then
      put("rocket_star_appear", p < 60 and math.min(4, t * 8 // length) or 3 + (now // 250) % 2, STAR_SKY[1], STAR_SKY[2])
    elseif step == "pulsa" then put("rocket_star_appear", 3 + (now // 110) % 2, STAR_SKY[1], STAR_SKY[2])
    elseif step == "baja" or step == "cerca" then
      local a, b = step == "baja" and STAR_SKY or STAR_MID, step == "baja" and STAR_MID or STAR_HOUSE
      local e = p * p // 100
      put(step == "baja" and "rocket_star_descend" or "rocket_star_descend_near", loop,
          a[1] + (b[1] - a[1]) * e // 100, a[2] + (b[2] - a[2]) * e // 100)
    elseif step == "revela" then put("rocket_star_reveal", play, 120, 110)
    elseif step == "asciende" then
      local e = 100 - (100 - p) ^ 2 // 100
      put("audrey_star_remains", 0, 150 - (150 - STAR_AT[1]) * e // 100, 230 - (230 - STAR_AT[2]) * e // 100)
    elseif step == "destello" then put("audrey_star_remains", 1 + math.min(1, t * 2 // length), STAR_AT[1], STAR_AT[2])
    else
      put("audrey_star_remains", 3 + (now // 700) % 2, STAR_AT[1], STAR_AT[2])
      if step == "creditos" then credits(snap, t, length)
      elseif step == "gracias" then thanks(snap)
      elseif step == "autores" then authors(t, length) end
    end
  end
  if snap.farewell_done then
    local picked = snap.farewell_choice == "recuerdos" and S.memories_button or S.new_life_button
    ui.text("< " .. picked .. " >", 240, 300, T[1], "center")
  end
end

return M
