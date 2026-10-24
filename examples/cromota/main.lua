-- CROMOTA: a touch-first drop puzzle that restores a painting. Rules: reglas.lua / juego.lua. Drawing: dibujo.lua.
-- This file is the flow: screens, input, and the animation of what a swap returned (pasos).
local R = require("reglas")
local J = require("juego")
local OBRAS = require("obras")
local L = require("layout")
local U = require("util")
local lang = require("lang")
local D = require("dibujo")
local Gd = require("guia")
local S = require("sonido")
local juice = require("juice")
local particles = require("particles")
local transition = require("transition")

local C, CELDA = U.C, U.CELDA
local OB_W, OB_H = L.obra_w, L.obra_h
local RGB, NOMBRE, MIN = U.RGB, U.NOMBRE, U.MIN
local dentro = U.dentro

G = {visto = {}, logros = {}, estado = "titulo", t_estado = 0, usa_botones = false, sel_titulo = 1, progreso = {estrellas = {}}, flotantes = {},
     botones_fin = {}, obras = OBRAS, obra = OBRAS[1]} -- shared with dibujo.lua; global so tests can reach it
local P

local function NV() return G.obra.niveles end
local function DATOS() return L.obras[G.obra.id] end -- the painting's regions and hit grid

-- ----------------------------------------------------------------------------------------------- canvases
local function lienzo_ref() -- the finished painting of each work, drawn once
  for _, o in ipairs(OBRAS) do
    canvas("REF_" .. o.id, OB_W, OB_H)
    target("REF_" .. o.id)
    for i = 1, #L.obras[o.id].regiones do img("OBRA_" .. o.id .. "_" .. i, 0, 0) end
    target()
    canvas("REF2_" .. o.id, OB_W * 2, OB_H * 2) -- the level-select backdrop: the painting at 2x and dimmed, once
    target("REF2_" .. o.id)
    img("REF_" .. o.id, 0, 0, {scale = 2})
    shade(0, 0, OB_W * 2, OB_H * 2)
    target()
  end
end

local function pintar_region(k, hasta)
  target("REST")
  clip(0, 0, hasta or OB_W, OB_H)
  img("OBRA_" .. G.obra.id .. "_" .. k, 0, 0)
  clip()
  target()
end

-- ----------------------------------------------------------------------------------------------- level setup
if not achieve then achieve = function() end end

-- an achievement earned for the first time: it is granted and a banner (dibujo.lua, D.logro) tells which
local function logro(id)
  if achieve(id) then G.logros[#G.logros + 1] = {id = id, t = 0} end
end

local function toast(texto, color, dur)
  dur = dur or 100
  P.msg = {texto = texto, color = color or 0xFFFFFF, t = dur, dur = dur}
end

local function sincroniza() P.shown = U.copia_plana(P.s.stock) end

local function ir(fn)
  if transition.active() then return end
  transition.go("fade", 0.32, {on_mid = fn, color = 0x0A0A14})
end

local function poner_menu()
  if not menuitem then return end -- older consoles have no pause-menu items
  menuitem()
  menuitem(lang.tr("menu_retry"), function()
    if P and G.estado ~= "titulo" and G.estado ~= "niveles" then local n = P.n; ir(function() G.nuevo_nivel(n) end) end
  end)
  menuitem(lang.tr("how_item"), function() -- the explanations of this level, again
    if P and G.estado == "juego" and not P.tour and #P.cola == 0 then
      P.tour = Gd.pasos(P, true)
      for _, p in ipairs(P.tour) do p.repetir = true end
      Gd.entrar(P, P.tour[1])
    end
  end)
  menuitem(lang.tr(S.activa() and "menu_music_on" or "menu_music_off"), function() S.musica(not S.activa()); poner_menu() end)
end

local function nuevo_nivel(n)
  local nivel = NV()[n]
  local s = J.nuevo(nivel)
  P = {
    n = n, s = s, V = U.copia(s.b.g), D = {}, land = {}, cola = {}, sel = nil, arrastre = nil, cursor = {4, 4},
    msg = nil, barrido = nil, combo = nil, quieto = 0, pista = nil, ayuda = nivel.ayuda and true or false, fin_t = 0,
    resultado = nil, vuelos = {}, popups = {}, rebote = {}, shown = U.copia_plana(s.stock), mov_prev = s.mov,
    mov_t = 0, tintar = nil, brillo = 0, busy = false, tour = nil, tour_hecho = false, tour_pend = nil,
  }
  for r = 1, L.filas do P.D[r] = {} end
  P.regc = {} -- where each region sits in the restored painting (screen pixels), for the tutorial's arrow
  local suma = {}
  for gy, fila in ipairs(DATOS().rejilla) do
    for gx = 1, #fila do
      local k = tonumber(fila:sub(gx, gx))
      suma[k] = suma[k] or {0, 0, 0}
      suma[k][1], suma[k][2], suma[k][3] = suma[k][1] + gx, suma[k][2] + gy, suma[k][3] + 1
    end
  end
  for k, v in pairs(suma) do
    P.regc[k] = {C.rest[1] + math.floor(v[1] / v[3] * 4) - 2, C.rest[2] + math.floor(v[2] / v[3] * 4) - 2}
  end
  G.P, G.fx = P, particles.new()
  canvas("REST", "OBRA_" .. G.obra.id .. "_GRIS")
  local usadas = {}
  for _, o in ipairs(s.obj) do usadas[o.region] = true end
  for k = 1, #DATOS().regiones do
    if not usadas[k] then pintar_region(k) end
  end
  poner_menu()
  G.estado, G.t_estado = "intro", 0
end

-- the drops fall into the board when the level starts
local function entrada()
  for r = 1, L.filas do
    for c = 1, L.cols do
      P.D[r][c] = -(CELDA * L.filas + 30 + (c - 1) * 9 + (L.filas - r) * 7)
    end
  end
  P.cola[#P.cola + 1] = {tipo = "caer", movs = {}}
end

-- ----------------------------------------------------------------------------------------------- animation
local function centro(r, c)
  return C.celdas[1] + (c - 1) * CELDA + CELDA // 2, C.celdas[2] + (r - 1) * CELDA + CELDA // 2
end

local function aplicar_caida(movs)
  for _, m in ipairs(movs) do
    if m.de >= 1 then P.V[m.de][m.c] = nil end
  end
  for _, m in ipairs(movs) do
    P.V[m.a][m.c] = m.p
    P.D[m.a][m.c] = (m.de - m.a) * CELDA
  end
end

local function cae_pendiente()
  for r = 1, L.filas do
    for c = 1, L.cols do
      if (P.D[r][c] or 0) < 0 then return true end
    end
  end
  return false
end

local function encola(fase) P.cola[#P.cola + 1] = fase end

local function explosion(q)
  local n = math.max(2, math.min(8, 90 // math.max(#q, 1))) -- about 90 particles a burst however many pieces go (each costs Lua time)
  for _, e in ipairs(q) do
    local x, y = centro(e[1], e[2])
    local col = RGB[e[3]] or 0xDDBB44
    G.fx:burst(x, y, n, {speed = 2.6, spread = 360, gravity = 0.09, life = 26, size = 3, shape = "square",
                         colours = {U.clara(col), col, col, 0x20202A}})
  end
end

-- the pigment of a burst group flies to its icon in the stock
local function vuelan(f)
  local retraso = 0
  for _, g in ipairs(f.grupos) do
    local cr, cc, n = 0, 0, 0
    for _, cell in ipairs(g.celdas) do cr, cc, n = cr + cell[1], cc + cell[2], n + 1 end
    local x, y = centro(cr / n, cc / n)
    local unidades = n + (f.combo >= 2 and 1 or 0)
    P.popups[#P.popups + 1] = {x = x, y = y - 6, texto = "+" .. unidades, color = U.clara(RGB[g.color]), t = 0}
    local tx_, ty_ = U.pos_reserva(P.s.nivel, g.color)
    for i, cell in ipairs(g.celdas) do
      local x0, y0 = centro(cell[1], cell[2])
      P.vuelos[#P.vuelos + 1] = {x0 = x0, y0 = y0, x1 = tx_ + 6, y1 = ty_ + 6, t = -(retraso + i * 2), dur = 24, color = g.color}
    end
    retraso = retraso + 3
  end
end

local function empezar_fase(f)
  if f.tipo == "pop" then
    if f.crea then -- a group of 4 or 5: one of its pieces stays, as a brush or a tube
      P.V[f.crea[1]][f.crea[2]] = f.crea[3]
      P.land[f.crea[1] * 100 + f.crea[2]] = 10
      S.crea()
      local x, y = centro(f.crea[1], f.crea[2])
      G.fx:burst(x, y, 10, {speed = 2, spread = 360, life = 24, size = 2, shape = "square", colours = {0xFFFFFF, 0xFFE08A, 0xF2C230}})
    end
    if f.tubo then
      S.tubo()
      juice.trauma(0.5)
      local x, y = centro(f.tubo.r, f.tubo.c)
      G.fx:burst(x, y, 14, {speed = 3, spread = 360, life = 24, size = 3, shape = "square",
                            colours = {0xFFFFFF, U.clara(RGB[f.tubo.color]), RGB[f.tubo.color]}})
    end
    if f.linea then
      P.rayo = {t = 0, horizontal = f.linea.horizontal, idx = f.linea.idx}
      S.pincel()
      juice.trauma(0.4)
    end
    f.set = {}
    for _, e in ipairs(f.quitados) do f.set[e[1] * 100 + e[2]] = true end
    explosion(f.quitados)
    vuelan(f)
    local visto = {}
    for _, g in ipairs(f.grupos) do
      if not visto[g.color] then visto[g.color] = true; S.grupo(g.color, f.combo) end
    end
    if f.combo >= 2 then juice.trauma(math.min(0.18 + 0.14 * f.combo, 0.65)) else juice.trauma(0.08) end
  elseif f.tipo == "caer" then
    aplicar_caida(f.movs)
  elseif f.tipo == "swap" and not f.vuelta then
    S.cambia()
  end
end

local function terminar_fase(f)
  if f.tipo == "swap" then
    local a, b = P.V[f.r1][f.c1], P.V[f.r2][f.c2]
    P.V[f.r1][f.c1], P.V[f.r2][f.c2] = b, a
  elseif f.tipo == "pop" then
    for _, e in ipairs(f.quitados) do P.V[e[1]][e[2]] = nil end
  elseif f.tipo == "barajar" then
    P.V = U.copia(P.s.b.g)
  end
end

local function actualiza_vuelos()
  for i = #P.vuelos, 1, -1 do
    local v = P.vuelos[i]
    v.t = v.t + 1
    if v.t >= v.dur then
      local k = v.color
      P.shown[k] = math.min(P.s.stock[k] or 0, (P.shown[k] or 0) + 1)
      P.rebote[k] = 14
      local x, y = v.x1, v.y1
      G.fx:burst(x, y, 2, {speed = 1, spread = 360, life = 10, size = 2, shape = "square", colours = {0xFFFFFF, U.clara(RGB[k])}})
      table.remove(P.vuelos, i)
    end
  end
  for k, v in pairs(P.rebote) do
    v = v - 1
    P.rebote[k] = v > 0 and v or nil
  end
end

local function actualiza_cola()
  local f = P.cola[1]
  if not f then return end
  if not f.t then f.t = 0; empezar_fase(f) end
  f.t = f.t + 1
  if f.tipo == "caer" then
    local v = f.t * 0.9
    for r = 1, L.filas do
      for c = 1, L.cols do
        local d = P.D[r][c] or 0
        if d < 0 then
          local nd = math.min(0, d + 3 + v)
          P.D[r][c] = nd
          if nd == 0 then P.land[r * 100 + c] = 8 end
        end
      end
    end
    if not cae_pendiente() then terminar_fase(f); table.remove(P.cola, 1) end
  elseif f.t >= f.dur then
    terminar_fase(f)
    table.remove(P.cola, 1)
  end
  if #P.cola == 0 then P.V = U.copia(P.s.b.g) end -- the view meets the truth
end

local function actualiza_efectos()
  for k, v in pairs(P.land) do
    v = v - 1
    P.land[k] = v > 0 and v or nil
  end
  for i = #P.popups, 1, -1 do
    local p = P.popups[i]
    p.t = p.t + 1
    if p.t > 42 then table.remove(P.popups, i) end
  end
  if P.tintar then
    P.tintar = P.tintar - 1
    if P.tintar <= 0 then P.tintar = nil end
  end
  if P.brillo > 0 then P.brillo = P.brillo - 1 end
  if P.rayo then
    P.rayo.t = P.rayo.t + 1
    if P.rayo.t > 16 then P.rayo = nil end
  end
  if P.s.mov ~= P.mov_prev then P.mov_prev, P.mov_t = P.s.mov, 10 end
  if P.mov_t > 0 then P.mov_t = P.mov_t - 1 end
end

local function ocupado() return #P.cola > 0 or P.barrido ~= nil or #P.vuelos > 0 end

-- ----------------------------------------------------------------------------------------------- actions
local function intenta_cambio(r1, c1, r2, c2)
  if ocupado() or P.s.fin then return end
  local ok, info = J.cambiar(P.s, r1, c1, r2, c2)
  P.quieto, P.pista = 0, nil
  if ok then
    P.sel = nil
    encola({tipo = "swap", r1 = r1, c1 = c1, r2 = r2, c2 = c2, dur = 9})
    for k, paso in ipairs(info.pasos) do
      if paso.linea or paso.tubo then logro("pieza_especial") end
      encola({tipo = "pop", quitados = paso.quitados, grupos = paso.grupos, combo = k, dur = (paso.linea or paso.tubo) and 16 or 12,
              crea = paso.crea, linea = paso.linea, tubo = paso.tubo})
      if paso.crea then P.tour_pend = P.tour_pend or paso.crea[3] end
      encola({tipo = "caer", movs = paso.caidas})
    end
    if info.barajado then
      encola({tipo = "barajar", dur = 20})
      toast(lang.tr("msg_shuffled"), 0xFFE08A)
    end
    if info.combo >= 2 then
      P.combo = {n = info.combo, extra = info.mov_extra, t = 110}
      if info.combo >= 3 then logro("combo") end
      P.tour_pend = P.tour_pend or "combo"
    end
  elseif info.razon == "sin_grupo" then
    encola({tipo = "swap", r1 = r1, c1 = c1, r2 = r2, c2 = c2, dur = 7})
    encola({tipo = "swap", r1 = r1, c1 = c1, r2 = r2, c2 = c2, dur = 7, vuelta = true})
    S.rechazo()
    toast(lang.tr("msg_nogroup"), 0xFFB0A0, 70)
    P.sel = nil
  elseif info.razon == "sin_movs" then
    toast(lang.tr("msg_nomoves"), 0xFFE08A)
  end
end

local function cicla_receta()
  local n = #P.s.recetas
  if n < 2 then return end
  P.s.receta = P.s.receta % n + 1
  S.selecciona()
end

local function mezclar()
  if P.s.fin then return end
  local s = P.s
  if #s.recetas == 0 then toast(lang.tr("msg_nomix"), 0xFFFFFF, 70); return end
  local ok, razon = J.mezclar(s, s.receta)
  if ok then
    S.mezcla()
    logro("alquimista")
    sincroniza()
    P.rebote[razon] = 14
    toast(lang.tr("msg_mixed", {color = NOMBRE[razon]}), 0xFFFFFF, 70)
    local x, y = C.res[1] + C.res[3] // 2, C.res[2] + 16
    G.fx:burst(x, y, 14, {speed = 2.2, spread = 360, gravity = 0.05, life = 26, size = 3, shape = "square",
                          colours = {U.clara(RGB[razon]), RGB[razon], 0xFFFFFF}})
  elseif razon == "faltan" then
    S.error()
    local _, falta = J.puede_mezclar(s, s.receta)
    local partes = {}
    for _, k in ipairs(U.ordenados(falta)) do partes[#partes + 1] = falta[k] .. " " .. MIN[k] end
    toast(lang.tr("msg_missing", {parts = table.concat(partes, ", ")}), 0xFFB0A0)
  elseif razon == "lleno" then
    S.error()
    toast(lang.tr("msg_stockfull", {color = MIN[s.recetas[s.receta]]}), 0xFFE08A)
  end
  P.quieto = 0
end

local function carga(n)
  if ocupado() or P.s.fin then return end
  local ok, razon, falta = J.cargar(P.s, n)
  local o = P.s.obj[n]
  if ok then
    S.carga()
    sincroniza()
    P.tintar = 10
    toast(lang.tr("msg_brush", {color = NOMBRE[o.color], region = U.region(G.obra, o.region)}), 0xFFFFFF, 90)
    local x, y = C.pincel[1] + 30, C.pincel[2] + 40
    G.fx:burst(x, y, 8, {speed = 1.6, spread = 200, angle = -90, gravity = 0.05, life = 20, size = 2, shape = "square",
                         colours = {U.clara(RGB[o.color]), RGB[o.color]}})
  elseif razon == "faltan" then
    S.error()
    toast(lang.tr("msg_need", {n = falta, color = MIN[o.color]}), 0xFFB0A0)
  elseif razon == "hecho" then
    toast(lang.tr("msg_zonedone"), 0xFFFFFF, 60)
  end
  P.quieto = 0
end

local function pinta(region)
  if ocupado() or P.s.fin then return end
  local brush = P.s.brush
  local ok, razon = J.pintar(P.s, region)
  if ok then
    S.pinta()
    P.barrido = {k = region, x = 0, color = RGB[brush.color]}
  elseif razon == "sin_carga" then
    S.error()
    toast(lang.tr("msg_brushempty"), 0xFFE08A)
  elseif razon == "zona" then
    S.error()
    toast(lang.tr("msg_wrongzone", {color = MIN[brush.color]}), 0xFFB0A0)
  end
  P.quieto = 0
end

local function actualiza_barrido()
  local b = P.barrido
  if not b then return end
  b.x = b.x + 7
  local x = C.rest[1] + math.min(b.x, OB_W)
  for _ = 1, 2 do
    G.fx:burst(x, C.rest[2] + math.random(0, OB_H), 1, {speed = 1.4, spread = 360, gravity = 0.04, life = 20, size = 2,
                                                         shape = "square", colours = {0xFFFFFF, U.clara(b.color), b.color}})
  end
  if b.x >= OB_W + 8 then
    P.barrido = nil
    P.brillo = 24
    for _ = 1, 16 do
      G.fx:burst(C.rest[1] + math.random(0, OB_W), C.rest[2] + math.random(0, OB_H), 1,
                 {speed = 0.8, spread = 360, gravity = -0.02, life = 30, size = 2, shape = "square",
                  colours = {0xFFFFFF, 0xFFE08A, b.color}})
    end
    if not P.s.fin then toast(lang.tr("msg_zoneok"), 0xA8F0A0, 70) end
  end
end

-- ----------------------------------------------------------------------------------------------- input
local MARGEN_TABLERO = 6 -- a finger that lands this close outside the board still picks the nearest cell

local function celda_en(x, y, margen)
  local cx, cy, cw, ch = table.unpack(C.celdas)
  margen = margen or 0
  if x < cx - margen or y < cy - margen or x >= cx + cw + margen or y >= cy + ch + margen then return nil end
  x, y = math.max(cx, math.min(cx + cw - 1, x)), math.max(cy, math.min(cy + ch - 1, y)) -- snap to the nearest cell
  return (y - cy) // CELDA + 1, (x - cx) // CELDA + 1
end

local function region_en(x, y)
  local gx, gy = (x - C.rest[1]) // 4 + 1, (y - C.rest[2]) // 4 + 1
  local fila = DATOS().rejilla[gy]
  if not fila then return nil end
  return tonumber(fila:sub(gx, gx))
end

local function cerca(x, y, caja, margen)
  return dentro(x, y, {caja[1] - margen, caja[2] - margen, caja[3] + 2 * margen, caja[4] + 2 * margen})
end

local function toca(x, y)
  G.usa_botones = false
  if cerca(x, y, U.BTN_AYUDA, 10) then
    P.ayuda = not P.ayuda
    S.selecciona()
    return
  end
  local r, c = celda_en(x, y, MARGEN_TABLERO)
  if r then
    S.selecciona()
    local s = P.sel
    if s and math.abs(s[1] - r) + math.abs(s[2] - c) == 1 then
      intenta_cambio(s[1], s[2], r, c)
      P.arrastre = nil
    else
      P.sel = {r, c}
      P.arrastre = {r, c, x, y}
    end
    return
  end
  for i = 1, #P.s.obj do
    if cerca(x, y, L.slots_obj[i], 1) then carga(i); return end
  end
  if cerca(x, y, C.res, 6) then mezclar(); return end
  if cerca(x, y, C.ing_a, 4) or cerca(x, y, C.ing_b, 4) or cerca(x, y, C.mezcla_titulo, 6) then cicla_receta(); return end
  if cerca(x, y, C.pincel, 3) then
    pinta(P.s.brush and P.s.obj[P.s.brush.obj].region or nil)
    return
  end
  if dentro(x, y, C.rest) then pinta(region_en(x, y)) end
end

local UMBRAL_ARRASTRE = 7 -- px of finger travel that make a swipe

local function arrastra(x, y)
  local a = P.arrastre
  if not a or ocupado() then return end
  local dx, dy = x - a[3], y - a[4]
  if math.abs(dx) < UMBRAL_ARRASTRE and math.abs(dy) < UMBRAL_ARRASTRE then return end
  local r2, c2 = a[1], a[2]
  if math.abs(dx) > math.abs(dy) then c2 = c2 + (dx > 0 and 1 or -1) else r2 = r2 + (dy > 0 and 1 or -1) end
  P.arrastre = nil
  if P.V[r2] and P.V[r2][c2] ~= nil then intenta_cambio(a[1], a[2], r2, c2) end
end

local function botones()
  local d = {up = {-1, 0}, down = {1, 0}, left = {0, -1}, right = {0, 1}}
  for nombre, v in pairs(d) do
    if btnp(nombre, 20, 6) then
      G.usa_botones = true
      local cu = P.cursor
      if P.sel then
        intenta_cambio(P.sel[1], P.sel[2], P.sel[1] + v[1], P.sel[2] + v[2])
        P.sel = nil
      else
        cu[1] = math.max(1, math.min(L.filas, cu[1] + v[1]))
        cu[2] = math.max(1, math.min(L.cols, cu[2] + v[2]))
      end
    end
  end
  if btnp("a") then
    G.usa_botones = true
    S.selecciona()
    if P.sel then P.sel = nil else P.sel = {P.cursor[1], P.cursor[2]} end
  end
  if btnp("b") then
    G.usa_botones = true
    if P.sel then
      P.sel = nil
    else
      local s = P.s
      local n = #s.recetas
      for _ = 1, n do
        if J.puede_mezclar(s, s.receta) then break end
        s.receta = s.receta % n + 1
      end
      mezclar()
    end
  end
  if btnp("c") then -- one button for the brush: paint if loaded, else load the next objective that can be paid
    G.usa_botones = true
    local s = P.s
    if s.brush then
      pinta(s.obj[s.brush.obj].region)
    else
      for i, o in ipairs(s.obj) do
        if not o.hecho and (s.stock[o.color] or 0) >= o.unidades then carga(i); return end
      end
      toast(lang.tr("msg_nopigment"), 0xFFE08A)
    end
  end
end

-- ----------------------------------------------------------------------------------------------- play flow
local function pista()
  if P.pista or ocupado() or P.s.fin or P.s.mov <= 0 then return end
  local j = R.jugadas(P.s.b)[1]
  if j then P.pista = j end
end

local function confeti()
  local cols = {0xF2C230, 0xD8342C, 0x2A5DB0, 0x3E9A48, 0xFFFFFF, 0xEE7A22}
  juice.every(0.1, function()
    G.fx:burst(math.random(20, 460), -6, 3, {speed = 2.4, angle = 90, spread = 70, gravity = 0.06, life = 110, size = 3,
                                              shape = "square", colours = {cols[math.random(#cols)], cols[math.random(#cols)]}})
  end, 16)
end

local function termina_nivel()
  local s = P.s
  local gana = s.fin == "gana"
  local e = J.estrellas(s)
  P.resultado = {gana = gana, estrellas = e, puntos = s.puntos, mov = s.mov}
  if gana then
    S.gana()
    confeti()
    local id = G.obra.id
    G.progreso.estrellas[id] = G.progreso.estrellas[id] or {}
    G.progreso.estrellas[id][P.n] = math.max(G.progreso.estrellas[id][P.n] or 0, e)
    local guardar = {}
    for _, o in ipairs(OBRAS) do -- dense lists per painting: store() refuses sparse tables
      guardar[o.id] = {}
      for i = 1, #o.niveles do guardar[o.id][i] = U.estrellas(o.id, i) end
    end
    store("progreso", {e = guardar})
    if G.obra == OBRAS[1] and P.n == 1 then logro("primer_trazo") end
    if e == 3 then logro("tres_estrellas") end
    if U.hechos(G.obra) == #NV() then logro("obra_maestra") end
    local todos = true
    for _, o in ipairs(OBRAS) do if U.hechos(o) < #o.niveles then todos = false end end
    if todos then logro("ultimo_trazo") end
  else
    S.pierde()
  end
  G.estado, G.t_estado = "fin", 0
end

local function actualiza_juego()
  actualiza_cola()
  actualiza_vuelos()
  actualiza_barrido()
  actualiza_efectos()
  G.fx:update()
  if P.msg then
    P.msg.t = P.msg.t - 1
    if P.msg.t <= 0 then P.msg = nil end
  end
  if P.combo then
    P.combo.t = P.combo.t - 1
    if P.combo.t <= 0 then P.combo = nil end
  end
  P.busy = ocupado()
  if P.busy then P.tuto_j = nil end
  if not P.busy and #P.cola == 0 then sincroniza() end
  if transition.active() then return end
  local px, py, down, tapped, released = pen()
  if not P.busy and not P.tour_hecho then -- the board has settled for the first time: explain what is new in this level
    P.tour_hecho = true
    P.tour = Gd.pasos(P)
    if #P.tour == 0 then P.tour = nil else Gd.entrar(P, P.tour[1]) end
  elseif not P.busy and P.tour_pend then
    local pasos = (Gd[P.tour_pend] or Gd.combo)(P)
    P.tour_pend = nil
    if #pasos > 0 then P.tour = pasos end
  end
  if P.tour and #P.tour > 0 then
    if (tapped or btnp("a") or btnp("b") or btnp("c")) and G.t_estado > 10 then
      local paso = table.remove(P.tour, 1)
      if not paso.repetir then G.visto[paso.id] = true; store("visto", G.visto) end
      S.selecciona()
      if #P.tour == 0 then P.tour = nil else Gd.entrar(P, P.tour[1]) end
      G.t_estado = 0
    end
    return
  end
  if not P.busy then
    if tapped then toca(px, py) end
    if down and P.arrastre then arrastra(px, py) end
    botones()
  elseif tapped then
    G.usa_botones = false
  end
  if released then P.arrastre = nil end
  P.dedo = (down and P.arrastre and not P.busy) and {px, py} or nil -- where the held drop is drawn (dibujo.lua)
  if P.sel and P.V[P.sel[1]] and P.V[P.sel[1]][P.sel[2]] == nil then P.sel = nil end
  P.quieto = P.quieto + 1
  if P.quieto > 360 then pista() end
  if P.s.fin and not ocupado() then
    P.fin_t = P.fin_t + 1
    if P.fin_t > 50 then termina_nivel() end
  end
end

-- ----------------------------------------------------------------------------------------------- screens
local function empieza(i)
  if U.nivel_libre(i) then ir(function() nuevo_nivel(i) end) else S.error() end
end

local function caja_nivel(i) return {30 + (i - 1) * 90, 140, 82, 94} end
local function caja_obra(i) return {12 + (i - 1) * 156, 112, 148, 128} end
local CAJA_VOLVER = {16, 274, 86, 30}

local function elige_obra(i)
  if U.obra_libre(i) then
    G.obra, G.sel_titulo = OBRAS[i], 1
    ir(function() G.estado, G.t_estado = "niveles", 0 end)
  else
    S.error()
  end
end

local function actualiza_titulo()
  if transition.active() then return end
  local px, py, _, tapped = pen()
  if tapped then
    G.usa_botones = false
    for i = 1, #OBRAS do
      if dentro(px, py, caja_obra(i)) then G.sel_obra = i; elige_obra(i) end
    end
  end
  if btnp("left") then G.usa_botones = true; G.sel_obra = math.max(1, G.sel_obra - 1) end
  if btnp("right") then G.usa_botones = true; G.sel_obra = math.min(#OBRAS, G.sel_obra + 1) end
  if btnp("a") then G.usa_botones = true; elige_obra(G.sel_obra) end
end

local function actualiza_niveles()
  if transition.active() then return end
  local px, py, _, tapped = pen()
  if tapped then
    G.usa_botones = false
    for i = 1, #NV() do
      if dentro(px, py, caja_nivel(i)) then G.sel_titulo = i; empieza(i) end
    end
    if dentro(px, py, CAJA_VOLVER) then G.ir_titulo() end
  end
  if btnp("left") then G.usa_botones = true; G.sel_titulo = math.max(1, G.sel_titulo - 1) end
  if btnp("right") then G.usa_botones = true; G.sel_titulo = math.min(#NV(), G.sel_titulo + 1) end
  if btnp("a") then G.usa_botones = true; empieza(G.sel_titulo) end
  if btnp("b") then G.ir_titulo() end
end

local function actualiza_intro()
  if transition.active() then return end
  local _, _, _, tapped = pen()
  if G.t_estado > 24 and (tapped or btnp("a") or btnp("b") or btnp("c")) then
    S.carga()
    G.estado, G.t_estado = "juego", 0
    entrada()
  end
end

local function actualiza_fin()
  if transition.active() or G.t_estado < 30 then return end
  local px, py, _, tapped = pen()
  if tapped then
    for _, b in ipairs(G.botones_fin) do
      if dentro(px, py, b) then b[5](); return end
    end
  end
  if btnp("a") and G.botones_fin[1] then G.botones_fin[1][5]() end
  if btnp("b") then G.ir_titulo() end
end

G.ir_siguiente = function()
  local n = P.n + 1
  if NV()[n] then ir(function() nuevo_nivel(n) end); return end
  for i, o in ipairs(OBRAS) do -- the last level of a painting: on to the next one, when it is open
    if o == G.obra and OBRAS[i + 1] and U.obra_libre(i + 1) then
      ir(function() G.obra = OBRAS[i + 1]; nuevo_nivel(1) end)
      return
    end
  end
  G.ir_titulo()
end
G.ir_repetir = function() local n = P.n; ir(function() nuevo_nivel(n) end) end
G.ir_titulo = function() ir(function() G.estado, G.t_estado = (G.estado == "niveles") and "titulo" or "niveles", 0 end) end
G.toca = function(x, y) toca(x, y) end -- tests tap at computed places
G.nuevo_nivel = nuevo_nivel
G.hay_siguiente = function()
  if NV()[P.n + 1] then return true end
  for i, o in ipairs(OBRAS) do
    if o == G.obra then return OBRAS[i + 1] ~= nil and U.obra_libre(i + 1) end
  end
  return false
end
G.avanza = function() -- tests: start a level from its card, press the first button of a result
  if G.estado == "intro" then G.t_estado = 99; G.estado = "juego"; G.t_estado = 0; entrada()
  elseif G.estado == "fin" then
    if P.resultado.gana and G.hay_siguiente() then G.ir_siguiente() else G.ir_repetir() end
  end
end

-- ----------------------------------------------------------------------------------------------- callbacks
function _resume() lang.load() end

function _init()
  lang.load()
  G.visto = stored("visto", {})
  local guardado = stored("progreso", {})
  G.progreso = {estrellas = {}}
  local e = guardado.e or guardado.estrellas or {}
  if type(e[1]) == "number" then e = {noche = e} end -- the first version saved one list: it was the first painting
  for id, lista in pairs(e) do
    G.progreso.estrellas[id] = {}
    for i, v in ipairs(lista) do G.progreso.estrellas[id][i] = v end
  end
  lienzo_ref()
  G.estado, G.sel_titulo, G.sel_obra = "titulo", 1, 1
  G.fx = particles.new()
  G.flotantes = {}
  local claves = {"rojo", "amarillo", "azul", "blanco", "naranja", "verde", "violeta", "celeste"}
  for i = 1, 14 do
    G.flotantes[i] = {x = (i % 2 == 0) and math.random(8, 52) or math.random(412, 448), y0 = math.random(0, 300), vy = 0.18 + math.random() * 0.3,
                      fase = math.random() * 6, color = claves[(i - 1) % #claves + 1]}
  end
  S.musica(true)
end

function _update()
  S.tick()
  juice.update()
  transition.update()
  G.t_estado = G.t_estado + 1
  if G.logros[1] then
    G.logros[1].t = G.logros[1].t + 1
    if G.logros[1].t > D.LOGRO_DUR then table.remove(G.logros, 1) end
  end
  local antes = G.estado
  if G.estado == "titulo" then actualiza_titulo()
  elseif G.estado == "niveles" then actualiza_niveles()
  elseif G.estado == "intro" then actualiza_intro()
  elseif G.estado == "juego" then actualiza_juego()
  elseif G.estado == "fin" then
    G.fx:update()
    actualiza_efectos()
    actualiza_fin()
  end
  if G.estado ~= antes then G.t_estado = 0 end
end

function _draw()
  if G.estado == "juego" and P.barrido then pintar_region(P.barrido.k, P.barrido.x) end
  if G.estado == "titulo" then D.titulo()
  elseif G.estado == "niveles" then D.niveles()
  elseif G.estado == "intro" then D.intro(P)
  elseif G.estado == "juego" then D.juego(P)
  elseif G.estado == "fin" then
    D.fin(P)
    G.fx:draw()
  end
  D.logro()
  juice.draw()
  transition.draw()
end
