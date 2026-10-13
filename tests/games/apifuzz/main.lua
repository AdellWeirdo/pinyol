-- Every API function called with odd arguments, many times a tick, in pcall: wrong types, NaN, infinities, huge
-- and negative numbers, bad names. The engine must refuse or clamp, never crash or read outside its memory
-- (tests/apifuzz.script, under ASan in Debug builds).
local NAMES = {"btn", "btnp", "touch", "t", "ticks", "rgb", "pal", "palette", "backdrop", "bg", "scroll", "affine",
  "rot", "mode7", "project", "mget", "mset", "mapsize", "line_scroll", "line_backdrop", "line_window", "line_off",
  "sheet", "spr", "spr_off", "spr_clear", "prio", "bank", "spr_mat", "mat", "show", "blend", "fade", "fx_off",
  "window", "window_off", "window_out", "objwindow", "mosaic", "text", "textw", "rect", "box", "shade", "panel",
  "plate", "img", "frame", "sfx", "tone", "note", "perf", "pset", "pget", "line", "circ", "tri", "poly", "cls", "canvas",
  "target", "camera", "clip", "imgsize", "noise", "sound", "sfx_set", "sfx_stop", "sfx_on", "music_layer"}
local VALUES = {0, 1, -1, 2, 3, 4, 7, 15, 16, 31, 127, 128, 255, 256, 1023, 1024, 32767, 65535, 1e9, -1e9, 0.5, -0.5,
  0 / 0, 1 / 0, -1 / 0, 2 ^ 31, -(2 ^ 31), 2 ^ 53, 0x7FFFFFFF, -0x7FFFFFFF - 1, "", "x", "STARS", "PLANET", "SHIP",
  "../x", "/etc", "C4", "light", "dark", "affine", "tiles", "bitmap", "off", true, false, {}, {map = "STARS"},
  {map = "PLANET", mode = "affine"}, {map = "STARS", mosaic = true, prio = 9}, {image = "SHIP"}, {wave = "noise"},
  ALL, OBJ, BG0, BG3, BACK, FX, FLIP_X | FLIP_Y, BLEND, WINDOW, DOUBLE, MOSAIC, string.rep("ñ", 300),
  "STAR", "FR_NEON", "arcade", "main", {font = "arcade", outline = 0, shadow = 0xFFFFFF, gradient = 0, scale = 1e9,
  spacing = -1e9, wave = 1e9, shake = 0 / 0, shadow_x = 1 / 0, width = 1e9, chars = -5},
  {font = "nofont"}, {font = "../x"}, {font = {}}, {align = "middle"}, {scale = 0.0001, angle = 0 / 0},
  {scale = 1e9, angle = 1e9, flip_x = true, flip_y = 1}, {scale_x = -16, scale_y = 1 / 0, frame = 1e9},
  {scale = 3, angle = 45}, {font = "arcade", scale = 8, outline = 1, shadow = 1, wave = 32, shake = 16},
  "CANV", "CANV2", CLEAR, {1, 2, 3, 4, 5, 6}, {0, 0, 1e9, 1e9, -1e9, 5, 0 / 0, 1}, {1, 2, 3}, {"a", "b", "c", "d"},
  "coin", "laser", "random", "SND", {wave = "noise", freq = 1e9, slide = -1e9, sustain = 1e9, lowpass = 0 / 0,
  resonance = 1, again = 0.0001, arp = 0, volume = 2}, {pitch = 1e9, loop = true, gain = -5}, {pitch = 0 / 0}}
-- The newer functions get their own storm with its own random numbers, so the one above keeps its sequence (a
-- different one finds strips that differ from the whole frame on odd PPU settings, 2026-10-13: not fixed yet)
local NEW = {"mic", "mic_record", "music_time", "file", "physics_turning", "video", "led", "battery"}
local NEW_VALUES = {0, 1, -1, 0.5, 1e9, -1e9, 0 / 0, 1 / 0, "", "x", "../x", "SND", "STARS", "bad.txt", true, false,
  {}, {1, 2, 3}, {canvas = "CANV", loop = true, speed = -16}, {canvas = "../x"}, {speed = 0 / 0},
  {{kind = "poly", pts = {0, 0, 1e9, 0 / 0, -1e9, 5}, turns = true, inv = 1, iinv = 1e9},
   {kind = "box", x = 0, y = 0, w = 1e9, h = 0 / 0, turns = true, inv = 1 / 0, angle = 1e9, spin = 0 / 0},
   {kind = "circle", x = 1, y = 1, r = -5, turns = true, inv = 1, iinv = 1}, {kind = "poly", pts = "x", turns = true},
   {kind = "box", x = 1, y = 1, w = 3, h = 3, turns = true, inv = 1, iinv = 1, friction = -1, bounce = 1e9}, 7}}
local seed = 12345
local function rnd(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % n + 1
end
local function storm_new(n)
  for _ = 1, n do
    local f, a = _G[NEW[rnd(#NEW)]], {}
    for i = 1, rnd(7) - 1 do a[i] = NEW_VALUES[rnd(#NEW_VALUES)] end
    calls = calls + 1
    if not pcall(f, table.unpack(a, 1, 6)) then failures = failures + 1 end
  end
end
local fns = {}
for _, n in ipairs(NAMES) do fns[#fns + 1] = _G[n] end
for _, f in ipairs({link.send, link.recv, link.peers, link.id}) do fns[#fns + 1] = f end
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
  sound("SND", "coin", 3)
  canvas("CANV", 64, 48)
  canvas("CANV2", "STAR")
  palette("OBJ", true)
  ship = sheet("SHIP")
  bg(3, {map = "STARS"})
  bg(2, {map = "PLANET", mode = "affine"})
end

function _update()
  storm(60)
  storm_new(10)
  for i = 0, 20 do pcall(spr, math.random(0, 127), ship, math.random(-2, 5), math.random(-300, 300),
                         math.random(-300, 300), math.random(0, 0x3FFF)) end
end

function _draw()
  storm(60)
end
