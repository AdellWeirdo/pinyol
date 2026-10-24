-- The third painting: Water Lilies. Region ids (layout.obras.nenufares.regiones): 1 azul 2 marino 3 celeste 4 verde
-- 5 amarillo 6 violeta. It teaches violet (red + blue). Numbers are first guesses to tune with play.
return {
  {
    id = "nenufares_1", especiales = {"pincel"}, movimientos = 9, semilla = 1906, cap = 30,
    nota = true,
    paleta = {"azul", "amarillo", "rojo"}, recetas = {},
    objetivos = {{color = "azul", region = 1, unidades = 26}, {color = "amarillo", region = 5, unidades = 20}},
    ayuda = true,
  },
  {
    id = "nenufares_2", especiales = {"pincel"}, movimientos = 10, semilla = 6091, cap = 30,
    paleta = {"rojo", "azul", "amarillo"}, recetas = {"violeta"},
    objetivos = {{color = "violeta", region = 6, unidades = 14}, {color = "amarillo", region = 5, unidades = 20}},
    ayuda = true,
  },
  {
    id = "nenufares_3", especiales = {"pincel", "tubo"}, movimientos = 13, semilla = 2250, cap = 30,
    paleta = {"rojo", "amarillo", "azul"}, pesos = {rojo = 0.8}, recetas = {"verde", "violeta"},
    objetivos = {{color = "verde", region = 4, unidades = 15}, {color = "violeta", region = 6, unidades = 10},
                 {color = "azul", region = 1, unidades = 18}},
  },
  {
    id = "nenufares_4", especiales = {"pincel", "tubo"}, movimientos = 17, semilla = 4006, cap = 30,
    paleta = {"amarillo", "azul", "blanco", "rojo"}, pesos = {blanco = 0.7, rojo = 0.7}, recetas = {"celeste", "verde"},
    objetivos = {{color = "celeste", region = 3, unidades = 7}, {color = "verde", region = 4, unidades = 8},
                 {color = "azul", region = 1, unidades = 16}},
  },
  {
    id = "nenufares_5", especiales = {"pincel", "tubo"}, movimientos = 24, semilla = 1899, cap = 30,
    paleta = {"azul", "blanco", "negro", "amarillo", "rojo"}, pesos = {blanco = 0.7, negro = 0.6, rojo = 0.7},
    recetas = {"marino", "celeste", "violeta", "verde"},
    objetivos = {{color = "marino", region = 2, unidades = 6}, {color = "celeste", region = 3, unidades = 6},
                 {color = "violeta", region = 6, unidades = 6}, {color = "verde", region = 4, unidades = 8}},
    bloqueos = {{2, 6}, {4, 3}, {6, 7}},
  },
}
