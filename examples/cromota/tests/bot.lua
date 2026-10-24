-- A player for the playthrough script: decides like a person (paint, load the brush, mix, swap) and acts only through
-- G.toca, the same path a finger takes. Returns what it did.
local L = require("layout")
local J = require("juego")
local R = require("reglas")

local function cc(c) return 70 + (c - 1) * 28 + 14 end
local function cr(r) return 10 + (r - 1) * 28 + 14 end

local function aqui(k)
  for gy, fila in ipairs(L.obras[G.obra.id].rejilla) do
    for gx = 1, #fila do
      if tonumber(fila:sub(gx, gx)) == k then return 313 + (gx - 1) * 4 + 2, 145 + (gy - 1) * 4 + 2 end
    end
  end
end

return function()
  local P = G.P
  if G.estado ~= "juego" or not P or P.tour or P.busy then return "espera" end
  local s = P.s
  if s.fin then return "fin" end
  local habil = G.habilidad or 1 -- 1: perfect; lower: sometimes a poor move, a wrong tap
  if s.brush then
    local region = s.obj[s.brush.obj].region
    if math.random() > habil + 0.3 then region = region % 6 + 1 end -- taps the wrong zone
    local x, y = aqui(region)
    G.toca(x, y)
    return "pinta"
  end
  for i, o in ipairs(s.obj) do
    if not o.hecho and (s.stock[o.color] or 0) >= o.unidades then
      local sl = L.slots_obj[i]
      G.toca(sl[1] + 10, sl[2] + 10)
      return "carga"
    end
  end
  for i, k in ipairs(s.recetas) do
    for _, o in ipairs(s.obj) do
      if not o.hecho and o.color == k and (s.stock[k] or 0) < o.unidades and J.puede_mezclar(s, i) then
        s.receta = i
        G.toca(L.caja.res[1] + 10, L.caja.res[2] + 10)
        return "mezcla"
      end
    end
  end
  local j = J.sugerencia(s)
  if j and math.random() > habil then
    local todas = R.jugadas(s.b)
    j = todas[math.random(#todas)]
  end
  if math.random() > habil + 0.35 then -- a swap that makes nothing
    local r, c = math.random(7), math.random(7)
    G.toca(cc(c), cr(r))
    G.toca(cc(c + 1), cr(r))
    return "tonteria"
  end
  if j then
    G.toca(cc(j[2]), cr(j[1]))
    G.toca(cc(j[4]), cr(j[3]))
    return "cambia"
  end
  return "nada"
end
