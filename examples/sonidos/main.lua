-- Sonidos: los sonidos de un juego hechos con números (sound), tocados a cualquier tono y en bucle (sfx, sfx_set),
-- música que cambia con el juego (music_layer), y un teclado: una sola muestra tocada como cualquier nota (instrument),
-- una onda dibujada a mano y ruido de 7 bits. Solo una grabación, la música en capas; lo demás sale del código.
--   C o START: cambia de juguete

local CX, CY = SCREEN_W // 2, SCREEN_H // 2
local TOYS = {"Fábrica", "Theremin", "Motor", "Capas", "Teclado"}
toy = 1 -- globals: the test looks at them
local t = 0

-- ------------------------------------------------------------------ Fábrica: a sound from a recipe and a seed
local RECIPES = {"coin", "laser", "explosion", "powerup", "hit", "jump", "blip", "random"}
local NAMES = {coin = "moneda", laser = "láser", explosion = "explosión", powerup = "mejora", hit = "golpe",
               jump = "salto", blip = "bip", random = "sorpresa"}
pick, seed, made = 1, 1, nil -- made: the numbers of the last sound made

local function make()
  made = sound("FAB", RECIPES[pick], seed)
  sfx("FAB")
end

local function factory_update()
  local tx, ty, down, tap = touch()
  if btnp("right") then pick = pick % #RECIPES + 1 end
  if btnp("left") then pick = (pick - 2) % #RECIPES + 1 end
  if btnp("down") then pick = (pick + 3) % #RECIPES + 1 end
  if btnp("up") then pick = (pick - 5) % #RECIPES + 1 end
  if tap then -- a recipe's button
    local col, row = (tx * 2 - 20) // 112, (ty * 2 - 210) // 44
    if col >= 0 and col < 4 and row >= 0 and row < 2 then pick, seed = row * 4 + col + 1, seed + 1 make() end
  end
  if btnp("a") then seed = seed + 1 make() end
  if btnp("b") and made then sfx("FAB") end
end

local function factory_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x1C1830)
  if made then -- the envelope (how loud) and the pitch over time
    local len = made.attack + made.sustain + made.decay
    local function x(s) return 30 + s / len * 420 end
    local base = 170
    poly({x(0), base, x(made.attack), base - 80, x(made.attack), base - 80 - made.punch * 30,
          x(made.attack + made.sustain), base - 80, x(len), base}, 0x3A3466)
    local f, sl, px, py = made.freq, made.slide, nil, nil
    for i = 0, 60 do
      local s = len * i / 60
      local fi = math.max(made.freq_min > 0 and made.freq_min or 20, f + sl * s + made.slide_accel * s * s / 2)
      if made.arp_time > 0 and s > made.arp_time then fi = fi * made.arp end
      local y = base - math.log(fi / 50, 2) * 14
      if px then line(px, py, x(s), y, 0x7CE0FF) end
      px, py = x(s), y
    end
    text(NAMES[RECIPES[pick]] .. "  #" .. seed .. "  " .. made.wave .. "  " .. math.floor(made.freq) .. " Hz", 30, 40,
         0xE0E0F0, "main")
    text(string.format("%.2f s", len), SCREEN_W - 30, 40, 0x9090C0, "main", "right")
  end
  for i, r in ipairs(RECIPES) do
    local col, row = (i - 1) % 4, (i - 1) // 4
    local x, y = 20 + col * 112, 210 + row * 44
    rect(x, y, 104, 38, i == pick and 0xF2B233 or 0x3A3466)
    text(NAMES[r], x + 52, y + 8, i == pick and 0x1C1830 or 0xE0E0F0, "bold", "center")
  end
  text("A: otro · B: otra vez", SCREEN_W - 20, 8, 0x9090C0, "main", "right")
end

-- ------------------------------------------------------------------ Theremin: a looped sound, pitch and volume by hand
local hum = nil -- the handle of the sound that is playing
local pitch, gain = 1, 0
local trail = {} -- where the hand was, newest first

local function theremin_update()
  local tx, ty, down = touch()
  if down then pitch, gain = 0.25 * 2 ^ (tx / 240 * 4), 1 - ty / 160
  else
    pitch = math.max(0.25, math.min(4, pitch * ((btn("right") and 1.02 or 1) / (btn("left") and 1.02 or 1))))
    gain = btn("a") and math.min(1, gain + 0.05) or math.max(0, gain - 0.03)
  end
  if not hum then hum = sfx("HUM", 0, {loop = true}) end
  sfx_set(hum, {pitch = pitch, gain = gain})
  table.insert(trail, 1, {math.log(pitch / 0.25, 2) / 4 * 479, (1 - gain) * 318})
  trail[41] = nil
end

local function theremin_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x08101C)
  for o = 0, 4 do line(o * 119, 30, o * 119, SCREEN_H - 40, 0x1A2A40) end -- the octaves
  for i = #trail, 2, -1 do circ(trail[i][1], trail[i][2], 4 - i // 12, i < 14 and 0x4FA8D0 or 0x24506A) end
  local x, y = math.log(pitch / 0.25, 2) / 4 * 479, (1 - gain) * 318
  circ(x, y, 6 + math.floor(gain * 14), 0x7CE0FF, false)
  circ(x, y, 4, 0xFFFFFF)
  text(string.format("%d Hz", math.floor(220 * pitch)), x + 24, y - 10, 0x7CE0FF, "main")
  text("el dedo: tono ‹ › y volumen", CX, SCREEN_H - 30, 0x7090B0, "main", "center")
end

-- ------------------------------------------------------------------ Motor: the engine's pitch follows the speed
car = {speed = 0, x = 0}
local engine = nil

local function motor_update()
  if btn("a") then car.speed = math.min(8, car.speed + 0.06) else car.speed = math.max(0, car.speed - 0.04) end
  if btn("b") then car.speed = math.max(0, car.speed - 0.2) end
  car.x = (car.x + car.speed) % 64
  if not engine then engine = sfx("ENGINE", 0.6, {loop = true}) end
  sfx_set(engine, {pitch = 0.6 + car.speed * 0.3, gain = 0.35 + car.speed * 0.06})
end

local function motor_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x7EC8E8)
  rect(0, 200, SCREEN_W, 120, 0x505660)
  for x = -64, SCREEN_W, 64 do rect(x - car.x, 252, 34, 6, 0xF2F2F2) end
  local bob = math.floor(math.sin(t * car.speed) * 1.5)
  rect(170, 176 + bob, 140, 34, 0xE8443A)
  rect(200, 156 + bob, 70, 24, 0xE8443A)
  rect(210, 160 + bob, 22, 14, 0xBDE8F8)
  rect(240, 160 + bob, 22, 14, 0xBDE8F8)
  circ(200, 212, 14, 0x202020)
  circ(282, 212, 14, 0x202020)
  rect(30, 40, 200, 16, 0x203040)
  rect(32, 42, math.floor(car.speed / 8 * 196), 12, 0xF2B233)
  text("A: acelera · B: frena", SCREEN_W - 20, 40, 0x203040, "main", "right")
end

-- ------------------------------------------------------------------ Capas: music in layers, in and out
layers = {true, false, false} -- drums, bass, melody
local LAYER_NAMES = {"batería", "bajo", "melodía"}

local function layers_update()
  local tx, ty, down, tap = touch()
  for i = 1, 3 do
    local hit = tap and ty * 2 > 120 and ty * 2 < 200 and tx * 2 > 40 + (i - 1) * 140 and tx * 2 < 160 + (i - 1) * 140
    if btnp(({"left", "up", "right"})[i]) or hit then
      layers[i] = not layers[i]
      music_layer(i - 1, layers[i] and 1 or 0, 400)
    end
  end
end

local function layers_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x2A1A30)
  for i = 1, 3 do
    local x = 40 + (i - 1) * 140
    local beat = layers[i] and math.abs(math.sin(t / 16 * math.pi)) or 0
    rect(x, 120, 120, 80, layers[i] and 0xF2B233 or 0x4A3A56)
    circ(x + 60, 100 - math.floor(beat * 14), 10, layers[i] and 0xFFFFFF or 0x6A5A76)
    text(LAYER_NAMES[i], x + 60, 150, layers[i] and 0x2A1A30 or 0xC0B0D0, "bold", "center")
  end
  text("‹ batería · ^ bajo · › melodía (o tócalas)", CX, SCREEN_H - 30, 0xC0B0D0, "main", "center")
end

-- ------------------------------------------------------------------ Teclado: a recording as any note, a drawn wave, 7-bit noise
local KEYS = {"C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"}
local SOLFA = {"do", "re", "mi", "fa", "sol", "la", "si", "do"}
local TIMBRES = {"muestra con envolvente", "onda de tabla (bajo)", "ruido de 7 bits"}
local BASS = {8, 10, 12, 14, 15, 14, 12, 10, 8, 6, 4, 2, 0, 2, 4, 6, 8, 10, 12, 14, 15, 14, 12, 10, 8, 6, 4, 2, 0, 2, 4, 6}
local ADSR = {a = 0.02, d = 0.15, s = 0.6, r = 0.35}
cursor, timbre, held, gba, last_h = 1, 1, nil, false, 0 -- globals: the test looks at them
local organ, note_h, via, since = nil, nil, nil, 0

local function press(k)
  held, since = k, 0
  if timbre == 1 then
    note_h = organ:play(KEYS[k], 0.9)
    last_h = note_h
  elseif timbre == 2 then
    tone(1, note(KEYS[k]) / 2, {wave = BASS, vol = 0.7, sustain = 1, vibrato = {depth = 15, speed = 5.5, delay = 0.15}})
  else
    tone(3, 2000 + 700 * k, {wave = "noise", lfsr = 7, vol = 0.7, decay = 0.12})
  end
end

local function lift()
  if not held then return end
  if timbre == 1 and note_h then organ:release(note_h) elseif timbre == 2 then tone(1) end
  held, note_h = nil, nil
end

local function set_gba(on) -- the GBA's sound driver: its two-echo reverb, and everything held at 13,379 Hz and 8 bits
  gba = on
  studio.fx({reverb = "gba", size = 0.6, lofi = on})
  organ.reverb = on and 0.5 or 0
end

local function keys_update()
  local tx, _, down = touch()
  if btnp("left") then cursor = (cursor - 2) % 8 + 1 end
  if btnp("right") then cursor = cursor % 8 + 1 end
  if btnp("up") or btnp("down") then
    lift()
    timbre = (timbre + (btnp("up") and 0 or -2)) % #TIMBRES + 1
  end
  if btnp("b") then set_gba(not gba) end
  if down then
    local k = math.max(1, math.min(8, math.floor(tx * 8 / 240) + 1))
    if held ~= k then lift() cursor = k press(k) end
    via = "touch"
  elseif via == "touch" then lift() via = nil end
  if via ~= "touch" then
    if btnp("a") then lift() press(cursor) via = "a" end
    if via == "a" and not btn("a") then lift() via = nil end
  end
  if held then since = since + 1 / 60 end
end

local function level(s) -- the envelope's level s seconds after the key goes down (and while it is held)
  if s < ADSR.a then return s / ADSR.a end
  if s < ADSR.a + ADSR.d then return 1 - (1 - ADSR.s) * (s - ADSR.a) / ADSR.d end
  return ADSR.s
end

local function keys_draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x14202C)
  -- the envelope: attack, decay, sustain (held), release
  local x0, y0, w, h = 30, 120, 420, 70
  local total = ADSR.a + ADSR.d + 0.4 + ADSR.r
  local function X(s) return x0 + s / total * w end
  local function Y(l) return y0 + h - l * h end
  poly({X(0), Y(0), X(ADSR.a), Y(1), X(ADSR.a + ADSR.d), Y(ADSR.s), X(ADSR.a + ADSR.d + 0.4), Y(ADSR.s),
        X(total), Y(0)}, timbre == 1 and 0x2C5A6E or 0x24323E)
  if held and timbre == 1 then circ(X(math.min(since, ADSR.a + ADSR.d + 0.4)), Y(level(since)), 5, 0xFFE070) end
  text(TIMBRES[timbre], 30, 40, 0xE0E8F0, "bold")
  text(gba and "modo GBA: dos ecos y 8 bits" or "B: modo GBA", 30, 74, gba and 0xFFE070 or 0x7090B0, "main")
  -- the keys
  for i = 1, 8 do
    local x = (i - 1) * 60
    local on = held == i
    rect(x + 2, 214, 56, 100, on and 0xFFE070 or (cursor == i and 0xC8D8E8 or 0xF0F4F8))
    text(SOLFA[i], x + 30, 262, 0x14202C, "bold", "center")
    text(KEYS[i], x + 30, 288, 0x607080, "main", "center")
  end
  text("A o el dedo · ‹ › nota · ^ v timbre", SCREEN_W - 20, 8, 0x7090B0, "main", "right")
end

-- ------------------------------------------------------------------ the toy box
local UPDATE = {factory_update, theremin_update, motor_update, layers_update, keys_update}
local DRAW = {factory_draw, theremin_draw, motor_draw, layers_draw, keys_draw}

local function leave(toy_left) -- what a toy plays stops when it is left
  if toy_left == 2 and hum then sfx_stop(hum) hum = nil end
  if toy_left == 3 and engine then sfx_stop(engine) engine = nil end
  if toy_left == 4 then music() end
  if toy_left == 5 then lift() via = nil if gba then set_gba(false) end end
end

function _init()
  show(0)
  sound("HUM", {wave = "sine", freq = 220, sustain = 1, decay = 0, vibrato = 0.02, vibrato_speed = 5, volume = 0.6})
  sound("ENGINE", {wave = "saw", freq = 55, sustain = 1, decay = 0, lowpass = 0.5, resonance = 0.3, volume = 0.7})
  made = sound("FAB", RECIPES[pick], seed) -- whole cycles in a second: both loop without a click
  sound("KEYS", {wave = "saw", freq = 220, sustain = 1, decay = 0, lowpass = 0.55, volume = 0.6}) -- an A3, one second of whole cycles
  -- the loop starts 10 cycles in (220 Hz: 10 / 220 s): the recording's first moments, where its filter is still warming up,
  -- are played once and never again, so the seam is no sharper than the wave's own edge (docs/gba/listen/numbers.txt)
  organ = instrument{sample = "KEYS", root = "A3", loop = {from = 10 / 220, to = 1}, adsr = ADSR, gain = 0.8}
end

function _update()
  t = t + 1
  if btnp("c") or btnp("start") then
    leave(toy)
    toy = toy % #TOYS + 1
    if toy == 4 then
      music("MUS_CAPAS", 0)
      for i = 1, 3 do music_layer(i - 1, layers[i] and 1 or 0, 0) end
    end
  end
  UPDATE[toy]()
end

function _draw()
  DRAW[toy]()
  text(TOYS[toy], 12, 8, toy == 3 and 0x203040 or 0xFFFFFF, "bold")
end
