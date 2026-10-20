-- play: the island. The hero moves a cell at a time (iso.lua says where it may), and each move is shown over a few ticks: a step, a
-- jump in an arc, a drop off an edge, a crate pushed along (and sinking, to stay as a raft), a fall into the sea that puts it back.
-- The d-pad goes along the grid: up is up-right on the screen, right is down-right, down down-left, left up-left.
--   A jump (with a direction, onto a cell one block higher at most)   C put the crates back   START to the title
local scene = require("scene")
local iso = require("iso")
local V = require("view")
local ui = require("ui")

local P = {}
local DUR = {walk = 10, jump = 18, push = 16, splash = 14}
local SPLASH_TICKS = 24
local JUMP_ARC = 1.2 -- blocks above the straight line, at the top of a jump
local FACE = {right = {0, 0}, down = {0, FLIP_X}, up = {2, 0}, left = {2, FLIP_X}} -- the hero's frames from the front or back, mirrored

local mv, mv_t, splash_t, face, t, cam_x, cam_y, won, msg, msg_t

-- game: everything the tests read and set; game.input is where the keys come from (a test puts its own there), game.paused stops the
-- clock (the water, the gems), game.hidden leaves the hero and its shadow out (a picture to compare with one where it is hidden)
game = nil

local function keys()
  local dir = btn("up") and "up" or btn("right") and "right" or btn("down") and "down" or btn("left") and "left" or nil
  return {dir = dir, jump = btnp("a"), reset = btnp("c")}
end

function P.enter()
  game = {s = iso.new(require("level")), steps = 0, input = keys}
  mv, mv_t, splash_t, face, t, won, msg, msg_t = nil, 0, 0, "right", 0, false, nil, 0
  V.init(game.s)
  cam_x, cam_y = V.camera(P.hero_px())
end

-- where the hero is drawn: its cell (between two in a move), its height in blocks, and the frame
local function hero_pos()
  local s = game.s
  if not mv then return s.hx, s.hy, iso.surface(s, s.hx, s.hy), 0 end
  local f = math.min(1, mv_t / DUR[mv.kind])
  local x, y = s.hx + (mv.tx - s.hx) * f, s.hy + (mv.ty - s.hy) * f
  local z = mv.z0
  if mv.kind == "jump" then
    z = mv.z0 + (mv.z1 - mv.z0) * f + JUMP_ARC * 4 * f * (1 - f)
  elseif mv.kind == "splash" then
    x, y = s.hx + (mv.tx - s.hx) * math.min(1, f * 1.6), s.hy + (mv.ty - s.hy) * math.min(1, f * 1.6)
    z = mv.z0 - (mv.z0 + 1) * math.max(0, f - 0.4) / 0.6
  elseif f > 0.5 and mv.z1 < mv.z0 then -- off an edge: across, then down
    z = mv.z0 - (mv.z0 - mv.z1) * ((f - 0.5) / 0.5) ^ 2
  end
  return x, y, z, f
end

function P.hero_px()
  local x, y, z = hero_pos()
  local px, py = V.px(x, y)
  return px, py + 8 - 16 * z
end

local function start(dir, jump)
  face = dir or face
  local m = dir and iso.try(game.s, dir, jump)
  if m then
    mv, mv_t = m, 0
    sfx(m.kind == "jump" and "JUMP" or m.kind == "push" and "PUSH" or "STEP")
  elseif jump then -- a jump on the spot, or into what is too high: up and down where it stands
    local s = game.s
    local z = iso.surface(s, s.hx, s.hy)
    mv, mv_t = {kind = "jump", tx = s.hx, ty = s.hy, z0 = z, z1 = z}, 0
    sfx("JUMP")
  end
end

local function finish()
  local m = mv
  mv = nil
  if m.kind == "splash" then
    splash_t = SPLASH_TICKS
    game.splash = {m.tx, m.ty}
    sfx("SPLASH")
    return
  end
  if m.tx ~= game.s.hx or m.ty ~= game.s.hy then game.steps = game.steps + 1 end
  if m.sinks then sfx("SPLASH") end
  if iso.apply(game.s, m) then
    sfx("GEM")
    msg, msg_t = game.s.gems_left > 0 and ("¡Una gema! Quedan " .. game.s.gems_left) or "¡Las cinco!", 90
    if game.s.gems_left == 0 then
      won = true
      local best = stored("best")
      if not best or game.steps < best then store("best", game.steps) end
      sfx("WIN")
    end
  end
end

function P.busy() return mv ~= nil or splash_t > 0 end

function P.update()
  if game.paused then return end
  t = t + 1
  if msg_t > 0 then msg_t = msg_t - 1 end
  local k = game.input()
  if btnp("start") then scene.go(require("title"), nil, {fade = 0.4}) return end
  if won then
    if btnp("a") then scene.go(require("title"), nil, {fade = 0.4}) end
  elseif splash_t > 0 then
    splash_t = splash_t - 1
    if splash_t == 0 then game.splash = nil end
  elseif mv then
    mv_t = mv_t + 1
    if mv_t >= DUR[mv.kind] then finish() end
  elseif k.reset then
    iso.reset(game.s)
    msg, msg_t = "Las cajas, como estaban", 60
  elseif k.jump or k.dir then
    start(k.dir, k.jump)
  end
  local tx, ty = V.camera(P.hero_px())
  cam_x, cam_y = cam_x + (tx - cam_x) * 0.15, cam_y + (ty - cam_y) * 0.15
end

-- what moves, as V.thing for the view: the crates (one may be on its way), the rafts, the gems, the hero, its shadow, a splash
local function moving()
  local s, out = game.s, {}
  local L = V.LAYER
  local pushed = mv and mv.kind == "push" and iso.key(mv.tx, mv.ty)
  local f = mv and math.min(1, mv_t / DUR[mv.kind]) or 0
  for k in pairs(s.crates) do
    local x, y = k % 100, k // 100
    local z = iso.ground(s, x, y)
    if k == pushed then
      local cz = mv.cz0
      if f > 0.5 and mv.cz1 < mv.cz0 then cz = mv.cz0 - (mv.cz0 - mv.cz1) * ((f - 0.5) / 0.5) ^ 2 end
      x, y, z = x + (mv.cx - x) * f, y + (mv.cy - y) * f, cz
    end
    local px, py = V.px(x, y)
    out[#out + 1] = V.thing(math.floor(x + 0.5), math.floor(y + 0.5), L.block, "CRATE", 0, px - 16, py - 16 * z, 0, "crate")
  end
  for k in pairs(s.filled) do
    local x, y = k % 100, k // 100
    local px, py = V.px(x, y)
    out[#out + 1] = V.thing(x, y, L.raft, "RAFT", 0, px - 16, py + 2, 0, "raft")
  end
  for k in pairs(s.gems) do
    local x, y = k % 100, k // 100
    local px, py = V.px(x, y)
    local bob = math.sin(t / 12 + x) * 2
    out[#out + 1] = V.thing(x, y, L.top, "GEM", (t // 8) % 4, px - 8, py - 16 * iso.surface(s, x, y) - 10 + bob, 0, "gem")
  end
  if splash_t > 0 then
    local px, py = V.px(game.splash[1], game.splash[2])
    out[#out + 1] = V.thing(game.splash[1], game.splash[2], L.top, "SPLASH", math.min(2, (SPLASH_TICKS - splash_t) // 6), px - 8, py, 0, "splash")
  elseif not game.hidden then
    local x, y, z = hero_pos()
    local cx, cy = math.floor(x + 0.5), math.floor(y + 0.5)
    local px, py = V.px(x, y)
    local fr = FACE[face]
    local step = mv and (mv.kind == "walk" or mv.kind == "push") and (t // 5) % 2 or 0
    local ground = iso.surface(s, cx, cy)
    if ground >= 0 and z >= ground then
      out[#out + 1] = V.thing(cx, cy, L.shadow, "SHADOW", 0, px - 8, py + 4 - 16 * ground, 0, "shadow")
    end
    out[#out + 1] = V.thing(cx, cy, L.top, "HERO", fr[1] + step, px - 8, py + 8 - 16 * z - 22, fr[2], "hero")
  end
  return out
end

function P.draw()
  V.water(t)
  V.draw(moving(), cam_x, cam_y)
  local s = game.s
  local got = #s.level.gems - s.gems_left
  text("Gemas " .. got .. "/" .. #s.level.gems, 12, 10, {font = "bold", color = ui.SEL, shadow = 0x000000})
  text("Pasos " .. game.steps, 468, 10, {font = "bold", color = ui.INK, align = "right", shadow = 0x000000})
  if msg_t > 0 and msg then text(msg, 240, 40, {font = "bold", align = "center", color = ui.INK, shadow = 0x000000}) end
  if t < 240 and not won then
    text("A saltar   C las cajas otra vez   START salir", 240, 300, {font = "main", align = "center", color = ui.INK, shadow = 0x000000})
  end
  if won then
    ui.box(110, 110, 260, 100)
    text("¡La isla es tuya!", 240, 126, {font = "large_bold", align = "center", color = ui.SEL})
    text(game.steps .. " pasos   (el mejor: " .. (stored("best") or game.steps) .. ")", 240, 162, {font = "main", align = "center", color = ui.INK})
    text("A para volver", 240, 186, {font = "main", align = "center", color = ui.SUB})
  end
end

return P
