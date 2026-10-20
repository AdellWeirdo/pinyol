-- Made by tools/tiled2asset.py from tesoro.tmx: change the map in Tiled and import it again.
return {
  width = 15,
  height = 10,
  tile_w = 16,
  tile_h = 16,
  layers = {
    suelo = {
      asset = "ROOM_TESORO_SUELO",
      data = {
        1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0,
        0, 0, 2, 2, 2, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 1, 0, 0, 1, 1, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 2, 2, 2,
        2, 0, 0, 0, 0, 3, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 3, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
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
      name = "heart",
      type = "heart",
      x = 216,
      y = 144,
      w = 0,
      h = 0,
      props = {},
    },
  },
  props = {
    mx = 1,
    my = 2,
  },
}
