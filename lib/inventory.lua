-- inventory: the few things a character carries, as an adventure game has them (a handful of slots, one selected, items
-- that can be used on something). It does not draw a menu: `inv:draw(x, y)` is a strip of slots, shown whenever the game
-- wants (always, or for a moment when the selection changes).
--
--   local inventory = require("inventory")
--   inv = inventory.new({
--     slots = 3,
--     items = {                                           -- what each id is
--       llave = {name = "Llave", icon = "ICO_LLAVE", desc = "Abre el botellero."},
--       birra = {name = "Birra", icon = "ICO_BIRRA"},
--     },
--     uses = {                                            -- inv:use_on(target): what an item does to a target
--       llave = {botellero = function() unlock() return true end},   -- true: the item is used up
--     },
--     on_change = function(inv, what, id) end,            -- what: "add", "remove", "select"
--   })
--   inv:add("llave")                    -- true, or false and "full" / "unknown" / "have" (a second one is not taken
--                                       -- unless the item says stack = true)
--   inv:has("llave"), inv:count(), inv:full(), inv:remove("llave"), inv:selected()   -- the selected item's id or nil
--   inv:next(), inv:prev(), inv:select(i), inv:swap(1, 2)
--   inv:use_on("botellero")             -- the selected item on a target: its function in `uses`, true if it did something
--   inv:draw(x, y, {size = 28, gap = 4, frame = "FRAME_SLOT", box = 0x101820, border = 0xE8D8B0, pick = 0xFFE070,
--                   label = true})      -- the slots left to right, the selected one marked, its name under the strip
--   store("inv", inv:save())            inv:load(stored("inv"))
local inventory = {}
inventory.__index = inventory

function inventory.new(opts)
  opts = opts or {}
  local self = setmetatable({}, inventory)
  self.n = opts.slots or 3
  self.items, self.uses, self.on_change = opts.items or {}, opts.uses or {}, opts.on_change
  self.slot = {} -- slot[i] = item id or nil
  self.sel = 1
  return self
end

local function changed(self, what, id) if self.on_change then self.on_change(self, what, id) end end

function inventory:has(id)
  for i = 1, self.n do if self.slot[i] == id then return true, i end end
  return false
end

function inventory:count()
  local n = 0
  for i = 1, self.n do if self.slot[i] then n = n + 1 end end
  return n
end

function inventory:full() return self:count() >= self.n end

function inventory:add(id)
  local def = self.items[id]
  if not def then return false, "unknown" end
  if self:has(id) and not def.stack then return false, "have" end
  for i = 1, self.n do
    if not self.slot[i] then
      self.slot[i] = id
      changed(self, "add", id)
      return true, i
    end
  end
  return false, "full"
end

function inventory:remove(id)
  local has, i = self:has(id)
  if not has then return false end
  self.slot[i] = nil
  changed(self, "remove", id)
  return true
end

function inventory:selected() return self.slot[self.sel] end

function inventory:select(i)
  i = math.max(1, math.min(self.n, i))
  if i ~= self.sel then
    self.sel = i
    changed(self, "select", self.slot[i])
  end
end

function inventory:next() self:select(self.sel % self.n + 1) end
function inventory:prev() self:select((self.sel - 2) % self.n + 1) end

function inventory:swap(i, j)
  if i < 1 or j < 1 or i > self.n or j > self.n then return end
  self.slot[i], self.slot[j] = self.slot[j], self.slot[i]
end

-- The selected item on a target: what the game says it does there. false when nothing is selected or it does nothing.
function inventory:use_on(target)
  local id = self:selected()
  local f = id and self.uses[id] and self.uses[id][target]
  if not f then return false end
  local used = f(self, id, target)
  if used then self:remove(id) end
  return true
end

function inventory:save()
  local t = {sel = self.sel}
  for i = 1, self.n do t[i] = self.slot[i] or false end -- (false, not nil: a table with holes does not save)
  return t
end

function inventory:load(t)
  if type(t) ~= "table" then return end
  for i = 1, self.n do
    local id = t[i]
    self.slot[i] = id and self.items[id] and id or nil -- (an id the game no longer has is dropped)
  end
  self.sel = math.max(1, math.min(self.n, t.sel or 1))
end

function inventory:draw(x, y, o)
  o = o or {}
  local size, gap = o.size or 28, o.gap or 4
  local fill, border, pick = o.box or 0x101820, o.border or 0xE8D8B0, o.pick or 0xFFE070 -- (not named box: that is the function)
  for i = 1, self.n do
    local sx = x + (i - 1) * (size + gap)
    if o.frame then frame(o.frame, sx, y, size, size) else rect(sx, y, size, size, fill) box(sx, y, size, size, border) end
    local id = self.slot[i]
    local def = id and self.items[id]
    if def and def.icon then
      local w, h = imgsize(def.icon)
      if w then img(def.icon, sx + (size - w) // 2, y + (size - h) // 2) end
    end
    if i == self.sel then
      box(sx - 1, y - 1, size + 2, size + 2, pick)
      box(sx - 2, y - 2, size + 4, size + 4, pick)
    end
  end
  local def = self:selected() and self.items[self:selected()]
  if o.label ~= false and def and def.name then text(def.name, x, y + size + 6, o.color or 0xFFFFFF, o.font or "main") end
end

return inventory
