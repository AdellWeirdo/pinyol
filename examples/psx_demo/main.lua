-- PS1 / Saturn: a small hall to see what the engine does the way those consoles did, all drawn by code (no pictures):
--   quad()    the floor going away (a strip of quads, the way PlayStation games cut a floor up to keep its textures
--             straight), a sign that swings on its chains (a Saturn distorted sprite), a banner lit corner by corner
--   grad()    the sky, from night to the horizon's glow, with the PlayStation's dither
--   add, sub  the lantern's light (img add) and the shadow it casts (img sub), a faint halo (quarter)
--   sound     a chime kept as ADPCM (audio/CHIME.vag), held with an envelope while B is down, placed left or right by
--             the lantern, through the PlayStation's own reverb rooms (A changes the room)
-- Arrows move the lantern. A: next room (and a note in it). B: hold a chime. C: a click, placed where the lantern is.
local HORIZON, SCREEN_W = 118, 480
local ROOMS = {false, "room", "studio_large", "hall", "space_echo"}
local NAMES = {"no reverb", "Room", "Studio Large", "Hall", "Space Echo"}

room, lantern_x, lantern_y, held = 1, 240, 230, nil -- (globals: tests/psx_demo.script)
local t = 0

local function lerp(a, b, k) return a + (b - a) * k end
local function rgb(r, g, b) return math.floor(r) << 16 | math.floor(g) << 8 | math.floor(b) end

local seed = 7
local function noise(n) seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF return (seed >> 16) % n end

local function make_textures()
  -- bricks, in rows that give way by half a brick
  canvas("TEX_FLOOR", 64, 64); target("TEX_FLOOR")
  for row = 0, 3 do
    for col = -1, 2 do
      local x, y = col * 32 + (row % 2) * 16, row * 16
      local shade = noise(24)
      rect(x, y, 32, 16, rgb(96 + shade, 62 + shade * 0.6, 44 + shade * 0.4))
      box(x, y, 32, 16, 0x2A1A12)
    end
  end
  for _ = 1, 160 do pset(noise(64), noise(64), rgb(70 + noise(40), 46 + noise(24), 32 + noise(16))) end
  -- the sign: dark blue, a gold edge, its name
  canvas("TEX_SIGN", 96, 48); target("TEX_SIGN")
  rect(0, 0, 96, 48, 0x182838); box(0, 0, 96, 48, 0xD8A838); box(3, 3, 90, 42, 0x8A6A20)
  text("PS1", 48, 4, {font = "arcade", align = "center", color = 0xF0D890})
  text("SATURN", 48, 26, {font = "arcade", align = "center", color = 0xC0B070})
  -- a banner: cloth, a stripe, a diamond
  canvas("TEX_BANNER", 40, 72); target("TEX_BANNER")
  rect(0, 0, 40, 72, 0x902828); rect(0, 30, 40, 6, 0xD8B040)
  tri(20, 40, 8, 52, 20, 64, 0xD8B040); tri(20, 40, 32, 52, 20, 64, 0xB89030)
  -- a glow: rings from dark at the edge to warm at the heart (drawn with add or sub, it is light or shadow)
  canvas("TEX_GLOW", 64, 64); target("TEX_GLOW")
  for r = 31, 1, -1 do
    local k = (1 - r / 32) ^ 2
    circ(32, 32, r, rgb(255 * k, 176 * k, 96 * k), true)
  end
  target()
end

function _init()
  show(0)
  make_textures()
  sound("SFX_CLICK", {wave = "square", freq = 900, slide = -2200, sustain = 0.02, decay = 0.09, volume = 0.35})
end

-- the carpet: three quads from the horizon to the screen's foot, each the whole texture in perspective (persp = true: the quad is
-- cut into cells as the far edge is smaller than the near one needs, so the bricks stay straight and go away as they should).
-- A quad costs about 150 ns a pixel on the console (400 lit), so it is for what is not the whole screen: a carpet, a sign,
-- a banner. A floor that fills the screen goes on the PPU's affine layer (mode7() in docs/lua.md, examples/carreras).
local function floor_bands()
  local bands = 3
  for i = 0, bands - 1 do
    local a, b = i / bands, (i + 1) / bands
    local ya, yb = HORIZON + (320 - HORIZON) * a * a, HORIZON + (320 - HORIZON) * b * b -- the far edge's depth, then the near's
    local wa, wb = lerp(110, 330, a * a), lerp(110, 330, b * b)
    quad("TEX_FLOOR", 240 - wa / 2, ya, 240 + wa / 2, ya, 240 + wb / 2, yb, 240 - wb / 2, yb, {persp = true})
  end
end

function _update()
  t = t + 1
  if btn("left") then lantern_x = math.max(20, lantern_x - 3) end
  if btn("right") then lantern_x = math.min(SCREEN_W - 20, lantern_x + 3) end
  if btn("up") then lantern_y = math.max(150, lantern_y - 2) end
  if btn("down") then lantern_y = math.min(300, lantern_y + 2) end
  local pan = (lantern_x - 240) / 240
  if btnp("a") then
    room = room % #ROOMS + 1
    reverb(ROOMS[room], 0.8, {music = 0, ambient = 0})
    sfx("CHIME", 0.6, {pan = pan, reverb = 1, release = 0.6, attack = 0.005, sustain = 1})
  end
  if btnp("b") then
    held = sfx("CHIME", 0.7, {loop = true, pan = pan, reverb = 0.8, attack = 0.25, release = 1.2})
  end
  if held and not btn("b") then sfx_stop(held) held = nil end
  if held then sfx_set(held, {pan = pan}) end
  if btnp("c") then sfx("SFX_CLICK", 1, {pan = pan, reverb = 0.6}) end
end

function _draw()
  rect(0, 0, 480, 320, 0x000000)
  -- the sky: night overhead to a glow at the horizon, dithered
  grad(0, 0, 480, HORIZON, 0x080818, 0x6A3A58, {dither = true})
  grad(0, HORIZON - 40, 480, 40, 0x000000, 0x301418, {add = true, alpha = 0.5})
  grad(0, HORIZON, 480, 320 - HORIZON, 0x2A1810, 0x0C0806, {dither = true}) -- the ground beside the carpet
  floor_bands()
  -- the sign swings on two chains: its corners move, the picture bends with them
  local sw = math.sin(t / 28) * 14
  quad("TEX_SIGN", 150 + sw, 36, 250 + sw * 0.9, 40 + sw * 0.2, 252 + sw * 0.9, 88, 146 + sw, 84,
       {lights = {0xA0A0A0, 0xFFFFFF, 0xC0C0C0, 0x808080}, dither = true})
  line(160, 0, 154 + sw, 38, 0x504030); line(240, 0, 246 + sw * 0.9, 41, 0x504030)
  -- the banner is lit a corner at a time, the light going round
  local ph = t / 20
  local function lit(o) return rgb(160 + 95 * math.sin(ph + o), 120 + 60 * math.sin(ph + o), 110 + 40 * math.sin(ph + o)) end
  quad("TEX_BANNER", 350, 34, 390, 30, 394, 104, 346, 108, {lights = {lit(0), lit(1.6), lit(3.2), lit(4.8)}, dither = true})
  -- the lantern: its shadow on the floor (taken away), a halo (a quarter), its light (added)
  img("TEX_GLOW", lantern_x - 64, lantern_y + 24, {scale_x = 2, scale_y = 0.5, sub = true, alpha = 0.6})
  img("TEX_GLOW", lantern_x - 64, lantern_y - 64, {scale = 2, quarter = true})
  local flick = 1 + math.sin(t / 3) * 0.05
  img("TEX_GLOW", lantern_x - 32 * flick, lantern_y - 32 * flick, {scale = flick, add = true})
  rect(lantern_x - 3, lantern_y - 5, 6, 10, 0xF0C060)
  -- what it can do
  text("A ROOM: " .. NAMES[room], 8, 282, {font = "arcade", color = 0xE0D0C0, outline = 0x100808})
  text("B CHIME   C CLICK", 8, 300, {font = "arcade", color = 0xA09080, outline = 0x100808})
end
