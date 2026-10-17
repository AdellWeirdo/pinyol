-- the adventure libraries (lib/inventory.lua, lib/hud.lua, lib/rooms.lua) played through tests/adv.script: two rooms and a
-- street, a wall, a door, a key to take, a variant of the look when miseria is high, the memory of what was done in them
rooms = require("rooms") -- (globals: tests/adv.script)
inventory = require("inventory")
hud = require("hud")

mis = 0
inv = inventory.new({
  slots = 3,
  items = {llave = {name = "Llave", icon = "ICO"}, birra = {name = "Birra", icon = "ICO"}, pizza = {name = "Pizza", icon = "ICO"},
           moneda = {name = "Moneda", icon = "ICO", stack = true}},
  uses = {llave = {botellero = function() opened = true return true end}, birra = {}},
})
meter = hud.meter({x = 20, y = 24, w = 120, h = 12, label = "MISERIA", segments = 10, danger = 0.7, danger_color = 0xE03030})
player = {x = 0, y = 0, w = 16, h = 40}
log = {}

local function pic(id, w, h, colour)
  canvas(id, w, h) target(id) cls(colour) box(0, 0, w, h, 0xFFFFFF) target()
end

function _init()
  show(0)
  pic("ICO", 20, 20, 0xC0A030)
  pic("BG_A", 480, 320, 0x203040) pic("BG_A_RED", 480, 320, 0x501820) pic("BG_B", 480, 320, 0x304020)
  pic("COUNTER", 120, 50, 0x603010) pic("STOOL", 20, 30, 0x909090) pic("NPC", 24, 60, 0x8060A0) pic("KEY", 12, 12, 0xF0D040) pic("PILLAR", 40, 320, 0x101010)
  rooms.define({
    id = "a", w = 480, h = 320,
    layers = {{pic = "BG_A"}}, front = {{pic = "PILLAR", x = 300}},
    solids = {{x = 0, y = 280, w = 480, h = 40}, {x = 200, y = 200, w = 30, h = 80}},
    spawns = {default = {x = 40, y = 240}, from_b = {x = 400, y = 240}},
    exits = {{x = 468, y = 180, w = 12, h = 100, to = "b", spawn = "from_a"}},
    things = {{id = "npc", x = 100, y = 220, w = 24, h = 60, pic = "NPC", talk = "npc"},
              {id = "key", x = 150, y = 268, w = 12, h = 12, pic = "KEY", take = "llave"},
              {id = "ghost", x = 60, y = 100, w = 10, h = 10, pic = "KEY", when = function() return mis > 50 end}},
    occluders = {{pic = "COUNTER", x = 250, y = 230, z = 280}, {pic = "STOOL", x = 380, y = 250, z = 262}},
    variant = function() return mis > 70 and "crisis" or nil end,
    variants = {crisis = {layers = {{pic = "BG_A_RED"}}}},
    assets = {images = {"BG_A", "NOPE"}, sounds = {}},
    enter = function(room, spawn) log[#log + 1] = "enter a " .. tostring(spawn) .. " " .. tostring(room.look) end,
    leave = function() log[#log + 1] = "leave a" end,
  })
  rooms.define({
    id = "b", w = 960, h = 320, layers = {{pic = "BG_B", parallax = 0.5}},
    spawns = {default = {x = 40, y = 240}, from_a = {x = 20, y = 240}},
    solids = {{x = 0, y = 280, w = 960, h = 40}},
    exits = {{x = 0, y = 180, w = 8, h = 100, to = "a", spawn = "from_b"}},
    things = {},
    enter = function() log[#log + 1] = "enter b" end,
  })
  rooms.player = player
  rooms.go("a")
end

function _update()
  rooms.update()
  hud.update() meter:update()
end

function _draw()
  rooms.draw(function() rect(player.x, player.y, player.w, player.h, 0xE04040) end, player.y + player.h)
  meter:draw()
  hud.hearts(20, 44, 2, 3)
  hud.counter(20, 64, "ICO", 37)
  inv:draw(20, 90, {size = 28})
  hud.objective(250, 20, nil, "OBJETIVO", {"Cierra la valvula", "Llega al nucleo"}, {done = {true, false}})
  hud.draw_toasts(20, 150)
end
