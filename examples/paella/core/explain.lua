-- explain: "Cómo funciona", from the console's menu or the title. The mission stands still and the Neo Geo's tricks are shown with this game's own sprites: how many pictures a frame
-- is made of (the chip drew 380, 96 on a line), how a chef is one picture a frame, painted whole, how a sprite could only be shrunk and never grown, and how a handful of 15-colour
-- palettes dressed the same picture many ways.
local C = require("core.const")
local S = require("core.spr")
local Run = require("core.run")
local Hud = require("core.hud")
local lang = require("lang")
local Ex = {}

Ex.active = false
local PAGES = {"sprites", "frames", "shrink", "palettes"}
local page, t, sub = 1, 0, 1
local play

function Ex.enter(p)
  play = p
  Ex.active, page, t, sub = true, 1, 0, 1
  achieve("curioso")
end

function Ex.leave() Ex.active = false end

function Ex.update()
  t = t + 1
  if btnp("b") or btnp("start") then Ex.leave() return true end
  if btnp("a") or btnp("c") then page = page % #PAGES + 1 sub = 1 end
  if btnp("left") then sub = math.max(1, sub - 1) end
  if btnp("right") then sub = sub + 1 end
  return false
end

local TINTS = {0xFFFFFF, 0xFFB0B0, 0xB0FFB0, 0xB0C8FF, 0xFFE890, 0xE0B0FF}

function Ex.draw()
  local pg = PAGES[page]
  play.draw_world()
  local chef = play.chef.id
  local count = S.count
  shade(0, 0, 480, 320)
  Hud.panel(10, 8, 460, 104)
  text(lang.tr("ex_" .. pg .. "_title"), 240, 14, {font = "bold", align = "center", color = 0x8a3a08})
  text(lang.tr("ex_" .. pg .. "_text", {n = count, max = 380, line = 96}), 240, 40, {font = "main", align = "center", width = 440, color = 0x402010})
  if pg == "frames" then
    -- a run cycle, frame by frame, side by side, and the same one playing
    for i = 0, 3 do
      S.draw("chef_" .. chef, "run_" .. i, 70 + i * 100, 270, {})
      text(tostring(i + 1), 70 + i * 100, 278, {font = "main", align = "center", color = 0xFFFFFF, outline = 0x200010})
    end
    S.draw("chef_" .. chef, "run_" .. (t // 4) % 6, 430, 270, {})
  elseif pg == "shrink" then
    local scales = {1, 0.75, 0.5, 0.35}
    for i, k in ipairs(scales) do
      local sh = S.sheets["chef_" .. chef]
      local x = 50 + (i - 1) * 110
      local f = sh.frames["select_0"]
      img(sh.pieces and (sh.id .. "_C" .. (f // sh.per)) or sh.id, x, 300 - sh.h * k, {frame = f % (sh.per or 10), scale = k})
    end
    text("1", 90, 304, {font = "main", color = 0xFFFFFF, outline = 0x200010})
  elseif pg == "palettes" then
    for i, tint in ipairs(TINTS) do
      S.draw("chef_" .. chef, "select_" .. (t // 12 + i) % 2, 50 + (i - 1) * 76, 300, {mul = tint, scale = nil})
    end
  end
  text(lang.tr("ex_help"), 240, 300, {font = "main", align = "center", color = 0xFFFFFF, outline = 0x200010})
end

return Ex
