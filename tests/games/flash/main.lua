-- The whole screen white one tick and black the next: thirty flashes a second (tests/flash.script, --check-flashes fails it)
function _draw() rect(0, 0, 480, 320, ticks() % 2 == 0 and 0xFFFFFF or 0x000000) end
