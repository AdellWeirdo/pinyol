-- CROMOTA drawing: every screen, over the canonical 480x320 UI (assets/FONDO). No rules here: it reads G (the shared
-- state set by main.lua) and the play state G.P.
local R = require("reglas")
local J = require("juego")
local L = require("layout")
local U = require("util")
local lang = require("lang")
local juice = require("juice")

local D = {}
local C, CELDA = U.C, U.CELDA
local tx, gota, dentro, tx_fit = U.tx, U.gota, U.dentro, U.tx_fit
local TINTA, TINTA_SUAVE, PERGAMINO = U.TINTA, U.TINTA_SUAVE, U.PERGAMINO
local VERDE_OK, ROJO_NO, DORADO = U.VERDE_OK, U.ROJO_NO, U.DORADO
local FT, FB, FS = U.FT, U.FB, U.FS
local RGB, NOMBRE, FRAME = U.RGB, U.NOMBRE, U.FRAME
local OB_W, OB_H = L.obra_w, L.obra_h
local function NV() return G.obra.niveles end

-- ------------------------------------------------------------------------------------------------ small pieces
local function placa(x, y, w, h)
  rect(x + 3, y + 4, w, h, 0x120A04)
  rect(x + 2, y + 2, w, h, 0x2A1C10)
  grad(x, y, w, h, 0xF4E6BE, 0xDEC690)
  box(x, y, w, h, 0x7A5230)
  box(x + 2, y + 2, w - 4, h - 4, 0xC4A272)
  for _, p in ipairs({{x + 4, y + 4}, {x + w - 5, y + 4}, {x + 4, y + h - 5}, {x + w - 5, y + h - 5}}) do
    rect(p[1], p[2], 1, 1, 0x8A6238)
  end
end
D.placa = placa

local function estrella(x, y, llena, k)
  k = k or 1
  local c = llena and DORADO or 0xA89A80
  local pts = {}
  for i = 0, 9 do
    local a, rr = math.rad(-90 + i * 36), ((i % 2 == 0) and 10 or 4.4) * k
    pts[#pts + 1] = x + math.cos(a) * rr
    pts[#pts + 1] = y + math.sin(a) * rr
  end
  poly(pts, llena and U.clara(c) or 0x8C806A, true)
  local inner = {}
  for i = 1, #pts, 2 do
    inner[#inner + 1] = x + (pts[i] - x) * 0.78
    inner[#inner + 1] = y + (pts[i + 1] - y) * 0.78
  end
  poly(inner, c, true)
  poly(pts, 0x6A4A20, false)
end

local function check(x, y, color)
  for d = 0, 1 do
    line(x - 4, y + d, x - 1, y + 3 + d, color)
    line(x - 1, y + 3 + d, x + 5, y - 4 + d, color)
  end
end

local function flecha(x, y, color)
  rect(x, y - 1, 12, 3, color)
  tri(x + 10, y - 6, x + 10, y + 6, x + 18, y, color, true)
end

local function numero(str, x, y, color, font, align, scale)
  tx(str, x, y, color, font or FT, align or "center",
     {outline = 0x1A0E06, shadow = 0x000000, shadow_x = 1, shadow_y = 2, scale = scale})
end

local ESPINAS = {}
for i = 0, 15 do
  local a, rr = math.rad(i * 22.5), (i % 2 == 0) and 29 or 21
  ESPINAS[#ESPINAS + 1] = math.cos(a) * rr
  ESPINAS[#ESPINAS + 1] = math.sin(a) * rr * 0.95
end

-- ------------------------------------------------------------------------------------------------ play
function D.combo(P)
  local c = P.combo
  if not c then return end
  local bx, by, bw, bh = table.unpack(C.combo)
  local cx, cy = bx + bw // 2, by + 26
  local k = U.rebote(math.min(1, (110 - c.t) / 14))
  local sale = c.t < 14 and c.t / 14 or 1
  k = k * sale
  local pts = {}
  for i = 1, #ESPINAS, 2 do
    pts[#pts + 1] = cx + ESPINAS[i] * k
    pts[#pts + 1] = cy + ESPINAS[i + 1] * k
  end
  poly(pts, 0x0F3A40, true)
  local mid = {}
  for i = 1, #pts, 2 do
    mid[#mid + 1] = cx + (pts[i] - cx) * 0.92
    mid[#mid + 1] = cy + (pts[i + 1] - cy) * 0.92
  end
  poly(mid, 0x39E0D0, true)
  local pts2 = {}
  for i = 1, #pts, 2 do
    pts2[#pts2 + 1] = cx + (pts[i] - cx) * 0.74
    pts2[#pts2 + 1] = cy + (pts[i + 1] - cy) * 0.74
  end
  poly(pts2, 0x168A8E, true)
  if k > 0.6 then
    tx(lang.tr("hud_combo"), cx, cy - 15, 0xFFFFFF, FS, "center", {outline = 0x0F3A40})
    numero("x" .. c.n, cx, cy - 4, DORADO, FT, "center")
  end
  if c.extra > 0 and c.t < 100 then
    placa(bx + 6, by + 50, bw - 12, 14)
    tx_fit(lang.tr("hud_combo_moves", {n = c.extra}), bx + bw // 2, by + 53, TINTA, FS, "center", bw - 14)
  end
end

local function dibuja_pieza(P, r, c, f)
  local p = P.V[r][c]
  if not p then return end
  local cx, cy = table.unpack(C.celdas)
  local x, y = cx + (c - 1) * CELDA + 2, cy + (r - 1) * CELDA + 2 + (P.D[r][c] or 0)
  local extra
  if f and f.tipo == "swap" then
    local k = f.t and math.min(1, f.t / f.dur) or 0
    if f.vuelta then k = 1 - k end
    k = U.suave(k)
    if r == f.r1 and c == f.c1 then x, y = x + (f.c2 - f.c1) * CELDA * k, y + (f.r2 - f.r1) * CELDA * k
    elseif r == f.r2 and c == f.c2 then x, y = x + (f.c1 - f.c2) * CELDA * k, y + (f.r1 - f.r2) * CELDA * k end
  elseif f and f.tipo == "pop" and f.set and f.set[r * 100 + c] then
    local k = U.suave((f.t or 0) / f.dur)
    extra = {scale = math.max(0.12, 1.15 - k * 1.05), alpha = 1 - k * 0.6}
  end
  local aterrizaje = P.land[r * 100 + c]
  if aterrizaje and not extra then
    local s = math.sin(math.pi * (1 - aterrizaje / 8))
    extra = {scale_x = 1 + 0.12 * s, scale_y = 1 - 0.16 * s}
    y = y + 12 * 0.16 * s
  end
  local sel = P.sel and P.sel[1] == r and P.sel[2] == c
  if sel and not extra and not P.busy then
    local b = 0.5 + 0.5 * math.sin(t() * 9)
    extra = {scale = 1.08 + 0.05 * b}
    y = y - 1
  end
  gota(p, math.floor(x), math.floor(y), extra)
end

local HOLD_SCALE, HOLD_LIFT = 1.3, 14

function D.tablero(P)
  local cx, cy, cw, ch = table.unpack(C.celdas)
  local ox, oy = juice.offset()
  camera(ox, oy)
  clip(cx, cy, cw, ch)
  local f = P.cola[1]
  for r = 1, L.filas do
    for c = 1, L.cols do dibuja_pieza(P, r, c, f) end
  end
  if P.rayo then -- the brush's stroke across its row or column
    local k = P.rayo.t / 16
    local c1, c2 = 0xFFF2B0, 0x8A5A10
    if P.rayo.horizontal then
      local y = cy + (P.rayo.idx - 1) * CELDA
      local ancho = math.floor(cw * math.min(1, k * 2.2))
      grad(cx, y + 2, ancho, CELDA - 4, c2, c1, {across = true, add = true})
      rect(cx + ancho - 2, y, 2, CELDA, 0xFFFFFF)
    else
      local x = cx + (P.rayo.idx - 1) * CELDA
      local alto = math.floor(ch * math.min(1, k * 2.2))
      grad(x + 2, cy, CELDA - 4, alto, c1, c2, {add = true})
      rect(x, cy + alto - 2, CELDA, 2, 0xFFFFFF)
    end
  end
  clip()
  if P.dedo and P.arrastre then -- the held drop, bigger and lifted so the finger does not hide it
    local p = P.V[P.arrastre[1]] and P.V[P.arrastre[1]][P.arrastre[2]]
    if p then gota(p, P.dedo[1] - 12, P.dedo[2] - 12 - HOLD_LIFT, {scale = HOLD_SCALE}) end
  end
  local pulso = 0.5 + 0.5 * math.sin(t() * 8)
  if P.sel then
    local x, y = cx + (P.sel[2] - 1) * CELDA, cy + (P.sel[1] - 1) * CELDA
    box(x, y, CELDA, CELDA, U.mezcla(0xC89A18, DORADO, pulso))
    box(x + 1, y + 1, CELDA - 2, CELDA - 2, 0x5A4208)
    for _, e in ipairs({{x, y}, {x + CELDA - 3, y}, {x, y + CELDA - 3}, {x + CELDA - 3, y + CELDA - 3}}) do
      rect(e[1], e[2], 3, 3, 0xFFF2B0)
    end
  elseif G.usa_botones then
    local x, y = cx + (P.cursor[2] - 1) * CELDA, cy + (P.cursor[1] - 1) * CELDA
    box(x, y, CELDA, CELDA, pulso > 0.5 and 0xFFFFFF or 0x9A9A9A)
  end
  if P.pista and not P.busy then
    for k = 0, 1 do
      local x, y = cx + (P.pista[k * 2 + 2] - 1) * CELDA, cy + (P.pista[k * 2 + 1] - 1) * CELDA
      if pulso > 0.4 then box(x + 1, y + 1, CELDA - 2, CELDA - 2, 0xFFFFFF) end
    end
  end
  camera()
end

function D.vuelos(P)
  for _, v in ipairs(P.vuelos) do
    if v.t >= 0 then
      local p = math.min(1, v.t / v.dur)
      local e = p * p
      local mx, my = (v.x0 + v.x1) / 2, math.min(v.y0, v.y1) - 30
      local x = (1 - e) * (1 - e) * v.x0 + 2 * (1 - e) * e * mx + e * e * v.x1
      local y = (1 - e) * (1 - e) * v.y0 + 2 * (1 - e) * e * my + e * e * v.y1
      gota(v.color, math.floor(x - 6), math.floor(y - 6), nil, true)
    end
  end
end

function D.popups(P)
  for _, p in ipairs(P.popups) do
    local y = p.y - p.t * 0.7
    local c = p.t > 30 and U.mezcla(p.color, 0x101018, (p.t - 30) / 12) or p.color
    tx(p.texto, math.floor(p.x), math.floor(y), c, FT, "center", {outline = 0x120A04, shadow = 0x000000, slide = true}) -- rises past the top on purpose
  end
end

local function cuenta(x, y, tenido, necesita, align)
  local color = tenido >= necesita and VERDE_OK or ((necesita > 0 and tenido == 0) and ROJO_NO or TINTA)
  tx(tenido .. "/" .. necesita, x, y, color, FS, align or "center")
end

function D.reserva(P)
  local x, y = C.reserva[1], C.reserva[2]
  tx_fit(lang.tr("hud_stock"), x + C.reserva[3] // 2, y + 5, 0xD8C49A, FS, "center", C.reserva[3] - 4, {shadow = 0x000000})
  for _, k in ipairs(U.claves_reserva(P.s.nivel)) do
    local cx, cy = U.pos_reserva(P.s.nivel, k)
    local n = P.shown[k] or 0
    local rb = P.rebote[k]
    local dy = rb and -math.floor(4 * math.sin(math.pi * (1 - rb / 14))) or 0
    gota(k, cx, cy + dy, nil, true)
    tx(tostring(n), cx + 14, cy + 2, rb and 0xFFE08A or (n == 0 and 0x9A8466 or 0xFFFFFF), FS, "left", {shadow = 0x000000})
  end
end

function D.objetivos(P)
  tx_fit(lang.tr("hud_goals"), C.obj_titulo[1] + C.obj_titulo[3] // 2, C.obj_titulo[2] + 3, TINTA, FS, "center", C.obj_titulo[3] - 4)
  for i, o in ipairs(P.s.obj) do
    local sx, sy, sw, sh = table.unpack(L.slots_obj[i])
    local cargado = P.s.brush and P.s.brush.obj == i
    local stock = P.shown[o.color] or 0
    local tenido = o.hecho and o.unidades or (cargado and P.s.brush.unidades or stock)
    local listo = not o.hecho and not cargado and stock >= o.unidades
    local bob = listo and math.floor(1.5 * math.sin(t() * 6)) or 0
    gota(o.color, sx + 4, sy + 4 + bob, o.hecho and {alpha = 0.4} or nil)
    if o.hecho then
      check(sx + 16, sy + 28, VERDE_OK)
    else
      cuenta(sx + sw // 2, sy + 36, math.min(tenido, o.unidades), o.unidades)
    end
    local pulso = 0.5 + 0.5 * math.sin(t() * 8)
    if cargado then
      box(sx, sy, sw, 34, U.mezcla(0xA07A10, DORADO, pulso))
      box(sx + 1, sy + 1, sw - 2, 32, U.mezcla(0xA07A10, DORADO, pulso))
    elseif listo then
      box(sx, sy, sw, 34, U.mezcla(0x1E6A28, 0x58D060, pulso))
    end
  end
end

function D.mezcla(P)
  tx_fit(lang.tr("hud_mix"), C.mezcla_titulo[1] + C.mezcla_titulo[3] // 2, C.mezcla_titulo[2] + 3, TINTA, FS, "center", C.mezcla_titulo[3] - 4)
  local s = P.s
  local k = s.recetas[s.receta]
  if not k then
    grad(C.mezcla[1] + 8, C.ing_a[2] - 3, C.mezcla[3] - 16, C.ing_a[4] + 4, 0xEBD8AC, 0xE4CE9C)
    tx_fit(lang.tr("mix_none1"), C.mezcla[1] + C.mezcla[3] // 2, C.mezcla[2] + 26, TINTA_SUAVE, FS, "center", C.mezcla[3] - 20)
    tx_fit(lang.tr("mix_none2"), C.mezcla[1] + C.mezcla[3] // 2, C.mezcla[2] + 42, TINTA_SUAVE, FS, "center", C.mezcla[3] - 20)
    return
  end
  local costos = R.RECETAS[k]
  local ings = U.ordenados(costos)
  local slots = {C.ing_a, C.ing_b}
  for i, ing in ipairs(ings) do
    local sl = slots[i]
    gota(ing, sl[1] + 6, sl[2] + 4)
    local alcanza = (P.shown[ing] or 0) >= costos[ing]
    tx("x" .. costos[ing], sl[1] + sl[3] // 2, sl[2] + 33, alcanza and VERDE_OK or ROJO_NO, FS, "center")
  end
  tx("+", C.ing_a[1] + C.ing_a[3] + (C.ing_b[1] - C.ing_a[1] - C.ing_a[3]) // 2, C.ing_a[2] + 12, TINTA, FT, "center")
  flecha(C.ing_b[1] + C.ing_b[3] + 6, C.ing_b[2] + 16, TINTA)
  local ok = J.puede_mezclar(s, s.receta)
  local pulso = ok and math.floor(1.5 * math.sin(t() * 6)) or 0
  gota(k, C.res[1] + 11, C.res[2] + 4 + pulso, ok and nil or {alpha = 0.4})
  tx(NOMBRE[k], C.res[1] + C.res[3] // 2, C.res[2] + 33, TINTA, FS, "center")
  local e = C.estado
  if ok then
    local b = 0.5 + 0.5 * math.sin(t() * 7)
    rect(e[1], e[2], e[3], e[4], U.mezcla(0xCFE6C4, 0xE6F6DC, b))
    box(e[1], e[2], e[3], e[4], VERDE_OK)
    tx_fit(lang.tr("mix_ready"), e[1] + 18, e[2] + 3, VERDE_OK, FS, "center", e[3] - 26)
    check(e[1] + e[3] - 11, e[2] + 7, VERDE_OK)
  else
    rect(e[1], e[2], e[3], e[4], 0xE0CDA4)
    box(e[1], e[2], e[3], e[4], 0xB8946A)
    tx_fit(lang.tr("mix_missing"), e[1] + e[3] // 2, e[2] + 3, TINTA_SUAVE, FS, "center", e[3] - 6)
  end
  if #s.recetas > 1 then
    tx_fit(lang.tr("mix_recipe", {i = s.receta, n = #s.recetas}), C.ing_a[1] + 48, C.estado[2] + 3, TINTA_SUAVE, FS, "center", 78)
  end
end

function D.pincel(P)
  local x, y, w, h = table.unpack(C.pincel)
  local b = P.s.brush
  local marco = b and (FRAME[b.color] + 1) or 0
  local bx, by = x + 14, y + 6
  if P.tintar then by = by + math.floor(4 * math.sin(math.pi * (1 - P.tintar / 10))) end
  if P.barrido then
    bx = bx + math.floor(math.sin(P.barrido.x * 0.5) * 3)
    by = by + math.floor(math.cos(P.barrido.x * 0.7) * 2)
  end
  img("BROCHA", bx, by, {frame = marco})
  if b then
    tx_fit(NOMBRE[b.color] .. " x" .. b.unidades, x + w // 2, y + 54, TINTA, FS, "center", w - 4)
  else
    tx_fit(lang.tr("brush_empty"), x + w // 2, y + 54, TINTA_SUAVE, FS, "center", w - 4)
  end
end

function D.obra(P)
  img("REF_" .. G.obra.id, C.obra[1], C.obra[2])
  img("REST", C.rest[1], C.rest[2])
  local b = P.barrido
  if P.s.brush then
    local r = P.s.obj[P.s.brush.obj].region
    local a = 0.16 + 0.24 * (0.5 + 0.5 * math.sin(t() * 7))
    img("OBRA_" .. G.obra.id .. "_" .. r, C.rest[1], C.rest[2], {tint = 0xFFFFFF, alpha = a})
  end
  if b then
    local x = C.rest[1] + math.min(b.x, OB_W)
    local c = U.clara(b.color)
    grad(math.max(C.rest[1], x - 14), C.rest[2], math.min(14, x - C.rest[1]), OB_H, 0x000000, c, {across = true, add = true})
    rect(x, C.rest[2], 2, OB_H, 0xFFFFFF)
  end
  if P.brillo and P.brillo > 0 then
    local f = P.brillo / 24
    local c = U.mezcla(0xD6A030, 0xFFF2B0, f)
    box(C.rest_marco[1] + 2, C.rest_marco[2] + 2, C.rest_marco[3] - 4, C.rest_marco[4] - 4, c)
    box(C.rest_marco[1] + 3, C.rest_marco[2] + 3, C.rest_marco[3] - 6, C.rest_marco[4] - 6, c)
  end
  tx_fit(U.titulo_obra(G.obra), C.obra_titulo[1] + C.obra_titulo[3] // 2, C.obra_titulo[2] + 5, TINTA, FS, "center", C.obra_titulo[3] - 6)
end

-- what the player should do next, and where to look: text, focus {tipo = "caja"|"region"|"jugada", ...}
local function ayuda(P)
  local s = P.s
  if s.fin then return nil end
  if s.brush then
    local r = s.obj[s.brush.obj].region
    return lang.tr("help_region"), {tipo = "region", caja = C.rest, p = P.regc and P.regc[r]}
  end
  for i, o in ipairs(s.obj) do
    if not o.hecho and (s.stock[o.color] or 0) >= o.unidades then
      return lang.tr("help_load"), {tipo = "caja", caja = L.slots_obj[i]}
    end
  end
  for _, o in ipairs(s.obj) do
    if not o.hecho and R.RECETAS[o.color] and s.recetas_ok[o.color] and (s.stock[o.color] or 0) < o.unidades then
      for i, k in ipairs(s.recetas) do
        if k == o.color and J.puede_mezclar(s, i) then
          if i == s.receta then return lang.tr("help_mix"), {tipo = "caja", caja = C.res} end
          return lang.tr("help_recipe"), {tipo = "caja", caja = C.ing_a}
        end
      end
    end
  end
  if P.tuto_j == nil then P.tuto_j = J.sugerencia(s) or false end
  return lang.tr("help_drag"), P.tuto_j and {tipo = "jugada", j = P.tuto_j} or nil
end

local function oscurece(c)
  local x, y, w, h = c[1] - 2, c[2] - 2, c[3] + 4, c[4] + 4
  shade(0, 0, 480, y)
  shade(0, y + h, 480, 320 - y - h)
  shade(0, y, x, h)
  shade(x + w, y, 480 - x - w, h)
end

local function flecha_abajo(x, y, color)
  local dy = math.floor(3 * math.sin(t() * 8))
  tri(x - 8, y - 14 + dy, x + 8, y - 14 + dy, x, y + dy, 0x1A0E06, true)
  tri(x - 6, y - 13 + dy, x + 6, y - 13 + dy, x, y - 3 + dy, color, true)
end

-- the dimming that points at what is next (drawn before the text strip so the text stays lit)
function D.coach_fondo(P)
  if not P.ayuda or P.busy or P.s.fin then return end
  local _, foco = ayuda(P)
  if foco and foco.tipo ~= "jugada" then oscurece(foco.caja) end
end

-- the pointing hand, arrows and rings
function D.coach_marca(P)
  if not P.ayuda or P.busy or P.s.fin then return end
  local _, foco = ayuda(P)
  if not foco then return end
  local pulso = 0.5 + 0.5 * math.sin(t() * 8)
  if foco.tipo == "jugada" then
    local j = foco.j
    local cx0, cy0 = C.celdas[1], C.celdas[2]
    local ax, ay = cx0 + (j[2] - 1) * CELDA + CELDA // 2, cy0 + (j[1] - 1) * CELDA + CELDA // 2
    local bx, by = cx0 + (j[4] - 1) * CELDA + CELDA // 2, cy0 + (j[3] - 1) * CELDA + CELDA // 2
    local ph = (t() * 0.9) % 2.2
    local x, y, k = ax, ay, 0
    if ph < 0.35 then x, y, k = ax, ay, ph / 0.35
    elseif ph < 1.15 then
      local e = U.suave((ph - 0.35) / 0.8)
      x, y, k = ax + (bx - ax) * e, ay + (by - ay) * e, 1
    elseif ph < 1.5 then x, y, k = bx, by, 1
    else return end
    circ(math.floor(x), math.floor(y), 8 + math.floor((1 - k) * 8), 0xFFFFFF, false)
    circ(math.floor(x) + 1, math.floor(y) + 2, 8, 0x000000, true)
    circ(math.floor(x), math.floor(y), 8, 0xFFFFFF, true)
    circ(math.floor(x), math.floor(y), 8, 0x4A2E18, false)
    circ(math.floor(x) - 2, math.floor(y) - 2, 2, 0xFFE8D0, true)
    return
  end
  local c = foco.caja
  box(c[1] - 2, c[2] - 2, c[3] + 4, c[4] + 4, U.mezcla(0xB88810, 0xFFF2B0, pulso))
  box(c[1] - 3, c[2] - 3, c[3] + 6, c[4] + 6, U.mezcla(0x7A5A08, DORADO, pulso))
  if foco.tipo == "region" then
    if foco.p then flecha_abajo(foco.p[1], foco.p[2] - 2, DORADO) end
  elseif c[2] > 40 then
    flecha_abajo(c[1] + c[3] // 2, c[2] - 3, DORADO)
  end
end

function D.mensaje(P)
  local texto, color
  if P.msg then texto, color = P.msg.texto, P.msg.color
  elseif P.ayuda then texto, color = ayuda(P), 0xFFFFFF end
  local b = U.BTN_AYUDA
  rect(b[1], b[2], b[3], b[4], P.ayuda and 0xF2D880 or 0xE0CDA4)
  box(b[1], b[2], b[3], b[4], 0x7A5230)
  tx("?", b[1] + b[3] // 2, b[2] + 3, TINTA, FB, "center")
  if not texto then return end
  local y = C.mensaje[2] + 5
  if P.msg and P.msg.t > P.msg.dur - 6 then y = y + (P.msg.t - (P.msg.dur - 6)) end -- slides up into place
  tx_fit(texto, C.mensaje[1] + (C.mensaje[3] - 20) // 2, y, color, FS, "center", C.mensaje[3] - 24, {shadow = 0x000000})
end

-- the explanation of a new element: everything dims but it, a bubble says what it is
function D.tour(P)
  local paso = P.tour and P.tour[1]
  if not paso then return end
  local c = paso.caja
  oscurece(c)
  local pulso = 0.5 + 0.5 * math.sin(t() * 8)
  box(c[1] - 2, c[2] - 2, c[3] + 4, c[4] + 4, U.mezcla(0xB88810, 0xFFF2B0, pulso))
  box(c[1] - 3, c[2] - 3, c[3] + 6, c[4] + 6, U.mezcla(0x7A5A08, DORADO, pulso))
  local w = 270
  local _, th = textw(paso.texto, {font = FS, width = w - 24})
  local h = th + 58
  local cx = c[1] + c[3] // 2
  local x = math.max(8, math.min(480 - w - 8, cx - w // 2))
  local arriba = c[2] + c[4] // 2 > 150
  local y = arriba and (c[2] - h - 12) or (c[2] + c[4] + 12)
  y = math.max(6, math.min(320 - h - 6, y))
  placa(x, y, w, h)
  local px = math.max(x + 14, math.min(x + w - 14, cx))
  if arriba then
    tri(px - 7, y + h, px + 7, y + h, px, y + h + 9, 0x7A5230, true)
    tri(px - 5, y + h - 1, px + 5, y + h - 1, px, y + h + 6, 0xDEC690, true)
  else
    tri(px - 7, y, px + 7, y, px, y - 9, 0x7A5230, true)
    tri(px - 5, y + 1, px + 5, y + 1, px, y - 6, 0xF4E6BE, true)
  end
  tx(paso.titulo, x + 12, y + 9, 0x9A5A10, FB, "left")
  tx(paso.texto, x + 12, y + 26, TINTA, FS, "left", {width = w - 24})
  local resto = #P.tour - 1
  if G.t_estado % 50 < 34 then
    tx(resto > 0 and lang.tr("tour_next_n", {n = resto}) or lang.tr("tour_next"), x + w - 12, y + h - 13, VERDE_OK, FS, "right")
  end
end

function D.hud(P)
  local s = P.s
  tx_fit(lang.tr("hud_level"), C.nivel[1] + C.nivel[3] // 2, C.nivel[2] + 5, TINTA, FS, "center", C.nivel[3] - 4)
  tx(tostring(P.n), C.nivel[1] + C.nivel[3] // 2, C.nivel[2] + 15, TINTA, FT, "center", {shadow = 0xC4A272})
  tx_fit(lang.tr("hud_moves"), C.mov[1] + C.mov[3] // 2, C.mov[2] + 5, TINTA, FS, "center", C.mov[3] - 4)
  local dy = P.mov_t > 0 and -math.floor(3 * math.sin(math.pi * (1 - P.mov_t / 10))) or 0
  local bajo = s.mov <= 3
  local col = bajo and U.mezcla(ROJO_NO, 0xFF6050, 0.5 + 0.5 * math.sin(t() * 10)) or 0x2A5DB0
  tx(tostring(s.mov), C.mov[1] + C.mov[3] // 2, C.mov[2] + 15 + dy, col, FT, "center", {shadow = 0xC4A272})
end

function D.juego(P)
  img("FONDO", 0, 0)
  D.hud(P)
  D.tablero(P)
  D.reserva(P)
  D.obra(P)
  D.mezcla(P)
  D.pincel(P)
  D.objetivos(P)
  D.combo(P)
  D.vuelos(P)
  G.fx:draw()
  D.popups(P)
  if P.tour and #P.tour > 0 then
    D.mensaje(P)
    D.tour(P)
  else
    D.coach_fondo(P)
    D.mensaje(P)
    D.coach_marca(P)
  end
end

-- ------------------------------------------------------------------------------------------------ screens
local function fondo_taller()
  grad(0, 0, 480, 236, 0x0C1236, 0x2E3F80)
  for _, f in ipairs(G.flotantes) do
    local y = (f.y0 + t() * f.vy * 60) % 300 - 30
    local x = f.x + math.sin(t() * 1.2 + f.fase) * 12
    gota(f.color, math.floor(x), math.floor(y), {alpha = 0.6})
  end
  rect(0, 236, 480, 84, 0x70482A)
  grad(0, 236, 480, 6, 0xC89458, 0x70482A)
  grad(0, 242, 480, 78, 0x70482A, 0x3E2412)
end

local function candado(x, y)
  rect(x + 9, y + 12, 20, 16, 0x8A7A5E)
  box(x + 11, y + 2, 16, 14, 0x8A7A5E)
  box(x + 12, y + 3, 14, 12, 0x8A7A5E)
  rect(x + 17, y + 18, 4, 6, 0x4A3A22)
end

-- the first screen: the title and the paintings to restore
function D.titulo()
  fondo_taller()
  img("LOGO", 84, 4 + math.floor(1.5 * math.sin(t() * 2))) -- the logo (assets/logo_b.png by the image model, fitted by hand), bobbing a little
  tx_fit(lang.tr("title_tag"), 240, 94, 0xFFF0C8, FB, "center", 440, {outline = 0x1A0E06, shadow = 0x000000})
  for i, o in ipairs(G.obras) do
    local x, y = 12 + (i - 1) * 156, 112
    local libre = U.obra_libre(i)
    local sel = i == G.sel_obra
    local dy = (sel and G.usa_botones) and -math.floor(2 + 2 * math.sin(t() * 6)) or 0
    placa(x, y + dy, 148, 128)
    if sel and G.usa_botones then box(x - 2, y - 2 + dy, 152, 132, DORADO) end
    img("REF_" .. o.id, x + 6, y + 6 + dy, {scale = 0.9})
    if not libre then
      shade(x + 6, y + 6 + dy, 137, 94)
      shade(x + 6, y + 6 + dy, 137, 94)
      candado(x + 55, y + 36 + dy)
    end
    tx_fit(U.titulo_obra(o), x + 74, y + 105 + dy, TINTA, FS, "center", 138)
    tx_fit(libre and U.memo("tl|" .. U.hechos(o) .. "|" .. #o.niveles, function() return lang.tr("title_levels", {n = U.hechos(o), m = #o.niveles}) end) or lang.tr("title_locked"), x + 74, y + 116 + dy,
           libre and (U.hechos(o) == #o.niveles and VERDE_OK or TINTA_SUAVE) or 0x9A8A70, FS, "center", 138)
  end
  tx_fit(lang.tr("title_hint1"), 240, 252, 0xFFFFFF, FS, "center", 460, {shadow = 0x000000})
  tx_fit(lang.tr("title_hint2"), 240, 272, 0xE0C890, FS, "center", 460, {shadow = 0x000000})
end

-- the levels of the chosen painting
function D.niveles()
  fondo_taller()
  rect(82, 8, 316, 220, 0x7A5230)
  box(82, 8, 316, 220, 0xC89458)
  img("REF2_" .. G.obra.id, 88, 14) -- the painting at 2x, dimmed: drawn once into a canvas (main.lua)
  local nombre = U.titulo_obra(G.obra)
  local esc = U.memo("esc|" .. G.obra.id, function() return textw(nombre, {font = FT, scale = 2}) <= 296 and 2 or 1 end) -- the big title when it fits the frame, else the normal one
  tx_fit(nombre, 240, 28 + (esc == 2 and 0 or 16), 0xFFE08A, FT, "center", 296,
         {scale = esc, gradient = 0xE0782A, outline = 0x3A1C08, shadow = 0x000000, shadow_y = 2})
  tx(G.obra.autor, 240, 92, 0xFFF0C8, FB, "center", {outline = 0x1A0E06, shadow = 0x000000})
  local dos = U.memo("dos|" .. G.obra.id, function() -- a title that needs two lines: this painting's cards make room for them (stars and drops move up)
    for _, nv in ipairs(NV()) do
      if textw(U.titulo_nivel(nv), {font = FS}) > 76 then return true end
    end
    return false
  end)
  local sube = dos and 6 or 0
  for i = 1, #NV() do
    local x, y = 30 + (i - 1) * 90, 140
    local libre = U.nivel_libre(i)
    local sel = i == G.sel_titulo
    local dy = (sel and G.usa_botones) and -math.floor(2 + 2 * math.sin(t() * 6)) or 0
    placa(x, y + dy, 82, 94)
    if sel and G.usa_botones then box(x - 2, y - 2 + dy, 86, 98, DORADO) end
    if libre then
      tx(tostring(i), x + 41, y + 2 + dy, TINTA, FT, "center", {scale = 2, shadow = 0xC4A272})
      local n = #NV()[i].objetivos
      for k, o in ipairs(NV()[i].objetivos) do
        gota(o.color, math.floor(x + 41 - n * 7 + (k - 1) * 14 - 1), y + 42 - sube * 5 // 8 + dy, nil, true)
      end
      for e = 1, 3 do estrella(x + 17 + (e - 1) * 24, y + 66 - sube + dy, U.estrellas(G.obra.id, i) >= e, 0.85) end
      if dos then -- up to two lines, centred in the room under the stars, never past the card
        textbox(U.titulo_nivel(NV()[i]), x + 3, y + 72 + dy, 76, 21, {font = FS, color = TINTA, align = "center", valign = "middle"})
      else
        tx_fit(U.titulo_nivel(NV()[i]), x + 41, y + 79 + dy, TINTA, FS, "center", 76)
      end
    else
      tx(tostring(i), x + 41, y + 6 + dy, 0xB8AA90, FT, "center", {scale = 2})
      candado(x + 22, y + 38 + dy)
    end
  end
  local b = {16, 274, 86, 30}
  grad(b[1], b[2], b[3], b[4], 0xE8D4A0, 0xC8AE76)
  box(b[1], b[2], b[3], b[4], 0x7A5230)
  tx_fit(lang.tr("levels_back"), b[1] + b[3] // 2, b[2] + 9, TINTA, FB, "center", b[3] - 8)
  tx_fit(lang.tr("levels_tap"), 240, 250, 0xFFFFFF, FB, "center", 400, {shadow = 0x000000})
end

function D.intro(P)
  D.juego(P)
  shade(0, 0, 480, 320)
  local nivel = P.s.nivel
  local n = #P.s.obj
  local nota = U.nota_nivel(nivel)
  local _, nota_h = textw(nota or "", {font = FS, width = 360 - 40})
  local nota_res = nota and math.max(38, nota_h + 8) or 0
  local w, h = 360, 88 + n * 20 + nota_res
  local k = U.sale(math.min(1, G.t_estado / 12))
  local x, y = 60, math.floor((320 - h) // 2 + 40 * (1 - k))
  placa(x, y, w, h)
  tx_fit(lang.tr("intro_level", {n = P.n}), 240, y + 9, TINTA_SUAVE, FB, "center", w - 20)
  tx_fit(U.titulo_nivel(nivel), 240, y + 23, TINTA, FT, "center", w - 20, {shadow = 0xC4A272})
  tx_fit(lang.tr("intro_goal"), 240, y + 50, TINTA, FS, "center", w - 20)
  for i, o in ipairs(P.s.obj) do
    local ry = y + 64 + (i - 1) * 20
    local rb = U.rebote(math.min(1, math.max(0, (G.t_estado - 6 - i * 4) / 12)))
    gota(o.color, x + 24, ry + math.floor((1 - rb) * 14), nil, true)
    local mezcla = R.RECETAS[o.color] and P.s.recetas_ok[o.color]
    local texto = lang.tr(mezcla and "intro_line_mix" or "intro_line",
                          {u = o.unidades, color = NOMBRE[o.color], region = U.region(G.obra, o.region)})
    tx_fit(texto, x + 44, ry + 2, TINTA, FS, "left", w - 44 - 12)
  end
  local yy = y + 64 + n * 20 + 2
  if nota then
    tx(nota, 240, yy, 0x6A4A2A, FS, "center", {width = w - 40})
    yy = yy + nota_res
  end
  tx_fit(lang.tr("intro_moves", {n = nivel.movimientos}), 240, y + h - 24, TINTA_SUAVE, FS, "center", w - 20)
  if G.t_estado % 60 < 40 then tx_fit(lang.tr("intro_start"), 240, y + h - 12, VERDE_OK, FS, "center", w - 20) end
end

function D.fin(P)
  D.juego(P)
  shade(0, 0, 480, 320)
  local res = P.resultado
  local k = U.rebote(math.min(1, G.t_estado / 18))
  local x, y, w, h = 100, math.floor(330 - 250 * k), 280, 150
  placa(x, y, w, h)
  tx_fit(lang.tr(res.gana and "fin_won" or "fin_lost"), 240, y + 10, res.gana and VERDE_OK or ROJO_NO, FT, "center", w - 16,
         {shadow = 0xC4A272})
  if res.gana then
    for e = 1, 3 do
      local ts = 18 + e * 12
      local ke = U.rebote(math.min(1, math.max(0, (G.t_estado - ts) / 14)))
      if G.t_estado >= ts then estrella(180 + (e - 1) * 60, y + 56, e <= res.estrellas, math.max(0.1, ke)) end
    end
    tx_fit(lang.tr("fin_score", {p = res.puntos, m = res.mov}), 240, y + 80, TINTA, FS, "center", w - 16)
    if not NV()[P.n + 1] then
      local siguiente = G.hay_siguiente()
      tx_fit(lang.tr(siguiente and "fin_newwork" or "fin_allwork"), 240, y + 94, VERDE_OK, FS, "center", w - 16)
    end
  else
    tx_fit(lang.tr("fin_lost1"), 240, y + 52, TINTA, FB, "center", w - 16)
    tx_fit(lang.tr("fin_lost2"), 240, y + 72, TINTA_SUAVE, FS, "center", w - 16)
  end
  G.botones_fin = {}
  local opciones = {}
  if res.gana and G.hay_siguiente() then opciones[#opciones + 1] = {lang.tr(NV()[P.n + 1] and "btn_next" or "btn_newwork"), G.ir_siguiente} end
  opciones[#opciones + 1] = {lang.tr("btn_retry"), G.ir_repetir}
  opciones[#opciones + 1] = {lang.tr("btn_menu"), G.ir_titulo}
  local bw = 80
  local x0 = 240 - (#opciones * (bw + 8) - 8) // 2
  for i, o in ipairs(opciones) do
    local bx, by = x0 + (i - 1) * (bw + 8), y + h - 40
    grad(bx, by, bw, 28, 0xE8D4A0, 0xC8AE76)
    box(bx, by, bw, 28, 0x7A5230)
    tx_fit(o[1], bx + bw // 2, by + 9, TINTA, FB, "center", bw - 8)
    G.botones_fin[i] = {bx, by, bw, 28, o[2]}
  end
end

-- the achievement just earned: a plaque slides down from the top edge, stays, and goes back up
D.LOGRO_DUR = 170
function D.logro()
  local l = G.logros[1]
  if not l then return end
  local nombre = lang.tr("ach_" .. l.id)
  local w = math.max(150, math.min(300, textw(nombre, {font = FB}) + 70))
  local h = 36
  local k = l.t < 14 and U.sale(l.t / 14) or (l.t > D.LOGRO_DUR - 14 and U.sale((D.LOGRO_DUR - l.t) / 14) or 1)
  local x, y = 240 - w // 2, math.floor(-h + (h + 6) * k)
  placa(x, y, w, h)
  estrella(x + 20, y + h // 2 + 1, true, 0.8)
  tx_fit(lang.tr("ach_new"), x + 38, y + 6, 0x9A5A10, FS, "left", w - 46, {slide = true})
  tx_fit(nombre, x + 38, y + 18, TINTA, FB, "left", w - 46, {slide = true})
end

return D
