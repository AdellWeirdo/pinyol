-- explain: "Cómo funciona", from the console's menu. The game stands still and is taken apart on the screen, with what
-- the Game Boy did: its layers one by one, the 8x8 tiles everything is made of (any tile of this screen, magnified),
-- the sprites the video chip would count (forty, ten to a line), the four tones and the way a fade moves them, and
-- the four voices of its sound. Everything shown is this game's own, live: the numbers are the ones of the screen.
local C = require("core.const")
local W = require("core.world")
local S = require("core.spr")
local Pal = require("core.pal")
local Game = require("core.game")
local Music = require("core.music")
local Sound = require("core.sound")
local lang = require("lang")
local TP = require("data.tilepix")
local Ex = {}

Ex.active = false
local PAGES = {"layers", "tiles", "sprites", "tones", "sound"}
local page, sub, t = 1, 1, 0
local cur = {x = 14, y = 8}   -- the tile under the cursor, in tiles of the screen (30 x 18)
local fade_level = 0
local voice_t = {0, 0, 0, 0}  -- ticks since each voice was played (for its meter)

local LAYER_MASKS -- built on first use: BG0 etc. are the engine's constants

local function masks()
  if not LAYER_MASKS then
    LAYER_MASKS = {ALL, BG1 | BACK, BG2 | BACK, OBJ | BACK, BG0 | BACK}
  end
  return LAYER_MASKS
end

function Ex.enter()
  Ex.active = true
  page, sub, t, fade_level = 1, 1, 0, 0
  cur.x, cur.y = 14, 8
  achieve("curioso")
end

function Ex.leave()
  Ex.active = false
  show(ALL)
  Pal.fade("light", 0)
  for v = 0, 3 do tone(v) end
end

-- the four voices: what the console's channels did (two pulses of different widths, a wave, noise)
local WAVE = {0, 2, 4, 6, 8, 10, 12, 14, 15, 14, 12, 10, 8, 6, 4, 2, 0, 2, 4, 6, 8, 10, 12, 14, 15, 14, 12, 10, 8, 6, 4, 2}
local function play_voice(i)
  voice_t[i] = 0
  if i == 1 then tone(0, "E5", {wave = "square", duty = 0.5, decay = 0.25, vol = 0.35})
  elseif i == 2 then tone(1, "B4", {wave = "square", duty = 0.25, decay = 0.25, vol = 0.35})
  elseif i == 3 then tone(2, "E3", {wave = WAVE, sustain = 0, decay = 0.4, vol = 0.45})
  else tone(3, 1800, {wave = "noise", decay = 0.12, vol = 0.35}) end
end

function Ex.update()
  t = t + 1
  for i = 1, 4 do voice_t[i] = voice_t[i] + 1 end
  if btnp("b") or btnp("start") then Ex.leave() return true end
  if btnp("c") then page = page % #PAGES + 1 sub = 1 Sound.play("select") end
  local name = PAGES[page]
  if name == "layers" then
    if btnp("a") then sub = sub % 5 + 1 end
  elseif name == "tiles" then
    if btnp("left", 14, 3) then cur.x = math.max(0, cur.x - 1) end
    if btnp("right", 14, 3) then cur.x = math.min(29, cur.x + 1) end
    if btnp("up", 14, 3) then cur.y = math.max(2, cur.y - 1) end
    if btnp("down", 14, 3) then cur.y = math.min(19, cur.y + 1) end
  elseif name == "tones" then
    if btnp("a") then fade_level = (fade_level + 1) % 4 Pal.fade("light", fade_level) end
    if btnp("up") then Pal.set_mode(Pal.mode + 1) end
    if btnp("down") then Pal.set_mode(Pal.mode - 1) end
  elseif name == "sound" then
    if btnp("a") then play_voice(1) end
    if btnp("up") then play_voice(2) end
    if btnp("down") then play_voice(3) end
    if btnp("left") or btnp("right") then play_voice(4) end
  end
  return false
end

-- the tile of the screen under the cursor, as the layers have it: its number and flips on the ground and the front
local function tile_at(tx, ty, layer)
  local e = mget(layer, W.sx * 30 + tx, W.sy * 18 + ty - 2)
  return e & 0x3FF, e & 0x400 ~= 0, e & 0x800 ~= 0
end

local function draw_tile(tileset, layer_name, n, hf, vf, x, y, k)
  local row = TP[tileset][layer_name][n + 1]
  if not row then return end
  for py = 0, 7 do
    for px = 0, 7 do
      local sx, sy = hf and 7 - px or px, vf and 7 - py or py
      local v = tonumber(row:sub(sy * 8 + sx + 1, sy * 8 + sx + 1))
      if v and v > 0 then rect(x + px * k, y + py * k, k, k, Pal.tone(v)) end
    end
  end
  box(x - 1, y - 1, 8 * k + 2, 8 * k + 2, Pal.tone(4))
end

local function panel(lines, y)
  local ink = Pal.tone(4)
  local h = #lines * 20 + 14
  y = y or (320 - h - 6)
  rect(6, y, 468, h, Pal.tone(1))
  box(6, y, 468, h, ink)
  box(9, y + 3, 462, h - 6, ink)
  for i, l in ipairs(lines) do text(l, 16, y + 8 + (i - 1) * 20, {font = "ps", color = ink}) end
end

local function wrap(str, width)
  local lines, line = {}, ""
  for word in str:gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if textw(try, "ps") > width and line ~= "" then lines[#lines + 1] = line line = word else line = try end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

local function header()
  local ink = Pal.tone(4)
  rect(0, 0, 480, 32, Pal.tone(1))
  rect(0, 30, 480, 2, ink)
  text(lang.tr("ex_t" .. page), 14, 8, {font = "ps", color = ink})
  text("C " .. page .. "/" .. #PAGES, 466, 8, {font = "ps", color = ink, align = "right"})
end

function Ex.draw()
  local Play = require("core.play")
  show(masks()[page == 1 and sub or 1])
  Play.draw()
  local name = PAGES[page]
  local ink = Pal.tone(4)
  if name == "layers" then
    panel(wrap(lang.tr("ex_1_" .. sub), 440))
  elseif name == "tiles" then
    -- the 8x8 grid over the screen, a cursor, and the tile under it magnified
    local g = Pal.tone(2)
    for x = 0, 480, 16 do line(x, 32, x, 320, g) end
    for y = 32, 320, 16 do line(0, y, 480, y, g) end
    box(cur.x * 16, cur.y * 16, 16, 16, ink)
    box(cur.x * 16 + 1, cur.y * 16 + 1, 14, 14, ink)
    local n, hf, vf = tile_at(cur.x, cur.y, 1)
    local nf, hff, vff = tile_at(cur.x, cur.y, 2)
    local count = W.area.screen_tiles[W.sx .. "," .. W.sy] or 0
    local ts = W.area.tileset
    local px = cur.x < 15 and 330 or 20
    rect(px - 12, 44, 140 + 24, 160, Pal.tone(1))
    box(px - 12, 44, 164, 160, ink)
    draw_tile(ts, "ground", n, hf, vf, px, 56, 8)
    if nf ~= 0 then draw_tile(ts, "front", nf, hff, vff, px + 70, 56, 2) end
    text(lang.tr("ex_2_n", {n = n}), px - 4, 130, {font = "ps", color = ink})
    panel(wrap(lang.tr("ex_2_a", {n = count}), 440))
  elseif name == "sprites" then
    local per, maxline, entries = {}, 0, 0
    for y = 0, 143 do per[y] = 0 end
    for i, r in ipairs(S.rects) do
      local x, y, w, h = r[1], r[2] - C.HUD, r[3], r[4]
      if y > 143 or y + h < 0 then goto skip end
      do
        local cols, rows = (w + 7) // 8, (h + 15) // 16
        entries = entries + cols * rows
        for ly = math.max(0, y), math.min(143, y + h - 1) do per[ly] = per[ly] + cols end
        box(x * 2, (y + C.HUD) * 2, w * 2, h * 2, ink)
        text(tostring(i), x * 2 + 2, (y + C.HUD) * 2 + 2, {font = "ps", color = ink})
      end
      ::skip::
    end
    for y = 0, 143 do if per[y] > maxline then maxline = per[y] end end
    -- a strip down the right: how many pieces cross each line; the limit is 10
    local gx = 452
    for y = 0, 143 do
      local v = math.min(per[y], 14)
      if v > 0 then rect(gx - v * 2, (y + C.HUD) * 2, v * 2, 2, per[y] > 10 and Pal.tone(4) or Pal.tone(3)) end
    end
    line(gx - 20, 32, gx - 20, 320, ink)
    panel(wrap(lang.tr("ex_3_a", {n = entries, m = maxline}), 440))
  elseif name == "tones" then
    local bw = 90
    for i = 1, 4 do
      local x = 20 + (i - 1) * (bw + 12)
      rect(x, 60, bw, 70, Pal.tone(i))
      box(x, 60, bw, 70, ink)
      text(tostring(i - 1), x + bw // 2, 140, {font = "ps", color = ink, align = "center"})
    end
    local bgp = ({"11 10 01 00", "10 01 00 00", "01 00 00 00", "00 00 00 00"})[fade_level + 1]
    text("BGP " .. bgp, 20, 168, {font = "ps", color = ink})
    text(Pal.name(), 20, 190, {font = "ps", color = ink})
    panel(wrap(lang.tr("ex_4_a"), 440))
  elseif name == "sound" then
    local names = {"PULSO 1", "PULSO 2", "ONDA", "RUIDO"}
    for i = 1, 4 do
      local x = 20 + (i - 1) * 112
      rect(x, 48, 104, 120, Pal.tone(1))
      box(x, 48, 104, 120, ink)
      text(({lang.tr("ex_v1"), lang.tr("ex_v2"), lang.tr("ex_v3"), lang.tr("ex_v4")})[i], x + 52, 54, {font = "ps", color = ink, align = "center"})
      -- the shape of the voice
      local cx, cy = x + 8, 112
      if i == 1 or i == 2 then
        local duty = i == 1 and 0.5 or 0.25
        local pts = {}
        local w = 88
        local a = w * duty
        line(cx, cy + 20, cx, cy - 20, ink) line(cx, cy - 20, cx + a, cy - 20, ink) line(cx + a, cy - 20, cx + a, cy + 20, ink)
        line(cx + a, cy + 20, cx + w, cy + 20, ink)
      elseif i == 3 then
        for k = 1, 31 do
          line(cx + (k - 1) * 2.7, cy + 20 - WAVE[k] * 2.6, cx + k * 2.7, cy + 20 - WAVE[k + 1] * 2.6, ink)
        end
      else
        math.randomseed(7)
        local py = cy
        for k = 0, 43 do
          local ny = cy + math.random(-20, 20)
          line(cx + k * 2, py, cx + k * 2 + 2, ny, ink)
          py = ny
        end
        math.randomseed(ticks())
      end
      -- a meter that jumps when the voice is played
      local lvl = math.max(0, 1 - voice_t[i] / 20)
      rect(x + 4, 160 - math.floor(lvl * 30), 96, math.floor(lvl * 30) + 1, Pal.tone(3))
    end
    local song = Music.now and lang.tr("ex_song", {name = Music.now}) or ""
    panel(wrap(lang.tr("ex_5_a") .. " " .. song, 440))
  end
  header()
end

return Ex
