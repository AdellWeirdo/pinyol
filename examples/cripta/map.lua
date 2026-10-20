-- map: the castle as far as it has been walked, over the game (START opens it, START or B closes it). Each room a box of its size on the grid of
-- screens; the one you are in blinks; a dot where something is still to be found in a room you have seen.
local scene = require("scene")
local W = require("world")
local ui = require("ui")

local M = {overlay = true}
local CW, CH = 40, 28 -- a screen of the castle on the map

function M.enter() M.t = 0 end

function M.update()
  M.t = M.t + 1
  if M.t > 2 and (btnp("start") or btnp("b")) then scene.pop() end
end

function M.draw()
  shade(0, 0, SCREEN_W, SCREEN_H)
  shade(0, 0, SCREEN_W, SCREEN_H)
  ui.box(36, 30, 408, 260)
  text("EL CASTILLO", 240, 40, {font = "bold", align = "center", color = ui.SEL})
  local ox, oy = 240 - 9 * CW // 2, 80
  for _, id in ipairs(W.order) do
    local r = W.rooms[id]
    if game.visited[id] then
      local x, y, w, h = ox + r.mx * CW, oy + r.my * CH, r.w // W.SW * CW, r.h // W.SH * CH
      local here = game.room == id
      rect(x + 2, y + 2, w - 4, h - 4, here and (M.t // 15) % 2 == 0 and 0xC04050 or 0x40507A)
      box(x + 2, y + 2, w - 4, h - 4, 0xE8D8B0)
      for _, th in ipairs(r.things) do
        local k = id .. ":" .. th.tx .. ":" .. th.ty
        if (th.kind == "wings" or th.kind == "gust" or th.kind == "heart") and not game.taken[k] then
          circ(x + 2 + th.tx * (w - 4) // r.w, y + 2 + th.ty * (h - 4) // r.h, 3, 0xFFE070)
        elseif th.kind == "statue" then
          rect(x + th.tx * (w - 4) // r.w, y + th.ty * (h - 4) // r.h, 5, 5, 0x90E8FF)
        end
      end
    end
  end
  local seen = 0
  for id in pairs(game.visited) do seen = seen + 1 end
  text(string.format("salas: %d de %d   corazones: %d   muertes: %d", seen, #W.order, game.max_hearts, game.deaths), 240, 236,
       {font = "main", align = "center", color = ui.INK})
  text("START: volver", 240, 262, {font = "main", align = "center", color = ui.DIM})
end

return M
