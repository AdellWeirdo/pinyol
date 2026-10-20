-- swirl: what happens between the meadow and a fight, all of it the picture's own effects and none of it drawn by the game: the
-- screen flashes twice (fade), the meadow ripples line by line (line_scroll) and goes blocky (mosaic), then an iris closes on the
-- hero (window and line_window), and the fight begins. It is an overlay on the meadow, which keeps drawing under it.
local scene = require("scene")
local ppu = require("ppu")

local S = {overlay = true}
local FLASH, RIPPLE_FROM, IRIS_FROM, LEN = 24, 20, 44, 72

function S.enter(args)
  S.t, S.zone = 0, args.zone
  sfx("SWIRL")
end

function S.update()
  S.t = S.t + 1
  local t = S.t
  local cam_x, cam_y = require("field").camera()
  if t <= FLASH then
    fade("light", ALL, math.floor(14 * math.abs(math.sin(t / FLASH * math.pi * 2)) + 0.5)) -- two flashes
  elseif t == FLASH + 1 then
    fx_off()
  end
  if t > RIPPLE_FROM then
    local k = (t - RIPPLE_FROM) / (LEN - RIPPLE_FROM)
    for y = 0, SCREEN_H // 2 - 1 do line_scroll(2, y, cam_x + math.floor(math.sin(y / 5 + t / 2) * 14 * k + 0.5)) end
    local m = 1 + math.floor(k * 8)
    mosaic(m, m, m, m)
  end
  if t == IRIS_FROM + 1 then backdrop(0) end -- (what the iris leaves outside it: black, as the fight's)
  if t > IRIS_FROM then
    local hx, hy = require("field").hero_on_screen()
    ppu.iris(hx, hy, 150 * (1 - (t - IRIS_FROM) / (LEN - IRIS_FROM)))
  end
  if t >= LEN then scene.go(require("battle"), {zone = S.zone}) end
end

function S.draw() end -- (the meadow under it is what is seen)

return S
