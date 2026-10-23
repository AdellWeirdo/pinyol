-- explain: "Cómo funciona", from the console's menu. The level stands still and is taken apart: its four layers one by one, the palette banks that recolour one
-- picture, the sprites the video chip would count (128, and how many fit in a line), the effects drawn a line at a time. Everything shown is this game's own, live.
local S = require("core.spr")
local W = require("core.world")
local Hero = require("core.hero")
local lang = require("lang")
local Ex = {}

Ex.active = false
local PAGES = {"layers", "banks", "sprites", "lines"}
local page, sub, t = 1, 1, 0
local play
local MASKS

function Ex.enter(p)
  play = p
  Ex.active = true
  page, sub, t = 1, 1, 0
  MASKS = {ALL, BG3 | BACK, BG2 | BACK, BG1 | BACK, BG0 | BACK, OBJ | BACK}
  achieve("curioso")
end

function Ex.leave()
  Ex.active = false
  show(ALL)
  line_off()
end

function Ex.update()
  t = t + 1
  if btnp("b") or btnp("start") then Ex.leave() return true end
  if btnp("c") or btnp("a") then page = page % #PAGES + 1 sub = 1 end
  if btnp("right") then sub = sub + 1 end
  if btnp("left") then sub = math.max(1, sub - 1) end
  return false
end

local function worst_line()
  local n = {}
  local worst = 0
  for _, r in ipairs(S.rects) do
    for y = math.max(0, r[2]), math.min(159, r[2] + r[4] - 1) do
      n[y] = (n[y] or 0) + r[3]
      if n[y] > worst then worst = n[y] end
    end
  end
  return worst
end

function Ex.draw()
  local pg = PAGES[page]
  if pg == "layers" then
    local k = (sub - 1) % #MASKS + 1
    show(MASKS[k])
  else
    show(ALL)
  end
  play.draw(t)
  if pg == "banks" then
    local names = {"zurron", "zurron_fuego", "zurron_golpe", "zurron_hinchado"}
    S.begin()
    for i, b in ipairs(names) do
      S.draw("HERO", "idle_" .. ((t // 10) % 6), 30 + (i - 1) * 46, 60, {bank = b})
    end
  end
  panel(8, 8, 464, 128)
  text(lang.tr("ex_" .. pg .. "_title"), 240, 16, {font = "gba_body", align = "center", color = 0x8a3a08})
  local info = {}
  if pg == "layers" then
    local k = (sub - 1) % #MASKS + 1
    info = {n = k}
  elseif pg == "sprites" then
    info = {n = S.n, max = 128, line = worst_line(), budget = 1210}
  end
  text(lang.tr("ex_" .. pg .. "_text", info), 240, 44, {font = "gba_body", align = "center", color = 0x3a1c08, width = 440})
  text(lang.tr("ex_help"), 240, 300, {font = "gba_small", align = "center", color = 0xFFFFFF, outline = 0x301808})
end

return Ex
