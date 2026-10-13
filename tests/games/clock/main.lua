-- music_time(), as a rhythm game reads it (tests/clock.script).
times = {}
function _init() show(0) end
function _update()
  local t = music_time()
  times[#times + 1] = t or false
  if #times > 600 then table.remove(times, 1) end
end
function _draw() cls(0) end
function last() return times[#times] end
function rising() -- every time read since the song started is >= the one before
  local prev = -1
  for _, t in ipairs(times) do
    if t then
      if t < prev then return false end
      prev = t
    end
  end
  return true
end
