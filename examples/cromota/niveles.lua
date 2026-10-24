-- The first campaign: five levels on one painting (Starry Night). Moves are first guesses to tune with play sessions.
-- Region ids are the painting's (layout.regiones): 1 azul 2 celeste 3 marino 4 verde 5 amarillo 6 naranja.
-- objetivos: {color, region, unidades}: the brush needs that many units of the colour (mixed ones are crafted first).
-- Regions that are not objectives start already restored.
local L = {
  {
    id = "nivel_1", nota = true, movimientos = 9, semilla = 12041, cap = 30,
    paleta = {"rojo", "amarillo", "azul"}, recetas = {},
    objetivos = {{color = "azul", region = 1, unidades = 20}, {color = "amarillo", region = 5, unidades = 16}},
    ayuda = true,
  },
  {
    id = "nivel_2", nota = true, movimientos = 11, semilla = 2207, cap = 30,
    paleta = {"rojo", "amarillo", "azul"}, pesos = {azul = 0.6}, recetas = {"naranja"},
    objetivos = {{color = "naranja", region = 6, unidades = 16}, {color = "amarillo", region = 5, unidades = 20}},
    ayuda = true,
  },
  {
    id = "nivel_3", nota = true, movimientos = 13, semilla = 31337, cap = 30,
    paleta = {"rojo", "amarillo", "azul"}, pesos = {amarillo = 0.7, rojo = 0.6}, recetas = {"verde"},
    objetivos = {{color = "verde", region = 4, unidades = 16}, {color = "azul", region = 1, unidades = 22}},
    ayuda = true,
  },
  {
    id = "nivel_4", nota = true, movimientos = 15, semilla = 4004, cap = 30,
    paleta = {"rojo", "amarillo", "azul", "blanco"}, pesos = {blanco = 0.6}, recetas = {"naranja", "celeste"},
    objetivos = {{color = "celeste", region = 2, unidades = 8}, {color = "amarillo", region = 5, unidades = 16},
                 {color = "naranja", region = 6, unidades = 10}},
  },
  {
    id = "nivel_5", nota = true, movimientos = 19, semilla = 5150, cap = 30,
    paleta = {"amarillo", "azul", "blanco", "negro"}, pesos = {blanco = 0.6, negro = 0.6},
    recetas = {"verde", "celeste", "marino"},
    objetivos = {{color = "verde", region = 4, unidades = 9}, {color = "celeste", region = 2, unidades = 8},
                 {color = "marino", region = 3, unidades = 8}, {color = "amarillo", region = 5, unidades = 14}},
    bloqueos = {{2, 3}, {4, 6}, {6, 2}},
  },
}

return L
