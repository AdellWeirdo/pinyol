-- play: the battlefield. Blue is yours: pick a unit (A), its reach shows in blue (a second layer of the picture, its tiles changed with mset
-- and blended over the ground), choose where to stand, then Atacar or Esperar. START ends your turn; C shows where red could hit next turn
-- (orange). Red plays by itself (ai.lua). With `auto_blue` set both sides do, which is the demonstration on the title and the tests' game.
local scene = require("scene")
local R = require("rules")
local AI = require("ai")
local ui = require("ui")
local DATA = require("data")

local P = {}

local CELL = 16                       -- a cell, in the picture's pixels (the screen is 240 x 160, 15 x 10 cells)
local WALK_TICKS, STRIKE_TICKS, FALL_TICKS, PAUSE = 5, 28, 18, 24
local EMPTY, BLUE, RED, ORANGE
local units_sheet, cursor_sheet
local phase, t
local cur = {x = 1, y = 3}
local sel, from, reach, reach_set, menu_i, target_i, targets, painted
local anim, popups, events, ai_queue, danger_on, danger_layer

game = nil -- {state, auto_blue}: global, so the scenes and the tests read it

local function key(x, y) return y * 100 + x end
local function to(p)
  phase, t = p, 0
  if game then game.phase = p end -- (read by the tests)
end
local function popup(cx, cy, text, color) popups[#popups + 1] = {x = cx * 32 + 16, y = cy * 32 - 4, text = text, color = color or 0xFFFFFF, t = 0} end

-- ------------------------------------------------------------------ the highlight layer
local function put(cells, tile)
  for _, c in ipairs(cells) do
    for dy = 0, 1 do for dx = 0, 1 do mset(1, c[1] * 2 + dx, c[2] * 2 + dy, tile) end end
    painted[#painted + 1] = c
  end
end

local function clear_layer()
  for _, c in ipairs(painted) do
    for dy = 0, 1 do for dx = 0, 1 do mset(1, c[1] * 2 + dx, c[2] * 2 + dy, EMPTY) end end
  end
  painted = {}
end

local function cells_of(list) -- {x, y, cost} entries to {x, y}
  local out = {}
  for _, c in ipairs(list) do out[#out + 1] = {c.x, c.y} end
  return out
end

local function refresh()
  clear_layer()
  local st = game.state
  if danger_on and danger_layer then
    local cells = {}
    for y = 0, st.h - 1 do for x = 0, st.w - 1 do if danger_layer:get(x, y) > 0 then cells[#cells + 1] = {x, y} end end end
    put(cells, ORANGE)
  end
  if phase == "move" and reach then put(cells_of(reach), BLUE) end
  if phase == "target" and targets then
    local cells = {}
    for _, o in ipairs(targets) do cells[#cells + 1] = {o.x, o.y} end
    put(cells, RED)
  end
end

local function recompute_danger()
  danger_layer = R.danger(game.state, game.state.side == "blue" and "red" or "blue")
end

-- ------------------------------------------------------------------ turns
local function save()
  local units = {}
  for _, u in ipairs(game.state.units) do units[#units + 1] = {id = u.id, team = u.team, kind = u.kind, x = u.x, y = u.y, hp = u.hp} end
  store("save", {units = units, turn = game.state.turn, side = game.state.side})
end

local function begin_side()
  local st = game.state
  ai_queue = {}
  local auto = st.side == "red" or game.auto_blue
  if auto then
    for _, u in ipairs(st.units) do if u.team == st.side then ai_queue[#ai_queue + 1] = u.id end end
    to("ai")
  else
    to("select")
    for _, u in ipairs(st.units) do if u.team == "blue" then cur.x, cur.y = u.x, u.y break end end
  end
  recompute_danger()
  refresh()
end

local function end_turn()
  game.state = R.end_turn(game.state)
  save()
  sfx("TURN")
  begin_side()
end

local function check_over()
  local w = R.winner(game.state)
  if w then
    game.winner = w
    to("over")
    sfx(w == "blue" and "WIN" or "LOSE")
    store("save", nil)
    return true
  end
end

local function all_done(side)
  for _, u in ipairs(game.state.units) do if u.team == side and not u.acted then return false end end
  return true
end

-- a blow: the lunge, the numbers and what falls; applies rules.strike and plays its events
local function start_strike(att_id, def_id)
  local att, def = R.unit(game.state, att_id), R.unit(game.state, def_id)
  local st, ev = R.strike(game.state, att_id, def_id)
  anim = {kind = "strike", att = att_id, def = def_id, ax = att.x, ay = att.y, dx = def.x, dy = def.y, state = st, events = ev,
          shown = 0}
  to("strike")
end

local function play_events()
  local ev = anim.events
  for i = anim.shown + 1, #ev do
    local e = ev[i]
    local u = R.unit(game.state, e.id)
    if e.kind == "hit" or e.kind == "counter" then
      popup(u.x, u.y, tostring(e.dmg), e.kind == "hit" and 0xFFFFFF or 0xFF9090)
      sfx("HIT")
    end
  end
  anim.shown = #ev
end

local function finish_strike()
  local att_id = anim.att
  game.state = anim.state
  local alive = R.unit(game.state, att_id)
  if alive then game.state = R.finish(game.state, att_id) end
  recompute_danger()
  anim = nil
  if check_over() then return end
  sel = nil
  if game.state.side == "red" or game.auto_blue then to("ai")
  elseif all_done("blue") then end_turn() return
  else to("select") end
  refresh()
end

-- ------------------------------------------------------------------ player's phases
local function select_unit(u)
  sel, from = u.id, {u.x, u.y}
  reach = R.reach(game.state, u)
  reach_set = {}
  for _, c in ipairs(reach) do reach_set[key(c.x, c.y)] = c end
  to("move")
  refresh()
  sfx("PICK")
end

local function cursor_move()
  local st = game.state
  local dx = (btnp("right", 14, 4) and 1 or 0) - (btnp("left", 14, 4) and 1 or 0)
  local dy = (btnp("down", 14, 4) and 1 or 0) - (btnp("up", 14, 4) and 1 or 0)
  if dx ~= 0 or dy ~= 0 then
    cur.x, cur.y = math.max(0, math.min(st.w - 1, cur.x + dx)), math.max(0, math.min(st.h - 1, cur.y + dy))
  end
end

local function walk_to(x, y)
  local u = R.unit(game.state, sel)
  local _, g = R.reach(game.state, u)
  local path = g:path(u.x, u.y, x, y)
  anim = {kind = "walk", id = sel, path = path or {}, i = 1, px = u.x * CELL, py = u.y * CELL, fx = u.x * CELL, fy = u.y * CELL, dest = {x, y}}
  to("walk")
end

local function select_update()
  cursor_move()
  local st = game.state
  if btnp("c") then danger_on = not danger_on refresh() end
  if btnp("start") then end_turn() return end
  if btnp("a") then
    local u = R.unit_at(st, cur.x, cur.y)
    if u and u.team == "blue" and not u.acted then select_unit(u)
    elseif u and u.team == "red" then danger_on = true sfx("PICK") refresh() else sfx("NO") end
  end
end

local function move_update()
  cursor_move()
  if btnp("b") then sel = nil to("select") refresh() return end
  if btnp("a") then
    local c = reach_set[key(cur.x, cur.y)]
    if c then walk_to(c.x, c.y) else sfx("NO") end
  end
end

local function menu_items()
  local u = R.unit(game.state, sel)
  local items = {}
  if #R.targets(game.state, u, u.x, u.y) > 0 then items[#items + 1] = "Atacar" end
  items[#items + 1] = "Esperar"
  return items
end

local function menu_update()
  local items = menu_items()
  if btnp("up") then menu_i = (menu_i - 2) % #items + 1 elseif btnp("down") then menu_i = menu_i % #items + 1 end
  if btnp("b") then -- take the move back
    game.state = R.move(game.state, sel, from[1], from[2])
    cur.x, cur.y = from[1], from[2]
    select_unit(R.unit(game.state, sel))
    return
  end
  if btnp("a") then
    if items[menu_i] == "Atacar" then
      local u = R.unit(game.state, sel)
      targets, target_i = R.targets(game.state, u, u.x, u.y), 1
      to("target")
      refresh()
    else
      game.state = R.finish(game.state, sel)
      sel = nil
      to("select")
      refresh()
      if all_done("blue") then end_turn() end
    end
  end
end

local function target_update()
  if btnp("right") or btnp("down") then target_i = target_i % #targets + 1 elseif btnp("left") or btnp("up") then target_i = (target_i - 2) % #targets + 1 end
  cur.x, cur.y = targets[target_i].x, targets[target_i].y
  if btnp("b") then to("menu") menu_i = 1 refresh() return end
  if btnp("a") then clear_layer() start_strike(sel, targets[target_i].id) end
end

-- ------------------------------------------------------------------ animation phases
local function walk_update()
  local a = anim
  local step = a.path[a.i]
  if not step then -- arrived
    game.state = R.move(game.state, a.id, a.dest[1], a.dest[2])
    cur.x, cur.y = a.dest[1], a.dest[2]
    anim = nil
    clear_layer()
    if game.state.side == "red" or game.auto_blue then
      local d = P.pending
      if d and d.target then start_strike(a.id, d.target) return end
      game.state = R.finish(game.state, a.id)
      to("ai")
    else
      menu_i = 1
      to("menu")
    end
    return
  end
  a.st = (a.st or 0) + 1
  local tx, ty = step[1] * CELL, step[2] * CELL
  local k = a.st / WALK_TICKS
  a.px, a.py = a.fx + (tx - a.fx) * k, a.fy + (ty - a.fy) * k
  if a.st >= WALK_TICKS then a.px, a.py, a.fx, a.fy, a.i, a.st = tx, ty, tx, ty, a.i + 1, 0 sfx("STEP") end
end

local function strike_update()
  if t == 12 then play_events() end
  if t >= STRIKE_TICKS then
    local fallen = false
    for _, e in ipairs(anim.events) do if e.kind == "fall" then fallen = true end end
    if fallen then anim.fall = 0 to("fall") else finish_strike() end
  end
end

local function fall_update()
  anim.fall = anim.fall + 1
  if anim.fall >= FALL_TICKS then finish_strike() end
end

local function ai_update()
  if t < PAUSE then return end
  if check_over() then return end
  local st = game.state
  local id = table.remove(ai_queue, 1)
  while id and not R.unit(st, id) do id = table.remove(ai_queue, 1) end
  if not id then end_turn() return end
  local u = R.unit(st, id)
  local d = AI.decide(st, u)
  P.pending = d
  sel = id
  cur.x, cur.y = d.x, d.y
  if d.x == u.x and d.y == u.y then
    if d.target then start_strike(id, d.target) else game.state = R.finish(st, id) t = 0 end
  else
    walk_to(d.x, d.y)
  end
end

local function over_update()
  if t > 40 and (btnp("a") or btnp("start")) then scene.go(require("title"), nil, {fade = 0.4}) end
end

-- ------------------------------------------------------------------ scene
function P.enter(args)
  require("ppu").reset()
  palette("WORLD")
  palette("OBJ", true)
  units_sheet, cursor_sheet = sheet("UNITS"), sheet("CURSOR")
  bg(0)
  bg(3)
  bg(2, {map = "FIELD", prio = 3, wrap = false})
  bg(1, {map = "OVERLAY", prio = 2, wrap = false})
  blend(BG1, BG2, 7, 9)
  EMPTY = mget(1, 0, 0)
  BLUE, RED, ORANGE = mget(1, 2, 0), mget(1, 4, 0), mget(1, 6, 0)
  painted = {}
  for ty = 0, 19 do for tx = 0, 29 do mset(1, tx, ty, EMPTY) end end -- (the swatches the picture carries are not shown)
  backdrop(0)
  popups, anim, sel, danger_on = {}, nil, nil, false
  game = {state = args.state or R.new_game(DATA), auto_blue = args.auto, winner = nil, cur = cur}
  begin_side()
end

function P.update()
  t = t + 1
  for i = #popups, 1, -1 do
    popups[i].t = popups[i].t + 1
    if popups[i].t > 36 then table.remove(popups, i) end
  end
  if phase == "select" then select_update()
  elseif phase == "move" then move_update()
  elseif phase == "walk" then walk_update()
  elseif phase == "menu" then menu_update()
  elseif phase == "target" then target_update()
  elseif phase == "strike" then strike_update()
  elseif phase == "fall" then fall_update()
  elseif phase == "ai" then ai_update()
  elseif phase == "over" then over_update() end
end

-- ------------------------------------------------------------------ drawing
local function unit_pixel(u)
  if anim and anim.kind == "walk" and anim.id == u.id then return anim.px, anim.py end
  if anim and anim.kind == "strike" and anim.att == u.id and t > 4 and t < 20 then -- the lunge: toward what it hits and back
    local k = math.sin((t - 4) / 16 * math.pi) * 5
    local dx, dy = anim.dx - u.x, anim.dy - u.y
    local len = math.max(1, math.abs(dx) + math.abs(dy))
    return u.x * CELL + dx / len * k, u.y * CELL + dy / len * k
  end
  return u.x * CELL, u.y * CELL
end

local function draw_units()
  local st = game.state
  local tick = ticks()
  for i, u in ipairs(st.units) do
    local px, py = unit_pixel(u)
    local frame = ((u.team == "red" and 3 or 0) + u.kind) * 2 + ((tick // 28 + u.id) % 2)
    local flags = prio(0)
    if anim and anim.kind ~= "walk" and anim.def == u.id then
      local falling = anim.fall
      if anim.shown >= 1 and t >= 12 and t < 22 and not falling then flags = flags | MOSAIC end -- the hit's blocky flash
      if falling then flags = flags | MOSAIC end
    end
    spr(i - 1, units_sheet, frame, math.floor(px), math.floor(py), flags)
  end
  for i = #st.units, 11 do spr_off(i) end
  mosaic(1, 1, anim and anim.fall and 1 + math.floor(anim.fall / 3) or (phase == "strike" and t >= 12 and t < 22) and 3 or 1,
         anim and anim.fall and 1 + math.floor(anim.fall / 3) or (phase == "strike" and t >= 12 and t < 22) and 3 or 1)
end

local function draw_hp()
  for _, u in ipairs(game.state.units) do
    local px, py = unit_pixel(u)
    local max = R.KINDS[u.kind].hp
    local x, y = math.floor(px) * 2 + 2, math.floor(py) * 2 + 29
    rect(x, y, 28, 3, 0x101018)
    rect(x, y, math.floor(28 * u.hp / max), 3, u.team == "blue" and 0x70B0FF or 0xFF7070)
    if u.acted and u.team == game.state.side then rect(x + 22, y - 28, 6, 6, 0x303848) box(x + 22, y - 28, 6, 6, 0xB8C0D0) end -- (done this turn)
  end
end

local function draw_info()
  local st = game.state
  local u = R.unit_at(st, cur.x, cur.y)
  local ter = R.terrain_at(st, cur.x, cur.y)
  local top = cur.y >= 5
  local y = top and 6 or 260
  ui.box(6, y, 338, 54)
  text(string.format("%s  (%d,%d)  defensa +%d", ter.name, cur.x, cur.y, ter.def), 16, y + 8, {font = "main", color = ui.SUB})
  if u then
    local k = R.KINDS[u.kind]
    text(string.format("%s %s  PV %d/%d  Atq %d", u.team == "blue" and "Azul" or "Rojo", k.name, u.hp, k.hp, k.atk), 16, y + 26,
         {font = "main", color = u.team == "blue" and 0xB0D0FF or 0xFFB0B0})
  end
  ui.box(352, y, 122, 54)
  text(string.format("Turno %d", st.turn), 362, y + 8, {font = "main", color = ui.INK})
  text(st.side == "blue" and "azul" or "rojo", 362, y + 26,
       {font = "main", color = st.side == "blue" and 0xB0D0FF or 0xFFB0B0})
end

local function draw_menu()
  local u = R.unit(game.state, sel)
  local items = menu_items()
  local x, y = u.x * 32 + 36, math.max(4, u.y * 32 - 6)
  if x > 380 then x = u.x * 32 - 100 end
  ui.box(x, y, 110, 14 + 22 * #items)
  for i, name in ipairs(items) do text((i == menu_i and "> " or "  ") .. name, x + 8, y + 8 + (i - 1) * 22, {font = "bold", color = i == menu_i and ui.SEL or ui.INK}) end
end

function P.draw()
  draw_units()
  if phase ~= "over" and not (phase == "ai" or phase == "walk" and (game.state.side == "red" or game.auto_blue)) then
    spr(20, cursor_sheet, (ticks() // 20) % 2, cur.x * CELL, cur.y * CELL, prio(0))
  else
    spr_off(20)
  end
  draw_hp()
  for _, p in ipairs(popups) do text(p.text, p.x, p.y - p.t * 0.6, {font = "large_bold", align = "center", color = p.color}) end
  if phase == "menu" then draw_menu() end
  draw_info()
  if phase == "over" then
    ui.box(100, 110, 280, 100)
    text(game.winner == "blue" and "¡VICTORIA!" or "DERROTA", 240, 124, {font = "large_bold", align = "center", color = ui.SEL})
    text(string.format("en el turno %d", game.state.turn), 240, 164, {font = "main", align = "center", color = ui.INK})
    if t > 40 then text("A: volver al título", 240, 184, {font = "main", align = "center", color = ui.SUB}) end
  end
end

return P
