-- Custodian: bag addon adapters. Each one hands another bag addon's item buttons to Custodian (Alt+Click, the
-- level icon, the disenchant blocker) and answers, per button, which real bag and slot it shows, or
-- nothing when that view isn't live or can't be trusted. All optional: an adapter only runs when its
-- addon is loaded, Custodian hooks instead of replacing anything, and an adapter that fails switches off.
-- docs/bag-addons.md has the rules; tools/smoke.lua has a stub of each addon's API.

local KS = StandingOrdersCustodian
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

---------------------------------------------------------------------------------------------------
-- ElvUI bags (only when ElvUI's bags module is on): B:UpdateSlot(frame, bagID, slotID) runs for every
-- slot; the button is frame.Bags[bagID][slotID] and carries BagID / SlotID. No offline views; the bank
-- frame only counts while the bank is open.

local function ElvBags()
  local E = _G.ElvUI and ElvUI[1]
  if not (E and E.private and E.private.bags and E.private.bags.enable and E.GetModule) then return end
  return E:GetModule("Bags", true)
end

KS.AddBagAddon({
  name = "ElvUI bags",
  loaded = function()
    local B = ElvBags()
    return B and B.UpdateSlot and true
  end,
  hook = function(add)
    hooksecurefunc(ElvBags(), "UpdateSlot", function(_, frame, bagID, slotID)
      local slot = frame and frame.Bags and frame.Bags[bagID] and frame.Bags[bagID][slotID]
      if slot then
        slot.favesBankFrame = frame.isBank and true or nil
        add(slot)
      end
    end)
  end,
  slot = function(btn)
    if not (btn.BagID and btn.SlotID and BankLive(btn.favesBankFrame)) then return end
    return btn.BagID, btn.SlotID
  end,
})

---------------------------------------------------------------------------------------------------
-- AdiBags: its own message library (ABEvent-1.0) sends AdiBags_UpdateButton(button) for every item
-- button update. Buttons are pooled and reused, so the slot is read each time: button.bag / .slot.
-- No offline views; bank buttons only count while the bank is open. On Forever each button has a secure
-- right-click button laid over it (button.ForeverSecureUse) that calls the item button's OnClick directly
-- for modified clicks, so the item button's PreClick never sees Alt+Right-click: clickFrames names it.

local function AdiBags()
  local ace = LibStub and LibStub("AceAddon-3.0", true)
  return ace and ace:GetAddon("AdiBags", true)
end

KS.AddBagAddon({
  name = "AdiBags",
  loaded = function() return AdiBags() and LibStub("ABEvent-1.0", true) and true end,
  hook = function(add)
    local listener = {}
    LibStub("ABEvent-1.0"):Embed(listener)
    listener:RegisterMessage("AdiBags_UpdateButton", function(_, button) add(button) end)
  end,
  clickFrames = function(btn) return { btn.ForeverSecureUse } end,
  slot = function(btn)
    local isBank = btn.IsBank and btn:IsBank()
    if not (btn.bag and btn.slot and BankLive(isBank)) then return end
    return btn.bag, btn.slot
  end,
})

---------------------------------------------------------------------------------------------------
-- BetterBags: its Events module sends "item/Updated"(ctx, item, decoration) whenever an item is drawn.
-- item.button takes the clicks; item.currentData has the real bagid / slotid and the item link. No
-- offline flag, so bank slots only count while the bank is open, and the drawn item must match the slot.

local function BetterBags()
  local ace = LibStub and LibStub("AceAddon-3.0", true)
  return ace and ace:GetAddon("BetterBags", true)
end
local function IsBankBag(bag) return bag < 0 or bag > (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) end

KS.AddBagAddon({
  name = "BetterBags",
  loaded = function()
    local bb = BetterBags()
    local ok, events = pcall(function() return bb and bb:GetModule("Events", true) end)
    return ok and events and events.RegisterMessage and true
  end,
  hook = function(add)
    BetterBags():GetModule("Events"):RegisterMessage("item/Updated", function(_, item)
      if item and item.button then
        item.button.favesItem = item
        add(item.button)
      end
    end)
  end,
  slot = function(btn)
    local d = btn.favesItem and btn.favesItem.currentData
    local bag, slot = d and d.bagid, d and d.slotid
    if not (bag and slot) or not BankLive(IsBankBag(bag)) then return end
    local link = d.itemInfo and d.itemInfo.itemLink
    if LinkID(link) ~= ItemAt(bag, slot) then return end
    return bag, slot
  end,
})

---------------------------------------------------------------------------------------------------
-- Baganator: every draw of an item button calls :SetItemDetails, which the button got from a mixin copied
-- onto it. Baganator freezes those mixins (table.freeze), so hooking them fails ("indexed assignment on a
-- frozen table"). Instead its skin API (the one Masque uses) hands over every item button as it's made, and
-- each button's own SetItemDetails is hooked. Cached buttons (other characters, the closed bank) come too,
-- but have no live item location, so slot() skips them. The parent's ID is the bag, the button's the slot,
-- and the shown item (BGR.itemID) must match that slot.

local function SkinsAPI()
  local api = _G.Baganator and Baganator.API and Baganator.API.Skins
  return api and type(api.RegisterListener) == "function" and api or nil
end
local baganatorButtons = setmetatable({}, { __mode = "k" })

KS.AddBagAddon({
  name = "Baganator",
  loaded = function() return SkinsAPI() ~= nil end,
  hook = function(add)
    local function Watch(details)
      local btn = type(details) == "table" and details.regionType == "ItemButton" and details.region
      if not btn or baganatorButtons[btn] or type(btn.SetItemDetails) ~= "function" then return end
      baganatorButtons[btn] = true
      hooksecurefunc(btn, "SetItemDetails", function(b) add(b) end)
      add(btn)
    end
    local api = SkinsAPI()
    api.RegisterListener(Watch)
    for _, details in ipairs(api.GetAllFrames and api.GetAllFrames() or {}) do Watch(details) end -- made before login
  end,
  slot = function(btn)
    local parent = btn.GetParent and btn:GetParent()
    local bag, slot = parent and parent:GetID(), btn:GetID()
    if not (bag and slot and slot > 0 and btn.BGR and btn.BGR.itemLocation) then return end
    if not BankLive(IsBankBag(bag)) or btn.BGR.itemID ~= ItemAt(bag, slot) then return end
    return bag, slot
  end,
})

---------------------------------------------------------------------------------------------------
-- Bagnon (and Combuctor, same BagBrother core): Item:Update runs for every item button (ContainerItem
-- calls it through Super). btn:GetBag() and btn:GetID() are the bag and slot; btn:IsCached() is true for
-- other characters and for the bank away from a banker.

for _, addonName in ipairs({ "Bagnon", "Combuctor" }) do
  KS.AddBagAddon({
    name = addonName,
    loaded = function()
      local a = _G[addonName]
      return type(a) == "table" and a.Item and a.Item.Update and true
    end,
    hook = function(add)
      hooksecurefunc(_G[addonName].Item, "Update", function(btn) add(btn) end)
    end,
    slot = function(btn)
      if not (btn.GetBag and btn.GetID) or (btn.IsCached and btn:IsCached()) then return end
      local bag, slot = btn:GetBag(), btn:GetID()
      if type(bag) ~= "number" or not slot or slot < 1 then return end
      return bag, slot
    end,
  })
end
