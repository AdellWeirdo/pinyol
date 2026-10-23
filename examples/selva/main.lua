-- Selva: a runner the way the 32-bit consoles drew them. Every solid is a mesh() (a few quads with a picture on each, lit flat, faded with
-- distance, its corners on whole pixels); the camera follows the fox from behind. The console's menu has "Cómo funciona", which lets the
-- player switch each trick off and see what it did.
--   left and right: steer   A: jump (land on a crate to break it)   B: spin   START: begin
local Tex, View, Fox = require("textures"), require("view"), require("fox")
local W, Snd, E = require("world"), require("sound"), require("explain")
local lang, hud = require("lang"), require("hud")

state = "title" -- title | play | over | explain (global: tests/selva.script)
fox, cam = nil, {x = 0, z = 0}
local best, new_record, faces_drawn, back_to = 0, false, 0, "title"
local idle, over_t = 0, 0
local combo_show = 0

local function menu() -- the game's own item in the console's menu, in the language of the settings
  menuitem()
  menuitem(lang.tr("how"), function()
    if state ~= "explain" then back_to, state = state == "over" and "title" or state, "explain" E.enter() achieve("curioso") end
  end)
end

local function toast(s) hud.toast(s, 170) sfx("SFX_TOAST", 0.8) end
local function earn(id) if achieve(id) then toast(lang.tr("ach_" .. id)) end end

local function new_run(seed) -- a run: the demo's, or the player's
  W.hook = function(ev)
    if state ~= "play" then return end -- (the attract mode makes no sound)
    if ev == "jump" then Snd.play("SFX_JUMP", 0.6)
    elseif ev == "fruit" then Snd.play("SFX_FRUIT", 0.8) if W.fruit == 1 then earn("fruta") end
    elseif ev == "crate" then Snd.play("SFX_CRATE") earn("caja")
    elseif ev == "stomp" then Snd.play("SFX_STOMP") if W.combo >= 3 then earn("racha") combo_show = 90 end
    elseif ev == "bump" then Snd.play("SFX_BUMP")
    elseif ev == "hurt" then Snd.play("SFX_HURT")
    elseif ev == "falling" then Snd.play("SFX_FALL")
    elseif ev == "fall" then Snd.play("SFX_HURT")
    elseif ev == "spin" then Snd.play("SFX_SPIN")
    elseif ev == "over" then Snd.play("SFX_OVER")
    end
  end
  W.new(seed)
  fox = W.fox
  cam.z, cam.x = fox.z - View.CAM_BACK, 0
end

function _init()
  show(0)
  lang.load()
  Tex.init(); View.init(); Fox.init(); Snd.init()
  best = stored("best", 0)
  new_run(7)
  menu()
end

function _resume() -- the menu closed: Ajustes may have changed the language
  lang.load()
  menu()
end

local function metres() return math.floor(W.dist / 6) end

function _update()
  hud.update()
  if combo_show > 0 then combo_show = combo_show - 1 end
  if state == "title" or state == "explain" then
    if W.over or fox.z > 40000 then new_run(7 + ticks() % 50) end -- the demo starts again by itself
    W.update(W.ai_input())
    if state == "title" and btnp("a") then
      idle = 0
      state = "play"
      sfx("SFX_START", 0.8)
      new_run(ticks() + 1)
    elseif state == "explain" and E.update() then state = back_to
    end
  elseif state == "play" then
    local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    W.update({dx = dx, jump = btnp("a"), spin = btnp("b")})
    if metres() >= 1000 then earn("lejos") end
    if W.over then
      state, over_t = "over", 0
      new_record = metres() > best
      if new_record then best = metres() store("best", best) end
    end
  elseif state == "over" then
    over_t = over_t + 1
    if over_t > 50 and btnp("a") then state = "title" new_run(7) end
  end
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
  hud.counter(14, 12, "SPR_FRUIT", W.fruit, {font = "arcade", color = 0xFFE8B8})
  hud.hearts(14, 38, W.lives, 3, {size = 14, gap = 4, color = 0xF07838})
  text(lang.tr("metres", {n = metres()}), 466, 12, {font = "arcade", align = "right", color = 0xFFE8B8})
  if combo_show > 0 then
    text(lang.tr("combo", {n = W.combo}), 240, 70, {font = "arcade", align = "center", color = 0xFFD060, outline = 0x301808})
  end
  hud.draw_toasts(110, 292, {font = "silk", w = 260})
end

function _draw()
  faces_drawn = scene()
  if state == "play" then hud_draw()
  elseif state == "over" then
    hud_draw()
    shade(60, 96, 360, 110)
    text(lang.tr("game_over"), 240, 108, {font = "arcade", align = "center", color = 0xFFE8B8, outline = 0x301808})
    text(lang.tr("metres", {n = metres()}) .. "  ·  " .. W.fruit .. " " .. lang.tr("fruit"), 240, 138, {font = "arcade", align = "center", color = 0xFFFFFF})
    text((new_record and lang.tr("new_record") or lang.tr("high") .. " " .. lang.tr("metres", {n = best})), 240, 162, {font = "main", align = "center", color = new_record and 0xFFD060 or 0xC8B898})
    if over_t > 50 then text(lang.tr("press"), 240, 188, {font = "silk", align = "center", color = 0xA09070}) end
  elseif state == "title" then
    shade(0, 40, 480, 96)
    text(lang.tr("title"), 240, 52, {font = "gothic", align = "center", color = 0xFFD070, outline = 0x301808})
    text(lang.tr("press"), 240, 108, {font = "arcade", align = "center", color = (ticks() // 30) % 2 == 0 and 0xFFE8B8 or 0xA08868})
    local a, b, c = lang.tr("controls"):match("^(.-) · (.-) · (.*)$")
    text(a, 240, 262, {font = "silk", align = "center", color = 0xE4D4B4})
    text(b .. "  ·  " .. c, 240, 278, {font = "silk", align = "center", color = 0xE4D4B4})
    text(lang.tr("hint"), 240, 298, {font = "silk", align = "center", color = 0xC0AE8C})
    if best > 0 then text(lang.tr("high") .. " " .. lang.tr("metres", {n = best}), 240, 142, {font = "silk", align = "center", color = 0xE4D4B4}) end
  elseif state == "explain" then
    E.panel(faces_drawn)
  end
end
