-- The new looks (tests/looks.script, tests/looks_check.py reads the shots): palcycle on the backdrop's entries, line_affine on
-- an affine layer (one map point a line: uniform lines), line_scroll_ramp on a bitmap, shock and haze on the world, and the
-- stack, water and road libraries.
stack = require("stack")
water = require("water")
road = require("road")
mode, phase, angle = "cycle", 0, 0

function _init()
  pal(0, 0xFF0000) pal(1, 0x00FF00) pal(2, 0x0000FF) pal(3, 0xFFFF00)
  for i = 4, 15 do pal(i, (i * 16) << 16 | (255 - i * 16) << 8 | (i * 37 % 256)) end
  canvas("PIC", 240, 160) target("PIC")
  for y = 0, 159 do for x = 0, 239 do pset(x, y, ((x // 8 + y // 8) % 2 == 0) and 0xFFFFFF or 0x202020) end end
  target()
  for i = 0, 2 do -- three slices drawn by code: a disc, a smaller disc, a dot
    canvas("SL" .. i, 16, 16) target("SL" .. i) circ(8, 8, 7 - i * 2, 0x40FF00 + i * 0x4000, true) target()
  end
  ship = sheet("SHIP")
  canvas("HM", 64, 64) target("HM") -- the hills: a slope rising to the north, a bump in the middle
  for y = 0, 63 do for x = 0, 63 do
    local h = math.floor((63 - y) * 2 + (math.abs(x - 32) < 8 and math.abs(y - 32) < 8 and 80 or 0))
    h = math.min(255, h) pset(x, y, h << 16 | h << 8 | h)
  end end
  target()
  canvas("CM", 64, 64) target("CM") for y = 0, 63 do for x = 0, 63 do pset(x, y, 0x208020 + (x % 2) * 0x102010) end end target()
  canvas("VX", 240, 160)
  car = stack.new({"SL0", "SL1", "SL2"}, {w = 16, h = 16, spacing = 2, scale = 1, steps = 8})
  pond = water.new({x = 0, y = 200, w = 480, springs = 24, colour = 0x2060C0, deep = 0x103060, depth = 100})
  rd = road.new({layer = 1, row = 5, map_w = 128, horizon = 48, stripe_pal = {{1, 0x3C9C3C, 0x2C7C2C}}})
  rd:add(400, 0) rd:add(300, 2) rd:add(300, -2)
end

function _update()
  pond:update()
  rd:update(5)
end

function _draw()
  bg(0) bg(1) bg(2) bg(3)
  if mode == "cycle" then
    palcycle(0, 3, phase)
  elseif mode == "plain" or mode == "shock" or mode == "haze" or mode == "ramp" then
    bg(1, {image = "PIC"})
    if mode == "shock" then shock(120, 80, 40, 8, 6) end
    if mode == "haze" then haze(0, 159, 4, 0, 16) end
    if mode == "ramp" then line_scroll_ramp(1, 0, 159, 0, 32) end
  elseif mode == "affine" then
    bg(1, {map = "PLANET", mode = "affine"})
    for y = 0, 159 do line_affine(1, y, 8 + (y // 40) * 24, 8 + (y // 40) * 24, 0, 0) end
  elseif mode == "road" then
    bg(1, {map = "PLANET", mode = "affine"})
    rd:draw(0)
  elseif mode == "stack" then
    car:draw(100, 100, angle)
  elseif mode == "water" then
    pond:draw()
  elseif mode == "voxel" then -- the hills seen from the south, the sky above the horizon
    line_off()
    voxels("VX", {height = "HM", colour = "CM", x = 32, y = 60, angle = -90, z = 140, horizon = 40, distance = 120, scale = 60, sky = 0x80C0FF})
    img("VX", 0, 0, {scale = 2})
  elseif mode == "sil" then -- the ship behind the picture: its silhouette shows through, red, half
    line_off() -- (the ramp's per-line scroll, from the mode before, would shear the picture)
    bg(1, {image = "PIC", prio = 0})
    silhouette(0xFF0000, 0.5)
    spr(0, ship, 0, 100, 60, SILHOUETTE | prio(1))
  end
end
