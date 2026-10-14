-- Aldea: a little top-down adventure, the GBA's RPG look (docs/lua.md).
--   the village was drawn in Tiled (art/aldea.tmx) and imported with tools/tiled2asset.py: three layers, the ground
--   (BG2), what stands on it (BG1) and the tree tops (BG0, in front of the characters, so you walk behind them);
--   which tiles are solid and where people stand come from the map (aldea.lua);
--   dialogue typed out letter by letter in a box (text with a width and a character count); music made of notes.

local LV = require("aldea")
local T, MW, MH = LV.tile_w, LV.width, LV.height
local SPEED = 1.1

state = "title"             -- title, play, talk, fin (globals: the tests look at them)
player = {x = 0, y = 0, dir = 2, step = 0}
npcs, chest = {}, {}
has_key, opened = false, false
dialog = nil                -- {lines, i, chars, name, voice, done}
local people, things
local cam_x, cam_y, timer, play_ticks = 0, 0, 0, 0

local function solid_at(px, py) -- a map pixel: outside the map, or a solid tile on the ground or on what stands on it
  local tx, ty = px // T, py // T
  if tx < 0 or ty < 0 or tx >= MW or ty >= MH then return true end
  local i = ty * MW + tx + 1
  for _, layer in ipairs({LV.layers.suelo, LV.layers.objetos}) do
    local id = layer.data[i]
    if id ~= 0 and LV.tiles[id] and LV.tiles[id].solid then return true end
  end
  return false
end

local function overlaps(x, y, who) -- someone's feet (a 10x6 box) at x, y would touch another's
  local all = {player, chest}
  for _, n in ipairs(npcs) do all[#all + 1] = n end
  for _, o in ipairs(all) do
    if o ~= who and o.x and math.abs(o.x - x) < 11 and math.abs(o.y - y) < 7 then return true end
  end
  return false
end

local function blocked(x, y, who)
  return solid_at(x + 3, y + 10) or solid_at(x + 12, y + 10) or solid_at(x + 3, y + 15) or solid_at(x + 12, y + 15)
         or overlaps(x, y, who)
end

local function reset()
  npcs, has_key, opened, dialog = {}, false, false, nil
  for _, o in ipairs(LV.objects) do -- Tiled's points are where feet stand
    if o.type == "spawn" then player.x, player.y, player.dir = o.x - 8, o.y - 14, 2
    elseif o.type == "npc" then
      npcs[#npcs + 1] = {x = o.x - 8, y = o.y - 14, who = o.props.who, name = o.name, dir = o.props.look or 2,
                         wander = o.props.wander, look_home = o.props.look or 2, step = 0, walk = 0}
    elseif o.type == "chest" then chest = {x = o.x - 8, y = o.y - 14} end
  end
  play_ticks = 0
end

function _init()
  people, things = sheet("PEOPLE"), sheet("THINGS")
  palette("OBJ", true)
  bg(2, {map = "ALDEA_SUELO", prio = 2, wrap = false})
  bg(1, {map = "ALDEA_OBJETOS", prio = 2, wrap = false})
  bg(0, {map = "ALDEA_ALTO", prio = 0, wrap = false})
  backdrop(rgb(30, 70, 40))
  reset()
end

-- what each one says, depending on how far you are
local function lines_for(n)
  if n.who == "abuela" then
    if has_key then return {"¡Esa llave! Ve al prado, al otro lado del puente."} end
    return {"¡Hola! Bienvenida a la aldea.", "El viejo cofre del prado lleva años cerrado. Nadie sabe qué guarda.",
            "Lucio, el pescador, encontró algo en el río esta mañana."}
  elseif n.who == "pescador" then
    if has_key then return {"Que no se te caiga al agua, ¿eh?"} end
    return {"¿Una llave? Sí, la saqué del río con la caña.", "Toma, a mí no me abre nada."},
           function() has_key = true; tone(2, "E5", {wave = "square", duty = 0.25, vol = 0.3, decay = 0.4}) end
  else
    return {"¿Sabías que esta aldea está hecha con pinyol?",
            "El mapa se dibujó en Tiled y el juego entero es un archivo de Lua.", "¡Tú también puedes hacer uno!"}
  end
end

local function talk(lines, name, voice, done)
  dialog = {lines = lines, i = 1, chars = 0, name = name, voice = voice, done = done}
  state = "talk"
end

local function interact() -- what is in front of you
  local fx = player.x + ({0, 12, 0, -12})[player.dir + 1]
  local fy = player.y + ({-10, 0, 10, 0})[player.dir + 1]
  for _, n in ipairs(npcs) do
    if math.abs(n.x - fx) < 12 and math.abs(n.y - fy) < 12 then
      n.dir = (player.dir + 2) % 4 -- turns to you
      local lines, done = lines_for(n)
      talk(lines, n.name, ({abuela = "A4", pescador = "C4", nina = "E5"})[n.who], done)
      return
    end
  end
  if math.abs(chest.x - fx) < 12 and math.abs(chest.y - fy) < 12 then
    if opened then talk({"El cofre está vacío."})
    elseif has_key then
      opened = true
      tone(2, "C5", {wave = "square", vol = 0.3, decay = 0.1})
      talk({"¡Clic! La llave gira...", "Dentro hay un mapa de una consola: la RetroGo. ¡Fin de la aventura!"}, nil, nil,
           function()
             state, timer = "fin", 0
             local best = stored("best")
             if not best or play_ticks < best then store("best", play_ticks) end
           end)
    else talk({"Está cerrado con llave."}) end
  end
end

-- music: a waltz, an eighth note every 15 ticks, six to a bar: the tune on voice 0, oom-pah-pah on voice 1
local TUNE = {{"E5", nil, "G5", nil, "E5", "D5"}, {"C5", nil, "E5", nil, "C5", "B4"},
              {"A4", nil, "C5", nil, "F5", "E5"}, {"D5", nil, "B4", nil, "G4", nil}}
local BASS = {{"C3", "G3"}, {"A2", "E3"}, {"F2", "C3"}, {"G2", "D3"}}
local function music()
  if ticks() % 15 ~= 0 then return end
  local step = ticks() // 15
  local bar, s = step // 6 % 4 + 1, step % 6
  local note = TUNE[bar][s + 1]
  if note then tone(0, note, {wave = "triangle", vol = 0.2, decay = 0.35}) end
  if s % 2 == 0 then
    tone(1, BASS[bar][s == 0 and 1 or 2], {wave = "square", duty = 0.25, vol = s == 0 and 0.1 or 0.05, decay = 0.2})
  end
end

local function wander(n)
  if not n.wander or state == "talk" then return end
  if n.walk <= 0 then -- a new idea every second or so
    n.walk = math.random(30, 90)
    n.moving = math.random(3) > 1
    n.dir = math.random(0, 3)
  end
  n.walk = n.walk - 1
  if n.moving then
    local dx, dy = ({0, 0.5, 0, -0.5})[n.dir + 1], ({-0.5, 0, 0.5, 0})[n.dir + 1]
    if not blocked(n.x + dx, n.y + dy, n) then n.x, n.y, n.step = n.x + dx, n.y + dy, n.step + 1
    else n.walk = 0 end
  end
end

function _update()
  timer = timer + 1
  if state ~= "title" then music() end
  if state == "title" then
    if btnp("a") or select(4, touch()) then state = "play" end
  elseif state == "play" then
    play_ticks = play_ticks + 1
    local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
    if dx ~= 0 then player.dir = dx > 0 and 1 or 3 end
    if dy ~= 0 then player.dir = dy > 0 and 2 or 0 end
    if not blocked(player.x + dx * SPEED, player.y, player) then player.x = player.x + dx * SPEED end
    if not blocked(player.x, player.y + dy * SPEED, player) then player.y = player.y + dy * SPEED end
    player.step = (dx ~= 0 or dy ~= 0) and player.step + 1 or 0
    if btnp("a") then interact() end
  elseif state == "talk" then
    local line = dialog.lines[dialog.i]
    local len = utf8.len(line)
    if dialog.chars < len then
      dialog.chars = dialog.chars + 1
      if dialog.voice and dialog.chars % 3 == 0 then -- a voice made of blips
        tone(3, dialog.voice, {wave = "square", duty = 0.25, vol = 0.08, decay = 0.03})
      end
    end
    if btnp("a") or select(4, touch()) then
      if dialog.chars < len then dialog.chars = len -- all of the line at once
      elseif dialog.i < #dialog.lines then dialog.i, dialog.chars = dialog.i + 1, 0
      else
        local done = dialog.done
        dialog, state = nil, "play"
        if done then done() end
      end
    end
  elseif state == "fin" then
    if timer > 60 and btnp("a") then reset(); state = "play" end
  end
  for _, n in ipairs(npcs) do wander(n) end
end

function _draw()
  cam_x = math.max(0, math.min(MW * T - W, player.x + 8 - W // 2))
  cam_y = math.max(0, math.min(MH * T - H, player.y + 8 - H // 2))
  for n = 0, 2 do scroll(n, cam_x, cam_y) end

  -- characters and the chest, the lower ones in front (sprite 0 is drawn over sprite 1)
  local list = {{o = player, f = player.dir * 2 + (player.step // 10) % 2}}
  for i, n in ipairs(npcs) do
    local who = ({abuela = 1, pescador = 2, nina = 3})[n.who]
    list[#list + 1] = {o = n, f = who * 8 + n.dir * 2 + (n.step // 12) % 2}
  end
  list[#list + 1] = {o = chest, f = opened and 1 or 0, things = true}
  table.sort(list, function(a, b) return a.o.y > b.o.y end)
  spr_clear()
  for i, it in ipairs(list) do
    spr(i, it.things and things or people, it.f, it.o.x - cam_x, it.o.y - cam_y, prio(1))
  end
  if has_key and not opened then spr(0, things, 2, 4, 4, prio(0)) end

  -- its own look: blackletter (fonts/bastarda.fnt, gotica.fnt), a parchment and a wooden sign, made by art.py
  if state == "title" then
    frame("FR_PERGAMI", 100, 58, 280, 174, 2)
    text("La aldea", SCREEN_W // 2, 72, {font = "bastarda", align = "center", color = 0x6A2E10, shadow = 0xC8A060})
    text("Habla con todos.", SCREEN_W // 2, 124, 0x5A3A20, "main", "center")
    text("Hay un cofre cerrado...", SCREEN_W // 2, 150, 0x5A3A20, "main", "center")
    text("A para empezar", SCREEN_W // 2, 188, 0xA03020, "gotica", "center")
  elseif dialog then
    frame("FR_PERGAMI", 12, 212, 456, 98, 2)
    if dialog.name then
      frame("FR_MADERA", 22, 188, textw(dialog.name, "gotica") + 34, 40, 2)
      text(dialog.name, 39, 199, 0x5A2A10, "gotica")
    end
    text(dialog.lines[dialog.i], 32, 234, 0x3A2410, "main", "left", 416, dialog.chars)
    if dialog.chars >= utf8.len(dialog.lines[dialog.i]) and (timer // 20) % 2 == 0 then
      text("A", 444, 282, 0xA03020, "bold")
    end
  elseif state == "fin" then
    frame("FR_PERGAMI", 90, 88, 300, 134, 2)
    text("¡Fin!", SCREEN_W // 2, 100, {font = "bastarda", align = "center", color = 0x6A2E10, shadow = 0xC8A060})
    local best = stored("best", play_ticks)
    text(string.format("%.1f s · récord %.1f s", play_ticks / 60, best / 60), SCREEN_W // 2, 144, 0x506070, "main",
         "center")
    if timer > 60 then text("A: otra vez", SCREEN_W // 2, 180, 0xC04030, "bold", "center") end
  end
end
