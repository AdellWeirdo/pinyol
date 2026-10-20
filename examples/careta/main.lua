-- Careta: a game with its own careta (splash.lua). The game itself is one screen; _init runs after the careta.
started, frames = false, 0 -- (global: tests/careta.script)

function _init()
  started = true
end

function _update()
  frames = frames + 1
end

function _draw()
  rect(0, 0, 480, 320, 0x0B0E1F)
  text("EL JUEGO EMPIEZA", 240, 150, {font = "bold", align = "center", color = 0xEEF0FF})
end
