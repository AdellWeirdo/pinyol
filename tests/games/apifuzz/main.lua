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
-- The newer functions get their own storm with its own random numbers, so the one above keeps its sequence
local NEW = {"mic", "mic_record", "music_time", "file", "physics_step", "video", "led", "battery", "grid", "btnr", "btnt",
             "btnb"}
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
-- The studio's functions, a storm of their own (its own numbers, so the storms above keep their sequences)
local STUDIO = {studio.tempo, studio.length, studio.track, studio.steps, studio.play, studio.stop, studio.playing,
                studio.pos, studio.hit, studio.synth, studio.notes, studio.note, studio.fx}
local seed2 = 777
local function rnd2(n)
  seed2 = (seed2 * 1103515245 + 12345) % 2147483648
  return seed2 % n + 1
end
local function storm_studio(n)
  for _ = 1, n do
    local f, a = STUDIO[rnd2(#STUDIO)], {}
    for i = 1, rnd2(4) - 1 do a[i] = NEW_VALUES[rnd2(#NEW_VALUES)] end
    if rnd2(3) == 1 then a[1] = rnd2(20) - 2 end -- often a track number first
    calls = calls + 1
    if not pcall(f, table.unpack(a, 1, 3)) then failures = failures + 1 end
  end
end
-- The PlayStation and Saturn ones, with arguments in their shape (so most of them draw, and --check-strips compares what they
-- draw) or odd ones in it; again their own numbers
local seed3 = 4242
local function rnd3(n)
  seed3 = (seed3 * 1103515245 + 12345) % 2147483648
  return seed3 // 65536 % n + 1 -- (the high bits: the low ones of this generator repeat soon)
end
local ODD = {0 / 0, 1 / 0, -1 / 0, 1e9, -1e9, 2 ^ 53, "x", true, {}}
local function coord() return rnd3(12) == 1 and ODD[rnd3(#ODD)] or rnd3(640) - 81 end
local function colour() return rnd3(10) == 1 and ODD[rnd3(#ODD)] or rnd3(0x1000000) - 1 end
local function pick(t) return t[rnd3(#t)] end
local PICS = {"STAR", "FR_NEON", "CANV", "CANV2", "SHIP", "nope", "../x"}
local MIXES = {{}, {add = true}, {sub = true}, {quarter = true}, {alpha = 0.5}, {alpha = 0 / 0}, {alpha = 2},
  {add = true, alpha = 0.3}, {dither = true}, {dither = true, sub = true}, {across = true}, {across = true, dither = true, add = true},
  {lay = true}, {frame = 1e9}, {frame = -1}, {light = 0xFFFFFF}, {light = 0x404040, dither = true},
  {lights = {0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF}}, {lights = {1, 2}, persp = true}, {persp = true},
  {persp = true, add = true, light = 0x808080}, {intensity = 2}, {intensity = 0 / 0, sub = true},
  {cone = {angle = 45, width = 60}}, {cone = {angle = 0 / 0, width = 1e9}, sub = true}, {cone = {}}, {dim = 0.5},
  {mul = 0x806040}, {sub = true, alpha = 0.7}, {quarter = true, scale = 2}, {angle = 33, add = true}}
local function rows(n)
  local t = {}
  for i = 1, n do t[i] = rnd3(9) == 1 and pick(ODD) or rnd3(41) - 21 end
  return t
end
local PSX = {
  function() quad(pick(PICS), coord(), coord(), coord(), coord(), coord(), coord(), coord(), coord(), pick(MIXES)) end,
  function() -- a quad that is nearly a box, or a floor going away: the shapes games use
    local x, y, w, h, k = rnd3(480) - 40, rnd3(320) - 40, rnd3(200), rnd3(150), rnd3(80)
    quad(pick(PICS), x + k, y, x + w - k, y, x + w + k, y + h, x - k, y + h, pick(MIXES))
  end,
  function() grad(coord(), coord(), coord(), coord(), colour(), colour(), pick(MIXES)) end,
  function() light(coord(), coord(), rnd3(3) == 1 and coord() or rnd3(160), colour(), pick(MIXES)) end,
  function() warp(pick(PICS), coord(), coord(), {rows = rows(rnd3(70)), cols = rnd3(2) == 1 and rows(rnd3(70)) or nil,
                                                  wrap = rnd3(2) == 1, frame = rnd3(3) - 2}) end,
  function() warp(pick(PICS), coord(), coord(), {rows = function(j) return (j * 7) % 13 - 6 end, cols = pick(ODD)}) end,
  function()
    local h = rnd3(8) == 1 and coord() or rnd3(330)
    local t = {}
    for i = 1, rnd3(340) do t[i] = colour() end
    linetint(coord(), coord(), coord(), h, rnd3(4) == 1 and function(j) return j * 0x010203 end or t, pick(MIXES))
  end,
  function() img(pick(PICS), coord(), coord(), pick(MIXES)) end,
  function() preload(rnd3(3) == 1 and pick(ODD) or {images = {pick(PICS), pick(PICS), 7}, sounds = {"SND", pick(ODD)}}) end,
  function() reverb(pick({"room", "studio", "hall", "space", "off", "nope", 7, 0 / 0}), pick({0, 0.5, 1, 1e9, 0 / 0, -1})) end,
  function() music_pan(pick({-1, 0, 1, 0 / 0, 1e9, "x"})) end,
  function() ambient(pick({"SND", "nope", "../x", 7, {}}), pick({0, 0.5, 2, 0 / 0})) end,
  function() sfx(pick({"SND", "coin", "nope"}), pick({0, 1, 0 / 0}), {pan = pick({-1, 1, 0 / 0, 1e9}), attack = pick({0, 0.1, -1, 0 / 0}),
                 decay = pick({0, 1e9}), sustain = pick({0, 0.5, 2}), release = pick({0, 0.2, 1 / 0}),
                 loop_start = pick({0, 5, -1, 1e9}), loop_end = pick({0, 3, 1e9})}) end,
}
psx_calls, psx_failures = 0, 0
local function storm_psx(n)
  for _ = 1, n do
    calls, psx_calls = calls + 1, psx_calls + 1
    if not pcall(PSX[rnd3(#PSX)]) then failures, psx_failures = failures + 1, psx_failures + 1 end
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
  storm_studio(6)
  for i = 0, 20 do pcall(spr, math.random(0, 127), ship, math.random(-2, 5), math.random(-300, 300),
                         math.random(-300, 300), math.random(0, 0x3FFF)) end
end

function _draw()
  -- boxes with no size or a negative one drew their edges outside their box, where the strips did not look
  box(111, 7, -2147483648, 1, 1023)
  box(255, 0, 1023, -1e9)
  box(300, 100, 1, 10, 0xFF0000)
  box(64, 200, 10, 1, 0x00FF00)
  panel(22, -1, 1e9, -0.5)
  panel(200, 40, 3, 30)
  plate(300, 60, 2, -5, 0xFF0000)
  storm(60)
  storm_psx(25)
end
