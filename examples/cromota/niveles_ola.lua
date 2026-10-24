-- The second painting: The Great Wave off Kanagawa. Region ids (layout.obras.ola.regiones): 1 marino 2 azul 3 celeste
-- 4 blanco 5 amarillo 6 naranja. Same rules as niveles.lua; numbers are first guesses to tune with play.
return {
  {
    id = "ola_1", movimientos = 9, semilla = 1831, cap = 30,
    nota = true,
    paleta = {"azul", "amarillo", "blanco"}, recetas = {},
    objetivos = {{color = "azul", region = 2, unidades = 20}, {color = "amarillo", region = 5, unidades = 18}},
    ayuda = true,
  },
  {
    id = "ola_2", movimientos = 10, semilla = 2250, cap = 30,
    nota = true,
    paleta = {"azul", "amarillo", "blanco"}, recetas = {},
    objetivos = {{color = "blanco", region = 4, unidades = 24}, {color = "azul", region = 2, unidades = 18}},
    ayuda = true,
  },
  {
    id = "ola_3", especiales = {"pincel"}, movimientos = 12, semilla = 8301, cap = 30,
    paleta = {"azul", "amarillo", "blanco"}, pesos = {amarillo = 0.8}, recetas = {"celeste"},
    objetivos = {{color = "celeste", region = 3, unidades = 12}, {color = "amarillo", region = 5, unidades = 26}},
  },
  {
    id = "ola_4", especiales = {"pincel"}, movimientos = 16, semilla = 4004, cap = 30,
    paleta = {"rojo", "amarillo", "azul", "blanco"}, pesos = {rojo = 0.7}, recetas = {"naranja", "celeste"},
    objetivos = {{color = "naranja", region = 6, unidades = 8}, {color = "celeste", region = 3, unidades = 7},
                 {color = "amarillo", region = 5, unidades = 18}},
  },
  {
    id = "ola_5", especiales = {"pincel"}, movimientos = 20, semilla = 1830, cap = 30,
    paleta = {"azul", "blanco", "negro", "amarillo"}, pesos = {negro = 0.6, blanco = 0.8}, recetas = {"marino", "celeste"},
    objetivos = {{color = "marino", region = 1, unidades = 9}, {color = "celeste", region = 3, unidades = 7},
                 {color = "blanco", region = 4, unidades = 16}, {color = "amarillo", region = 5, unidades = 16}},
    bloqueos = {{3, 2}, {5, 7}, {6, 4}},
  },
}
