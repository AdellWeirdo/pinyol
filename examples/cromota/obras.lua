-- The paintings: each one has its own five levels and its own regions (layout.obras[id]), and unlocks the next when all
-- its levels are done. Assets: OBRA_<id>_GRIS (parchment), OBRA_<id>_<region> (a region in colour).
return {
  {
    id = "noche", autor = "Van Gogh", niveles = require("niveles"),
  },
  {
    id = "ola", autor = "Hokusai", niveles = require("niveles_ola"),
  },
  {
    id = "nenufares", autor = "Monet", niveles = require("niveles_nenufares"),
  },
}
