-- Made by tools/tiled2asset.py from cripta.tmx: change the map in Tiled and import it again.
return {
  width = 15,
  height = 10,
  tile_w = 16,
  tile_h = 16,
  layers = {
    suelo = {
      asset = "ROOM_CRIPTA_SUELO",
      data = {
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      },
    },
  },
  tiles = {
    [1] = {
      solid = true,
    },
    [2] = {
      platform = true,
    },
    [3] = {
      solid = true,
      cracked = true,
    },
  },
  objects = {
    {
      name = "slime",
      type = "slime",
      x = 56,
      y = 144,
      w = 0,
      h = 0,
      props = {},
    },
    {
      name = "wings",
      type = "wings",
      x = 184,
      y = 144,
      w = 0,
      h = 0,
      props = {},
    },
  },
  props = {
    mx = 4,
    my = 1,
  },
}
