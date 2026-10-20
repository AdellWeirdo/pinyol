-- «La entrevista»: what the player plays, in beats of the song (song.lua: 4 a bar, 0 its start), on the 480x320
-- screen. Data only: the game's logic is in main.lua. Each phrase is numbered from 1 again, as its targets cross
-- the corridor from left to right; a drag is a short path the finger follows. Everyone stands against the wall (feet
-- at y 205): targets keep to the floor in front (y 230-295) and the wall's top strip (y 60-85), away from the faces.
local M = {}

M.APPROACH = 2        -- beats a target shows before its moment (its ring closing)
M.PERFECT = 0.08      -- seconds either side of the beat: "¡Genial!"
M.GOOD = 0.16         -- "¡Bien!"; later than this it is missed
M.FOLLOW = 46         -- pixels the finger may be from a drag's ball
M.OFFSET = 0          -- seconds added to every judgement (the screen and the ears; a calibration may set it)

-- Difficulty changes the window, the warning and how many notes there are, never the song's speed.
M.LEVELS = {
  {id = "ensayo", approach = 2.5, perfect = 0.10, good = 0.20, follow = 56, notes = "fewer"},
  {id = "pasacalles", approach = 2, perfect = 0.08, good = 0.16, follow = 46, notes = "as written"},
  {id = "plaza", approach = 1.6, perfect = 0.06, good = 0.12, follow = 40, notes = "more"},
}

function M.use(level) -- level 1..3: its windows become the chart's
  local l = M.LEVELS[level]
  M.APPROACH, M.PERFECT, M.GOOD, M.FOLLOW, M.level = l.approach, l.perfect, l.good, l.follow, level
end

-- Sections in beats, for the scene and the music's mood.
M.SECTIONS = {
  {name = "espera", from = 0, to = 16},
  {name = "avance", from = 16, to = 48},
  {name = "duda", from = 48, to = 80},
  {name = "fanfarria", from = 80, to = 112},
}

-- Phrases: beats of their taps, and the band of the screen they cross ({x0, x1, y, wave}).
local PHRASES = {
  {beats = {4, 8, 12}, band = {170, 390, 262, 0}},                 -- the wait: one alone each bar, a wide margin
  {beats = {16, 18, 20, 22}, band = {130, 410, 258, 22}},
  {beats = {24, 26, 28, 30}, band = {140, 400, 70, 12}},
  {beats = {32, 33, 34, 35}, band = {180, 360, 262, 18}},
  {beats = {36, 38, 40, 41, 42}, band = {130, 420, 255, 25}},
  {beats = {44, 46}, band = {210, 330, 72, 0}},
  {beats = {48, 50, 52, 54}, band = {150, 390, 262, 18}},          -- the doubt: slower, then a phrase to follow
  {drag = {56, 59}, path = {{140, 270}, {220, 245}, {300, 275}, {380, 250}}},
  {beats = {64, 66, 68, 69, 70}, band = {130, 410, 70, 12}},
  {drag = {72, 75}, path = {{390, 255}, {310, 280}, {230, 252}, {150, 275}}},
  {beats = {76, 78}, band = {210, 320, 262, 0}},
  {beats = {80, 81, 82, 83}, band = {140, 380, 258, 22}},           -- the fanfare: the whole band, denser
  {beats = {84, 86, 88, 89, 90, 91}, band = {120, 420, 70, 12}},
  {beats = {92, 94, 96, 98}, band = {150, 390, 262, 22}},
  {beats = {100, 101, 102, 103}, band = {160, 380, 255, 25}},
  {beats = {104, 106}, band = {220, 340, 72, 0}},
  {beats = {108, 109}, band = {428, 428, 118, 0}, knock = true},    -- knock, knock: on the door
}

-- The notes of a phrase at a level: fewer keeps the first and those two beats or more after the one kept before
-- (no runs); more adds one halfway into every gap of two beats (a run where there was a breath).
local function at_level(beats, kind)
  if kind == "fewer" then
    local out, last = {}, nil
    for _, b in ipairs(beats) do
      if not last or b - last >= 2 then out[#out + 1], last = b, b end
    end
    return out
  elseif kind == "more" then
    local out = {}
    for i, b in ipairs(beats) do
      out[#out + 1] = b
      if beats[i + 1] and beats[i + 1] - b == 2 then out[#out + 1] = b + 1 end
    end
    return out
  end
  return beats
end

function M.notes(level) -- every note at a level (1..3, 2 if left out), in order of time: {t, x, y, n} or a drag
  local kind = M.LEVELS[level or 2].notes
  local out = {}
  for _, p in ipairs(PHRASES) do
    if p.drag then
      out[#out + 1] = {t = p.drag[1], t2 = p.drag[2], path = p.path, x = p.path[1][1], y = p.path[1][2], n = 1, drag = true}
    else
      local x0, x1, y, wave = table.unpack(p.band)
      local beats = p.knock and p.beats or at_level(p.beats, kind) -- (the knock on the door stays as it is)
      local k = #beats
      for i, b in ipairs(beats) do
        local f = k > 1 and (i - 1) / (k - 1) or 0.5
        out[#out + 1] = {t = b, x = math.floor(x0 + (x1 - x0) * f), y = math.floor(y + wave * math.sin(i * 1.9)), n = i,
                         knock = p.knock}
      end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

return M
