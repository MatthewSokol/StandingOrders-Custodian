-- Custodian: marks for one copy of an item (1.2.0). An item's mark (for all your characters, or for this one)
-- covers every copy of it; a copy mark covers one exact item (its item GUID), wherever it goes.
--
-- Soulbound items are marked per copy: Alt+Click (or the mark menu) on a soulbound copy marks that copy only.
-- A soulbound copy takes the item's mark only where it fits:
--   * it can't be mailed, so the item's Mail mark is no mark for it;
--   * a BoE item that has become soulbound (you equipped it) is yours now: the item's Junk and Disenchant marks
--     don't apply to it either, while protection (Locked, Always on me) does.
-- When Custodian sees such a copy, it gives it a copy mark of its own (CopyTrack.lua), so from then on it no longer
-- follows the item's mark. A mark you put on it after that (Junk, after it's soulbound) stays.
-- Items that stack (potions, conjured food, quest items) never get copy marks: a stack's copies merge and split.
--
-- New marks (/soc settings, advanced, or /soc scope) go to all your characters (the default), this character, or
-- the copy you click. A copy that has a mark of its own is always changed per copy.
--
-- StandingOrdersCustodianDB.copyMarks[guid] = { id, link, level, bound, owner, where, seen, left }
--   level  its mark; Normal too, since it overrides the item's mark ("no mark on this copy")
--   bound  whether the copy was soulbound when it got the mark: a BoE copy marked while unbound loses its Junk,
--          Mail and Disenchant mark once it's soulbound
--   owner, where, seen, left: where it was last seen, for the clean-up (CopyTrack.lua)

local KS = StandingOrdersCustodian
local L = KS.LEVELS
local JUNK, DISENCHANT, MAIL, NORMAL = L.JUNK, L.DISENCHANT, L.MAIL, L.NORMAL
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function Marks()
  local db = StandingOrdersCustodianDB
  if not db then return nil end
  db.copyMarks = db.copyMarks or {}
  return db.copyMarks
end
KS.CopyMarks = Marks

local function ItemLink(id) return select(2, GetItemInfo(id)) or ("item:" .. id) end

-- An ItemLocation for a bag slot, or for an equipment slot when bag is nil.
function KS.ItemLoc(bag, slot)
  if not ItemLocation then return nil end
  local ok, loc
  if bag then
    if not ItemLocation.CreateFromBagAndSlot then return nil end
    ok, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
  else
    if not ItemLocation.CreateFromEquipmentSlot then return nil end
    ok, loc = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
  end
  return ok and loc or nil
end

-- The item GUID at a location: one exact copy. Nil for an empty slot or a client without the API (GetItemGUID
-- raises for an empty location, so DoesItemExist goes first).
function KS.LocGUID(loc)
  if not (loc and C_Item and C_Item.GetItemGUID) then return nil end
  if C_Item.DoesItemExist then
    local ok, exists = pcall(C_Item.DoesItemExist, loc)
    if not (ok and exists) then return nil end
  end
  local ok, guid = pcall(C_Item.GetItemGUID, loc)
  return (ok and type(guid) == "string" and guid ~= "") and guid or nil
end

-- Soulbound: bound to this character. Account-bound items are bound too, but can still go to your other characters
-- (the warband bank takes them), so they aren't. isBound: the container's answer, when the caller has it.
function KS.LocSoulbound(loc, isBound)
  if isBound == nil then
    if not (loc and C_Item and C_Item.IsBound) then return false end
    local ok, bound = pcall(C_Item.IsBound, loc)
    isBound = ok and bound
  end
  if not isBound then return false end
  if loc and C_Bank and C_Bank.IsItemAllowedInBankType and Enum and Enum.BankType and Enum.BankType.Account then
    local ok, warband = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account, loc)
    if ok and warband then return false end
  end
  return true
end

-- How the item binds: "boe" (on equip, on use, or warbound until equipped), "bop", or nil while the client doesn't
-- know it yet.
local BOE = { [2] = true, [3] = true, [9] = true }
function KS.BindKind(id)
  local bindType = id and select(14, GetItemInfo(id))
  if bindType == nil then return nil end
  return BOE[bindType] and "boe" or "bop"
end

-- Whether the item stacks (then it can't have copy marks). Not known yet counts as stacking.
function KS.Stacks(id, count)
  if count and count > 1 then return true end
  local max = id and select(8, GetItemInfo(id))
  return max == nil or max > 1
end

-- The mark an item mark gives a soulbound copy (see the top of this file). An item whose binding isn't known yet
-- counts as BoE: then a copy that's yours is never sold for its item's Junk mark.
function KS.SoulboundLevel(id, level)
  if level == MAIL then return NORMAL end
  if (level == JUNK or level == DISENCHANT) and KS.BindKind(id) ~= "bop" then return NORMAL end
  return level
end

-- Equipment-set protection on top of a copy's level, as for item marks.
function KS.WithSet(id, level)
  local item, own = KS.GetLevel(id), KS.GetOwnLevel(id)
  return (item > own and item > level) and item or level
end

-- The mark that counts for the copy at a location: its copy mark, else the item's mark as it applies to that copy.
function KS.LevelAt(id, loc, isBound)
  if not id then return NORMAL end
  local marks = Marks()
  if marks and next(marks) then
    local guid = KS.LocGUID(loc)
    local r = guid and marks[guid]
    if r then return KS.WithSet(id, KS.Effective(r.level)) end
  end
  local own = KS.GetOwnLevel(id)
  if (own == MAIL or own == JUNK or own == DISENCHANT) and KS.LocSoulbound(loc, isBound) then
    return KS.WithSet(id, KS.SoulboundLevel(id, own))
  end
  return KS.GetLevel(id)
end

-- The mark that counts for the item in a bag slot (Normal when it's empty).
function KS.GetSlotLevel(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  local id = info and info.itemID
  if not id then return NORMAL end
  local marks, own = Marks(), KS.GetOwnLevel(id)
  local maybeBound = info.isBound ~= false and (own == MAIL or own == JUNK or own == DISENCHANT)
  if not ((marks and next(marks)) or maybeBound) then return KS.GetLevel(id) end
  return KS.LevelAt(id, KS.ItemLoc(bag, slot), info.isBound)
end

-- The copy at a bag slot (an equipment slot when bag is nil): { guid, id, link, soulbound, bag, slot }, or nil when
-- it can't have a copy mark (empty, an item that stacks, or no item GUID on this client).
function KS.CopyAt(bag, slot)
  local id, link, count, isBound
  if bag then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not (info and info.itemID) then return nil end
    id, link, count, isBound = info.itemID, info.hyperlink, info.stackCount, info.isBound
  elseif GetInventoryItemID then
    id = GetInventoryItemID("player", slot)
    link = id and GetInventoryItemLink and GetInventoryItemLink("player", slot)
  end
  if not id or KS.Stacks(id, count) then return nil end
  local loc = KS.ItemLoc(bag, slot)
  local guid = KS.LocGUID(loc)
  if not guid then return nil end
  return { guid = guid, id = id, link = link, soulbound = KS.LocSoulbound(loc, isBound), bag = bag, slot = slot }
end

-- A copy's own mark, or nil when it has none.
function KS.CopyMark(guid)
  local marks = Marks()
  local r = marks and guid and marks[guid]
  return r and KS.Effective(r.level) or nil
end

-- What a copy shows without equipment sets: its own mark, else its item's mark as it applies to it.
function KS.CopyOwnLevel(copy)
  local own = KS.CopyMark(copy.guid)
  if own then return own end
  own = KS.GetOwnLevel(copy.id)
  return copy.soulbound and KS.SoulboundLevel(copy.id, own) or own
end

-- Where a mark given by clicking this bag slot goes: the copy (returned) when it's soulbound, has a mark of its own,
-- or new marks go to the copy you click (/soc scope copy); nil for the item's mark.
function KS.CopyToMark(bag, slot)
  local copy = bag and KS.CopyAt(bag, slot)
  if not copy then return nil end
  if copy.soulbound or KS.CopyMark(copy.guid) or KS.GetScope() == "copy" then return copy end
  return nil
end

function KS.CopyOwner() return (UnitGUID and UnitGUID("player")) or "?" end

-- Gives one copy its own mark (Normal too: no mark on this copy, whatever its item's), or takes it off (nil: the
-- copy follows its item's mark again). opts: { quiet = true }.
function KS.SetCopyMark(copy, level, opts)
  local marks = Marks()
  if not (marks and copy and copy.guid) then return end
  local link = copy.link or ItemLink(copy.id)
  if level == nil then
    marks[copy.guid] = nil
  else
    level = KS.Effective(level)
    local where, account = "bags", false
    if KS.CopyPlace then where, account = KS.CopyPlace(copy.bag) end
    marks[copy.guid] = { id = copy.id, link = link, level = level, bound = copy.soulbound and true or false,
      owner = account and "account" or KS.CopyOwner(), where = where, seen = time() }
  end
  if not (opts and opts.quiet) then
    if level == nil then
      KS.Notify("%s: this copy takes its item's mark again (%s).", link, KS.LevelText(KS.GetOwnLevel(copy.id)))
    else
      KS.Notify("%s is now %s |cff9d9d9d(this copy)|r.", link, KS.LevelText(level))
    end
  end
  if KS.RefreshBagIcons then KS.RefreshBagIcons() end
end

-- Alt+Shift+Left-click on a bag item: a soulbound copy's marks stay per copy; a copy's own mark becomes the item's
-- mark for all characters; otherwise the item's mark moves between all characters and this one (as before).
function KS.ToggleScopeAt(bag, slot, id, link)
  local copy = KS.CopyAt(bag, slot)
  if copy and copy.soulbound then
    return KS.Print("%s is soulbound: its marks are for this copy only.", link or ItemLink(id))
  end
  local own = copy and KS.CopyMark(copy.guid)
  if own then
    KS.SetCopyMark(copy, nil, { quiet = true })
    KS.SetLevel(id, own, link, { scope = "account", quiet = true })
    return KS.Notify("%s is now %s for all characters, not just this copy.", link or ItemLink(id), KS.LevelText(own))
  end
  KS.ToggleItemScope(id, link)
end

-- This character's copy marks (and those in the warband bank), for the Marked items window and /soc list print:
-- { guid, id, link, level, where }.
function KS.MarkedCopies()
  local out, me = {}, KS.CopyOwner()
  for guid, r in pairs(Marks() or {}) do
    if r.owner == me or r.owner == "account" then
      out[#out + 1] = { guid = guid, id = r.id, link = r.link, level = KS.Effective(r.level), where = r.where }
    end
  end
  return out
end

-- The level of buyback slot i's item, for the buyback rescue: a marked copy sold this session keeps its copy mark
-- (CopyTrack.lua remembers it); otherwise its item's mark as it applies to that copy (soulbound or not, from its
-- tooltip). The second value is the sold copy, when it's one.
function KS.BuybackLevel(i, id, link)
  local sold = KS.SoldCopy and KS.SoldCopy(id, link)
  if sold then return KS.WithSet(id, KS.Effective(sold.level)), sold end
  local own = KS.GetOwnLevel(id)
  if (own == MAIL or own == JUNK or own == DISENCHANT) and KS.BuybackBound(i) then
    return KS.WithSet(id, KS.SoulboundLevel(id, own))
  end
  return KS.GetLevel(id)
end

-- The level of the copy of item id that's on its way out of your bags: picked up (to destroy it), attached to a
-- mail or put in the trade window; its bag or equipment slot shows as locked meanwhile. With no such copy found,
-- the item's mark. KS.CopyBags: your bags and the reagent bag, and the bank's while it's open.
function KS.CopyBags()
  local bags = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = bag end
  local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if reagent then bags[#bags + 1] = reagent end
  if KS.IsBankOpen and KS.IsBankOpen() and KS.BankBags then
    for _, bag in ipairs(KS.BankBags()) do bags[#bags + 1] = bag end
  end
  return bags
end
function KS.LockedCopyLevel(id)
  if not id then return NORMAL end
  local best
  for _, bag in ipairs(KS.CopyBags()) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == id and info.isLocked then
        local level = KS.GetSlotLevel(bag, slot)
        if not best or level > best then best = level end
      end
    end
  end
  if GetInventoryItemID and IsInventoryItemLocked then
    for slot = 1, 19 do
      if GetInventoryItemID("player", slot) == id and IsInventoryItemLocked(slot) then
        local level = KS.LevelAt(id, KS.ItemLoc(nil, slot))
        if not best or level > best then best = level end
      end
    end
  end
  return best or KS.GetLevel(id)
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
