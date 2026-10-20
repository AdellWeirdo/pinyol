-- view: the island drawn. The ground is one background (BG2, scrolled by the camera); everything that stands up is a sprite, and the
-- sprites are given their numbers again each frame in depth order, as an isometric game on the GBA had to do: sprite 0 is drawn over
-- sprite 1, so the thing nearest the eye (the greatest x + y) gets the lowest number. Within one cell: a sunk crate on the water first,
-- then a column or crate, a shadow, and the hero or a gem on top. A thing between two cells counts as the one it is mostly in.
local G = require("index")
local iso = require("iso")

local V = {}
local SHEETS = {"COL1", "COL2", "COL3", "COL4", "CRATE", "RAFT", "PALM", "GEM", "HERO", "SHADOW", "SPLASH"}
V.LAYER = {raft = 0, block = 1, shadow = 2, top = 3}

local sheets, statics
local used = 0 -- sprites shown in the last frame
V.order = {} -- the last frame's things, nearest first: the sprite numbers they got (the tests read it)

-- where a cell's ground diamond has its top corner, in the ground picture's pixels (x and y may be fractions)
function V.px(x, y) return G.ox + (x - y) * 16, G.oy + (x + y) * 8 end

-- a thing to draw: its depth (x + y of its cell), layer, sheet, frame, top-left in the ground picture's pixels, flags, a name for tests
function V.thing(cx, cy, layer, sh, f, x, y, flags, name)
  return {k = (cx + cy) * 4 + layer, sh = sh, f = f, x = x, y = y, flags = flags, name = name}
end

function V.init(s)
  sheets = {}
  for _, n in ipairs(SHEETS) do sheets[n] = sheet(n) end
  palette("WORLD")
  palette("OBJ", true)
  bg(0) bg(1) bg(3)
  bg(2, {map = "FLOOR", prio = 2, wrap = false})
  backdrop(G.base)
  statics = {}
  for y = 0, s.h - 1 do
    for x = 0, s.w - 1 do
      local g, px, py = s.cells[iso.key(x, y)], V.px(x, y)
      if g >= 1 and g <= 4 then
        statics[#statics + 1] = V.thing(x, y, V.LAYER.block, "COL" .. g, 0, px - 16, py - 16 * g, 0, "col " .. x .. "," .. y)
      elseif g == iso.PALM then
        statics[#statics + 1] = V.thing(x, y, V.LAYER.block, "PALM", 0, px - 16, py + 8 - 60, 0, "palm " .. x .. "," .. y)
      end
    end
  end
  for i = 0, used - 1 do spr_off(i) end
  used = 0
end

-- the water's glint moving along its stripes: one of its three entries lit at a time
function V.water(t)
  local lit = (t // 10) % 3
  for i = 0, 2 do pal(G.water[2 + i], i == lit and G.glint or G.base) end
end

-- the frame: the ground scrolled, and the columns with what moves (things made with V.thing) given their sprite numbers
function V.draw(moving, cam_x, cam_y)
  cam_x, cam_y = math.floor(cam_x), math.floor(cam_y)
  scroll(2, cam_x, cam_y)
  local list = {}
  for i = 1, #statics do list[i] = statics[i] end
  for i = 1, #moving do list[#list + 1] = moving[i] end
  table.sort(list, function(a, b) return a.k > b.k end) -- nearest first
  local n, order = 0, {}
  for i = 1, #list do
    local it = list[i]
    local x, y = math.floor(it.x) - cam_x, math.floor(it.y) - cam_y
    if n < 128 and x > -40 and x < 240 and y > -90 and y < 160 then
      spr(n, sheets[it.sh], it.f, x, y, prio(1) | it.flags)
      n = n + 1
      order[n] = it
    end
  end
  for i = n, used - 1 do spr_off(i) end
  used, V.order = n, order
end

-- the camera that keeps a point of the ground picture near the middle of the screen, inside the picture
function V.camera(x, y)
  return math.max(0, math.min(G.w - 240, x - 120)), math.max(0, math.min(G.h - 160, y - 84))
end

return V
