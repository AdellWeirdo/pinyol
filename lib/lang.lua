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
local strings, order = {}, {}
M.code = "es"

local function csv_fields(line) -- one line of a CSV: quotes, doubled quotes, commas inside quotes
  local out, i, n = {}, 1, #line
  while i <= n + 1 do
    local field
    if line:sub(i, i) == '"' then
      local j = i + 1
      local parts = {}
      while j <= n do
        local c = line:sub(j, j)
        if c == '"' then
          if line:sub(j + 1, j + 1) == '"' then parts[#parts + 1] = '"' j = j + 2
          else break end
        else parts[#parts + 1] = c j = j + 1 end
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

function M.parse(text) -- the CSV's text -> {code -> {key -> string}}, the codes in order
  local langs, out, first = {}, {}, true
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    if line ~= "" then
      local f = csv_fields(line)
      if first then
        for k = 2, #f do langs[k] = f[k] out[f[k]] = {} end
        first = false
      else
        for k = 2, #f do if langs[k] and f[k] ~= nil then out[langs[k]][f[1]] = f[k] end end
      end
    end
  end
  local codes = {}
  for k = 2, #langs do codes[#codes + 1] = langs[k] end
  return out, codes
end

function M.load(code, name)
  local text = file(name or "strings.csv")
  if not text then error("lang: no " .. (name or "strings.csv") .. " in the game", 2) end
  strings, order = M.parse(text)
  M.set(code or (settings and settings().lang) or order[1] or "es")
  return M
end

function M.set(code)
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
