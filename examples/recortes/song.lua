-- song: the songs and their phrases. A bar is sixteen steps; a phrase is the notes of one bar: the step it falls on, the button, the syllable sung.
-- A song is a list of bars: the teacher sings a phrase, then the player sings it back.
local M = {}

local function n(step, button, syl) return {step = step, button = button, syl = syl} end

M.phrases = {
  {n(0, "a", "HO"), n(4, "a", "LA"), n(8, "b", "A-"), n(12, "b", "MI")},
  {n(0, "left", "SA"), n(4, "right", "PO"), n(8, "a", "SA"), n(12, "b", "PO!")},
  {n(0, "a", "UN"), n(2, "b", "DOS"), n(4, "a", "TRES"), n(8, "left", "Y"), n(12, "right", "A")},
  {n(0, "a", "RE"), n(3, "a", "CO"), n(6, "b", "RRE"), n(8, "right", "EL"), n(11, "left", "RI"), n(14, "a", "TMO")},
  {n(0, "left", "TIC"), n(2, "right", "TAC"), n(4, "left", "TIC"), n(6, "right", "TAC"), n(8, "a", "BUM"), n(12, "b", "PAF")},
  {n(0, "a", "VA"), n(2, "a", "MOS"), n(4, "b", "A"), n(6, "b", "BAI"), n(8, "left", "LAR"), n(10, "right", "TO"), n(12, "a", "DOS"), n(14, "b", "YA")},
}

local function pairs_of(list) -- teacher then player, for each phrase
  local bars = {}
  for _, k in ipairs(list) do
    bars[#bars + 1] = {who = "teacher", phrase = k}
    bars[#bars + 1] = {who = "player", phrase = k}
  end
  return bars
end

M.songs = {
  {name = "song1", bpm = 96, intro = 2, outro = 1, bars = pairs_of({1, 2, 3, 4, 5}),
   chords = {{"C4", "E4", "G4"}, {"A3", "C4", "E4"}, {"F3", "A3", "C4"}, {"G3", "B3", "D4"}}, bass = {"C2", "A1", "F1", "G1"}},
  {name = "song2", bpm = 120, intro = 2, outro = 1, bars = pairs_of({3, 4, 5, 6, 6}),
   chords = {{"D4", "F4", "A4"}, {"A#3", "D4", "F4"}, {"F3", "A3", "C4"}, {"C4", "E4", "G4"}}, bass = {"D2", "A#1", "F1", "C2"}},
}

return M
