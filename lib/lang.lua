-- lang: a game's words in the console's language, from one CSV of the game (strings.csv: a key and a column per
-- language, "key,es,ca,en", quotes as a spreadsheet writes them), so the texts are not in the code and a
-- translator never opens it. tools/strings_check.py says which letters the game's fonts lack.
--
--   local lang = require("lang")
--   lang.load()                      -- strings.csv, in the language of the console's settings (or lang.load("ca"))
--   text(lang.tr("hello", {name = nombre}), 10, 10)   -- "Hola, {name}" with its holes filled; a missing key is the key
--   lang.code                        -- the language in use; lang.set("en") changes it
--   lang.plural("coins", n)          -- the key "coins" for one, "coins_n" for several, {n = n} filled in
local M = {}
local strings, order, file_name = {}, {}, "strings.csv"
M.code = "es"

-- one line of a CSV: quotes, doubled quotes, commas inside quotes. Cut with find, not letter by letter: on the console every
-- letter made a string, and the garbage of a 160-key file left the heap in pieces (a game ran 20% slower with its words in it)
local function csv_fields(line)
  local out, i, n = {}, 1, #line
  if not line:find('"', 1, true) then
    while true do
      local j = line:find(",", i, true)
      if not j then out[#out + 1] = line:sub(i) return out end
      out[#out + 1] = line:sub(i, j - 1)
      i = j + 1
    end
  end
  while i <= n + 1 do
    local field
    if line:sub(i, i) == '"' then
      local j, parts = i + 1, {}
      while true do
        local q = line:find('"', j, true)
        if not q then parts[#parts + 1] = line:sub(j) j = n + 1 break end
        parts[#parts + 1] = line:sub(j, q - 1)
        if line:sub(q + 1, q + 1) == '"' then parts[#parts + 1] = '"' j = q + 2
        else j = q break end
      end
      field = table.concat(parts)
      i = j + 1
      if line:sub(i, i) == "," then i = i + 1 elseif i <= n then i = n + 2 end
    else
      local j = line:find(",", i, true) or (n + 1)
      field = line:sub(i, j - 1)
      i = j + 1
    end
    out[#out + 1] = field
    if i == n + 1 and line:sub(n, n) ~= "," then break end
    if i > n + 1 then break end
  end
  return out
end

-- the CSV's text -> {code -> {key -> string}}, the codes in order; `only` ({code = true}) keeps just those columns
function M.parse(text, only)
  local langs, out, first = {}, {}, true
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    if line ~= "" then
      local f = csv_fields(line)
      if first then
        for k = 2, #f do langs[k] = f[k] if not only or only[f[k]] then out[f[k]] = {} end end
        first = false
      else
        for k = 2, #f do if langs[k] and out[langs[k]] and f[k] ~= nil then out[langs[k]][f[1]] = f[k] end end
      end
    end
  end
  local codes = {}
  for k = 2, #langs do codes[#codes + 1] = langs[k] end
  return out, codes
end

-- only the first language (the one a missing word falls back to) and the one in use stay in memory: the other columns were a
-- third of the game's words for nothing; lang.set to another reads the file again
local function read(code)
  local text = file(file_name)
  if not text then error("lang: no " .. file_name .. " in the game", 2) end
  local head = csv_fields(text:match("^[^\r\n]*") or "")
  local base = head[2] or "es"
  code = code or (settings and settings().lang) or base
  local only = {[base] = true, [code] = true}
  strings, order = M.parse(text, only)
  order = {}
  for k = 2, #head do order[#order + 1] = head[k] end
  M.code = strings[code] and code or base
end

function M.load(code, name)
  file_name = name or "strings.csv"
  read(code)
  return M
end

function M.set(code)
  for _, c in ipairs(order) do
    if c == code and not strings[code] then read(code) return end
  end
  M.code = strings[code] and code or order[1] or code
end

local function fill(s, vars)
  if not vars then return s end
  return (s:gsub("{(%w+)}", function(k) local v = vars[k] return v ~= nil and tostring(v) or "{" .. k .. "}" end))
end

function M.tr(key, vars)
  local t = strings[M.code] or {}
  local s = t[key]
  if s == nil or s == "" then
    local base = strings[order[1]]
    s = base and base[key] or key
  end
  return fill(s, vars)
end

function M.plural(key, n, vars)
  vars = vars or {}
  vars.n = n
  return M.tr(n == 1 and key or (key .. "_n"), vars)
end

function M.keys() -- every key of the first language, sorted (tests, checks)
  local t, base = {}, strings[order[1]] or {}
  for k in pairs(base) do t[#t + 1] = k end
  table.sort(t)
  return t
end

return M
