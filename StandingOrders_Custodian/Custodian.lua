-- Custodian: per-item protection levels that every item-losing action (selling, disenchanting,
-- destroying, trading, mailing) honors.
--
-- Levels (stored per item ID, account wide):
--   Junk     safe to get rid of (Standing Orders: Vendor sells these automatically when a vendor opens)
--   Disenchant  to disenchant: kept from vendors (bought straight back, never sold by Standing Orders: Vendor),
--            free to disenchant, trade and mail
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
-- Its name before 1.0.0 (Standing Orders: Quartermaster). Standing Orders: Vendor, Mail and the Standing Orders
-- config addon still look for this one until they're updated; drop it once none of them do.
_G.StandingOrdersQuartermaster = KS
-- The addon icon (Icon.tga, the ledger): the AddOn List, the settings panel, the intro and the hold window.
KS.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Icon"

-- Mail sits between Junk and Normal. It's 1.5 rather than renumbering, so saved marks and addons that
-- compare against the old numbers (Standing Orders: Vendor: Normal 2, Confirm 3) keep working.
local JUNK, MAIL, NORMAL, CONFIRM, LOCK, ONME = 1, 1.5, 2, 3, 4, 5
KS.LEVELS = { JUNK = JUNK, MAIL = MAIL, NORMAL = NORMAL, CONFIRM = CONFIRM, LOCK = LOCK, ONME = ONME }
-- Disenchant (1.2.0) sits between Junk and Mail: stopped only from being sold. A field, not a local: this file's
-- main chunk is at Lua's 200-local limit.
KS.LEVELS.DISENCHANT = 1.25
-- Confirm (a temp hold that asks before allowing an action once) is held back from the first release: its
-- "Allow once" didn't let a sale through in testing (BACKLOG.md). While it's off, nothing offers it, and a
-- saved Confirm mark or set choice counts as Locked; the saved data keeps the 3, so turning it back on
-- restores those marks as they were.
local CONFIRM_ENABLED = false
KS.CONFIRM_ENABLED = CONFIRM_ENABLED
local function Effective(level) return (level == CONFIRM and not CONFIRM_ENABLED) and LOCK or level end
KS.Effective = Effective -- for Copies.lua
local ORDER = CONFIRM_ENABLED and { JUNK, KS.LEVELS.DISENCHANT, MAIL, NORMAL, CONFIRM, LOCK, ONME } -- lowest to highest protection
  or { JUNK, KS.LEVELS.DISENCHANT, MAIL, NORMAL, LOCK, ONME }
local CONFIRM_LATER = "Confirm is coming in a later version; use Locked (lock) for now."

local NAMES = { [JUNK] = "Junk", [KS.LEVELS.DISENCHANT] = "Disenchant", [MAIL] = "Mail", [NORMAL] = "Normal", [CONFIRM] = "Confirm", [LOCK] = "Locked", [ONME] = "Always on me" }
local COLORS = { [JUNK] = "ff9d9d9d", [KS.LEVELS.DISENCHANT] = "ff3fd6c4", [MAIL] = "ff4fb3ff", [NORMAL] = "ffffffff", [CONFIRM] = "ffffd100", [LOCK] = "ffff4040", [ONME] = "ffc069ff" }
local ICONS = {
  [JUNK] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
  [KS.LEVELS.DISENCHANT] = "Interface\\Icons\\INV_Enchant_Disenchant",
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
  if KS.ChatAllows and KS.ChatAllows("verbose") then Print("|cff888888[debug]|r " .. msg, ...) end -- ChatLog.lua
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
KS.Log = Log -- for CopyTrack.lua

-- Messages about what Custodian did on its own (auto-marks, buybacks, items moved back, blocked actions): always
-- kept in the log (/soc log), and shown in chat too only with "Show Custodian's own messages in chat" on
-- (StandingOrdersCustodianDB.chat, off by default). So do the replies to your Alt+Clicks ("... is now Junk."); typed commands answer in chat.
function KS.Notify(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  Log(msg)
  if KS.ChatAllows and KS.ChatAllows("basic") then Print(msg) end -- the chat logging level (ChatLog.lua)
end

-- What Alt+Click in your bags does (StandingOrdersCustodianDB.altClick): "cycle" (the default: Alt+Left-click and
-- Alt+Right-click move the mark along the Alt+Click sequence, Clicks.lua) or "menu" (either one opens the mark
-- menu, Marks.lua).
function KS.GetAltClick() return (db and db.altClick == "menu") and "menu" or "cycle" end
function KS.SetAltClick(mode) if db then db.altClick = (mode == "menu") and "menu" or "cycle" end end

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

-- For Marks.lua (the mark menu and the Marked items window) and Clicks.lua (the Alt+Click sequence).
KS.ORDER, KS.NAMES, KS.ICONS, KS.COLORS = ORDER, NAMES, ICONS, COLORS
KS.Print, KS.Err = Print, Err

function KS.GetLevel(id)
  if not id then return NORMAL end
  local level = Effective((cdb and cdb.items[id]) or (db and db.items[id]) or NORMAL)
  local fromSet = setLevelOf[id]
  return (fromSet and fromSet > level) and fromSet or level
end

-- The item's own mark, without equipment-set protection on top.
function KS.GetOwnLevel(id)
  if not id then return NORMAL end
  return Effective((cdb and cdb.items[id]) or (db and db.items[id]) or NORMAL)
end

-- Every item with a mark of its own: { id, level, scope = "char" or "account" }. This character's mark wins (a
-- stored Normal there overrides an account-wide mark). Equipment-set protection isn't a mark and isn't listed.
function KS.MarkedItems()
  local list, seen = {}, {}
  for id, l in pairs(cdb and cdb.items or {}) do
    list[#list + 1] = { id = id, level = Effective(l), scope = "char" }
    seen[id] = true
  end
  for id, l in pairs(db and db.items or {}) do
    if not seen[id] then list[#list + 1] = { id = id, level = Effective(l), scope = "account" } end
  end
  return list
end

-- "char" when this character has its own mark for the item, "account" for an account-wide one, else nil.
function KS.GetItemScope(id)
  if id and cdb and cdb.items[id] then return "char" end
  if id and db and db.items[id] then return "account" end
end

-- Where new marks go (Alt+Click, the mark menu, /soc <level> <item>): "account" (default), "char", or "copy" (the copy
-- you click; Copies.lua. A typed command names an item, not a copy, so it marks the item for all characters).
function KS.GetScope() return (db and db.scope) or "account" end
KS.SCOPES = { "account", "char", "copy" }
KS.SCOPE_NAMES = { account = "Account wide", char = "Per character", copy = "Per copy" }
function KS.SetScope(scope)
  db.scope = (scope == "char" or scope == "copy") and scope or nil
end

local function ScopeText(scope)
  return scope == "char" and " |cff9d9d9d(this character)|r" or ""
end

-- True when the item must not leave your bags without you lowering its level first.
function KS.IsLocked(id) return KS.GetLevel(id) >= CONFIRM end

local RefreshBags -- defined with the bag hooks below

-- The Marked items window's two columns, each on its own: this character's own mark ("char") and the mark for all
-- characters ("account"). GetMarkIn returns nil when that column has none. SetMarkIn with level nil clears it (for
-- this character: back to the account-wide mark); unlike SetLevel, neither column changes the other.
function KS.GetMarkIn(id, scope)
  local t = (scope == "char") and cdb or db
  local l = id and t and t.items[id]
  return l and Effective(l) or nil
end
function KS.SetMarkIn(id, scope, level)
  if not id then return end
  if scope == "char" then
    cdb.items[id] = level and Effective(level) or nil
  else
    db.items[id] = (level and level ~= NORMAL) and Effective(level) or nil
  end
  KS.Notify("%s is now %s%s.", ItemLink(id), LevelText(KS.GetOwnLevel(id)), ScopeText(KS.GetItemScope(id)))
  RefreshBags()
end

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

-- Profession tools are never auto-marked: fishing poles, mining picks, blacksmith hammers, spanners,
-- skinning knives, enchanting rods and the like look like plain white weapons or trade goods, but the
-- character whose profession needs one has to keep it. A do block: the main chunk is at Lua's 200-local limit.
do
  local TOOLS = {}
  for _, id in ipairs({
    2901, 5956, 7005, 6219, 10498,      -- Mining Pick, Blacksmith Hammer, Skinning Knife, Arclight Spanner, Gyromatic Micro-Adjustor
    4471, 9149, 15846,                  -- Flint and Tinder, Philosopher's Stone, Salt Shaker
    6218, 6339, 11130, 11145, 16207,    -- Runed Copper, Silver, Golden, Truesilver and Arcanite Rods
    6256, 6365, 6366, 6367, 12225, 19022, 19970, 25978, -- fishing poles (any Fishing Pole weapon counts anyway)
    20815, 39505, 40772,                -- Jeweler's Kit, Virtuoso Inking Set, Gnomish Army Knife
  }) do TOOLS[id] = true end
  local FISHING_POLE = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
  local WEAPON = ITEM_CLASS.Weapon or 2
  function KS.IsProfessionTool(id)
    if not id then return false end
    if TOOLS[id] then return true end
    if not GetInstant then return false end
    local _, _, _, _, _, class, subclass = GetInstant(id)
    return class == WEAPON and subclass == FISHING_POLE
  end
end

-- opts (optional): { scope = "account"|"char", quiet = true, reply = true }. The old third-argument link still works.
-- The "is now" line goes through KS.Notify (the log, and chat only with chat on), except for a typed command (reply).
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
    local Say = opts.reply and Print or KS.Notify
    Say("%s is now %s%s.", link or ItemLink(id), LevelText(level), ScopeText(scope))
    if KS.GetLevel(id) > level and setNameOf[id] then
      Say("It stays %s while it's in the equipment set \"%s\" (/soc sets).", LevelText(KS.GetLevel(id)), setNameOf[id])
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
    KS.Notify("%s is now %s for all characters.", link, LevelText(KS.GetLevel(id)))
  elseif shared then
    cdb.items[id] = shared
    db.items[id] = nil
    KS.Notify("%s is now %s%s; your other characters no longer have it marked.", link, LevelText(Effective(shared)), ScopeText("char"))
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

-- level (optional): the level of the copy being acted on (Copies.lua: its own mark, or its item's mark as it applies
-- to that copy). Other addons leave it out: then it's the item's mark.
function KS.Guard(id, link, action, level)
  level = (type(level) == "number") and level or KS.GetLevel(id)
  local keepFromVendor = level == KS.LEVELS.DISENCHANT and action == "sell" -- Disenchant: only selling stops
  if not keepFromVendor and level < (GUARD_FROM[action] or CONFIRM) then return false end
  link = link or ItemLink(id)
  if level == CONFIRM and UsePass(id, action) then return false end
  local msg
  if keepFromVendor then
    msg = ("%s is marked Disenchant. Disenchant it, or lower it to Junk to sell it (/soc junk <item>)."):format(link)
  elseif level == CONFIRM then
    msg = ("%s is on hold (Confirm)."):format(link)
  else
    local how = (action == "bank") and "Lower it to Locked to bank it (Alt+Right-click it in your bags)"
      or ("Lower it to Normal to %s it (Alt+Right-click it in your bags, or /soc normal <item>)"):format(action)
    msg = ("%s is %s. %s."):format(link, NAMES[level], how)
  end
  -- The red error on screen always shows; its copy in chat is one of Custodian's own messages.
  UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2)
  KS.Notify("|cffff4040%s|r", msg)
  if level == CONFIRM then AskToAllow(id, link, action) end
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
  if KS.ScanCopies then KS.ScanCopies() end -- so a marked copy sold just now is known (CopyTrack.lua)
  for i = GetNumBuybackItems(), 1, -1 do
    local link = GetBuybackItemLink(i)
    local id = LinkID(link)
    local level, sold
    if id then level, sold = KS.BuybackLevel(i, id, link) end -- that copy's level (Copies.lua)
    if id and (level >= CONFIRM or level == KS.LEVELS.DISENCHANT) then
      rescuing = true
      KS.Guard(id, link, "sell", level)
      KS.Notify("Bought %s back.", link)
      BuybackItem(i)
      if sold and KS.CopyBoughtBack then KS.CopyBoughtBack(sold) end
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
KS.IsPlayerBag = IsPlayerBag -- for CopyTrack.lua

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
KS.BankBags = BankBags -- for Copies.lua and CopyTrack.lua

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
      if info and info.itemID and info.isLocked and KS.GetSlotLevel(bag, slot) >= ONME then
        busy = true -- still moving into the bank: look again shortly
      elseif info and info.itemID and KS.GetSlotLevel(bag, slot) >= ONME then
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
        KS.Guard(info.itemID, info.hyperlink, "bank", KS.GetSlotLevel(bag, slot))
        KS.Notify("Moved %s back to your bags.", info.hyperlink)
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
    if kind == "item" and KS.Guard(id, link, "destroy", KS.LockedCopyLevel(id)) then -- the copy picked up (Copies.lua)
      StaticPopup_Hide(which)
      ClearCursor()
    end
  end)
end

---------------------------------------------------------------------------------------------------
-- Guard: trade and mail (take a locked item back out as soon as it's put in)

local function CheckTrade(slot)
  local link = GetTradePlayerItemLink(slot)
  if link and KS.Guard(LinkID(link), link, "trade", KS.LockedCopyLevel(LinkID(link))) then
    ClearCursor()
    ClickTradeButton(slot) -- picks the item up off the trade window...
    ClearCursor()          -- ...and drops it back in your bags
  end
end

local function CheckMail()
  for i = 1, ATTACHMENTS_MAX_SEND or 12 do
    local link = GetSendMailItemLink(i)
    if link and KS.Guard(LinkID(link), link, "mail", KS.LockedCopyLevel(LinkID(link))) then
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
KS.ButtonSlot = ButtonSlot -- for Highlights.lua
function KS.BagButtons() return hooked end

-- Mark icons: how much of the item button they cover, where they sit, and how opaque they are, so
-- they don't hide counts and other addons' text. Account-wide (StandingOrdersCustodianDB.icon).
-- size: the icon's side as a % of the item button's width (40% of the width covers 16% of the area).
-- style: "game" (the game's art, borders trimmed) or "addon" (Custodian's badges) (Icons.lua).
local ICON_DEFAULTS = { size = 40, anchor = "BOTTOMLEFT", alpha = 75, style = "game" }
local ICON_ANCHORS = { "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "CENTER" }
local ANCHOR_TEXT = { BOTTOMLEFT = "Bottom left", TOPLEFT = "Top left", TOPRIGHT = "Top right",
  BOTTOMRIGHT = "Bottom right", CENTER = "Center" }
local ANCHOR_OFFSET = { BOTTOMLEFT = { 1, 1 }, TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMRIGHT = { -1, 1 }, CENTER = { 0, 0 } }
KS.ICON_ANCHORS, KS.ANCHOR_TEXT, KS.ICON_DEFAULTS = ICON_ANCHORS, ANCHOR_TEXT, ICON_DEFAULTS

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
  elseif key == "style" then
    value = KS.ICON_STYLE_ALIAS[value] or value
    if not KS.ICON_STYLE_NAMES[value] then return false end
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
  local level = info and KS.GetSlotLevel(bag, slot) or NORMAL -- this copy's mark (Copies.lua)
  local tex = btn.favesIcon
  if ICONS[level] then
    if not tex then
      tex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
      btn.favesIcon = tex
    end
    KS.StyleIcon(tex, btn)
    KS.MarkTexture(tex, level) -- in the icon style in use (Icons.lua)
    tex:Show()
  elseif tex then
    tex:Hide()
  end
  if tex then KS.MarkEdge(btn, tex, level) end
  if KS.UpdateHighlight then KS.UpdateHighlight(btn, bag, slot) end -- the vendor/mailbox tint (Highlights.lua)
end

-- True while the Send Mail page is open and Postal's (or its Forever port Posty's) Express module is on: Express
-- attaches (or, with AutoSend, sends) a bag item on Alt+Left-click there, so Custodian leaves that click alone instead
-- of also changing the item's mark. A field, not a local: the main chunk is at Lua's 200-local limit.
-- Only for the default bags' buttons (btn): Express hooks the Blizzard bag click (ContainerFrameItemButton_OnModifiedClick,
-- while the mailbox is open), so it never sees a bag addon's buttons and Custodian keeps those clicks. Posty is the
-- global PostyForever; Postal is Postal.
function KS.MailAddonOwnsAltClick(btn)
  if not (SendMailFrame and SendMailFrame:IsVisible()) then return false end
  if btn and btn.favesAdapter then return false end
  for _, global in ipairs({ "PostyForever", "Postal" }) do
    local postal = rawget(_G, global)
    if type(postal) == "table" and type(postal.GetModule) == "function" then
      local ok, express = pcall(postal.GetModule, postal, "Express", true)
      if ok and type(express) == "table" and (type(express.IsEnabled) ~= "function" or express:IsEnabled() == true) then
        local hooked = express.modifiedClickHooked
        if not hooked and type(express.IsHooked) == "function" then
          local okHook, isHooked = pcall(express.IsHooked, express, "ContainerFrameItemButton_OnModifiedClick")
          hooked = okHook and isHooked
        end
        if hooked then return true end
      end
    end
  end
  return false
end

local function PreClick(btn, mouse)
  btn.favesHandled = nil
  local bag, slot = ButtonSlot(btn)
  local info = bag and slot and C.GetContainerItemInfo(bag, slot)
  if not info or not info.itemID then return end

  if IsAltKeyDown() and mouse == "LeftButton" and KS.MailAddonOwnsAltClick(btn) then
    if not KS.mailClickHinted then
      KS.mailClickHinted = true
      Print("At the mailbox, Alt+Left-click belongs to Postal's Express (it attaches the item), so Custodian doesn't change marks with it there. Use Alt+Right-click, or /soc lock <item>.")
    end
    return
  end

  -- Alt+Shift+Left-click moves the mark between all characters and this character only.
  if IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown() and mouse == "LeftButton" then
    btn.favesHandled, btn.favesCursorEmpty = true, GetCursorInfo() == nil
    KS.ToggleScopeAt(bag, slot, info.itemID, info.hyperlink) -- a soulbound copy's marks stay per copy (Copies.lua)
    return
  end

  -- Alt+Left-click and Alt+Right-click move the mark along the Alt+Click sequence (Clicks.lua), or open the menu.
  if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
    btn.favesHandled, btn.favesCursorEmpty = true, GetCursorInfo() == nil
    if KS.GetAltClick() == "menu" then
      KS.ShowMarkMenu(info.itemID, info.hyperlink, nil, btn)
      return
    end
    KS.ClickMark(info.itemID, info.hyperlink, mouse == "LeftButton", bag, slot)
    return
  end

  -- Shift+Left-click while the Marked items window is open: search it for the item (Marks.lua), instead of
  -- splitting the stack.
  if IsShiftKeyDown() and not IsControlKeyDown() and mouse == "LeftButton" and KS.MarkListTakesShiftClick
      and KS.MarkListTakesShiftClick() then
    btn.favesHandled, btn.favesCursorEmpty, btn.favesNoSplit = true, GetCursorInfo() == nil, true
    KS.SearchMarkList(info.hyperlink or info.itemID)
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
    if KS.Guard(info.itemID, info.hyperlink, action, KS.GetSlotLevel(bag, slot)) then
      btn.favesHandled, btn.favesCursorEmpty = true, GetCursorInfo() == nil
    end
  end
end

local function PostClick(btn)
  -- If the default click went on to pick the item up, put it back.
  if btn.favesHandled and btn.favesCursorEmpty and GetCursorInfo() then ClearCursor() end
  -- A shift-click that searched the Marked items window: close the split-stack box the default click opened.
  if btn.favesNoSplit and StackSplitFrame and StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
  btn.favesHandled, btn.favesNoSplit = nil, nil
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
KS.RefreshBagIcons = RefreshBags -- for Copies.lua

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
    if info then KS.Guard(info.itemID, info.hyperlink, BlockAction(), KS.GetSlotLevel(bag, slot)) end
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
      want = (info and info.itemID and KS.GetSlotLevel(bag, slot) >= CONFIRM and not KS.HasPass(info.itemID)) and true or false
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
-- Quest items, consumables, profession tools, bags, ammo, recipes, keys, shirts and tabards are left alone, and so is
-- anything VendorFlip is holding to flip. Items you got on purpose (traded to you, bought on the AH or
-- from a vendor, or mailed to you by a player) are left alone on the character that got them.
-- Each item ID is only decided once (StandingOrdersCustodianDB.autoSeen), so a level you change by hand stays.

KS.AUTO_MARKS = true -- Standing Orders: Vendor checks this and leaves auto-marking to Custodian

-- A new install marks only grays Junk (the simple options; Simple.lua): the other rules are advanced options, off
-- until turned on. An install from 1.0.0 keeps its own choices (1.0.0 had every rule but unusableJunk on).
-- unusableJunk can only guess which gear a character will grow into, and with Standing Orders: Vendor selling Junk
-- by itself a wrong guess is sold at the next vendor.
local AUTO_DEFAULTS = { grayJunk = true, whiteJunk = false, unusableJunk = false, boeMail = false, matsMail = false, keepReceived = true }
local AUTO_KEYS = { "grayJunk", "whiteJunk", "unusableJunk", "boeMail", "matsMail", "keepReceived" }
KS.AUTO_DEFAULTS, KS.AUTO_KEYS = AUTO_DEFAULTS, AUTO_KEYS

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
    KS.Notify("Your %s uses %s, so %s no longer Mail.", prof, table.concat(freed, ", "), #freed > 1 and "they're" or "it's")
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

-- Soulbound gear this character can't use: never (its class can't wear that armor or train that weapon type), or
-- not for a while (more than SOON levels away, counting armor a class learns later: Mail at 40 for Hunters and
-- Shamans, Plate at 40 for Warriors and Paladins). Weapon types a class can train count as usable now. Classic
-- proficiencies; an unknown class or item kind is never called unusable. A do block: the main chunk is at Lua's
-- 200-local limit.
do
  local ARMOR_CLASS, WEAPON_CLASS = ITEM_CLASS.Armor or 4, ITEM_CLASS.Weapon or 2
  local SOON = 5
  -- Armor subclasses only some classes wear (2 Leather, 3 Mail, 4 Plate, 6 Shield, 7 Libram, 8 Idol, 9 Totem):
  -- [subclass] = the level a class can wear it from. Cloth, Miscellaneous (rings, necks, trinkets, held items) and
  -- anything else count as wearable by everyone.
  local CLASS_ARMOR = { [2] = true, [3] = true, [4] = true, [6] = true, [7] = true, [8] = true, [9] = true }
  local ARMOR = {
    WARRIOR = { [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    PALADIN = { [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
    HUNTER = { [2] = 1, [3] = 40 },
    ROGUE = { [2] = 1 },
    PRIEST = {}, MAGE = {}, WARLOCK = {},
    SHAMAN = { [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
    DRUID = { [2] = 1, [8] = 1 },
  }
  -- Weapon types each class can train (0 1H Axe, 1 2H Axe, 2 Bow, 3 Gun, 4 1H Mace, 5 2H Mace, 6 Polearm, 7 1H Sword,
  -- 8 2H Sword, 10 Staff, 13 Fist, 15 Dagger, 16 Thrown, 18 Crossbow, 19 Wand). Other subclasses (Miscellaneous,
  -- Fishing Poles, spears...) count as usable by everyone.
  local CLASS_WEAPON = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [19] = true }
  local WEAPONS = {
    WARRIOR = " 0 1 2 3 4 5 6 7 8 10 13 15 16 18 ",
    PALADIN = " 0 1 4 5 6 7 8 ",
    HUNTER = " 0 1 2 3 6 7 8 10 13 15 16 18 ",
    ROGUE = " 2 3 4 7 13 15 16 18 ",
    PRIEST = " 4 10 15 19 ",
    SHAMAN = " 0 1 4 5 10 13 15 ",
    MAGE = " 7 10 15 19 ",
    WARLOCK = " 7 10 15 19 ",
    DRUID = " 4 5 10 13 15 ",
  }
  -- "never", "later" (more than SOON levels away), or nil (usable now or soon, or unknown). class and level
  -- default to this character's.
  function KS.UnusableReason(classID, subclassID, minLevel, class, level)
    class = class or (UnitClass and select(2, UnitClass("player")))
    level = level or (UnitLevel and UnitLevel("player")) or 1
    local from = 1
    if classID == ARMOR_CLASS and CLASS_ARMOR[subclassID] then
      local wears = ARMOR[class]
      if not wears then return nil end
      from = wears[subclassID]
      if not from then return "never" end
    elseif classID == WEAPON_CLASS and CLASS_WEAPON[subclassID] then
      local trains = WEAPONS[class]
      if not trains then return nil end
      if not trains:find(" " .. subclassID .. " ", 1, true) then return "never" end
    elseif classID ~= ARMOR_CLASS and classID ~= WEAPON_CLASS then
      return nil
    end
    if math.max(from, minLevel or 0) > level + SOON then return "later" end
    return nil
  end

  -- Enchanters keep green and better gear they can't use: they disenchant it.
  function KS.IsEnchanter()
    local profs = MyProfessions()
    return ((profs and profs.Enchanting) or (cdb and cdb.scanned and cdb.scanned.Enchanting)) and true or false
  end
end

-- The level the rules give an item, false when the rules leave it alone for good, or nil when it
-- can't be decided yet (item data not loaded, or the deciding rule is off: decide again later).
-- The second value is "char" when the decision is for this character only.
local function AutoLevel(info, bag, slot)
  local id = info.itemID
  local name, _, _, _, minLevel, _, _, _, equipLoc, _, _, classID, subclassID, bindType, _, _, isCrafting = GetItemInfo(id)
  if not name then return nil end
  if KS.IsPersonal(id) then return false end -- consumables, reagents, vendor trade goods
  if KS.IsProfessionTool(id) then return false end -- fishing poles, mining picks, hammers...
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
  -- Soulbound gear this character can't use (or not for more than a few levels): Junk, on this character only. Not a
  -- BoE item that's become soulbound: that copy is yours, and never takes its item's Junk mark (Copies.lua).
  if info.isBound and (classID == WEAPON or classID == ARMOR) and not NEVER_JUNK_SLOT[equipLoc]
      and KS.BindKind(id) ~= "boe" and KS.UnusableReason(classID, subclassID, minLevel) then
    if not auto.unusableJunk then return nil end
    if (quality or 0) >= 2 and KS.IsEnchanter() then return false, "char" end -- theirs to disenchant
    return JUNK, "char"
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
    KS.Notify("%s is no longer %s: you %s.", link or ItemLink(id), LevelText(mine), how)
    RefreshBags()
  end
  local auto = db.autoMarked[id]
  if auto and db.items[id] == auto and not cdb.items[id] then
    KS.SetLevel(id, NORMAL, link, { scope = "char", quiet = true })
    KS.Notify("%s was %s; you %s, so it's Normal on this character.", link or ItemLink(id), LevelText(auto), how)
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
  local n, tools = 0, 0
  -- Both account-wide and this character's own auto-marks (older builds marked crafting materials,
  -- Light Feathers among them, Mail per character). Profession tools too: 1.0.0 marked white ones Junk.
  for _, store in ipairs({ db, cdb }) do
    for id, level in pairs(store.autoMarked) do
      local tool = KS.IsProfessionTool(id)
      if tool or KS.IsPersonal(id) then
        if store.items[id] == level then store.items[id] = nil end
        store.autoMarked[id] = nil
        if tool then tools = tools + 1 else n = n + 1 end
      end
    end
  end
  if n > 0 then
    KS.Notify("Took auto-marks off %d consumables, reagents and vendor trade goods: mark those yourself, per character.", n)
  end
  if tools > 0 then
    KS.Notify("Took the auto-mark off %d profession tools (fishing poles, mining picks, hammers...): auto-marks leave tools alone now.", tools)
  end
  if n + tools > 0 then RefreshBags() end
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
    KS.Notify("Crafting materials are now Mail per character, and only when none of that character's professions use them. Took the old Mail mark off %d of them.", n)
    RefreshBags()
  end
end

local tradeOpen = false

local function AutoMark()
  if not db or tradeOpen then return end
  local marked = { [JUNK] = {}, [MAIL] = {}, here = {}, junkHere = {} }
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
          table.insert(here and (level == JUNK and marked.junkHere or marked.here) or marked[level], info.hyperlink)
        end
      end
    end
  end
  for _, key in ipairs({ JUNK, MAIL, "here", "junkHere" }) do
    local list = marked[key]
    if #list > 0 then
      local shown = table.concat(list, ", ", 1, math.min(#list, 5))
      if #list > 5 then shown = shown .. (" and %d more"):format(#list - 5) end
      if key == "here" then
        KS.Notify("Marked as %s on this character (none of your professions use them): %s. (/soc settings)",
          LevelText(MAIL), shown)
      elseif key == "junkHere" then
        KS.Notify("Marked as %s on this character (soulbound gear it can't use): %s. (/soc settings)", LevelText(JUNK), shown)
      else
        KS.Notify("Marked as %s: %s. (/soc settings to change this)", LevelText(key), shown)
      end
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
  unusableJunk = "Soulbound gear this character can't use (or not for 5+ levels) becomes |cff9d9d9dJunk|r, this character only",
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

  -- The simple options, always shown: how Alt+Click works, gray items become Junk, the intro and the Marked items
  -- window; then the switch for the advanced options (Simple.lua) and which of them are on.
  local prev = Header(panel, "Alt+Click in your bags", title, -16)
  local howNote = Note(panel, "", prev, 0, -6)
  refreshers[#refreshers + 1] = function()
    local w = KS.WrapWarning()
    howNote:SetText(KS.ClickText() .. (w and ("\n|cffff8040" .. w .. "|r") or ""))
  end
  panel.clickNote = howNote
  prev = Header(panel, "Marked for you", howNote)
  local gray = Check(panel, AUTO_TEXT.grayJunk, prev, -6, function(self) KS.SetAuto("grayJunk", self:GetChecked()) end)
  refreshers[#refreshers + 1] = function() gray:SetChecked(KS.GetAuto("grayJunk")) end
  panel.grayCheck = gray
  prev = Note(panel, "Standing Orders: Vendor sells Junk at any vendor. Items you got on purpose (traded, bought, or mailed to you by a player) are left alone.", gray, 26, -2)

  local intro = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  intro:SetSize(170, 24)
  intro:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -26, -18)
  intro:SetText("What Standing Orders protects")
  -- Fit the label (fonts and UI scale differ): its text width plus the button's end caps.
  local textW = intro.GetTextWidth and intro:GetTextWidth()
  if type(textW) == "number" and textW > 0 then intro:SetWidth(math.max(170, math.ceil(textW) + 32)) end
  panel.introButton = intro
  intro:SetScript("OnClick", function() KS:ShowIntro() end)
  local marks = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  marks:SetSize(150, 24)
  marks:SetPoint("LEFT", intro, "RIGHT", 8, 0)
  marks:SetText("Marked items")
  marks:SetScript("OnClick", function() KS.ShowMarkList() end)
  panel.marksButton = marks

  local advCheck = Check(panel, "Show advanced options", intro, -14, function(self)
    KS.SetShowAdvanced(self:GetChecked())
    KS.RefreshSettings()
  end)
  local advNote = Note(panel, "", advCheck, 26, -2)
  local simple = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  simple:SetSize(140, 22)
  simple:SetPoint("TOPLEFT", advNote, "BOTTOMLEFT", 0, -6)
  simple:SetText("Back to simple")
  simple:SetScript("OnClick", function() KS.AskBackToSimple() end)
  -- The advanced options sit in a frame of their own, so hiding it hides them all.
  local adv = CreateFrame("Frame", nil, panel)
  adv:SetPoint("TOPLEFT")
  adv:SetSize(1, 1)
  refreshers[#refreshers + 1] = function()
    local on = KS.AdvancedOn()
    advCheck:SetChecked(KS.GetShowAdvanced())
    advNote:SetText(#on == 0 and "All advanced options are at their simple defaults."
      or ((#on == 1 and "1 advanced option is on: " or (#on .. " advanced options are on: ")) .. table.concat(on, ", ") .. "."))
    simple:SetEnabled(#on > 0)
    adv[KS.GetShowAdvanced() and "Show" or "Hide"](adv)
  end
  panel.advCheck, panel.advNote, panel.simpleButton, panel.advanced = advCheck, advNote, simple, adv

  -- Advanced: the Alt+Click sequence (Clicks.lua): a preset, the editor, what Alt+Right-click does, the ends; or the menu.
  prev = Header(adv, "Alt+Click sequence", simple, -24)
  prev:SetPoint("TOPLEFT", simple, "BOTTOMLEFT", -26, -24)
  local cycle = Check(adv, "Alt+Click moves the mark along a sequence:", prev, -6, function()
    KS.SetAltClick("cycle")
    RefreshPanel()
  end)
  local seq, showSeq = ChoiceControl(adv, 180, function()
      return KS.ClickPreset() == "custom" and { "loop", "dial", "custom" } or { "loop", "dial" }
    end,
    function() return KS.ClickPreset() end,
    function(p) return KS.CLICK_PRESET_NAMES[p] end,
    function(p)
      if p ~= "custom" then KS.ApplyClickPreset(p) end
      local w = KS.WrapWarning()
      if w then Print("|cffff8040%s|r", w) end
    end)
  seq:SetPoint("LEFT", cycle.Text, "RIGHT", 10, 0)
  local editor = KS.ClickEditor(adv, RefreshPanel)
  editor:SetPoint("TOPLEFT", cycle, "BOTTOMLEFT", 26, -4)
  local function SetClickField(key, on)
    local c = KS.GetClick()
    c[key] = on and true or false
    KS.SetClick(c)
    local w = KS.WrapWarning()
    if w then Print("|cffff8040%s|r", w) end
    RefreshPanel()
  end
  local back = Check(adv, "Alt+Right-click goes back one step (off: it takes the mark off)", editor, -4, function(self) SetClickField("back", self:GetChecked()) end)
  local ends = Check(adv, "Loop around at the ends (off: stop at the first and last mark)", back, -2, function(self) SetClickField("loop", self:GetChecked()) end)
  local menuMode = Check(adv, "Alt+Click opens a menu to pick the mark instead", ends, -6, function()
    KS.SetAltClick("menu")
    RefreshPanel()
  end)
  menuMode:SetPoint("TOPLEFT", ends, "BOTTOMLEFT", -26, -6)
  refreshers[#refreshers + 1] = function()
    local c = KS.GetClick()
    cycle:SetChecked(KS.GetAltClick() == "cycle")
    menuMode:SetChecked(KS.GetAltClick() == "menu")
    back:SetChecked(c.back)
    ends:SetChecked(c.loop)
    showSeq()
    editor.Refresh()
  end
  panel.altClickChecks, panel.clickChoice, panel.clickEditor = { cycle = cycle, menu = menuMode }, seq, editor
  panel.clickBack, panel.clickEnds = back, ends

  -- Advanced: the other auto-marks.
  prev = Header(adv, "More auto-marks", menuMode)
  local first = true
  for _, key in ipairs(AUTO_KEYS) do
    if key ~= "grayJunk" then
      local cb = Check(adv, AUTO_TEXT[key], prev, first and -6 or -2, function(self)
        KS.SetAuto(key, self:GetChecked())
        RefreshPanel()
      end)
      if key == "keepReceived" then cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10) end
      refreshers[#refreshers + 1] = function() cb:SetChecked(KS.GetAuto(key)) end
      prev, first = cb, false
    end
  end
  prev = Note(adv, "Only unmarked items, each item only once: if you change an auto-marked item's level, it stays changed. Quest items, enchanting materials, profession tools (fishing poles, mining picks, hammers...), bags, ammo, recipes, shirts and tabards are left alone, and so is anything VendorFlip is holding. Open each of your profession windows once so Custodian knows which materials your recipes use. Junk and BoE Mail marks apply to all your characters. Soulbound gear counts as usable when the class can train that weapon type or will wear that armor within 5 levels (Mail at 40 for Hunters and Shamans, Plate at 40 for Warriors and Paladins); enchanters keep green and better to disenchant.\n\nNever auto-marked, and marked per character when you mark them: consumables (food, drink, potions, scrolls...), reagents (ankhs, feathers...) and trade goods sold by vendors (thread, vials, flux, dyes, salt...).", prev, 26, -2)

  -- Advanced: where new marks go (Alt+Click, the mark menu, /soc <level>).
  local scopeHeader = Header(adv, "Default marking", prev)
  scopeHeader:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -26, -18)
  local scopeLabel = adv:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  scopeLabel:SetPoint("TOPLEFT", scopeHeader, "BOTTOMLEFT", 4, -10)
  scopeLabel:SetText("New marks apply")
  local scopeChoice, showScope = ChoiceControl(adv, 160, function() return KS.SCOPES end, KS.GetScope,
    function(c) return KS.SCOPE_NAMES[c] or c end, function(c) KS.SetScope(c) end)
  scopeChoice:SetPoint("LEFT", scopeLabel, "RIGHT", 10, 0)
  refreshers[#refreshers + 1] = showScope
  panel.scopeChoice = scopeChoice
  prev = Note(adv, "Account wide: to all your characters. Per character: to this one. Per copy: to just the item you Alt+Click (an item that stacks gets an item mark instead; /soc <level> <item> marks the item). Soulbound items are always marked per copy. Alt+Shift+Left-click an item in your bags to move its mark between all characters and this one.", scopeLabel, -4, -14)

  -- Advanced: Custodian's own messages in chat.
  local chatHeader = Header(adv, "Chat", prev)
  chatHeader:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -26, -18)
  local chatLabel = adv:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  chatLabel:SetPoint("TOPLEFT", chatHeader, "BOTTOMLEFT", 4, -10)
  chatLabel:SetText("Chat logging")
  local chatChoice, showChat = ChoiceControl(adv, 160, KS.ChatLevels, KS.ChatLevel,
    function(c) return KS.CHAT_LEVEL_NAMES[c] or c end, function(c) KS.SetChatLevel(c) end)
  chatChoice:SetPoint("LEFT", chatLabel, "RIGHT", 10, 0)
  refreshers[#refreshers + 1] = showChat
  panel.chatChoice = chatChoice
  prev = Note(adv, "Off: only warnings and replies to your commands. Basic: also what Custodian did on its own (auto-marks, buybacks, items moved back, blocked actions) and the replies to your Alt+Clicks (\"... is now Junk.\"). Verbose (dev builds): debugging detail too. Everything is kept in the log either way (/soc log); the red error always shows on screen.", chatLabel, -4, -14)

  -- Equipment sets: the default for sets, then one row per set on this character, rebuilt each time the
  -- panel opens. Last on the panel, since the number of rows changes. Each row is a dropdown (a cycling button on clients without one).
  local DEFAULT_CHOICES = CONFIRM_ENABLED and { CONFIRM, LOCK, ONME, "off" } or { LOCK, ONME, "off" }
  local SET_CHOICES = CONFIRM_ENABLED and { "default", CONFIRM, LOCK, ONME, "off" } or { "default", LOCK, ONME, "off" }
  -- Mark icons: size, position and opacity, with a sample bag button that shows the result.
  local iconHeader = Header(adv, "Mark icons on bag items", prev)
  iconHeader:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -26, -22)
  prev = iconHeader
  local iconRows = {}
  local function IconRow(i, label)
    local fs = adv:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12 - (i - 1) * 26)
    fs:SetWidth(80)
    fs:SetJustifyH("LEFT")
    fs:SetText(label)
    iconRows[i] = fs
    return fs
  end
  local function Stepper(i, label, key)
    local fs = IconRow(i, label)
    local minus = CreateFrame("Button", nil, adv, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    minus:SetText("-")
    local value = adv:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(230) -- "70% opaque (30% see-through)" on one line
    local plus = CreateFrame("Button", nil, adv, "UIPanelButtonTemplate")
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
  local pos, showPos = ChoiceControl(adv, 290, function() return ICON_ANCHORS end,
    function() return select(2, KS.GetIconStyle()) end,
    function(a) return ANCHOR_TEXT[a] or a end,
    function(a) KS.SetIconStyle("anchor", a) end)
  pos:SetPoint("LEFT", posLabel, "RIGHT", 10, 0)
  local alphaText, alphaMinus, alphaPlus = Stepper(3, "Opacity", "alpha")
  local styleLabel = IconRow(4, "Style")
  local styleChoice, showStyle = ChoiceControl(adv, 200, function() return KS.ICON_STYLES end,
    function() return KS.GetIconStyleName() end,
    function(s) return KS.ICON_STYLE_NAMES[s] or s end,
    function(s) KS.SetIconStyle("style", s) end)
  styleChoice:SetPoint("LEFT", styleLabel, "RIGHT", 10, 0)
  local compare = CreateFrame("Button", nil, adv, "UIPanelButtonTemplate")
  compare:SetSize(120, 22)
  compare:SetPoint("LEFT", styleChoice, "RIGHT", 10, 0)
  compare:SetText("Compare styles")
  compare:SetScript("OnClick", function() KS.ShowIconCompare() end)
  panel.iconStyle = { sizeMinus = sizeMinus, sizePlus = sizePlus, pos = pos, alphaMinus = alphaMinus, alphaPlus = alphaPlus,
    style = styleChoice, compare = compare }

  local sample = CreateFrame("Frame", nil, adv)
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
    showStyle()
    KS.StyleIcon(mark, sample)
    KS.MarkTexture(mark, LOCK)
    KS.MarkEdge(sample, mark, LOCK)
  end

  local highlight = Check(adv, "At a vendor or the mailbox, tint items: red can't go, blue is marked for it", iconRows[4], -10, function(self)
    KS.SetHighlight(self:GetChecked())
    RefreshPanel()
  end)
  refreshers[#refreshers + 1] = function() highlight:SetChecked(KS.GetHighlight()) end
  panel.highlightCheck = highlight
  local highlightNote = Note(adv, "Vendor: red for Locked, Always on me and Disenchant, blue for Junk. Mailbox: red for Locked and Always on me, blue for Mail.", highlight, 26, -2)

  prev = Header(adv, "Equipment sets protect their items", highlightNote, -22)
  prev:SetPoint("TOPLEFT", highlightNote, "BOTTOMLEFT", -26, -22)
  local setsNote = Note(adv, "", prev, 0, -6)
  local rows = {}
  panel.setRows = rows
  local function Row(i)
    if rows[i] then return rows[i] end
    local r = {}
    r.label = adv:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.label:SetPoint("TOPLEFT", setsNote, "BOTTOMLEFT", 0, -12 - (i - 1) * 26)
    r.label:SetWidth(180)
    r.label:SetJustifyH("LEFT")
    r.button, r.show = ChoiceControl(adv, 240, function() return r.setID and SET_CHOICES or DEFAULT_CHOICES end,
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
    if not adv:IsShown() then last = simple end -- advanced options hidden: the simple ones end at Back to simple
    local bottom = last:GetBottom()
    if type(top) == "number" and type(bottom) == "number" then panel:SetHeight(math.max(1, top - bottom + 24)) end
  end
  outer.FitPanel = FitPanel
  outer:SetScript("OnShow", function()
    RefreshPanel()
    FitPanel()
    C_Timer.After(0, FitPanel) -- positions settle after the first frame
  end)
  -- After a change from outside the page (Back to simple): refresh it and fit its height to what's shown.
  KS.RefreshSettings = function() RefreshPanel(); FitPanel() end
  outer.setRows, outer.iconStyle, outer.iconSample, outer.introButton = panel.setRows, panel.iconStyle, panel.iconSample, panel.introButton
  outer.chatCheck, outer.clickChoice, outer.clickNote = panel.chatCheck, panel.clickChoice, panel.clickNote
  outer.scopeChoice = panel.scopeChoice
  outer.altClickChecks, outer.marksButton = panel.altClickChecks, panel.marksButton
  outer.advCheck, outer.advNote, outer.simpleButton, outer.advanced = panel.advCheck, panel.advNote, panel.simpleButton, panel.advanced
  outer.clickEditor, outer.clickBack, outer.clickEnds, outer.grayCheck = panel.clickEditor, panel.clickBack, panel.clickEnds, panel.grayCheck
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
    local copyLevel = KS.TooltipCopyLevel and KS.TooltipCopyLevel(data) -- this copy's (Copies.lua)
    if copyLevel then level, from = copyLevel, " |cff9d9d9d(this copy)|r" end
    if level ~= NORMAL then tip:AddLine("Standing Orders: " .. LevelText(level) .. from) end
  end)
end

---------------------------------------------------------------------------------------------------
-- One-time intro: what the marks mean, what's marked for you, what Locked protects and what it doesn't yet,
-- and which bags it works with. Shown until "Got it" is clicked; bump INTRO_VERSION when it changes so
-- everyone sees the new one once. Built from separate lines (headings, indented bullets, small gaps)
-- so it reads as sections, not one block of text.

local INTRO_VERSION = 7
do -- the intro's helpers stay out of the main chunk's 200-local limit
local GOLD, GREEN, ORANGE, MUTED = "ffffd100", "ff33ff99", "ffff8040", "ffbbbbbb"
-- One table, not four locals: the main chunk is at Lua's 200-local limit, and locals in this do block count too.
local PATHS = {
  ready = "Interface\\RaidFrame\\ReadyCheck-Ready", -- the check after a bag addon in use
  addon = "Interface\\Icons\\INV_Misc_Bag_10", -- an installed bag addon with no icon of its own
  missing = "Interface\\COMMON\\Indicator-Gray", -- a supported bag addon that isn't installed
  bag = "Interface\\Icons\\INV_Misc_Bag_08", -- Blizzard bags
}
local function Tex(path) return "|T" .. path .. ":16:16|t" end
local function Colored(color, text) return "|c" .. color .. text .. "|r" end -- pipes:ok (a color escape built from its parts)
local function LevelLine(level, text) return KS.IconTag(level) .. " " .. Colored(COLORS[level], NAMES[level]) .. ": " .. text end

-- The intro's view helpers, in one table: the main chunk is at Lua's 200-local limit.
local UI = {}

-- The short view, shown by default: how to change a mark (as Alt+Click is set up now), the marks, and where
-- to see them all. { text, indent, gap before (pixels), font }
function UI.ShortLines()
  local legend, onme = {}, false
  for _, level in ipairs(KS.ShownLevels()) do -- Always on me only when it's in use (Simple.lua)
    legend[#legend + 1] = (ICONS[level] and (KS.IconTag(level) .. " ") or "") .. Colored(COLORS[level], NAMES[level])
    onme = onme or level == ONME
  end
  return {
    { Colored(GOLD, "In short"), 0, 0, "GameFontNormalLarge" },
    { KS.ClickText(), 0, 6 },
    { table.concat(legend, "    "), 10, 8 },
    { Colored(COLORS[LOCK], NAMES[LOCK]) .. " items can't be sold, disenchanted, destroyed, traded or mailed by accident"
      .. (onme and ("; " .. Colored(COLORS[ONME], NAMES[ONME]) .. " also keeps them out of the bank.") or "."), 0, 8 },
    { "See and change every mark, with a search box: /soc list. Options: /soc settings.", 0, 8 },
  }
end

-- The detailed view. { text, indent, gap before (pixels), font }
local INTRO_LINES = {
  { Colored(GOLD, "Your marks"), 0, 0, "GameFontNormalLarge" },
  { "Marks are for all your characters. Alt+Shift+Left-click an item to keep its mark on this character only (or back again); /soc scope char makes that the default.", 0, 4 },
  { "", 0, 6 }, -- how Alt+Click works now (UI.FullLines)
  -- The marks' lines are made when shown (UI.FullLines), so their icons follow the icon style.
  { function() return LevelLine(JUNK, "happy to lose (Standing Orders: Vendor, coming soon, will sell them at any vendor)") end, 10, 4 },
  { function() return LevelLine(KS.LEVELS.DISENCHANT, "to disenchant: never sold (bought straight back), but free to disenchant, trade and mail") end, 10, 3 },
  { function() return LevelLine(MAIL, "to send to your bank character (Standing Orders: Mail, coming soon, will mail them)") end, 10, 3 },
  { function() return LevelLine(LOCK, "protected: never sold, disenchanted, destroyed, traded or mailed by accident") end, 10, 3 },
  { function() return LevelLine(ONME, "Locked, and also kept out of the bank") end, 10, 3 },
  { "See and change every mark, with a search box: /soc list. Pick one item's mark from a menu: /soc mark <item>.", 0, 6 },

  { Colored(GOLD, "Marked for you"), 0, 12, "GameFontNormalLarge" },
  -- A 5th field names the auto-mark rule a line describes: UI.FullLines leaves it out while that rule is off.
  { "• Grays: " .. Colored(COLORS[JUNK], "Junk"), 10, 4, nil, "grayJunk" },
  { "• White gear, weapons and junk with no profession or quest use: " .. Colored(COLORS[JUNK], "Junk"), 10, 2, nil, "whiteJunk" },
  { "• Soulbound gear this character can't use: " .. Colored(COLORS[JUNK], "Junk") .. ", for this character only", 10, 2, nil, "unusableJunk" },
  { "• Unbound Bind on Equip items, green and up: " .. Colored(COLORS[MAIL], "Mail"), 10, 2, nil, "boeMail" },
  { "• Crafting materials none of this character's professions use: " .. Colored(COLORS[MAIL], "Mail") .. ", for this character only (enchanting materials are left alone)", 10, 2, nil, "matsMail" },
  { "• Never items traded to you, bought (AH or vendor) or mailed to you by a player", 10, 2, nil, "keepReceived" },
  { "• Never profession tools (fishing poles, mining picks, hammers...)", 10, 2 },
  { "• Never consumables, reagents or vendor trade goods (thread, vials...); when you mark one, the mark is for this character only", 10, 2 },
  { "", 10, 4, nil, "more" }, -- where to change these (UI.FullLines)

  { Colored(GREEN, "Protected against"), 0, 12, "GameFontNormalLarge" },
  { "• Selling it: it's bought straight back while the vendor is open", 10, 4 },
  { "• Disenchant, Prospecting, Milling: the click is blocked", 10, 2 },
  { "• Destroying: the delete popup closes", 10, 2 },
  { "• Trade and mail: the item is taken back out", 10, 2 },
  { "• Bank (Always on me only): it's moved straight back to your bags", 10, 2 },

  { Colored(GREEN, "Still allowed"), 0, 12, "GameFontNormalLarge" },
  { "• Applying enchants, oils and scrolls", 10, 4 },

  { Colored(ORANGE, "Not protected yet"), 0, 12, "GameFontNormalLarge" },
  { "• Auction house posting", 10, 4 },
  { "• Using or eating the item, or handing it to an NPC", 10, 2 },
  { "• Closing the vendor right after a sale, before it can be bought back", 10, 2 },
  { "• Not yet supported bag addons: no Alt+Click, icons or Disenchant block", 10, 2 },

  { Colored(GOLD, "Works with these bags"), 0, 12, "GameFontNormalLarge" },
  { Colored(MUTED, "Green with a check: in use now. White: installed. Gray: not installed."), 10, 2 },
}

-- The detailed view as things are set up now: its Alt+Click line, and only the auto-mark rules that are on.
function UI.FullLines()
  INTRO_LINES[3][1] = KS.ClickText() .. " /soc settings has other sequences, and a menu instead. The marks:"
  local out, off = {}, false
  for _, line in ipairs(INTRO_LINES) do
    local rule = line[5]
    if rule == "more" then
      line[1] = Colored(MUTED, off and "More rules (white gear, Bind on Equip items, crafting materials...) are in /soc settings, under Show advanced options."
        or "Change any of this in /soc settings.")
      out[#out + 1] = line
    elseif rule and not KS.GetAuto(rule) then
      off = true
    elseif type(line[1]) == "function" then
      out[#out + 1] = { line[1](), line[2], line[3], line[4] }
    else
      out[#out + 1] = line
    end
  end
  return out
end

-- The supported bags: { label, addon folder (nil = built in), old name }. The label matches the adapter's name;
-- an old name is the addon's earlier name, still supported (Bagnonium was Combuctor).
local BAG_LIST = {
  { "Blizzard bags" }, { "ArkInventory", "ArkInventory" }, { "Bagnon", "Bagnon" }, { "Bagnonium", "Bagnonium", "Combuctor" },
  { "Baganator", "Baganator" }, { "AdiBags", "AdiBags" }, { "BetterBags", "BetterBags" }, { "ElvUI bags", "ElvUI" },
}

local function AddonMeta(folder, key)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if not get then return nil end
  local ok, value = pcall(get, folder, key)
  return ok and value or nil
end

-- One bag list entry: green with its own icon and a check at the end when Custodian is hooked into it (no
-- "(in use)" words, so "Bagnonium (was Combuctor)" stays on one line), white with its own icon when it's
-- installed, gray with a gray dot when it isn't. Only an addon in use gets a check.
local function BagEntry(entry)
  local label, folder, old = entry[1], entry[2], entry[3]
  if not folder then return Tex(PATHS.bag) .. " " .. label .. " " .. Colored(MUTED, "(built in)") end
  local was = old and (" " .. Colored(MUTED, "(was " .. old .. ")")) or ""
  for _, adapter in ipairs(bagAddons) do
    if (adapter.name == label or adapter.name == old) and adapter.active then
      local icon = AddonMeta(folder, "IconTexture") or (old and AddonMeta(old, "IconTexture")) or PATHS.addon
      return Tex(icon) .. " " .. Colored(GREEN, label) .. was .. " " .. Tex(PATHS.ready)
    end
  end
  for _, name in ipairs({ folder, old }) do
    if AddonMeta(name, "Title") then return Tex(AddonMeta(name, "IconTexture") or PATHS.addon) .. " " .. label .. was end
  end
  return Tex(PATHS.missing) .. " " .. Colored(MUTED, label) .. was
end

-- The intro's words, for the self-test and smoke checks: the detailed view (with the bag list), or with
-- view "short" the short one.
function KS.IntroText(view)
  local out = {}
  for _, line in ipairs(view == "short" and UI.ShortLines() or UI.FullLines()) do out[#out + 1] = line[1] end
  if view ~= "short" then
    for _, entry in ipairs(BAG_LIST) do out[#out + 1] = BagEntry(entry) end
  end
  return table.concat(out, "\n")
end

local intro

-- Places lines top-down from y, reusing pool's font strings (and hiding the ones it doesn't need).
-- Returns the y under the last line.
function UI.Place(pool, lines, y)
  for i, line in ipairs(lines) do
    local text, indent, gap, font = line[1], line[2] or 0, line[3] or 0, line[4] or "GameFontHighlight"
    local fs = pool[i]
    if not fs then
      fs = intro:CreateFontString(nil, "OVERLAY", font)
      pool[i] = fs
    end
    fs:SetFontObject(font)
    y = y - gap
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 18 + indent, y)
    fs:SetWidth(444 - indent)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    fs:SetText(text)
    fs:Show()
    y = y - fs:GetStringHeight()
  end
  for i = #lines + 1, #pool do pool[i]:Hide() end
  return y
end

-- Lays the intro out in its view: short (the default) or detailed (StandingOrdersCustodianDB.introDetails).
function UI.Layout()
  local detailed = db.introDetails and true or false
  local y = -36
  if detailed then
    UI.Place(intro.shortPool, {}, y)
    y = UI.Place(intro.fullPool, UI.FullLines(), y) - 6
    -- The bag list: two columns, refreshed every time (bag addons hook in after login).
    for i, entry in ipairs(BAG_LIST) do
      local fs = intro.bags[i]
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 28 + col * 222, y - row * 22)
      fs:SetText(BagEntry(entry))
      fs:Show()
    end
    y = y - math.ceil(#BAG_LIST / 2) * 22
  else
    UI.Place(intro.fullPool, {}, y)
    for _, fs in ipairs(intro.bags) do fs:Hide() end
    y = UI.Place(intro.shortPool, UI.ShortLines(), y)
  end
  intro.detailed = detailed
  intro.toggle:SetText(detailed and "Show less" or "Show details")
  intro:SetSize(480, -y + 56)
end

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

    intro.shortPool, intro.fullPool, intro.bags = {}, {}, {}
    for i = 1, #BAG_LIST do
      local fs = intro:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetWidth(212)
      fs:SetJustifyH("LEFT")
      intro.bags[i] = fs
    end

    intro.toggle = CreateFrame("Button", nil, intro, "UIPanelButtonTemplate")
    intro.toggle:SetSize(120, 24)
    intro.toggle:SetPoint("BOTTOMLEFT", 18, 14)
    intro.toggle:SetScript("OnClick", function()
      db.introDetails = not db.introDetails
      UI.Layout()
    end)

    local ok = CreateFrame("Button", nil, intro, "UIPanelButtonTemplate")
    ok:SetSize(110, 24)
    ok:SetPoint("BOTTOMRIGHT", -18, 14)
    ok:SetText("Got it")
    ok:SetScript("OnClick", function()
      db.introSeen = INTRO_VERSION
      intro:Hide()
      Print("You can reopen this with /soc intro.")
    end)
    intro.ok = ok
    tinsert(UISpecialFrames, "SOCustodianIntro") -- Esc closes it (it shows again next login until "Got it")
  end
  UI.Layout()
  intro:Show()
end
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
  { id = 6256, want = false, why = "profession tool" },               -- Fishing Pole
  { id = 2901, want = false, why = "profession tool" },               -- Mining Pick
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
    -- Vendor and mailbox tints (Highlights.lua): red for what can't go, blue for what's marked for it.
    local H = KS.HighlightColor
    local tintOk = H and H(LOCK, "vendor") and H(KS.LEVELS.DISENCHANT, "vendor") and H(JUNK, "vendor")
      and not H(MAIL, "vendor") and H(LOCK, "mail") and H(MAIL, "mail") and not H(KS.LEVELS.DISENCHANT, "mail")
      and not H(NORMAL, "vendor") and not H(NORMAL, "mail")
    d[#d + 1] = Detail("vendor and mailbox tints", tintOk and "right" or "WRONG", tintOk and "pass" or "fail")
    -- Copy marks (Copies.lua): what a soulbound copy takes from its item's mark, and item GUIDs on this client.
    local S = KS.SoulboundLevel
    local boundOk = S and S(0, MAIL) == NORMAL and S(0, LOCK) == LOCK and S(0, ONME) == ONME
    d[#d + 1] = Detail("soulbound copies: no Mail mark, protection kept", boundOk and "right" or "WRONG", boundOk and "pass" or "fail")
    local guids = C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot and true or false
    d[#d + 1] = Detail("item GUIDs for copy marks", guids and ("yes; %d copy marks on this character"):format(#KS.MarkedCopies())
      or "not on this client: no copy marks", guids and "pass" or "warn")
    -- Chat logging (ChatLog.lua): a known level; with no saved choice, basic in a dev build and off in a release.
    local chosen = db and db.chatLog
    local level = KS.ChatLevel()
    local chatOk = KS.CHAT_LEVEL_NAMES[level] ~= nil and (chosen ~= nil or level == (KS.IsDevBuild() and "basic" or "off"))
    d[#d + 1] = Detail("chat logging", ("%s (%s, %s build)"):format(level, chosen and "chosen" or "default",
      KS.IsDevBuild() and "dev" or "release"), chatOk and "pass" or "fail")
    local devOk = KS.IsDevVersion("@project-version@") and KS.IsDevVersion("v1.1.0-9-g5cf6270")
      and KS.IsDevVersion("5cf6270") and KS.IsDevVersion("candidate/v1.2.0") and KS.IsDevVersion("dev")
      and KS.IsDevVersion("") and not KS.IsDevVersion("v1.1.0")
    d[#d + 1] = Detail("dev build check (token, git describe, bare hash, candidate tag, release)", devOk and "right" or "WRONG", devOk and "pass" or "fail")
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
    local seq = type(db.click) == "table" and #KS.GetClick().order >= 2
    d[#d + 1] = Detail("Alt+Click sequence", KS.CLICK_PRESET_NAMES[KS.ClickPreset()], seq and "pass" or "fail")
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
      else
        -- With its rule off (white gear is an advanced option), the item must be left alone. (Not "x and false
        -- or y": that always gives y.)
        local want = s.want
        if s.rule and not db.auto[s.rule] then want = false end
        local info = { itemID = s.id, quality = quality, hasNoValue = (sellPrice or 0) == 0, isBound = false }
        local got = AutoLevel(info)
        local ok = (got or false) == want
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
        get = function() return KS.ChatLevel() == "verbose" end,
        set = function(_, v) KS.SetChatLevel(v and "verbose" or nil) end,
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
  for _, c in ipairs(KS.MarkedCopies()) do
    any = true
    Print("%s: %s |cff9d9d9d(one copy%s)|r", LevelText(c.level), c.link or ItemLink(c.id), c.where == "bank" and ", in the bank" or "")
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
  elseif key == "style" then ok = KS.SetIconStyle("style", value)
  elseif key == "compare" then return KS.ShowIconCompare()
  elseif key == "reset" then
    for k, v in pairs(ICON_DEFAULTS) do KS.SetIconStyle(k, v) end
  elseif key ~= "" then ok = false end
  if not ok then return Err("Use /soc icon size 10-100, /soc icon position bottomleft||topleft||topright||bottomright||center, /soc icon opacity 10-100, /soc icon style game||addon, /soc icon compare or /soc icon reset.") end
  local size, anchor, alpha = KS.GetIconStyle()
  Print("Mark icons: %s, %d%% of the button's width, %s, %d%% opaque.", KS.ICON_STYLE_NAMES[KS.GetIconStyleName()], size, (ANCHOR_TEXT[anchor] or anchor):lower(), alpha)
end

local function Help()
  Print("Commands (/custodian works the same as /soc):")
  print("  /soc junk||disenchant||mail||normal||lock||onme <item link or ID> [char||account] - set an item's level (disenchant: kept from vendors, free to disenchant)")
  print("  /soc list [search] - the Marked items window: search, then change any mark (/soc list print: in chat)")
  print("  /soc sets - equipment sets and how they protect their items; /soc set <name> default||lock||onme||off")
  print("  /soc scope account||char||copy - where new marks go (now " .. KS.SCOPE_NAMES[KS.GetScope()]:lower() .. "; soulbound items are always marked per copy)")
  print("  /soc settings - auto-marking (Junk and Mail), where new marks go, mark icons and equipment sets")
  print("  /soc icon size 10-100 || position bottomleft||topleft||topright||bottomright||center || opacity 10-100 || style game||addon || compare || reset - mark icons on bag items (size: % of the button's width)")
  print("  /soc status - check which guards are active")
  print("  /soc intro - what the marks mean, what's protected (and what isn't yet) and which bags it works with")
  print("  /soc mark <item link or ID> - pick an item's mark from a menu")
  print("  /soc click loop||dial - the Alt+Click sequence: Quick loop or Protection dial (now " .. KS.CLICK_PRESET_NAMES[KS.ClickPreset()] .. ")")
  print("  /soc click order junk lock mail || right clear||back || ends loop||stop - your own sequence (marks: junk, mail, normal, lock, onme)")
  print("  /soc why <item> - would soulbound gear this character can't use become Junk? (no copy needed)")
  print("  /soc simple - put the advanced options back to their simple defaults (asks first; marks stay)")
  print("  /soc altclick cycle||menu - Alt+Click moves along the sequence, or opens the menu (now " .. KS.GetAltClick() .. ")")
  print("  /soc log off||basic||verbose - chat logging: basic adds Custodian's own messages (auto-marks, buybacks, blocked actions, Alt+Click replies), verbose debugging detail (now " .. KS.CHAT_LEVEL_NAMES[KS.ChatLevel()] .. ")")
  print("  /soc log [n] - the chat logging level and the last n log lines (default 25)")
  print("  /soc chat on||off - the same as /soc log basic or off; /soc debug - verbose on and off")
  print("  /soc highlight on||off - at a vendor or the mailbox, tint what can't go red and what's marked for it blue (now " .. (KS.GetHighlight() and "on" or "off") .. ")")
  print("  /soc selftest - check this install (results are saved for bug reports)")
  print("  In bags: " .. KS.ClickText())
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
  print("  new marks: " .. KS.SCOPE_NAMES[KS.GetScope()]:lower() .. "; copy marks on this character: " .. #KS.MarkedCopies())
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

local LEVEL_CMDS = { junk = JUNK, disenchant = KS.LEVELS.DISENCHANT, de = KS.LEVELS.DISENCHANT, mail = MAIL, normal = NORMAL, lock = LOCK, locked = LOCK, onme = ONME, always = ONME }
if CONFIRM_ENABLED then LEVEL_CMDS.confirm = CONFIRM end

-- /custodian always works: another addon (Pocket Social - Forever) also uses /soc, and which one wins is up to load order.
SLASH_SOC1 = "/soc"
SLASH_SOC2 = "/custodian"
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
    KS.SetLevel(id, LEVEL_CMDS[cmd], rest:match("|c.-|r") or ItemLink(id), { scope = scope, reply = true }) -- pipes:ok (a pattern)
  elseif cmd == "sets" or cmd == "set" then
    SetsCommand(rest)
  elseif cmd == "scope" and (rest == "char" or rest == "account" or rest == "copy") then
    KS.SetScope(rest)
    Print("New marks now go to %s (soulbound items: always the copy).", rest == "char" and "this character only"
      or rest == "copy" and "just the copy you Alt+Click" or "all characters")
  elseif cmd == "icon" or cmd == "icons" then
    IconCommand(rest)
  elseif cmd == "settings" or cmd == "config" or cmd == "options" then
    KS.OpenSettings()
  elseif cmd == "automail" and (rest == "on" or rest == "off") then -- older command: both Mail rules
    KS.SetAuto("boeMail", rest == "on")
    KS.SetAuto("matsMail", rest == "on")
    Print("Auto-marking Mail (BoE items and crafting materials) is %s.", rest)
  elseif cmd == "list" or cmd == "marks" then
    if rest == "print" then ListItems() else KS.ShowMarkList(rest ~= "" and rest or nil) end
  elseif cmd == "status" then
    Status()
  elseif cmd == "intro" or cmd == "protect" then
    KS:ShowIntro()
  elseif cmd == "mark" then
    local id = LinkID(rest) or tonumber(rest)
    if not id then return Err("Use /soc mark <shift-clicked item or item ID>.") end
    KS.ShowMarkMenu(id, rest:match("|c.-|r") or ItemLink(id)) -- pipes:ok (a pattern)
  elseif cmd == "altclick" and (rest == "cycle" or rest == "menu") then
    KS.SetAltClick(rest)
    Print("%s", KS.ClickText())
  elseif cmd == "click" or cmd == "clicks" then
    KS.ClickCommand(rest)
  elseif cmd == "why" then
    local id = LinkID(rest) or tonumber(rest)
    if not id then return Err("Use /soc why <shift-clicked item or item ID>.") end
    KS.WhyUnusable(id, rest:match("|c.-|r") or ItemLink(id)) -- pipes:ok (a pattern)
  elseif cmd == "highlight" then
    KS.HighlightCommand(rest)
  elseif cmd == "simple" then
    KS.AskBackToSimple()
  elseif cmd == "chat" then
    if rest == "on" or rest == "off" then KS.SetChat(rest == "on") else KS.SetChat(not KS.GetChat()) end
    Print("Chat logging: %s.", KS.CHAT_LEVEL_NAMES[KS.ChatLevel()])
  elseif cmd == "log" and KS.CHAT_LEVEL_NAMES[rest] then
    KS.SetChatLevel(rest)
    Print("Chat logging: %s.", KS.CHAT_LEVEL_NAMES[KS.ChatLevel()])
  elseif cmd == "log" then
    Print("Chat logging: %s (/soc log off||basic||verbose).", KS.CHAT_LEVEL_NAMES[KS.ChatLevel()])
    local log = db.log or {}
    local n = tonumber(rest) or 25
    Print("Last %d log lines (of %d):", math.min(n, #log), #log)
    for i = math.max(1, #log - n + 1), #log do print("  " .. log[i]) end
  elseif cmd == "selftest" or cmd == "test" then
    KS.SelfTest()
  elseif cmd == "debug" then
    KS.SetChatLevel(KS.ChatLevel() ~= "verbose" and "verbose" or nil) -- /soc debug: verbose on and off
    Print("Chat logging: %s.", KS.CHAT_LEVEL_NAMES[KS.ChatLevel()])
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
    local fresh = StandingOrdersCustodianDB == nil -- a new install, not one from 1.0.0 or a test build
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
    KS.MigrateChat(db) -- 1.1.0's chat and debug switches become chat logging levels (ChatLog.lua)
    KS.InitClick(db, fresh) -- the Alt+Click sequence: the Quick loop when new, 1.0.0's clicks otherwise
    db.auto = db.auto or {}
    if db.autoMail == false and db.auto.boeMail == nil then db.auto.boeMail = false end
    for key, on in pairs(AUTO_DEFAULTS) do
      -- An older install missing a rule gets 1.0.0's default for it: on, except unusableJunk.
      if db.auto[key] == nil then db.auto[key] = on or (not fresh and key ~= "unusableJunk") end
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
    C_Timer.After(5, KS.OfferQuickLoop) -- 1.0.0 players only, once, after the intro
    C_Timer.After(6, KS.CheckWrapWarning) -- after the other Standing Orders addons have loaded their settings
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
