-- explain: "Cómo funciona", from the console's menu or the title. The stage stands still and the CPS2's tricks are shown with this game's own sprites: the fifteen colours of a character
-- and the second colours borrowed from another palette, the floor of the street (how far down a character is decides what is in front), how the parts change the fight, and how many pictures
-- a frame is made of.
local C = require("core.const")
local S = require("core.spr")
local Run = require("core.run")
local Hud = require("core.hud")
local lang = require("lang")
local Ex = {}

Ex.active = false
local PAGES = {"palette", "depth", "parts", "sprites"}
local page, t = 1, 0
local play
local BODY_H = {} -- each page's text height, learnt when drawn: the panel is as tall as its text

function Ex.enter(p)
  play = p
  Ex.active, page, t = true, 1, 0
  achieve("curioso")
end

function Ex.leave() Ex.active = false end

function Ex.update()
  t = t + 1
  if btnp("b") or btnp("start") then Ex.leave() return true end
  if btnp("a") or btnp("c") or btnp("right") then page = page % #PAGES + 1 end
  if btnp("left") then page = (page - 2) % #PAGES + 1 end
  return false
end

local PART_NAMES = {"part_hammer", "part_springs", "part_wrench", "part_boiler"}
local PART_KEYS = {"hammer", "springs", "wrench", "boiler"}

function Ex.draw()
  local pg = PAGES[page]
  play.draw_world()
  local count = S.count
  local id = play.hero.id
  shade(0, 0, 480, 320)
  Hud.panel(10, 8, 460, 38 - 8 + (BODY_H[pg] or 100) + 30)
  text(lang.tr("ex_" .. pg .. "_title"), 240, 14, {font = "bold", align = "center", color = 0x8a3a08})
  local _, h = text(lang.tr("ex_" .. pg .. "_text", {n = count, max = 380, line = 96, ymin = C.Y_MIN, ymax = C.Y_MAX}), 240, 38, {font = "main", align = "center", width = 396, color = 0x402010})
  BODY_H[pg] = h
  if pg == "palette" then
    S.draw(id, "select_0", 140, 290, {})
    S.draw(id, "select_0", 340, 290, {alt = true})
    Hud.label("15", 240, 190, {align = "center", scale = 3, gradient = 0xFFB020})
    text("<- pal ->", 240, 240, {font = "main", align = "center", color = 0xFFFFFF, outline = 0x200010})
  elseif pg == "depth" then
    for i, y in ipairs({C.Y_MIN + 6, 272, C.Y_MAX}) do
      rect(0, y, 480, 1, 0xFFE070)
      text(tostring(y), 8, y - 12, {font = "main", color = 0xFFE070, outline = 0x200010})
      S.draw(i == 2 and id or "rodete", i == 2 and "idle_" .. (t // 9) % 4 or "idle_0", 110 + i * 110, y, {flip = i ~= 2})
    end
  elseif pg == "parts" then
    for i, nm in ipairs(PART_NAMES) do
      S.draw("parts", nm, 70 + (i - 1) * 105, 190, {})
      text(lang.tr("part_" .. PART_KEYS[i]), 70 + (i - 1) * 105, 198, {font = "bold", align = "center", color = 0xFFFFFF, outline = 0x200010})
      textbox(lang.tr("partd_" .. PART_KEYS[i]), 70 + (i - 1) * 105 - 52, 212, 104, 78, {font = "main", align = "center", color = 0xFFFFFF, outline = 0x200010})
    end
  end
  text(lang.tr("ex_help"), 240, 292, {font = "main", align = "center", color = 0xFFFFFF, outline = 0x200010})
end

return Ex
