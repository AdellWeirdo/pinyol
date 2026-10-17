# Porting the board game's core to Lua

`games/audreygotchi/core/<name>.lua` is a port of `~/Desktop/DEV/AUDREYGOTCHI-main/audreygotchi/core/<name>.py`:
the same rules, numbers, names, branches and order of checks. A faithful translation, not a redesign: if the Python
does something odd, the Lua does the same odd thing (add a `-- ported as is:` comment when it looks like a bug).
Keep the Python's comments that explain a rule (shorten them if you like), in English.

## Runtime

- Lua 5.4 with **32-bit integers and 32-bit floats** (as the console). No `io`, `os`, `debug`, `package`.
- `require("core.x")` loads `core/x.lua`. No cycles: the Python modules import each other without cycles, keep it so.
- Test on the host with the standalone interpreter (same Lua, same 32-bit numbers):
  `LUA_ROOT=games/audreygotchi $LUA32 games/audreygotchi/tests/core/test_<group>.lua`
  (`$LUA32` = `/private/tmp/claude-501/-Users-pauavila/ea56f8f1-4eab-4a4f-a228-6f67b1d48f17/scratchpad/lua32/lua32`).
  Its `require` resolves `a.b` to `$LUA_ROOT/a/b.lua`. It has `print`, `assert`, `pcall`, `loadfile`.

## A module

```lua
-- <name>: what it is in one line (a port of audreygotchi/core/<name>.py).
local util = require("core.util")
local memory = require("core.memory")      -- module-level imports as in the Python
local M = {}

M.SOME_CONSTANT = 30                        -- module constants: public on M (other modules read them)

local function helper(s, x) ... end         -- Python's _private functions: local (or M._name if another module uses it)

function M.minute(s, now_ms) ... end        -- Python's def minute(state, now_ms): `state` is `s`

return M
```

## The state `s`

`s` is GameState: a plain table of fields (exactly the Python attribute names, leading underscores included:
`s.hunger`, `s._later`, `s._frame_ms`) whose metatable gives:

- the constants of `core/rules.lua` (Python's `Rules`): `s.TICK_INTERVAL_SEC`, `s.FEED_EFFECTS.Comida.H`;
- GameState's methods (Python's `state.py` and `state_screens.py`). **Every Python `state.method(args)` becomes
  `s:method(args)`** (colon): `s:_emit_sound("come")`, `s:compute_mood()`, `s:_log_event("...")`,
  `s:mark_dirty()`, `s:_pf("sociability")`, `s:is_night()`, `s:enter_sleep(now_ms, "manual", false)`.
  Keyword arguments become positional in the Python signature's order (`reason=`, `show_overlay=`).
- the clock: `s.clock:now()` (integer game seconds), `s.clock:localtime(ts)` (a table with `tm_year tm_mon
  tm_mday tm_hour tm_min tm_sec tm_yday tm_wday`, as Python's struct_time), `s.clock:local_hour()`,
  `s.clock:now_ms()`. Colon here too.

Fields are saved as they are (see "Saving"), so a field must hold only numbers, strings, booleans and tables of
them: never a function. Python `None` stored in a field becomes `nil` (the field disappears): fine, test with
`== nil`.

## Translation rules (the traps)

- **Truthiness.** In Lua only `nil` and `false` are false: `0`, `""`, `{}` are TRUE. Translate every Python test of
  a number, string or container explicitly: `if state.sitter_until:` -> `if s.sitter_until ~= 0 then`;
  `if state.grow_to:` -> `if s.grow_to ~= "" then`; `if state._later:` -> `if #s._later > 0 then`;
  `if not d:` (dict) -> `if next(d) == nil then`; `x or default` where x may be 0/"" -> spell it out.
  Same for `and`/`or` used as values: `a and b or c` breaks when b is false/nil.
- **Indices.** Index-like *values* stay 0-based as in Python (`selected_index`, `current_scene`, `hidden_scene`
  -1, columns, rooms, `feed_choice`...): they are data and the UI reads them. Only when you index a Lua array
  add 1: `items[s.selected_index + 1]`. `len(x)` -> `#x` (lists) or `util.len(d)` (dicts).
  `range(a, b)` -> `for i = a, b - 1`. `x[-1]` -> `x[#x]`. Slices: `util.slice`.
- **Numbers.** Python `//` and `%` floor like Lua's `//` and `%`: keep them. `int(x)` -> `util.int(x)` (towards
  zero) unless x is already an integer; `round(x)` -> `util.round(x)`; `float(x)` -> `x` (or `x + 0.0`);
  `abs` -> `math.abs`; `min/max` -> `math.min/max`; `sum` -> `util.sum`. Integers overflow past 2^31: never
  multiply timestamps; milliseconds stay small (they count from the session's start). `x ** y` -> `x ^ y`
  (float), integer powers by hand.
- **Strings.** f-strings -> `string.format` or `..`. Text is Windows-1252 only: **drop every emoji** from on-screen
  strings (and the space before it): `"¡Splash! Brrr... 🛁"` -> `"¡Splash! Brrr..."`. Keep the Spanish exactly
  otherwise. `str.startswith(p)` -> `x:sub(1, #p) == p`; `split`, `strip`, `in` (substring) -> `string.find(x, y,
  1, true)`. Careful with `#` on UTF-8 strings: it counts bytes (use `utf8.len` for letters).
- **Containers.** Lists -> arrays; `append` -> `t[#t+1] = v`; `pop(0)` -> `table.remove(t, 1)`; `pop()` ->
  `table.remove(t)`; `x in list` -> `util.contains(list, x)`; `x in dict` -> `d[x] ~= nil`; `dict.get(k, d)` ->
  `util.get(t, k, d)`; `list.index(v)` -> `util.index(list, v)` (0-based); `sorted` -> copy + `table.sort`;
  iterating a dict -> `for _, k in ipairs(util.keys(d))` when the order can change a result (deterministic).
  Tuples -> arrays. Sets -> `{[k] = true}`. A dict's keys that are ints in Python stay what they are (`daily_metrics`
  uses string keys `tostring(day)`, as the Python).
- **Random.** `random.random()` -> `math.random()`; `randint(a, b)` -> `math.random(a, b)`; `uniform` ->
  `util.uniform`; `choice` -> `util.choice`; `sample` -> `util.sample`; `shuffle` -> `util.shuffle`;
  `random.choices(items, weights)[0]` -> `util.weighted(items, weights)`.
- **Errors.** `try/except` around a cast -> just do the safe thing; around real work -> `pcall`.
  `isinstance(x, dict)` -> `type(x) == "table"`. `getattr(s, name, d)` -> `util.get(s, name, d)`;
  `setattr(s, name, v)` -> `s[name] = v`.
- **Time.** `now_ms` is the front end's frame tick in ms (integer, from the session's start). `s.clock:now()` is
  game seconds (integer). Keep each value on the base the Python used.

## Tests

Other groups port other modules at the same time, so a module you require may not exist yet. Require it normally
in your module; in your test, stub what you call before requiring your module:
`LOADED["core.memory"] = {first = function() end, remember = function() end}` (the interpreter's `require` checks
`LOADED` first). Stub only what the Python module really exports, with the Python names.

Each group writes `games/audreygotchi/tests/core/test_<group>.lua`: plain `assert`s, one block per rule that
matters (a number, a threshold, a branch), ending with `print("ok <group>")`. Build the state you need by hand
(a table with only the fields your module touches, `setmetatable(s, {__index = setmetatable({...stub methods...},
{__index = require("core.rules")})})`), or, once `core/state.lua` exists, `require("core.state").new(clock)` for a
whole fresh game. Seed with `math.randomseed(1)` where random matters. Port the matching asserts of the Python
tests (`~/Desktop/DEV/AUDREYGOTCHI-main/tests/test_rules_v11.py`, `test_v2_gameplay.py`, `test_bible_64.py`,
`test_core_flows.py`, `test_minigames_v1.py`...) when they test your modules.

## Saving

`core/save.lua` (the front end's) stores every field of `s` except the transient ones listed there. If your module
has a field that must not survive a reload (Python's payload_codec drops it or resets it), say so in a comment
at its first assignment: `-- transient`.
