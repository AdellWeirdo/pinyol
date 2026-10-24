-- CROMOTA sounds, all synthesised (no files). Each colour has a note; chains climb. Voices: 0-1 notes, 2 bass, 3 noise.
local S = {}

local NOTAS = {rojo = "C", amarillo = "E", azul = "G", blanco = "B", negro = "A", naranja = "D", verde = "F",
               violeta = "A", celeste = "B", marino = "G"}
local cola = {}

local function luego(d, f) cola[#cola + 1] = {t = ticks() + d, f = f} end

-- a quiet loop underneath: four chords, an arpeggio a step every 14 ticks on voice 2 (sound effects may cut it off)
local ACORDES = {{"A3", "C4", "E4"}, {"F3", "A3", "C4"}, {"C3", "E3", "G3"}, {"G3", "B3", "D4"}}
local paso, sonando = 0, true
function S.musica(on) sonando = on end
function S.activa() return sonando end

function S.tick()
  local ahora = ticks()
  if sonando and ahora % 14 == 0 then
    local acorde = ACORDES[(paso // 8) % 4 + 1]
    local n = ({1, 2, 3, 2, 1, 3, 2, 3})[paso % 8 + 1]
    tone(2, acorde[n], {wave = "triangle", vol = 0.1, decay = 0.35})
    paso = paso + 1
  end
  for i = #cola, 1, -1 do
    if cola[i].t <= ahora then
      local f = cola[i].f
      table.remove(cola, i)
      f()
    end
  end
end

function S.cambia() tone(3, "E5", {wave = "triangle", vol = 0.25, decay = 0.05}) end
function S.rechazo() tone(2, "C3", {wave = "square", duty = 0.25, vol = 0.3, decay = 0.12, slide = -120}) end
function S.selecciona() tone(3, "A5", {wave = "square", duty = 0.125, vol = 0.18, decay = 0.03}) end

function S.grupo(color, combo)
  local n, o = NOTAS[color] or "C", math.min(4 + combo - 1, 7)
  tone(0, n .. o, {wave = "square", duty = 0.25, vol = 0.32, decay = 0.1})
  luego(3, function() tone(1, n .. (o + 1), {wave = "triangle", vol = 0.3, decay = 0.12}) end)
end

function S.mezcla()
  tone(0, "E4", {wave = "triangle", vol = 0.35, decay = 0.08})
  luego(4, function() tone(1, "B4", {wave = "triangle", vol = 0.35, decay = 0.14}) end)
end

function S.carga() tone(3, "D5", {wave = "square", duty = 0.5, vol = 0.2, decay = 0.05}) end
function S.error() tone(2, "G2", {wave = "saw", vol = 0.25, decay = 0.1, slide = -80}) end

function S.pinta()
  tone(3, 1400, {wave = "noise", vol = 0.2, decay = 0.35, lfsr = 7})
  luego(8, function() tone(0, "C5", {wave = "triangle", vol = 0.3, decay = 0.2}) end)
  luego(14, function() tone(1, "G5", {wave = "triangle", vol = 0.3, decay = 0.25}) end)
end

function S.pincel()
  tone(3, 1800, {wave = "noise", vol = 0.22, decay = 0.3, lfsr = 7, slide = -4000})
  luego(3, function() tone(0, "G5", {wave = "triangle", vol = 0.3, decay = 0.2}) end)
  luego(8, function() tone(1, "C6", {wave = "triangle", vol = 0.3, decay = 0.25}) end)
end

function S.tubo() -- every drop of a colour goes
  tone(3, 500, {wave = "noise", vol = 0.25, decay = 0.35, lfsr = 15, slide = 3000})
  for i, n in ipairs({"C5", "E5", "G5", "C6", "E6"}) do
    luego((i - 1) * 2, function() tone((i - 1) % 2, n, {wave = "square", duty = 0.25, vol = 0.28, decay = 0.15}) end)
  end
end

function S.crea() -- a brush was made
  for i, n in ipairs({"E5", "G5", "C6"}) do
    luego((i - 1) * 3, function() tone((i - 1) % 2, n, {wave = "square", duty = 0.25, vol = 0.28, decay = 0.12}) end)
  end
end

function S.gana()
  for i, n in ipairs({"C5", "E5", "G5", "C6"}) do
    luego((i - 1) * 7, function() tone((i - 1) % 2, n, {wave = "square", duty = 0.25, vol = 0.35, decay = 0.2}) end)
  end
end

function S.pierde()
  for i, n in ipairs({"G4", "E4", "C4"}) do
    luego((i - 1) * 9, function() tone(0, n, {wave = "triangle", vol = 0.35, decay = 0.25}) end)
  end
end

return S
