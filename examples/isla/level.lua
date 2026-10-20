-- level: the island, one character a cell (art.py reads these rows too, to draw the ground). A row is a y, going down-left on the
-- screen; a column an x, going down-right.
--   ~ water   . ground   1-4 a stone column that many blocks high   t a palm: nothing goes through it or onto it
-- On it: the crates (pushed, they fall to what is under them; into the water, they fill it), the five gems and where the hero starts.
-- The order: the first two are walked and climbed to; a crate pushed against the low pillar climbs to the third, and from it the
-- fourth on the tower; the other crate pushed into the channel is the bridge to the islet's fifth.
return {
  rows = {
    "~~~~~~~~~~~~",
    "~~.....t~~~~",
    "~.123...~~~~",
    "~.......~~~~",
    "~t......~..~",
    "~.......~..~",
    "~.......~..~",
    "~..234..~~~~",
    "~.......~~~~",
    "~~.....t~~~~",
    "~~~....~~~~~",
    "~~~~~~~~~~~~",
  },
  crates = {{3, 5}, {6, 5}},
  gems = {{6, 1}, {4, 2}, {3, 7}, {5, 7}, {10, 5}},
  start = {4, 9},
}
