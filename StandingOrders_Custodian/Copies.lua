-- Custodian: marks for some copies of an item (1.2.0). Besides the item's own mark, an item can have a mark for
-- its bound copies and marks for copies with a given enchant, so the copy you wear (bound, maybe enchanted) can
-- be Locked while the copies you craft to sell stay free.
--
-- The mark that counts for one copy: its enchant's mark if it has one, else the bound-copies mark if this copy is
-- bound, else the item's mark (as before). Within each, this character's mark comes before the one for all
-- characters. Equipment-set protection still applies on top, by item ID.
--
-- Stored next to the item marks, in a new table, so 1.1.0 data needs no change:
--   StandingOrdersCustodianDB.copies / StandingOrdersCustodianCharDB.copies =
--     { [itemID] = { bound = level, ench = { [enchantID] = level } } }
-- Unlike item marks, Normal is stored too: it's a choice ("these copies are free"), not the absence of one.
--
-- Bound status: the bag slot's (container info, or C_Item.IsBound on an ItemLocation), the buyback tooltip's
-- "Soulbound" line for the sell guard, or the slot of the item on the cursor for the destroy guard. Bound items
-- can't be traded or mailed, so those guards only need the link's enchant.

local KS = StandingOrdersCustodian
local L = KS.LEVELS

local function Copies(scope, create)
  local sv = (scope == "char") and StandingOrdersCustodianCharDB or StandingOrdersCustodianDB
  if not sv then return nil end
  if create and not sv.copies then sv.copies = {} end
  return sv.copies
end

-- The enchant ID in an item link (the field after the item ID), or nil when there's none.
function KS.LinkEnchant(link)
  local e = type(link) == "string" and tonumber(link:match("item:%-?%d+:(%d*)") or "")
  return (e and e > 0) and e or nil
end

-- kind is "bound" or an enchant ID; scope "char" or "account". Nil when that copy mark isn't set.
function KS.GetCopyMark(id, kind, scope)
  local t = Copies(scope)
  local c = t and id and t[id]
  if not (c and kind) then return nil end
  if kind == "bound" then return c.bound end
  return c.ench and c.ench[kind]
end

-- Sets (level) or clears (nil) one copy mark.
function KS.SetCopyMark(id, kind, scope, level)
  local t = id and kind and Copies(scope, true)
  if not t then return end
  local c = t[id] or {}
  if kind == "bound" then
    c.bound = level
  else
    c.ench = c.ench or {}
    c.ench[kind] = level
    if not next(c.ench) then c.ench = nil end
  end
  t[id] = (c.bound or c.ench) and c or nil
  if KS.RefreshBagIcons then KS.RefreshBagIcons() end
end

-- True when the item has any copy mark, on this character or for all.
function KS.HasCopyMarks(id)
  local a, c = Copies("account"), Copies("char")
  return (id and ((a and a[id]) or (c and c[id]))) and true or false
end

-- The mark that counts for one copy (see the top of this file).
function KS.GetCopyLevel(id, link, bound)
  if not id then return L.NORMAL end
  if not KS.HasCopyMarks(id) then return KS.GetLevel(id) end
  local own
  local e = KS.LinkEnchant(link)
  if e then own = KS.GetCopyMark(id, e, "char") or KS.GetCopyMark(id, e, "account") end
  if not own and bound then own = KS.GetCopyMark(id, "bound", "char") or KS.GetCopyMark(id, "bound", "account") end
  if not own then return KS.GetLevel(id) end
  own = KS.Effective(own)
  local item, ownItem = KS.GetLevel(id), KS.GetOwnLevel(id)
  local set = (item > ownItem) and item or nil -- an equipment set raises the item above its own mark
  return (set and set > own) and set or own
end

-- Bound status of a bag slot.
function KS.IsSlotBound(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if info and info.isBound ~= nil then return info.isBound and true or false end
  if not (C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return false end
  local ok, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
  if not (ok and loc) then return false end
  local ok2, bound = pcall(C_Item.IsBound, loc)
  return (ok2 and bound) and true or false
end

-- The mark that counts for the item in a bag slot (Normal when it's empty).
function KS.GetSlotLevel(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not (info and info.itemID) then return L.NORMAL end
  if not KS.HasCopyMarks(info.itemID) then return KS.GetLevel(info.itemID) end
  return KS.GetCopyLevel(info.itemID, info.hyperlink, KS.IsSlotBound(bag, slot))
end

-- Whether buyback slot i holds a soulbound item: from its tooltip ("Soulbound").
local scanTip
function KS.BuybackBound(i)
  local soulbound = ITEM_SOULBOUND or "Soulbound"
  if C_TooltipInfo and C_TooltipInfo.GetBuybackItem then
    local ok, data = pcall(C_TooltipInfo.GetBuybackItem, i)
    if ok and data and data.lines then
      for _, line in ipairs(data.lines) do
        if line.leftText == soulbound then return true end
      end
      return false
    end
  end
  if not (CreateFrame and GameTooltip) then return false end
  scanTip = scanTip or CreateFrame("GameTooltip", "SOCustodianScanTip", nil, "GameTooltipTemplate")
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  local ok = pcall(scanTip.SetBuybackItem, scanTip, i)
  if not ok then return false end
  for n = 2, math.min(scanTip:NumLines() or 0, 6) do
    local fs = _G["SOCustodianScanTipTextLeft" .. n]
    if fs and fs:GetText() == soulbound then return true end
  end
  return false
end

-- Whether the item on the cursor (picked up from a bag) is bound: the bag slot it came from shows as locked.
function KS.CursorBound(id)
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == id and info.isLocked then return KS.IsSlotBound(bag, slot) end
    end
  end
  return false
end
