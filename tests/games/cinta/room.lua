-- The room, one character per 8x8 block, 28x16 and two rows for the status under it. art.py draws it, main.lua
-- plays it and gives each block its colours (its attribute).
-- #  wall    =  floor (held from above)    -  a floor that crumbles    >  a conveyor (carries you right)
-- *  a poisonous plant    k  a key    X  the gate (2x2)    P  start    g  the guardian    .  air
return {
  "############################",
  "#..........................#",
  "#..........*...k......k....#",
  "#..======...=====...=====..#",
  "#..........................#",
  "#.k..................*.....#",
  "#====...=====...----..=====#",
  "#..........................#",
  "#......*.................k.#",
  "#...======...>>>>>>>>...===#",
  "#..........................#",
  "#.....k....................#",
  "#=====...-----....======...#",
  "#.P.........g...........XX.#",
  "#.............*.........XX.#",
  "############################",
  "............................",
  "............................",
}
