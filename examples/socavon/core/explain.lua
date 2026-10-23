-- explain: "Cómo funciona", from the console's menu. Four pages about what made a Spectrum picture what it was:
--   1 the attributes: the screen is a grid of 8x8 blocks and each block has two colours only; move the cursor to read one
--   2 the colour clash: a sprite has no colours of its own, it takes the ink of the block it is over
--   3 bright and flash: the eight colours, normal and bright, and the flashing pair
--   4 the tape and the beeper: why it loaded as it did, and one voice
-- Left and right: page.  Arrows on pages 1 and 2: move.  B: back to the game.
local R = require("core.room")
local Z = require("core.zx")
local H = require("core.hud")
local lang = require("lang")
local E = {}

E.hook = function(id) end
local PAGES = 4
local page, cx, cy, sx, t = 1, 10, 6, 40, 0
E.page, E.sx = 1, 40
local saved = nil -- the room as it was, to put back
local SPR = nil

local function demo_blocks() -- page 2: four bands of different ink and paper across an empty room
  for ty = 0, R.H - 1 do for tx = 0, R.W - 1 do mset(1, tx, ty, R.tile("air") | (R.BANK.air << 12)) end end
  local bands = {{"yellow/blue"}, {"+red/black"}, {"+green/magenta"}, {"white/red"}}
  for i, b in ipairs(bands) do
    local ink, paper = Z.attr(b[1])
    local bank = 9 + i
    pal(bank * 16 + 1, ink) pal(bank * 16 + 2, paper) pal(bank * 16 + 1, ink, true)
    R.band_bank = R.band_bank or {}
    R.band_bank[i] = bank
    for tx = (i - 1) * 7, (i - 1) * 7 + 6 do
      for ty = 2, 13 do mset(1, tx, ty, R.tile("air") | (bank << 12)) end
    end
  end
end

function E.enter(sprite_sheet)
  SPR = sprite_sheet
  page, cx, cy, sx, t = 1, 10, 6, 40, 0
  E.page, E.sx = 1, 40
  saved = {n = R.n}
  E.hook("curioso")
  E.show_page()
end

function E.show_page()
  R.load(R.n) -- the room as the game has it (keys back: the explainer is a look, not a move)
  if page == 2 then demo_blocks() end
end

function E.leave()
  R.load(saved.n)
end

local function swatch(x, y, w, h, c) rect(x, y, w, h, c) end

function E.update()
  t = t + 1
  if btnp("left") and page > 1 then page = page - 1 E.show_page() end
  if btnp("right") and page < PAGES then page = page + 1 E.show_page() end
  E.page = page
  if page == 1 then
    if btnp("up") then cy = math.max(0, cy - 1) end
    if btnp("down") then cy = math.min(R.H - 1, cy + 1) end
    if btnp("a") then cx = (cx + 1) % R.W end
  elseif page == 2 then
    if btn("a") or btn("b") then sx = sx + (btn("a") and 1 or -1) * 1.5 end
    sx = math.max(0, math.min(R.W * 8 - 16, sx))
    E.sx = sx
  end
  return btnp("start") or (btnp("b") and page == PAGES)
end

local function title(txt) text(txt, 240, 2, {font = H.F.title, align = "center", color = Z.BYELLOW}) end
local function body(key, y, extra) text(lang.tr(key, extra), 28, y, {font = H.F.small, color = Z.BWHITE}) end

function E.draw(g)
  rect(0, 0, 480, 16, Z.BLACK)
  title(lang.tr("ex_title_" .. page))
  rect(0, 272, 480, 48, Z.BLACK)
  text(lang.tr("ex_nav", {n = page, m = PAGES}), 240, 304, {font = H.F.small, align = "center", color = Z.rgb("cyan", true)})
  if page == 1 then
    -- the grid of attributes over the room, and the block under the cursor read out
    local grid = Z.rgb("blue", true)
    for x = 0, R.W do rect(16 + x * 16, 16, 1, R.H * 16, grid) end
    for y = 0, R.H do rect(16, 16 + y * 16, R.W * 16, 1, grid) end
    local a = R.attr[R.kind(R.char(cx, cy))]
    local blink = (t // 20) % 2 == 0 and Z.BYELLOW or Z.BWHITE -- the cursor block: outlined, blinking
    rect(16 + cx * 16, 16 + cy * 16, 16, 2, blink) rect(16 + cx * 16, 30 + cy * 16, 16, 2, blink)
    rect(16 + cx * 16, 16 + cy * 16, 2, 16, blink) rect(30 + cx * 16, 16 + cy * 16, 2, 16, blink)
    rect(16, 276, 22, 18, Z.BWHITE) swatch(18, 278, 18, 14, a[2])
    rect(124, 276, 22, 18, Z.BWHITE) swatch(126, 278, 18, 14, a[3])
    text(lang.tr("ex_ink"), 44, 278, {font = H.F.small, color = Z.BWHITE})
    text(lang.tr("ex_paper"), 152, 278, {font = H.F.small, color = Z.BWHITE})
    text(lang.tr("ex_p1"), 240, 276, {font = H.F.small, color = Z.rgb("yellow", true)})
    text(lang.tr("ex_p1b"), 240, 290, {font = H.F.small, color = Z.BWHITE})
  elseif page == 2 then
    text(lang.tr("ex_p2"), 24, 276, {font = H.F.small, color = Z.rgb("yellow", true)})
    text(lang.tr("ex_p2b"), 24, 290, {font = H.F.small, color = Z.BWHITE})
  elseif page == 3 then
    rect(16, 16, 448, 256, Z.BLACK)
    for i, n in ipairs(Z.NAMES) do
      local x = 40 + (i - 1) * 52
      rect(x, 60, 44, 40, Z.rgb(n, false))
      rect(x, 108, 44, 40, Z.rgb(n, true))
      text(n:upper(), x + 22, 44, {font = H.F.small, align = "center", color = Z.BWHITE})
    end
    text(lang.tr("ex_normal"), 40, 156, {font = H.F.small, color = Z.BWHITE})
    text(lang.tr("ex_bright"), 40, 170, {font = H.F.small, color = Z.BWHITE})
    local on = (t // 16) % 2 == 0
    rect(40, 200, 120, 40, on and Z.rgb("red", true) or Z.rgb("yellow", true))
    rect(48, 208, 104, 24, on and Z.rgb("yellow", true) or Z.rgb("red", true))
    text(lang.tr("ex_flash"), 180, 214, {font = H.F.small, color = Z.BWHITE})
  else
    rect(16, 16, 448, 256, Z.BLACK)
    for i = 1, 5 do body("ex_p4_" .. i, 30 + (i - 1) * 30) end
    for i = 0, 27 do -- the beeper's square wave
      rect(40 + i * 16, 232 - ((i // 1 % 2 == 0) and 24 or 0), 16, 2, Z.rgb("green", true))
      if i < 27 then rect(55 + i * 16, 208, 2, 26, Z.rgb("green", true)) end
    end
  end
end

return E
