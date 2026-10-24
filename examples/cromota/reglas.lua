-- CROMOTA rules: the board and the pigment arithmetic. No drawing, no animation: every function is deterministic
-- (a board carries its own seeded stream) and tested alone (tests/reglas.script).
-- A cell holds a colour key ("rojo"...) or "esponja" (a blocker: it never swaps, it goes when a group bursts beside it).
local rng = require("rng")
local R = {}

R.ESPONJA = "esponja"
R.TUBO = "tubo" -- a paint tube: a group of 5+ makes one; swapped with a coloured neighbour it clears every drop of that colour
R.PINCEL = "pincel" -- a wide brush: a group of 4+ makes one; swapped with a neighbour it clears that row or column
R.MAX_CASCADA = 30 -- safety: a turn that does not settle by here is cut

-- recipes by result; each one makes one unit of its result
R.RECETAS = {
  naranja = {rojo = 1, amarillo = 1},
  verde = {amarillo = 1, azul = 1},
  violeta = {rojo = 1, azul = 1},
  celeste = {azul = 2, blanco = 1},
  marino = {azul = 2, negro = 1},
}

local function es_color(p) return p ~= nil and p ~= R.ESPONJA and p ~= R.PINCEL and p ~= R.TUBO end
local function movible(p) return p ~= nil and p ~= R.ESPONJA end

local function elegir(b, pesos, paleta)
  local total = 0
  for _, k in ipairs(paleta) do total = total + (pesos[k] or 1) end
  local x = b.rng:float() * total
  for _, k in ipairs(paleta) do
    x = x - (pesos[k] or 1)
    if x < 0 then return k end
  end
  return paleta[#paleta]
end

-- a colour that would not complete a run of three at (r, c) given what is already left of / above it
local function sin_racha(b, r, c, pesos, paleta)
  for _ = 1, 20 do
    local p = elegir(b, pesos, paleta)
    local g = b.g
    local h = c > 2 and g[r][c - 1] == p and g[r][c - 2] == p
    local v = r > 2 and g[r - 1][c] == p and g[r - 2][c] == p
    if not h and not v then return p end
  end
  return paleta[1]
end

function R.celda(b, r, c) return b.g[r] and b.g[r][c] end

-- groups of 3+ in a row or column; groups that share a piece are one (an L or a T is one group)
function R.grupos(b)
  local marca, runs = {}, {}
  local function run(cells)
    runs[#runs + 1] = cells
  end
  for r = 1, b.filas do
    local c = 1
    while c <= b.cols do
      local p = b.g[r][c]
      local e = c
      while es_color(p) and e < b.cols and b.g[r][e + 1] == p do e = e + 1 end
      if es_color(p) and e - c >= 2 then
        local cells = {}
        for k = c, e do cells[#cells + 1] = {r, k} end
        run(cells)
      end
      c = e + 1
    end
  end
  for c = 1, b.cols do
    local r = 1
    while r <= b.filas do
      local p = b.g[r][c]
      local e = r
      while es_color(p) and e < b.filas and b.g[e + 1][c] == p do e = e + 1 end
      if es_color(p) and e - r >= 2 then
        local cells = {}
        for k = r, e do cells[#cells + 1] = {k, c} end
        run(cells)
      end
      r = e + 1
    end
  end
  -- merge runs that share a cell
  local grupos = {}
  for _, cells in ipairs(runs) do
    local into
    for _, cell in ipairs(cells) do
      local id = marca[cell[1] * 100 + cell[2]]
      if id then
        if not into then
          into = id
        elseif id ~= into then -- two groups meet through this run: fold id into `into`
          for _, x in ipairs(grupos[id].celdas) do
            marca[x[1] * 100 + x[2]] = into
            grupos[into].celdas[#grupos[into].celdas + 1] = x
          end
          grupos[id].celdas = {}
        end
      end
    end
    if not into then
      grupos[#grupos + 1] = {color = b.g[cells[1][1]][cells[1][2]], celdas = {}}
      into = #grupos
    end
    for _, cell in ipairs(cells) do
      local k = cell[1] * 100 + cell[2]
      if marca[k] ~= into then
        marca[k] = into
        grupos[into].celdas[#grupos[into].celdas + 1] = cell
      end
    end
  end
  local out = {}
  for _, g in ipairs(grupos) do
    if #g.celdas > 0 then out[#out + 1] = g end
  end
  return out
end

local function cambia(b, r1, c1, r2, c2)
  b.g[r1][c1], b.g[r2][c2] = b.g[r2][c2], b.g[r1][c1]
end

-- can these two cells swap at all (neighbours, both there, neither a blocker)?
function R.vecinas(b, r1, c1, r2, c2)
  if not (b.g[r1] and b.g[r2] and b.g[r1][c1] and b.g[r2][c2]) then return false end
  if math.abs(r1 - r2) + math.abs(c1 - c2) ~= 1 then return false end
  local a, c = b.g[r1][c1], b.g[r2][c2]
  if a == R.TUBO then return es_color(c) end -- a tube works on a colour: not on a brush, a sponge or another tube
  if c == R.TUBO then return es_color(a) end
  return movible(a) and movible(c)
end

-- every swap that makes a group: {{r1, c1, r2, c2}, ...}
function R.jugadas(b)
  local out = {}
  for r = 1, b.filas do
    for c = 1, b.cols do
      for _, d in ipairs({{0, 1}, {1, 0}}) do
        local r2, c2 = r + d[1], c + d[2]
        if R.vecinas(b, r, c, r2, c2) and b.g[r][c] ~= b.g[r2][c2] then
          local con_pincel = b.g[r][c] == R.PINCEL or b.g[r2][c2] == R.PINCEL or b.g[r][c] == R.TUBO or b.g[r2][c2] == R.TUBO
          cambia(b, r, c, r2, c2)
          local ok = con_pincel or #R.grupos(b) > 0
          cambia(b, r, c, r2, c2)
          if ok then out[#out + 1] = {r, c, r2, c2} end
        end
      end
    end
  end
  return out
end

-- swap and keep it only if it makes a group; false = it was put back
function R.intercambiar(b, r1, c1, r2, c2)
  if not R.vecinas(b, r1, c1, r2, c2) then return false end
  local con_pincel = b.g[r1][c1] == R.PINCEL or b.g[r2][c2] == R.PINCEL or b.g[r1][c1] == R.TUBO or b.g[r2][c2] == R.TUBO
  cambia(b, r1, c1, r2, c2)
  if not con_pincel and #R.grupos(b) == 0 then
    cambia(b, r1, c1, r2, c2)
    return false
  end
  return true
end

-- take the groups off; a blocker beside a burst piece goes too. Returns {{r, c, p}, ...}
function R.limpiar(b, grupos, conserva)
  local quitar, visto = {}, {}
  if conserva then visto[conserva[1] * 100 + conserva[2]] = true end -- that piece stays (it becomes a brush)
  local function marcar(r, c)
    local k = r * 100 + c
    if not visto[k] and b.g[r] and b.g[r][c] then
      visto[k] = true
      quitar[#quitar + 1] = {r, c, b.g[r][c]}
    end
  end
  for _, g in ipairs(grupos) do
    for _, cell in ipairs(g.celdas) do marcar(cell[1], cell[2]) end
  end
  local base = #quitar
  for i = 1, base do
    local r, c = quitar[i][1], quitar[i][2]
    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
      local rr, cc = r + d[1], c + d[2]
      if b.g[rr] and b.g[rr][cc] == R.ESPONJA then marcar(rr, cc) end
    end
  end
  for _, q in ipairs(quitar) do b.g[q[1]][q[2]] = nil end
  return quitar
end

-- would colour p at (r, c) make a run of three with what is already around it?
local function racha(b, r, c, p)
  local function n(dr, dc)
    local k, rr, cc = 0, r + dr, c + dc
    while b.g[rr] and b.g[rr][cc] == p do k, rr, cc = k + 1, rr + dr, cc + dc end
    return k
  end
  return n(0, -1) + n(0, 1) >= 2 or n(-1, 0) + n(1, 0) >= 2
end

-- gravity, then new drops from the top. New drops never make a group by themselves: a chain can only come from what is
-- on the board, so it can be planned. Returns {{c, de, a, p}, ...}: column, row it was at (<= 0: it came from above),
-- row it lands on, piece.
function R.caer(b)
  local movs, vacios = {}, {}
  for c = 1, b.cols do
    local w = b.filas
    for r = b.filas, 1, -1 do
      local p = b.g[r][c]
      if p then
        if w ~= r then
          b.g[w][c], b.g[r][c] = p, nil
          movs[#movs + 1] = {c = c, de = r, a = w, p = p}
        end
        w = w - 1
      end
    end
    vacios[c] = w
  end
  for r = 1, b.filas do
    for c = 1, b.cols do
      if not b.g[r][c] then
        local p
        for _ = 1, 20 do
          p = elegir(b, b.pesos, b.paleta)
          if not racha(b, r, c, p) then break end
        end
        b.g[r][c] = p
        movs[#movs + 1] = {c = c, de = r - vacios[c], a = r, p = p}
      end
    end
  end
  return movs
end

-- the brush: clear the whole row (a horizontal swap) or column of the cell it landed on. One step, like a burst.
function R.pincelazo(b, rd, cd, horizontal)
  local celdas, quitados, por_color = {}, {}, {}
  if horizontal then
    for c = 1, b.cols do celdas[#celdas + 1] = {rd, c} end
  else
    for r = 1, b.filas do celdas[#celdas + 1] = {r, cd} end
  end
  local grupos = {}
  for _, cell in ipairs(celdas) do
    local p = b.g[cell[1]][cell[2]]
    if p then
      quitados[#quitados + 1] = {cell[1], cell[2], p}
      if es_color(p) then
        por_color[p] = por_color[p] or {color = p, celdas = {}}
        local g = por_color[p]
        g.celdas[#g.celdas + 1] = {cell[1], cell[2]}
      end
      b.g[cell[1]][cell[2]] = nil
    end
  end
  for _, g in pairs(por_color) do grupos[#grupos + 1] = g end
  table.sort(grupos, function(x, y) return x.color < y.color end) -- pairs() order is not a promise we want to lean on
  return {grupos = grupos, quitados = quitados, caidas = R.caer(b), linea = {horizontal = horizontal, idx = horizontal and rd or cd}}
end

-- the tube: every drop of one colour goes (and sponges beside them), and the tube itself
function R.tubazo(b, rt, ct, color)
  local celdas = {}
  for rr = 1, b.filas do
    for cc = 1, b.cols do
      if b.g[rr][cc] == color then celdas[#celdas + 1] = {rr, cc} end
    end
  end
  local grupo = {color = color, celdas = celdas}
  local quitados = R.limpiar(b, {grupo})
  if b.g[rt][ct] == R.TUBO then
    quitados[#quitados + 1] = {rt, ct, R.TUBO}
    b.g[rt][ct] = nil
  end
  return {grupos = {grupo}, quitados = quitados, caidas = R.caer(b), tubo = {r = rt, c = ct, color = color}}
end

-- the turn after a swap: groups burst, things fall, again. pasos = {{grupos, quitados, caidas}, ...}
-- crea = {r1, c1, r2, c2, permite = {pincel = true, tubo = true}}: the swap that started it; a first group that holds one of
-- these cells leaves a special there: a tube from 5 drops, a brush from 4 (when the level allows it)
function R.resolver(b, crea)
  local pasos = {}
  while #pasos < R.MAX_CASCADA do
    local gs = R.grupos(b)
    if #gs == 0 then break end
    local conserva, tipo
    if crea and #pasos == 0 then
      for _, g in ipairs(gs) do
        local este = (#g.celdas >= 5 and crea.permite.tubo) and R.TUBO or ((#g.celdas >= 4 and crea.permite.pincel) and R.PINCEL or nil)
        if este and (not tipo or este == R.TUBO) then
          for _, cell in ipairs(g.celdas) do
            for k = 0, 1 do
              if cell[1] == crea[k * 2 + 1] and cell[2] == crea[k * 2 + 2] and (not conserva or este == R.TUBO and tipo ~= R.TUBO) then
                conserva, tipo = {cell[1], cell[2]}, este
              end
            end
          end
        end
      end
    end
    local q = R.limpiar(b, gs, conserva)
    if conserva then b.g[conserva[1]][conserva[2]] = tipo end
    pasos[#pasos + 1] = {grupos = gs, quitados = q, caidas = R.caer(b), crea = conserva and {conserva[1], conserva[2], tipo} or nil}
  end
  return pasos
end

-- reshuffle the colours (blockers stay) until nothing bursts by itself and a move exists
function R.barajar(b)
  for _ = 1, 100 do
    local lista = {}
    for r = 1, b.filas do
      for c = 1, b.cols do
        if es_color(b.g[r][c]) then lista[#lista + 1] = b.g[r][c] end
      end
    end
    b.rng:shuffle(lista)
    local i = 0
    for r = 1, b.filas do
      for c = 1, b.cols do
        if es_color(b.g[r][c]) then
          i = i + 1
          b.g[r][c] = lista[i]
        end
      end
    end
    if #R.grupos(b) == 0 and #R.jugadas(b) > 0 then return true end
  end
  return false
end

-- a new board for a level: no group to start with, at least one move
function R.nuevo(nivel)
  local b = {cols = nivel.cols or 8, filas = nivel.filas or 7, g = {}, paleta = nivel.paleta, pesos = nivel.pesos or {},
            rng = rng.new(nivel.semilla or 1)}
  for r = 1, b.filas do b.g[r] = {} end
  for _, e in ipairs(nivel.bloqueos or {}) do b.g[e[1]][e[2]] = R.ESPONJA end
  for r = 1, b.filas do
    for c = 1, b.cols do
      if not b.g[r][c] then b.g[r][c] = sin_racha(b, r, c, b.pesos, b.paleta) end
    end
  end
  if #R.jugadas(b) == 0 then R.barajar(b) end
  return b
end

-- ---------------------------------------------------------------------------------------------- pigments
-- Can the stock still pay for these colours (units each), crafting what is mixed? need = {azul = 3, verde = 1}
function R.alcanzable(stock, recetas_ok, need)
  local falta, bases = {}, {}
  for k, n in pairs(need) do
    local rest = n - (stock[k] or 0)
    if rest > 0 then
      local rc = R.RECETAS[k]
      if rc and recetas_ok[k] then
        for ing, q in pairs(rc) do bases[ing] = (bases[ing] or 0) + q * rest end
      else
        falta[k] = (falta[k] or 0) + rest
      end
    end
  end
  for k, n in pairs(bases) do
    local libre = (stock[k] or 0) - (need[k] or 0) -- what the stock holds beyond its own objective
    if libre < n then falta[k] = (falta[k] or 0) + (n - math.max(libre, 0)) end
  end
  return next(falta) == nil, falta
end

return R
