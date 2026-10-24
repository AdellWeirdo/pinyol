-- CROMOTA tutorial: every new element is explained once, the moment it first shows up (a spotlight on it and a bubble).
-- What was explained is kept in G.visto (saved). A step: {id, titulo, texto, caja = {x, y, w, h}, receta = index?}.
local R = require("reglas")
local U = require("util")
local lang = require("lang")

local Gd = {}
local C, CELDA = U.C, U.CELDA

local function caja_celda(r, c)
  return {C.celdas[1] + (c - 1) * CELDA, C.celdas[2] + (r - 1) * CELDA, CELDA, CELDA}
end

local function buscar(P, clave)
  for r = 1, #P.V do
    for c = 1, #P.V[r] do
      if P.V[r][c] == clave then return r, c end
    end
  end
end

local function ingredientes(k)
  local partes = {}
  for _, ing in ipairs(U.ordenados(R.RECETAS[k])) do
    partes[#partes + 1] = R.RECETAS[k][ing] .. " " .. U.NOMBRE[ing]
  end
  return table.concat(partes, " + ")
end

-- the steps for this level that were not explained yet (all of them when `todo`), in the order they are best learned
function Gd.pasos(P, todo)
  local visto, s, lista = G.visto, P.s, {}
  local nivel = s.nivel
  local function nuevo(id, paso)
    if todo or not visto[id] then
      paso.id = id
      lista[#lista + 1] = paso
    end
  end
  nuevo("mov", {titulo = lang.tr("tour_moves_t"), caja = C.mov, texto = lang.tr("tour_moves")})
  nuevo("objetivos", {titulo = lang.tr("tour_goals_t"), caja = C.obj_marco, texto = lang.tr("tour_goals")})
  nuevo("reserva", {titulo = lang.tr("tour_stock_t"), caja = C.reserva, texto = lang.tr("tour_stock")})
  nuevo("cuadro", {titulo = lang.tr("tour_painting_t"), caja = C.rest_marco, texto = lang.tr("tour_painting")})
  for _, k in ipairs({"blanco", "negro"}) do
    for _, p in ipairs(nivel.paleta) do
      if p == k then
        local r, c = buscar(P, k)
        if r then
          nuevo("color_" .. k, {titulo = lang.tr("tour_new", {c = U.NOMBRE[k]}), caja = caja_celda(r, c),
                                texto = lang.tr(k == "blanco" and "tour_white" or "tour_black")})
        end
      end
    end
  end
  if nivel.bloqueos then
    local r, c = buscar(P, R.ESPONJA)
    if r then
      nuevo("esponja", {titulo = lang.tr("tour_sponge_t"), caja = caja_celda(r, c), texto = lang.tr("tour_sponge")})
    end
  end
  if #nivel.recetas > 0 then
    nuevo("mezcla", {titulo = lang.tr("tour_mix_t"), caja = C.mezcla, texto = lang.tr("tour_mix")})
  end
  for i, k in ipairs(nivel.recetas) do
    nuevo("receta_" .. k, {titulo = lang.tr("tour_newcolor", {c = U.NOMBRE[k]}), caja = C.mezcla, receta = i,
                           texto = lang.tr("tour_recipe", {c = U.NOMBRE[k], ing = ingredientes(k)})})
  end
  if #nivel.recetas > 1 then
    nuevo("recetas_varias", {titulo = lang.tr("tour_recipes_t"), receta = 1,
                             caja = {C.ing_a[1], C.ing_a[2], C.ing_b[1] + C.ing_b[3] - C.ing_a[1], C.ing_a[4]},
                             texto = lang.tr("tour_recipes")})
  end
  return lista
end

function Gd.combo()
  if G.visto.combo then return {} end
  return {{id = "combo", titulo = lang.tr("tour_combo_t"), caja = C.combo, texto = lang.tr("tour_combo")}}
end

-- the first time a brush shows up on the board
function Gd.pincel(P)
  if G.visto.pincel then return {} end
  local r, c = buscar(P, R.PINCEL)
  if not r then return {} end
  return {{id = "pincel", titulo = lang.tr("tour_brush_t"), caja = caja_celda(r, c), texto = lang.tr("tour_brush")}}
end

function Gd.tubo(P)
  if G.visto.tubo then return {} end
  local r, c = buscar(P, R.TUBO)
  if not r then return {} end
  return {{id = "tubo", titulo = lang.tr("tour_tube_t"), caja = caja_celda(r, c), texto = lang.tr("tour_tube")}}
end

-- called when a step becomes the current one
function Gd.entrar(P, paso)
  if paso and paso.receta then P.s.receta = paso.receta end
end

return Gd
