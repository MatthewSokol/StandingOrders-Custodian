-- Custodian: per-item protection levels that every item-losing action (selling, disenchanting,
-- destroying, trading, mailing) honors.
--
-- Levels (stored per item ID, account wide):
--   Junk     safe to get rid of (Standing Orders: Vendor sells these automatically when a vendor opens)
--   Mail     to be mailed to a bank character (for a mailing addon; Standing Orders: Vendor never sells these).
--   Auto-marks (on by default, /soc settings): grays and useless whites become Junk, crafting
--   materials and unbound BoE items become Mail, except items you got on purpose (see Auto-marks)
--   Normal   the default, stored as nil
--   Confirm  "temp hold": stopped like Locked, then a window asks whether to allow the action once
--   Locked   never sold, disenchanted, destroyed, traded or mailed until you lower it
--   On me    "Always on me": Locked, and also kept out of the bank (moved straight back to your bags)
--
-- Other addons: StandingOrdersCustodian.GetLevel(itemID), StandingOrdersCustodian.IsLocked(itemID), StandingOrdersCustodian.LEVELS, and
-- StandingOrdersCustodian.Guard(itemID, link, action), which shows the error and returns true when the action must stop.

local ADDON = ...
local KS = {}
_G.StandingOrdersCustodian = KS
-- Its name before 0.2.1 (Standing Orders: Quartermaster). Standing Orders: Vendor, Mail and the Standing Orders
-- config addon still look for this one until they're updated; drop it once none of them do.
_G.StandingOrdersQuartermaster = KS
-- The addon icon (Icon.tga, the ledger): the AddOn List, the settings panel, the intro and the hold window.
KS.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Icon"

-- Mail sits between Junk and Normal. It's 1.5 rather than renumbering, so saved marks and addons that
-- compare against the old numbers (Standing Orders: Vendor: Normal 2, Confirm 3) keep working.
local JUNK, MAIL, NORMAL, CONFIRM, LOCK, ONME = 1, 1.5, 2, 3, 4, 5
KS.LEVELS = { JUNK = JUNK, MAIL = MAIL, NORMAL = NORMAL, CONFIRM = CONFIRM, LOCK = LOCK, ONME = ONME }
-- Confirm (a temp hold that asks before allowing an action once) is held back from the first release: its
-- "Allow once" didn't let a sale through in testing (BACKLOG.md). While it's off, nothing offers it, and a
-- saved Confirm mark or set choice counts as Locked; the saved data keeps the 3, so turning it back on
-- restores those marks as they were.
local CONFIRM_ENABLED = false
KS.CONFIRM_ENABLED = CONFIRM_ENABLED
local function Effective(level) return (level == CONFIRM and not CONFIRM_ENABLED) and LOCK or level end
local ORDER = CONFIRM_ENABLED and { JUNK, MAIL, NORMAL, CONFIRM, LOCK, ONME } -- lowest to highest protection
  or { JUNK, MAIL, NORMAL, LOCK, ONME }
local CONFIRM_LATER = "Confirm is coming in a later version; use Locked (lock) for now."

local NAMES = { [JUNK] = "Junk", [MAIL] = "Mail", [NORMAL] = "Normal", [CONFIRM] = "Confirm", [LOCK] = "Locked", [ONME] = "Always on me" }
local COLORS = { [JUNK] = "ff9d9d9d", [MAIL] = "ff4fb3ff", [NORMAL] = "ffffffff", [CONFIRM] = "ffffd100", [LOCK] = "ffff4040", [ONME] = "ffc069ff" }
local ICONS = {
  [JUNK] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
  [MAIL] = "Interface\\Icons\\INV_Letter_15",
  [CONFIRM] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  [LOCK] = "Interface\\Icons\\INV_Misc_Key_03",
  [ONME] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", -- purple diamond
}
-- The lowest level each action is blocked at. Anything not listed (sell, disenchant, destroy, trade,
-- mail, ...) is blocked from Confirm up.
local GUARD_FROM = { bank = ONME }
-- Spells that destroy the item you click: Disenchant, Prospecting, Milling (ignored if the client lacks them).
local DESTRUCTIVE_SPELLS = { 13262, 31252, 51005 }
local DELETE_POPUPS = { DELETE_ITEM = true, DELETE_GOOD_ITEM = true, DELETE_QUEST_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

local C = C_Container
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local IsCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
local NUM_BAGS = NUM_BAG_SLOTS or 4

local db
local mechanic -- MechanicLib, when the optional Mechanic dev tool is installed
local merchantOpen = false
local bankOpen = false
function KS.IsBankOpen() return bankOpen end

---------------------------------------------------------------------------------------------------
-- Output

local function Print(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Standing Orders|r: " .. msg)
end

local function Debug(msg, ...)
  if db and db.debug then Print("|cff888888[debug]|r " .. msg, ...) end
end

-- Always-on log of guard decisions, kept in SavedVariables (StandingOrdersCustodianDB.log) so a miss can be
-- diagnosed after /reload. Also echoed to chat with /soc debug.
local function Log(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  if db then
    db.log = db.log or {}
    table.insert(db.log, date("%m-%d %H:%M:%S ") .. msg)
    while #db.log > 200 do table.remove(db.log, 1) end
  end
  Debug(msg)
  if mechanic then mechanic:Log(ADDON, msg, mechanic.Categories and mechanic.Categories.CORE) end
end

local function Err(msg)
  UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2)
  Print("|cffff4040%s|r", msg)
end

local function LinkID(link) return link and tonumber(link:match("item:(%d+)")) end

local function ItemLink(id) return select(2, GetItemInfo(id)) or ("item:" .. id) end

local function LevelText(level)
  local text = "|c" .. COLORS[level] .. NAMES[level] .. "|r" -- pipes:ok (a color code)
  return text
end
KS.LevelText = LevelText

---------------------------------------------------------------------------------------------------
-- Levels and the guard every action goes through

-- Marks are account wide (StandingOrdersCustodianDB.items) or for one character (StandingOrdersCustodianCharDB.items). A character mark
-- wins, so a character can also override an account-wide mark (stored as Normal to clear it there).
local cdb -- StandingOrdersCustodianCharDB
local setLevelOf, setNameOf = {}, {} -- equipment sets: itemID -> level and set name (see Equipment sets)

function KS.GetLevel(id)
  if not id then return NORMAL end
  local level = Effective((cdb and cdb.items[id]) or (db and db.items[id]) or NORMAL)
  local fromSet = setLevelOf[id]
  return (fromSet and fromSet > level) and fromSet or level
end

-- "char" when this character has its own mark for the item, "account" for an account-wide one, else nil.
function KS.GetItemScope(id)
  if id and cdb and cdb.items[id] then return "char" end
  if id and db and db.items[id] then return "account" end
end

-- Where new marks go (Alt+Click, /soc <level> <item>): "account" (default) or "char".
function KS.GetScope() return (db and db.scope) or "account" end
function KS.SetScope(scope)
  db.scope = (scope == "char") and "char" or "account"
end

local function ScopeText(scope)
  return scope == "char" and " |cff9d9d9d(this character)|r" or ""
end

-- True when the item must not leave your bags without you lowering its level first.
function KS.IsLocked(id) return KS.GetLevel(id) >= CONFIRM end

local RefreshBags -- defined with the bag hooks below

-- Per-character items: consumables, spell reagents (ankhs, feathers, powders...) and trade goods that
-- vendors sell (thread, vials, flux, dyes, salt, spices...). Each character keeps its own stock of
-- these, so they're never auto-marked, and a mark on one stays on that character unless you ask for
-- all characters (/soc <level> <item> account, or Alt+Shift+Left-click).
local ITEM_CLASS = (Enum and Enum.ItemClass) or {}
local CLASS_CONSUMABLE = ITEM_CLASS.Consumable or 0
local CLASS_REAGENT = ITEM_CLASS.Reagent or 5
local CLASS_TRADEGOODS = ITEM_CLASS.Tradegoods or 7
-- Vendor trade goods known up front; the rest are learned from every vendor you open (StandingOrdersCustodianDB.vendorMats).
local VENDOR_MATS = {}
for _, id in ipairs({
  2320, 2321, 4291, 8343, 14341,             -- Coarse, Fine, Silken, Heavy Silken, Rune Thread
  3371, 3372, 8925, 18256,                   -- Empty, Leaded, Crystal, Imbued Vial
  2880, 3466,                                -- Weak, Strong Flux
  4289, 2324,                                -- Salt, Bleach
  2325, 2604, 2605, 4340, 4341, 4342, 6260, 6261, 10290, -- dyes
  2678, 2692, 3713,                          -- Mild, Hot, Soothing Spices
  6217, 4470, 3857, 4399, 4400,              -- Copper Rod, Simple Wood, Coal, Wooden Stock, Heavy Stock
}) do VENDOR_MATS[id] = true end

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local function ItemClass(id)
  if GetInstant then return select(6, GetInstant(id)) end
  return select(12, GetItemInfo(id))
end

function KS.IsVendorMat(id)
  return (VENDOR_MATS[id] or (db and db.vendorMats and db.vendorMats[id])) and true or false
end

function KS.IsPersonal(id)
  if not id then return false end
  local class = ItemClass(id)
  if class == CLASS_CONSUMABLE or class == CLASS_REAGENT then return true end
  return class == CLASS_TRADEGOODS and KS.IsVendorMat(id)
end

-- opts (optional): { scope = "account"|"char", quiet = true }. The old third-argument link still works.
function KS.SetLevel(id, level, link, opts)
  if not id then return end
  level = Effective(level) -- another addon asking for Confirm while it's off gets Locked
  opts = opts or {}
  local scope = opts.scope or (KS.IsPersonal(id) and "char") or KS.GetScope()
  if scope == "char" then
    -- Normal only needs storing here when it has to override an account-wide mark.
    cdb.items[id] = (level ~= NORMAL or db.items[id]) and level or nil
  else
    db.items[id] = (level ~= NORMAL) and level or nil
    cdb.items[id] = nil -- an account-wide change replaces this character's own mark
  end
  if not opts.quiet then
    Print("%s is now %s%s.", link or ItemLink(id), LevelText(level), ScopeText(scope))
    if KS.GetLevel(id) > level and setNameOf[id] then
      Print("It stays %s while it's in the equipment set \"%s\" (/soc sets).", LevelText(KS.GetLevel(id)), setNameOf[id])
    end
  end
  RefreshBags()
end

-- Moves an item's mark between account wide and this character only (Alt+Shift+Click).
function KS.ToggleItemScope(id, link)
  link = link or ItemLink(id)
  local mine, shared = cdb.items[id], db.items[id]
  if mine then
    db.items[id] = (mine ~= NORMAL) and mine or nil
    cdb.items[id] = nil
    Print("%s is now %s for all characters.", link, LevelText(KS.GetLevel(id)))
  elseif shared then
    cdb.items[id] = shared
    db.items[id] = nil
    Print("%s is now %s%s; your other characters no longer have it marked.", link, LevelText(Effective(shared)), ScopeText("char"))
  else
    Print("%s isn't marked. Alt+Click it first.", link)
    return
  end
  RefreshBags()
end

-- The one check for any action that would lose an item. Returns true (and shows the error) when the
-- item is locked, so callers just do: if StandingOrdersCustodian.Guard(id, link, "sell") then <undo or block> end
-- Some actions are only blocked at higher levels (banking: Always on me only).
-- Confirm ("temp hold") items: the action is still stopped first, then a window asks whether to allow
-- it once. "Allow once" gives the item a pass and you do the action again. A pass is used up by one
-- disenchant or destroy within PASS_TIME; for selling, trading and mailing it lasts until that window
-- closes (the buyback and mail checks run again while it's open).
local PASS_TIME = 120
local WINDOW_OF = { sell = "merchant", trade = "trade", mail = "mail" }
local VERB = { sell = "sold", trade = "traded", mail = "mailed", destroy = "destroyed", disenchant = "disenchanted",
  prospect = "prospected", mill = "milled" }
local passes = {} -- itemID -> { expires = GetTime(), window = "merchant"|"trade"|"mail"|nil }

-- True when the item has a pass for this action. peek: just look (the disenchant blocker), don't use it.
local function UsePass(id, action, peek)
  local p = passes[id]
  if not p or (not p.window and GetTime() > p.expires) then return false end
  if peek then return true end
  local window = WINDOW_OF[action]
  if window then p.window = window else passes[id] = nil end
  Log("pass used: %s of item %d", action, id)
  return true
end

function KS.ClearPasses(window)
  for id, p in pairs(passes) do
    if p.window == window then passes[id] = nil end
  end
end

local function AskToAllow(id, link, action)
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs.SOC_CONFIRM = StaticPopupDialogs.SOC_CONFIRM or {
    text = "|T" .. KS.ICON .. ":32:32|t\n%s is on hold.\n\nAllow it to be %s once? Then do it again.", -- pipes:ok (an inline texture)
    button1 = "Allow once", button2 = "Keep it",
    OnAccept = function(_, data)
      passes[data.id] = { expires = GetTime() + PASS_TIME }
      Print("%s: allowed once. Do it again within 2 minutes.", data.link)
      Log("pass given: %s of item %d", data.action, data.id)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show("SOC_CONFIRM", link, VERB[action] or "used up", { id = id, link = link, action = action })
end

function KS.Guard(id, link, action)
  local level = KS.GetLevel(id)
  if level < (GUARD_FROM[action] or CONFIRM) then return false end
  link = link or ItemLink(id)
  if level == CONFIRM and UsePass(id, action) then return false end
  if level == CONFIRM then
    Err(("%s is on hold (Confirm)."):format(link))
    AskToAllow(id, link, action)
  else
    local how = (action == "bank") and "Lower it to Locked to bank it (Alt+Right-click it in your bags)"
      or ("Lower it to Normal to %s it (Alt+Right-click it in your bags, or /soc normal <item>)"):format(action)
    Err(("%s is %s. %s."):format(link, NAMES[level], how))
  end
  Log("blocked %s of item %d (level %s)", action, id, NAMES[level])
  return true
end
KS.HasPass = function(id) return UsePass(id, nil, true) end

-- One-time move of levels kept by SellAll 1.0 betas (SellAllDB.items). Existing Custodian levels win.
-- Returns how many items were brought over.
function KS.ImportLevels(items)
  if type(items) ~= "table" or not db then return 0 end
  local n = 0
  for id, level in pairs(items) do
    if type(id) == "number" and NAMES[level] and level ~= NORMAL and db.items[id] == nil then
      db.items[id] = level
      n = n + 1
    end
  end
  if n > 0 then
    Log("imported %d item levels from SellAll", n)
    RefreshBags()
  end
  return n
end

---------------------------------------------------------------------------------------------------
-- Equipment sets: every item in one of this character's equipment sets (the game's equipment manager)
-- is protected at that set's level: Confirm, Locked or Always on me. Each set uses its own choice
-- (StandingOrdersCustodianCharDB.sets[setID]) or the default for sets (StandingOrdersCustodianDB.setDefault, Locked unless changed); "off"
-- turns it off. It's a layer on top of marks: an item's level is the higher of its mark and its sets',
-- and an item taken out of a set loses that protection by itself. Marks are never written.

local SET_LEVELS = { confirm = CONFIRM_ENABLED and CONFIRM or nil, lock = LOCK, locked = LOCK, onme = ONME, always = ONME }

function KS.GetSetDefault() return Effective((db and db.setDefault) or LOCK) end
function KS.GetSetChoice(setID) return Effective((cdb and cdb.sets[setID]) or "default") end

local function LevelForSet(setID)
  local choice = KS.GetSetChoice(setID)
  if choice == "default" then choice = KS.GetSetDefault() end
  return choice ~= "off" and choice or nil
end

-- This character's equipment sets: { { id, name }, ... }, empty when the client has none.
function KS.EquipmentSets()
  local list, E = {}, C_EquipmentSet
  if not (E and E.GetEquipmentSetIDs and E.GetEquipmentSetInfo) then return list end
  local ok, ids = pcall(E.GetEquipmentSetIDs)
  for _, setID in ipairs(ok and ids or {}) do
    local name = E.GetEquipmentSetInfo(setID)
    if name then list[#list + 1] = { id = setID, name = (name:gsub("|", "||")) } end -- pipes:ok (escapes | in set names)
  end
  return list
end

function KS.RefreshSets()
  wipe(setLevelOf)
  wipe(setNameOf)
  local E = C_EquipmentSet
  for _, set in ipairs(KS.EquipmentSets()) do
    local level = LevelForSet(set.id)
    local ok, items = pcall(E.GetItemIDs, set.id)
    local ignored = E.GetIgnoredSlots and select(2, pcall(E.GetIgnoredSlots, set.id))
    for slot, itemID in pairs(level and ok and type(items) == "table" and items or {}) do
      if type(itemID) == "number" and itemID > 1 and not (type(ignored) == "table" and ignored[slot])
          and level > (setLevelOf[itemID] or 0) then
        setLevelOf[itemID], setNameOf[itemID] = level, set.name
      end
    end
  end
  RefreshBags()
end

-- The set name and level that protect an item, if any.
function KS.GetSetProtection(id) return setNameOf[id], setLevelOf[id] end

-- choice: "default", "off", or a level. setID nil sets the default for sets ("default" not allowed).
function KS.SetSetChoice(setID, choice)
  if setID then cdb.sets[setID] = (choice ~= "default") and choice or nil
  elseif choice ~= "default" then db.setDefault = choice end
  KS.RefreshSets()
end

function KS.SetChoiceText(choice)
  if choice == "off" then return "|cff9d9d9dnot protected|r" end
  if choice == "default" then return "default (" .. KS.SetChoiceText(KS.GetSetDefault()) .. ")" end
  return LevelText(choice)
end

local function ListSets()
  local sets = KS.EquipmentSets()
  Print("Equipment sets protect their items. Default for sets: %s.", KS.SetChoiceText(KS.GetSetDefault()))
  if #sets == 0 then print("  This character has no equipment sets.") end
  for _, set in ipairs(sets) do print(("  %s: %s"):format(set.name, KS.SetChoiceText(KS.GetSetChoice(set.id)))) end
end

-- /soc sets [default] <confirm||lock||onme||off> or /soc set <name> <default||confirm||lock||onme||off>
local function SetsCommand(rest)
  local target, word = rest:match("^(.-)%s*(%a+)$")
  local w = word and word:lower()
  if w == "confirm" and not CONFIRM_ENABLED then return Err(CONFIRM_LATER) end
  local choice = (w == "off" or w == "default") and w or SET_LEVELS[w or ""]
  if rest == "" or not choice then return ListSets() end
  if target == "" or target:lower() == "default" then
    if choice == "default" then
      return Err(CONFIRM_ENABLED and "The default for sets can be confirm, lock, onme or off." or "The default for sets can be lock, onme or off.")
    end
    KS.SetSetChoice(nil, choice)
    return Print("Default for equipment sets: %s.", KS.SetChoiceText(choice))
  end
  for _, set in ipairs(KS.EquipmentSets()) do
    if set.name:lower() == target:lower() then
      KS.SetSetChoice(set.id, choice)
      return Print("Equipment set \"%s\": %s.", set.name, KS.SetChoiceText(choice))
    end
  end
  Err(("No equipment set called \"%s\" on this character (/soc sets lists them)."):format(target))
end
KS.SetsCommand = SetsCommand


---------------------------------------------------------------------------------------------------
-- Guard: vendor. Selling can't be blocked before it happens (right-click, drag to vendor, other
-- addons' auto-sell), so any locked item that lands in the buyback list is bought straight back.
-- One per pass, with a pause, so a stale list can never make us buy back the wrong slot.

local rescuing = false

local function RescueBuyback()
  if rescuing or not merchantOpen then return end
  for i = GetNumBuybackItems(), 1, -1 do
    local link = GetBuybackItemLink(i)
    local id = LinkID(link)
    if id and KS.IsLocked(id) then
      rescuing = true
      KS.Guard(id, link, "sell")
      Print("Bought %s back.", link)
      BuybackItem(i)
      C_Timer.After(0.7, function()
        rescuing = false
        RescueBuyback()
      end)
      return
    end
  end
end

local rescueQueued = false
local function QueueRescue()
  if rescueQueued then return end
  rescueQueued = true
  C_Timer.After(0.2, function()
    rescueQueued = false
    RescueBuyback()
  end)
end

---------------------------------------------------------------------------------------------------
-- Guard: bank. Like selling, putting an item in the bank can't be blocked beforehand (right-click,
-- dragging, a bag-sort or auto-deposit addon), so any Always on me item found in the bank while it's
-- open is moved straight back to your bags. One per pass, with a pause, like the buyback.

-- The player's own bags (never treated as bank): backpack, bags and the reagent bag.
local function IsPlayerBag(b)
  local bi = Enum and Enum.BagIndex
  return (b >= 0 and b <= NUM_BAGS) or (bi and b == bi.ReagentBag) or false
end

-- Every bank container. Forever's bank is tabs (each its own container) listed by C_Bank, like
-- retail; the old Classic IDs (-1, bank bag slots) are only used when the client has no tabs.
local function BankBags()
  local bags, seen = {}, {}
  local function add(b)
    if type(b) == "number" and not seen[b] and not IsPlayerBag(b) then
      seen[b] = true
      bags[#bags + 1] = b
    end
  end
  local bi = Enum and Enum.BagIndex or {}
  if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType then
    for _, kind in ipairs({ Enum.BankType.Character, Enum.BankType.Account }) do
      local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, kind)
      if ok and type(ids) == "table" then
        for _, id in ipairs(ids) do add(id) end
      end
    end
  end
  for i = 1, 6 do add(bi["CharacterBankTab_" .. i]) end
  for i = 1, 5 do add(bi["AccountBankTab_" .. i]) end
  add(bi.Bank)
  add(bi.Reagentbank)
  for i = 1, 7 do add(bi["BankBag_" .. i]) end
  if #bags == 0 then
    add(BANK_CONTAINER or -1)
    local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAGS) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(b) end
  end
  return bags
end

-- Puts the item on the cursor into the first normal player bag with room. True when it landed.
local function PutInBags()
  for bag = 0, NUM_BAGS do
    local free, bagType = C.GetContainerNumFreeSlots(bag)
    if free and free > 0 and (bagType == 0 or bagType == nil) then
      if bag == 0 then
        PutItemInBackpack()
      else
        PutItemInBag(C.ContainerIDToInventoryID(bag))
      end
      if not GetCursorInfo() then return true end
    end
  end
  return false
end

local bankRescuing = false
local warnedFull = {}

local function RescueBank()
  if bankRescuing or not bankOpen then return end
  if GetCursorInfo() then return end -- wait until you've let go of whatever you're holding
  local bags, slots, busy = BankBags(), 0, false
  for _, bag in ipairs(bags) do
    for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
      slots = slots + 1
      local info = C.GetContainerItemInfo(bag, slot)
      if info and info.itemID and info.isLocked and KS.GetLevel(info.itemID) >= ONME then
        busy = true -- still moving into the bank: look again shortly
      elseif info and info.itemID and KS.GetLevel(info.itemID) >= ONME then
        C.PickupContainerItem(bag, slot)
        if not PutInBags() then
          ClearCursor() -- puts it back where it was
          if not warnedFull[info.itemID] then
            warnedFull[info.itemID] = true
            Err(("%s is Always on me, but your bags are full so it can't come back out of the bank.")
              :format(info.hyperlink))
          end
          Log("no bag room to move item %d out of the bank", info.itemID)
          return
        end
        warnedFull[info.itemID] = nil
        KS.Guard(info.itemID, info.hyperlink, "bank")
        Print("Moved %s back to your bags.", info.hyperlink)
        bankRescuing = true
        C_Timer.After(0.5, function()
          bankRescuing = false
          RescueBank()
        end)
        return
      end
    end
  end
  Debug("bank scan: %d containers (%s), %d slots, nothing to move", #bags, table.concat(bags, ","), slots)
  if busy then
    bankRescuing = true
    C_Timer.After(0.5, function()
      bankRescuing = false
      RescueBank()
    end)
  end
end

local bankQueued = false
local function QueueBankRescue()
  if bankQueued or not bankOpen then return end
  bankQueued = true
  C_Timer.After(0.2, function()
    bankQueued = false
    RescueBank()
  end)
end

---------------------------------------------------------------------------------------------------
-- Guard: disenchant / prospect / mill (cancel the targeting cursor before the click lands)

-- IsCurrentSpell alone isn't reliable while a spell waits for its target, so we also remember what
-- started the targeting cursor: every way to cast (action bar, macro, /cast, spellbook) or use an
-- item (oils, scrolls) is hooked. When we can't tell, a protected item stays protected.

local castRecord        -- { kind = "spell"|"item"|"craft"|"other", id, name, time }
local targetStart = -1  -- GetTime() when the current targeting cursor appeared
local wasTargeting = false
local destructiveNames  -- localized spell name (lower case) -> spell ID, built on first use

local function SpellNameAndID(spell)
  if spell == nil then return end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(spell)
    if info then return info.name, info.spellID end
  elseif GetSpellInfo then
    local name, _, _, _, _, _, id = GetSpellInfo(spell)
    return name, id
  end
end

local function IsDestructive(id, name)
  if id then
    for _, d in ipairs(DESTRUCTIVE_SPELLS) do
      if d == id then return true, d end
    end
  end
  if not destructiveNames then
    destructiveNames = {}
    for _, d in ipairs(DESTRUCTIVE_SPELLS) do
      local n = SpellNameAndID(d)
      if n then destructiveNames[n:lower()] = d end
    end
  end
  local d = name and destructiveNames[name:lower()]
  return d ~= nil, d
end

local function Record(kind, spell)
  local name, id
  if kind == "spell" then
    name, id = SpellNameAndID(spell)
    if not name and type(spell) == "string" then name = spell end
    if not id and type(spell) == "number" then id = spell end
  end
  castRecord = { kind = kind, id = id, name = name, time = GetTime() }
  if kind == "spell" then
    Log("cast/use recorded: spell %s %s", tostring(name), tostring(id))
  else
    Log("cast/use recorded: %s", kind)
  end
end

local function HookCasts()
  hooksecurefunc("CastSpellByName", function(spell)
    if type(spell) ~= "string" then return end
    spell = spell:gsub("^!", "")
    spell = spell:gsub("%s*%(.-%)%s*$", "") -- drop "(Rank 1)"
    Record("spell", spell)
  end)
  if CastSpellByID then hooksecurefunc("CastSpellByID", function(id) Record("spell", id) end) end
  if CastSpell then
    hooksecurefunc("CastSpell", function(index, book)
      local id
      if GetSpellBookItemInfo then
        local ok, _, sid = pcall(GetSpellBookItemInfo, index, book)
        if ok then id = sid end
      end
      Record("spell", id)
    end)
  end
  if C_SpellBook and C_SpellBook.CastSpellBookItem then
    hooksecurefunc(C_SpellBook, "CastSpellBookItem", function(slot, bank)
      local info = C_SpellBook.GetSpellBookItemInfo and C_SpellBook.GetSpellBookItemInfo(slot, bank)
      Record("spell", info and (info.spellID or info.actionID))
    end)
  end
  hooksecurefunc("UseAction", function(slot)
    local t, id = GetActionInfo(slot)
    if t == "spell" then
      Record("spell", id)
    elseif t == "macro" then
      -- The macro's own /cast or /use was already recorded inside this call; only add the spell
      -- when the macro reports one.
      local sid = GetMacroSpell and GetMacroSpell(id)
      if sid then Record("spell", sid) end
    elseif t == "item" then
      Record("item")
    end
  end)
  hooksecurefunc(C, "UseContainerItem", function() Record("item") end)
  if UseItemByName then hooksecurefunc("UseItemByName", function() Record("item") end) end
  if C_Item and C_Item.UseItemByName then hooksecurefunc(C_Item, "UseItemByName", function() Record("item") end) end
  -- Enchanting from the profession window targets an item too, and is allowed on locked items.
  if DoCraft then hooksecurefunc("DoCraft", function() Record("craft") end) end
  if DoTradeSkill then hooksecurefunc("DoTradeSkill", function() Record("craft") end) end
  if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
    hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function() Record("craft") end)
  end
end

local function OnSpellCastChanged()
  local now = SpellIsTargeting()
  if now and not wasTargeting then targetStart = GetTime() end
  wasTargeting = now
end

-- What the targeting cursor will do to the item you click: "destructive", "safe" or "unknown".
local function TargetingKind()
  if IsCurrentSpell then
    for _, d in ipairs(DESTRUCTIVE_SPELLS) do
      if IsCurrentSpell(d) then return "destructive", d, "IsCurrentSpell" end
    end
  end
  local r = castRecord
  -- The record counts only if it came from the cast that put this cursor up (same moment).
  if r and math.abs(r.time - targetStart) <= 1 then
    if r.kind == "spell" then
      local destructive, d = IsDestructive(r.id, r.name)
      if destructive then return "destructive", d, "recorded cast" end
      return "safe", r.id, "recorded cast"
    elseif r.kind == "item" or r.kind == "craft" then
      return "safe", nil, "recorded " .. r.kind
    end
  end
  return "unknown", nil, "no matching cast"
end

---------------------------------------------------------------------------------------------------
-- Guard: destroy (hide the delete confirmation and put the item back)

local function HookDestroy()
  if not StaticPopup_Show then return end
  hooksecurefunc("StaticPopup_Show", function(which)
    if not DELETE_POPUPS[which] then return end
    local kind, id, link = GetCursorInfo()
    if kind == "item" and KS.Guard(id, link, "destroy") then
      StaticPopup_Hide(which)
      ClearCursor()
    end
  end)
end

---------------------------------------------------------------------------------------------------
-- Guard: trade and mail (take a locked item back out as soon as it's put in)

local function CheckTrade(slot)
  local link = GetTradePlayerItemLink(slot)
  if link and KS.Guard(LinkID(link), link, "trade") then
    ClearCursor()
    ClickTradeButton(slot) -- picks the item up off the trade window...
    ClearCursor()          -- ...and drops it back in your bags
  end
end

local function CheckMail()
  for i = 1, ATTACHMENTS_MAX_SEND or 12 do
    local link = GetSendMailItemLink(i)
    if link and KS.Guard(LinkID(link), link, "mail") then
      ClickSendMailItemButton(i, true) -- true = remove the attachment
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Bag buttons: level icons, Alt+Click to change levels, and the disenchant guard

local hooked = setmetatable({}, { __mode = "k" })
local hookedCount = 0

-- Bag addons (Adapters.lua): each adapter hands Custodian another bag addon's item buttons and answers, per
-- button, which real bag and slot it shows, or nil when that view isn't live or can't be trusted.
-- An adapter is { name, loaded = fn() -> bool, hook = fn(add), slot = fn(btn) -> bag, slot }.
local bagAddons = {}
function KS.AddBagAddon(adapter) bagAddons[#bagAddons + 1] = adapter end

local function ButtonSlot(btn)
  if btn.favesAdapter then return btn.favesAdapter.slot(btn) end
  if btn.GetBagID then return btn:GetBagID(), btn:GetID() end
  local parent = btn:GetParent()
  return parent and parent:GetID(), btn:GetID()
end

-- Mark icons: how much of the item button they cover, where they sit, and how opaque they are, so
-- they don't hide counts and other addons' text. Account-wide (StandingOrdersCustodianDB.icon).
-- size: the icon's side as a % of the item button's width (40% of the width covers 16% of the area).
local ICON_DEFAULTS = { size = 40, anchor = "BOTTOMLEFT", alpha = 75 }
local ICON_ANCHORS = { "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "CENTER" }
local ANCHOR_TEXT = { BOTTOMLEFT = "Bottom left", TOPLEFT = "Top left", TOPRIGHT = "Top right",
  BOTTOMRIGHT = "Bottom right", CENTER = "Center" }
local ANCHOR_OFFSET = { BOTTOMLEFT = { 1, 1 }, TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMRIGHT = { -1, 1 }, CENTER = { 0, 0 } }
KS.ICON_ANCHORS, KS.ANCHOR_TEXT = ICON_ANCHORS, ANCHOR_TEXT

function KS.GetIconStyle()
  local st = db and db.icon or ICON_DEFAULTS
  return st.size, st.anchor, st.alpha
end

-- key is "size" or "alpha" (percent, 10-100, in steps of 5) or "anchor" (one of ICON_ANCHORS).
function KS.SetIconStyle(key, value)
  if not (db and db.icon) then return false end
  if key == "size" or key == "alpha" then
    value = tonumber(value)
    if not value then return false end
    value = math.max(10, math.min(100, math.floor(value / 5 + 0.5) * 5))
  elseif key ~= "anchor" or not ANCHOR_TEXT[value] then
    return false
  end
  db.icon[key] = value
  RefreshBags()
  return true
end

-- Pixel size, point, x, y and alpha of the mark icon on a button of width w.
function KS.IconLayout(w)
  local size, anchor, alpha = KS.GetIconStyle()
  w = (type(w) == "number" and w > 0) and w or 37
  local off = ANCHOR_OFFSET[anchor] or ANCHOR_OFFSET.BOTTOMLEFT
  return math.max(6, w * size / 100), anchor, off[1], off[2], alpha / 100
end

function KS.StyleIcon(tex, btn)
  local px, point, x, y, alpha = KS.IconLayout(btn.GetWidth and btn:GetWidth())
  tex:SetSize(px, px)
  tex:ClearAllPoints()
  tex:SetPoint(point, btn, point, x, y)
  tex:SetAlpha(alpha)
end

local function UpdateButton(btn)
  local bag, slot = ButtonSlot(btn)
  local info = bag and slot and C.GetContainerItemInfo(bag, slot)
  local icon = ICONS[info and KS.GetLevel(info.itemID) or NORMAL]
  local tex = btn.favesIcon
  if icon then
    if not tex then
      tex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
      btn.favesIcon = tex
    end
    KS.StyleIcon(tex, btn)
    tex:SetTexture(icon)
    tex:Show()
  elseif tex then
    tex:Hide()
  end
end

local function PreClick(btn, mouse)
  btn.favesHandled = nil
  local bag, slot = ButtonSlot(btn)
  local info = bag and slot and C.GetContainerItemInfo(bag, slot)
  if not info or not info.itemID then return end

  -- Alt+Shift+Left-click moves the mark between all characters and this character only.
  if IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown() and mouse == "LeftButton" then
    btn.favesHandled, btn.favesCursorEmpty = true, GetCursorInfo() == nil
    KS.ToggleItemScope(info.itemID, info.hyperlink)
    return
  end

  -- Alt+Left-click raises protection (Junk > Mail > Normal > Confirm > Locked > Always on me);
  -- Alt+Right-click lowers it.
  if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
    local cur = KS.GetLevel(info.itemID)
    local i = 3
    for n, level in ipairs(ORDER) do if level == cur then i = n end end
    i = math.max(1, math.min(#ORDER, i + (mouse == "LeftButton" and 1 or -1)))
    local new = ORDER[i]
    btn.favesHandled, btn.favesCursorEmpty = true, GetCursorInfo() == nil
    if new == cur then
      Print("%s is already %s.", info.hyperlink, LevelText(cur))
    else
      KS.SetLevel(info.itemID, new, info.hyperlink)
    end
    return
  end

  if SpellIsTargeting() then
    local kind, spellID, how = TargetingKind()
    Log("targeting click on %s (%s): %s, spell %s, via %s", info.hyperlink, NAMES[KS.GetLevel(info.itemID)],
      kind, tostring(spellID), how)
    if kind == "safe" then return end
    local action = "use that spell on"
    if spellID == 13262 then action = "disenchant"
    elseif spellID == 31252 then action = "prospect"
    elseif spellID == 51005 then action = "mill" end
    -- No SpellStopTargeting(): it's protected on this client (ADDON_ACTION_FORBIDDEN). The click is
    -- still eaten; Esc or right-click ends the targeting cursor.
    if KS.Guard(info.itemID, info.hyperlink, action) then
      btn.favesHandled, btn.favesCursorEmpty = true, GetCursorInfo() == nil
    end
  end
end

local function PostClick(btn)
  -- If the default click went on to pick the item up, put it back.
  if btn.favesHandled and btn.favesCursorEmpty and GetCursorInfo() then ClearCursor() end
  btn.favesHandled = nil
end

local function HookButton(btn)
  if hooked[btn] then return end
  hooked[btn] = true
  hookedCount = hookedCount + 1
  btn:HookScript("PreClick", PreClick)
  btn:HookScript("PostClick", PostClick)
end

local function UpdateFrame(frame)
  -- Hook even while hidden: the default UI can fill a bag frame just before showing it.
  if not (frame and frame.EnumerateValidItems) then return end
  -- On Forever the enumerator can yield empty slots (nil): skip them rather than stop with an error.
  for _, btn in frame:EnumerateValidItems() do
    if type(btn) == "table" then
      HookButton(btn)
      UpdateButton(btn)
    end
  end
end

-- Not ContainerFrameUtil_EnumerateContainerFrames: it builds its list lazily, and building it from
-- addon code taints it.
local function BagFrames()
  local frames = {}
  if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local f = _G["ContainerFrame" .. i]
    if f then frames[#frames + 1] = f end
  end
  return frames
end

-- Hooks each loaded bag addon once; its adapter hands buttons over with add(button). A failing adapter
-- only switches itself off.
-- Some bag addons lay another frame over the item button that takes some clicks itself (AdiBags on Forever:
-- a secure right-click button). adapter.clickFrames(btn) names them; their Alt+clicks count as the item
-- button's. Only Alt+clicks, so a plain right-click (use the item) or one during targeting is untouched.
local overlayHooked = setmetatable({}, { __mode = "k" })
local function HookOverlays(adapter, btn)
  if not adapter.clickFrames then return end
  local ok, frames = pcall(adapter.clickFrames, btn)
  if not ok or type(frames) ~= "table" then return end
  for _, f in ipairs(frames) do
    if type(f) == "table" and f.HookScript and not overlayHooked[f] then
      overlayHooked[f] = true
      f:HookScript("PreClick", function(_, mouse) if IsAltKeyDown() then PreClick(btn, mouse) end end)
      f:HookScript("PostClick", function() PostClick(btn) end)
    end
  end
end

local function AdoptButton(adapter, btn)
  if type(btn) ~= "table" or not btn.HookScript then return end
  btn.favesAdapter = adapter
  HookButton(btn)
  HookOverlays(adapter, btn)
  UpdateButton(btn)
end

local function HookBagAddons()
  for _, adapter in ipairs(bagAddons) do
    local ok, loaded = pcall(adapter.loaded)
    if not adapter.active and ok and loaded then
      local hooked, err = pcall(adapter.hook, function(btn) AdoptButton(adapter, btn) end)
      adapter.active, adapter.failed = hooked, not hooked
      Log(hooked and "%s support on" or "%s support failed: %s", adapter.name, tostring(err))
    end
  end
end

-- "name: on" / "name: loaded, but ..." lines for status and the self-test.
function KS.BagAddonStatus()
  local out = {}
  for _, adapter in ipairs(bagAddons) do
    if adapter.active then out[#out + 1] = { adapter.name, true }
    elseif adapter.failed then out[#out + 1] = { adapter.name, false } end
  end
  return out
end

function RefreshBags()
  for _, frame in ipairs(BagFrames()) do UpdateFrame(frame) end
  for btn in pairs(hooked) do
    if btn.favesAdapter then UpdateButton(btn) end
  end
end

local function HookBags()
  HookBagAddons()
  for _, frame in ipairs(BagFrames()) do
    if frame.UpdateItems then hooksecurefunc(frame, "UpdateItems", UpdateFrame) end
    frame:HookScript("OnShow", function(self)
      C_Timer.After(0, function() UpdateFrame(self) end)
    end)
  end
end

---------------------------------------------------------------------------------------------------
-- Disenchant guard, part 2: while a destructive (or unidentified) targeting cursor is up, cover each
-- Confirm/Locked bag slot with a blocker that takes the click, so the click never reaches the item.
-- This doesn't depend on the bag button's own click handlers, which PreClick alone did.

local blockers = {}      -- item button -> blocker
local anyBlocker = false
local blockSpell         -- spell ID of the current cursor, when known

local function BlockAction()
  if blockSpell == 31252 then return "prospect" end
  if blockSpell == 51005 then return "mill" end
  if blockSpell == 13262 then return "disenchant" end
  return "use that spell on"
end

local function GetBlocker(btn)
  local b = blockers[btn]
  if b then return b end
  b = CreateFrame("Button", nil, btn)
  b:SetAllPoints(btn)
  b:SetFrameLevel(btn:GetFrameLevel() + 10)
  b:RegisterForClicks("AnyDown")
  local tex = b:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetColorTexture(1, 0, 0, 0.35)
  b:SetScript("OnClick", function()
    local bag, slot = ButtonSlot(btn)
    local info = bag and slot and C.GetContainerItemInfo(bag, slot)
    -- The blocker takes the click; it can't cancel the cursor (SpellStopTargeting is protected here).
    Log("blocker caught click on %s", info and info.hyperlink or "?")
    if info then KS.Guard(info.itemID, info.hyperlink, BlockAction()) end
  end)
  b:SetScript("OnEnter", function(self)
    local bag, slot = ButtonSlot(btn)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if bag and slot then GameTooltip:SetBagItem(bag, slot) end
    GameTooltip:AddLine("Protected by Standing Orders: this click is blocked.", 1, 0.3, 0.3)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:Hide()
  blockers[btn] = b
  return b
end

local watchTargeting = false

local function UpdateBlockers()
  local targeting = SpellIsTargeting()
  if targeting and not watchTargeting then
    -- Also caught here in case CURRENT_SPELL_CAST_CHANGED didn't fire for this cursor.
    if GetTime() - targetStart > 1 then targetStart = GetTime() end
    local kind, spellID, how = TargetingKind()
    Log("targeting started: %s, spell %s, via %s (bag buttons hooked: %d)", kind, tostring(spellID), how, hookedCount)
  end
  watchTargeting = targeting

  local on, spellID = false, nil
  if targeting then
    local kind
    kind, spellID = TargetingKind()
    on = kind ~= "safe"
  end
  if not on and not anyBlocker then return end
  blockSpell = spellID

  anyBlocker = false
  for btn in pairs(hooked) do
    local want = false
    if on and btn:IsVisible() then
      local bag, slot = ButtonSlot(btn)
      local info = bag and slot and C.GetContainerItemInfo(bag, slot)
      want = (info and info.itemID and KS.IsLocked(info.itemID) and not KS.HasPass(info.itemID)) and true or false
    end
    if want then
      GetBlocker(btn):Show()
      anyBlocker = true
    elseif blockers[btn] then
      blockers[btn]:Hide()
    end
  end
end

local watcher = CreateFrame("Frame")
local sinceUpdate = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
  sinceUpdate = sinceUpdate + elapsed
  if sinceUpdate < 0.05 then return end
  sinceUpdate = 0
  UpdateBlockers()
end)

-- Last line of defence for diagnosis: a destructive cast was sent at a protected item anyway.
local function OnSpellcastSent(target, spellID)
  if not IsDestructive(spellID) then return end
  Log("destructive cast sent: spell %s on '%s'", tostring(spellID), tostring(target))
  if not target or target == "" then return end
  for bag = 0, NUM_BAGS do
    for slot = 1, C.GetContainerNumSlots(bag) do
      local info = C.GetContainerItemInfo(bag, slot)
      if info and info.itemID and KS.IsLocked(info.itemID) and GetItemInfo(info.itemID) == target then
        Log("MISSED: %s is %s but the cast went through. targeting kind %s, blockers %s, record %s",
          info.hyperlink, NAMES[KS.GetLevel(info.itemID)], (TargetingKind()), tostring(anyBlocker),
          castRecord and (castRecord.kind .. " " .. tostring(castRecord.name or castRecord.id)) or "none")
        Err(("Standing Orders couldn't stop this cast on %s. Details are in /soc log.")
          :format(info.hyperlink))
        return
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Auto-marks. Unmarked items in your bags get a level by these rules (each can be turned off in
-- /soc settings):
--   gray                                        -> Junk
--   white with no profession or quest use        -> Junk  (gear, weapons, gray-ish junk)
--   crafting materials (white and up, unbound)   -> Mail on this character, when none of its
--                                                   professions use them (see Professions)
--   unbound Bind on Equip (green and up)         -> Mail
-- Quest items, consumables, bags, ammo, recipes, keys, shirts and tabards are left alone, and so is
-- anything VendorFlip is holding to flip. Items you got on purpose (traded to you, bought on the AH or
-- from a vendor, or mailed to you by a player) are left alone on the character that got them.
-- Each item ID is only decided once (StandingOrdersCustodianDB.autoSeen), so a level you change by hand stays.

KS.AUTO_MARKS = true -- Standing Orders: Vendor checks this and leaves auto-marking to Custodian

local AUTO_DEFAULTS = { grayJunk = true, whiteJunk = true, boeMail = true, matsMail = true, keepReceived = true }
local AUTO_KEYS = { "grayJunk", "whiteJunk", "boeMail", "matsMail", "keepReceived" }

local CLASS = (Enum and Enum.ItemClass) or {}
local CONSUMABLE, CONTAINER, WEAPON, REAGENT, PROJECTILE, TRADEGOODS, RECIPE, QUIVER, QUEST, KEY, MISC =
  CLASS.Consumable or 0, CLASS.Container or 1, CLASS.Weapon or 2, CLASS.Reagent or 5, CLASS.Projectile or 6,
  CLASS.Tradegoods or 7, CLASS.Recipe or 9, CLASS.Quiver or 11, CLASS.Questitem or 12, CLASS.Key or 13,
  CLASS.Miscellaneous or 15
local ARMOR = CLASS.Armor or 4
local NEVER_JUNK_CLASS = { [CONSUMABLE] = true, [CONTAINER] = true, [PROJECTILE] = true, [RECIPE] = true,
  [QUIVER] = true, [KEY] = true }
local NEVER_JUNK_SLOT = { INVTYPE_BODY = true, INVTYPE_TABARD = true }
local BIND_ON_PICKUP, BIND_ON_EQUIP = 1, 2
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

function KS.GetAuto(key) return db and db.auto and db.auto[key] end
function KS.SetAuto(key, on)
  if not (db and AUTO_DEFAULTS[key] ~= nil) then return end
  db.auto[key] = on and true or false
  if on then KS.QueueAutoMark() end
end

local function HeldByVendorFlip(id)
  local VF = _G.VendorFlip
  if not (VF and VF.IsHeld) then return false end
  local ok, held = pcall(VF.IsHeld, id)
  return ok and held == true
end

---------------------------------------------------------------------------------------------------
-- Professions: which crafting materials this character uses. The reliable answer is the reagents of
-- the recipes it knows, read whenever one of its profession windows opens (StandingOrdersCustodianCharDB.recipeMats).
-- For a profession whose window hasn't been opened yet, the item's kind is used as a guess; when the
-- kind can't tell, the item waits. Enchanting materials are never auto-marked.

local ENCHANTING_SUBCLASS = 12 -- Trade Goods: Enchanting
local ENCHANT_MATS = {}
for _, id in ipairs({
  10940, 11083, 11137, 11176, 16204,                                     -- dusts
  10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203,  -- essences
  10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725,         -- shards, Nexus Crystal
}) do ENCHANT_MATS[id] = true end

local function IsEnchantingMat(id, classID, subclassID)
  return (ENCHANT_MATS[id] or (classID == TRADEGOODS and subclassID == ENCHANTING_SUBCLASS)) and true or false
end

function KS.IsEnchantingMat(id)
  if not (id and GetItemInfoInstant) then return ENCHANT_MATS[id] or false end
  local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
  return IsEnchantingMat(id, classID, subclassID)
end

-- Gathering professions have no recipes (Mining does: smelting).
local GATHERING = { [182] = true, [393] = true, [356] = true, Herbalism = true, Skinning = true, Fishing = true }
local CRAFTING_NAMES = { Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
  Leatherworking = true, Tailoring = true, Mining = true, Cooking = true, ["First Aid"] = true,
  Jewelcrafting = true, Inscription = true }
-- Trade Goods subclass -> the professions that might use it (the guess before recipes are seen).
-- Subclasses not listed (plain Trade Goods, Elemental, Other...) can't be guessed.
local SUBCLASS_PROFS = {
  [1] = { Engineering = true }, [2] = { Engineering = true }, [3] = { Engineering = true }, -- Parts, Explosives, Devices
  [4] = { Jewelcrafting = true },
  [5] = { Tailoring = true, ["First Aid"] = true },                                        -- Cloth
  [6] = { Leatherworking = true },
  [7] = { Blacksmithing = true, Engineering = true, Mining = true, Jewelcrafting = true },  -- Metal & Stone
  [8] = { Cooking = true },                                                                -- Meat
  [9] = { Alchemy = true, Inscription = true },                                            -- Herb
  [16] = { Inscription = true },
}

-- This character's crafting professions (name -> true), or nil when the client can't say.
local function MyProfessions()
  if GetProfessions and GetProfessionInfo then
    local profs, list = {}, { GetProfessions() }
    for i = 1, 6 do
      local index = list[i]
      if index then
        local name, _, _, _, _, _, line = GetProfessionInfo(index)
        if name and not GATHERING[line or 0] and not GATHERING[name] then profs[name] = true end
      end
    end
    return profs
  end
  if GetNumSkillLines and GetSkillLineInfo then
    local profs, any = {}, false
    for i = 1, GetNumSkillLines() do
      local name, isHeader = GetSkillLineInfo(i)
      if name and not isHeader then
        any = true
        if CRAFTING_NAMES[name] then profs[name] = true end
      end
    end
    if any then return profs end
  end
end

-- Professions for this pass of auto-marks: what the client says plus every one whose recipes we've
-- read. nil when neither is known yet.
local profState
local function ProfessionState()
  if profState ~= nil then return profState or nil end
  local detected = MyProfessions()
  if not detected and not next(cdb.scanned) then
    profState = false
    return nil
  end
  local unscanned = {}
  for name in pairs(detected or {}) do
    if not cdb.scanned[name] then unscanned[#unscanned + 1] = name end
  end
  profState = { unscanned = unscanned }
  return profState
end

-- true when this character's professions use the item, false when none do, nil when it can't tell yet.
local function UsedHere(id, subclassID)
  if cdb.recipeMats[id] then return true end
  local state = ProfessionState()
  if not state then return nil end
  if #state.unscanned == 0 then return false end
  local could = SUBCLASS_PROFS[subclassID]
  if not could then return nil end
  for _, name in ipairs(state.unscanned) do
    if could[name] then return nil end
  end
  return false
end

-- The reagents of a profession's known recipes, from its window. Mail marks this character's
-- auto-marks put on items it turns out to use come off again.
local function RecordRecipes(prof, mats)
  if not (cdb and prof and prof ~= "" and next(mats)) then return end
  local count, new = 0, 0
  for id in pairs(mats) do
    count = count + 1
    if not cdb.recipeMats[id] then
      cdb.recipeMats[id] = prof
      new = new + 1
    end
  end
  local first = not cdb.scanned[prof]
  cdb.scanned[prof] = true
  local freed = {}
  for id, level in pairs(cdb.autoMarked) do
    if cdb.recipeMats[id] then
      if cdb.items[id] == level then
        cdb.items[id] = nil
        freed[#freed + 1] = ItemLink(id)
      end
      cdb.autoMarked[id] = nil
      cdb.autoSeen[id] = true -- decided: used here
    end
  end
  if first or new > 0 then
    Log("%s recipes read: %d reagents, %d new", prof, count, new)
    profState = nil
    KS.QueueAutoMark()
  end
  if #freed > 0 then
    Print("Your %s uses %s, so %s no longer Mail.", prof, table.concat(freed, ", "), #freed > 1 and "they're" or "it's")
    RefreshBags()
  end
end

local function AddReagent(mats, link)
  local id = LinkID(link)
  if id then mats[id] = true end
end

local function ScanTradeSkill()
  if IsTradeSkillLinked and IsTradeSkillLinked() then return end -- someone else's
  local mats, prof = {}, nil
  if GetNumTradeSkills and GetTradeSkillLine and (GetNumTradeSkills() or 0) > 0 then
    prof = GetTradeSkillLine()
    for i = 1, GetNumTradeSkills() do
      local _, kind = GetTradeSkillInfo(i)
      if kind ~= "header" and kind ~= "subheader" then
        for r = 1, (GetTradeSkillNumReagents(i) or 0) do AddReagent(mats, GetTradeSkillReagentItemLink(i, r)) end
      end
    end
  elseif C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic then
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return end
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    prof = base and base.professionName
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
      local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
      if recipe and recipe.learned then
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        for _, slotInfo in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
          for _, reagent in ipairs(slotInfo.reagents or {}) do
            if reagent.itemID then mats[reagent.itemID] = true end
          end
        end
      end
    end
  end
  RecordRecipes(prof, mats)
end

-- The Craft window (Enchanting on older clients).
local function ScanCraft()
  if not (GetNumCrafts and GetCraftReagentItemLink) then return end
  local prof = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()) or (GetCraftName and GetCraftName())
  local mats = {}
  for i = 1, (GetNumCrafts() or 0) do
    local _, _, kind = GetCraftInfo(i)
    if kind ~= "header" then
      for r = 1, (GetCraftNumReagents(i) or 0) do AddReagent(mats, GetCraftReagentItemLink(i, r)) end
    end
  end
  RecordRecipes(prof, mats)
end

local scanQueued = {}
local function QueueScan(fn)
  if scanQueued[fn] then return end
  scanQueued[fn] = true
  C_Timer.After(0.3, function()
    scanQueued[fn] = nil
    local ok, err = pcall(fn)
    if not ok then Log("recipe scan failed: %s", tostring(err)) end
  end)
end

-- The level the rules give an item, false when the rules leave it alone for good, or nil when it
-- can't be decided yet (item data not loaded, or the deciding rule is off: decide again later).
-- The second value is "char" when the decision is for this character only.
local function AutoLevel(info, bag, slot)
  local id = info.itemID
  local name, _, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID, bindType, _, _, isCrafting = GetItemInfo(id)
  if not name then return nil end
  if KS.IsPersonal(id) then return false end -- consumables, reagents, vendor trade goods
  if not classID and GetItemInfoInstant then
    local _, _, _, loc, _, cls, sub = GetItemInfoInstant(id)
    equipLoc, classID, subclassID = equipLoc or loc, cls, sub
  end
  local quest = classID == QUEST
  if not quest and bag and C.GetContainerItemQuestInfo then
    local q = C.GetContainerItemQuestInfo(bag, slot)
    quest = q and (q.isQuestItem or q.questID) and true or false
  end
  if quest then return false end

  if IsEnchantingMat(id, classID, subclassID) then return false end

  local quality, auto = info.quality, db.auto
  local crafting = classID == TRADEGOODS or isCrafting == true
  if quality == 0 then
    if info.hasNoValue then return false end -- can't be sold anyway
    if not auto.grayJunk then return nil end
    return JUNK
  end
  if crafting then
    if info.isBound or bindType == BIND_ON_PICKUP then return false end
    if not auto.matsMail then return nil end
    local used = UsedHere(id, subclassID)
    if used == nil then return nil end
    if used then return false, "char" end
    return MAIL, "char"
  end
  if quality == 1 then
    if info.hasNoValue or NEVER_JUNK_CLASS[classID] or NEVER_JUNK_SLOT[equipLoc] then return false end
    local junkish = classID == WEAPON or classID == ARMOR or (classID == MISC and subclassID == 0)
    if not junkish then return false end
    if not auto.whiteJunk then return nil end
    return JUNK
  end
  if quality and quality >= 2 and bindType == BIND_ON_EQUIP and not info.isBound then
    if not auto.boeMail then return nil end
    return MAIL
  end
  return false
end

-- An item this character got on purpose: auto-marks leave it alone here, and an auto-mark already
-- made on another character is overridden with Normal for this one.
local function OverrideHere(id, link, how)
  local mine = cdb.autoMarked[id]
  if mine and cdb.items[id] == mine then
    cdb.items[id] = nil
    cdb.autoMarked[id] = nil
    Print("%s is no longer %s: you %s.", link or ItemLink(id), LevelText(mine), how)
    RefreshBags()
  end
  local auto = db.autoMarked[id]
  if auto and db.items[id] == auto and not cdb.items[id] then
    KS.SetLevel(id, NORMAL, link, { scope = "char", quiet = true })
    Print("%s was %s; you %s, so it's Normal on this character.", link or ItemLink(id), LevelText(auto), how)
  end
end

local function KeepHere(id, link, how)
  if not (db and cdb and id) or not db.auto.keepReceived then return end
  cdb.kept[id] = how
  Log("kept item %d here: %s", id, how)
  OverrideHere(id, link, how)
end

-- Auto-marks on per-character items (from before they were left alone, or before a vendor showed
-- that an item is sold there) are taken off again.
local function DropPersonalAutoMarks()
  local n = 0
  -- Both account-wide and this character's own auto-marks (older builds marked crafting materials,
  -- Light Feathers among them, Mail per character).
  for _, store in ipairs({ db, cdb }) do
    for id, level in pairs(store.autoMarked) do
      if KS.IsPersonal(id) then
        if store.items[id] == level then store.items[id] = nil end
        store.autoMarked[id] = nil
        n = n + 1
      end
    end
  end
  if n > 0 then
    Print("Took auto-marks off %d consumables, reagents and vendor trade goods: mark those yourself, per character.", n)
    Log("dropped %d auto-marks on per-character items", n)
    RefreshBags()
  end
end

-- Trade goods this vendor sells become per-character items.
local function LearnVendorMats()
  if not (db and GetMerchantNumItems) then return end
  local new = 0
  for i = 1, GetMerchantNumItems() do
    local id = LinkID(GetMerchantItemLink(i))
    if id and not KS.IsVendorMat(id) and ItemClass(id) == CLASS_TRADEGOODS then
      db.vendorMats[id] = true
      new = new + 1
    end
  end
  if new > 0 then
    Log("learned %d vendor trade goods", new)
    DropPersonalAutoMarks()
  end
end

-- Crafting materials used to be marked Mail for all characters. They're per character now, so the
-- old marks come off once and every character decides again.
local function MigrateAutoMarks()
  if (db.autoVersion or 1) >= 2 then return end
  local n = 0
  for id, level in pairs(db.autoMarked) do
    if level == MAIL and ItemClass(id) == CLASS_TRADEGOODS then
      if db.items[id] == level then db.items[id] = nil end
      db.autoMarked[id] = nil
      n = n + 1
    end
  end
  for id in pairs(db.autoSeen) do
    if ItemClass(id) == CLASS_TRADEGOODS then db.autoSeen[id] = nil end
  end
  db.autoVersion = 2
  if n > 0 then
    Print("Crafting materials are now Mail per character, and only when none of that character's professions use them. Took the old Mail mark off %d of them.", n)
    Log("migrated auto-marks: %d account-wide crafting Mail marks removed", n)
    RefreshBags()
  end
end

local tradeOpen = false

local function AutoMark()
  if not db or tradeOpen then return end
  local marked = { [JUNK] = {}, [MAIL] = {}, here = {} }
  profState = nil
  for bag = 0, NUM_BAGS do
    for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
      local info = C.GetContainerItemInfo(bag, slot)
      local id = info and info.itemID
      if id and cdb.kept[id] and db.auto.keepReceived then
        OverrideHere(id, info.hyperlink, cdb.kept[id]) -- catches marks made on another character since
      elseif id and not db.autoSeen[id] and not cdb.autoSeen[id] and not KS.GetItemScope(id)
          and not HeldByVendorFlip(id) and not setLevelOf[id] then
        local level, scope = AutoLevel(info, bag, slot)
        local here = scope == "char"
        if level ~= nil then (here and cdb.autoSeen or db.autoSeen)[id] = true end
        if level then
          (here and cdb.autoMarked or db.autoMarked)[id] = level
          KS.SetLevel(id, level, info.hyperlink, { scope = here and "char" or "account", quiet = true })
          table.insert(here and marked.here or marked[level], info.hyperlink)
        end
      end
    end
  end
  for _, key in ipairs({ JUNK, MAIL, "here" }) do
    local list = marked[key]
    if #list > 0 then
      local shown = table.concat(list, ", ", 1, math.min(#list, 5))
      if #list > 5 then shown = shown .. (" and %d more"):format(#list - 5) end
      if key == "here" then
        Print("Marked as %s on this character (none of your professions use them): %s. (/soc settings)",
          LevelText(MAIL), shown)
      else
        Print("Marked as %s: %s. (/soc settings to change this)", LevelText(key), shown)
      end
      Log("auto-marked %d items as %s", #list, key == "here" and "Mail (this character)" or NAMES[key])
    end
  end
end

local autoQueued = false
function KS.QueueAutoMark(delay)
  if autoQueued or not db then return end
  autoQueued = true
  C_Timer.After(delay or 0.5, function()
    autoQueued = false
    AutoMark()
  end)
end

-- Where items you got on purpose come from.
local function OnTakeMail(index, attach)
  if not (db and index) then return end
  local _, _, sender, _, _, _, _, _, _, _, _, canReply, isGM = GetInboxHeaderInfo(index)
  local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
  local how
  if invoice == "buyer" then how = "bought it on the AH"
  elseif canReply and not isGM and not invoice then how = "got it in the mail from " .. tostring(sender) end
  for a = attach or 1, attach or (ATTACHMENTS_MAX_RECEIVE or 16) do
    local link = GetInboxItemLink(index, a)
    if link then
      Log("mail item %s from %s (%s)", link, tostring(sender), how or "auto-marks apply")
      if how then KeepHere(LinkID(link), link, how) end
    end
  end
end

local function KeepTradeItems()
  for i = 1, (MAX_TRADABLE_ITEMS or 6) do
    local link = GetTradeTargetItemLink(i)
    if link then KeepHere(LinkID(link), link, "got it in a trade") end
  end
end

local function HookReceipts()
  if TakeInboxItem then hooksecurefunc("TakeInboxItem", OnTakeMail) end
  if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(index) OnTakeMail(index) end) end
  if BuyMerchantItem then
    hooksecurefunc("BuyMerchantItem", function(index)
      local link = GetMerchantItemLink(index)
      if link then KeepHere(LinkID(link), link, "bought it from a vendor") end
    end)
  end
  if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID)
      KeepHere(itemID, nil, "bought it on the AH")
    end)
  end
end

---------------------------------------------------------------------------------------------------
-- Settings panel (/soc settings, or Esc > Options > AddOns > Custodian)

local category
local refreshers = {}

local function RefreshPanel() for _, fn in ipairs(refreshers) do fn() end end

-- A dropdown (the game's menu system) of choices() where the client has one; otherwise a button that
-- cycles (right-click goes back). current() is the checked choice, text(c) its label, choose(c) picks it.
-- Returns the frame and a Show() that brings its text up to date (call it from a refresher).
local function ChoiceControl(parent, width, choices, current, text, choose)
  local function Pick(c) choose(c); RefreshPanel() end
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(width)
    dd:SetupMenu(function(_, root)
      for _, c in ipairs(choices()) do
        root:CreateRadio(text(c), function() return current() == c end, function() Pick(c) end)
      end
    end)
    dd.isDropdown = true
    return dd, function() dd:GenerateMenu() end
  end
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(width, 22)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(_, mouse)
    local list, cur, n = choices(), current(), 1
    for k, c in ipairs(list) do if c == cur then n = k end end
    Pick(list[(n + (mouse == "RightButton" and -2 or 0)) % #list + 1])
  end)
  return btn, function() btn:SetText(text(current())) end
end

local function Check(panel, text, anchor, y, onClick)
  local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -2)
  cb.Text:SetText(text)
  cb:SetScript("OnClick", onClick)
  return cb
end

local function Note(panel, text, anchor, x, y)
  local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)
  fs:SetWidth(560)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function Header(panel, text, anchor, y)
  local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -18)
  fs:SetText(text)
  return fs
end

local AUTO_TEXT = {
  grayJunk = "Gray items become |cff9d9d9dJunk|r",
  whiteJunk = "White gear, weapons and junk (no profession or quest use) become |cff9d9d9dJunk|r",
  matsMail = "Crafting materials none of this character's professions use become |cff4fb3ffMail|r (this character only)",
  boeMail = "Bind on Equip items (green and up, not yet bound) become |cff4fb3ffMail|r",
  keepReceived = "Except items you got on purpose: traded, bought (AH or vendor) or mailed to you by a player",
}

local function CreatePanel()
  -- The settings page is a fixed-size canvas, so everything sits in a scroll frame: `outer` is what
  -- the game shows, `panel` is the scrolling content (sized to fit by FitPanel below).
  local outer = CreateFrame("Frame", "SOCustodianSettings")
  outer.name = "Standing Orders: Custodian"
  local scroll = CreateFrame("ScrollFrame", nil, outer, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local panel = CreateFrame("Frame", nil, scroll)
  panel:SetSize(600, 600)
  scroll:SetScrollChild(panel)
  outer.scroll, outer.content = scroll, panel

  panel.icon = panel:CreateTexture(nil, "ARTWORK")
  panel.icon:SetSize(32, 32)
  panel.icon:SetPoint("TOPLEFT", 16, -10)
  panel.icon:SetTexture(KS.ICON)

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("LEFT", panel.icon, "RIGHT", 8, 0)
  title:SetText("Standing Orders: Custodian")

  local prev = Header(panel, "Auto-mark items in your bags", title, -16)
  local first = true
  for _, key in ipairs(AUTO_KEYS) do
    local cb = Check(panel, AUTO_TEXT[key], prev, first and -6 or -2, function(self)
      KS.SetAuto(key, self:GetChecked())
    end)
    if key == "keepReceived" then cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10) end
    refreshers[#refreshers + 1] = function() cb:SetChecked(KS.GetAuto(key)) end
    prev, first = cb, false
  end
  prev = Note(panel, "Only unmarked items, each item only once: if you change an auto-marked item's level, it stays changed. Quest items, enchanting materials, bags, ammo, recipes, shirts and tabards are left alone, and so is anything VendorFlip is holding. Open each of your profession windows once so Custodian knows which materials your recipes use. Junk and BoE Mail marks apply to all your characters.\n\nNever auto-marked, and marked per character when you mark them: consumables (food, drink, potions, scrolls...), reagents (ankhs, feathers...) and trade goods sold by vendors (thread, vials, flux, dyes, salt...).", prev, 26, -2)

  prev = Header(panel, "New marks (Alt+Click, /soc <level>)", prev)
  local acct = Check(panel, "Apply to all my characters", prev, -6, function()
    KS.SetScope("account")
    RefreshPanel()
  end)
  local char = Check(panel, "Apply to this character only", acct, -2, function()
    KS.SetScope("char")
    RefreshPanel()
  end)
  refreshers[#refreshers + 1] = function()
    acct:SetChecked(KS.GetScope() ~= "char")
    char:SetChecked(KS.GetScope() == "char")
  end
  prev = Note(panel, "Alt+Left-click an item in your bags to protect it more, Alt+Right-click to protect it less, Alt+Shift+Left-click to move its mark between all characters and this one.", char, 26, -2)

  local intro = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  intro:SetSize(170, 24)
  intro:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -26, -18)
  intro:SetText("What Standing Orders protects")
  -- Fit the label (fonts and UI scale differ): its text width plus the button's end caps.
  local textW = intro.GetTextWidth and intro:GetTextWidth()
  if type(textW) == "number" and textW > 0 then intro:SetWidth(math.max(170, math.ceil(textW) + 32)) end
  panel.introButton = intro
  intro:SetScript("OnClick", function() KS:ShowIntro() end)

  -- Equipment sets: the default for sets, then one row per set on this character, rebuilt each time the
  -- panel opens. Last on the panel, since the number of rows changes. Each row is a dropdown (a cycling button on clients without one).
  local DEFAULT_CHOICES = CONFIRM_ENABLED and { CONFIRM, LOCK, ONME, "off" } or { LOCK, ONME, "off" }
  local SET_CHOICES = CONFIRM_ENABLED and { "default", CONFIRM, LOCK, ONME, "off" } or { "default", LOCK, ONME, "off" }
  -- Mark icons: size, position and opacity, with a sample bag button that shows the result.
  prev = Header(panel, "Mark icons on bag items", intro, -22)
  local iconRows = {}
  local function IconRow(i, label)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12 - (i - 1) * 26)
    fs:SetWidth(80)
    fs:SetJustifyH("LEFT")
    fs:SetText(label)
    iconRows[i] = fs
    return fs
  end
  local function Stepper(i, label, key)
    local fs = IconRow(i, label)
    local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    minus:SetText("-")
    local value = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(230) -- "70% opaque (30% see-through)" on one line
    local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
    plus:SetText("+")
    local function Step(d)
      local size, _, alpha = KS.GetIconStyle()
      KS.SetIconStyle(key, (key == "size" and size or alpha) + d)
      RefreshPanel()
    end
    minus:SetScript("OnClick", function() Step(-5) end)
    plus:SetScript("OnClick", function() Step(5) end)
    return value, minus, plus
  end
  local sizeText, sizeMinus, sizePlus = Stepper(1, "Size", "size")
  local posLabel = IconRow(2, "Position")
  -- As wide as a stepper row: - (24), gap, value (230), gap, + (24).
  local pos, showPos = ChoiceControl(panel, 290, function() return ICON_ANCHORS end,
    function() return select(2, KS.GetIconStyle()) end,
    function(a) return ANCHOR_TEXT[a] or a end,
    function(a) KS.SetIconStyle("anchor", a) end)
  pos:SetPoint("LEFT", posLabel, "RIGHT", 10, 0)
  local alphaText, alphaMinus, alphaPlus = Stepper(3, "Opacity", "alpha")
  panel.iconStyle = { sizeMinus = sizeMinus, sizePlus = sizePlus, pos = pos, alphaMinus = alphaMinus, alphaPlus = alphaPlus }

  local sample = CreateFrame("Frame", nil, panel)
  sample:SetSize(37, 37)
  sample:SetPoint("LEFT", pos, "RIGHT", 40, 0)
  local item = sample:CreateTexture(nil, "ARTWORK")
  item:SetAllPoints()
  item:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
  local count = sample:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  count:SetPoint("BOTTOMRIGHT", -2, 2)
  count:SetText("20")
  local mark = sample:CreateTexture(nil, "OVERLAY", nil, 7)
  mark:SetTexture(ICONS[LOCK])
  panel.iconSample = mark
  refreshers[#refreshers + 1] = function()
    local size, anchor, alpha = KS.GetIconStyle()
    sizeText:SetText(size .. "% of the button's width")
    showPos()
    alphaText:SetText(alpha .. "% opaque (" .. (100 - alpha) .. "% see-through)")
    KS.StyleIcon(mark, sample)
  end

  prev = Header(panel, "Equipment sets protect their items", iconRows[3], -22)
  local setsNote = Note(panel, "", prev, 0, -6)
  local rows = {}
  panel.setRows = rows
  local function Row(i)
    if rows[i] then return rows[i] end
    local r = {}
    r.label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.label:SetPoint("TOPLEFT", setsNote, "BOTTOMLEFT", 0, -12 - (i - 1) * 26)
    r.label:SetWidth(180)
    r.label:SetJustifyH("LEFT")
    r.button, r.show = ChoiceControl(panel, 240, function() return r.setID and SET_CHOICES or DEFAULT_CHOICES end,
      function() return r.setID and KS.GetSetChoice(r.setID) or KS.GetSetDefault() end,
      KS.SetChoiceText,
      function(c) KS.SetSetChoice(r.setID, c) end)
    r.dropdown = r.button.isDropdown
    r.button:SetPoint("LEFT", r.label, "RIGHT", 10, 0)
    rows[i] = r
    return r
  end
  refreshers[#refreshers + 1] = function()
    local sets = KS.EquipmentSets()
    setsNote:SetText(#sets == 0 and "This character has no equipment sets yet. Make one in the character window's equipment manager; its items are then protected at the default below."
      or "Items in a set are protected at its level, on top of their own marks. Pick a level from its menu.")
    local r = Row(1)
    r.setID = nil
    r.label:SetText("Default for all sets")
    r.show()
    for i, set in ipairs(sets) do
      r = Row(i + 1)
      r.setID = set.id
      r.label:SetText(set.name)
      r.show()
    end
    for i, row in ipairs(rows) do
      local shown = i <= #sets + 1
      row.label[shown and "Show" or "Hide"](row.label)
      row.button[shown and "Show" or "Hide"](row.button)
    end
  end

  -- Content height: from its top to the lowest shown control, so the scroll bar reaches the last set row.
  local function FitPanel()
    local w = scroll:GetWidth()
    if type(w) == "number" and w > 0 then panel:SetWidth(w) end
    local top, last = panel:GetTop(), setsNote
    for _, row in ipairs(rows) do if row.button:IsShown() then last = row.button end end
    local bottom = last:GetBottom()
    if type(top) == "number" and type(bottom) == "number" then panel:SetHeight(math.max(1, top - bottom + 24)) end
  end
  outer.FitPanel = FitPanel
  outer:SetScript("OnShow", function()
    RefreshPanel()
    FitPanel()
    C_Timer.After(0, FitPanel) -- positions settle after the first frame
  end)
  outer.setRows, outer.iconStyle, outer.iconSample, outer.introButton = panel.setRows, panel.iconStyle, panel.iconSample, panel.introButton
  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(outer, outer.name)
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(outer)
    category = outer
  end
end

function KS.OpenSettings()
  if not category then return end
  if Settings and Settings.OpenToCategory and category.GetID then
    Settings.OpenToCategory(category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(category)
    InterfaceOptionsFrame_OpenToCategory(category)
  end
end

---------------------------------------------------------------------------------------------------
-- Tooltip line

local function HookTooltip()
  if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
    local level = KS.GetLevel(data and data.id)
    local setName, setLevel = KS.GetSetProtection(data and data.id)
    local from = (setName and setLevel == level) and (" |cff9d9d9d(equipment set \"" .. setName .. "\")|r") or ScopeText(KS.GetItemScope(data.id))
    if level ~= NORMAL then tip:AddLine("Standing Orders: " .. LevelText(level) .. from) end
  end)
end

---------------------------------------------------------------------------------------------------
-- One-time intro: what Confirm/Locked protect, and what they don't yet. Shown until "Got it" is
-- clicked; bump INTRO_VERSION when the list changes so everyone sees the new one once.

local INTRO_VERSION = 5
local INTRO_TEXT = table.concat({
  "|cffff4040Locked|r (key icon) items are protected. Alt+Left-click an item in your bags to protect it more, Alt+Right-click to protect it less.",
  "|cffc069ffAlways on me|r (purple diamond, one step above Locked) is Locked and also stays out of the bank.",
  "|cff9d9d9dJunk|r (coin icon) marks items you're happy to lose (Standing Orders: Vendor, coming soon, will sell them at any vendor).",
  "|cff4fb3ffMail|r (letter icon, between Junk and Normal) marks items to send to your bank character (Standing Orders: Mail, coming soon, will mail them).",
  "New items are marked for you: grays and white gear with no use become Junk, unbound BoE items become Mail, and so do crafting materials none of this character's professions use (for this character only; enchanting materials are left alone). Not items traded to you, bought (AH or vendor) or mailed to you by a player. Change this in /soc settings.",
  "Consumables, reagents and vendor trade goods (thread, vials...) are never auto-marked, and when you mark them the mark is for this character only.",
  "Marks are for all your characters. Alt+Shift+Left-click an item to keep its mark on this character only (or back again); /soc scope char makes that the default.",
  "",
  "|cff33ff99Protected against|r",
  "- Selling it: it's bought straight back while the vendor is open",
  "- Disenchant, Prospecting, Milling: the click is blocked",
  "- Destroying: the delete popup closes",
  "- Trade and mail: the item is taken back out",
  "- Bank (Always on me only): it's moved straight back to your bags",
  "",
  "|cff33ff99Still allowed|r",
  "- Enchants, oils and scrolls",
  "",
  "|cffff8040Not protected yet|r",
  "- Auction house posting",
  "- Using or eating the item, or handing it to an NPC",
  "- Closing the vendor right after a sale, before it can be bought back",
  "- Bag addons Standing Orders doesn't know (it supports Blizzard bags, ArkInventory, Bagnon, Combuctor, Baganator, AdiBags, BetterBags and ElvUI): no Alt+Click, icons or Disenchant block",
}, "\n")

local intro

function KS:ShowIntro()
  if not intro then
    intro = CreateFrame("Frame", "SOCustodianIntro", UIParent, "BasicFrameTemplateWithInset")
    intro:SetPoint("CENTER")
    intro:SetFrameStrata("DIALOG")
    intro:SetClampedToScreen(true)
    intro:EnableMouse(true)
    intro:SetMovable(true)
    intro:RegisterForDrag("LeftButton")
    intro:SetScript("OnDragStart", intro.StartMoving)
    intro:SetScript("OnDragStop", intro.StopMovingOrSizing)

    local title = intro:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 8, -5)
    title:SetText("Standing Orders: Custodian")
    intro.icon = intro:CreateTexture(nil, "OVERLAY")
    intro.icon:SetSize(16, 16)
    intro.icon:SetPoint("RIGHT", title, "LEFT", -4, 0)
    intro.icon:SetTexture(KS.ICON)

    local body = intro:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 18, -38)
    body:SetWidth(444)
    body:SetJustifyH("LEFT")
    body:SetSpacing(2)
    body:SetText(INTRO_TEXT)

    local ok = CreateFrame("Button", nil, intro, "UIPanelButtonTemplate")
    ok:SetSize(110, 24)
    ok:SetPoint("BOTTOM", 0, 14)
    ok:SetText("Got it")
    ok:SetScript("OnClick", function()
      db.introSeen = INTRO_VERSION
      intro:Hide()
      Print("You can reopen this with /soc intro.")
    end)

    intro:SetSize(480, body:GetStringHeight() + 38 + 54)
    tinsert(UISpecialFrames, "SOCustodianIntro") -- Esc closes it (it shows again next login until "Got it")
  end
  intro:Show()
end

---------------------------------------------------------------------------------------------------
-- Self-tests and Mechanic. /soc selftest runs read-only checks of this install and saves them in
-- StandingOrdersCustodianDB.selfTest (readable from the SavedVariables file after /reload). When the Mechanic dev tool
-- is installed (optional, never required: !Mechanic), Custodian also registers with it, so the checks show
-- in its Tests tab and the guard log in its Console. Nothing here changes marks or moves items.

local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
  or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"

-- Items the auto-mark rules must get right. "want" is the level, or false for "left alone".
local SAMPLES = {
  { id = 6948, want = false, why = "no vendor price" },             -- Hearthstone
  { id = 10940, want = false, why = "enchanting material" },        -- Strange Dust
  { id = 2320, want = false, why = "vendor trade good" },           -- Coarse Thread
  { id = 4540, want = false, why = "consumable" },                  -- Tough Hunk of Bread
  { id = 17030, want = false, why = "reagent" },                    -- Ankh
  { id = 4865, want = JUNK, rule = "grayJunk", why = "gray" },       -- Ruined Pelt
  { id = 25, want = JUNK, rule = "whiteJunk", why = "white weapon" }, -- Worn Shortsword
}

local function Detail(label, value, status) return { label = label, value = tostring(value), status = status } end

local function Result(details, message)
  local fails, warns = 0, 0
  for _, d in ipairs(details) do
    if d.status == "fail" then fails = fails + 1 elseif d.status == "warn" then warns = warns + 1 end
  end
  local passed = fails == 0
  return { passed = passed, warnings = warns, details = details,
    message = message or (passed and (warns > 0 and ("ok, %d warning(s)"):format(warns) or "ok")
      or ("%d failed"):format(fails)) }
end

local TESTS = {
  { id = "levels", name = "Levels and guards", run = function()
    local d = {}
    local ordered = true
    for i = 2, #ORDER do if not (ORDER[i] > ORDER[i - 1]) then ordered = false end end
    d[#d + 1] = Detail("levels in order", ordered and "yes" or "no", ordered and "pass" or "fail")
    local lockOk = not KS.IsLocked(nil) and KS.GetLevel(nil) == NORMAL
    d[#d + 1] = Detail("unmarked items are Normal and unlocked", lockOk and "yes" or "no", lockOk and "pass" or "fail")
    local apiOk = KS.LEVELS.MAIL == MAIL and KS.LEVELS.NORMAL == 2 and KS.LEVELS.CONFIRM == 3
    d[#d + 1] = Detail("LEVELS numbers other addons rely on", apiOk and "unchanged" or "CHANGED", apiOk and "pass" or "fail")
    d[#d + 1] = Detail("bank blocked from", NAMES[GUARD_FROM.bank], GUARD_FROM.bank == ONME and "pass" or "fail")
    return Result(d)
  end },
  { id = "saved", name = "Saved marks", run = function()
    local d, bad = {}, 0
    for _, t in ipairs({ db.items, cdb.items }) do
      for id, level in pairs(t) do
        if type(id) ~= "number" or not NAMES[level] then bad = bad + 1 end
      end
    end
    d[#d + 1] = Detail("marks with an unknown level", bad, bad == 0 and "pass" or "fail")
    local missing = {}
    for _, key in ipairs(AUTO_KEYS) do
      if type(db.auto[key]) ~= "boolean" then missing[#missing + 1] = key end
    end
    d[#d + 1] = Detail("auto-mark settings", #missing == 0 and "all set" or table.concat(missing, ", "),
      #missing == 0 and "pass" or "fail")
    return Result(d)
  end },
  { id = "hooks", name = "Guards hooked", run = function()
    local d = {}
    d[#d + 1] = Detail("bag buttons hooked", hookedCount, hookedCount > 0 and "pass" or "warn")
    for _, a in ipairs(KS.BagAddonStatus()) do
      d[#d + 1] = Detail(a[1] .. " support", a[2] and "on" or "failed to hook", a[2] and "pass" or "warn")
    end
    d[#d + 1] = Detail("destroy guard (StaticPopup_Show)", StaticPopup_Show and "on" or "missing", StaticPopup_Show and "pass" or "fail")
    d[#d + 1] = Detail("tooltip line", TooltipDataProcessor and "on" or "missing", TooltipDataProcessor and "pass" or "warn")
    d[#d + 1] = Detail("disenchant guard (IsCurrentSpell)", IsCurrentSpell and "available" or "missing", IsCurrentSpell and "pass" or "warn")
    local bags = BankBags()
    d[#d + 1] = Detail("bank containers", table.concat(bags, ","), #bags > 0 and "pass" or "fail")
    return Result(d)
  end },
  { id = "automarks", name = "Auto-mark rules on sample items", run = function()
    local d = {}
    for _, s in ipairs(SAMPLES) do
      local name, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(s.id)
      if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(s.id) end
        d[#d + 1] = Detail("item " .. s.id, "not loaded yet: run again", "warn")
      elseif s.rule and not db.auto[s.rule] then
        d[#d + 1] = Detail(name, s.rule .. " is off", "warn")
      else
        local info = { itemID = s.id, quality = quality, hasNoValue = (sellPrice or 0) == 0, isBound = false }
        local got = AutoLevel(info)
        local ok = (got or false) == s.want
        d[#d + 1] = Detail(name .. " (" .. s.why .. ")", got and NAMES[got] or (got == nil and "undecided" or "left alone"),
          ok and "pass" or "fail")
      end
    end
    return Result(d)
  end },
  { id = "professions", name = "Professions for crafting materials", run = function()
    local d = {}
    local profs = MyProfessions()
    d[#d + 1] = Detail("professions detected", profs and "yes" or "no (recipes only)", profs and "pass" or "warn")
    for name in pairs(profs or {}) do
      d[#d + 1] = Detail(name, cdb.scanned[name] and "recipes read" or "open its window once",
        cdb.scanned[name] and "pass" or "warn")
    end
    return Result(d)
  end },
  { id = "errors", name = "No Standing Orders: Custodian Lua errors", run = function()
    local d = {}
    local bg = _G.BugGrabber
    if not (bg and bg.GetDB) then
      d[#d + 1] = Detail("BugGrabber", "not installed: can't check", "warn")
      return Result(d)
    end
    local n, first = 0, nil
    for _, err in ipairs(bg:GetDB() or {}) do
      local text = tostring(err.message) .. tostring(err.stack)
      if text:find("StandingOrders_Custodian[/\\]") then
        n = n + 1
        first = first or tostring(err.message)
      end
    end
    d[#d + 1] = Detail("errors from Custodian files", n, n == 0 and "pass" or "fail")
    if first then d[#d + 1] = Detail("first", first:sub(1, 200), "fail") end
    return Result(d)
  end },
}

local testsByID, testResults = {}, {}
for _, t in ipairs(TESTS) do testsByID[t.id] = t end

local function RunTest(id)
  local t = testsByID[id]
  if not t then return end
  local start = debugprofilestop and debugprofilestop()
  local ok, res = pcall(t.run)
  if not ok then res = { passed = false, message = "test error: " .. tostring(res), details = {} } end
  res.duration = start and (debugprofilestop() - start) / 1000 or nil
  testResults[id] = res
  return res
end

-- Runs every check, saves the results, and reports them to Mechanic's console when it's there.
function KS.SelfTest(quiet)
  local summary = { version = VERSION, at = date("%Y-%m-%d %H:%M:%S"), passed = true, tests = {} }
  for _, t in ipairs(TESTS) do
    local res = RunTest(t.id)
    summary.tests[t.id] = res
    if not res.passed then summary.passed = false end
  end
  if db then db.selfTest = summary end
  local fails = 0
  for _, t in ipairs(TESTS) do
    local res = testResults[t.id]
    if not res.passed then fails = fails + 1 end
    if not quiet or not res.passed then
      Print("%s %s: %s", res.passed and "|cff33ff99ok|r  " or "|cffff4040FAIL|r", t.name, res.message)
      for _, dd in ipairs(res.details) do
        if dd.status ~= "pass" then print(("    %s %s: %s"):format(dd.status, dd.label, dd.value)) end
      end
    end
  end
  Log("self-test %s: %d of %d checks failed", summary.passed and "passed" or "FAILED", fails, #TESTS)
  return summary
end

local function RegisterMechanic()
  local LS = _G.LibStub
  local ML = LS and LS("MechanicLib-1.0", true)
  if not (ML and ML.Register) then return end
  mechanic = ML
  local defs = {}
  for _, t in ipairs(TESTS) do defs[#defs + 1] = { id = t.id, name = t.name, category = "Standing Orders: Custodian" } end
  ML:Register(ADDON, {
    version = VERSION,
    getDebugBuffer = function() return db and db.log or {} end,
    clearDebugBuffer = function() if db then db.log = {} end end,
    tests = {
      getAll = function() return defs end,
      getCategories = function() return { "Standing Orders: Custodian" } end,
      run = RunTest,
      -- MechanicLib expects runAll to return passed, total.
      runAll = function()
        local summary, passed = KS.SelfTest(true), 0
        for _, res in pairs(summary.tests) do if res.passed then passed = passed + 1 end end
        return passed, #TESTS
      end,
      -- Mechanic saves getResult for every test on /reload and logout: run it then, so the saved
      -- results are always this session's.
      getResult = RunTest,
    },
    settings = {
      debug = {
        type = "toggle", name = "Debug messages", order = 1,
        get = function() return db and db.debug and true or false end,
        set = function(_, v) if db then db.debug = v and true or false end end,
      },
    },
  })
  Log("registered with Mechanic")
  -- With Mechanic there, every session's self-test results are saved (StandingOrdersCustodianDB.selfTest) for the gate.
  KS.SelfTest(true)
end

---------------------------------------------------------------------------------------------------
-- Slash commands

local function ListItems()
  local any = false
  for _, level in ipairs(ORDER) do
    for _, scope in ipairs({ "account", "char" }) do
      for id, l in pairs(scope == "char" and cdb.items or db.items) do
        if Effective(l) == level then -- a saved Confirm lists under Locked while Confirm is off
          any = true
          Print("%s: %s%s", LevelText(level), ItemLink(id), ScopeText(scope))
        end
      end
    end
  end
  if not any then Print("No items are marked. Alt+Click an item in your bags to mark it.") end
end

local ANCHOR_WORDS = { bottomleft = "BOTTOMLEFT", topleft = "TOPLEFT", topright = "TOPRIGHT", bottomright = "BOTTOMRIGHT", center = "CENTER" }

-- /soc icon [size <percent> | position <corner or center> | opacity <percent> | reset]
local function IconCommand(rest)
  local key, value = rest:lower():match("^(%a*)%s*(%S*)$")
  local ok = key ~= nil
  if key == "size" then ok = KS.SetIconStyle("size", value)
  elseif key == "opacity" or key == "alpha" then ok = KS.SetIconStyle("alpha", value)
  elseif key == "position" or key == "corner" or key == "anchor" then ok = KS.SetIconStyle("anchor", ANCHOR_WORDS[value])
  elseif key == "reset" then
    for k, v in pairs(ICON_DEFAULTS) do KS.SetIconStyle(k, v) end
  elseif key ~= "" then ok = false end
  if not ok then return Err("Use /soc icon size 10-100, /soc icon position bottomleft||topleft||topright||bottomright||center, /soc icon opacity 10-100 or /soc icon reset.") end
  local size, anchor, alpha = KS.GetIconStyle()
  Print("Mark icons: %d%% of the button's width, %s, %d%% opaque.", size, (ANCHOR_TEXT[anchor] or anchor):lower(), alpha)
end

local function Help()
  Print("Commands:")
  print("  /soc junk||mail||normal||lock||onme <item link or ID> [char||account] - set an item's level")
  print("  /soc list - show marked items")
  print("  /soc sets - equipment sets and how they protect their items; /soc set <name> default||lock||onme||off")
  print("  /soc scope account||char - where new marks go (now " .. (KS.GetScope() == "char" and "this character" or "all characters") .. ")")
  print("  /soc settings - auto-marking (Junk and Mail), where new marks go, mark icons and equipment sets")
  print("  /soc icon size 10-100 || position bottomleft||topleft||topright||bottomright||center || opacity 10-100 || reset - mark icons on bag items (size: % of the button's width)")
  print("  /soc status - check which guards are active")
  print("  /soc intro - what Locked protects (and what it doesn't yet)")
  print("  /soc log [n] - show the last n guard log lines (default 25)")
  print("  /soc debug - toggle debug messages")
  print("  /soc selftest - check this install (results are saved for bug reports)")
  print("  In bags: Alt+Left-click raises protection, Alt+Right-click lowers it,")
  print("  Alt+Shift+Left-click moves a mark between all characters and this character only.")
end

local function Status()
  Print("Status:")
  local on = {}
  for _, key in ipairs(AUTO_KEYS) do if KS.GetAuto(key) then on[#on + 1] = key end end
  print("  auto-marks on: " .. (#on > 0 and table.concat(on, ", ") or "none") .. " (/soc settings)")
  local profs, parts = MyProfessions() or {}, {}
  for name in pairs(cdb.scanned) do profs[name] = true end
  for name in pairs(profs) do parts[#parts + 1] = name .. (cdb.scanned[name] and "" or " (open its window once)") end
  table.sort(parts)
  print("  professions: " .. (#parts > 0 and table.concat(parts, ", ") or "none found"))
  print("  equipment sets: " .. #KS.EquipmentSets() .. " on this character, default " .. KS.SetChoiceText(KS.GetSetDefault()))
  print("  new marks go to: " .. (KS.GetScope() == "char" and "this character only" or "all characters"))
  print("  bag buttons hooked: " .. hookedCount .. " (open your bags to hook more)")
  print("  disenchant guard: on (IsCurrentSpell " .. (IsCurrentSpell and "available" or "missing") ..
    ", last cast: " .. (castRecord and (castRecord.kind .. " " .. tostring(castRecord.name or castRecord.id)) or "none") .. ")")
  print("  destroy guard: " .. (StaticPopup_Show and "on" or "OFF"))
  print("  tooltip line: " .. ((TooltipDataProcessor and "on") or "OFF"))
  print("  trade/mail/vendor buyback guards: on (vendor open: " .. tostring(merchantOpen) .. ")")
  print("  bank guard (Always on me): on (bank open: " .. tostring(bankOpen) ..
    (bankOpen and (", containers " .. table.concat(BankBags(), ",")) or "") .. ")")
  for _, a in ipairs(KS.BagAddonStatus()) do
    print("  " .. a[1] .. ": " .. (a[2] and "supported (Alt+Click, icons, disenchant blocker; live views only)"
      or "|cffffd100loaded, but Standing Orders couldn't hook it: Alt+Click, icons and the disenchant guard only work in the default bags|r"))
  end
end

local LEVEL_CMDS = { junk = JUNK, mail = MAIL, normal = NORMAL, lock = LOCK, locked = LOCK, onme = ONME, always = ONME }
if CONFIRM_ENABLED then LEVEL_CMDS.confirm = CONFIRM end

SLASH_SOC1 = "/soc"
SlashCmdList.SOC = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "confirm" and not CONFIRM_ENABLED then
    Err(CONFIRM_LATER)
  elseif LEVEL_CMDS[cmd] and rest ~= "" then
    local scope
    local item, word = rest:match("^(.-)%s+(%a+)$")
    if word and (word:lower() == "char" or word:lower() == "account") then
      rest, scope = item, word:lower()
    end
    local id = LinkID(rest) or tonumber(rest)
    if not id then return Err("Shift-click an item into the command, or give its item ID.") end
    KS.SetLevel(id, LEVEL_CMDS[cmd], rest:match("|c.-|r") or ItemLink(id), { scope = scope }) -- pipes:ok (a pattern)
  elseif cmd == "sets" or cmd == "set" then
    SetsCommand(rest)
  elseif cmd == "scope" and (rest == "char" or rest == "account") then
    KS.SetScope(rest)
    Print("New marks now go to %s.", rest == "char" and "this character only" or "all characters")
  elseif cmd == "icon" or cmd == "icons" then
    IconCommand(rest)
  elseif cmd == "settings" or cmd == "config" or cmd == "options" then
    KS.OpenSettings()
  elseif cmd == "automail" and (rest == "on" or rest == "off") then -- older command: both Mail rules
    KS.SetAuto("boeMail", rest == "on")
    KS.SetAuto("matsMail", rest == "on")
    Print("Auto-marking Mail (BoE items and crafting materials) is %s.", rest)
  elseif cmd == "list" then
    ListItems()
  elseif cmd == "status" then
    Status()
  elseif cmd == "intro" or cmd == "protect" then
    KS:ShowIntro()
  elseif cmd == "log" then
    local log = db.log or {}
    local n = tonumber(rest) or 25
    Print("Last %d guard log lines (of %d):", math.min(n, #log), #log)
    for i = math.max(1, #log - n + 1), #log do print("  " .. log[i]) end
  elseif cmd == "selftest" or cmd == "test" then
    KS.SelfTest()
  elseif cmd == "debug" then
    db.debug = not db.debug
    Print("Debug messages %s.", db.debug and "on" or "off")
  else
    Help()
  end
end

---------------------------------------------------------------------------------------------------
-- Events

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:RegisterEvent("MERCHANT_UPDATE")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
pcall(f.RegisterEvent, f, "BANK_TABS_CHANGED") -- tabbed bank only
pcall(f.RegisterEvent, f, "EQUIPMENT_SETS_CHANGED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
f:RegisterEvent("TRADE_SHOW")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  pcall(f.RegisterEvent, f, event) -- whichever this client has
end
f:RegisterEvent("TRADE_CLOSED")
f:RegisterEvent("TRADE_ACCEPT_UPDATE")
f:RegisterEvent("MAIL_SEND_INFO_UPDATE")
f:RegisterEvent("MAIL_CLOSED")
f:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")

f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    StandingOrdersCustodianDB = StandingOrdersCustodianDB or {}
    db = StandingOrdersCustodianDB
    db.items = db.items or {}
    StandingOrdersCustodianCharDB = StandingOrdersCustodianCharDB or {}
    cdb = StandingOrdersCustodianCharDB
    cdb.items = cdb.items or {}
    db.vendorMats = db.vendorMats or {}  -- trade goods seen on a vendor: per-character items
    cdb.autoSeen = cdb.autoSeen or {}     -- item IDs decided for this character only
    cdb.autoMarked = cdb.autoMarked or {} -- item ID -> level auto-marks gave it on this character
    cdb.recipeMats = cdb.recipeMats or {} -- item ID -> a profession of this character that uses it
    cdb.scanned = cdb.scanned or {}       -- professions whose recipes have been read
    cdb.sets = cdb.sets or {}             -- equipment set ID -> level, "off" (missing: the default)
    cdb.kept = cdb.kept or {}            -- item IDs this character got on purpose: no auto-marks here
    db.autoSeen = db.autoSeen or db.autoMailSeen or {} -- item IDs the auto-marks have decided on
    db.autoMarked = db.autoMarked or {}  -- item ID -> the level auto-marks gave it
    for id in pairs(db.autoMailed or {}) do db.autoMarked[id] = db.autoMarked[id] or MAIL end
    db.auto = db.auto or {}
    if db.autoMail == false and db.auto.boeMail == nil then db.auto.boeMail = false end
    for key, on in pairs(AUTO_DEFAULTS) do
      if db.auto[key] == nil then db.auto[key] = on end
    end
    db.autoMailSeen, db.autoMailed, db.autoMail = nil, nil, nil
    db.icon = db.icon or {}
    -- Test builds defaulted to 30% of the width (a tenth of the area); 40% is the new default.
    if not db.icon.v then
      if db.icon.size == 30 then db.icon.size = nil end
      db.icon.v = 2
    end
    for key, v in pairs(ICON_DEFAULTS) do
      if db.icon[key] == nil then db.icon[key] = v end
    end
    if not ANCHOR_TEXT[db.icon.anchor] then db.icon.anchor = ICON_DEFAULTS.anchor end
  elseif event == "PLAYER_LOGIN" then
    HookBags()
    HookCasts()
    HookTooltip()
    HookDestroy()
    HookReceipts()
    CreatePanel()
    KS.RefreshSets()
    RegisterMechanic()
    -- Ask for the self-test sample items now so they're loaded when a test runs.
    if C_Item and C_Item.RequestLoadItemDataByID then
      for _, sample in ipairs(SAMPLES) do C_Item.RequestLoadItemDataByID(sample.id) end
    end
    DropPersonalAutoMarks()
    MigrateAutoMarks()
    KS.QueueAutoMark(5)
    if db.introSeen ~= INTRO_VERSION then C_Timer.After(4, function() KS:ShowIntro() end) end
  elseif event == "MERCHANT_SHOW" then
    LearnVendorMats()
    merchantOpen = true
    QueueRescue()
  elseif event == "EQUIPMENT_SETS_CHANGED" then
    KS.RefreshSets()
  elseif event == "MAIL_CLOSED" then
    KS.ClearPasses("mail")
  elseif event == "MERCHANT_CLOSED" then
    KS.ClearPasses("merchant")
    merchantOpen = false
  elseif event == "MERCHANT_UPDATE" then
    LearnVendorMats()
    QueueRescue()
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    local bags = BankBags()
    Log("bank opened: containers %s", table.concat(bags, ","))
    QueueBankRescue()
  elseif event == "BANKFRAME_CLOSED" then
    bankOpen = false
  elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "BANK_TABS_CHANGED" then
    QueueBankRescue()
  elseif event == "CURRENT_SPELL_CAST_CHANGED" then
    OnSpellCastChanged()
  elseif event == "UNIT_SPELLCAST_SENT" then
    OnSpellcastSent(arg2, arg4) -- unit, target, castGUID, spellID
  elseif event == "BAG_UPDATE_DELAYED" then
    RefreshBags()
    KS.QueueAutoMark()
    if merchantOpen then QueueRescue() end
    if bankOpen then QueueBankRescue() end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "TRADE_SKILL_LIST_UPDATE" then
    QueueScan(ScanTradeSkill)
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    QueueScan(ScanCraft)
  elseif event == "TRADE_SHOW" then
    tradeOpen = true -- no auto-marks until the trade is over and its items are known
  elseif event == "TRADE_ACCEPT_UPDATE" then
    if arg1 == 1 or arg2 == 1 then KeepTradeItems() end
  elseif event == "TRADE_CLOSED" then
    KS.ClearPasses("trade")
    C_Timer.After(1, function()
      tradeOpen = false
      KS.QueueAutoMark()
    end)
  elseif event == "TRADE_PLAYER_ITEM_CHANGED" then
    if arg1 then CheckTrade(arg1) end
  elseif event == "MAIL_SEND_INFO_UPDATE" then
    CheckMail()
  end
end)
