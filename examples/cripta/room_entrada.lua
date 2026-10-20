-- Made by tools/tiled2asset.py from entrada.tmx: change the map in Tiled and import it again.
return {
  width = 15,
  height = 10,
  tile_w = 16,
  tile_h = 16,
  layers = {
    suelo = {
      asset = "ROOM_ENTRADA_SUELO",
      data = {
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
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
      name = "start",
      type = "start",
      x = 56,
      y = 144,
      w = 0,
      h = 0,
      props = {},
    },
    {
      name = "statue",
      type = "statue",
      x = 136,
      y = 144,
      w = 0,
      h = 0,
      props = {},
    },
  },
  props = {
    mx = 0,
    my = 1,
  },
}
