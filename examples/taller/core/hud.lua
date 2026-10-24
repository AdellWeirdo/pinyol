-- hud: the status of the player, an arcade way: the hero's name and life bar, the lives, the steam gauge (a special when full), the part being worn with its time, the score, the
-- boss's life bar, a blinking GO arrow and the stage's name.
local C = require("core.const")
local S = require("core.spr")
local Run = require("core.run")
local Boss = require("core.boss")
local L = require("core.level")
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

-- a parchment panel of the game's own interface kit (art/ui.png), stretched to w x h keeping its corners
function H.panel(x, y, w, h)
  local sz = S.sheets.ui.sizes.panel
  S.nine("ui", "panel", x, y, w, h, 14, sz[1], sz[2])
end

local PART_ICON = {hammer = "part_hammer", springs = "part_springs", wrench = "part_wrench", boiler = "part_boiler"}

local function bar(x, y, w, h, frac, color, back)
  rect(x - 2, y - 2, w + 4, h + 4, 0x100810)
  rect(x, y, w, h, back or 0x401818)
  rect(x, y, math.floor(w * math.max(0, math.min(1, frac))), h, color)
end

function H.draw(play, t)
  local h = play.hero
  label(lang.tr("hero_" .. h.id .. "_name"), 16, 8, {color = 0xFFFFFF})
  -- the life gauge: the brass frame with its fill inside
  S.draw("ui", "bar", 10, 30, {})
  local frac = math.max(0, math.min(1, h.hp / h.max_hp))
  rect(30, 39, math.floor(93 * frac), 12, frac < 0.3 and 0xF04030 or 0xF0B020)
  S.draw("ui", "life", 150, 31, {})
  label("x" .. math.max(0, h.lives), 182, 34, {color = 0xFFFFFF})
  -- the steam gauge
  local full = h.meter >= C.METER
  S.draw("ui", "gauge", 10, 66, {})
  bar(40, 74, 100, 6, h.meter / C.METER, full and ((t // 6) % 2 == 0 and 0xFFFFFF or 0x60D0FF) or 0x3090D0, 0x182030)
  if full then label(lang.tr("hud_special"), 150, 66, {color = (t // 8) % 2 == 0 and 0xFFFFFF or 0x60D0FF}) end
  S.draw("ui", "score", 6, 98, {})
  label(string.format("%07d", Run.score), 22, 116, {color = 0xFFE070})
  if h.part then
    S.draw("parts", PART_ICON[h.part], 34, 192, {})
    bar(70, 178, 80, 6, h.part_t / C.PART_TICKS, require("core.hero").PARTS[h.part].color, 0x201010)
    label(lang.tr("part_" .. h.part), 70, 156, {color = 0xFFFFFF})
  end
  if Boss.active and not Boss.done then
    local bx, by = 162, 252
    S.draw("ui", "boss", bx, by, {})
    local w = 100
    rect(bx + 40, by + 21, w, 12, 0x201008)
    rect(bx + 40, by + 21, math.floor(w * math.max(0, Boss.hp) / Boss.max_hp), 12, Boss.hp < Boss.max_hp * 0.4 and 0xF04030 or 0xF0A020)
    label(lang.tr("boss_name"), 240, 232, {align = "center", color = 0xFFFFFF})
  end
  if play.go_t > 0 and (play.go_t // 20) % 2 == 0 and play.state == "play" then
    label("GO!", 434, 120, {scale = 2, align = "center", gradient = 0xFF5020})
    label(">>>", 434, 160, {scale = 2, align = "center"})
  end
  if play.banner_t > 0 then
    local st = play.stage()
    local msg = Boss.active and lang.tr("boss_banner") or (st.name[lang.code] or st.name.es)
    if play.banner_t > 20 then
      label(lang.tr("stage_n", {n = Run.stage}), 240, 124, {align = "center", color = 0xFFFFFF})
      label(msg, 240, 146, {align = "center", scale = 2, fit = 420, gradient = 0xFF6020})
    end
    if Boss.active and (t // 10) % 2 == 0 then label("WARNING", 240, 100, {align = "center", scale = 2, color = 0xFF4030}) end
  end
end

return H
