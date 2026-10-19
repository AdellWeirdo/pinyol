-- screens: everything that is not the room, the board's screens (platforms/esp32s3/screens.py, renderer.py) in
-- Game Boy windows: a submenu's options as a list over the menu, Estado's pages, Ajustes, Sistema, her questions
-- (Sí/No), the guide, hide and seek's bar and the day with Sancho. They only draw the snapshot.
local ui = require("ui")
local hud = require("hud")
local strings = require("strings")
local stickers = require("core.stickers")
local visitors = require("core.visitors")
local T = ui.T
local S = strings.T
local M = {}

local LIST_ICON = {
  ["Siguela por la casa"] = "SUB_SIGUELA", ["Quita nudos"] = "OPT_YARN", ["Palito con plumas"] = "SUB_PLUMAS",
  ["Trile de cajas"] = "SUB_TRILE", ["Simón"] = "SUB_SIMON", ["Puntero láser"] = "SUB_LASER",
  Cepillarla = "SUB_CEPILLO", Medicina = "SUB_MEDICINA", Veterinario = "SUB_VETERINARIO", Leche = "SUB_LECHE",
  Pienso = "SUB_PIENSO", Latas = "SUB_LATAS", Chuches = "SUB_CHUCHES", Yogurt = "SUB_YOGURT", Sandia = "SUB_SANDIA",
  Sonido = "SUB_SONIDO", Micro = "SUB_MICRO", Amigos = "SUB_AMIGOS", Idioma = "SUB_IDIOMA", Nombre = "SUB_NOMBRE",
  ["Guía"] = "SUB_GUIA", Salir = "SUB_SALIR", Calabaza = "SUB_CALABAZA", Pavo = "SUB_PAVO", ["Turrón"] = "SUB_TURRON",
  Gambas = "SUB_GAMBAS", ["Roscón"] = "SUB_ROSCON", ["Butifarra d'ou"] = "SUB_BUTIFARRA", Mona = "SUB_MONA",
  Coca = "SUB_COCA", ["Pa amb tomàquet"] = "SUB_PA_AMB_TOMAQUET", ["Bañarla"] = "MENU_BATH", Arenero = "SUB_ARENERO",
}
local STICKER_ICONS = {comida = "OPT_MEAL", mimos = "FX_HEART", bano = "MENU_BATH", juego = "SUB_PLUMAS",
  encontrada = "SUB_SIGUELA", veterinario = "SUB_VETERINARIO", favorita = "ST_HEART2", amigo = "SUB_AMIGOS",
  tesoro = "LEGADO_PIEDRA", cielo = "ST_COMET", juvenil = "ST_PAW", adulta = "ST_HEART", tres_estrellas = "ST_STAR",
  todos_los_juegos = "SUB_SIMON", semana = "ST_SPARKLE", mes = "ST_SPARKLE2"}
local ROWS_SHOWN = 4
local ROW = 36

local function icon_c(id, cx, cy) -- centred, world scale
  local w, h = imgsize("IC_" .. id)
  if w then img("IC_" .. id, cx - w, cy - h, {scale = 2}) return true end
  return false
end

local function contains(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end

-- a submenu: its options in a window over the menu, the picked one marked; a locked one in a lighter tone with
-- when it opens; values beside settings; a wait or a note under the picked one's name
local function dropdown(ui_, items, index, o)
  o = o or {}
  local locked, fresh, values = o.locked or {}, o.fresh or {}, o.values
  local n = #items
  local shown = math.min(n, ROWS_SHOWN)
  local first = n > shown and math.max(0, math.min(n - shown, index - shown // 2)) or 0
  local w, h = 440, shown * ROW + 24 + (o.title and 28 or 0)
  local x, y = 20, hud.MENU_Y - h - 4
  ui.box(x, y, w, h)
  local ty = y + 12
  if o.title then ui.text(o.title, x + 16, ty + 2, T[3]) ty = ty + 28 end
  for r = 0, shown - 1 do
    local i = first + r
    local item = items[i + 1]
    local ry = ty + r * ROW
    local lock = locked[item]
    if i == index then rect(x + 8, ry - 2, w - 16, ROW - 2, T[2]) ui.cursor(x + 12, ry + 9) end
    icon_c(LIST_ICON[item] or "", x + 44, ry + 15)
    local label = strings.label(item, ui_.name)
    if values and values[i + 1] and values[i + 1] ~= "" then label = label .. ": " .. values[i + 1] end
    ui.text(label, x + 66, ry + 8, lock and T[2] or T[4])
    if contains(fresh, item) and (o.t // 12) % 2 == 0 then ui.text("!", x + w - 26, ry + 8, T[4]) end
  end
  if first > 0 then tri(x + w - 30, y + 18, x + w - 18, y + 18, x + w - 24, y + 10, T[4]) end
  if first + shown < n then tri(x + w - 30, y + h - 18, x + w - 18, y + h - 18, x + w - 24, y + h - 10, T[4]) end
  -- the picked one's note, on the menu's strip: when a locked one opens, or a wait
  local item = items[index + 1]
  local note
  if item and locked[item] then note = strings.label(item, ui_.name) .. " · " .. strings.opens(locked[item], ui_.age_days)
  elseif o.note then note = o.note end
  if note then
    ui.box(0, hud.MENU_Y, 480, 40)
    ui.text(note, 240, hud.MENU_Y + 12, T[4], "center")
    return true
  end
  return false
end

function M.feed(ui_, t)
  local left = ui_.feed_cd_sec_left or 0
  return dropdown(ui_, ui_.feed_options or {}, ui_.feed_choice or 0,
                  {locked = ui_.unlocks, note = left > 0 and S.wait:format(left) or nil, t = t})
end

function M.play(ui_, t)
  local left = ui_.play_cd_sec_left or 0
  return dropdown(ui_, ui_.play_options or {}, ui_.play_choice or 0,
                  {locked = ui_.unlocks, fresh = ui_.new_games, note = left > 0 and S.wait:format(left) or nil, t = t})
end

function M.heal(ui_, t) return dropdown(ui_, ui_.heal_options or {}, ui_.heal_choice or 0, {t = t}) end
function M.bath(ui_, t) return dropdown(ui_, ui_.bath_options or {}, ui_.bath_choice or 0, {t = t}) end

function M.settings(ui_, t)
  local sm, vol = ui_.sound_mode or 0, ui_.volume or 1
  local value = {
    Sonido = sm ~= 0 and S.sound[sm + 1] or S.volumes[vol + 1],
    Micro = S.onoff[ui_.mic_on and 1 or 2],
    Amigos = S.onoff[ui_.friends_on and 1 or 2],
    Idioma = ui_.language or "es",
    Nombre = tostring(ui_.name or ""):sub(1, 10),
  }
  local options = ui_.settings_options or {}
  local values = {}
  for i, o in ipairs(options) do values[i] = value[o] or "" end
  return dropdown(ui_, options, ui_.settings_index or 0, {values = values, t = t, title = "Ajustes"})
end

function M.system(ui_, t)
  ui.box(40, 60, 400, 200)
  ui.text(S.system, 240, 76, T[4], "center")
  for i, o in ipairs(ui_.system_options or {}) do
    local y = 108 + (i - 1) * 30
    if i - 1 == (ui_.system_index or 0) then ui.cursor(70, y) end
    ui.text(o, 92, y, T[4])
  end
  ui.text(S.confirm_hold, 240, 232, T[3], "center")
end

-- ------------------------------------------------------------------ Estado

local function page_header(title, page, pages, count)
  cls(T[1])
  ui.box(0, 0, 480, 320)
  ui.text(string.format("%s %d/%d", title, page + 1, pages), 20, 18, T[4])
  if count then ui.text(count, 460, 18, T[3], "right") end
  tri(8, 26, 14, 20, 14, 32, T[3]) tri(472, 26, 466, 20, 466, 32, T[3])
  rect(16, 42, 448, 2, T[3])
end

local function disc(cx, cy, r, id, earned)
  circ(cx, cy, r + 2, T[4])
  circ(cx, cy, r, earned and T[1] or T[2])
  if not earned then ui.text("?", cx, cy - 8, T[3], "center") return end
  icon_c(id, cx, cy)
end

local function stats_page(ui_)
  local st = ui_.stats or {}
  local rows = {{S.hunger, "Hambre"}, {S.affection, "Afecto"}, {S.energy, "Energía"}, {S.health, "Salud"},
                {S.dirt, "Suciedad"}}
  for i, r in ipairs(rows) do
    local y = 56 + (i - 1) * 40
    ui.text(r[1], 24, y, T[4])
    ui.text(tostring(st[r[2]] or 0), 456, y, T[4], "right")
    rect(24, y + 20, 432, 8, T[4])
    rect(26, y + 22, 428, 4, T[1])
    rect(26, y + 22, 428 * math.max(0, math.min(100, st[r[2]] or 0)) // 100, 4, T[3])
  end
  ui.text(S.weight_height:format(tostring(st.PesoKg or "-"), tostring(st.AlturaCm or "-")), 24, 262, T[3])
  if ui_.overweight then ui.text(S.overweight, 24, 286, T[4]) end
end

local function events_page(ui_)
  local ev = ui_.events or {}
  if #ev == 0 then ui.text(S.no_events, 240, 160, T[3], "center") return end
  local y = 56
  for i = math.max(1, #ev - 9), #ev do
    ui.text(tostring(ev[i]):sub(1, 28), 24, y, T[4])
    y = y + 24
  end
end

local function who_she_is(ui_)
  local lines = {}
  if ui_.about then lines[#lines + 1] = S.about[ui_.about] or "" end
  local nick = S.nicknames[ui_.nickname or ""]
  if nick then lines[#lines + 1] = S.called:format(ui_.name or "", nick) end
  if ui_.favorite_known then lines[#lines + 1] = S.loves:format(ui_.favorite_known) end
  if ui_.fav_game then lines[#lines + 1] = S.loves_game:format(strings.label(ui_.fav_game, ui_.name)) end
  if ui_.fav_room then lines[#lines + 1] = S.fav_room:format(ui_.fav_room) end
  if ui_.fav_time then lines[#lines + 1] = S.fav_times[ui_.fav_time] or "" end
  if ui_.toy then lines[#lines + 1] = S.toy_line:format(S.toys[ui_.toy] or "") end
  if ui_.friends and #ui_.friends > 0 then
    local f = {}
    for i = 1, math.min(3, #ui_.friends) do f[i] = ui_.friends[i] end
    lines[#lines + 1] = S.friends_line:format(table.concat(f, ", "))
  end
  return lines
end
M.who_she_is = who_she_is

local function about_page(ui_)
  ui.text(S.phase:format(ui_.phase or "-"), 24, 56, T[4])
  ui.text(S.day_age:format(ui_.day or 1, ui_.age_days or 0), 24, 80, T[4])
  local lines = {S.moods[ui_.mood] or ""}
  for _, l in ipairs(who_she_is(ui_)) do lines[#lines + 1] = l end
  local y = 116
  for _, l in ipairs(lines) do
    for _, chunk in ipairs(ui.wrap(l, 27)) do
      if y < 300 then ui.text(chunk, 24, y, T[4]) end
      y = y + 20
    end
  end
end

local function album_page(ui_)
  local earned = {}
  for _, id in ipairs(ui_.stickers or {}) do earned[id] = true end
  for i, sid in ipairs(stickers.IDS) do
    local cx, cy = 60 + ((i - 1) % 6) * 72, 84 + ((i - 1) // 6) * 72
    disc(cx, cy, 26, STICKER_ICONS[sid] or sid:upper(), earned[sid])
  end
end

local function three_a_row(i, n, x_step) -- i 0-based: (column offset) centring the last row
  local in_row = math.min(3, n - (i // 3) * 3)
  return (2 * (i % 3) - in_row + 1) * x_step
end

local function gifts_page(ui_)
  local got = {}
  for _, g in ipairs(ui_.gifts or {}) do got[g[1]] = g[2] end
  for i, a in ipairs(visitors.ANIMALS) do
    local gift = visitors.GIFTS[a]
    local cx, cy = 240 + three_a_row(i - 1, #visitors.ANIMALS, 76), 80 + ((i - 1) // 3) * 86
    disc(cx, cy, 24, "REGALO_" .. gift:upper(), got[gift] ~= nil)
    ui.text(got[gift] and S.gift_names[gift] or "???", cx, cy + 30, got[gift] and T[4] or T[3], "center")
  end
end

local function friends_page(ui_)
  local met = {}
  for _, a in ipairs(ui_.animals or {}) do met[a] = true end
  for i, a in ipairs(visitors.ANIMALS) do
    local cx, cy = 240 + three_a_row(i - 1, #visitors.ANIMALS, 76), 84 + ((i - 1) // 3) * 86
    circ(cx, cy, 30, T[4]) circ(cx, cy, 28, met[a] and T[1] or T[2])
    if met[a] then
      local w, h = imgsize("IC_VISITA_" .. a:upper())
      if w then img("IC_VISITA_" .. a:upper(), cx - w // 2, cy - h // 2) end
    else ui.text("?", cx, cy - 8, T[3], "center") end
    ui.text(met[a] and S.animals[a] or "???", cx, cy + 34, met[a] and T[4] or T[3], "center")
  end
end

function M.status(ui_)
  local pages = ui_.status_pages or {"Stats"}
  local page = math.max(0, math.min(#pages - 1, ui_.status_page or 0))
  local name = pages[page + 1]
  local count
  if name == "Álbum" then count = string.format("%d/%d", #(ui_.stickers or {}), #stickers.IDS)
  elseif name == "Regalos" then count = string.format("%d/%d", #(ui_.gifts or {}), #visitors.ANIMALS)
  elseif name == "Amigos" then count = string.format("%d/%d", #(ui_.animals or {}), #visitors.ANIMALS) end
  page_header(name, page, #pages, count)
  local draw = ({Stats = stats_page, Eventos = events_page, ["Álbum"] = album_page, Regalos = gifts_page,
                 Amigos = friends_page})[name] or about_page
  draw(ui_)
end

-- ------------------------------------------------------------------ questions, the guide, Sancho, hide and seek

function M.question(ui_, key, yes)
  local x, y, w, h = 40, 70, 400, 170
  ui.box(x, y, w, h)
  local name = ui_.name or "Audrey"
  ui.text(S[key .. "_ask"]:format(name), 240, y + 20, T[4], "center")
  ui.text(S[key .. "_ask2"], 240, y + 44, T[4], "center")
  ui.text(S[key .. "_note"], 240, y + 74, T[3], "center")
  local labels = S[key .. "_yes"] and {S[key .. "_yes"], S[key .. "_no"]} or {S.yes, S.no}
  for i, l in ipairs(labels) do
    local bx = x + 60 + (i - 1) * 170
    local picked = (i == 1) == (yes and true or false)
    if picked then rect(bx - 6, y + 112, 130, 36, T[4]) rect(bx - 4, y + 114, 126, 32, T[2]) ui.cursor(bx, y + 122) end
    ui.text(l, bx + 20, y + 122, T[4])
  end
end

function M.guide()
  cls(T[1])
  ui.box(20, 20, 440, 280)
  local w, h = imgsize("TITLE_LOGO")
  img("TITLE_LOGO", 240 - w // 2, 34, {scale = 1})
  ui.text(S.guide_title, 240, 112, T[4], "center")
  for i, g in ipairs(S.guide) do
    ui.text(g[1], 200, 140 + (i - 1) * 28, T[4], "right")
    ui.text(g[2], 224, 140 + (i - 1) * 28, T[3])
  end
  ui.text(S.guide_go, 240, 266, T[4], "center")
end

function M.away(ui_)
  local left = ui_.sitter_left_min or 0
  ui.box(0, hud.MENU_Y - 56, 480, 320 - hud.MENU_Y + 56)
  ui.text(S.away_title:format(ui_.name or "Audrey"), 240, hud.MENU_Y - 42, T[4], "center")
  ui.text(S.away_left:format(left // 60, left % 60), 240, hud.MENU_Y - 18, T[3], "center")
  ui.text(S.away_pick, 240, hud.MENU_Y + 10, T[4], "center")
end

-- hide and seek: the rooms as little pictures (here framed, searched in vain struck out), and three paws,
-- darker the warmer the room on screen (seek_warm)
function M.seek(ui_, t)
  ui.box(0, hud.MENU_Y - 20, 480, 320 - hud.MENU_Y + 20)
  local rooms = {"ROOM_LIVING", "ROOM_KITCHEN", "ROOM_RASCA", "ROOM_STUDIO", "ROOM_WC"}
  local here, searched = ui_.scene_idx or 0, ui_.seek_searched or 0
  for i, id in ipairs(rooms) do
    local cx = 40 + (i - 1) * 64
    local cy = hud.MENU_Y + 8
    if i - 1 == here then rect(cx - 28, cy - 22, 56, 44, T[4]) rect(cx - 26, cy - 20, 52, 40, T[2]) end
    icon_c(id, cx, cy)
    if (searched >> (i - 1)) & 1 == 1 and i - 1 ~= here then
      line(cx - 20, cy - 16, cx + 20, cy + 16, T[4]) line(cx - 19, cy - 16, cx + 21, cy + 16, T[4])
    end
    if ui_.seek_hint == i - 1 and (t // 8) % 2 == 0 then icon_c("FX_SPARKLE", cx, cy - 30) end
  end
  local warm = ui_.seek_warm or 0
  for i = 0, 2 do
    local cx = 372 + i * 36
    local id = "FX_PAW"
    if i <= warm then icon_c(id, cx, hud.MENU_Y + 8)
    else circ(cx, hud.MENU_Y + 8, 4, T[2]) end
  end
end

function M.off()
  cls(T[4])
  ui.text(S.off, 240, 140, T[2], "center")
  ui.text(S.wake, 240, 168, T[2], "center")
end

return M
