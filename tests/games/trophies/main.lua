-- achievements and the console's record (tests/trophies.script, PINYOL_HOME set by CMake so the record is kept)
function _init() end
function _update() if btnp("a") then got = achieve("first") end end
function _draw() cls(0) end
