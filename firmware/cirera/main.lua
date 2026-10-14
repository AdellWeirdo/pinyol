-- Cirera: the console's game list, made with pinyol, as pinyol's brand manual says (ink 70 %, paper 20 %, cherry and
-- gold 10 %; Jersey 15 for titles, Silkscreen for labels; the logo whole, with its clear space, never stretched).
-- When the console wakes, pinyol's logo builds itself (frames drawn for it: the seed falls, lands in a puff of dust and
-- sprouts; the word comes in from the right as a streak of light and settles), "Cirera · firmware" under it, a
-- four-note chime; then the games as covers in a row, the chosen one big in the middle. Moving slides the row, a soft
-- tick a step; the chosen cover bobs, a light crosses it when it lands, the background takes a little of its colour.
-- A plays it: the cover sinks under the finger, then grows to fill the screen. B asks before switching off (MENU is
-- START in a game with no bag: game.c). Back from a game the list opens on it, without the intro.
-- The games and their covers come from the console (console_games, console_cover); a game without one gets a card.
local INK, INK2, INK3, PAPER, DIM, CHERRY, GOLD = 0x0B0E1F, 0x131837, 0x1C2350, 0xEEF0FF, 0x8F97CC, 0xE8344E, 0xFFC94A
local LOGO = {x = 88, y = 52} -- the intro's logo: its canvas (303 x 197) on the screen
local SPACING, CY = 214, 132  -- the row: cover centres apart, and their height on the screen
local SCALES = {0.62, 0.78, 0.94, 1.1} -- a cover's sizes, few so each is made once (a scaled picture is kept)
local SLOTS = 36 -- covers kept at once (canvases CV1..): 36 x 240 x 160 is within a game's 3 MB of canvases
local CARDS = {0x7A2E3A, 0x2E5A7A, 0x3A7A4E, 0x7A5E2E, 0x5A3A7A, 0x2E7A72} -- a cover-less game's card

state, sel, GAMES = "intro", 1, {} -- (global: tests/cirera.script)
local tick, pos, bg, shine, press, zoom, asking, enter = 0, 1, INK, 0, 0, 0, false, 0
local version = console_version and console_version() or ""
local slot_of, slot_game, slot_used, loaded = {}, {}, {}, 0

local function mix(a, b, k) -- two 0xRRGGBB colours, k = 0 is a, 1 is b
  local function ch(s) return ((a >> s) & 255) + (((b >> s) & 255) - ((a >> s) & 255)) * k end
  return (math.floor(ch(16)) << 16) | (math.floor(ch(8)) << 8) | math.floor(ch(0))
end
local function ease(k) return 1 - (1 - k) ^ 3 end -- fast, then gently into place
local function ease_in(k) return k * k end

function _init()
  show(0)
  sound("TICK", {wave = "square", freq = 1320, sustain = 0.008, decay = 0.04, volume = 0.12})
  sound("OK", {wave = "square", freq = 660, slide = 1400, sustain = 0.03, decay = 0.2, volume = 0.22})
  sound("EDGE", {wave = "square", freq = 220, sustain = 0.01, decay = 0.06, volume = 0.12})
  local last, cold
  GAMES, last, cold = console_games()
  for i, g in ipairs(GAMES) do
    g.color = CARDS[(i - 1) % #CARDS + 1]
    g.look = g.subtitle ~= "" and g.subtitle or (g.flash and "En la memoria" or "En la tarjeta")
  end
  sel = last or 1
  pos = sel
  SLOTS = math.min(SLOTS, math.max(1, #GAMES))
  version = version:match("^v?(%d+%.%d+%.%d+)") or version:sub(1, 12) -- "0.1.0", as the manual shows it
  if not cold then state, enter = "list", 1 end -- back from a game: straight to its cover
end

-- ------------------------------------------------------------------ covers

local function cover(i) -- the canvas with game i's cover, loaded now if it is not; nil: it has none
  local g = GAMES[i]
  if not g or g.none then return nil end
  local s = slot_of[i]
  if not s then
    s = 1
    for k = 1, SLOTS do -- a free slot, or the one drawn longest ago
      if not slot_game[k] then s = k break end
      if (slot_used[k] or 0) < (slot_used[s] or 0) then s = k end
    end
    if slot_game[s] then slot_of[slot_game[s]] = nil end
    local color = console_cover(g.id, "CV" .. s)
    if not color then g.none = true return nil end
    g.color, slot_of[i], slot_game[s] = color, s, i
  end
  slot_used[s] = tick
  return "CV" .. s
end

local function preload() -- one cover a tick while nothing moves: the chosen one first, then outwards
  if loaded >= 2 * SLOTS then return end
  loaded = loaded + 1
  local d = loaded // 2
  local i = loaded % 2 == 0 and sel + d or sel - d
  if i >= 1 and i <= #GAMES then cover(i) end
end

-- ------------------------------------------------------------------ the sky

local function draw_sky(tint) -- the night: its colour, then its stars (one picture, art.py), twinkling
  rect(0, 0, 480, 320, tint)
  img("SKY", 0, 0, {frame = (tick // 40) % 2})
end

-- ------------------------------------------------------------------ the intro

local function chime(t) -- four notes as the logo comes together
  if t == 34 then tone(0, "C5", {wave = "square", duty = 0.25, decay = 0.25, volume = 0.2}) end
  if t == 62 then tone(1, "E5", {wave = "square", duty = 0.25, decay = 0.25, volume = 0.2}) end
  if t == 80 then tone(2, "G5", {wave = "square", duty = 0.25, decay = 0.4, volume = 0.2}) end
  if t == 96 then tone(0, "C6", {wave = "triangle", decay = 0.9, volume = 0.25}) end
end

local function draw_logo(x, y, t) -- as far as time t has built it
  if t >= 10 then -- the seed: falls (frame 0, its trail), lands in dust (1), sprouts (2, 3, 4); then the logo's own
    if t < 34 then img("INTRO_SEED", x, y - 230 * (1 - ease_in((t - 10) / 24)), {frame = 0})
    elseif t < 70 then img("INTRO_SEED", x, y, {frame = math.min(4, 1 + (t - 34) // 9)})
    else img("SEED", x, y) img("LEAVES", x, y, {frame = 5}) end
  end
  if t >= 60 then -- the word: a streak from the right (0), arriving (1), settled (2), a light across it (3), a sparkle
    if t < 70 then img("INTRO_WORD", x + 300 * (1 - ease((t - 60) / 10)), y, {frame = 0})
    elseif t < 80 then img("INTRO_WORD", x + 40 * (1 - ease((t - 70) / 10)), y, {frame = 1})
    elseif t < 88 then img("INTRO_WORD", x, y, {frame = 2})
    elseif t < 96 then img("INTRO_WORD", x, y, {frame = 3})
    elseif t < 104 then img("INTRO_WORD", x, y, {frame = 4})
    else img("WORD", x, y) end
  end
end

local function update_intro()
  chime(tick)
  if tick > 8 and (btnp("a") or btnp("b") or btnp("start") or btnp("left") or btnp("right")) then tick = 170 end
  if tick >= 170 then state, enter = "list", 0 end
  preload()
end

local function draw_intro()
  draw_sky(mix(0x000000, INK, math.min(1, tick / 16)))
  local up = tick > 140 and ease_in(math.min(1, (tick - 140) / 30)) or 0 -- then up and away, for the list
  draw_logo(LOGO.x, LOGO.y - 260 * up, math.min(tick, 140))
  if tick >= 104 and up == 0 then -- the console and its firmware, a seed's height under the logo
    local line = "CIRERA" .. (version ~= "" and ("  ·  FIRMWARE " .. version:upper()) or "")
    text(line, 240, 282, {font = "label", align = "center", color = mix(INK, DIM, math.min(1, (tick - 104) / 20))})
  end
end

-- ------------------------------------------------------------------ the list

local function move(d)
  local to = sel + d
  if to < 1 or to > #GAMES then sfx("EDGE") return end
  sel, shine = to, 0
  sfx("TICK", 1, {pitch = 1 + (sel - 1) * 0.02}) -- a little higher along the row
end

local function update_list()
  if asking then -- "switch off?"
    if btnp("a") then console_off() end
    if btnp("b") then asking = false end
    return
  end
  if press > 0 then
    press = press + 1
    if press > 6 then state, zoom = "launch", 0 end
    return
  end
  if #GAMES == 0 then return end
  if btnp("left", 18, 6) or btnp("up", 18, 6) then move(-1) end
  if btnp("right", 18, 6) or btnp("down", 18, 6) then move(1) end
  local x, _, _, tapped = touch()
  if tapped then
    if x < 70 then move(-1) elseif x > 170 then move(1) else press = 1 sfx("OK") end
  end
  if btnp("a") or btnp("start") then press = 1 sfx("OK") end
  if btnp("b") then asking = true end
end

local function step(s) -- the nearest of the few sizes
  local best = SCALES[1]
  for _, v in ipairs(SCALES) do if math.abs(v - s) < math.abs(best - s) then best = v end end
  return best
end

local function card_rect(i, k_launch)
  local d = i - pos
  local a = math.min(1, math.abs(d))
  local s = step(SCALES[#SCALES] - (SCALES[#SCALES] - SCALES[1]) * a)
  local cx = 240 + d * SPACING
  local cy = CY + ((i == sel and press == 0) and math.sin(tick / 22) * 2 or 0) + 220 * (1 - ease(enter))
  if i == sel and press > 0 then cy = cy + 3 * math.sin(math.min(press, 6) / 6 * math.pi) end -- pressed in
  if k_launch then s, cx, cy = s + (2 - s) * k_launch, cx + (240 - cx) * k_launch, cy + (160 - cy) * k_launch end
  return cx - 120 * s, cy - 80 * s, 240 * s, 160 * s, s, a
end

local function draw_card(i, k_launch)
  local x, y, w, h, s, a = card_rect(i, k_launch)
  if x > 480 or x + w < 0 then return end
  local chosen = a < 0.5
  if chosen then -- a shadow and a paper frame
    rect(x + 5, y + 7, w, h, mix(bg, 0x000000, 0.65))
    rect(x - 3, y - 3, w + 6, h + 6, PAPER)
  end
  local g, c = GAMES[i], cover(i)
  if c then img(c, x, y, {scale = s})
  else -- no cover: a card of its colour, the seed and its name
    rect(x, y, w, h, g.color)
    if chosen then text(g.title, x + w / 2, y + h / 2 - 8, {font = "label", align = "center", color = PAPER, width = w - 16}) end
  end
  if not chosen then shade(x, y, w, h) end -- the neighbours, darker (cheaper than mixing them)
  if a < 0.02 and shine < 30 and not k_launch and s == SCALES[#SCALES] then -- a light crossing it as it lands
    clip(math.floor(x), math.floor(y), math.floor(w), math.floor(h))
    img("SHINE", x - 72 + (w + 72) * ease(shine / 30), y, {add = true})
    clip()
  end
end

local function draw_header()
  img("CIRERA_LOGO", 14, 5)
  local level, charging = battery()
  if level then -- the battery: an outline and its charge
    box(422, 14, 40, 18, PAPER)
    rect(462, 19, 3, 8, PAPER)
    rect(425, 17, math.floor(34 * level + 0.5), 12, (charging and GOLD) or (level < 0.2 and CHERRY) or PAPER)
  end
end

local function draw_footer(g)
  text(g.title, 240, 228, {font = "title", align = "center", color = PAPER})
  local look = g.look:upper()
  local extra = (g.flash and not g.music) and "  ·  SIN MÚSICA" or ""
  local w1 = textw(look, "label")
  local w2 = extra ~= "" and textw(extra, "label") or 0
  local x0 = 240 - (w1 + w2) // 2
  text(look, x0, 260, {font = "label", color = DIM})
  if extra ~= "" then text(extra, x0 + w1, 260, {font = "label", color = GOLD}) end
  local n, track = #GAMES, 200 -- where it is in the row: a thin track and a cherry pill on it (two calls, not n)
  local pill = math.max(10, track // n)
  rect(240 - track // 2, 285, track, 2, INK3)
  rect(240 - track // 2 + (track - pill) * (pos - 1) / math.max(1, n - 1), 284, pill, 4, CHERRY)
  tri(26, 302, 34, 297, 34, 307, DIM) tri(50, 302, 42, 297, 42, 307, DIM)
  text("ELEGIR", 58, 295, {font = "label", color = DIM})
  circ(214, 302, 9, INK3)
  text("B", 214, 295, {font = "label", align = "center", color = PAPER})
  text("APAGAR", 228, 295, {font = "label", color = DIM})
  circ(380, 302, 9, CHERRY)
  text("A", 380, 295, {font = "label", align = "center", color = PAPER})
  text("JUGAR", 394, 295, {font = "label", color = PAPER})
end

local function draw_list(k_launch)
  draw_sky(bg)
  draw_header()
  if #GAMES == 0 then
    text("No hay juegos", 240, 130, {font = "title", align = "center", color = PAPER})
    text("CÓPIALOS EN LA TARJETA, EN GAMES/", 240, 172, {font = "label", align = "center", color = DIM})
    return
  end
  local order = {}
  for i = math.max(1, sel - 3), math.min(#GAMES, sel + 3) do order[#order + 1] = i end
  table.sort(order, function(p, q) return math.abs(p - pos) > math.abs(q - pos) end) -- the far ones first
  for _, i in ipairs(order) do if i ~= sel or not k_launch then draw_card(i, nil) end end
  if k_launch then draw_card(sel, k_launch) elseif enter >= 1 then draw_footer(GAMES[sel]) end
  if asking then
    shade(0, 0, 480, 320)
    rect(96, 104, 288, 112, INK2)
    box(96, 104, 288, 112, CHERRY)
    text("¿Apagar la consola?", 240, 124, {font = "title", align = "center", color = PAPER})
    text("A: SÍ      B: NO", 240, 176, {font = "label", align = "center", color = DIM})
  end
end

-- ------------------------------------------------------------------ the loop

function _update()
  tick = tick + 1
  if state == "intro" then update_intro()
  elseif state == "list" then
    if enter < 1 then enter = math.min(1, enter + 1 / 24) end -- the row coming up after the intro
    update_list()
    pos = pos + (sel - pos) * 0.22
    if math.abs(sel - pos) < 0.01 then pos, shine = sel, shine + 1 preload() end
    if GAMES[sel] then bg = mix(bg, mix(INK, GAMES[sel].color, 0.16), 0.12) end -- ink, a little of its colour
  elseif state == "launch" then
    zoom = zoom + 1
    if zoom == 24 then console_launch(GAMES[sel].id) end -- the menu ends here, the game starts
  end
end

function _draw()
  if state == "intro" then draw_intro()
  elseif state == "list" then draw_list(nil)
  else
    draw_list(ease(math.min(1, zoom / 18)))
    if zoom > 20 then rect(0, 0, 480, 320, INK) end
  end
end
