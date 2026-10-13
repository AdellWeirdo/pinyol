-- CONTROL: the evening news of 1994, directed from the control room. The producer calls each step in your headset
-- (story/ca.txt, story/es.txt); you cut the cameras, roll the tape and put the captions on, on the beat of the
-- newscast's theme (music_time). The console's LED is the studio's tally light. Then a camera that does not exist
-- comes on, and it is looking at you: it hears you (mic), knows your battery (battery), and its picture is the
-- screen in your hands, which shows the control room, which shows... (canvases, video, story, mic, led, battery)
-- Left and right: pick a source. A: cut it to the programme. B: roll the tape. C: caption on or off.
local story = require("story")

local FONT, TITLE = "vt", "title"
local SRC = { -- the sources on the wall: their pictures small (their monitor) and big (the programme monitor)
  {name = "CAM 1", small = "CAM1_S", big = "CAM1_B"},
  {name = "CAM 2", small = "CAM2_S", big = "CAM2_B"},
  {name = "CAM 3", small = "CAM3_S", big = "CAM3_B"},
  {name = "VTR", small = "VTR", big = "VTR"},
}
local CAM00 = 5
local CUES = { -- the running order: when (seconds into the theme, which loops every 16), what, and its lines
  {t = 4, act = "cut", src = 1, k = "c1"},
  {t = 8, act = "cap", on = true, k = "c2", text = "anchor"},
  {t = 12, act = "cap", on = false, k = "c3"},
  {t = 16, act = "vtr", k = "c4"},
  {t = 28, act = "cut", src = 2, k = "c5"},
  {t = 32, act = "cut", src = 1, k = "c6"},
  {t = 36, act = "cut", src = 3, k = "c7"},
  {t = 44, act = "cut", src = 1, k = "c8"},
  {t = 48, act = "cap", on = true, k = "c9", text = "late"},
}
local WARN, EARLY, LATE = 2.5, 1.0, 1.5 -- seconds: the producer warns before; an action counts this early or late
local TWIST_AT = 53
local WORDS = {
  ca = {sub = "ESTUDI 2 · INFORMATIU DEL VESPRE · 1994", start = "START per entrar al control", lang = "< CATALÀ >",
        keys = "<  > tria   A talla   B vídeo   C rètol", air = "EN L'AIRE", rehearsal = "ASSAIG",
        order = "ESCALETA", nosignal = "SENSE SENYAL", anchor = "MARTA VILA", late = "ÚLTIMA HORA",
        grade = {P = "PERFECTE", B = "BÉ", J = "JUST", X = "TARD", E = "MASSA AVIAT"}, speak = "PARLA...",
        press = "Prem A", heard = "T'HEM SENTIT", over = "FI DE L'EMISSIÓ", again = "START per tornar a començar",
        score = "Punts", items = {"CAM 1", "Rètol", "Fora rètol", "VTR", "CAM 2", "CAM 1", "CAM 3", "CAM 1", "Rètol"}},
  es = {sub = "ESTUDIO 2 · INFORMATIVO DE LA NOCHE · 1994", start = "START para entrar en el control",
        lang = "< CASTELLANO >", keys = "<  > elige   A corta   B vídeo   C rótulo", air = "EN EL AIRE",
        rehearsal = "ENSAYO", order = "ESCALETA", nosignal = "SIN SEÑAL", anchor = "MARTA VILA",
        late = "ÚLTIMA HORA", grade = {P = "PERFECTO", B = "BIEN", J = "JUSTO", X = "TARDE", E = "DEMASIADO PRONTO"},
        speak = "HABLA...", press = "Pulsa A", heard = "TE HEMOS OÍDO", over = "FIN DE LA EMISIÓN",
        again = "START para volver a empezar", score = "Puntos",
        items = {"CAM 1", "Rótulo", "Fuera rótulo", "VTR", "CAM 2", "CAM 1", "CAM 3", "CAM 1", "Rótulo"}},
}
local POINTS = {P = 3, B = 2, J = 1, X = 0, E = 0}
-- where things are on the screen
local MON_X, MON_Y, MON_W, MON_H = {11, 129, 247, 365}, 8, 104, 80 -- the four sources (a 96x72 picture each)
local PGM_X, PGM_Y = 170, 108                                       -- the programme monitor (128x96 inside)
local C00_X, C00_Y = 365, 116
local HAND = {x = 209.5, y = 189.5, w = 11.5, h = 8.5}               -- the console's screen in CAM00_Z (480x360)

LANG = stored("lang", "ca")
AUTO = false -- the tests' (and a demo's) perfect director
state, sel, pgm, caption, cap_text = "title", 1, 0, false, nil
grades, punts, cue, said = {}, 0, 1, nil
s, tv = nil, nil -- the producer's story and the tape (global: tests/control.script reads them)
local heard_ticks, listen_t, flash, flash_t, zoom_t, glitch = 0, 0, nil, 0, 0, 0
local W = WORDS[LANG]

function zoom() state, zoom_t = "zoom", 0 end -- (the story calls it: [do zoom()])

local function open_story()
  W = WORDS[LANG]
  s = story.new(file("story/" .. LANG .. ".txt"), {name = LANG .. ".txt",
    ui = {font = FONT, x = 16, y = 222, w = 448, h = 90, box = 0x0C1014, border = 0xC83C32, name_color = 0xFF7060,
          speed = 1.5}})
end

local function set_led()
  if state == "brief" then led(0x00FF00)                  -- standby: green
  elseif state == "air" or state == "zoom" then led(0xFF0000) -- on air: red
  elseif state == "twist" then led(ticks() % 30 < 15 and 0xFF0000 or 0xFFC000)
  else led() end                                          -- the console's own
end

local function start_air()
  state, sel, pgm, caption, cap_text, cue, grades, punts = "air", 1, 0, false, nil, 1, {}, 0
  said = nil
  tv:pause()
  tv:seek(0)
  tv.speed = 1
  music("MUS_NEWS")
end

local function grade(i, g)
  grades[i], punts = g, punts + POINTS[g]
  flash, flash_t = W.grade[g], 50
  sfx(g == "P" and "OK" or (g == "X" or g == "E") and "BAD" or "CLIC", 0.6)
end

-- What the player did, at time t: does it answer the cue waiting?
local function act(kind, arg, t)
  local c = CUES[cue]
  if not c then return end
  local ok = c.act == kind and (kind ~= "cut" or c.src == arg) and (kind ~= "cap" or c.on == arg)
  if not ok then return end
  local d = t - c.t
  if d < -EARLY then grade(cue, "E")
  else
    local a = math.abs(d)
    grade(cue, a <= 0.2 and "P" or a <= 0.5 and "B" or "J")
  end
  cue = cue + 1
end

local function cut(src, t)
  if pgm ~= src then sfx("CUT", 0.5) end
  pgm = src
  act("cut", src, t)
end

local function apply(c) -- what cue c does to the programme
  if c.act == "cut" then sel, pgm = c.src, c.src
  elseif c.act == "vtr" then sel, pgm = 4, 4; tv:seek(0); tv:play()
  else caption, cap_text = c.on, c.text end
end

local function do_cue(c, t) -- the cue done, and judged
  apply(c)
  if c.act == "cut" then sfx("CUT", 0.5) end
  act(c.act, c.act == "cut" and c.src or c.on, t)
end

local function update_air()
  local t = music_time() or 0
  -- the producer: a warning a little before each cue, the call on it
  local c = CUES[cue]
  if c then
    if t >= c.t - WARN and said ~= c.k .. "w" then s:go(c.k); said = c.k .. "w" end
    if t >= c.t and said == c.k .. "w" then s:next(); said = c.k .. "g" end
    if AUTO and t >= c.t then do_cue(c, t)
    elseif t > c.t + LATE then -- missed: she does it herself
      grade(cue, "X")
      apply(c)
      cue = cue + 1
    end
  end
  if not AUTO then
    if btnp("left") then sel = (sel - 2) % 4 + 1; sfx("CLIC", 0.3) end
    if btnp("right") then sel = sel % 4 + 1; sfx("CLIC", 0.3) end
    if btnp("a") then cut(sel, t) end
    if btnp("b") then tv:seek(0); tv:play(); sel = 4; cut(4, t); act("vtr", nil, t) end
    if btnp("c") then
      caption = not caption
      cap_text = caption and (cue == 9 and "late" or "anchor") or nil
      act("cap", caption, t)
    end
  end
  if t >= TWIST_AT then
    state, glitch = "twist", 0
    local level = battery()
    s.vars.bateria = level and math.floor(level * 100 + 0.5) or nil
    s.vars.punts = punts
    s:go("twist")
    tv.speed = -2
    tv:play()
    sfx("STATIC", 0.5)
  end
end

local function update_twist()
  glitch = glitch + 1
  if glitch == 90 then pgm = CAM00; sfx("STATIC", 0.4) end
  if s:running() then
    s:update()
    if AUTO and glitch % 120 == 0 then s:next() end
    if not s:running() then listen_t, heard_ticks = 0, 0; state = "listen"; mic_record("VEU", 3) end
    return
  end
end

local function update_listen()
  listen_t = listen_t + 1
  local level = mic()
  if level and level > 0.25 then heard_ticks = heard_ticks + 1 end
  local done = heard_ticks >= 20 or (AUTO and listen_t >= 60) or (not level and btnp("a"))
  if level == nil and listen_t > 60 * 8 then done = true end
  if done then
    mic_record()
    state = "twist2"
    if heard_ticks >= 20 then
      s:go("heard")
      sfx("VEU", 1, {pitch = 0.75}) -- your voice, from the control room
    else
      s:go("silent")
    end
  elseif level and listen_t > 60 * 10 then -- ten seconds of silence
    mic_record()
    state = "twist2"
    s:go("silent")
  end
end

local function update_zoom()
  zoom_t = zoom_t + 1
  if zoom_t >= 300 then
    state, caption = "end", false
    music()
    s.vars.punts = punts
    s:go("fi")
  end
end

function _init()
  show(0)
  sound("CLIC", "blip", 4)
  sound("CUT", {wave = "noise", sustain = 0.01, decay = 0.05, volume = 0.4, lowpass = 0.5})
  sound("STATIC", {wave = "noise", sustain = 0.5, decay = 0.4, volume = 0.35, highpass = 0.2})
  sound("OK", "coin", 6)
  sound("BAD", "hit", 2)
  canvas("SCREEN", 480, 320)
  tv = video("VTR", {play = false}) -- (its canvas, VTR, from the start: the monitors draw it)
  canvas("VTR_S", 96, 72)           -- the tape at its source monitor's size, made when a new frame comes
  open_story()
  set_led()
end

local shown = -1
local function small_tape() -- the clip's frame scaled down once, not every frame on every strip
  if tv:frame() == shown then return end
  shown = tv:frame()
  target("VTR_S")
  img("VTR", 0, 0, {scale = 0.75})
  target()
end

function _update()
  small_tape()
  if state == "title" then
    if btnp("left") or btnp("right") then
      LANG = LANG == "ca" and "es" or "ca"
      store("lang", LANG)
      open_story()
      sfx("CLIC", 0.4)
    end
    if btnp("start") or btnp("a") then state = "brief"; s:go("brief") end
  elseif state == "brief" then
    if btnp("start") then s.done = true else s:update() end
    if AUTO and ticks() % 45 == 0 then s:next() end
    if not s:running() then start_air() end
  elseif state == "air" then update_air()
  elseif state == "twist" then update_twist()
  elseif state == "listen" then update_listen()
  elseif state == "twist2" then
    s:update()
    if AUTO and ticks() % 120 == 0 then s:next() end
  elseif state == "zoom" then update_zoom()
  elseif state == "end" then
    s:update()
    if AUTO and ticks() % 120 == 0 then s:next() end
    if btnp("start") then state = "title"; open_story() end
  end
  if flash_t > 0 then flash_t = flash_t - 1 end
  set_led()
end

-- ------------------------------------------------------------------ drawing

local function noise_box(x, y, w, h)
  for _ = 1, 24 do
    local yy = y + math.random(0, h - 2)
    rect(x, yy, w, math.random(1, 2), math.random(0, 1) == 0 and 0xD0D0D0 or 0x303030)
  end
end

local function bezel(x, y, w, h, tally)
  rect(x, y, w, h, 0x1A1D22)
  box(x, y, w, h, tally == "red" and 0xE03020 or tally == "green" and 0x30C040 or 0x3A3F48)
  if tally then box(x + 1, y + 1, w - 2, h - 2, tally == "red" and 0xE03020 or 0x30C040) end
end

local function picture(src, big, x, y, w, h)
  if src == 0 then rect(x, y, w, h, 0x000000); return end
  if src == CAM00 then img(big and "CAM00_B" or "CAM00_S", x, y); return end
  local p = SRC[src]
  if src == 4 and not big then img("VTR_S", x, y)
  else img(big and p.big or p.small, x, y) end
end

local function draw_room(live) -- the control room: in play on the screen, at the end on SCREEN too
  img("BG_ROOM", 0, 0)
  for i = 1, 4 do
    local x = MON_X[i]
    local tally = pgm == i and "red" or (sel == i and state == "air") and "green" or nil
    bezel(x, MON_Y, MON_W, MON_H, tally)
    picture(i, false, x + 4, MON_Y + 4, 96, 72)
    if state == "twist" and glitch % 40 < 6 then noise_box(x + 4, MON_Y + 4, 96, 72) end
    plate(x + 20, MON_Y + MON_H + 2, 64, 15, 0x0C0E12)
    text(SRC[i].name, x + 52, MON_Y + MON_H + 1, {font = FONT, align = "center",
         color = pgm == i and 0xFF6050 or sel == i and 0x70F080 or 0xC8C8C8})
  end
  -- the programme monitor
  bezel(PGM_X, PGM_Y, 140, 108, pgm ~= 0 and "red" or nil)
  picture(pgm, true, PGM_X + 6, PGM_Y + 6, 128, 96)
  if caption and pgm ~= 0 then
    local late = cap_text == "late"
    rect(PGM_X + 10, PGM_Y + 78, 120, 14, late and 0xC01818 or 0x183C8C)
    text(late and W.late or W.anchor, PGM_X + 13, PGM_Y + 76, {font = FONT, color = 0xFFFFFF, width = 116})
  end
  plate(PGM_X + 4, PGM_Y - 2, 34, 13, 0xC01818)
  text("PGM", PGM_X + 8, PGM_Y - 4, {font = FONT, color = 0xFFFFFF})
  if flash_t > 0 and flash then
    text(flash, PGM_X + 70, PGM_Y + 40, {font = TITLE, align = "center", color = flash == W.grade.P and 0x70FF90 or
         0xFFE070, outline = 0x000000})
  end
  -- CAM 00: nothing, until it is something
  bezel(C00_X, C00_Y, MON_W, MON_H, pgm == CAM00 and "red" or nil)
  if state == "twist" or state == "listen" or state == "twist2" or state == "zoom" or state == "end" then
    img("CAM00_S", C00_X + 4, C00_Y + 4)
    if glitch % 50 < 4 then noise_box(C00_X + 4, C00_Y + 4, 96, 72) end
  else
    rect(C00_X + 4, C00_Y + 4, 96, 72, 0x08080A)
    text(W.nosignal, C00_X + 52, C00_Y + 30, {font = FONT, align = "center", color = 0x50555C})
  end
  plate(C00_X + 20, C00_Y + MON_H + 2, 64, 15, 0x0C0E12)
  text("CAM 00", C00_X + 52, C00_Y + MON_H + 1, {font = FONT, align = "center", color = 0x9098A0})
  -- the running order
  shade(8, 108, 150, 110)
  shade(8, 108, 150, 110)
  local t = music_time() or 0
  local on_air = state ~= "title" and state ~= "brief"
  text(on_air and W.air or W.rehearsal, 14, 108, {font = FONT, color = on_air and 0xFF5040 or 0x70F080})
  text(string.format("%02d:%02d", math.floor(t / 60), math.floor(t % 60)), 152, 108, {font = FONT, align = "right",
       color = 0xE8E8E8})
  local first = math.max(1, math.min(cue - 2, #CUES - 5))
  for i = first, math.min(#CUES, first + 5) do
    local y = 124 + (i - first) * 15
    local g = grades[i]
    local col = g and (POINTS[g] >= 2 and 0x70F080 or POINTS[g] == 1 and 0xFFE070 or 0xFF6050) or
                i == cue and 0xFFFFFF or 0x8A9098
    if i == cue and state == "air" then rect(10, y + 2, 146, 14, 0x2A3038) end
    text(string.format("%02d", CUES[i].t), 14, y, {font = FONT, color = 0x8A9098})
    text(W.items[i], 38, y, {font = FONT, color = col})
    if g then text(g, 150, y, {font = FONT, align = "right", color = col}) end
  end
  if live and (state == "air") then
    text(W.keys, 240, 300, {font = FONT, align = "center", color = 0xB0B4BA, shadow = 0x000000})
  end
end

local function draw_line() -- the producer's words during the programme: subtitles, not a box to press
  local l = s:line()
  if not l then return end
  shade(16, 226, 448, 40)
  shade(16, 226, 448, 40)
  text((l.who and (l.who .. ": ") or "") .. l.text, 24, 230, {font = FONT, color = 0xFFFFFF, width = 432})
end

local function draw_title()
  img("BG_ROOM", 0, 0)
  shade(0, 0, 480, 320)
  for i = 1, 4 do
    bezel(MON_X[i], MON_Y, MON_W, MON_H, nil)
    noise_box(MON_X[i] + 4, MON_Y + 4, 96, 72)
  end
  text("CONTROL", 240, 104, {font = TITLE, scale = 2, align = "center", color = 0xFF4A3A, gradient = 0x901810,
       outline = 0x100404, shadow = 0x000000, shadow_x = 2, shadow_y = 2})
  text(W.sub, 240, 176, {font = FONT, align = "center", color = 0xE8DCC0})
  text(W.lang, 240, 214, {font = FONT, align = "center", color = 0x9CC8FF})
  if ticks() % 60 < 40 then text(W.start, 240, 250, {font = FONT, align = "center", color = 0xFFFFFF}) end
end

local function draw_zoom()
  if zoom_t <= 1 then -- the control room again, once, onto the canvas: the screen in your hands
    target("SCREEN")
    draw_room(false)
    target()
  end
  if zoom_t > 240 then draw_room(false); return end -- inside: the control room, live again
  local f = zoom_t / 240
  local z = 1 + (480 / HAND.w - 1) * f * f * f -- slow, then rushing in
  local cx, cy = HAND.x + HAND.w / 2, HAND.y + HAND.h / 2
  local ox, oy = 240 - cx * z, 160 - cy * z + (1 - f) * -20
  local ix, iy, iw, ih = ox + HAND.x * z, oy + HAND.y * z, HAND.w * z, HAND.h * z
  if not (ix <= 0 and iy <= 0 and ix + iw >= 480 and iy + ih >= 320) then -- (covered: not drawn under it)
    img("CAM00_Z", ox, oy, {scale = z})
  end
  img("SCREEN", ix, iy, {scale_x = iw / 480, scale_y = ih / 320})
end

function _draw()
  cls(0)
  if state == "title" then draw_title(); return end
  if state == "zoom" then draw_zoom(); return end
  draw_room(true)
  if state == "brief" or state == "twist" or state == "twist2" or state == "end" then
    s:draw()
  elseif state == "air" then
    draw_line()
  end
  if state == "listen" then
    local level = mic()
    shade(16, 226, 448, 60)
    if level then
      text(W.speak, 24, 232, {font = TITLE, color = 0xFF6050})
      rect(24, 272, math.floor(432 * level), 8, level > 0.25 and 0x60F080 or 0xC8C8C8)
      box(24, 272, 432, 8, 0x60666E)
    else
      text(W.press, 24, 240, {font = TITLE, color = 0xFFFFFF})
    end
  end
  if state == "end" then
    plate(PGM_X + 10, PGM_Y + 40, 120, 20, 0x000000)
    text(W.over, PGM_X + 70, PGM_Y + 40, {font = FONT, align = "center", color = 0xFFFFFF})
    text(W.score .. ": " .. punts .. " / 27", 240, 204, {font = FONT, align = "center", color = 0xFFE070})
    if not s:running() then text(W.again, 240, 300, {font = FONT, align = "center", color = 0xB0B4BA}) end
  end
end
