-- CROMOTA level logic: one level's state and the four things a player does (swap, mix, load the brush, paint).
-- Pure like reglas.lua: the UI replays the `pasos` a swap returns, the bots in the tests call these same functions.
local R = require("reglas")
local J = {}

J.BONO_COMBO = 3 -- a chain this long (or more) also gives moves: combo - 1, at most 3
local COMBO_MAX_MOVS = 2

function J.nuevo(nivel)
  local s = {
    nivel = nivel, b = R.nuevo(nivel), mov = nivel.movimientos, stock = {}, cap = nivel.cap or 12, brush = nil,
    obj = {}, recetas = nivel.recetas, receta = 1, puntos = 0, combo_max = 0, fin = nil, usados = 0,
  }
  s.recetas_ok = {}
  for _, k in ipairs(nivel.recetas) do s.recetas_ok[k] = true end
  for i, o in ipairs(nivel.objetivos) do s.obj[i] = {color = o.color, region = o.region, unidades = o.unidades, hecho = false} end
  return s
end

local function necesidades(s)
  local need = {}
  for _, o in ipairs(s.obj) do
    if not o.hecho and not (s.brush and s.obj[s.brush.obj] == o) then need[o.color] = (need[o.color] or 0) + o.unidades end
  end
  return need
end

-- the level is lost when no moves are left and what is in stock cannot pay for what is still to paint
function J.revisar(s)
  if s.fin then return s.fin end
  local pendiente = false
  for _, o in ipairs(s.obj) do if not o.hecho then pendiente = true end end
  if not pendiente then s.fin = "gana"
  elseif s.mov <= 0 and not R.alcanzable(s.stock, s.recetas_ok, necesidades(s)) then s.fin = "pierde" end
  return s.fin
end

-- a swap. Returns ok, info: info.pasos (what burst and fell), info.razon when refused:
-- "fin" "sin_movs" "vecinas" "sin_grupo".
function J.cambiar(s, r1, c1, r2, c2)
  if s.fin then return false, {razon = "fin"} end
  if s.mov <= 0 then return false, {razon = "sin_movs"} end
  if not R.vecinas(s.b, r1, c1, r2, c2) then return false, {razon = "vecinas"} end
  local b = s.b
  local pa, pb = b.g[r1][c1], b.g[r2][c2]
  local pincel_a, pincel_b = pa == R.PINCEL, pb == R.PINCEL
  local tubo_a, tubo_b = pa == R.TUBO, pb == R.TUBO
  if not R.intercambiar(b, r1, c1, r2, c2) then return false, {razon = "sin_grupo"} end
  s.mov, s.usados = s.mov - 1, s.usados + 1
  local pasos = {}
  if pincel_a or pincel_b then -- the brush lands where the other drop was: it clears that row (horizontal swap) or column
    local rd, cd = r1, c1
    if pincel_a then rd, cd = r2, c2 end
    pasos[1] = R.pincelazo(b, rd, cd, r1 == r2)
    s.pinceles = (s.pinceles or 0) + 1
  elseif tubo_a or tubo_b then -- the tube clears every drop of the colour it was swapped with
    local rt, ct, color = r1, c1, pa
    if tubo_a then rt, ct, color = r2, c2, pb end
    pasos[1] = R.tubazo(b, rt, ct, color)
    s.tubos = (s.tubos or 0) + 1
  end
  local crea
  if s.nivel.especiales and #pasos == 0 then
    local permite = {}
    for _, e in ipairs(s.nivel.especiales) do permite[e] = true end
    crea = {r1, c1, r2, c2, permite = permite}
  end
  for _, p in ipairs(R.resolver(b, crea)) do pasos[#pasos + 1] = p end
  local info = {pasos = pasos, combo = #pasos, ganado = {}, mov_extra = 0, pincel = pincel_a or pincel_b, tubo = tubo_a or tubo_b}
  for k, paso in ipairs(pasos) do
    paso.combo = k
    paso.ganado = {}
    for _, g in ipairs(paso.grupos) do
      local n = #g.celdas + (k >= 2 and 1 or 0) -- every piece is a unit; a chain link pays one more per group
      paso.ganado[g.color] = (paso.ganado[g.color] or 0) + n
      s.puntos = s.puntos + #g.celdas * 10 * k
    end
    for color, n in pairs(paso.ganado) do
      local antes = s.stock[color] or 0
      s.stock[color] = math.min(s.cap, antes + n)
      info.ganado[color] = (info.ganado[color] or 0) + (s.stock[color] - antes)
    end
    if paso.crea then s.creados = (s.creados or 0) + 1; if paso.crea[3] == R.PINCEL then s.pinceles_creados = (s.pinceles_creados or 0) + 1 end end
  end
  s.combo_max = math.max(s.combo_max, #pasos)
  if #pasos >= J.BONO_COMBO then
    info.mov_extra = math.min(#pasos - 2, COMBO_MAX_MOVS)
    s.mov = s.mov + info.mov_extra
  end
  if #R.jugadas(s.b) == 0 then info.barajado = R.barajar(s.b) end
  J.revisar(s)
  return true, info
end

-- can the current recipe be paid? -> ok, what is missing {color = n}
function J.puede_mezclar(s, i)
  local k = s.recetas[i]
  local costos = k and R.RECETAS[k]
  if not costos then return false, {} end
  local falta = {}
  for ing, n in pairs(costos) do
    if (s.stock[ing] or 0) < n then falta[ing] = n - (s.stock[ing] or 0) end
  end
  return next(falta) == nil, falta
end

-- mix recipe i: its ingredients are taken and one unit of the result is stocked, all at once. ok, razon
function J.mezclar(s, i)
  if s.fin then return false, "fin" end
  local k = s.recetas[i]
  if not k then return false, "sin_receta" end
  local ok = J.puede_mezclar(s, i)
  if not ok then return false, "faltan" end
  if (s.stock[k] or 0) >= s.cap then return false, "lleno" end
  for ing, n in pairs(R.RECETAS[k]) do s.stock[ing] = s.stock[ing] - n end
  s.stock[k] = (s.stock[k] or 0) + 1
  J.revisar(s)
  return true, k
end

-- load the brush for objective n: its units leave the stock (a brush already loaded gives its back first). ok, razon
function J.cargar(s, n)
  local o = s.obj[n]
  if s.fin then return false, "fin" end
  if not o or o.hecho then return false, "hecho" end
  local en_stock = s.stock[o.color] or 0
  if s.brush then en_stock = en_stock + (s.obj[s.brush.obj].color == o.color and s.brush.unidades or 0) end
  if en_stock < o.unidades then return false, "faltan", o.unidades - (s.stock[o.color] or 0) end
  if s.brush then
    local p = s.obj[s.brush.obj]
    s.stock[p.color] = (s.stock[p.color] or 0) + s.brush.unidades
  end
  s.stock[o.color] = s.stock[o.color] - o.unidades
  s.brush = {obj = n, color = o.color, unidades = o.unidades}
  return true
end

-- put the brush back (its units return to the stock)
function J.vaciar(s)
  if not s.brush then return end
  s.stock[s.brush.color] = (s.stock[s.brush.color] or 0) + s.brush.unidades
  s.brush = nil
end

-- paint a region with what the brush holds. ok, razon: "sin_carga", "zona" (wrong place: the load is kept)
function J.pintar(s, region)
  if s.fin then return false, "fin" end
  if not s.brush then return false, "sin_carga" end
  local o = s.obj[s.brush.obj]
  if region ~= o.region then return false, "zona" end
  o.hecho = true
  s.brush = nil
  J.revisar(s)
  return true, o.region
end

-- the colours worth collecting now: what the objectives need, or the ingredients of what they need mixed
function J.quiero(s)
  local q = {}
  for _, o in ipairs(s.obj) do
    if not o.hecho then
      local rc = R.RECETAS[o.color]
      if rc and s.recetas_ok[o.color] then
        for ing in pairs(rc) do q[ing] = true end
      else
        q[o.color] = true
      end
    end
  end
  return q
end

-- the swap that gathers the most of what is wanted (for the bot and for the tutorial's hand): {r1, c1, r2, c2} or nil
function J.sugerencia(s)
  local q, mejor, nota, b = J.quiero(s), nil, -1, s.b
  for _, jg in ipairs(R.jugadas(b)) do
    local a, c = b.g[jg[1]][jg[2]], b.g[jg[3]][jg[4]]
    b.g[jg[1]][jg[2]], b.g[jg[3]][jg[4]] = c, a
    local n = 0
    for _, g in ipairs(R.grupos(b)) do if q[g.color] then n = n + #g.celdas end end
    b.g[jg[1]][jg[2]], b.g[jg[3]][jg[4]] = a, c
    if n > nota then mejor, nota = jg, n end
  end
  -- a brush on the board: the line it would clear, counting what is wanted
  for r = 1, b.filas do
    for c = 1, b.cols do
      if b.g[r][c] == R.PINCEL then
        for _, d in ipairs({{0, 1}, {0, -1}, {1, 0}, {-1, 0}}) do
          local r2, c2 = r + d[1], c + d[2]
          if R.vecinas(b, r, c, r2, c2) then
            local n = 0
            if d[1] == 0 then
              for k = 1, b.cols do if q[b.g[r][k]] then n = n + 1 end end
            else
              for k = 1, b.filas do if q[b.g[k][c2]] then n = n + 1 end end
            end
            if n > nota then mejor, nota = {r, c, r2, c2}, n end
          end
        end
      end
    end
  end
  -- a tube: the colour it would take off the board
  for r = 1, b.filas do
    for c = 1, b.cols do
      if b.g[r][c] == R.TUBO then
        for _, d in ipairs({{0, 1}, {0, -1}, {1, 0}, {-1, 0}}) do
          local r2, c2 = r + d[1], c + d[2]
          if R.vecinas(b, r, c, r2, c2) and q[b.g[r2][c2]] then
            local n, color = 0, b.g[r2][c2]
            for rr = 1, b.filas do for cc = 1, b.cols do if b.g[rr][cc] == color then n = n + 1 end end end
            if n > nota then mejor, nota = {r, c, r2, c2}, n end
          end
        end
      end
    end
  end
  return mejor
end

-- stars: 1 for winning, +1 with a quarter of the moves left, +1 with a chain of 4 or half the moves left
function J.estrellas(s)
  if s.fin ~= "gana" then return 0 end
  local total = s.nivel.movimientos
  local e = 1
  if s.mov * 4 >= total then e = e + 1 end
  if s.combo_max >= 4 or s.mov * 2 >= total then e = e + 1 end
  return e
end

return J
