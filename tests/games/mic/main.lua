-- The microphone as a game uses it (tests/mic.script feeds it tones; on the console it is the real one).
heard = {level = 0, pitch = 0, hits = 0, rec = false}
present = nil

function _init() show(0) end

function _update()
  local level, pitch, hit, rec = mic()
  present = level ~= nil
  if not present then return end
  heard.level, heard.pitch, heard.rec = level, pitch, rec
  if hit then heard.hits = heard.hits + 1 end
end

function _draw()
  cls(0x101820)
  if not present then
    text("sin micrófono", 20, 20, 0xFFFFFF)
    return
  end
  rect(20, 60, math.floor(440 * heard.level), 24, 0x60E080)
  text(string.format("nivel %.2f  tono %.0f Hz  golpes %d", heard.level, heard.pitch, heard.hits), 20, 20, 0xFFFFFF)
end
