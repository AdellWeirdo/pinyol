-- room: the scene, as the board's renderer drew it (renderer.py _draw_scene, scenery.py): the room by day or night,
-- what past lives left, her stars, Sancho in the background, the litter box, a sparrow at the window, a visitor,
-- and Audrey (actor) or her peeking out from where she hides. Board scene coordinates through hud.sc.
local hud = require("hud")
local actor = require("actor")
local anim = require("anim")
local ui = require("ui")
local T = ui.T
local M = {}

local ROOMS = {"bg_living", "bg_kitchen", "bg_rasca", "bg_studio", "bg_wc"}
local SANCHO_HOME = {bg_living = {208, 143}, bg_kitchen = {200, 80}, bg_rasca = {62, 85}, bg_studio = {60, 108}}
local SANCHO_CHANCE = 0.3
local LEGACY_AT = {12, 128}
local MOON_AT = {bg_living = {150, 56}, bg_studio = {148, 32}}
local WINDOW_STARS = {
  bg_living = {{100, 40}, {132, 64}, {86, 72}, {156, 40}, {116, 86}, {146, 82}, {96, 56}, {124, 46}},
  bg_studio = {{134, 24}, {160, 38}, {142, 44}, {168, 22}, {150, 28}, {128, 38}, {162, 46}, {138, 30}},
}
local HIDE_SPOTS = {
  bg_living = {{195, 119}, {40, 83}, {75, 140, "r"}, {145, 150, "l"}},
  bg_kitchen = {{125, 113}, {170, 78}, {43, 118, "l"}},
  bg_rasca = {{143, 141}, {40, 66}, {190, 134, "l"}},
  bg_studio = {{141, 51}, {66, 87}, {189, 140, "l"}, {80, 148, "r"}},
  bg_wc = {{48, 92}, {70, 135, "r"}, {139, 106, "r"}},
}
local BIRD_PERCH = {bg_living = {96, 113}, bg_studio = {150, 44}}
local BIRD_LOOP = {0, 0, 0, 1, 1, 0, 2, 2, 0, 0, 3, 3}
local LITTER_X = 206
local VISIT_DX, VISIT_UP = -74, 6
local VISIT_ROOM = {32, 16}
local WANT_ICON = {Feed = "IC_OPT_MEAL", Cuddle = "IC_FX_HEART", Bath = "IC_MENU_BATH", Sleep = "IC_MENU_SLEEP",
                   Heal = "IC_SUB_MEDICINA", Play = "IC_TOY_PELOTA"}
local STINK_ABOVE = 75
local K = actor.K

local R = {bg = nil, sancho = false, spot = nil, trail_at = nil, t = 0}
M.state = R

function M.room(ui_) return tostring(ui_.background or "bg_living"):match("^([^.]+)") end

local function picture(name, frame, x, y) -- an A_ set's frame, top-left on the screen
  local id = "A_" .. name:upper()
  local w, h, n = imgsize(id)
  if not w then return nil end
  img(id, x, y, {frame = (frame or 0) % n, scale = 2})
  return w * 2, h * 2
end

local function at_bottom(name, frame, cx, bottom) -- its canvas's bottom centre at (cx, bottom)
  local w, h = imgsize("A_" .. name:upper())
  if not w then return end
  picture(name, frame, cx - w, bottom - h * 2)
end

function M.background(ui_)
  local room = M.room(ui_)
  local id = "BG_" .. room:sub(4):upper()
  if ui_.dark and imgsize(id .. "_NOCHE") then id = id .. "_NOCHE" end
  img(id, 0, hud.ROOM_Y, {scale = 2})
end

local function enter_room(ui_) -- on entering a room: is Sancho in its background? (rolled once, never popping in)
  local room = M.room(ui_)
  if room ~= R.bg then
    if R.bg ~= nil then R.trail_at = R.t end
    R.bg = room
    R.sancho = SANCHO_HOME[room] ~= nil and math.random() < SANCHO_CHANCE
  end
end

local function sancho_home(ui_)
  if not R.sancho or ui_.phase == "Cachorro" or ui_.away then return end
  if ui_.sick or ui_.in_critical or (ui_.stress or 0) >= 70 then return end
  local p = SANCHO_HOME[R.bg]
  local sx, sy = hud.sc(p[1], p[2])
  local loop = (R.t // 90) % 4
  at_bottom(loop == 3 and "sancho_mira" or "sancho", (R.t // 16) % 2, sx, sy)
end

local function legacy(ui_)
  if R.bg ~= "bg_living" then return end
  for i, item in ipairs(ui_.legacy or {}) do
    local x, y = hud.sc(LEGACY_AT[1] + (i - 1) * 15, LEGACY_AT[2])
    local id = "IC_LEGADO_" .. tostring(item):upper()
    local w, h = imgsize(id)
    if w then img(id, x, y - h * 2, {scale = 2}) end
  end
end

local function window_stars(ui_)
  local spots = WINDOW_STARS[R.bg]
  if not spots or not ui_.dark then return end
  for i = 1, math.min(ui_.stars or 0, #spots) do
    local x, y = hud.sc(spots[i][1], spots[i][2])
    if y > hud.TOP_H and (R.t // 20 + i) % 4 ~= 0 then
      rect(x - 2, y - 6, 4, 12, T[1])
      rect(x - 6, y - 2, 12, 4, T[1])
    end
  end
end

local function litter(ui_)
  if R.bg ~= "bg_wc" then return end
  local x, y = hud.sc(LITTER_X, 214)
  at_bottom("arenero", math.max(0, math.min(3, ui_.litter or 0)), x, y)
end

local function bird(ui_)
  local perch = BIRD_PERCH[R.bg]
  if not ui_.bird or not perch then return end
  local x, y = hud.sc(perch[1], perch[2])
  at_bottom("pajaro", BIRD_LOOP[(R.t // 10) % #BIRD_LOOP + 1], x, y)
end

local function peek(ui_) -- hide and seek: she shows only in her room, peeking over the furniture's edge
  if not ui_.hidden_here then return end
  local spots = HIDE_SPOTS[R.bg]
  if not spots then return end
  R.spot = R.spot or math.random(256)
  local spot = spots[R.spot % #spots + 1]
  local x, edge = hud.sc(spot[1], spot[2])
  local set = anim.pick("hidden")
  local w, h = imgsize("A_" .. set:upper())
  if not w then return end
  local frame = (actor.tick() // 3) % select(3, imgsize("A_" .. set:upper()))
  if spot[3] == "l" then picture(set, frame, x - w * 2, edge - h)
  elseif spot[3] == "r" then picture(set, frame, x, edge - h)
  else picture(set, frame, x - w, edge - h * 2) end
end

local function visitor(ui_, cx) -- an animal friend (visitors.py) or a friend's cat (friends.py) beside her
  local who = ui_.visitor and ("visita_" .. ui_.visitor) or (ui_.friend and "amigo") or nil
  if not who then return 0 end
  local shift = math.floor((anim.puppy(ui_) and VISIT_ROOM[1] or VISIT_ROOM[2]) * K)
  local w, h, n = imgsize("A_" .. who:upper())
  if w then
    picture(who, (R.t // 12) % n, cx + math.floor(VISIT_DX * K) - w, hud.FLOOR - math.floor(VISIT_UP * K) - h * 2)
  end
  if ui_.visitor_gift then
    local id = "IC_REGALO_" .. tostring(ui_.visitor_gift):upper()
    if imgsize(id) then actor.icon(id, cx - 70, hud.FLOOR - 16) end
  end
  return shift
end

local function want(ui_, x, y, w) -- what she needs, thought of in a bubble now and then
  local need = ui_.need
  if not need or (R.t // 240) % 3 ~= 0 then return end
  local dirty = ((ui_.stats or {})["Suciedad"] or 0) > STINK_ABOVE
  local id = (need == "Bath" and not dirty) and "IC_SUB_ARENERO" or WANT_ICON[need] or "IC_FX_HEART"
  local bx, by = math.min(x + w - 8, 440), math.max(y - 8, hud.CONTENT_Y + 60)
  ui.box(bx - 22, by - 22, 44, 44)
  actor.icon(id, bx, by)
end

local function dream(ui_, x, y, w) -- asleep: the bubble with what she dreams of
  if not ui_.dream then return end
  local bx, by = math.min(x + w - 30, 420), math.max(y - 10, hud.CONTENT_Y + 64)
  circ(bx - 18, by + 26, 3, T[1]) circ(bx - 18, by + 26, 3, T[4], false)
  circ(bx - 10, by + 16, 5, T[1]) circ(bx - 10, by + 16, 5, T[4], false)
  ui.box(bx - 4, by - 30, 52, 40)
  local icons = {comida = "IC_OPT_MEAL", juego = "IC_TOY_PELOTA", objeto = "IC_TOY_RATON", nieve = "IC_ST_SPARKLE",
                 estrella = "IC_ST_STAR", juguete = "IC_TOY_PELOTA", legado = "IC_LEGADO_ESTRELLA",
                 fiesta = "IC_ST_HEART", mimos = "IC_FX_HEART"}
  local key = type(ui_.dream) == "table" and ui_.dream[1] or ui_.dream
  if key == "juguete" and ui_.toy then icons.juguete = "IC_TOY_" .. tostring(ui_.toy):upper() end
  actor.icon(icons[key] or "IC_FX_HEART", bx + 22, by - 10)
end

local function stink(cx, y)
  for i = 0, 2 do
    local x = cx - 30 + i * 30
    local wave = (R.t // 8 + i) % 2 == 0 and 2 or -2
    line(x, y, x + wave, y - 8, T[3]) line(x + wave, y - 8, x, y - 16, T[3])
  end
end

local function paw_trail()
  if not R.trail_at or R.t - R.trail_at > 4 * 16 then return end
  local n = math.min((R.t - R.trail_at) // 16 + 1, 4)
  for i = 0, n - 1 do actor.icon("IC_FX_PAW", 24 + i * 30, hud.FLOOR - 8 - (i % 2) * 18) end
end

function M.update() R.t = R.t + 1 end

function M.draw(ui_, cut)
  enter_room(ui_)
  M.background(ui_)
  if ui_.night and MOON_AT[R.bg] and actor.moon_showing() then
    local mx, my = hud.sc(MOON_AT[R.bg][1], MOON_AT[R.bg][2])
    actor.icon("IC_MOON", mx, math.max(my, hud.TOP_H + 14))
  end
  window_stars(ui_)
  bird(ui_)
  sancho_home(ui_)
  legacy(ui_)
  paw_trail()
  litter(ui_)
  local cx = 240
  if cut and cut(cx, hud.FLOOR) then return end -- Sancho comes for her or brings her back
  if ui_.away then return end                    -- with Sancho: an empty room
  if ui_.hidden then peek(ui_) R.spot_live = true return end
  R.spot = nil
  local shift = visitor(ui_, cx)
  local x, y, w, h = actor.draw(cx + shift, hud.FLOOR)
  local sleeping = ui_.sleeping or ui_.deep_sleep
  if not sleeping then want(ui_, x, y, w) end
  if ((ui_.stats or {})["Suciedad"] or 0) > STINK_ABOVE then stink(cx + shift, y + 40) end
  if sleeping then dream(ui_, x, y, w) end
  if actor.toy_playing() and ui_.toy then
    actor.icon("IC_TOY_" .. tostring(ui_.toy):upper(), cx + shift + 90, hud.FLOOR - 12 - ((R.t // 6) % 4 // 2) * 16)
  end
  if ui_.grow_due and (R.t // 30) % 2 == 0 then
    for i, d in ipairs({{-60, 40}, {60, 30}, {0, 0}}) do actor.icon("IC_FX_SPARKLE", cx + d[1], y + d[2] + (i % 2) * 4) end
  end
end

return M
