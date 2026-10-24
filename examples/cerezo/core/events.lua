-- events: the scenes of the story, written as scripts (core/cine.lua): the opening, the stone seal giving way, the mole
-- king's entrance, the cherry tree blooming. Where things stand comes from the maps' notes, so a scene is not tied to a place in
-- this file.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local E = require("core.ents")
local Game = require("core.game")
local Pal = require("core.pal")
local FX = require("core.fx")
local Sound = require("core.sound")
local Music = require("core.music")
local Cine = require("core.cine")
local Dialog = require("core.dialog")
local Hero = require("core.hero")
local Things = require("core.things")
local lang = require("lang")
local Ev = {}

Ev.credits_t = nil

-- ------------------------------------------------------------------ the opening
-- the words cut into lines of at most `width` screen pixels
local function wrap_lines(str, width)
  local lines, line = {}, ""
  for word in str:gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if textw(try, "ps") > width and line ~= "" then lines[#lines + 1] = line line = word else line = try end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

-- a few lines of text on a plain screen, each fading in and out
local function crawl(knots)
  for _, k in ipairs(knots) do
    local s = Dialog.story
    s:go(k)
    local lines = {}
    local l = s:line()
    while l do
      for _, ln in ipairs(wrap_lines(l.text, 400)) do lines[#lines + 1] = ln end
      lines[#lines + 1] = ""
      s:next()
      l = s:line()
    end
    Cine.draw_fn = function()
      cls(Pal.tone(1))
      local y = 160 - (#lines * 26) // 2
      for _, ln in ipairs(lines) do
        text(ln, 240, y, {font = "ps", color = Pal.tone(4), align = "center"})
        y = y + 26
      end
    end
    Cine.fade_in("light", 6)
    Cine.wait(160)
    Cine.fade_out("light", 6)
  end
  Cine.draw_fn = nil
end

function Ev.intro(start)
  Music.play("intro", 0)
  Pal.fade("light", 3)
  Cine.run(function()
    crawl({"intro_1", "intro_2", "intro_3"})
    Pal.fade("dark", 3)
    start() -- the game puts the hero in his bed (the area's notes: bed, yaya)
    Cine.wait(10)
    Music.play("house", 0)
    local hero = E.hero
    local notes = W.area.notes
    hero.state = "talk"
    hero.sleeping = true
    hero.x, hero.y = notes.bed_pillow[1] * C.T, notes.bed_pillow[2] * C.T - 4
    Cine.fade_in("dark", 6)
    Cine.wait(40)
    Cine.say("intro_yaya_llama", {pose = true})
    Cine.wait(30)
    -- he wakes: sits up, then stands beside the bed
    hero.sleeping = false
    hero.sitting = true
    Sound.play("select")
    Cine.wait(30)
    hero.sitting = false
    local bx, by = notes.bed_out[1] * C.T, notes.bed_out[2] * C.T - 4
    hero.x, hero.y, hero.face = bx, by, "down"
    Cine.wait(20)
    -- Yaya waits by the table
    local tx, ty = notes.yaya_talk[1] * C.T, notes.yaya_talk[2] * C.T - 4
    Cine.walk(hero, tx, ty, 0.9)
    hero.face = "up"
    Cine.say("intro_cama")
    Cine.say("intro_pala")
    Game.setflag("yaya_met")
    require("core.rewards").get("pala")
    Cine.wait_until(function() return not Dialog.active end)
    Music.play(W.area.notes.music)
    Hero.set(hero, "walk")
  end)
end

-- ------------------------------------------------------------------ the three sockets of the stone seal
Things.kinds.socket = function(def)
  local e = {kind = "socket", x = def.cx * C.T, y = def.cy * C.T, solid = true, hx = 0, hy = 0, hw = 16, hh = 16, sort = 8}
  function e.interact(self, hero)
    local placed = Game.flags["socket_" .. def.n]
    if placed then
      Dialog.start("sello_parcial")
      return
    end
    local used = 0
    for i = 1, 3 do if Game.flags["socket_" .. i] then used = used + 1 end end
    if Game.pits - used <= 0 then
      Dialog.start(used > 0 and "sello_parcial" or "sello_vacio")
      return
    end
    Game.flags["socket_" .. def.n] = true
    W.set(def.cx, def.cy, "semillero_full")
    Sound.play("confirm")
    FX.shake(1, 8)
    if used + 1 >= 3 then Ev.seal_opens() end
  end
  return E.add(e)
end

-- the three sockets sink when the seal gives way (the cells become the path to the door)
local function sockets_sink()
  for _, def in ipairs(W.area.things) do
    if def.kind == "socket" then W.set(def.cx, def.cy, "dirt_a") end
  end
end

function Ev.seal_opens()
  local n = W.area.notes
  Cine.run(function()
    Cine.wait(30)
    Music.stop()
    for i = 1, 6 do FX.shake(2, 20) Sound.play("dig") Cine.wait(20) end
    local ox, oy = n.seal[1], n.seal[2] -- the top-left cell of the 3x3 door
    for r = 0, 2 do
      for c = 0, 2 do W.set(ox + c, oy + r, "caveopen_" .. r .. "_" .. c) end
    end
    FX.dust(ox * C.T + 24, oy * C.T + 40)
    FX.dust(ox * C.T + 8, oy * C.T + 40)
    FX.dust(ox * C.T + 40, oy * C.T + 40)
    Sound.play("secret")
    Cine.wait(40)
    sockets_sink()
    Game.setflag("seal_open")
    Music.play(n.music)
    Cine.say("sello_abierto")
  end)
end

-- ------------------------------------------------------------------ the mole king's entrance (a zone of the boss room)
Things.kinds.zone = function(def)
  if def.flag and Game.flags[def.flag] then return nil end
  local e = {kind = "zone", x = def.cx * C.T, y = def.cy * C.T, hw = 0, hh = 0}
  function e.update(self)
    local h = E.hero
    if h.state ~= "walk" then return end
    if U.overlap(h.x + 4, h.y + 8, 8, 6, def.cx * C.T, def.cy * C.T, (def.w or 1) * C.T, (def.h or 1) * C.T) then
      if def.flag then Game.flags[def.flag] = true end
      self.dead = true
      if def.event == "boss_intro" then Ev.boss_intro() end
    end
  end
  return E.add(e)
end

function Ev.boss_intro()
  Cine.run(function()
    Music.stop()
    local h = E.hero
    Hero.set(h, "talk")
    FX.shake(2, 40)
    Sound.play("dig")
    Cine.wait(50)
    Cine.say("topo_intro")
    Hero.set(h, "walk")
  end)
end

-- ------------------------------------------------------------------ the cherry tree: where the golden cherry is planted
Things.kinds.plant = function(def)
  local e = {kind = "plant", x = def.cx * C.T, y = def.cy * C.T, hw = def.w * C.T, hh = def.h * C.T, hx = 0, hy = 0, ix = def.cx * C.T,
             iy = def.cy * C.T, iw = def.w * C.T, ih = def.h * C.T}
  function e.interact(self, hero)
    if Game.flags.tree_bloomed then return end
    if Game.flags.cereza_dorada then Ev.ending(def) else Dialog.start("higuera_casa") end
  end
  return E.add(e)
end

-- ------------------------------------------------------------------ the ending
local VILLAGERS = {
  {"yaya", -1, 3}, {"higuera", 1, 3}, {"bellota", -2, 5}, {"nogal", 2, 5}, {"sardina", -3, 3}, {"aldeano_a", 3, 3},
  {"aldeano_b", -1, 6}, {"mostaza", 1, 6},
}

function Ev.ending(def)
  local n = W.area.notes
  Cine.run(function()
    local h = E.hero
    Hero.set(h, "talk")
    Cine.say("plantar")
    Music.stop()
    FX.shake(2, 80)
    Sound.play("dig")
    Cine.wait(60)
    -- the tree wakes: the screen goes to light and back, and the tree is in bloom
    Cine.fade_out("light", 8)
    local tx, ty = n.tree[1], n.tree[2]
    for r = 0, 3 do for c = 0, 3 do W.set(tx + c, ty + r, "cherry_bloom_" .. r .. "_" .. c) end end
    Game.setflag("tree_bloomed")
    achieve("primavera")
    Music.play("ending", 0)
    Cine.wait(20)
    Cine.fade_in("light", 8)
    -- the petals, and the people
    Ev.petals_on = true
    for i, v in ipairs(VILLAGERS) do
      local x0 = (v[2] < 0 and -16 or C.PW + 8) + W.cam_x
      local npc = Things.spawn({kind = "npc", id = v[1], cx = (x0 // C.T), cy = n.crowd_y, face = v[2] < 0 and "right" or "left"})
      npc.solid, npc.cine = false, true
      npc.x, npc.y = x0, n.crowd_y * C.T - 4
      npc.t_walk = {tx + 2 + v[2], n.crowd_y * C.T - 4 + (v[3] - 5) * 4}
      npc.walking_in = true
    end
    for _, e in ipairs(E.list) do
      if e.kind == "npc" and e.t_walk then
        Cine.walk(e, e.t_walk[1] * C.T, e.t_walk[2], 1.0)
        e.face = "up"
      end
    end
    Cine.wait(30)
    Cine.say("fin_1") Cine.say("fin_2") Cine.say("fin_3")
    Cine.fade_out("dark", 8)
    Ev.start_credits()
  end)
end

-- ------------------------------------------------------------------ the credits
function Ev.start_credits()
  Ev.petals_on = false
  Ev.credits_t = 0
  Music.play("title", 0)
end


-- the credits scroll: what the game was, how long it took, and a thanks
function Ev.draw_credits()
  cls(Pal.tone(1))
  local ink = Pal.tone(4)
  local t = Ev.credits_t
  local y = 340 - t * 0.5
  local function line(str, size)
    -- a line wider than the picture breaks at the space nearest its middle
    if textw(str, {font = "ps", scale = size or 1}) > 460 then
      local mid, cut = #str // 2, nil
      for i = 1, #str do
        if str:sub(i, i) == " " and (not cut or math.abs(i - mid) < math.abs(cut - mid)) then cut = i end
      end
      if cut then
        line(str:sub(1, cut - 1), size)
        return line(str:sub(cut + 1), size)
      end
    end
    text(str, 240, y, {font = "ps", color = ink, align = "center", scale = size or 1})
    y = y + (size == 2 and 44 or 30)
  end
  line("CEREZO", 2)
  y = y + 10
  line(lang.tr("cr_made"))
  line(lang.tr("cr_engine"))
  y = y + 24
  local mins = Game.time // 3600
  line(lang.tr("cr_time", {h = mins // 60, m = string.format("%02d", mins % 60)}))
  line(lang.tr("cr_cut", {n = Game.stats.cut}))
  line(lang.tr("cr_kills", {n = Game.stats.kills}))
  line(lang.tr("cr_deaths", {n = Game.deaths}))
  y = y + 24
  line(lang.tr("cr_thanks"), 1)
  y = y + 40
  line(lang.tr("cr_end"), 2)
  Ev.credits_end = y < 120
end

function Ev.update_credits()
  Ev.credits_t = Ev.credits_t + 1
  if Ev.credits_t < 60 then Pal.fade("dark", math.max(0, 3 - Ev.credits_t // 15)) end
  if Ev.credits_t > 60 and (btnp("a") or btnp("start")) and (Ev.credits_end or btn("b")) then
    Ev.credits_t = nil
    return true
  end
  return false
end

return Ev
