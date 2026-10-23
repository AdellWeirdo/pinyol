-- Selva: a runner the way the 32-bit consoles drew them. Every solid is a mesh() (a few quads with a picture on each, lit flat, faded with
-- distance, its corners on whole pixels); the camera follows the fox from behind. The console's menu has "Cómo funciona", which lets the
-- player switch each trick off and see what it did.
--   left and right: steer   A: jump (hold it for a high one; land on a crate to break it)   B: spin   START: begin
local Tex, View, Fox = require("textures"), require("view"), require("fox")
local W, Snd, E, Music = require("world"), require("sound"), require("explain"), require("music")
local lang, hud, juice, particles = require("lang"), require("hud"), require("juice"), require("particles")

state = "title" -- title | play | over | explain (global: tests/selva.script)
fox, cam = nil, {x = 0, z = 0}
local best, new_record, faces_drawn, back_to = 0, false, 0, "title"
local over_t, combo_show, pulse, hint, hint_t, mile = 0, 0, 0, nil, 0, 0
local step_n, fx = 0, nil
local WOOD, DUST, SPARK = {0xC08A44, 0x8A5A28, 0x5A3A18}, {0xD8BC88, 0x9A7A50}, {0xFFF0A0, 0xFFB040}

local function menu() -- the game's own item in the console's menu, in the language of the settings
  menuitem()
  menuitem(lang.tr("how"), function()
    if state ~= "explain" then back_to, state = state == "over" and "title" or state, "explain" E.enter() achieve("curioso") end
  end)
end

local function toast(s) hud.toast(s, 170) sfx("SFX_TOAST", 0.8) end
local function earn(id) if achieve(id) then toast(lang.tr("ach_" .. id)) end end

-- where a thing of the way is on the screen (its middle, a little above the ground)
local function at(x, y, z) local sx, sy = View.project(x, y, z, cam) return sx or 240, sy or 200 end

local function dust(x, y, z, n, power)
  local sx, sy = at(x, y, z)
  fx:burst(sx, sy, n, {speed = power or 1.3, angle = -90, spread = 150, gravity = 0.03, life = 20, size = 3, size_end = 1.8, colours = DUST, shape = "square"})
end

local function say_hint(key)
  local n = stored("hint_" .. key, 0)
  if n >= 2 or hint then return end
  store("hint_" .. key, n + 1)
  hint, hint_t = key, 200
end

local function on_event(ev, it)
  if state ~= "play" then return end -- (the attract mode makes no sound, and throws no chips)
  if ev == "jump" then Snd.play("SFX_JUMP", 0.6) dust(fox.x, 0, fox.z, 5)
  elseif ev == "land" then Snd.play("SFX_LAND", 0.8) dust(fox.x, 0, fox.z, 7, 1.6) juice.shake(1.2)
  elseif ev == "fruit" then
    Snd.play("SFX_FRUIT", 0.8, {pitch = 1 + math.min(W.streak - 1, 7) * 0.07})
    local sx, sy = at(it.x, it.y + 6, it.z)
    fx:burst(sx, sy, 8, {speed = 2.2, angle = -90, spread = 360, gravity = 0.04, life = 22, size = 2.5, colours = SPARK, shape = "square"})
    pulse = 10
    if W.fruit == 1 then earn("fruta") end
  elseif ev == "crate" then
    Snd.play("SFX_CRATE") earn("caja")
    local sx, sy = at(it.x, 10, it.z)
    fx:burst(sx, sy, 16, {speed = 3.4, angle = -90, spread = 200, gravity = 0.2, life = 30, size = 3, colours = WOOD, shape = "square"})
    juice.shake(3) juice.freeze(3)
    pulse = 10
  elseif ev == "stomp" then
    Snd.play("SFX_STOMP")
    if W.combo >= 3 then earn("racha") combo_show = 90 end
  elseif ev == "bump" then Snd.play("SFX_BUMP") juice.shake(2.5) dust(fox.x, 0, fox.z + 8, 5)
  elseif ev == "hurt" then Snd.play("SFX_HURT") juice.shake(6) juice.flash(0xE04020, 4)
  elseif ev == "falling" then Snd.play("SFX_FALL")
  elseif ev == "fall" then Snd.play("SFX_HURT") juice.shake(5)
  elseif ev == "spin" then Snd.play("SFX_SPIN")
  elseif ev == "over" then Snd.play("SFX_OVER") Music.set(nil) juice.shake(5)
  end
end

local function new_run(seed) -- a run: the demo's, or the player's
  W.hook = on_event
  W.new(seed)
  fox = W.fox
  cam.z, cam.x = fox.z - View.CAM_BACK, 0
  fx = particles.new()
  hint, hint_t, mile, combo_show, step_n = nil, 0, 0, 0, 0
end

function _init()
  show(0)
  lang.load()
  Tex.init(); View.init(); Fox.init(); Snd.init()
  best = stored("best", 0)
  Music.on = stored("music", true)
  new_run(7)
  Music.set("soft")
  menu()
end

function _resume() -- the menu closed: Ajustes may have changed the language
  lang.load()
  menu()
end

local function metres() return math.floor(W.dist / 6) end

-- the first time a danger is ahead, say what to press (twice in all, then never again)
local function hints()
  if hint_t > 0 then hint_t = hint_t - 1 if hint_t == 0 then hint = nil end return end
  if W.dist > 3000 then return end
  for _, it in ipairs(W.items) do
    local d = it.z - fox.z
    if it.alive and d > 30 and d < 110 then
      if it.k == "crate" then say_hint("jump") return end
      if it.k == "pit" then say_hint("pit") return end
      if it.k == "spike" then say_hint("spike") return end
    end
  end
end

function _update()
  hud.update()
  fx:update()
  Music.update()
  if juice.update() then return end -- a moment frozen when a crate breaks
  if pulse > 0 then pulse = pulse - 1 end
  if combo_show > 0 then combo_show = combo_show - 1 end
  if state == "title" or state == "explain" then
    if W.over or fox.z > 40000 then new_run(7 + ticks() % 50) end -- the demo starts again by itself
    W.update(W.ai_input())
    if state == "title" and btnp("a") then
      state = "play"
      sfx("SFX_START", 0.8)
      new_run(ticks() + 1)
      Music.set("full")
    elseif state == "explain" and E.update() then state = back_to
    end
  elseif state == "play" then
    local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    W.update({dx = dx, jump = btnp("a"), hold = btn("a"), spin = btnp("b")})
    hints()
    -- footsteps on the beat of the stride, a little dust now and then
    local n = math.floor(fox.phase / math.pi)
    if n ~= step_n then
      step_n = n
      if fox.y <= 0.5 and fox.state == "run" then
        Snd.play("SFX_STEP", 0.5)
        if n % 3 == 0 then dust(fox.x, 0, fox.z - 6, 1, 0.7) end
      end
    end
    local m = metres()
    if m >= mile + 250 and m < 1100 then
      mile = m - m % 250
      toast(lang.tr("milestone", {n = mile})) Snd.play("SFX_MILE", 0.9)
    end
    if m >= 1000 then earn("lejos") end
    if W.over then
      state, over_t = "over", 0
      new_record = m > best
      if new_record then best = m store("best", best) end
    end
  elseif state == "over" then
    over_t = over_t + 1
    if over_t > 50 and btnp("a") then state = "title" new_run(7) Music.set("soft") end
  end
  if state == "explain" and Music.mode == nil then Music.set("soft") end
  -- the camera follows from behind, the sideways move a little behind the fox's
  cam.z = fox.z - View.CAM_BACK
  cam.x = cam.x + (fox.x * 0.55 - cam.x) * 0.15
end

local function scene()
  View.sky()
  local n = View.path(cam)
  View.haze()
  n = n + View.trees(cam)
  -- what is on the way, with the fox among it, far to near
  local list = {}
  for _, it in ipairs(W.items) do
    local d = it.z - cam.z
    if it.alive and d > 24 and d < 520 then list[#list + 1] = it end
  end
  list[#list + 1] = {k = "fox", z = fox.z}
  table.sort(list, function(a, b) return a.z > b.z end)
  for _, it in ipairs(list) do
    if it.k == "fox" then
      if fox.y > -60 then View.shadow(fox, cam) end
      n = n + Fox.draw(fox, cam)
    else
      n = n + View.thing(it, cam, ticks())
    end
  end
  return n
end

local function hud_draw()
  local k = 1 + pulse * 0.05
  img("SPR_FRUIT", 14, 10, {scale_x = k, scale_y = k})
  text(tostring(W.fruit), 36, 12, {font = "arcade", color = pulse > 0 and 0xFFFFFF or 0xFFE8B8})
  hud.hearts(14, 38, W.lives, 3, {size = 14, gap = 4, color = 0xF07838})
  local m = metres()
  text(lang.tr("metres", {n = m}), 466, 12, {font = "arcade", align = "right", color = 0xFFE8B8})
  rect(386, 32, 80, 4, 0x2A1A10) -- the way to a thousand metres
  rect(386, 32, math.floor(80 * math.min(1, m / 1000)), 4, 0xF0A858)
  if combo_show > 0 then
    text(lang.tr("combo", {n = W.combo}), 240, 100, {font = "arcade", align = "center", color = 0xFFD060, outline = 0x301808})
  end
  if hint then
    local a = hint_t < 20 and hint_t / 20 or 1
    if a > 0.3 then
      shade(90, 64, 300, 26)
      text(lang.tr("hint_" .. hint), 240, 71, {font = "silk", align = "center", color = 0xFFE8B8})
    end
  end
  hud.draw_toasts(110, 292, {font = "silk", w = 260})
end

local function title_draw()
  shade(0, 36, 480, 112)
  local bob = math.sin(ticks() / 24) * 2
  text(lang.tr("title"), 242, 49 + bob + 2, {font = "gothic", align = "center", color = 0x301808})
  text(lang.tr("title"), 240, 48 + bob, {font = "gothic", align = "center", color = 0xFFD070, outline = 0x301808})
  text(lang.tr("press"), 240, 108, {font = "arcade", align = "center", color = (ticks() // 30) % 2 == 0 and 0xFFE8B8 or 0xA08868})
  shade(0, 254, 480, 66)
  local a, b, c = lang.tr("controls"):match("^(.-) · (.-) · (.*)$")
  text(a, 240, 262, {font = "silk", align = "center", color = 0xE4D4B4})
  text(b .. "  ·  " .. c, 240, 278, {font = "silk", align = "center", color = 0xE4D4B4})
  text(lang.tr("hint"), 240, 298, {font = "silk", align = "center", color = 0xC0AE8C})
  if best > 0 then text(lang.tr("high") .. " " .. lang.tr("metres", {n = best}), 240, 138, {font = "silk", align = "center", color = 0xE4D4B4}) end
end

function _draw()
  camera(juice.offset())
  faces_drawn = scene()
  fx:draw()
  camera()
  if state == "play" then hud_draw()
  elseif state == "over" then
    hud_draw()
    shade(60, 80, 360, 140)
    text(lang.tr("game_over"), 240, 92, {font = "arcade", align = "center", color = 0xFFE8B8, outline = 0x301808})
    text(lang.tr("metres", {n = metres()}), 240, 120, {font = "arcade", align = "center", color = 0xFFFFFF})
    text(W.fruit .. " " .. lang.tr("fruit") .. "  ·  " .. W.crates .. " " .. lang.tr("crates"), 240, 144, {font = "arcade", align = "center", color = 0xFFE8B8})
    text((new_record and lang.tr("new_record") or lang.tr("high") .. " " .. lang.tr("metres", {n = best})), 240, 170, {font = "main", align = "center", color = new_record and 0xFFD060 or 0xC8B898})
    if over_t > 50 then text(lang.tr("press"), 240, 196, {font = "silk", align = "center", color = 0xC0AE8C}) end
  elseif state == "title" then title_draw()
  elseif state == "explain" then E.panel(faces_drawn)
  end
  juice.draw()
end
