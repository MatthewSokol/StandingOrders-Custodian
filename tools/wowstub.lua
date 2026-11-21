-- Minimal WoW API stubs to load Custodian and drive it from tools/smoke.lua. Only what Custodian touches.
-- Events Custodian registers without pcall must be listed here: an unknown event throws in the real game
-- and stops the file loading, so add one only after checking it exists on Forever.
KNOWN_EVENTS = {
  ADDON_LOADED = true, PLAYER_LOGIN = true, MERCHANT_SHOW = true, MERCHANT_CLOSED = true, MERCHANT_UPDATE = true,
  BANKFRAME_OPENED = true, BANKFRAME_CLOSED = true, PLAYERBANKSLOTS_CHANGED = true, BAG_UPDATE_DELAYED = true,
  TRADE_PLAYER_ITEM_CHANGED = true, TRADE_SHOW = true, TRADE_CLOSED = true, TRADE_ACCEPT_UPDATE = true,
  MAIL_SEND_INFO_UPDATE = true, MAIL_CLOSED = true, EQUIPMENT_SETS_CHANGED = true, CURRENT_SPELL_CAST_CHANGED = true, UNIT_SPELLCAST_SENT = true,
  TRADE_SKILL_SHOW = true, TRADE_SKILL_UPDATE = true,
}

local frames = {}
local function stub(name)
  local o = { __name = name }
  return setmetatable(o, { __index = function(t, k)
    return function(self, ...)
      local a = { ... }
      if k == "CreateTexture" or k == "CreateFontString" then return stub(name .. "." .. k) end
      if k == "GetFrameLevel" or k == "GetEffectiveScale" then return 1 end
      if k == "GetStringHeight" then return 100 end
      if k == "GetText" then return rawget(t, "__text") or "" end
      if k == "SetText" then rawset(t, "__text", a[1]); return end
      if k == "GetTextWidth" or k == "GetStringWidth" then return 7 * #(rawget(t, "__text") or "") end -- ~7px a letter
      if k == "SetSize" then rawset(t, "__w", a[1]); return end
      if k == "SetWidth" then rawset(t, "__w", a[1]); return end
      if k == "GetWidth" then return rawget(t, "__w") end
      if k == "IsShown" or k == "IsVisible" then return rawget(t, "__shown") or false end
      if k == "Show" then rawset(t, "__shown", true); return end
      if k == "Hide" then rawset(t, "__shown", false); return end
      if k == "SetScript" then rawset(t, "__s_" .. a[1], a[2]); return end
      if k == "GetScript" then return rawget(t, "__s_" .. a[1]) end
      if k == "HookScript" then rawset(t, "__h_" .. a[1], a[2]); return end
      if k == "SetChecked" then rawset(t, "__checked", a[1] and true or false); return end
      if k == "GetChecked" then return rawget(t, "__checked") or false end
      if k == "RegisterEvent" or k == "RegisterUnitEvent" then
        if not KNOWN_EVENTS[a[1]] then error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. tostring(a[1]) .. "\"", 2) end
        local ev = rawget(t, "__ev") or {}; ev[a[1]] = true; rawset(t, "__ev", ev); return
      end
      if k == "GetID" then return rawget(t, "__id") or 0 end
      if k == "SetupMenu" then rawset(t, "__menu", a[1]); return end -- DropdownButton: MENU_RADIOS() reads it
      return nil
    end
  end })
end
STUB = stub
function CreateFrame(kind, name, parent, template)
  local f = stub(name or kind)
  frames[#frames + 1] = f
  if name then _G[name] = f end
  if template == "UICheckButtonTemplate" then rawset(f, "Text", stub("Text")) end
  return f
end
function FIRE(event, ...)
  for _, f in ipairs(frames) do
    local ev, fn = rawget(f, "__ev"), rawget(f, "__s_OnEvent")
    if ev and ev[event] and fn then
      local ok, err = xpcall(fn, debug.traceback, f, event, ...)
      if not ok then print("ERROR in " .. event .. ": " .. err) end
    end
  end
end
function CALL(label, fn, ...)
  if type(fn) ~= "function" then print("ERROR " .. label .. ": not a function"); return end
  local ok, err = xpcall(fn, debug.traceback, ...)
  print((ok and "ok    " or "ERROR ") .. label .. (ok and "" or (": " .. err)))
end
-- A dropdown's menu as a list of radios { text, selected(), pick() }, built like the game's menu system does.
function MENU_RADIOS(dropdown)
  local gen, radios = rawget(dropdown, "__menu"), {}
  if not gen then return radios end
  gen(dropdown, { CreateRadio = function(_, text, isSelected, onSelect)
    radios[#radios + 1] = { text = text, selected = isSelected, pick = onSelect }
  end })
  return radios
end
function CHECK(label, cond, got)
  print((cond and "ok    " or "FAIL  ") .. label .. (cond and "" or ("  (got " .. tostring(got) .. ")")))
end
-- Timers wait in STUB_TIMERS; RUN_TIMERS() runs them (and any they add) like time passing.
C_Timer = { After = function(t, f) STUB_TIMERS[#STUB_TIMERS + 1] = f end }
STUB_TIMERS = {}
function RUN_TIMERS()
  for _ = 1, 20 do
    local list = STUB_TIMERS
    if #list == 0 then return end
    STUB_TIMERS = {}
    for _, f in ipairs(list) do
      local ok, err = xpcall(f, debug.traceback)
      if not ok then print("ERROR in timer: " .. err) end
    end
  end
end

-- Chat output is captured so the smoke script can look for messages.
CHAT = {}
DEFAULT_CHAT_FRAME = stub("ChatFrame")
rawset(DEFAULT_CHAT_FRAME, "AddMessage", function(_, msg) CHAT[#CHAT + 1] = msg end)
UIErrorsFrame = stub("UIErrorsFrame")
rawset(UIErrorsFrame, "AddMessage", function(_, msg) CHAT[#CHAT + 1] = "ERRFRAME " .. tostring(msg) end)
function CHAT_HAS(text)
  for _, line in ipairs(CHAT) do if tostring(line):find(text, 1, true) then return true end end
  return false
end

-- Items: STUB_ITEMDB[id] = { name, quality, sellPrice, classID, subclassID, bindType, isCrafting, equipLoc }
STUB_ITEMDB = {}
local function link(id) return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. (STUB_ITEMDB[id] and STUB_ITEMDB[id].name or id) .. "]|h|r" end
STUB_LINK = link
local function info(id)
  local i = STUB_ITEMDB[id]
  if not i then return nil end
  return i.name, link(id), i.quality, 1, 1, "", "", 20, i.equipLoc or "", 134400, i.sellPrice or 0,
    i.classID, i.subclassID or 0, i.bindType or 0, 0, nil, i.isCrafting or false
end
GetItemInfo = info
C_Item = {
  GetItemInfo = info,
  GetItemInfoInstant = function(id)
    local i = STUB_ITEMDB[id]
    if not i then return nil end
    return id, "", "", i.equipLoc or "", 134400, i.classID, i.subclassID or 0
  end,
  RequestLoadItemDataByID = function() end,
}
-- Bags: STUB_BAGS[bag][slot] = itemID (stack of 1, unbound unless STUB_BOUND[id])
STUB_BAGS = {}
STUB_BOUND = {}
C_Container = {
  GetContainerNumSlots = function(bag) return STUB_BAGS[bag] and 16 or 0 end,
  GetContainerNumFreeSlots = function(bag)
    if not STUB_BAGS[bag] or bag < 0 or bag > 4 then return 0, 0 end
    local used = 0
    for _ in pairs(STUB_BAGS[bag]) do used = used + 1 end
    return 16 - used, 0
  end,
  GetContainerItemInfo = function(bag, slot)
    local id = STUB_BAGS[bag] and STUB_BAGS[bag][slot]
    local i = id and STUB_ITEMDB[id]
    if not i then return nil end
    return { itemID = id, hyperlink = link(id), quality = i.quality, stackCount = 1, isLocked = false,
      isBound = STUB_BOUND[id] or false, hasNoValue = (i.sellPrice or 0) == 0, iconFileID = 134400 }
  end,
  GetContainerItemQuestInfo = function() return { isQuestItem = false } end,
  PickupContainerItem = function(bag, slot)
    STUB_CURSOR = { bag = bag, slot = slot, id = STUB_BAGS[bag] and STUB_BAGS[bag][slot] }
  end,
  ContainerIDToInventoryID = function(bag) return 30 + bag end,
  UseContainerItem = function() end,
}
local function drop(bag)
  if not STUB_CURSOR then return end
  STUB_BAGS[bag] = STUB_BAGS[bag] or {}
  for s = 1, 16 do
    if not STUB_BAGS[bag][s] then
      STUB_BAGS[bag][s] = STUB_CURSOR.id
      STUB_BAGS[STUB_CURSOR.bag][STUB_CURSOR.slot] = nil
      STUB_CURSOR = nil
      return
    end
  end
end
PutItemInBackpack = function() drop(0) end
PutItemInBag = function(inv) drop(inv - 30) end
GetCursorInfo = function() if STUB_CURSOR then return "item", STUB_CURSOR.id, link(STUB_CURSOR.id) end end
ClearCursor = function() STUB_CURSOR = nil end
C_Bank = { FetchPurchasedBankTabIDs = function(kind) return kind == 0 and { 6 } or {} end }
Enum = {
  BankType = { Character = 0, Account = 2 },
  BagIndex = { ReagentBag = 5, CharacterBankTab_1 = 6, AccountBankTab_1 = 12 },
  ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Armor = 4, Reagent = 5, Projectile = 6,
    Tradegoods = 7, Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15 },
}
NUM_BAG_SLOTS = 4

-- Mail, trade, vendor, professions
STUB_INBOX = {} -- [index] = { sender, canReply, invoice, items = { id, ... } }
GetInboxHeaderInfo = function(i)
  local m = STUB_INBOX[i]
  if m then return nil, nil, m.sender, "", 0, 0, 30, true, false, false, false, m.canReply, false end
end
GetInboxInvoiceInfo = function(i) return STUB_INBOX[i] and STUB_INBOX[i].invoice end
GetInboxItemLink = function(i, a) local m = STUB_INBOX[i]; local id = m and m.items[a]; return id and link(id) end
TakeInboxItem = function() end
AutoLootMailItem = function() end
ATTACHMENTS_MAX_RECEIVE = 16
STUB_TRADE = {}
GetTradeTargetItemLink = function(i) return STUB_TRADE[i] and link(STUB_TRADE[i]) end
STUB_TRADE_PLAYER = {}
GetTradePlayerItemLink = function(i) return STUB_TRADE_PLAYER[i] and link(STUB_TRADE_PLAYER[i]) end
ClickTradeButton = function(i) STUB_TRADE_PLAYER[i] = nil end
GetSendMailItemLink = function() return nil end
ATTACHMENTS_MAX_SEND = 12
STUB_MERCHANT = {}
GetMerchantNumItems = function() return #STUB_MERCHANT end
GetMerchantItemLink = function(i) return STUB_MERCHANT[i] and link(STUB_MERCHANT[i]) end
BuyMerchantItem = function() end
GetNumBuybackItems = function() return 0 end
STUB_PROFESSIONS = {} -- { { name, skillLine }, ... }
GetProfessions = function()
  local p = STUB_PROFESSIONS
  return p[1] and 1, p[2] and 2, nil, nil, nil, nil
end
GetProfessionInfo = function(i) local p = STUB_PROFESSIONS[i]; return p[1], 0, 1, 300, 0, 0, p[2] end
STUB_RECIPES = {} -- current profession window: { name, recipes = { { reagents = { id, ... } } } }
GetNumTradeSkills = function() return STUB_RECIPES.recipes and #STUB_RECIPES.recipes or 0 end
GetTradeSkillLine = function() return STUB_RECIPES.name end
GetTradeSkillInfo = function() return "Recipe", "optimal" end
GetTradeSkillNumReagents = function(i) return #STUB_RECIPES.recipes[i].reagents end
GetTradeSkillReagentItemLink = function(i, r) return link(STUB_RECIPES.recipes[i].reagents[r]) end

-- Equipment manager: STUB_SETS[setID] = { name, items = { [slot] = itemID }, ignored = { [slot] = true } }
STUB_SETS = {}
C_EquipmentSet = {
  GetEquipmentSetIDs = function() local ids = {} for id in pairs(STUB_SETS) do ids[#ids + 1] = id end table.sort(ids) return ids end,
  GetEquipmentSetInfo = function(id) local s = STUB_SETS[id]; if s then return s.name, 0, id end end,
  GetItemIDs = function(id) return STUB_SETS[id] and STUB_SETS[id].items end,
  GetIgnoredSlots = function(id) return STUB_SETS[id] and STUB_SETS[id].ignored or {} end,
}

-- Baganator freezes the mixin it copies onto each live bag button, so hooking the mixin itself must fail here
-- too; Custodian gets the buttons from Baganator's skin API (smoke.lua's Baganator stub) instead.
BaganatorClassicLiveContainerItemButtonMixin = setmetatable({}, {
  __index = { SetItemDetails = function() end },
  __newindex = function() error("attempted to perform indexed assignment on a frozen table", 2) end,
})

-- Everything else Custodian calls
hooksecurefunc = function(t, name, fn)
  if type(t) == "string" then t, name, fn = _G, t, name end
  local orig = t[name]
  if type(orig) ~= "function" then error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 2) end
  -- A plain assignment, not rawset, so a frozen table (see Baganator's mixin above) errors like the game does.
  t[name] = function(...) local r = { orig(...) }; fn(...); return (table.unpack or unpack)(r) end
end
CastSpellByName = function() end
UseAction = function() end
GetActionInfo = function() return nil end
StaticPopupDialogs = {}
StaticPopup_Show = function(which, a1, a2, data) STUB_POPUP = { which = which, a1 = a1, a2 = a2, data = data } end
StaticPopup_Hide = function() end
SpellIsTargeting = function() return false end
SpellStopTargeting = function() error("ADDON_ACTION_FORBIDDEN: SpellStopTargeting() is protected on Forever") end
IsAltKeyDown = function() return STUB_ALT or false end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
GetTime = function() return STUB_TIME or 1 end
debugprofilestop = function() return 0 end
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GameTooltip = stub("GameTooltip")
GameTooltip_Hide = function() end
UIParent = stub("UIParent")
SlashCmdList = {}
date = os.date
C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and "test" or nil end, IsAddOnLoaded = function() return false end }

-- Reads of globals the game doesn't have are fine (Custodian checks for them); remember them for the report.
UNDEFINED = {}
setmetatable(_G, { __index = function(_, k) UNDEFINED[k] = true end })
function LOADFILE(src, name, addon)
  local f, err = load(src, "@" .. addon .. "/" .. name)
  if not f then print("COMPILE ERROR " .. err); return end
  local ok, e = xpcall(f, debug.traceback, addon, {})
  print((ok and "loaded " or "LOAD ERROR ") .. name .. (ok and "" or (": " .. e)))
end
