-- This game's own careta: every game opens with POWERED BY PINYOL, and this one says it its own way. A table with
-- update(t) (true when it is done) and draw(t), t the ticks since it began; the engine plays it before _init, lets
-- no button skip it, keeps it between 2 and 6 s, and draws the seal over whatever it draws, where powered_by puts it.
local SKY, BAND, GOLD, CHERRY = 0x1A0F2E, 0x2E1B4F, 0xFFC94A, 0xE8344E
local careta = {}

function careta.update(t)
  if t == 20 then tone(0, "G4", {wave = "triangle", decay = 0.5, vol = 0.3}) end
  if t == 40 then tone(1, "D5", {wave = "triangle", decay = 0.8, vol = 0.3}) end
  return t >= 150
end

function careta.draw(t)
  rect(0, 0, 480, 320, SKY)
  for i = 0, 11 do -- bands of light going up
    rect(0, (i * 29 - t * 2) % 340 - 20, 480, 3, BAND)
  end
  local k = math.min(1, t / 40)
  text("CARETA", 240, 90 + math.floor((1 - k) * 80), {font = "bold", scale = 3, align = "center", color = GOLD})
  local w, h = powered_by() -- its size, to centre it
  powered_by((480 - w) // 2, 200)
  rect(0, 196, 480, 6, CHERRY) -- drawn after it, on its edge: the seal stays on top
end

return careta
