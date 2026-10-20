-- play: a run shown. The floor is written into BG1 cell by cell (mset, four map entries a cell) when the hero comes down to it, and the
-- fog into BG0, over the sprites: dark where the hero has not been, a checker of dark over what it has seen, clear where it sees now.
-- After each turn only the fog's cells that changed are written again. The hero and the monsters slide from cell to cell; a new turn is
-- taken when they have arrived. The d-pad steps (into a monster, a blow), A rests a turn, B drinks a potion, START gives up.
local scene = require("scene")
local D = require("dungeon")
local R = require("run")
local I = require("index")
local ui = require("ui")

local P = {}
local SLIDE = 4 -- pixels a tick: a cell in four
local BLOW_TICKS, HURT_TICKS, CARD_TICKS = 10, 12, 40
local MAP_W, MAP_H = D.W * 16, D.H * 16

local sheets, fog, t, cam_x, cam_y, blow, hurt, ended, monsters_due, card
-- game: what the tests read and set: game.r is the run; game.input where the commands come from (a test puts its own there)
game = nil

local function keys()
  for _, d in ipairs({"up", "down", "left", "right"}) do if btn(d) then return {dir = d} end end
  if btnp("a") then return {rest = true} end
  if btnp("b") then return {potion = true} end
  return nil
end

local function put(layer, x, y, e)
  mset(layer, 2 * x, 2 * y, e[1]) mset(layer, 2 * x + 1, 2 * y, e[2])
  mset(layer, 2 * x, 2 * y + 1, e[3]) mset(layer, 2 * x + 1, 2 * y + 1, e[4])
end

-- what the fog of a cell should be now: 0 clear, 1 seen before, 2 dark
local function fog_of(r, k) return r.visible[k] and 0 or r.seen[k] and 1 or 2 end
local FOG = {[0] = I.fog.clear, I.fog.seen, I.fog.dark}

-- A floor shown: the two maps loaded again (all rock, all dark: copied by the engine at once), then only what is not plain rock written
-- into BG1, the open cells and the faces of the walls over them, and into BG0 the cells the hero sees. Writing every cell of both, on the
-- console, held the tick 166 ms.
local function write_floor()
  local r = game.r
  local d = r.d
  bg(1, {map = "DUNGEON", prio = 2, wrap = false})
  bg(0, {map = "FOG", prio = 0, wrap = false, pal = false})
  local cells, W, WALL, C = d.cells, D.W, D.WALL, I.cells
  for y = 0, D.H - 1 do
    for x = 0, W - 1 do
      local c, e = cells[y * W + x + 1], nil
      if c ~= WALL then e = c == D.STAIRS and C.stairs or (x * 7 + y * 13) % 11 == 0 and C.crack or C.floor
      elseif y + 1 < D.H and cells[(y + 1) * W + x + 1] ~= WALL then e = C.face end -- a wall over a floor shows its face
      if e then
        local tx, ty = 2 * x, 2 * y
        mset(1, tx, ty, e[1]) mset(1, tx + 1, ty, e[2]) mset(1, tx, ty + 1, e[3]) mset(1, tx + 1, ty + 1, e[4])
      end
    end
  end
  fog = {} -- (nothing in it: dark)
  for k in pairs(r.visible) do
    fog[k] = fog_of(r, k)
    put(0, (k - 1) % D.W, (k - 1) // D.W, FOG[fog[k]])
  end
  game.floor_shown = r.floor
end

-- the fog's cells that changed in the turn: those seen now and not before (clear), and those seen before and not now (a checker)
function P.update_fog()
  local r = game.r
  local n = 0
  local function set(k, f)
    if fog[k] ~= f then fog[k] = f put(0, (k - 1) % D.W, (k - 1) // D.W, FOG[f]) n = n + 1 end
  end
  for k in pairs(r.visible) do if not r.was_visible[k] then set(k, 0) end end
  for k in pairs(r.was_visible) do if not r.visible[k] then set(k, 1) end end
  game.fog_writes = n
end

local function snap(e) e.px, e.py = e.x * 16, e.y * 16 end

-- where the camera goes: the hero in the middle, the floor's edges never past the screen's
local function camera_target()
  local h = game.r.hero
  return math.max(0, math.min(MAP_W - 240, h.px + 8 - 120)), math.max(0, math.min(MAP_H - 160, h.py + 8 - 84))
end

local function slide(e)
  local tx, ty = e.x * 16, e.y * 16
  if not e.px then snap(e) end
  e.px = e.px + math.max(-SLIDE, math.min(SLIDE, tx - e.px))
  e.py = e.py + math.max(-SLIDE, math.min(SLIDE, ty - e.py))
  return e.px == tx and e.py == ty
end

function P.enter(args)
  local r = R.new(args and args.seed or 1)
  game = {r = r, input = keys, daily = args and args.daily}
  if game.daily then R.say(r, "La sima del día: hoy, la misma para todos") end
  sheets = {}
  for _, n in ipairs({"HERO", "RATA", "MURCIELAGO", "ESQUELETO", "POCION", "ORO", "AMULETO", "GOLPE"}) do sheets[n] = sheet(n) end
  palette("WORLD")
  palette("OBJ", true)
  bg(2) bg(3)
  backdrop(0x08060C)
  t, blow, hurt, ended, monsters_due, card = 0, nil, 0, false, false, nil
  write_floor()
  snap(r.hero)
  cam_x, cam_y = camera_target()
end

function P.busy()
  local r = game.r
  if monsters_due or card then return true end
  if r.hero.px ~= r.hero.x * 16 or r.hero.py ~= r.hero.y * 16 then return true end
  for _, m in ipairs(r.monsters) do if m.px and (m.px ~= m.x * 16 or m.py ~= m.y * 16) then return true end end
  return false
end

local function finish_run()
  local r = game.r
  ended = true
  local best = stored("best") or 0
  if r.floor > best then store("best", r.floor) end
  if r.won then store("wins", (stored("wins") or 0) + 1) end
end

function P.update()
  t = t + 1
  local r = game.r
  if hurt > 0 then hurt = hurt - 1 end
  if blow then blow.t = blow.t - 1 if blow.t <= 0 then blow = nil end end
  if btnp("start") then scene.go(require("title"), nil, {fade = 0.4}) return end
  local still = slide(r.hero)
  for _, m in ipairs(r.monsters) do still = slide(m) and still end
  if card then -- "Piso 2 de 5" on black, as the Mystery Dungeons put between floors: the floor is made under it (on the console,
    -- with the maps written, some 50 ms: a tick that long is not seen while the card stays)
    if card.due then
      card.due = false
      R.descend(r)
      write_floor()
      snap(r.hero)
      cam_x, cam_y = camera_target()
    end
    card.t = card.t - 1
    if card.t <= 0 then card = nil end
  elseif ended then
    if btnp("a") then scene.go(require("title"), nil, {fade = 0.4}) end
  elseif monsters_due then -- the turn's second half, a tick after the hero's
    monsters_due = false
    R.monsters_act(r)
    if r.hurt then hurt = HURT_TICKS sfx("HURT") end
    if r.dead then sfx("DEATH") finish_run() end
  elseif still then
    local cmd = game.input()
    if cmd then
      local tx, ty = cmd.dir and r.hero.x + R.DIRS[cmd.dir][1], cmd.dir and r.hero.y + R.DIRS[cmd.dir][2]
      local what = R.hero_acts(r, cmd)
      if what == "hit" then blow = {x = tx, y = ty, t = BLOW_TICKS} sfx("HIT")
      elseif what == "move" then sfx("STEP")
      elseif what == "potion" then sfx("DRINK") end
      if what == "stairs" then -- the floor's card first; the next floor is made behind it, a tick later
        sfx("DOWN")
        card = {t = CARD_TICKS, due = true}
      elseif what then
        P.update_fog()
        monsters_due = what ~= "won"
      end
      if r.won then sfx("WIN") finish_run() end
    end
  end
  local tx, ty = camera_target()
  cam_x, cam_y = cam_x + (tx - cam_x) * 0.25, cam_y + (ty - cam_y) * 0.25
end

function P.draw()
  local r = game.r
  local cx, cy = math.floor(cam_x), math.floor(cam_y)
  scroll(1, cx, cy)
  scroll(0, cx, cy)
  spr_clear()
  local n = 0
  local function show(sh, frame, px, py, flags)
    local x, y = math.floor(px) - cx, math.floor(py) - cy
    if x > -16 and x < 240 and y > -16 and y < 160 then spr(n, sheets[sh], frame, x, y, prio(1) | (flags or 0)) n = n + 1 end
  end
  if blow then show("GOLPE", blow.t > BLOW_TICKS // 2 and 0 or 1, blow.x * 16, blow.y * 16) end
  if hurt == 0 or (hurt // 2) % 2 == 0 then show("HERO", (t // 30) % 2, r.hero.px, r.hero.py) end
  for _, m in ipairs(r.monsters) do
    if r.visible[D.key(m.x, m.y)] then
      if not m.px then snap(m) end
      show(m.kind:upper(), (t // 15) % 2, m.px, m.py, m.px > r.hero.px and FLIP_X or 0)
    else
      snap(m) -- out of sight it is where it is: it does not slide in from where it was last seen
    end
  end
  for _, it in ipairs(r.items) do
    if r.seen[D.key(it.x, it.y)] then show(it.kind == "pocion" and "POCION" or "ORO", 0, it.x * 16, it.y * 16) end
  end
  if r.floor == D.FLOORS and not r.won and r.seen[D.key(r.d.exit[1], r.d.exit[2])] then
    show("AMULETO", 0, r.d.exit[1] * 16, r.d.exit[2] * 16 - math.floor(math.sin(t / 10) * 2))
  end
  -- the hero's state at the top, the last things that happened at the foot
  local h = r.hero
  shade(0, 0, 480, 28)
  text("Piso " .. r.floor .. "/" .. D.FLOORS, 10, 6, {font = "bold", color = ui.SEL})
  rect(104, 9, 80, 10, 0x401018)
  rect(104, 9, 80 * h.hp // h.max, 10, h.hp * 3 <= h.max and 0xE04040 or 0x40C060)
  text(h.hp .. "/" .. h.max, 190, 6, {font = "bold", color = ui.INK})
  text("Pociones " .. h.potions .. "   Oro " .. h.gold, 470, 6, {font = "main", color = ui.INK, align = "right"})
  shade(0, 256, 480, 64)
  for i, line in ipairs(r.log) do
    text(line, 12, 258 + (i - 1) * 20, {font = "main", color = i == #r.log and ui.INK or ui.DIM})
  end
  if card then
    rect(0, 0, 480, 320, 0x08060C)
    text("Piso " .. (card.due and r.floor + 1 or r.floor) .. " de " .. D.FLOORS, 240, 140, {font = "large_bold", align = "center", color = ui.SEL})
  end
  if ended then
    ui.box(90, 90, 300, 120)
    text(r.won and "¡Has salido con el amuleto!" or "Fin de la bajada", 240, 104, {font = "large_bold", align = "center", color = ui.SEL})
    text("Piso " .. r.floor .. "   " .. r.kills .. " vencidos   " .. h.gold .. " de oro", 240, 144, {font = "main", align = "center", color = ui.INK})
    text("A para volver", 240, 178, {font = "main", align = "center", color = ui.SUB})
  end
end

return P
