-- explain: "Cómo funciona", from the console's menu. Four pages about what made a pocket LCD game what it was:
--   1 every shape at once (the factory's test): all the figures of the glass ON, to see there are only so many
--   2 one figure, one place: A steps a ball along the places it can be, and each place is a fixed shape
--   3 the digits: seven segments, a, b, c... lit one at a time, and the clock built of them
--   4 the beeper: a piezo that makes one note; A plays each sound of the game with its frequency
-- Left and right: page. START: back to the game.
local lang = require("lang")
local E = {}

E.hook = function(id) end
local PAGES = 4
local page, sel, t = 1, 1, 0
local SOUNDS = {{"SFX_STEP", 1760}, {"SFX_CATCH", 2300}, {"SFX_MISS", 330}, {"SFX_BONUS", 1500}}
local GX, GY, GW = 44, 36, 392

function E.enter() page, sel, t = 1, 1, 0 E.hook("curioso") end

function E.update()
  t = t + 1
  if btnp("left") and page > 1 then page = page - 1 sel = 1 end
  if btnp("right") and page < PAGES then page = page + 1 sel = 1 end
  if page == 2 and btnp("a") then sel = sel % 12 + 1 sfx("SFX_STEP") end
  if page == 4 then
    if btnp("up") then sel = (sel - 2) % #SOUNDS + 1 end
    if btnp("down") then sel = sel % #SOUNDS + 1 end
    if btnp("a") then sfx(SOUNDS[sel][1]) end
  end
  return btnp("start")
end

local function say(s, x, y, font, c, align) text(s, x, y, {font = font, color = c, align = align or "center"}) end

function E.draw(juggler, ball, digits, colon, arc, HL, HR, ON, GHOST)
  rect(GX, GY, GW, 220, 0xC4C9B0) -- the picture is out: the bare glass, so the shapes are all there is
  if page == 1 then
    juggler(ON, true, false) juggler(ON, false, true)
    for k = 1, 5 do for _, dir in ipairs({1, -1}) do local x, y = arc(k, dir) ball(x, y, ON) end end
    digits("8888", ON) colon(ON)
  elseif page == 2 then
    juggler(GHOST, false, false)
    local places = {}
    for k = 1, 5 do places[#places + 1] = {arc(k, 1)} end
    places[#places + 1] = {HR[1] + 10, HR[2] - 4}
    for k = 5, 1, -1 do places[#places + 1] = {arc(k, -1)} end
    places[#places + 1] = {HL[1] - 10, HL[2] - 4}
    for i, p in ipairs(places) do ball(p[1], p[2], i == sel and ON or GHOST) end
    digits("8888", GHOST) colon(GHOST)
  elseif page == 3 then
    local seg = (t // 30) % 8 -- the segments of a big digit one at a time, then all
    local letters = "abcdefg"
    local x, y = 80, 90
    local R = {a = {2, 0, 14, 3}, b = {16, 2, 3, 14}, c = {16, 18, 3, 14}, d = {2, 32, 14, 3}, e = {-1, 18, 3, 14}, f = {-1, 2, 3, 14}, g = {2, 16, 14, 3}}
    for s2 in letters:gmatch(".") do
      local r = R[s2]
      local on = seg == 7 or letters:sub(seg + 1, seg + 1) == s2
      rect(x + r[1] * 3, y + r[2] * 3, r[3] * 3, r[4] * 3, on and ON or GHOST)
    end
    if seg < 7 then say(letters:sub(seg + 1, seg + 1), x + 24, y + 116, "pocket_lcd_title", ON) end
    local c = clock()
    digits(c and string.format("%02d%02d", c.hour, c.min) or "----", ON)
    if (t // 30) % 2 == 0 then colon(ON) end
  else
    for i, s2 in ipairs(SOUNDS) do
      local y = GY + 50 + (i - 1) * 26
      rect(150, y, 200, 20, i == sel and ON or GHOST)
      say(s2[2] .. " Hz", 250, y + 5, "pocket_lcd_small", i == sel and 0xC4C9B0 or ON)
    end
  end
  -- the title and the sentence on a clear band at the bottom of the glass, the way to move on at its top corner
  rect(GX, GY + 164, GW, 56, 0xC4C9B0)
  say(lang.tr("ex_title_" .. page), 240, GY + 172, "pocket_lcd_title", ON)
  say(lang.tr("ex_p" .. page, {n = sel, m = 12}), 240, GY + 198, "pocket_lcd_small", ON)
  text(lang.tr("ex_nav", {n = page, m = PAGES}), GX + GW - 8, GY + 8, {font = "pocket_lcd_small", color = ON, align = "right"})
end

return E
