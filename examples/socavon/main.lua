-- Socavón: a mine shaft the way a ZX Spectrum game drew one, from the moment it loaded off the tape (gen/ makes the art, the rooms
-- and the tunes). Eight rooms: take every key, then go through the portal before the air runs out.
--   The loading: stripes in the border while the pilot tone sounds, the picture arriving in the machine's own order, then its colours.
--   The rooms: blocks of 8x8 with two colours each (a palette bank per kind of block, as the attributes were), sprites with only an
--   ink that takes the ink of the block they are in (the colour clash), keys that flash, belts, floors that crumble, one beeper voice.
-- Arrows walk; A jumps (straight up or along; once in the air there is no steering). The console's menu has "Cómo funciona".
local R, M, G = require("core.room"), require("core.miner"), require("core.guards")
local Z, H, Tape, Mu = require("core.zx"), require("core.hud"), require("core.tape"), require("core.music")
local Explain = require("core.explain")
local Input = require("core.input")
local Frames = require("data.frames")
local lang = require("lang")

state = "load" -- load | title | demo | play | clear | win | over | explain (global: tests/socavon.script)
GAME = {room = 1, lives = 3, score = 0, air = 1, deaths = 0, room_deaths = 0, high = 0}
local g = GAME
local t = 0
local miner_sh, enemy_sh, fx_sh
local AIR_SECONDS = 75
local toast_text, toast_t = nil, 0
local sparks = {} -- the glints of a key taken

local function toast(s) toast_text, toast_t = s, 170 end

local function earn(id)
  if achieve(id) then toast(lang.tr("ach_" .. id)) end
end

local function menu() -- the game's own item in the console's menu, in the language of the settings
  menuitem()
  menuitem(lang.tr("how"), function()
    if state == "play" or state == "title" then
      Explain.enter(miner_sh)
      state = "explain"
    end
  end)
end

local function begin_room(n)
  sparks = {}
  g.room = n
  R.load(n)
  G.load(R.rm)
  M.reset()
  g.air = 1
  g.room_deaths = 0
  Mu.play("sala_" .. ((n - 1) % 4 + 1))
end

local function new_game()
  g.lives, g.score, g.deaths = 3, 0, 0
  Mu.sfx("start")
  begin_room(1)
  state, t = "play", 0
  show(ALL)
end

function _init()
  lang.load()
  R.init()
  miner_sh, enemy_sh, fx_sh = sheet("MINER"), sheet("ENEMY"), sheet("FX")
  palette("OBJ", true)
  g.high = stored("high", 0)
  Explain.hook = earn
  M.on_jump = function() Mu.sfx("jump") end
  M.on_die = function() Mu.sfx("hit") Mu.stop() end
  show(0) -- the loading is drawn at full resolution; the room's layers come after
  menu()
end

function _resume()
  lang.load()
  menu()
end

-- ------------------------------------------------------------------ the title's demo: a miner that walks to and fro and jumps, in each room in turn
local DEMO_AFTER, DEMO_ROOM_TICKS = 600, 420
local demo_t = 0

local function demo_feed(n)
  local held = {}
  local phase = (n // 90) % 2
  if phase == 0 then held.right = true else held.left = true end
  if n % 130 == 100 then held.a = true end
  return held
end

local function demo_start()
  state, demo_t = "demo", 0
  Input.feed = demo_feed
  Input.reset()
  show(ALL)
  begin_room(1)
  Mu.play("titulo")
end

local function demo_stop()
  Input.feed = nil
  M.dead = 0
  state, t = "title", 0
  show(0)
  Mu.play("titulo")
end

local function update_demo()
  demo_t = demo_t + 1
  if btnp("a") or btnp("start") then demo_stop() new_game() return end
  if demo_t % DEMO_ROOM_TICKS == 0 then
    begin_room(g.room % R.count() + 1)
    Mu.play("titulo")
    M.reset()
  end
  Input.step()
  M.update()
  if M.dead > 0 then M.dead = 0 M.reset() end -- the demo does not die
  G.update()
  if t % 6 == 0 then R.animate(t) end
end

-- ------------------------------------------------------------------ playing

local function die_done()
  g.lives = g.lives - 1
  g.deaths = g.deaths + 1
  g.room_deaths = g.room_deaths + 1
  if g.lives <= 0 then
    if g.score > g.high then g.high = g.score store("high", g.high) end
    state, t = "over", 0
    Mu.play("gameover")
  else
    local n = g.room
    R.load(n)
    G.load(R.rm)
    M.reset()
    g.air = 1
    Mu.play("sala_" .. ((n - 1) % 4 + 1))
  end
end

local function room_clear()
  state, t = "clear", 0
  Mu.play("portal")
  earn("primera_sala")
  if g.air < 0.1 then earn("justo") end
end

local function update_play()
  if M.dead > 0 then
    M.update()
    if M.dead > 60 then die_done() end
    return
  end
  M.update()
  G.update()
  g.air = g.air - 1 / (60 * AIR_SECONDS * (R.rm.air or 1))
  if g.air <= 0 then M.die() end
  if G.hits(M.x, M.y) then M.die() end
  for _, p in ipairs(M.corners()) do
    local tx, ty = math.floor(p[1]) // 8, math.floor(p[2]) // 8
    local c = R.char(tx, ty)
    if R.is_hazard(c) then M.die() end
    if c == "k" then
      R.set(tx, ty, ".")
      R.keys, g.score = R.keys - 1, g.score + 100
      Mu.sfx("key")
      sparks[#sparks + 1] = {x = tx * 8 - 4, y = ty * 8 - 4, t = 0}
      if R.keys == 0 then R.open_portal() end
    end
    if c == "X" and R.open then room_clear() end
  end
  if t % 6 == 0 then R.animate(t) end
  for i = #sparks, 1, -1 do
    sparks[i].t = sparks[i].t + 1
    if sparks[i].t >= 18 then table.remove(sparks, i) end
  end
end

local function update_clear()
  M.win = true
  M.anim = M.anim + 1
  if g.air > 0 then -- the air left turns into score, quickly, with a tick for each bit
    g.air = g.air - 0.012
    g.score = g.score + 12
    if t % 2 == 0 then Mu.sfx("tally") end
    return
  end
  g.air = 0
  if Mu.done() and t > 90 then
    if g.room >= R.count() then
      state, t = "win", 0
      Mu.play("fin")
      earn("minero")
      if g.deaths == 0 then earn("impecable") end
      if g.score > g.high then g.high = g.score store("high", g.high) end
    else
      begin_room(g.room + 1)
      state, t = "play", 0
    end
  end
end

function _update()
  t = t + 1
  if state == "load" then
    if t == 1 then tone(0, 807, {wave = "square", vol = 0.08}) end -- the pilot tone
    if t == Tape.PILOT then tone(0) tone(3, 3000, {wave = "noise", vol = 0.05}) end -- the data
    if t == Tape.TOTAL then tone(3) end
    if btnp("a") then
      if t < Tape.TOTAL then t = Tape.TOTAL tone(0) tone(3)
      else state, t = "title", 0 Mu.play("titulo") end
    end
    if t > Tape.TOTAL + 120 then state, t = "title", 0 Mu.play("titulo") end
  elseif state == "title" then
    if btnp("a") or btnp("start") then new_game() elseif t > DEMO_AFTER then demo_start() end
  elseif state == "demo" then
    update_demo()
    if t % 16 == 0 and not settings().reduce_flashing then R.colours((t // 16) % 2 == 1) end
  elseif state == "play" then
    update_play()
    if t % 16 == 0 and not settings().reduce_flashing then R.colours((t // 16) % 2 == 1) end
  elseif state == "clear" then
    update_clear()
    if t % 16 == 0 and not settings().reduce_flashing then R.colours((t // 16) % 2 == 1) end
  elseif state == "explain" then
    if Explain.update() then Explain.leave() state = "play" end
  elseif state == "win" or state == "over" then
    if t > 60 and btnp("a") then state, t = "title", 0 Mu.play("titulo") show(0) end
  end
  if toast_t > 0 then toast_t = toast_t - 1 end
  if state ~= "load" then Mu.update() end
end

-- ------------------------------------------------------------------ drawing

local function draw_sprites()
  spr_clear()
  if M.dead == 0 or (M.dead // 4) % 2 == 0 or M.dead > 30 then
    local f = Frames.MINER[M.frame()]
    spr(0, miner_sh, f, 8 + math.floor(M.x), 8 + math.floor(M.y), prio(0) | bank(R.ink_bank(M.x + 8, M.y + 8)) | (M.face < 0 and FLIP_X or 0))
  end
  for i, gd in ipairs(G.list) do
    local f = Frames.ENEMY[G.frame(gd)]
    local fx = (gd.dir < 0 and gd.k.axis == "x")
    spr(i, enemy_sh, f, 8 + math.floor(gd.x), 8 + math.floor(gd.y), prio(0) | bank(R.ink_bank(gd.x + 8, gd.y + 8)) | (fx and FLIP_X or 0))
  end
end

local function draw_sparks()
  for i, f in ipairs(sparks) do
    spr(40 + i, fx_sh, Frames.FX["glint_" .. f.t // 6], 8 + f.x, 8 + f.y, prio(0) | bank(R.BANK.key))
  end
end

local function draw_threads() -- a spider hangs from its thread: a line from the ceiling
  for _, gd in ipairs(G.list) do
    if gd.kind == "arana" then rect(16 + math.floor(gd.x) * 2 + 15, 16 + 16, 2, math.floor(gd.y) * 2 - 16 + 12, R.attr.air[2]) end
  end
end

function _draw()
  if state == "load" then
    Tape.draw(t, settings().reduce_flashing)
    if t >= Tape.TOTAL and (t // 30) % 2 == 0 then
      text(lang.tr("press"), 240, 288, {font = H.F.body, align = "center", color = Z.BWHITE})
    end
    return
  end
  if state == "title" then
    rect(0, 0, 480, 320, Z.BLACK)
    Tape.picture(144, 18)
    rect(16, 16, 448, 36, Z.BLACK) -- a band for the name, over the sky and the rock
    rect(16, 52, 448, 2, Z.BRED)
    text(lang.tr("title"), 240, 22, {font = H.F.title, align = "center", color = Z.BYELLOW, scale = 2})
    rect(16, 262, 448, 42, Z.BLACK)
    if (t // 30) % 2 == 0 then text(lang.tr("press"), 240, 268, {font = H.F.title, align = "center", color = Z.BWHITE}) end
    text(lang.tr("high") .. " " .. string.format("%06d", g.high), 240, 288, {font = H.F.body, align = "center", color = Z.BYELLOW})
    return
  end
  backdrop(R.border or Z.BLACK)
  scroll(1, -8, -8)
  if state == "demo" then
    draw_sprites()
    draw_threads()
    H.status(g)
    H.border(R.border or Z.BLACK)
    rect(160, 8, 160, 14, Z.BLACK)
    if (t // 30) % 2 == 0 then text(lang.tr("demo") .. " · " .. lang.tr("press"), 240, 9, {font = H.F.small, align = "center", color = Z.BWHITE}) end
    return
  end
  if state == "explain" then
    spr_clear()
    if Explain.page == 2 then -- the miner crossing four bands: he takes the ink of the band he is in
      local band = math.min(4, math.floor((Explain.sx + 8) / 56) + 1)
      spr(0, miner_sh, Frames.MINER["walk_" .. (t // 6) % 4], 8 + math.floor(Explain.sx), 8 + 56, prio(0) | bank(R.band_bank[band]))
    end
    Explain.draw(g)
    H.border(R.border or Z.BLACK)
    return
  end
  draw_sprites()
  draw_sparks()
  draw_threads()
  H.status(g)
  H.border(R.border or Z.BLACK)
  if state == "over" then
    rect(112, 120, 256, 48, Z.BLACK)
    text(lang.tr("game_over"), 240, 136, {font = H.F.title, align = "center", color = Z.BRED})
  elseif state == "win" then
    rect(48, 100, 384, 100, Z.BLACK)
    text(lang.tr("win_1"), 240, 116, {font = H.F.title, align = "center", color = Z.BYELLOW})
    text(lang.tr("win_2"), 240, 142, {font = H.F.body, align = "center", color = Z.BWHITE})
    text(lang.tr("score") .. " " .. string.format("%06d", g.score), 240, 166, {font = H.F.body, align = "center", color = Z.BGREEN})
  end
  if toast_t > 0 then
    rect(80, 8, 320, 14, Z.BLACK)
    text(toast_text, 240, 9, {font = H.F.small, align = "center", color = Z.BYELLOW})
  end
end
