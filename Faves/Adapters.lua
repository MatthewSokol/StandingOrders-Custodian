-- Faves: bag addon adapters. Each one hands another bag addon's item buttons to Faves (Alt+Click, the
-- level icon, the disenchant blocker) and answers, per button, which real bag and slot it shows, or
-- nothing when that view isn't live or can't be trusted. All optional: an adapter only runs when its
-- addon is loaded, Faves hooks instead of replacing anything, and an adapter that fails switches off.
-- docs/bag-addons.md has the rules; tools/smoke.lua has a stub of each addon's API.

local KS = Faves
local C = C_Container

local function LinkID(link) return link and tonumber(link:match("item:(%d+)")) end
local function ItemAt(bag, slot)
  local info = C.GetContainerItemInfo(bag, slot)
  return info and info.itemID
end
-- Bank bags only answer while the bank is open.
local function BankLive(isBank) return not isBank or KS.IsBankOpen() end

---------------------------------------------------------------------------------------------------
-- ArkInventory: its public API (ArkInventory.API.ItemFrameLoaded / ItemFrameUpdated) runs for every
-- item button. Only the bag and bank windows; offline views (another character, the bank away from a
-- banker) and buttons whose item doesn't match the slot are left alone.

KS.AddBagAddon({
  name = "ArkInventory",
  loaded = function()
    local api = _G.ArkInventory and ArkInventory.API
    return api and api.ItemFrameLoaded and api.ItemFrameUpdated and true
  end,
  hook = function(add)
    local ark = ArkInventory
    local function take(frame, loc_id)
      local L = ark.Const and ark.Const.Location
      if L and (loc_id == L.Bag or loc_id == L.Bank) then add(frame) end
    end
    hooksecurefunc(ark.API, "ItemFrameLoaded", take)
    hooksecurefunc(ark.API, "ItemFrameUpdated", take)
    if ark.API.ItemFrameLoadedIterate then
      for _, frame, loc_id in ark.API.ItemFrameLoadedIterate() do take(frame, loc_id) end
    end
  end,
  slot = function(btn)
    local ark, d = ArkInventory, btn.ARK_Data
    local loc = ark.Global and ark.Global.Location and d and ark.Global.Location[d.loc_id]
    if not loc or loc.isOffline or not d.slot_id then return end
    local bag = d.blizzard_id
    if not bag and ark.API.getBlizzardBagIdFromWindowId then
      bag = ark.API.getBlizzardBagIdFromWindowId(d.loc_id, d.bag_id)
    end
    if not bag then return end
    local i = ark.API.ItemFrameItemTableGet and ark.API.ItemFrameItemTableGet(btn)
    if (i and i.h and LinkID(i.h)) ~= ItemAt(bag, d.slot_id) then return end
    return bag, d.slot_id
  end,
})

