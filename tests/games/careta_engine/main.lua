-- A game with no careta of its own: the engine's plays first (tests/careta_engine.script).
started = false
function _init() started = true end
function _draw() rect(0, 0, 480, 320, 0x000000) end
