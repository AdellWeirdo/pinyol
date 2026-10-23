-- explain: "Cómo funciona", from the console's menu. Four pages about what a PICO-8 cartridge is made of, shown on the level you were playing:
--   1 the palette: sixteen colours and no more; pick one and swap it for another with pal(), live
--   2 the map: the level is 16x16 numbers, each the number of an 8x8 sprite
--   3 four channels: the music playing, voice by voice, with a bar that jumps on each note
--   4 fades: a fade is a palette change, step by step to black; up and down move through the levels of the fade
-- Left and right: page.  START: back to the game.
local V = require("core.view")
local F = require("core.fx")
local Mu = require("core.music")
local Rules = require("core.rules")
local lang = require("lang")
local E = {}

E.hook = function(id) end
local PAGES = 4
local page, cur, t = 1, 8, 0
local FONT = {title = "pico8_title", body = "pico8_body", small = "pico8_small"}
local swaps = {}
local NAMES = {[0] = "negro", "azul", "violeta", "verde", "marrón", "gris", "claro", "blanco", "rojo", "naranja", "amarillo", "verde cl.",
               "azul cl.", "lavanda", "rosa", "piel"}
local lv_, st_ = nil, nil
local MAPID = {["#"] = 1, ["."] = 2, S = 2, o = 3, ["^"] = 4, E = 5, m = 6, c = 7, k = 8, D = 9, ["1"] = 10, ["2"] = 11, u = 12, d = 12, l = 12, r = 12}

local function map_canvas()
  canvas("MAPNUM", 256, 256)
  target("MAPNUM")
  for y = 0, 15 do
    for x = 0, 15 do
      local c = lv_.g[y + 1][x + 1]
      local n = MAPID[c] or 0
      text(string.format("%x", n), x * 16 + 4, y * 16 + 3, {font = FONT.body, color = F.P8[c == "#" and 13 or c == "." and 5 or 10]})
    end
  end
  target()
end

function E.enter(lv, st, hist)
  lv_, st_ = lv, st
  page, cur, t = 1, 8, 0
  swaps = {}
  F.fade(0) F.unswap()
  E.hook("curioso")
  Mu.play("tumba_1")
  map_canvas()
end

function E.leave() F.fade(0) F.unswap() end

local function say(s, x, y, font, colour, align) text(s, x, y, {font = font or FONT.body, color = colour or F.P8[7], align = align}) end

-- a sentence in the right margin, wrapped to its width; returns the y where the next starts
local function note(key, y, colour)
  local line = ""
  local lines = {}
  for word in lang.tr(key):gmatch("%S+") do
    if #line + #word + 1 > 19 and line ~= "" then lines[#lines + 1] = line line = word else line = line == "" and word or (line .. " " .. word) end
  end
  if line ~= "" then lines[#lines + 1] = line end
  for _, l in ipairs(lines) do say(l, 392, y, FONT.small, colour or F.P8[6]) y = y + 12 end
  return y + 8
end

function E.update()
  t = t + 1
  if btnp("left") and page > 1 then page = page - 1 end
  if btnp("right") and page < PAGES then page = page + 1 end
  if page == 1 then
    if btnp("up") then cur = (cur - 1) % 16 end
    if btnp("down") then cur = (cur + 1) % 16 end
    if btnp("a") then
      swaps[cur] = ((swaps[cur] or cur) + 1) % 16
      F.swap(cur, swaps[cur])
    end
    if btnp("b") then swaps = {} F.unswap() end
  elseif page == 4 then
    if btnp("up") then F.fade(math.max(0, F.level - 1)) end
    if btnp("down") then F.fade(math.min(5, F.level + 1)) end
  end
  return btnp("start")
end

function E.draw(lv, st)
  -- the level stays where it is (the map layer), the margins and the top say what the page shows
  rect(0, 0, 480, 32, F.P8[0])
  say(lang.tr("ex_title_" .. page), 240, 8, FONT.title, F.P8[10], "center")
  rect(0, 288, 480, 32, F.P8[0])
  say(lang.tr("ex_nav", {n = page, m = PAGES}), 240, 298, FONT.small, F.P8[12], "center")
  rect(0, 32, 112, 256, F.P8[0]) rect(368, 32, 112, 256, F.P8[0])
  if page == 1 then
    for i = 0, 15 do
      local x, y = 6 + (i % 4) * 26, 50 + (i // 4) * 30
      rect(x, y, 24, 24, F.P8[7]) -- the real colour of the index (the game's own, before any swap)
      rect(x + 1, y + 1, 22, 22, F.P8[swaps[i] or i])
      say(tostring(i), x + 12, y + 8, FONT.small, (i == 0 or i == 1 or i == 2 or i == 5 or i == 3 or i == 4) and F.P8[7] or F.P8[0], "center")
      if i == cur then rect(x - 2, y - 2, 28, 2, F.P8[10]) rect(x - 2, y + 24, 28, 2, F.P8[10]) rect(x - 2, y - 2, 2, 28, F.P8[10]) rect(x + 24, y - 2, 2, 28, F.P8[10]) end
    end
    local y = note("ex_p1a", 50, F.P8[7])
    y = note("ex_p1b", y) y = note("ex_p1c", y) note("ex_p1d", y)
    say("pal(" .. cur .. "," .. (swaps[cur] or cur) .. ")", 392, 190, FONT.body, F.P8[10])
  elseif page == 2 then
    img("MAPNUM", 112, 32)
    local y = note("ex_p2a", 50, F.P8[7])
    note("ex_p2b", y)
    say("mget(x,y)", 392, 190, FONT.body, F.P8[10])
  elseif page == 3 then
    for v = 1, 4 do
      local y = 60 + (v - 1) * 52
      say("CH" .. (v - 1), 120, y, FONT.small, F.P8[13])
      say(lang.tr("ch_" .. v), 120, y + 14, FONT.body, F.P8[7])
      rect(232, y + 6, 124, 14, F.P8[1])
      rect(232, y + 6, math.floor(124 * Mu.level[v]), 14, ({F.P8[8], F.P8[12], F.P8[11], F.P8[10]})[v])
    end
    local y = note("ex_p3a", 50, F.P8[7])
    note("ex_p3b", y)
  else
    say(lang.tr("ex_p4a"), 120, 50, FONT.small, F.P8[7])
    say(lang.tr("ex_p4b"), 120, 66, FONT.small, F.P8[6])
    say(lang.tr("ex_p4c"), 120, 82, FONT.small, F.P8[6])
    for i = 0, 5 do
      rect(120 + i * 38, 220, 34, 34, F.P8[i <= F.level and 10 or 5])
      say(tostring(i), 120 + i * 38 + 17, 232, FONT.body, F.P8[0], "center")
    end
    say("fade level " .. F.level, 240, 262, FONT.body, F.P8[7], "center")
  end
end

return E
