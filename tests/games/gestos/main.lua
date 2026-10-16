-- What a finger did, for tests/gestos.script: where it went down, where it is, how long, how many lifts.
down_at, now_at, held, lifts, taps, path = nil, nil, 0, 0, 0, 0
local was
function _update()
  local x, y, down, tapped = touch()
  if down then
    if not was then down_at, now_at, held, path = {x, y}, nil, 0, 0 end
    if now_at then path = path + math.abs(x - now_at[1]) + math.abs(y - now_at[2]) end
    now_at, held = {x, y}, held + 1
  elseif was then
    lifts = lifts + 1
  end
  if tapped then taps = taps + 1 end
  was = down
end
function _draw() cls(0) end
