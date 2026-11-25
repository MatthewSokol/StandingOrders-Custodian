-- Custodian: keeps copy marks (Copies.lua) in step with the copies themselves.
--   * Where each marked copy is: after every change to your bags or equipped items, and in the bank while it's open.
--   * Soulbound: a BoE copy marked before it was soulbound loses its Junk, Mail or Disenchant mark once it is (you
--     equipped it). A soulbound copy whose item has a Mail mark, or a BoE item's soulbound copy whose item has any
--     mark, gets a copy mark of its own (the item's mark as it applies to it), so it stops following the item's mark.
--   * Selling: a marked copy that leaves your bags while a vendor is open is remembered for the session, so the
--     buyback rescue (Custodian.lua) knows its mark; bought back, it keeps it, even with a new item GUID.
--   * Clean-up, at login only (the buyback list is empty by then): this character's marked copies that left its bags
--     some other way (sold, destroyed, disenchanted, used up) and didn't come back lose their marks. Copies in the
--     bank are checked while it's open. Copies that went away by mail, the auction house or the guild bank keep
--     their marks for 60 days, in case they come back to one of your characters.

local KS = StandingOrdersCustodian
local L = KS.LEVELS
local KEEP_AWAY = 60 * 24 * 60 * 60
local open = {}      -- windows open now: merchant, mail, auction, guildbank, bank (bankClosed: when the bank closed)
local sold = {}      -- marked copies sold this session: { guid, id, key, level }
local returning = {} -- copies bought back, maybe with a new GUID: { guid, id, key }
local present = {}   -- the copy GUIDs the last pass saw
local queued = false

-- An item link's identity without the parts that change with who's looking (level, spec): item, enchant, gems,
-- suffix. Buyback links and bag links of one copy compare equal this way.
local function Key(link)
  local s = type(link) == "string" and link:match("item:([%-%d:]+)")
  if not s then return link end
  local parts = {}
  for field in (s .. ":"):gmatch("([^:]*):") do
    parts[#parts + 1] = field
    if #parts == 7 then break end
  end
  return table.concat(parts, ":")
end

local function Forget(list, guid)
  for k = #list, 1, -1 do
    if list[k].guid == guid then table.remove(list, k) end
  end
end

local function IsAccountBag(bag)
  local bi = Enum and Enum.BagIndex or {}
  for i = 1, 5 do
    if bi["AccountBankTab_" .. i] == bag then return true end
  end
  if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType and Enum.BankType.Account then
    local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Account)
    if ok and type(ids) == "table" then
      for _, b in ipairs(ids) do
        if b == bag then return true end
      end
    end
  end
  return false
end

-- Where a copy in this bag is: "bags" (your bags, the reagent bag, or equipped: bag nil) or "bank"; and whether
-- that's the warband bank (then any of your characters can take it out).
function KS.CopyPlace(bag)
  if bag == nil or (KS.IsPlayerBag and KS.IsPlayerBag(bag)) then return "bags", false end
  return "bank", IsAccountBag(bag)
end

-- How a marked copy that isn't where it was has left.
local function Departure(bankRead)
  if open.merchant then return "sold" end
  if open.mail or open.auction or open.guildbank then return "away" end
  if not bankRead and (open.bank or (open.bankClosed and GetTime() - open.bankClosed < 3)) then return "bank" end
  return "gone"
end

-- A copy bought back may come back with a new GUID: it takes the mark its old GUID had. Only a copy that wasn't in
-- your bags before (a twin that never left keeps its own).
local function Adopt(marks, guid, id, key)
  if #returning == 0 or present[guid] then return nil end
  for k, b in ipairs(returning) do
    if b.id == id and b.key == key and marks[b.guid] then
      table.remove(returning, k)
      marks[guid], marks[b.guid] = marks[b.guid], nil
      return marks[guid]
    end
  end
end

local function Short(links)
  local shown = table.concat(links, ", ", 1, math.min(#links, 5))
  if #links > 5 then shown = shown .. (" and %d more"):format(#links - 5) end
  return shown
end

-- One pass over your bags and equipped items, and the bank's while it's open. Returns the copy GUIDs it saw, or nil
-- when your bags can't be read yet.
function KS.ScanCopies()
  local marks = KS.CopyMarks()
  if not marks or (C_Container.GetContainerNumSlots(0) or 0) == 0 then return nil end
  local me, now = KS.CopyOwner(), time()
  local seen, guids, changed, made = {}, 0, {}, 0
  local all = next(marks) ~= nil or #returning > 0 -- else only bound copies whose item has a mark can matter
  local function visit(bag, slot)
    local id, link, count, isBound
    if bag then
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if not (info and info.itemID) then return end
      id, link, count, isBound = info.itemID, info.hyperlink, info.stackCount, info.isBound
    else
      id = GetInventoryItemID and GetInventoryItemID("player", slot)
      if not id then return end
      link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    end
    local own = KS.GetOwnLevel(id)
    if not all and (own == L.NORMAL or isBound == false) then return end
    local loc = KS.ItemLoc(bag, slot)
    local guid = KS.LocGUID(loc)
    if not guid then return end
    guids = guids + 1
    seen[guid] = true
    local r = marks[guid] or Adopt(marks, guid, id, Key(link))
    local where, account = KS.CopyPlace(bag)
    if r then
      r.where, r.owner, r.seen, r.left = where, account and "account" or me, now, nil
      r.link = link or r.link
      Forget(sold, guid)
      Forget(returning, guid)
      if not r.bound and KS.LocSoulbound(loc, isBound) then -- soulbound since it was marked
        r.bound = true
        local level = KS.SoulboundLevel(id, r.level)
        if level ~= r.level then r.level = level; changed[#changed + 1] = link or ("item:" .. id) end
      end
    elseif own ~= L.NORMAL and not KS.Stacks(id, count) and KS.LocSoulbound(loc, isBound) then
      local kind = KS.BindKind(id)
      if kind and (own == L.MAIL or kind == "boe") then -- it stops following its item's mark
        local level = KS.SoulboundLevel(id, own)
        marks[guid] = { id = id, link = link, level = level, bound = true, owner = account and "account" or me,
          where = where, seen = now }
        made = made + 1
        if level ~= own then changed[#changed + 1] = link or ("item:" .. id) end
      end
    end
  end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do visit(bag, slot) end
  end
  local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if reagent and reagent > (NUM_BAG_SLOTS or 4) then
    for slot = 1, (C_Container.GetContainerNumSlots(reagent) or 0) do visit(reagent, slot) end
  end
  for slot = 1, 19 do visit(nil, slot) end
  local bankRead = false
  if open.bank and KS.BankBags then
    for _, bag in ipairs(KS.BankBags()) do
      local n = C_Container.GetContainerNumSlots(bag) or 0
      if n > 0 then bankRead = true end
      for slot = 1, n do visit(bag, slot) end
    end
  end
  present = seen
  -- Marked copies that were here and aren't any more (only once GUIDs could be read at all).
  if guids > 0 then
    for guid, r in pairs(marks) do
      local mine = r.owner == me or (r.owner == "account" and bankRead)
      if not seen[guid] and mine and (r.where == "bags" or (bankRead and r.where == "bank")) then
        r.where, r.left, r.owner = Departure(bankRead), now, me
        if r.where == "sold" then sold[#sold + 1] = { guid = guid, id = r.id, key = Key(r.link), level = r.level } end
      end
    end
  end
  if #changed > 0 then
    KS.Notify("These copies are soulbound, so their item's Junk, Mail or Disenchant mark is off them (a mark you give them now stays): %s.", Short(changed))
  end
  if (#changed > 0 or made > 0) and KS.RefreshBagIcons then KS.RefreshBagIcons() end
  return seen
end

-- The marked copy sold this session that a buyback entry is: the latest with that item and link, or nil.
function KS.SoldCopy(id, link)
  local key = Key(link)
  for k = #sold, 1, -1 do
    if sold[k].id == id and sold[k].key == key then return sold[k] end
  end
end

-- The buyback rescue bought a sold copy back: it keeps its mark (by its old GUID, or its new one when it comes back
-- with another).
function KS.CopyBoughtBack(s)
  if not s then return end
  Forget(sold, s.guid)
  returning[#returning + 1] = { guid = s.guid, id = s.id, key = s.key }
end

-- At login: this character's marked copies that left its bags (sold, destroyed, used up) and aren't back, and copies
-- gone by mail or auction for more than 60 days, lose their marks.
local function CleanUp(seen)
  local marks, me, now, n = KS.CopyMarks(), KS.CopyOwner(), time(), 0
  for guid, r in pairs(marks) do
    local gone = r.owner == me and not seen[guid] and (r.where == "bags" or r.where == "sold" or r.where == "gone")
    local stale = r.where == "away" and now - (r.left or r.seen or now) > KEEP_AWAY
    if gone or stale then
      marks[guid] = nil
      n = n + 1
    end
  end
  if n > 0 and KS.Log then KS.Log("copy marks: took %d off copies that are gone", n) end
  return n
end

local function Queue(delay)
  if queued then return end
  queued = true
  C_Timer.After(delay or 0.3, function()
    queued = false
    KS.ScanCopies()
  end)
end

local OPENS = { MERCHANT_SHOW = "merchant", MAIL_SHOW = "mail", AUCTION_HOUSE_SHOW = "auction",
  BANKFRAME_OPENED = "bank", GUILDBANKFRAME_OPENED = "guildbank" }
local CLOSES = { MERCHANT_CLOSED = "merchant", MAIL_CLOSED = "mail", AUCTION_HOUSE_CLOSED = "auction",
  BANKFRAME_CLOSED = "bank", GUILDBANKFRAME_CLOSED = "guildbank" }
local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_SHOW",
  "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BANKFRAME_OPENED",
  "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" }) do
  pcall(f.RegisterEvent, f, event)
end
f:SetScript("OnEvent", function(_, event, isLogin)
  if event == "PLAYER_ENTERING_WORLD" then
    -- A while after login (not a /reload: the buyback list is still there), once your bags are surely loaded.
    C_Timer.After(10, function()
      local seen = KS.ScanCopies()
      if seen and isLogin == true then CleanUp(seen) end
    end)
  elseif OPENS[event] then
    open[OPENS[event]] = true
    Queue(0.5)
  elseif CLOSES[event] then
    KS.ScanCopies() -- what left while it was open counts as sold, sent or banked
    open[CLOSES[event]] = nil
    if event == "BANKFRAME_CLOSED" then open.bankClosed = GetTime() end
  else
    Queue()
  end
end)

KS.CopyCleanUp = CleanUp -- for the smoke test
