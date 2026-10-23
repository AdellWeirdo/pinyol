-- Recortes: call and response with paper dolls, the way the rhythm games of the 32-bit consoles did it. The teacher sings a phrase on the buttons, you sing
-- it back in time. The dolls are quads (turned, bent, scaled pictures), the set is the PPU's layers, the music is live on the synth's voices from the
-- game's own clock. The console's menu has "Cómo funciona", which switches each trick off.
--   left, right, A, B: the notes   left and right on the title: the song   A: begin
local Art, Chars, Stage, Puppet = require("art"), require("chars"), require("stage"), require("puppet")
local G, Song, Music, Snd, E = require("game"), require("song"), require("music"), require("sound"), require("explain")
local lang, hud, juice, particles = require("lang"), require("hud"), require("juice"), require("particles")

state = "title" -- title | play | results | explain (global: tests/recortes.script)
song_pick = 1 -- (global: tests/recortes.script)
local back_to = "title"
local fx, popups = nil, {}
local sapo = {sing_t = 0, bubble = nil, bubble_t = 0}
local lila = {sing_t = 0, bubble = nil, bubble_t = 0, hop = 0}
local bar_notes = {}
local quads_drawn, results_t = 0, 0
local PITCH = {a = "C5", b = "E5", left = "G4", right = "A4"}
local COLOURS = {cool = 0xFFD860, good = 0xFFFFFF, bad = 0xB0B0B0, awful = 0xE05848, miss = 0xE05848}
local CONFETTI = {0xFFD860, 0xE05848, 0x4890E0, 0x58B060, 0xFFFFFF}

local function menu()
  menuitem()
  menuitem(lang.tr("how"), function()
    if state ~= "explain" then back_to, state = state, "explain" E.enter() achieve("curioso") end
  end)
end

local function toast(s) hud.toast(s, 170) sfx("SFX_TOAST", 0.8) end
local function earn(id) if achieve(id) then toast(lang.tr("ach_" .. id)) end end

local function popup(kind, x, y)
  popups[#popups + 1] = {text = lang.tr(kind), x = x, y = y, t = 40, col = COLOURS[kind]}
end

local function on_event(ev, a, b)
  if ev == "sing" then -- the teacher's note
    tone(3, PITCH[a.button], {wave = "square", duty = 0.5, vol = 0.18, decay = 0.16})
    sapo.sing_t, sapo.bubble, sapo.bubble_t, sapo.arm = 12, a.syl, 28, 36
  elseif ev == "press" then
    lila.sing_t = 10
  elseif ev == "judge" then
    local kind, note = a, b
    if kind == "cool" or kind == "good" then
      tone(3, PITCH[note.button], {wave = "triangle", vol = kind == "cool" and 0.26 or 0.2, decay = 0.18})
      lila.bubble, lila.bubble_t = note.syl, 28
      if kind == "cool" then Snd.play("SFX_COOL") lila.hop = 1 fx:burst(370, 190, 8, {speed = 2.6, angle = -90, spread = 140, gravity = 0.12, life = 34, size = 2.5, colours = CONFETTI, shape = "square"}) end
      earn("nota")
      if G.best_combo >= 12 then earn("racha") end
    elseif kind == "bad" then Snd.play("SFX_BAD")
    else Snd.play("SFX_MISS") juice.shake(2) end
    popup(kind, 360, 150)
  elseif ev == "rank" then
    if a == "cool" then toast(lang.tr("cool")) end
  elseif ev == "done" then
    state, results_t = "results", 0
    Music.reset()
    local pct = math.floor(a.accuracy * 100 + 0.5)
    if pct > stored("best" .. G.id, 0) then store("best" .. G.id, pct) end
    if a.rank == "cool" then earn("genial") end
    if a.clean then earn("limpio") end
    sfx("SFX_DONE", 0.9)
  end
end

local function new_song(id)
  G.hook = on_event
  G.start(id)
  Music.reset()
  bar_notes = {}
  for _, list in ipairs({G.sing, G.notes}) do
    for _, nt in ipairs(list) do bar_notes[nt.bar] = bar_notes[nt.bar] or {} table.insert(bar_notes[nt.bar], nt) end
  end
  popups = {}
  fx = particles.new()
  sapo.sing_t, lila.sing_t, sapo.bubble_t, lila.bubble_t, sapo.arm = 0, 0, 0, 0, 0
end

function _init()
  show(BG0 | BG1 | BG2 | BG3)
  lang.load()
  Art.init(); Snd.init(); Stage.init()
  Music.on = stored("music", true)
  fx = particles.new()
  new_song(1)
  G.t = -2000 -- the title: the clock runs but nothing is sung
  menu()
end

function _resume() lang.load() menu() end

local function inputs()
  return {a = btnp("a"), b = btnp("b"), left = btnp("left"), right = btnp("right")}
end

function _update()
  hud.update()
  fx:update()
  juice.update()
  Music.update()
  if sapo.sing_t > 0 then sapo.sing_t = sapo.sing_t - 1 end
  if lila.sing_t > 0 then lila.sing_t = lila.sing_t - 1 end
  if sapo.bubble_t > 0 then sapo.bubble_t = sapo.bubble_t - 1 end
  if lila.bubble_t > 0 then lila.bubble_t = lila.bubble_t - 1 end
  lila.hop = math.max(0, lila.hop - 0.08)
  sapo.arm = math.max(0, (sapo.arm or 0) - 1.5)
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.t, p.y = p.t - 1, p.y - 0.8
    if p.t <= 0 then table.remove(popups, i) end
  end
  if state == "title" or state == "explain" then
    G.t = G.t + 1 -- (the clock of the dolls' dance)
    Stage.update(E.flags.layers and 0.25 or 0)
    if state == "title" then
      if btnp("left") then song_pick = (song_pick - 2) % #Song.songs + 1 sfx("SFX_BLIP", 0.8) end
      if btnp("right") then song_pick = song_pick % #Song.songs + 1 sfx("SFX_BLIP", 0.8) end
      if btnp("a") then state = "play" new_song(song_pick) sfx("SFX_START", 0.9) end
    elseif E.update() then state = back_to
    end
  elseif state == "play" then
    G.update(inputs())
    local rate = (G.rank == "cool" and 0.9 or G.rank == "good" and 0.5 or 0.2)
    Stage.update(E.flags.layers and rate or 0)
    -- the count in
    if G.t < 0 and G.t % math.floor(G.step_t * 4) == 0 and G.t > -G.bar_t - 1 then Snd.play("SFX_COUNT", 0.8) end
  elseif state == "results" then
    results_t = results_t + 1
    Stage.update(E.flags.layers and 0.3 or 0)
    if results_t > 60 and btnp("a") then state = "title" G.t = -2000 Music.reset() end
  end
end

local function bubble(x, y, syl)
  part_ = nil
  quad("P_BUBBLE", x - 56, y - 16, x + 56, y - 16, x + 56, y + 36, x - 56, y + 36)
  text(syl, x, y - 4, {font = "arcade", align = "center", color = 0x2A2030})
end

local function lane()
  local x0, sw, y = 40, 25, 292
  local k, who, step = G.where()
  rect(30, y - 20, 420, 40, 0xFFFFFF) rect(32, y - 18, 416, 36, 0xF4E8D0)
  for i = 0, 16, 4 do rect(x0 + i * sw - 1, y - 16, 2, 32, 0xD8C8A8) end
  local list = bar_notes[k]
  if list and (who == "teacher" or who == "player") then
    for _, nt in ipairs(list) do
      local nx = x0 + nt.step * sw + sw // 2
      local dim = (who == "teacher" and nt.state == "pending") and "dim" or nil
      Stage.mark(nt.button, nx, y, 9, dim)
      if who == "player" and nt.state ~= "pending" then
        circ(nx, y, 13, COLOURS[nt.state], false)
        if nt.state == "awful" or nt.state == "miss" then line(nx - 8, y - 8, nx + 8, y + 8, 0xE05848) line(nx - 8, y + 8, nx + 8, y - 8, 0xE05848) end
      end
    end
  end
  if who == "teacher" or who == "player" then -- the playhead
    local px = x0 + step * sw
    tri(px - 6, y - 24, px + 6, y - 24, px, y - 14, who == "teacher" and 0xE05848 or 0x4890E0, true)
  end
  local label = who == "teacher" and "teacher" or who == "player" and "you" or nil
  if label then text(lang.tr(label), 240, 36, {font = "arcade", align = "center", color = who == "teacher" and 0xE05848 or 0x4890E0, outline = 0xFFFFFF}) end
end

local function hud_draw()
  -- the mood: a paper strip with four zones and a marker
  rect(150, 6, 180, 14, 0xFFFFFF)
  local zones = {{0, 0.2, 0xE05848}, {0.2, 0.45, 0xB0A090}, {0.45, 0.78, 0x70B070}, {0.78, 1, 0xFFD860}}
  for _, z in ipairs(zones) do rect(152 + math.floor(176 * z[1]), 8, math.floor(176 * (z[2] - z[1])), 10, z[3]) end
  local mx = 152 + math.floor(176 * G.meter)
  tri(mx - 5, 24, mx + 5, 24, mx, 17, 0x2A2030, true)
  text(lang.tr("mood"), 140, 8, {font = "silk", align = "right", color = 0x2A2030, outline = 0xFFFFFF})
  if G.combo > 1 then text(lang.tr("combo", {n = G.combo}), 450, 8, {font = "arcade", align = "right", color = 0xFFD860, outline = 0x2A2030}) end
  hud.draw_toasts(110, 44, {font = "silk", w = 260})
end

function _draw()
  quads_drawn = 0
  local beat = G.step_t * 4
  local t = G.t
  local energy = state == "play" and 1 or 0.7
  camera(juice.offset())
  -- shadows, then the dolls
  if E.flags.shadow then
    quad("P_SHADOW", 70, 248, 190, 248, 190, 262, 70, 262) -- (a darker floor colour, not a see-through black: a mixed quad costs five times)
    quad("P_SHADOW", 300, 248, 420, 248, 420, 262, 300, 262)
  end
  Chars.sapo(130, 258, {t = t, beat = beat, sing = sapo.sing_t > 0, energy = energy, arm = sapo.arm})
  Chars.lila(360, 258, {t = t, beat = beat, sing = lila.sing_t > 0, energy = energy, mood = G.rank, hop = lila.hop, tilt = lila.sing_t > 0 and 5 or 0})
  quads_drawn = 20
  if sapo.bubble_t > 0 and state == "play" then bubble(180, 70, sapo.bubble) end
  if lila.bubble_t > 0 and state == "play" then bubble(330, 70, lila.bubble) end
  fx:draw()
  camera()
  if state == "play" then
    lane()
    hud_draw()
    for _, p in ipairs(popups) do text(p.text, p.x, p.y, {font = "arcade", align = "center", color = p.col, outline = 0x2A2030}) end
    if G.t < 0 then -- the count in
      local beats_left = math.ceil(-G.t / beat)
      if beats_left <= 3 then text(tostring(beats_left), 240, 120, {font = "gothic", align = "center", color = 0xFFFFFF, outline = 0x2A2030}) end
    end
  elseif state == "results" then
    lane()
    local r = G.result
    shade(60, 50, 360, 170)
    rect(70, 60, 340, 150, 0xF4E8D0) box(70, 60, 340, 150, 0x2A2030)
    text(lang.tr("done_" .. r.rank), 240, 72, {font = "arcade", align = "center", color = 0x2A2030})
    text(lang.tr("accuracy", {n = math.floor(r.accuracy * 100 + 0.5)}), 240, 108, {font = "main", align = "center", color = 0x2A2030})
    text(lang.tr("longest", {n = r.best_combo}), 240, 134, {font = "main", align = "center", color = 0x2A2030})
    local c = r.count
    text(string.format("%s %d   %s %d   %s %d   %s %d", lang.tr("cool"), c.cool, lang.tr("good"), c.good, lang.tr("bad"), c.bad + c.miss, lang.tr("awful"), c.awful), 240, 164, {font = "silk", align = "center", color = 0x504838})
    if results_t > 60 then text(lang.tr("again"), 240, 188, {font = "silk", align = "center", color = 0x504838}) end
  elseif state == "title" then
    shade(0, 26, 480, 104)
    text(lang.tr("title"), 242, 38, {font = "gothic", align = "center", color = 0x2A2030})
    text(lang.tr("title"), 240, 36, {font = "gothic", align = "center", color = 0xFFF0D0, outline = 0x2A2030})
    text("< " .. lang.tr("song" .. song_pick) .. " >", 240, 92, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x2A2030})
    local best = stored("best" .. song_pick, 0)
    if best > 0 then text(lang.tr("best") .. " " .. best .. " %", 240, 112, {font = "silk", align = "center", color = 0xFFF0D0}) end
    text(lang.tr("press"), 240, 140, {font = "arcade", align = "center", color = (ticks() // 30) % 2 == 0 and 0xFFFFFF or 0xC0B090})
    shade(0, 262, 480, 58)
    local a, b = lang.tr("controls"):match("^(.-): (.*)$")
    text(a .. ":", 240, 268, {font = "silk", align = "center", color = 0xFFF0D0})
    text(b, 240, 283, {font = "silk", align = "center", color = 0xFFF0D0})
    text(lang.tr("hint"), 240, 301, {font = "silk", align = "center", color = 0xD8C8A8})
  elseif state == "explain" then E.panel(quads_drawn)
  end
end
