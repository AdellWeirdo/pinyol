-- A fighting-game scene at the screen's full resolution, with examples/duelo's pictures (tests/make_neo_game.py
-- converts them): the measure of how much np2d draws in a frame, the way a Neo Geo game does. `mode` (set by
-- tests/neo.script or the benchmark): 1 the stage without fighters, 2 with two, 3 two at 1.25 (a zoomed camera),
-- 4 six of them, 5 at odd scales (small, stretched, upside down, three times as big off the screen's edges).
mode = 2
local t = 0

function _init() show(0) end -- nothing from the 240x160 world: every pixel is drawn at 480x320

function _update() t = t + 1 end

local function fighter(id, x, frame, flip, k)
  if k == 1 then img(id, x, 292 - 181, {frame = frame, flip_x = flip})
  else img(id, x, 292 - 181 * k, {frame = frame, flip_x = flip, scale = k}) end
end

function _draw()
  local cam = math.floor(46 + 46 * math.sin(t / 60)) -- the camera sweeping the stage
  img("BG_FAR", -57 - cam // 2, 0)
  img("BG_NEAR", -cam, 145)
  if mode == 1 then return end
  local f = 1 + (t // 6) % 10 -- walking, then striking
  local k = mode == 3 and 1.25 or 1
  fighter("SPR_F1", 60 + 20 * math.sin(t / 40), f, false, k)
  fighter("SPR_F2", 230 - 20 * math.sin(t / 50), 1 + (f + 3) % 10, true, k)
  if mode == 5 then
    img("SPR_F1", 10, 10, {frame = f, scale = 0.5})
    img("SPR_F2", 140, 20, {frame = f, scale_x = -0.75, scale_y = 1.5})
    img("SPR_F1", 300, 60, {frame = f, scale = 1.1, flip_y = true, flip_x = true})
    img("SPR_F2", -200, -150, {frame = f, scale = 3})
    img("SPR_F1", 420, 200, {frame = f, scale = 0.3, angle = 30}) -- turned: unpacked
    return
  end
  if mode == 4 then
    for i = 0, 3 do fighter(i % 2 == 0 and "SPR_F1" or "SPR_F2", -40 + i * 110, 1 + (f + i) % 10, i % 2 == 1, 1) end
  end
  rect(16, 16, 200, 14, 0x101018) rect(264, 16, 200, 14, 0x101018)
  rect(18, 18, 150, 10, 0xF0C020) rect(312, 18, 150, 10, 0xF0C020)
  text("KAI", 18, 34, {font = "bold", color = 0xFFFFFF, outline = 0x200010})
  text("RAN", 462, 34, {font = "bold", color = 0xFFFFFF, outline = 0x200010, align = "right"})
end
