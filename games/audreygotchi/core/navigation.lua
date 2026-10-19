-- navigation: A and C, the main menu and its cursor (a port of audreygotchi/core/navigation.py).
local util = require("core.util")
local asks = require("core.asks")
local scene_sancho = require("core.scene_sancho")
local actions = require("core.actions")
local lifecycle = require("core.lifecycle")
local litter = require("core.litter")
local M = {}

M.MENU_MAX = 10 -- the menu's buttons on screen: two rows of five

function M.status_page_left(s)
  local n = #s.STATUS_PAGES
  if n <= 0 then
    return
  end
  s.status_page = (s.status_page - 1) % n
  s:mark_dirty()
end

function M.status_page_right(s)
  local n = #s.STATUS_PAGES
  if n <= 0 then
    return
  end
  s.status_page = (s.status_page + 1) % n
  s:mark_dirty()
end

M.HEAL_MENU_HEALTH = 50.0 -- below this Curar joins the menu even without an illness

function M.needs_heal(s)
  if s.sick or s.in_critical then return true end
  return s.health < M.HEAL_MENU_HEALTH
end

-- `item` before the first of `later` in the menu, or last.
local function insert_before(items, item, later)
  local at = #items
  for _, x in ipairs(later) do
    if util.contains(items, x) then
      at = util.index(items, x)
      break
    end
  end
  table.insert(items, at + 1, item)
end

local function remove_item(items, x) -- list.remove(x): the first one
  table.remove(items, util.index(items, x) + 1)
end

function M.active_menu_items(s)
  local items = util.copy(s.menu_items)
  -- no day out with Sancho as a baby, and then his introduction brings his button (owner)
  local unmet = s.sancho_intro_at ~= 0 and s.mode ~= "sancho_intro"
  if (s.phase == "Cachorro" or unmet) and util.contains(items, "Sitter") then
    remove_item(items, "Sitter")
  end
  local animals = s.memory["animals"]
  if animals ~= nil and next(animals) ~= nil then -- her friends', once one came (owner, 2026-10-08)
    insert_before(items, "Friends", {"Album", "Status", "Settings"})
  end
  if actions.fiesta_item(s) ~= nil then -- a holiday's own button, after Sancho's (owner, 2026-10-07)
    insert_before(items, "Fiesta", {"Friends", "Album", "Status", "Settings"})
  end
  -- v11 keeps the v9 menu; Curar lives in the health flow, so it shows up only when needed, first in the second
  -- row, where the care goes on (owner, 2026-10-08)
  if M.needs_heal(s) then
    insert_before(items, "Heal", {"Sitter", "Fiesta", "Friends", "Album", "Status", "Settings"})
  end
  for _, spare in ipairs({"Album", "Friends"}) do -- more than fit: these wait in Estado, the album first
    if #items > M.MENU_MAX and util.contains(items, spare) then
      remove_item(items, spare)
    end
  end
  return items
end

local function same_list(a, b) -- Python's list ==
  if a == nil or b == nil or #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- Keep the cursor on its item when Curar comes or goes: the cursor is an index.
function M.sync_menu_cursor(s)
  local items = s:active_menu_items()
  local seen = s._menu_seen
  if same_list(items, seen) then
    return
  end
  local idx = util.int(s.selected_index)
  local label = nil
  if seen ~= nil and #seen > 0 and 0 <= idx and idx < #seen then label = seen[idx + 1] end
  if label ~= nil and util.contains(items, label) then
    s.selected_index = util.index(items, label)
  else
    s.selected_index = math.max(0, math.min(idx, #items - 1))
  end
  s._menu_seen = items -- transient (rebuilt on load)
end

-- The board's icons are emoji, which pinyol's Windows-1252 text cannot draw: dropped (the front end draws its own).
local ICON_MAP = {Feed = "", Play = "", Cuddle = "", Bath = "", Sleep = "", Heal = "", Status = "", Album = "",
                  Friends = "", Settings = "", Sitter = ""}

function M.active_menu_icons(s)
  local out = {}
  for _, x in ipairs(s:active_menu_items()) do out[#out + 1] = util.get(ICON_MAP, x, "•") end
  return out
end

function M.move_left(s)
  if s.powered_off or s.deep_sleep or s.mode == "guide" then
    return
  end
  if s.mode == "status" then
    s:status_page_left()
    return
  end
  if s.mode == "settings" then
    s:settings_left()
    return
  end
  if s.mode == "tech" then
    s:tech_page_left()
    return
  end
  if s.mode == "system" then
    s:system_move(-1)
    return
  end
  if s.mode == "action_feed" then
    s:feed_left()
    return
  end
  if s.mode == "action_play" then
    s:play_left()
    return
  end
  if s.mode == "action_minigame" then
    if s.minigame_left ~= nil then
      s:minigame_left()
    end
    return
  end
  if s.mode == "action_heal" then
    s:heal_left()
    return
  end
  if s.mode == "action_bath" then
    litter.move(s, -1)
    return
  end
  if s.mode == "farewell" then -- at its end: a new life or her memories
    lifecycle.farewell_move(s)
    return
  end
  if s.mode == "birth" or s.mode == "sancho_intro" or s.mode == "grow" then
    return
  end
  if s.mode == "sitter_confirm" then -- Sí is on the left
    scene_sancho.choose(s, true)
    return
  end
  if s.mode == "ask" then
    asks.choose(s, true)
    return
  end
  if s.sitter_until ~= 0 and s.mode == "main" then -- away with Sancho: B only
    return
  end
  if s.hidden and s.mode == "main" then -- hide and seek: walk to the previous room
    s:_look(-1)
    return
  end

  if s.selected_index > 0 then
    s.selected_index = s.selected_index - 1
    s:mark_dirty()
  end
end

function M.move_right(s)
  if s.powered_off or s.deep_sleep or s.mode == "guide" then
    return
  end
  if s.mode == "status" then
    s:status_page_right()
    return
  end
  if s.mode == "settings" then
    s:settings_right()
    return
  end
  if s.mode == "tech" then
    s:tech_page_right()
    return
  end
  if s.mode == "system" then
    s:system_move(1)
    return
  end
  if s.mode == "action_feed" then
    s:feed_right()
    return
  end
  if s.mode == "action_play" then
    s:play_right()
    return
  end
  if s.mode == "action_minigame" then
    if s.minigame_right ~= nil then
      s:minigame_right()
    end
    return
  end
  if s.mode == "action_heal" then
    s:heal_right()
    return
  end
  if s.mode == "action_bath" then
    litter.move(s, 1)
    return
  end
  if s.mode == "farewell" then -- at its end: a new life or her memories
    lifecycle.farewell_move(s)
    return
  end
  if s.mode == "birth" or s.mode == "sancho_intro" or s.mode == "grow" then
    return
  end
  if s.mode == "sitter_confirm" then -- No is on the right
    scene_sancho.choose(s, false)
    return
  end
  if s.mode == "ask" then
    asks.choose(s, false)
    return
  end
  if s.sitter_until ~= 0 and s.mode == "main" then -- away with Sancho: B only
    return
  end
  if s.hidden and s.mode == "main" then -- hide and seek: walk to the next room
    s:_look(1)
    return
  end

  if s.selected_index < #s:active_menu_items() - 1 then
    s.selected_index = s.selected_index + 1
    s:mark_dirty()
  end
end

function M.current_label(s)
  local items = s:active_menu_items()
  local idx = math.max(0, math.min(util.int(s.selected_index), math.max(0, #items - 1)))
  if #items > 0 then return items[idx + 1] end
  return ""
end

return M
