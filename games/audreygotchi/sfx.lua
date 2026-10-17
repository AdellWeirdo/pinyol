-- sfx: the board's sounds, note for note (platforms/esp32s3/hardware/speaker.py): square-wave note lists, which is
-- what a Game Boy's pulse channel plays. A little sequencer plays them on voice 0, one after another; the same
-- rules decide what is heard at night (D-14).
local M = {}

local C5, E5, G5, C6 = 523, 659, 784, 1047
local D5, F5, A5, B5, D6, E6, G6 = 587, 698, 880, 988, 1175, 1319, 1568

local function rep(notes, n) local out = {} for _ = 1, n do for _, x in ipairs(notes) do out[#out + 1] = x end end return out end
local function cat(...)
  local out = {}
  for _, l in ipairs({...}) do for _, x in ipairs(l) do out[#out + 1] = x end end
  return out
end
local function up(notes) local out = {} for i, x in ipairs(notes) do out[i] = {x[1] * 2, x[2]} end return out end
local function n(...) local a, out = {...}, {} for i = 1, #a, 2 do out[#out + 1] = {a[i], a[i + 1]} end return out end

local S = {
  simon_0 = n(C5, 220), simon_1 = n(E5, 220), simon_2 = n(G5, 220),
  responde = n(G5, 70, 0, 40, E5, 110),
  saludo = n(C5, 80, E5, 80, G5, 90),
  mimos = cat(rep(n(523, 40, 587, 40), 3), n(0, 30, 880, 50, 1047, 80)),
  hambre = n(1400, 80, 0, 40, 1400, 80),
  alerta = rep(n(1500, 70, 1250, 70, 1000, 80, 800, 140, 0, 70), 2),
  enfado = n(622, 40, 587, 40, 554, 40),
  enferma = n(880, 120, 740, 120, 587, 110),
  curar = n(C5, 50, E5, 50, G5, 50, C6, 60, 1568, 90),
  rechazo = n(698, 50, 523, 50),
  buscar = n(880, 60, 0, 60, 880, 60, 0, 60, 880, 60),
  escondida = n(G5, 60, E5, 60, C5, 90),
  encontrada = n(C5, 70, E5, 70, G5, 70, C6, 160),
  pide_jugar = n(600, 60, 750, 60, 950, 120),
  capricho = n(750, 60, 600, 60, 900, 140),
  fiesta = n(C5, 80, E5, 80, G5, 80, E5, 80, C6, 200),
  gana = n(C5, 90, E5, 90, G5, 90, C6, 140, 0, 40, G5, 90, C6, 260),
  pierde = n(784, 200, 740, 200, 698, 200, 659, 420),
  tema_feather = n(G5, 110, E5, 110, G5, 110, C6, 220, 0, 50, 880, 110, G5, 110, E5, 220),
  tema_brush = n(E5, 180, G5, 180, 880, 180, G5, 180, E5, 360),
  tema_knots = n(C5, 130, 587, 130, E5, 130, C5, 130, E5, 130, 698, 130, G5, 260),
  tema_laser = n(C6, 70, 1319, 70, 1568, 70, 1319, 70, C6, 140, 0, 40, 1568, 200),
  tema_boxes = n(440, 140, C5, 140, E5, 140, 880, 280, 0, 50, E5, 140, C5, 280),
  tema_simon = n(C5, 130, E5, 130, G5, 130, E5, 130, C5, 130, G5, 280),
  mezcla = rep(n(E5, 80, G5, 80), 8),
  llama = n(800, 80, 1000, 120, 0, 90, 800, 80, 650, 160),
  pegatina = n(1568, 60, 2093, 60, 2637, 140),
  regana = n(784, 80, 0, 40, 622, 90, 523, 160),
  come = n(784, 40, 0, 30, 880, 40, 0, 30, 784, 40, 0, 30, 880, 60),
  favorita = n(C5, 60, E5, 60, G5, 60, C6, 60, G5, 60, C6, 140),
  bano = n(1200, 30, 900, 30, 1400, 30, 1000, 30, 1600, 50),
  despierta = n(988, 110, 880, 130, 740, 180),
  saluda = n(700, 80, 900, 140),
  crece_aviso = n(C6, 80, 1319, 80, 1568, 80, 2093, 200, 0, 60, 1568, 80, 2093, 260),
  crece = n(C5, 110, E5, 110, G5, 110, C6, 260, 0, 50, G5, 90, C6, 90, 1319, 120, 1568, 420, 0, 60, 1319, 110,
            1568, 110, 2093, 520),
  regalo = n(C6, 60, 1319, 60, 1568, 60, 2093, 160),
  pajaro = n(2637, 40, 0, 30, 3136, 50, 0, 60, 2637, 40, 0, 30, 3520, 70),
  pajaro_vuela = n(1568, 30, 0, 20, 1760, 30, 0, 20, 1976, 30, 0, 20, 2349, 30, 0, 20, 2637, 60),
  limpia = n(E5, 60, G5, 60, C6, 60, 0, 40, C6, 120),
  sancho = up(cat(n(392, 90, 330, 90, 392, 140, 0, 60),
                  rep(n(196, 150, 0, 50, 247, 150, 0, 50, 294, 150, 0, 50, 247, 150, 0, 50), 2),
                  n(196, 150, 0, 50, 294, 150, 0, 50), n(523, 120, 659, 160, 0, 120, 784, 200, 0, 480),
                  rep(n(196, 140, 0, 40, 392, 100, 0, 40, 247, 140, 0, 40, 494, 100, 0, 40), 3),
                  n(294, 150, 0, 50, 247, 150, 0, 50, 196, 500, 0, 300))),
  vuelve = up(cat(rep(n(196, 140, 0, 40, 392, 100, 0, 40, 247, 140, 0, 40, 494, 100, 0, 40), 4),
                  n(784, 90, 988, 140, 0, 120), rep(n(196, 150, 0, 50, 247, 150, 0, 50), 4),
                  n(392, 90, 330, 90, 392, 140, 0, 200))),
  tira = n(E5, 50, G5, 80),
  aprieta = n(554, 90, 0, 30, 466, 160),
  libre = n(C5, 60, E5, 60, G5, 60, C6, 60, E5, 60, C6, 160),
  amigo = n(G5, 70, E5, 90, 0, 60, E5, 70, G5, 120),
  trueno = n(180, 30, 0, 20, 140, 40, 110, 60, 160, 30, 90, 120, 120, 80, 70, 200),
  fuegos = n(900, 25, 0, 90, 1300, 20, 0, 60, 700, 30, 0, 150, 1600, 15, 0, 40, 1100, 20),
  nace_estrella = n(C6, 90, 0, 60, 1319, 130),
  nace_fugaz = n(1568, 50, 1319, 50, 1175, 50, 988, 60, 880, 90),
  nace_zoom = n(900, 70, 780, 70, 660, 70, 560, 80, 480, 110),
  nace_cae = n(1400, 50, 1200, 50, 1000, 60, 850, 60, 700, 80),
  nace_rebota = n(440, 90, 0, 40, 587, 60, 784, 80, 0, 70, 659, 60),
  nace_orejas = n(900, 40, 0, 100, 1000, 40),
  nace_cola = n(500, 40, 820, 60),
  nace_bostezo = n(740, 120, 622, 140, 523, 170),
  nace_saludo = n(600, 60, 750, 60, 950, 110),
  nace_logo = n(C5, 120, E5, 120, G5, 120, C6, 260),
}

-- the farewell's music box: each note plucked, a short ring then a rest; a beat is 420 ms
local BEAT = 420
local function box(notes)
  local out = {}
  for _, x in ipairs(notes) do
    local ms = math.floor(BEAT * x[2])
    if x[1] ~= 0 then out[#out + 1] = {x[1], ms * 2 // 3} out[#out + 1] = {0, ms - ms * 2 // 3}
    else out[#out + 1] = {0, ms} end
  end
  return out
end
local function b(...) return box(n(...)) end
local A_ = n(E5, 1, G5, 1, C6, 1, G5, 1, A5, 1, G5, 1, E5, 2)
local B_ = n(F5, 1, A5, 1, C6, 1, A5, 1, G5, 1, E5, 1, D5, 2)
local C_ = n(E5, 1, D5, 1, C5, 1, E5, 1, G5, 1, A5, 1, G5, 2)
local D_ = n(C6, 1, B5, 1, A5, 1, G5, 1, E5, 1, D5, 1, C5, 2)
local function part(l, a, z) local out = {} for i = a, z or #l do out[#out + 1] = l[i] end return out end
local TWINKLE = n(E6, 50, 0, 30, G6, 60, 0, 110)
local FALL = n(G6, 50, E6, 50, D6, 50, C6, 60, A5, 70, G5, 90)
local PIP = n(1400, 60, 0, 90, 1400, 60, 0, 150)
local DOOR = n(440, 70, 554, 70, 659, 90, 880, 140)
local ENGINE = rep(n(440, 70, 0, 10, 523, 70, 0, 10), 6)
local WHOOSH = n(440, 50, 554, 50, 659, 50, 784, 50, 988, 60, 1175, 80)
local SHIMMER = rep(n(1760, 40, 1568, 40), 6)
local FAREWELL = {
  habitacion = box(part(A_, 1, 4)),
  calma = box(cat(part(A_, 5), n(E5, 1, D5, 1, C5, 2))),
  nota = cat(TWINKLE, b(G5, 1, A5, 1, G5, 2, 0, 1)),
  ventana = cat(S.nace_zoom, box(part(B_, 1, 5))),
  estrella = cat(TWINKLE, b(E5, 1, G5, 1, C6, 1, E6, 2)),
  mira = b(D6, 1, C6, 1, G5, 3),
  pulsa = cat(SHIMMER, b(C6, 1, E6, 2)),
  baja = cat(FALL, b(G5, 1, E5, 1, C5, 2)),
  cerca = b(F5, 1, A5, 1, C6, 1, D6, 1, C6, 2),
  revela = cat(SHIMMER, b(C6, 0.5, E6, 0.5, G6, 1, E6, 1, C6, 2)),
  llega = cat(WHOOSH, b(G5, 1, C6, 1, E6, 1, D6, 2)),
  presenta = cat(PIP, PIP, b(C6, 1, G5, 1, C6, 1.5)),
  entiende = box(cat(part(C_, 1, 4), n(E5, 1))),
  despide = b(G5, 1, A5, 1, G5, 1, E5, 1, D5, 1, C5, 2),
  anda = box(cat(rep(n(C5, 0.5, E5, 0.5, G5, 0.5, E5, 0.5), 3), n(C6, 1))),
  puerta = cat(DOOR, b(E5, 1, G5, 1, C6, 2)),
  sube = box(B_),
  ventanita = cat(S.responde, b(G5, 1, A5, 1, G5, 2, 0, 1)),
  prepara = cat(ENGINE, b(C5, 1, E5, 1, G5, 1)),
  despega = cat(WHOOSH, b(C6, 1, E6, 1, G6, 2), SHIMMER),
  aleja = box(cat(part(A_, 1, #A_ - 1), n(E5, 1.5))),
  asciende = b(C5, 1, E5, 1, G5, 1, C6, 1, E6, 2),
  destello = cat(SHIMMER, b(C6, 0.5, E6, 0.5, G6, 2)),
  su_estrella = box(D_),
  creditos = box(cat(A_, B_, part(D_, 1, 4), n(E5, 2))),
  gracias = b(D5, 1, E5, 1, C5, 4),
  autores = box(cat(C_, B_, n(C5, 4))),
  logo = b(C5, 0.5, E5, 0.5, G5, 0.5, C6, 1.5, 0, 1, G5, 0.5, C6, 2),
}
for step, notes in pairs(FAREWELL) do S["adios_" .. step] = notes end
M.SOUNDS = S

local function evolution() -- her growing-up scene's music, in time with core/scene_grow's timings
  local grow = require("core.scene_grow")
  local notes = {}
  for _, hz in ipairs({C5, E5, G5, 988, C6, 1319, 1175, 1568}) do notes[#notes + 1] = {hz, grow.GLOW_MS // 8} end
  local times, prev = grow.flicker_times(), grow.GLOW_MS
  local pairs_ = {{880, 1319}, {988, 1480}, {C6, 1568}}
  for k0, t in ipairs(times) do
    local k = k0 - 1
    local pr = pairs_[math.min(2, 3 * k // #times) + 1]
    notes[#notes + 1] = {k % 2 == 1 and pr[2] or pr[1], t - prev}
    prev = t
  end
  notes[#notes + 1] = {2093, grow.FLASH_MS - prev}
  local run = {C6, 1319, 1568, 2093, 2637, 3136}
  local step = (grow.REVEAL_MS - grow.FLASH_MS - 200) // #run
  for _, hz in ipairs(run) do notes[#notes + 1] = {hz, step} end
  notes[#notes + 1] = {2093, grow.REVEAL_MS - grow.FLASH_MS - step * #run}
  return notes
end

local GROWS = {crece_aviso = true, evoluciona = true, crece = true}
local CRITICAL = {enferma = true, alerta = true}
local VOLUMES = {0.5, 1.0, 2.0}

function M.volume_for(name, sound_mode, night, answering, volume) -- 0: silent
  if not S[name] and name ~= "evoluciona" then return 0 end
  if sound_mode == 1 then return 0 end
  local w = 1.0
  if night or sound_mode == 2 then
    if answering then w = 0.6
    elseif CRITICAL[name] or GROWS[name] or name:sub(1, 5) == "nace_" or name:sub(1, 6) == "adios_" then w = 0.3
    else w = 0 end
  end
  return w * VOLUMES[math.max(0, math.min(2, volume or 1)) + 1]
end

-- the sequencer: notes queued on voice 0, a frame at a time
local queue, at, left = {}, 0, 0

function M.play(name, scale)
  scale = scale or 1
  if scale <= 0 then return end
  local notes = S[name]
  if name == "evoluciona" then S.evoluciona = S.evoluciona or evolution() notes = S.evoluciona end
  if not notes then return end
  if #queue > 48 then return end -- a flood of sounds: drop the newest
  for _, x in ipairs(notes) do queue[#queue + 1] = {x[1], x[2], scale} end
end

function M.stop() queue, left = {}, 0 tone(0) end
function M.busy() return #queue > 0 or left > 0 end

function M.update() -- 60 times a second
  left = left - 1000 / 60
  while left <= 0 do
    local x = table.remove(queue, 1)
    if not x then tone(0) left = 0 return end
    left = left + x[2]
    if x[1] > 0 then
      tone(0, x[1], {wave = "square", duty = 0.5, vol = math.min(1, 0.22 * x[3]), attack = 0.002, decay = 0,
                     sustain = 1, len = x[2] / 1000, release = 0.01})
    else
      tone(0)
    end
  end
end

return M
