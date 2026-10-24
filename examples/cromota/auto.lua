-- An autopilot that plays real levels through juego.lua (no drawing): it proves a level can be won and gives the tests
-- something to play with. It prefers the swap that makes a wanted colour; it mixes and paints whenever it can.
local R = require("reglas")
local J = require("juego")
local A = {}

-- one decision: paint, load, mix, or swap. Returns what it did ("pinta", "carga", "mezcla", "cambia") or nil when stuck.
function A.paso(s, habil)
  habil = habil or 1
  if s.fin then return nil end
  if s.brush then
    J.pintar(s, s.obj[s.brush.obj].region)
    return "pinta"
  end
  for i, o in ipairs(s.obj) do
    if not o.hecho and J.cargar(s, i) then return "carga" end
  end
  for i, k in ipairs(s.recetas) do
    local pendiente = false
    for _, o in ipairs(s.obj) do if not o.hecho and o.color == k and (s.stock[k] or 0) < o.unidades then pendiente = true end end
    if pendiente and J.puede_mezclar(s, i) and J.mezclar(s, i) then return "mezcla" end
  end
  if s.mov <= 0 then return nil end
  local mejor = J.sugerencia(s)
  if mejor and math.random() > habil then -- a less careful player: any move that works
    local todas = R.jugadas(s.b)
    mejor = todas[math.random(#todas)]
  end
  if not mejor then return nil end
  J.cambiar(s, mejor[1], mejor[2], mejor[3], mejor[4])
  return "cambia"
end

-- play a level to its end. Returns the state.
function A.jugar(nivel, habil)
  local s = J.nuevo(nivel)
  for _ = 1, 400 do
    if not A.paso(s, habil) then break end
  end
  return s
end

return A
