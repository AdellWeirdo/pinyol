-- the same module after an edit: a number tuned, a function fixed, a field added
local M = {speed = 10, name = "second", extra = true}
function M.step() return M.speed * 2 end
return M
