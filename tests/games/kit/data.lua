-- What the editor writes: pictures (their sizes; the files are SPR_<name>), kinds, the map, objects, sounds.
local W, H = 30, 10
local cells = {}
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local t = 0
    if y == H - 1 then t = 1 end                     -- the floor
    if y == H - 2 and x == 18 then t = 2 end         -- spikes
    if y == H - 2 and (x == 12 or x == 13) then t = 1 end -- a step on the floor
    cells[#cells + 1] = t
  end
end
return {
  title = "Kit", tile = 16, background = 0x6CB4E0, camera = "heroe",
  sprites = {heroe = {w = 12, h = 16, frames = 1}, suelo = {w = 16, h = 16, frames = 1}, moneda = {w = 8, h = 8, frames = 1},
             malo = {w = 14, h = 12, frames = 1}, pincho = {w = 16, h = 16, frames = 1}},
  kinds = {heroe = {behaviour = "platformer", speed = 1.6, jump = 4.6, animate = 8},
           moneda = {behaviour = "still", gravity = false}, malo = {behaviour = "patrol", speed = 0.6}},
  solid = {suelo = true},
  map = {w = W, h = H, tiles = {"suelo", "pincho"}, cells = cells},
  objects = {{kind = "heroe", x = 20, y = 100}, {kind = "moneda", x = 120, y = 130}, {kind = "malo", x = 360, y = 120}},
  sounds = {moneda = {wave = "square", freq = 900, arp = 1.5, arp_time = 0.05, sustain = 0.05, decay = 0.2}},
}
