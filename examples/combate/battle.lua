-- battle: a fight of turns. Each living member of the party chooses (Atacar, Magia, Objeto, Huir), the enemies choose, then all act
-- in order of speed. The enemies are 64 x 64 sprites turned and scaled by a matrix (they breathe, shake when hit and spin away
-- when beaten); the blocky flash of a hit is the sprites' mosaic. Menus and numbers are drawn at the screen's 480 x 320.
local scene = require("scene")
local R = require("rules")
local ppu = require("ppu")
local ui = require("ui")
local hud = require("hud")

local B = {}

local MENU = {"Atacar", "Magia", "Objeto", "Huir"}
local SPOTS = {{{178, 90}}, {{148, 88}, {204, 94}}, {{120, 86}, {166, 96}, {212, 86}}} -- where 1, 2 or 3 enemies stand (feet)
local SCALE = {1, 0.9, 0.8}                  -- the more of them, the smaller
local PARTY_SPOTS = {{46, 108}, {82, 118}}
local ENEMY_SPRITE, PARTY_SPRITE = 0, 8     -- the sprite numbers they use (the enemies' matrices have the same numbers)
local INTRO, ACT_LEN, HIT_AT = 40, 46, 22   -- ticks: the iris opening, one action, and when in it the blow lands
local PANEL_Y = 236

local sheets, meters
local enemies, phase, t
local cur, menu_i, target_i, picks, queue, qi, action, line, popups, result, flee_tried

local function to(p) phase, t = p, 0 end
local function say(msg) line = msg end

local function living(list)
  local out = {}
  for i, a in ipairs(list) do if a.hp > 0 then out[#out + 1] = i end end
  return out
end

local function first_living_member(from)
  for i = from, #game.party do if game.party[i].hp > 0 then return i end end
end

local function popup(x, y, text, color) popups[#popups + 1] = {x = x, y = y, text = text, color = color or 0xFFFFFF, t = 0} end

local function enemy_pos(i)
  local spots = SPOTS[#enemies]
  return spots[i][1], spots[i][2]
end

-- ------------------------------------------------------------------ choosing
local function begin_choosing()
  cur = first_living_member(1)
  picks, menu_i = {}, 1
  to("menu")
  say(cur and (game.party[cur].name .. ": ¿qué hace?") or "")
end

local function next_member()
  local n = first_living_member(cur + 1)
  if n then
    cur, menu_i = n, 1
    to("menu")
    say(game.party[cur].name .. ": ¿qué hace?")
    return
  end
  local actions = {}
  for i, p in pairs(picks) do
    local m = game.party[i]
    actions[#actions + 1] = {side = "party", i = i, spd = m.spd, kind = p.kind, target = p.target, spell = p.spell}
  end
  local alive_party = living(game.party)
  for i, e in ipairs(enemies) do
    if e.hp > 0 then
      actions[#actions + 1] = {side = "enemy", i = i, spd = e.spd, kind = "attack", target = alive_party[math.random(1, #alive_party)]}
    end
  end
  queue, qi = R.order(actions), 1
  to("acts")
end

local function pick(p)
  picks[cur] = p
  next_member()
end

local function back_one()
  local before
  for i = cur - 1, 1, -1 do if game.party[i].hp > 0 then before = i break end end
  if before then picks[before], cur, menu_i = nil, before, 1 end
  to("menu")
  say(game.party[cur].name .. ": ¿qué hace?")
end

local function choose_target(kind, spell)
  B.pending = {kind = kind, spell = spell}
  local list = kind == "item" and living(game.party) or living(enemies)
  target_i = 1
  if kind ~= "item" and #list == 1 then pick({kind = kind, target = list[1], spell = spell}) return end
  to("target")
  say(kind == "item" and "¿A quién?" or "¿A cuál?")
end

local function menu_update()
  if btnp("up") or btnp("down") then menu_i = ({3, 4, 1, 2})[menu_i] end -- (the other row)
  if btnp("left") or btnp("right") then menu_i = ({2, 1, 4, 3})[menu_i] end
  if btnp("b") and cur > 1 then back_one() return end
  if not btnp("a") then return end
  local m = game.party[cur]
  if menu_i == 1 then choose_target("attack")
  elseif menu_i == 2 then
    local s = R.SPELLS[m.spell]
    if m.mp >= s.mp then choose_target("spell", m.spell) else say("No hay PM para " .. s.name .. ".") sfx("NO") end
  elseif menu_i == 3 then
    if game.potions > 0 then choose_target("item") else say("No quedan pociones.") sfx("NO") end
  else pick({kind = "flee"}) end
end

local function target_update()
  local list = B.pending.kind == "item" and living(game.party) or living(enemies)
  if btnp("right") or btnp("down") then target_i = target_i % #list + 1 elseif btnp("left") or btnp("up") then target_i = (target_i - 2) % #list + 1 end
  if btnp("b") then to("menu") say(game.party[cur].name .. ": ¿qué hace?") return end
  if btnp("a") then pick({kind = B.pending.kind, target = list[target_i], spell = B.pending.spell}) end
end

-- ------------------------------------------------------------------ acting
local function victory_check()
  if #living(enemies) == 0 then return "win" end
  if #living(game.party) == 0 then return "lose" end
end

local function apply(a)
  local actor = a.side == "party" and game.party[a.i] or enemies[a.i]
  if a.kind == "attack" or a.kind == "spell" then
    local power, magic = 1, false
    if a.kind == "spell" then
      local s = R.SPELLS[a.spell]
      power, magic = s.power, s.magic
      actor.mp = actor.mp - s.mp
    end
    if a.side == "party" then
      local e = enemies[a.target]
      local dmg = R.damage(actor.atk, e.def, power, magic)
      e.hp, e.hit = math.max(0, e.hp - dmg), 10
      local ex, ey = enemy_pos(a.target)
      popup(ex * 2, (ey - 50) * 2, tostring(dmg))
      sfx(a.kind == "spell" and "MAGIC" or "HIT")
    else
      local m = game.party[a.target]
      local dmg = R.damage(actor.atk, m.def, 1, false)
      m.hp, m.hurt = math.max(0, m.hp - dmg), 10
      popup(PARTY_SPOTS[a.target][1] * 2, (PARTY_SPOTS[a.target][2] - 24) * 2, tostring(dmg), 0xFF8080)
      sfx("HURT")
    end
  elseif a.kind == "item" then
    local m = game.party[a.target]
    local heal = math.min(R.POTION, m.maxhp - m.hp)
    m.hp, game.potions = m.hp + heal, game.potions - 1
    popup(PARTY_SPOTS[a.target][1] * 2, (PARTY_SPOTS[a.target][2] - 24) * 2, "+" .. heal, 0x80FF90)
    sfx("HEAL")
  elseif a.kind == "flee" then
    local best = 0
    for _, e in ipairs(enemies) do best = math.max(best, e.spd) end
    flee_tried = true
    if math.random() < R.flee_chance(actor.spd, best) then result = "fled" else say("¡No se puede huir!") end
  end
end

local function describe(a)
  local actor = a.side == "party" and game.party[a.i] or enemies[a.i]
  if a.kind == "attack" then return actor.name .. " ataca."
  elseif a.kind == "spell" then return actor.name .. " usa " .. R.SPELLS[a.spell].name .. "."
  elseif a.kind == "item" then return actor.name .. " bebe una poción."
  else return actor.name .. " intenta huir." end
end

local function acts_update()
  local a = queue[qi]
  if not a then -- the turn is over: a side may have fallen in its last blow
    local over = result or victory_check()
    if over then to(over) else begin_choosing() end
    return
  end
  local actor = a.side == "party" and game.party[a.i] or enemies[a.i]
  if actor.hp <= 0 then qi = qi + 1 t = 0 return end -- (beaten before its turn)
  if a.kind ~= "item" and a.kind ~= "flee" and a.side == "party" and enemies[a.target].hp <= 0 then -- its target went: another one
    local alive = living(enemies)
    if #alive == 0 then qi = #queue + 1 return end -- (nothing left to hit: the next tick says who won)
    a.target = alive[1]
  end
  if a.side == "enemy" and game.party[a.target].hp <= 0 then
    local alive = living(game.party)
    if #alive == 0 then qi = #queue + 1 return end
    a.target = alive[1]
  end
  if t == 1 then say(describe(a)) end
  if t == HIT_AT then apply(a) end
  if t >= ACT_LEN then
    qi, t = qi + 1, 0
    local over = result or victory_check()
    if over then to(over) end
  end
end

-- ------------------------------------------------------------------ the end
local function finish_win()
  local xp = 0
  for _, e in ipairs(enemies) do xp = xp + e.xp end
  local lines = {string.format("¡Victoria! %d de experiencia.", xp)}
  for i, m in ipairs(game.party) do
    if m.hp > 0 then
      local up, gained = R.award(m, xp)
      game.party[i] = up
      if gained > 0 then lines[#lines + 1] = string.format("%s sube a nivel %d.", up.name, up.lv) end
    end
  end
  if math.random() < 0.5 then game.potions, lines[#lines + 1] = game.potions + 1, "Encuentras una poción." end
  game.wins = game.wins + 1
  store("save", {party = game.party, potions = game.potions, wins = game.wins, x = game.x, y = game.y, dir = game.dir})
  B.win_lines = lines
  tone(0, "C5", {wave = "square", vol = 0.3, decay = 0.2})
  tone(1, "E5", {wave = "square", vol = 0.3, decay = 0.3, attack = 0.1})
  tone(2, "G5", {wave = "square", vol = 0.3, decay = 0.5, attack = 0.2})
end

local function leave()
  scene.go(require("field"), nil, {fade = 0.7, transition = "blocks", size = 24})
end

-- ------------------------------------------------------------------ scene
function B.enter(args)
  ppu.reset()
  palette("WORLD")
  palette("OBJ", true)
  sheets = {enemies = sheet("ENEMIES"), party = sheet("PARTY")}
  bg(0)
  bg(1)
  bg(2)
  bg(3, {map = "BACKDROP", prio = 3, wrap = false})
  backdrop(0)
  enemies, popups, result, flee_tried, B.win_lines = R.encounter(args.zone), {}, nil, false, nil
  for _, e in ipairs(enemies) do e.hit, e.vanish = 0, nil end
  meters = {}
  for i = 1, #game.party do meters[i] = hud.meter({x = 254, y = 262 + (i - 1) * 36, w = 118, h = 8, segments = 12, color = 0x60D878, speed = 0.04}) end
  to("intro")
  say("¡Aparecen enemigos!")
  sfx("APPEAR")
end

function B.update()
  t = t + 1
  hud.update()
  for i, m in ipairs(game.party) do
    meters[i]:set(m.hp / m.maxhp)
    meters[i]:update()
    meters[i].o.color = m.hp / m.maxhp < 0.3 and 0xE86060 or 0x60D878
    if m.hurt and m.hurt > 0 then m.hurt = m.hurt - 1 end
  end
  local blocky = false
  for _, e in ipairs(enemies) do
    if e.hit > 0 then e.hit, blocky = e.hit - 1, true end
    if e.hp <= 0 and not e.vanish then e.vanish = 0 end
    if e.vanish then e.vanish = e.vanish + 1 end
  end
  mosaic(1, 1, blocky and 3 or 1, blocky and 3 or 1)
  for i = #popups, 1, -1 do
    popups[i].t = popups[i].t + 1
    if popups[i].t > 40 then table.remove(popups, i) end
  end

  if phase == "intro" then
    local k = math.min(1, t / INTRO)
    ppu.iris(176, 80, 150 * k)
    fade("light", ALL, math.max(0, math.floor(16 * (1 - k * 2) + 0.5)))
    if t >= INTRO then
      ppu.iris_off()
      fx_off()
      begin_choosing()
    end
  elseif phase == "menu" then menu_update()
  elseif phase == "target" then target_update()
  elseif phase == "acts" then acts_update()
  elseif phase == "win" then
    if t == 1 then finish_win() end
    if t > 30 and btnp("a") then leave() end
  elseif phase == "fled" then
    if t == 1 then say("¡Habéis escapado!") end
    if t > 30 and btnp("a") then leave() end
  elseif phase == "lose" then
    if t == 1 then say("El grupo cae...") sfx("DRAIN") end
    if t > 60 and btnp("a") then
      game.party = R.new_party()
      game.potions = 3
      scene.go(require("title"), nil, {fade = 0.6})
    end
  end
end

-- ------------------------------------------------------------------ drawing
local function draw_sprites()
  local tick = ticks()
  for i, e in ipairs(enemies) do
    local x, y = enemy_pos(i)
    local slide = phase == "intro" and (1 - math.min(1, t / INTRO)) * 90 or 0
    local base = SCALE[#enemies]
    local sx, sy, deg = base * (1 + 0.03 * math.sin(tick / 14 + i)), base * (1 + 0.05 * math.sin(tick / 10 + i * 2)), 0
    local shake = e.hit > 0 and (e.hit % 2 == 0 and 3 or -3) or 0
    if e.vanish then
      local k = math.min(1, e.vanish / 24)
      sx, sy, deg = base * (1 - k), base * (1 - k), k * 540
    end
    if not e.vanish or e.vanish < 24 then
      mat(ENEMY_SPRITE + i - 1, deg, sx, sy)
      spr(ENEMY_SPRITE + i - 1, sheets.enemies, e.frame, math.floor(x - 32 + shake + slide), y - 58,
          prio(1) | spr_mat(ENEMY_SPRITE + i - 1) | (e.vanish and DOUBLE or 0) | MOSAIC) -- (the double area costs 4 times the pixels: only while it spins)
    else
      spr_off(ENEMY_SPRITE + i - 1)
    end
  end
  for i, m in ipairs(game.party) do
    local fx, fy = PARTY_SPOTS[i][1], PARTY_SPOTS[i][2]
    local lunge = (phase == "acts" and queue[qi] and queue[qi].side == "party" and queue[qi].i == i and t > 6 and t < 34) and 12 or 0
    local drop = m.hp <= 0 and 8 or 0
    spr(PARTY_SPRITE + i - 1, sheets.party, m.sprite, fx - 16 + lunge + (m.hurt and m.hurt > 0 and (m.hurt % 2 == 0 and 2 or -2) or 0), fy - 30 + drop,
        prio(1) | (m.hp <= 0 and BLEND or 0))
  end
end

local function draw_menu()
  ui.box(0, PANEL_Y, 480, 84)
  local msg = line or ""
  if phase == "menu" and menu_i == 2 then
    local sp = R.SPELLS[game.party[cur].spell]
    msg = string.format("%s: %d PM", sp.name, sp.mp)
  elseif phase == "menu" and menu_i == 3 then
    msg = string.format("Poción: cura %d PV   (quedan %d)", R.POTION, game.potions)
  end
  text(msg, 14, PANEL_Y + 8, {font = "main", color = 0xFFFFFF})
  if phase == "menu" then
    for i, name in ipairs(MENU) do
      local x, y = 24 + ((i - 1) % 2) * 112, PANEL_Y + 32 + ((i - 1) // 2) * 24
      local m = game.party[cur]
      local dim = (i == 2 and m.mp < R.SPELLS[m.spell].mp) or (i == 3 and game.potions == 0)
      text((i == menu_i and "> " or "  ") .. name, x, y, {font = "bold", color = dim and 0x808898 or (i == menu_i and 0xFFE070 or 0xFFFFFF)})
    end
  elseif phase == "target" then
    local list = B.pending.kind == "item" and living(game.party) or living(enemies)
    local idx = list[target_i]
    local x, y
    if B.pending.kind == "item" then x, y = PARTY_SPOTS[idx][1] * 2, (PARTY_SPOTS[idx][2] - 36) * 2
    else local ex, ey = enemy_pos(idx) x, y = ex * 2, (ey - 62) * 2 end
    text("v", x, y + math.floor(2 * math.sin(ticks() / 5)), {font = "large_bold", align = "center", color = 0xFFE070})
  elseif phase == "win" and B.win_lines then
    for i, l in ipairs(B.win_lines) do text(l, 14, PANEL_Y + 8 + (i - 1) * 16, {font = "main", color = i == 1 and 0xFFE070 or 0xFFFFFF}) end
    if t > 30 then text("A: seguir", 14, PANEL_Y + 66, {font = "main", color = 0x9CB0C8}) end
  end
  for i, m in ipairs(game.party) do
    local y = PANEL_Y + 8 + (i - 1) * 36
    local ink = m.hp > 0 and ui.INK or ui.DIM
    text(string.format("%s  Nv%d", m.name, m.lv), 252, y, {font = "main", color = ink})
    text(string.format("PV %d/%d", m.hp, m.maxhp), 468, y, {font = "main", color = ink, align = "right"})
    text(string.format("PM %d/%d", m.mp, m.maxmp), 384, y + 16, {font = "main", color = ui.SUB})
    meters[i].o.x, meters[i].o.y = 254, y + 20
    meters[i]:draw()
  end
end

function B.draw()
  draw_sprites()
  for _, p in ipairs(popups) do
    text(p.text, p.x, p.y - p.t * 0.6, {font = "large_bold", align = "center", color = p.color})
  end
  if phase ~= "intro" then draw_menu() end
end

return B
