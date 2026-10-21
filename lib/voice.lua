-- voice: a character's voice made of one short sound, the way Animal Crossing's villagers and Undertale's people
-- talk: a blip every few letters as the text types out, its pitch from the letter (vowels higher) around the
-- voice's own, so each speaker sounds like someone and no line sounds the same twice.
--
--   local voice = require("voice")
--   abuela = voice.new({sound = "BLIP", pitch = 0.8, spread = 2, every = 2, gain = 0.5})
--   abuela:say(letter)          -- each letter typed (true when it blipped); spaces and marks are silent
--   r = rich.new(line, {blip = abuela:blip()})    -- rich's typing calls it letter by letter
--   abuela:reset()              -- a new line: the count of letters from its start
--
-- sound: a short clip (make one with sound("BLIP", "blip"), or record one); pitch: the voice's own, 1 as the clip is,
-- 2 an octave up; spread: semitones the letters move it, each way (2); every: letters between blips (2).
local M = {}
local V = {}
V.__index = V

function M.new(opts)
  assert(opts and opts.sound, "voice.new: a sound is needed")
  return setmetatable({sound = opts.sound, pitch = opts.pitch or 1, spread = opts.spread or 2, every = opts.every or 2,
                       gain = opts.gain or 0.5, n = 0}, V)
end

function V:say(ch)
  if type(ch) ~= "string" or not ch:match("^%a$") then return false end
  self.n = self.n + 1
  if self.n % self.every ~= 0 then return false end
  local b = ch:lower():byte()
  local semis = ((b * 7) % 13 - 6) / 6 * self.spread -- the letter's own place, -spread..spread, the same every time
  if ("aeiou"):find(ch:lower(), 1, true) then semis = semis + 2 end
  sfx(self.sound, self.gain, {pitch = self.pitch * 2 ^ (semis / 12)})
  return true
end

function V:reset() self.n = 0 end
function V:blip() return function(ch) self:say(ch) end end

return M
