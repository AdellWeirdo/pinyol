-- juice_hook: the screen's shake, behind one name so the modules that shake it need not know the library (and a test can silence it).
local juice = require("juice")
local J = {}
function J.shake(n) juice.shake(n) end
function J.offset() return juice.offset() end
function J.freeze(n) juice.freeze(n) end
function J.flash(c, n) juice.flash(c, n) end
return J
