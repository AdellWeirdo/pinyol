-- Shared constants and small helpers for main.lua and dibujo.lua.
local R = require("reglas")
local L = require("layout")
local lang = require("lang")

local U = {}

U.C = L.caja
U.CELDA = L.celda
U.TINTA, U.TINTA_SUAVE, U.PERGAMINO = 0x4A2E18, 0x8A6A44, 0xECD8AA
U.VERDE_OK, U.ROJO_NO, U.DORADO = 0x2E7D32, 0xB3261E, 0xF2C230
U.FT, U.FB, U.FS = "snes_title", "snes_body", "snes_small"

U.BTN_AYUDA = {U.C.mensaje[1] + U.C.mensaje[3] - 20, U.C.mensaje[2] + 1, 18, 16}
U.FRAME, U.RGB, U.ORDEN = {}, {}, {}
-- the colours' names in the player's language: NOMBRE[k] for labels (capitals), MIN[k] inside a sentence
U.NOMBRE = setmetatable({}, {__index = function(_, k) return lang.tr("col_" .. k) end})
U.MIN = setmetatable({}, {__index = function(_, k) return lang.tr("colm_" .. k) end})
for i, c in ipairs(L.colores) do
  U.FRAME[c.clave], U.RGB[c.clave], U.ORDEN[c.clave] = i - 1, c.rgb, i
end
U.FRAME[R.ESPONJA] = #L.colores
U.FRAME[R.PINCEL] = #L.colores + 1
U.FRAME[R.TUBO] = #L.colores + 2

function U.tx(str, x, y, color, font, align, extra)
  local o = {color = color or 0xFFFFFF, font = font or U.FB, align = align or "left"}
  if extra then for k, v in pairs(extra) do o[k] = v end end
  return text(str, x, y, o)
end

-- text that fits its width, never cut: in the font asked for, else in the next smaller (title, body, small), else wrapped
-- to the width; returns the font used. What fits is measured once per (language, text, font, width, scale) and remembered:
-- measuring is the costly part and the same words are drawn every frame.
local fit_cache = {}
function U.tx_fit(str, x, y, color, font, align, w, extra)
  local sc = extra and extra.scale or 1
  local key = lang.code .. "|" .. font .. "|" .. w .. "|" .. sc .. "|" .. str
  local f = fit_cache[key]
  if f == nil then
    f = false -- nothing fits: wrapped in the last font
    local chain = {[U.FT] = {U.FT, U.FB, U.FS}, [U.FB] = {U.FB, U.FS}}
    local last = font
    for _, cand in ipairs(chain[font] or {font}) do
      last = cand
      if (textw(str, {font = cand, scale = sc})) <= w then f = cand; break end
    end
    fit_cache[key] = f or ("wrap:" .. last)
    f = fit_cache[key]
  end
  if f:sub(1, 5) == "wrap:" then
    local o = {width = w}
    if extra then for k, v in pairs(extra) do o[k] = v end end
    f = f:sub(6)
    U.tx(str, x, y, color, f, align, o)
  else
    U.tx(str, x, y, color, f, align, extra)
  end
  return f
end

-- a value worked out once per language (what only changes when the language or the data does)
local memo = {}
function U.memo(key, fn)
  local k = lang.code .. "|" .. key
  local v = memo[k]
  if v == nil then v = fn(); memo[k] = v end
  return v
end

-- the name of a level, its note and a painting's region in the player's language
function U.titulo_nivel(nivel) return lang.tr("lvl_" .. nivel.id) end
function U.nota_nivel(nivel) return nivel.nota and lang.tr("lvl_" .. nivel.id .. "_n") or nil end
function U.titulo_obra(obra) return lang.tr("obra_" .. obra.id) end
function U.region(obra, k) return lang.tr("reg_" .. obra.id .. "_" .. k) end

function U.dentro(x, y, caja)
  return x >= caja[1] and x < caja[1] + caja[3] and y >= caja[2] and y < caja[2] + caja[4]
end

function U.copia(g)
  local c = {}
  for r = 1, #g do
    c[r] = {}
    for k = 1, L.cols do c[r][k] = g[r][k] end
  end
  return c
end

function U.copia_plana(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

function U.ordenados(costos)
  local ks = {}
  for k in pairs(costos) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return U.ORDEN[a] < U.ORDEN[b] end)
  return ks
end

-- a drop (or the sponge) at x, y; small = the 12x12 icon
function U.gota(clave, x, y, extra, pequena)
  local o = {frame = U.FRAME[clave]}
  if extra then for k, v in pairs(extra) do o[k] = v end end
  img(pequena and "GOTAS_S" or "GOTAS", x, y, o)
end

function U.mezcla(c, d, t)
  local r1, g1, b1 = c >> 16 & 255, c >> 8 & 255, c & 255
  local r2, g2, b2 = d >> 16 & 255, d >> 8 & 255, d & 255
  return (math.floor(r1 + (r2 - r1) * t) << 16) | (math.floor(g1 + (g2 - g1) * t) << 8) | math.floor(b1 + (b2 - b1) * t)
end

function U.clara(c) return U.mezcla(c, 0xFFFFFF, 0.45) end

function U.suave(t) return t * t * (3 - 2 * t) end -- smoothstep
function U.sale(t) local u = 1 - t; return 1 - u * u * u end -- ease out cubic
function U.rebote(t) -- out_back-ish: overshoots then settles
  local c1, c3 = 1.70158, 2.70158
  local u = t - 1
  return 1 + c3 * u * u * u + c1 * u * u
end

-- where a colour's icon sits in the stock cabinet (top-left of the 12x12)
function U.pos_reserva(nivel, clave)
  local claves, visto = {}, {}
  for _, k in ipairs(nivel.paleta) do claves[#claves + 1] = k; visto[k] = true end
  for _, k in ipairs(nivel.recetas) do
    if not visto[k] then claves[#claves + 1] = k end
  end
  for i, k in ipairs(claves) do
    if k == clave then
      local col, fila = (i - 1) // 4, (i - 1) % 4
      return U.C.reserva[1] + 3 + col * 28, U.C.reserva[2] + 16 + fila * 13
    end
  end
  return U.C.reserva[1] + 4, U.C.reserva[2] + 16
end

function U.claves_reserva(nivel)
  local claves, visto = {}, {}
  for _, k in ipairs(nivel.paleta) do claves[#claves + 1] = k; visto[k] = true end
  for _, k in ipairs(nivel.recetas) do
    if not visto[k] then claves[#claves + 1] = k end
  end
  return claves
end

-- ------------------------------------------------------------------------------------------ paintings and progress
function U.niv() return G.obra.niveles end

function U.estrellas(obra_id, i)
  local e = G.progreso.estrellas[obra_id]
  return e and e[i] or 0
end

-- a painting opens when every level of the one before has at least a star
function U.obra_libre(idx)
  if idx == 1 then return true end
  local previa = G.obras[idx - 1]
  for i = 1, #previa.niveles do
    if U.estrellas(previa.id, i) < 1 then return false end
  end
  return true
end

function U.nivel_libre(i) return i == 1 or U.estrellas(G.obra.id, i - 1) > 0 end

-- how many levels of a painting are done
function U.hechos(obra)
  local n = 0
  for i = 1, #obra.niveles do if U.estrellas(obra.id, i) > 0 then n = n + 1 end end
  return n
end

return U
