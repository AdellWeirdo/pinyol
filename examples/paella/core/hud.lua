-- hud: the status line, Metal Slug's way: the score at the top left with the lives, bombs and the weapon's time under it, the boss's life bar, the tractor's, a blinking GO arrow.
local C = require("core.const")
local S = require("core.spr")
local Run = require("core.run")
local Boss = require("core.boss")
local Tractor = require("core.tractor")
local lang = require("lang")
local H = {}

local FONT = "arcade"

-- label(str, x, y, {scale, fit, color, gradient, align}): arcade-font text; `fit` is the widest it may be: the scale shrinks until it fits
local function label(str, x, y, o)
  o = o or {}
  local scale = o.scale or 1
  if o.fit then
    while scale > 1 and textw(str, {font = FONT, scale = scale}) > o.fit do scale = scale - 1 end
  end
  text(str, x, y, {font = FONT, color = o.color or 0xFFE070, gradient = o.gradient, outline = 0x200010, align = o.align, scale = scale})
end
H.label = label

-- a paper panel of the game's own interface kit (art/ui.png), stretched to w x h keeping its corners
function H.panel(x, y, w, h)
  local sz = S.sheets.ui.sizes.panel
  S.nine("ui", "panel", x, y, w, h, 14, sz[1], sz[2])
end

function H.draw(play, t)
  local c = play.chef
  S.draw("ui", "score", 6, 4, {})
  label(string.format("%07d", Run.score), 22, 20, {color = 0xFFE070})
  S.draw("ui", "life", 10, 58, {})
  label("x" .. math.max(0, c.lives), 42, 62, {color = 0xFFFFFF})
  S.draw("ui", "gauge", 84, 58, {})
  label(string.format("%02d", c.grenades), 114, 62, {color = 0xFFFFFF})
  if c.up_shots > 0 then
    rect(14, 92, 80, 8, 0x201010)
    rect(15, 93, math.floor(78 * c.up_shots / 60), 6, 0xF0C020)
  end
  if c.shield > 0 then label(lang.tr("hud_shield"), 14, 104, {color = 0x60E0FF}) end
  -- the tractor's bar
  if c.vehicle then
    local v = c.vehicle
    label(lang.tr("hud_tractor"), 14, 122, {color = 0xFFFFFF})
    S.draw("ui", "bar", 10, 140, {})
    for i = 1, 8 do rect(22 + (i - 1) * 14, 148, 12, 12, i <= v.hp and 0x40E060 or 0x203020) end
  end
  if Boss.active and not Boss.done then
    local bx, by = 154, 256
    S.draw("ui", "boss", bx, by, {})
    local w = 118
    rect(bx + 42, by + 22, w, 10, 0x201008)
    rect(bx + 42, by + 22, math.floor(w * math.max(0, Boss.hp) / Boss.max_hp), 10, Boss.hp < Boss.max_hp * 0.33 and 0xF04030 or 0xF0A020)
    label(lang.tr("boss_name"), 240, 238, {align = "center", color = 0xFFFFFF})
  end
  if play.go_t > 0 and (play.go_t // 20) % 2 == 0 then
    label("GO!", 400, 130, {scale = 2, gradient = 0xFF5020})
    label(">>>", 400, 170, {scale = 2})
  end
  if play.banner_t > 0 then
    local z = require("core.level").ZONES[play.zone]
    local msg = Boss.active and lang.tr("boss_banner") or z.name[lang.code] or z.name.es
    local a = math.min(1, play.banner_t / 40)
    if a > 0.2 then label(msg, 240, 70, {align = "center", scale = 2, fit = 380, gradient = 0xFF6020}) end
    if Boss.active and (t // 10) % 2 == 0 then label("WARNING", 240, 60, {align = "center", scale = 2, color = 0xFF4030}) end
  end
end

return H
