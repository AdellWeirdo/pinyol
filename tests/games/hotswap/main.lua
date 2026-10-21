-- a module renewed while the game runs (tests/hotswap.script): the table the game holds gets the new file's fields
mod = require("mod")
kept = mod
count = 0
function _update() count = count + mod.step() end
function _draw() cls(0) end
