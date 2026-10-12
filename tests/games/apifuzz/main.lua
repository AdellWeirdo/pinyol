-- Every API function called with odd arguments, many times a tick, in pcall: wrong types, NaN, infinities, huge
-- and negative numbers, bad names. The engine must refuse or clamp, never crash or read outside its memory
-- (tests/apifuzz.script, under ASan in Debug builds).
local NAMES = {"btn", "btnp", "touch", "t", "ticks", "rgb", "pal", "palette", "backdrop", "bg", "scroll", "affine",
  "rot", "mode7", "project", "mget", "mset", "mapsize", "line_scroll", "line_backdrop", "line_window", "line_off",
  "sheet", "spr", "spr_off", "spr_clear", "prio", "bank", "spr_mat", "mat", "show", "blend", "fade", "fx_off",
  "window", "window_off", "window_out", "objwindow", "mosaic", "text", "textw", "rect", "box", "shade", "panel",
  "plate", "img", "sfx", "tone", "note", "perf"}
local VALUES = {0, 1, -1, 2, 3, 4, 7, 15, 16, 31, 127, 128, 255, 256, 1023, 1024, 32767, 65535, 1e9, -1e9, 0.5, -0.5,
  0 / 0, 1 / 0, -1 / 0, 2 ^ 31, -(2 ^ 31), 2 ^ 53, 0x7FFFFFFF, -0x7FFFFFFF - 1, "", "x", "STARS", "PLANET", "SHIP",
  "../x", "/etc", "C4", "light", "dark", "affine", "tiles", "bitmap", "off", true, false, {}, {map = "STARS"},
  {map = "PLANET", mode = "affine"}, {map = "STARS", mosaic = true, prio = 9}, {image = "SHIP"}, {wave = "noise"},
  ALL, OBJ, BG0, BG3, BACK, FX, FLIP_X | FLIP_Y, BLEND, WINDOW, DOUBLE, MOSAIC, string.rep("ñ", 300)}
local fns = {}
for _, n in ipairs(NAMES) do fns[#fns + 1] = _G[n] end
calls, failures = 0, 0
local ship

local function args()
  local a = {}
  for i = 1, math.random(0, 8) do a[i] = VALUES[math.random(#VALUES)] end
  if math.random(4) == 1 then a[1] = math.random(-2, 130) end -- often a sensible index first
  return a
end

local function storm(n)
  for _ = 1, n do
    local f = fns[math.random(#fns)]
    local a = args()
    calls = calls + 1
    if not pcall(f, table.unpack(a, 1, 8)) then failures = failures + 1 end
  end
end

function _init()
  palette("OBJ", true)
  ship = sheet("SHIP")
  bg(3, {map = "STARS"})
  bg(2, {map = "PLANET", mode = "affine"})
end

function _update()
  storm(60)
  for i = 0, 20 do pcall(spr, math.random(0, 127), ship, math.random(-2, 5), math.random(-300, 300),
                         math.random(-300, 300), math.random(0, 0x3FFF)) end
end

function _draw()
  storm(60)
end
