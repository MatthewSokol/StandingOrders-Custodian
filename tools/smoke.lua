-- Smoke test: loads Custodian with the stubbed API, then walks through its main features and checks the
-- results. Run: node tools/harness.js StandingOrders_Custodian "" tools/smoke.lua   (green = no ERROR/FAIL lines)
-- Item names below are the game's; nothing here is a character or player name.

STUB_ITEMDB = {
  [6948] = { name = "Hearthstone", quality = 1, sellPrice = 0, classID = 15, subclassID = 0 },
  [4865] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15, subclassID = 0 },
  [25] = { name = "Worn Shortsword", quality = 1, sellPrice = 7, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" },
  [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7, subclassID = 5, isCrafting = true },
  [2770] = { name = "Copper Ore", quality = 1, sellPrice = 5, classID = 7, subclassID = 7, isCrafting = true },
  [10940] = { name = "Strange Dust", quality = 1, sellPrice = 50, classID = 7, subclassID = 12, isCrafting = true },
  [2320] = { name = "Coarse Thread", quality = 1, sellPrice = 2, classID = 7, subclassID = 5, isCrafting = true },
  [4540] = { name = "Tough Hunk of Bread", quality = 1, sellPrice = 1, classID = 0, subclassID = 0 },
  [17030] = { name = "Ankh", quality = 1, sellPrice = 10, classID = 5, subclassID = 0 },
  [15210] = { name = "Raider Shortsword", quality = 2, sellPrice = 900, classID = 2, subclassID = 7, bindType = 2, equipLoc = "INVTYPE_WEAPON" },
  [9999] = { name = "Gifted Blade", quality = 2, sellPrice = 900, classID = 2, subclassID = 7, bindType = 2, equipLoc = "INVTYPE_WEAPON" },
  [4306] = { name = "Silk Cloth", quality = 1, sellPrice = 38, classID = 7, subclassID = 5, isCrafting = true },
  [6256] = { name = "Fishing Pole", quality = 1, sellPrice = 23, classID = 2, subclassID = 20, equipLoc = "INVTYPE_2HWEAPON" },
  [2901] = { name = "Mining Pick", quality = 1, sellPrice = 16, classID = 2, subclassID = 0, equipLoc = "INVTYPE_WEAPON" },
}
STUB_PROFESSIONS = { { "Tailoring", 197 } }

-- A bag frame whose enumerator yields an empty slot between two buttons (seen on Forever).
local function button(bag, slot)
  return {
    GetBagID = function() return bag end,
    GetID = function() return slot end,
    HookScript = function(self, script, fn) self["__h_" .. script] = fn end,
    CreateTexture = function() return STUB("Texture") end,
    GetWidth = function() return 37 end,
  }
end
local bagButtons = { button(0, 1), nil, button(0, 3) }
ContainerFrame1 = STUB("ContainerFrame1")
rawset(ContainerFrame1, "EnumerateValidItems", function()
  local i = 0
  return function() i = i + 1; if i <= 3 then return i, bagButtons[i] end end
end)

-- A stand-in ArkInventory with its public item-frame API (bags live, bank offline).
ArkInventory = {
  Const = { Location = { Bag = 1, Bank = 3 } },
  Global = { Location = { [1] = { isOffline = false }, [3] = { isOffline = true } } },
  API = {
    ItemFrameLoaded = function() end,
    ItemFrameUpdated = function() end,
    ItemFrameItemTableGet = function(f) return f.__item end,
    ItemFrameLoadedIterate = function() return function() end end,
  },
}

-- Stand-ins for ElvUI's bags module, AdiBags (with its ABEvent-1.0 messages) and BetterBags (its Events
-- module), with just the hooks the adapters use.
local ElvB = { UpdateSlot = function() end }
ElvUI = { { private = { bags = { enable = true } }, GetModule = function(_, name) return name == "Bags" and ElvB end } }
ADI_MSG, BB_MSG = {}, {}
local Adi = {}
local BBEvents = { RegisterMessage = function(_, msg, fn) BB_MSG[msg] = fn end }
local BB = { GetModule = function(_, name) return name == "Events" and BBEvents end }
local ABEvent = { Embed = function(_, obj) obj.RegisterMessage = function(_, msg, fn) ADI_MSG[msg] = fn end end }
local AceAddon = { GetAddon = function(_, name) return (name == "AdiBags" and Adi) or (name == "BetterBags" and BB) or nil end }
-- Baganator's skin API: listeners get every item button as Baganator makes it ({ regionType, region }).
BAGANATOR_LISTENERS, BAGANATOR_FRAMES = {}, {}
Baganator = { API = { Skins = {
  RegisterListener = function(fn) BAGANATOR_LISTENERS[#BAGANATOR_LISTENERS + 1] = fn end,
  GetAllFrames = function() return BAGANATOR_FRAMES end,
} } }
Bagnon = { Item = { Update = function() end } }
LibStub = function(name) return (name == "AceAddon-3.0" and AceAddon) or (name == "ABEvent-1.0" and ABEvent) or nil end
-- An older build's per-character Mail auto-mark on a reagent (seen in game on Light Feathers).
StandingOrdersCustodianCharDB = { items = { [17030] = 1.5 }, autoMarked = { [17030] = 1.5 } }
-- 1.0.0 auto-marked white fishing poles Junk for all characters.
StandingOrdersCustodianDB = { items = { [6256] = 1 }, autoMarked = { [6256] = 1 }, autoSeen = { [6256] = true } }
FIRE("ADDON_LOADED", "StandingOrders_Custodian")
FIRE("PLAYER_LOGIN")
local KS = StandingOrdersCustodian
local L = KS.LEVELS
CHECK("1.0.0's Junk auto-mark on a fishing pole comes off at login", KS.GetLevel(6256) == L.NORMAL and next(StandingOrdersCustodianDB.autoMarked) == nil, KS.GetLevel(6256))
CHECK("a per-character auto-mark on a reagent comes off at login", KS.GetLevel(17030) == L.NORMAL and next(StandingOrdersCustodianCharDB.autoMarked) == nil, KS.GetLevel(17030))
CHECK("Custodian global and levels", KS and L and L.MAIL == 1.5 and L.ONME == 5)
CHECK("the old global still works for Vendor, Mail and the config addon", StandingOrdersQuartermaster == KS)
CHECK("/soc is the command and /soq is gone", SlashCmdList.SOC ~= nil and SLASH_SOC1 == "/soc" and SlashCmdList.SOQ == nil)
CHECK("/custodian is the backup command", SLASH_SOC2 == "/custodian")
CHECK("slash command: /soc only (the old /faves is gone)", SLASH_SOC1 == "/soc" and SLASH_SOQ2 == nil)
CHECK("auto-mark settings default on", KS.GetAuto("grayJunk") and KS.GetAuto("matsMail") and KS.GetAuto("keepReceived"))

-- Auto-marks on what's in the bags at login
KS.SetLevel(6948, L.ONME, nil, { quiet = true })
STUB_BAGS[0] = { 6948, 4865, 25, 2589, 2770, 10940, 2320, 4540, 17030, 15210, 6256, 2901 }
RUN_TIMERS()
CALL("bag refresh with an empty slot", function() FIRE("BAG_UPDATE_DELAYED"); RUN_TIMERS() end)
CHECK("bag buttons after the empty slot still get hooked", rawget(bagButtons[3], "__h_PreClick") ~= nil)
CHECK("gray becomes Junk", KS.GetLevel(4865) == L.JUNK, KS.GetLevel(4865))
CHECK("white weapon becomes Junk", KS.GetLevel(25) == L.JUNK, KS.GetLevel(25))
CHECK("a fishing pole (a white weapon, but a profession tool) is left alone", KS.GetLevel(6256) == L.NORMAL, KS.GetLevel(6256))
CHECK("a mining pick (a profession tool by ID) is left alone", KS.GetLevel(2901) == L.NORMAL, KS.GetLevel(2901))
CHECK("profession tools: by ID and by the Fishing Pole subclass", KS.IsProfessionTool(2901) and KS.IsProfessionTool(6256) and not KS.IsProfessionTool(25))
CHECK("Hearthstone keeps its own mark", KS.GetLevel(6948) == L.ONME, KS.GetLevel(6948))
CHECK("BoE green becomes Mail (all characters)", KS.GetLevel(15210) == L.MAIL and KS.GetItemScope(15210) == "account")
CHECK("enchanting material left alone", KS.GetLevel(10940) == L.NORMAL, KS.GetLevel(10940))
CHECK("vendor thread left alone", KS.GetLevel(2320) == L.NORMAL, KS.GetLevel(2320))
CHECK("food left alone", KS.GetLevel(4540) == L.NORMAL, KS.GetLevel(4540))
CHECK("Ankh left alone", KS.GetLevel(17030) == L.NORMAL, KS.GetLevel(17030))
CHECK("cloth waits for the Tailoring recipes", KS.GetLevel(2589) == L.NORMAL, KS.GetLevel(2589))
CHECK("ore (no profession of ours) becomes Mail here", KS.GetLevel(2770) == L.MAIL and KS.GetItemScope(2770) == "char")

-- Opening the Tailoring window: cloth is used, so it stays; silk isn't in a known recipe yet
STUB_RECIPES = { name = "Tailoring", recipes = { { reagents = { 2589, 2320 } } } }
FIRE("TRADE_SKILL_SHOW")
RUN_TIMERS()
STUB_BAGS[1] = { 4306 }
FIRE("BAG_UPDATE_DELAYED")
RUN_TIMERS()
CHECK("cloth used by a known recipe stays unmarked", KS.GetLevel(2589) == L.NORMAL, KS.GetLevel(2589))
CHECK("silk (no known recipe) becomes Mail here", KS.GetLevel(4306) == L.MAIL, KS.GetLevel(4306))
STUB_RECIPES = { name = "Tailoring", recipes = { { reagents = { 2589 } }, { reagents = { 4306 } } } }
FIRE("TRADE_SKILL_UPDATE")
RUN_TIMERS()
CHECK("learning a silk recipe takes silk's Mail mark off", KS.GetLevel(4306) == L.NORMAL, KS.GetLevel(4306))

-- An item mailed by a player is kept on this character
STUB_INBOX[1] = { sender = "Aldren", canReply = true, items = { 9999 } }
CALL("take mail", TakeInboxItem, 1, 1)
STUB_BAGS[1][2] = 9999
FIRE("BAG_UPDATE_DELAYED")
RUN_TIMERS()
CHECK("BoE mailed by a player isn't auto-marked", KS.GetLevel(9999) == L.NORMAL, KS.GetLevel(9999))

-- Personal items: a manual mark on food goes to this character only
KS.SetLevel(4540, L.LOCK, nil, { quiet = true })
CHECK("mark on food is per character", KS.GetItemScope(4540) == "char", KS.GetItemScope(4540))

-- Bank guard: an Always on me item put in the bank comes back
FIRE("BANKFRAME_OPENED")
STUB_BAGS[6] = { 6948 }
STUB_BAGS[0][1] = nil
FIRE("PLAYERBANKSLOTS_CHANGED")
RUN_TIMERS()
local inBags = false
for bag = 0, 4 do for _, id in pairs(STUB_BAGS[bag] or {}) do if id == 6948 then inBags = true end end end
CHECK("Always on me item moved back out of the bank", inBags and not STUB_BAGS[6][1])
FIRE("BANKFRAME_CLOSED")

-- Custodian's own messages (auto-marks, items moved back...): the log only, unless chat is turned on
local function logHas(text)
  for _, line in ipairs(StandingOrdersCustodianDB.log or {}) do if line:find(text, 1, true) then return true end end
  return false
end
CHECK("chat logging is off by default in a release build, and nothing is saved", KS.ChatLevel() == "off" and KS.GetChat() == false and StandingOrdersCustodianDB.chatLog == nil and StandingOrdersCustodianDB.chat == nil)
CHECK("auto-mark and moved-back messages stay out of chat by default", not CHAT_HAS("Marked as") and not CHAT_HAS("back to your bags"))
CHECK("...and are kept in the log", logHas("Marked as") and logHas("back to your bags"))
CALL("/soc chat on", SlashCmdList.SOC, "chat on")
CHECK("/soc chat on turns them on", KS.GetChat() == true)
STUB_ITEMDB[4877] = { name = "Test Gray Bone", quality = 0, sellPrice = 3, classID = 15, subclassID = 0 }
STUB_BAGS[3] = { 4877 }
FIRE("BAG_UPDATE_DELAYED")
RUN_TIMERS()
CHECK("with chat on, an auto-mark shows in chat", CHAT_HAS("Marked as") and KS.GetLevel(4877) == L.JUNK)
CALL("/soc chat off", SlashCmdList.SOC, "chat off")
STUB_BAGS[3] = nil
CHECK("/soc chat off turns them off", KS.GetChat() == false)
-- Chat logging levels (wow-mod-dev ui.md 5): off, basic, verbose; the default follows the build; only choices are saved.
local getMeta = C_AddOns.GetAddOnMetadata
StandingOrdersCustodianDB.chatLog = nil
C_AddOns.GetAddOnMetadata = function(_, key) return key == "Version" and "candidate/v1.1.0-9-g5cf6270" or nil end
CHECK("a dev build (git describe) defaults to basic", KS.IsDevBuild() and KS.ChatLevel() == "basic" and StandingOrdersCustodianDB.chatLog == nil)
CHECK("a dev build's settings offer Verbose", #KS.ChatLevels() == 3)
C_AddOns.GetAddOnMetadata = function(_, key) return key == "Version" and "@project-version@" or nil end
CHECK("an unfilled packager token counts as a dev build", KS.IsDevBuild())
CHECK("a bare hash (no tag yet) counts as a dev build", KS.IsDevVersion("5cf6270") and KS.IsDevVersion("5CF6270"))
CHECK("an install exactly at a candidate tag counts as a dev build", KS.IsDevVersion("candidate/v1.2.0"))
CHECK("a dirty tree and dev count as dev builds", KS.IsDevVersion("v1.1.0-dirty") and KS.IsDevVersion("dev"))
CHECK("a release tag doesn't", not KS.IsDevVersion("v1.1.0") and not KS.IsDevVersion("1.1.0"))
C_AddOns.GetAddOnMetadata = function(_, key) if key == "X-Dev-Build" then return "v1.1.0-12-g1d9d2a0" end return key == "Version" and "v1.1.0" or nil end
CHECK("an ## X-Dev-Build line stamped by the install script makes it a dev build", KS.IsDevBuild())
C_AddOns.GetAddOnMetadata = getMeta
CHECK("a release build offers Off and Basic only", not KS.IsDevBuild() and #KS.ChatLevels() == 2)
CHAT = {}
CALL("/soc log basic", SlashCmdList.SOC, "log basic")
CHECK("/soc log basic saves the choice and says so", StandingOrdersCustodianDB.chatLog == "basic" and CHAT_HAS("Chat logging: Basic"), CHAT[1])
CHAT = {}
KS.Notify("routine line")
CHECK("at basic, routine lines show in chat", CHAT_HAS("routine line"))
CALL("/soc log off", SlashCmdList.SOC, "log off")
CHAT = {}
KS.Notify("quiet line")
CHECK("at off, routine lines stay in the log only", not CHAT_HAS("quiet line") and logHas("quiet line"))
CALL("/soc debug", SlashCmdList.SOC, "debug")
CHECK("/soc debug switches verbose on", KS.ChatLevel() == "verbose" and KS.ChatAllows("basic"))
CALL("/soc debug", SlashCmdList.SOC, "debug")
CHECK("...and off again, back to the build's default", StandingOrdersCustodianDB.chatLog == nil and KS.ChatLevel() == "off")
CHAT = {}
CALL("/soc log", SlashCmdList.SOC, "log")
CHECK("/soc log alone names the level, then the log", CHAT_HAS("Chat logging: Off"), CHAT[1])
CHAT = {}
CALL("/soc log loud", SlashCmdList.SOC, "log loud")
CHECK("an unknown level isn't saved", StandingOrdersCustodianDB.chatLog == nil)
local mig = { chat = true }
KS.MigrateChat(mig)
CHECK("1.1.0's chat on carries over as basic", mig.chatLog == "basic" and mig.chat == nil)
mig = { chat = false, debug = true }
KS.MigrateChat(mig)
CHECK("an old debug switch carries over as verbose; chat off isn't saved", mig.chatLog == "verbose" and mig.chat == nil and mig.debug == nil)
mig = { chat = false }
KS.MigrateChat(mig)
CHECK("1.1.0's default (chat off) isn't saved as a choice", mig.chatLog == nil)

-- Soulbound gear this character can't use (off by default): Junk on this character only; enchanters keep green+
CHECK("unusable soulbound gear: the rule is off by default", KS.GetAuto("unusableJunk") == false)
STUB_CLASS, STUB_LEVEL = "WARRIOR", 20
STUB_ITEMDB[7100] = { name = "Test Plate Helm", quality = 2, sellPrice = 300, classID = 4, subclassID = 4, equipLoc = "INVTYPE_HEAD", minLevel = 40 }
STUB_ITEMDB[7101] = { name = "Test Cloth Robe", quality = 2, sellPrice = 300, classID = 4, subclassID = 1, equipLoc = "INVTYPE_CHEST" }
STUB_ITEMDB[7102] = { name = "Test Wand", quality = 2, sellPrice = 300, classID = 2, subclassID = 19, equipLoc = "INVTYPE_RANGEDRIGHT" }
STUB_ITEMDB[7104] = { name = "Test Mail Belt", quality = 2, sellPrice = 300, classID = 4, subclassID = 3, equipLoc = "INVTYPE_WAIST", minLevel = 22 }
STUB_ITEMDB[7105] = { name = "Test Shield", quality = 2, sellPrice = 300, classID = 4, subclassID = 6, equipLoc = "INVTYPE_SHIELD" }
for _, id in ipairs({ 7100, 7101, 7102, 7104, 7105 }) do STUB_BOUND[id] = true end
STUB_BAGS[3] = { 7100, 7101, 7102, 7104 }
FIRE("BAG_UPDATE_DELAYED")
RUN_TIMERS()
CHECK("rule off: soulbound gear stays unmarked", KS.GetLevel(7100) == L.NORMAL and KS.GetLevel(7102) == L.NORMAL)
CALL("turn the unusable-gear rule on", KS.SetAuto, "unusableJunk", true)
RUN_TIMERS()
CHECK("a Warrior at 20: plate from 40 becomes Junk, this character only", KS.GetLevel(7100) == L.JUNK and KS.GetItemScope(7100) == "char", KS.GetLevel(7100))
CHECK("a Warrior: a wand (can't train wands) becomes Junk, this character only", KS.GetLevel(7102) == L.JUNK and KS.GetItemScope(7102) == "char", KS.GetLevel(7102))
CHECK("cloth (everyone can wear it) stays", KS.GetLevel(7101) == L.NORMAL, KS.GetLevel(7101))
CHECK("mail usable within 5 levels stays", KS.GetLevel(7104) == L.NORMAL, KS.GetLevel(7104))
STUB_CLASS = "MAGE"
STUB_PROFESSIONS = { { "Tailoring", 197 }, { "Enchanting", 333 } }
STUB_BAGS[3][5] = 7105
FIRE("BAG_UPDATE_DELAYED")
RUN_TIMERS()
CHECK("an enchanter's unusable green (a Mage's shield) stays, to disenchant", KS.GetLevel(7105) == L.NORMAL, KS.GetLevel(7105))
STUB_PROFESSIONS = { { "Tailoring", 197 } }
CHECK("Shaman at 37: Mail (from 40) is soon", KS.UnusableReason(4, 3, 40, "SHAMAN", 37) == nil)
CHECK("Shaman at 20: Mail (from 40) is later", KS.UnusableReason(4, 3, 1, "SHAMAN", 20) == "later")
CHECK("Mage: shields never", KS.UnusableReason(4, 6, 1, "MAGE", 60) == "never")
CHECK("Rogue: cloth is fine", KS.UnusableReason(4, 1, 1, "ROGUE", 10) == nil)
CHECK("Priest: daggers are fine", KS.UnusableReason(2, 15, 1, "PRIEST", 10) == nil)
CHECK("Paladin: wands never", KS.UnusableReason(2, 19, 1, "PALADIN", 10) == "never")
CHECK("Warrior: polearms can be trained", KS.UnusableReason(2, 6, 1, "WARRIOR", 10) == nil)
CHECK("Druid: an idol is fine, a totem never", KS.UnusableReason(4, 8, 1, "DRUID", 30) == nil and KS.UnusableReason(4, 9, 1, "DRUID", 30) == "never")
CHECK("rings and trinkets (Miscellaneous): everyone", KS.UnusableReason(4, 0, 1, "MAGE", 1) == nil)
CHECK("an unknown class is never guessed", KS.UnusableReason(4, 4, 1, "DEATHKNIGHT", 60) == nil)
CHECK("any class: a level 50 item at level 30 is later", KS.UnusableReason(4, 1, 50, "PRIEST", 30) == "later")
STUB_CLASS, STUB_LEVEL = "WARRIOR", 60
STUB_BAGS[3] = nil
KS.SetAuto("unusableJunk", false)

-- Slash commands
for _, cmd in ipairs({ "help", "list", "status", "settings", "scope char", "scope account", "log 5", "debug", "debug", "intro" }) do
  CALL("/soc " .. cmd, SlashCmdList.SOC, cmd)
end
CALL("/soc lock <item>", SlashCmdList.SOC, "lock " .. STUB_LINK(25))
CHECK("/soc lock sets Locked", KS.GetLevel(25) == L.LOCK, KS.GetLevel(25))
CALL("/soc mail <id> char", SlashCmdList.SOC, "mail 25 char")
CHECK("/soc mail ... char marks this character", KS.GetLevel(25) == L.MAIL and KS.GetItemScope(25) == "char")

-- Self-test and Mechanic (with a stand-in MechanicLib)
local registered
LibStub = function(name) if name == "MechanicLib-1.0" then return {
  Register = function(_, addon, caps) registered = { addon = addon, caps = caps } end,
  Log = function() end, Categories = { CORE = "[Core]" },
} end end
FIRE("PLAYER_LOGIN") -- registers again now that MechanicLib is here (hooks are idempotent enough for a stub)
RUN_TIMERS()
CHECK("registered with Mechanic", registered and registered.addon == "StandingOrders_Custodian" and registered.caps.tests ~= nil)
if registered then
  CHECK("self-test ran when Mechanic registered", StandingOrdersCustodianDB.selfTest ~= nil)
  local passed, total = registered.caps.tests.runAll()
  CHECK("Mechanic runAll returns passed, total", type(passed) == "number" and total and passed == total, tostring(passed) .. "/" .. tostring(total))
  CHECK("Mechanic getResult runs the test", registered.caps.tests.getResult("levels").passed == true)
  CHECK("Mechanic debug setting", registered.caps.settings and registered.caps.settings.debug.get() ~= nil)
  local all = registered.caps.tests.getAll()
  CHECK("Mechanic sees the tests", #all >= 5, #all)
  for _, t in ipairs(all) do
    local r = registered.caps.tests.getResult(t.id)
    CHECK("self-test " .. t.id .. " passes (" .. tostring(r and r.message) .. ")", r and r.passed)
  end
end
CALL("/soc selftest", SlashCmdList.SOC, "selftest")
CHECK("self-test saved", StandingOrdersCustodianDB.selfTest and StandingOrdersCustodianDB.selfTest.passed == true)

-- ArkInventory: Alt+Click on a live bag button marks the item in that slot; offline views and buttons
-- whose item doesn't match the slot are left alone.
local function arkButton(loc, bag, slot, itemID)
  local b = button(bag, slot)
  b.GetBagID = nil
  b.ARK_Data = { loc_id = loc, bag_id = 1, blizzard_id = bag, slot_id = slot }
  b.__item = { h = STUB_LINK(itemID) }
  b.IsVisible = function() return true end
  return b
end
-- One Alt+Left-click up from Normal: Confirm while it's on, Locked while it's held back from the release.
local STEP_UP = KS.CONFIRM_ENABLED and L.CONFIRM or L.LOCK
STUB_BAGS[0][3] = 25
KS.SetLevel(25, L.NORMAL, nil, { quiet = true, scope = "account" })
local ark = arkButton(1, 0, 3, 25)
CALL("Ark ItemFrameUpdated", ArkInventory.API.ItemFrameUpdated, ark, 1, 1, 3)
CHECK("Ark bag button hooked", ark.__h_PreClick ~= nil)
STUB_ALT = true
CALL("Alt+Left-click in Ark bags", ark.__h_PreClick, ark, "LeftButton")
CHECK("Alt+Click in Ark raised the level", KS.GetLevel(25) == STEP_UP, KS.GetLevel(25))
local offline = arkButton(3, 0, 3, 25)
CALL("Ark offline bank button", ArkInventory.API.ItemFrameUpdated, offline, 3, 1, 3)
CALL("Alt+Left-click an offline view", offline.__h_PreClick, offline, "LeftButton")
CHECK("offline view leaves the item alone", KS.GetLevel(25) == STEP_UP, KS.GetLevel(25))
local stale = arkButton(1, 0, 3, 4865)
CALL("Ark button showing another item", ArkInventory.API.ItemFrameUpdated, stale, 1, 1, 3)
CALL("Alt+Left-click a mismatched button", stale.__h_PreClick, stale, "LeftButton")
CHECK("mismatched button leaves both items alone", KS.GetLevel(25) == STEP_UP and KS.GetLevel(4865) == L.JUNK)
STUB_ALT = false

if KS.CONFIRM_ENABLED then
  -- Confirm (temp hold): the action is stopped, a window offers to allow it once; the pass lasts until
  -- the trade closes, and a disenchant pass is used up by one try.
  KS.SetLevel(2770, L.CONFIRM, nil, { quiet = true, scope = "account" })
  STUB_POPUP = nil
  STUB_TRADE_PLAYER[1] = 2770
  FIRE("TRADE_PLAYER_ITEM_CHANGED", 1)
  CHECK("held item taken back out of the trade", STUB_TRADE_PLAYER[1] == nil)
  CHECK("the hold window asks", STUB_POPUP and STUB_POPUP.which == "SOC_CONFIRM" and STUB_POPUP.a2 == "traded")
  CALL("Allow once", StaticPopupDialogs.SOC_CONFIRM and StaticPopupDialogs.SOC_CONFIRM.OnAccept, nil, STUB_POPUP and STUB_POPUP.data)
  STUB_TRADE_PLAYER[1] = 2770
  FIRE("TRADE_PLAYER_ITEM_CHANGED", 1)
  FIRE("TRADE_PLAYER_ITEM_CHANGED", 1)
  CHECK("allowed item stays in the trade", STUB_TRADE_PLAYER[1] == 2770)
  FIRE("TRADE_CLOSED")
  FIRE("TRADE_PLAYER_ITEM_CHANGED", 1)
  CHECK("the pass ends when the trade closes", STUB_TRADE_PLAYER[1] == nil)
  STUB_POPUP = nil
  CHECK("disenchant stopped without a pass", KS.Guard(2770, nil, "disenchant") == true)
  CALL("Allow once (disenchant)", StaticPopupDialogs.SOC_CONFIRM.OnAccept, nil, STUB_POPUP.data)
  CHECK("blocker steps aside for the pass", KS.HasPass(2770))
  CHECK("one disenchant allowed", KS.Guard(2770, nil, "disenchant") == false)
  CHECK("the pass is used up", KS.Guard(2770, nil, "disenchant") == true)
else
  -- Confirm is held back from the first release: a saved Confirm protects as Locked, nothing offers it.
  KS.SetLevel(2770, L.NORMAL, nil, { quiet = true, scope = "account" })
  StandingOrdersCustodianDB.items[2770] = L.CONFIRM
  CHECK("a saved Confirm mark counts as Locked", KS.GetLevel(2770) == L.LOCK, KS.GetLevel(2770))
  STUB_POPUP = nil
  CHECK("...and is stopped with no hold window", KS.Guard(2770, nil, "sell") == true and STUB_POPUP == nil)
  CHAT = {}
  CALL("/soc confirm <item>", SlashCmdList.SOC, "confirm 2770")
  CHECK("/soc confirm says it's coming later", CHAT_HAS("later version"), CHAT[1])
  KS.SetLevel(2770, L.CONFIRM, nil, { quiet = true, scope = "account" })
  CHECK("another addon asking for Confirm gets Locked", StandingOrdersCustodianDB.items[2770] == L.LOCK, StandingOrdersCustodianDB.items[2770])
  KS.SetLevel(2770, L.NORMAL, nil, { quiet = true, scope = "account" })
end
STUB_POPUP = nil
CHAT = {}
CHECK("Locked and above still just stop, no window", KS.Guard(6948, nil, "sell") == true and STUB_POPUP == nil)
CHECK("the guard error says how to sell it", CHAT_HAS("Lower it to Normal to sell it") and not CHAT_HAS("Unfavorite"), CHAT[1])
CHECK("the guard error shows on screen; its chat copy is off by default", CHAT_HAS("ERRFRAME ") and #CHAT == 1, #CHAT)

-- Equipment sets: items in a set are protected at the set's level (default Locked); marks underneath
-- stay as they are, and taking an item out of the set takes the protection away.
KS.SetLevel(9999, L.NORMAL, nil, { quiet = true, scope = "char" })
STUB_SETS[1] = { name = "Tank Gear", items = { [16] = 9999, [17] = 15210, [18] = 4306 }, ignored = { [18] = true } }
FIRE("EQUIPMENT_SETS_CHANGED")
CHECK("item in a set is Locked by default", KS.GetLevel(9999) == L.LOCK, KS.GetLevel(9999))
CHECK("a Mail mark under a set is outranked", KS.GetLevel(15210) == L.LOCK, KS.GetLevel(15210))
CHECK("ignored slot isn't protected", KS.GetLevel(4306) ~= L.LOCK, KS.GetLevel(4306))
CHECK("the set is named as the reason", KS.GetSetProtection(9999) == "Tank Gear")
CALL("/soc set Tank Gear onme", SlashCmdList.SOC, "set Tank Gear onme")
CHECK("per-set choice applies", KS.GetLevel(9999) == L.ONME, KS.GetLevel(9999))
if not KS.CONFIRM_ENABLED then
  CALL("/soc set Tank Gear confirm", SlashCmdList.SOC, "set Tank Gear confirm")
  CHECK("a set can't be put on Confirm while it's held back", KS.GetSetChoice(1) == L.ONME, KS.GetSetChoice(1))
end
CALL("/soc set Tank Gear off", SlashCmdList.SOC, "set Tank Gear off")
CHECK("set turned off: back to the item's own mark", KS.GetLevel(9999) == L.NORMAL and KS.GetLevel(15210) == L.MAIL)
CALL("/soc set Tank Gear default", SlashCmdList.SOC, "set Tank Gear default")
CALL("/soc sets onme", SlashCmdList.SOC, "sets onme")
CHECK("default for sets applies", KS.GetLevel(9999) == L.ONME, KS.GetLevel(9999))
CHAT = {}
KS.SetLevel(9999, L.JUNK)
local function LOG_HAS(text) for _, l in ipairs(StandingOrdersCustodianDB.log or {}) do if l:find(text, 1, true) then return true end end return false end
CHECK("lowering a set item explains it stays protected (in the log; chat is off)", LOG_HAS([[equipment set "Tank Gear"]]) and not CHAT_HAS([[equipment set "Tank Gear"]]) and KS.GetLevel(9999) == L.ONME)
CHAT = {}
CALL("/soc junk 9999 (a typed command)", SlashCmdList.SOC, "junk 9999")
CHECK("a typed command still answers in chat", CHAT_HAS("is now") and CHAT_HAS([[equipment set "Tank Gear"]]), CHAT[1])
STUB_SETS[1].items[16] = nil
FIRE("EQUIPMENT_SETS_CHANGED")
CHECK("taken out of the set: back to its own mark", KS.GetLevel(9999) == L.JUNK, KS.GetLevel(9999))
CALL("/soc sets", SlashCmdList.SOC, "sets")
CALL("/soc sets default lock", SlashCmdList.SOC, "sets default lock")
CHECK("default back to Locked", KS.GetSetDefault() == L.LOCK)
CALL("/soc set Nope lock", SlashCmdList.SOC, "set Nope lock")
-- The settings panel's equipment set rows: the default first, then each set; each picks its level from a dropdown.
local panel = SOCustodianSettings
CHECK("icon path is the addon's Icon.tga", KS.ICON == "Interface\\AddOns\\StandingOrders_Custodian\\Icon", KS.ICON)
CHECK("settings panel shows the icon", panel and panel.icon ~= nil)
if KS.CONFIRM_ENABLED then CHECK("hold window text shows the icon", StaticPopupDialogs.SOC_CONFIRM and StaticPopupDialogs.SOC_CONFIRM.text:find(KS.ICON, 1, true) ~= nil) end -- the hold window is only made for Confirm
CALL("intro", KS.ShowIntro, KS)
CHECK("intro shows the icon", SOCustodianIntro and SOCustodianIntro.icon ~= nil)
local introText = KS.IntroText()
local function before(a, b) local i, j = introText:find(a, 1, true), introText:find(b, 1, true); return i and j and i < j end
CHECK("intro: marks are for all characters comes first in Your marks", before("Your marks", "Marks are for all your characters") and before("Marks are for all your characters", "happy to lose"))
CHECK("intro: auto-marks are bullets under their own heading", before("Marked for you", "• Grays") and before("• Grays", "Protected against"))
CHECK("intro: still allowed says applying enchants", introText:find("Applying enchants, oils and scrolls", 1, true) ~= nil)
CHECK("intro: not yet supported bag addons", introText:find("Not yet supported bag addons", 1, true) ~= nil and not introText:find("doesn't know", 1, true))
CHECK("intro: lists every supported bag addon", before("Blizzard bags", "ArkInventory") and introText:find("ElvUI bags", 1, true) ~= nil)
CHECK("intro: one bag line per supported bag", SOCustodianIntro.bags and #SOCustodianIntro.bags == 8)
CHECK("intro: Bagnonium, with its old name Combuctor", introText:find("Bagnonium", 1, true) ~= nil and introText:find("(was Combuctor)", 1, true) ~= nil)
CHECK("intro: no \"(in use)\" words; a legend explains the colors", not introText:find("(in use)", 1, true) and introText:find("Green with a check: in use now", 1, true) ~= nil)
local introFrame = SOCustodianIntro
CHECK("the intro opens in its short view by default", introFrame.detailed == false and introFrame.toggle:GetText() == "Show details" and introFrame.shortPool[2]:IsShown() and introFrame.shortPool[2]:GetText():find("Alt+Left-click", 1, true) ~= nil, introFrame.toggle:GetText())
CHECK("the short view says where to see every mark", KS.IntroText("short"):find("/soc list", 1, true) ~= nil)
CALL("Show details", introFrame.toggle:GetScript("OnClick"), introFrame.toggle)
CHECK("Show details switches to the detailed view", introFrame.detailed == true and introFrame.toggle:GetText() == "Show less" and introFrame.fullPool[1]:IsShown() and not introFrame.shortPool[2]:IsShown() and introFrame.bags[1]:IsShown())
CHECK("the view choice is remembered", StandingOrdersCustodianDB.introDetails == true)
CALL("Show less", introFrame.toggle:GetScript("OnClick"), introFrame.toggle)
CHECK("Show less goes back to the short view", introFrame.detailed == false and not introFrame.fullPool[1]:IsShown() and not introFrame.bags[1]:IsShown())
KS.SetAltClick("menu")
CHECK("in menu mode the short view says Alt+Click opens a menu", KS.IntroText("short"):find("pick its mark from a menu", 1, true) ~= nil)
KS.SetAltClick("cycle")
CALL("settings panel OnShow", panel and rawget(panel, "__s_OnShow"), panel)
CHECK("settings: advanced options are hidden at first", not KS.GetShowAdvanced() and not panel.advanced:IsShown())
local advText = panel.advNote:GetText()
CHECK("settings: the simple page names the advanced options this 1.0.0 install has on", advText:find("advanced options are on", 1, true) ~= nil and advText:find("Protection dial", 1, true) ~= nil and advText:find("white gear becomes Junk", 1, true) ~= nil, advText)
CHECK("1.0.0's auto-mark choices are kept", KS.GetAuto("whiteJunk") and KS.GetAuto("boeMail") and not KS.GetAuto("unusableJunk"))
panel.advCheck:SetChecked(true)
CALL("tick Show advanced options", panel.advCheck:GetScript("OnClick"), panel.advCheck)
CHECK("settings: the advanced options show", KS.GetShowAdvanced() and panel.advanced:IsShown())
local rows = panel and panel.setRows or {}
CHECK("panel lists the default and each set", #rows == 2 and rows[2].label:GetText() == "Tank Gear", #rows)
if rows[2] then
  CHECK("set rows are dropdowns", rows[1].dropdown and rows[2].dropdown)
  local setMenu, defMenu = MENU_RADIOS(rows[2].button), MENU_RADIOS(rows[1].button)
  local n = KS.CONFIRM_ENABLED and 1 or 0 -- Confirm's extra entry
  CHECK("a set's menu: default, (Confirm,) Locked, Always on me, not protected", #setMenu == 4 + n and setMenu[1].text:find("default", 1, true) == 1, #setMenu)
  CHECK("the default's menu has no \"default\" choice", #defMenu == 3 + n, #defMenu)
  if not KS.CONFIRM_ENABLED then
    local any = false
    for _, r in ipairs(setMenu) do if r.text:find("Confirm", 1, true) then any = true end end
    CHECK("no menu offers Confirm while it's held back", not any)
  end
  CHECK("the set's current choice is checked", setMenu[1] and setMenu[1].selected() and not setMenu[2].selected())
  local second = KS.CONFIRM_ENABLED and L.CONFIRM or L.LOCK
  CALL("pick the second choice for the set", setMenu[2] and setMenu[2].pick)
  CHECK("picking it sets it", KS.GetSetChoice(1) == second and setMenu[2].selected(), KS.GetSetChoice(1))
  CALL("pick default for the set", setMenu[1] and setMenu[1].pick)
  CHECK("back to default", KS.GetSetChoice(1) == "default", KS.GetSetChoice(1))
  CALL("pick Always on me for the default", defMenu[2 + n] and defMenu[2 + n].pick)
  CHECK("default moved from Locked to Always on me", KS.GetSetDefault() == L.ONME, KS.GetSetDefault())
  KS.SetSetChoice(nil, L.LOCK)
end

-- Mark icons: 40% of the button's width, bottom left, 75% opaque by default; /soc icon and the panel change them.
local function style() return table.concat({ tostring(KS.GetIconStyle()), select(2, KS.GetIconStyle()), tostring(select(3, KS.GetIconStyle())) }, " ") end
CHECK("icon style defaults", style() == "40 BOTTOMLEFT 75", style())
local px, point, ix, iy, a = KS.IconLayout(40)
CHECK("icon layout on a 40px button", px == 16 and point == "BOTTOMLEFT" and ix == 1 and iy == 1 and a == 0.75, px)
CALL("/soc icon size 50", SlashCmdList.SOC, "icon size 50")
CALL("/soc icon position center", SlashCmdList.SOC, "icon position center")
CALL("/soc icon opacity 60", SlashCmdList.SOC, "icon opacity 60")
CHECK("/soc icon sets size, position and opacity", style() == "50 CENTER 60", style())
CALL("/soc icon size 3", SlashCmdList.SOC, "icon size 3")
CHECK("size can't go below 10%", style() == "10 CENTER 60", style())
CHAT = {}
CALL("/soc icon position middle", SlashCmdList.SOC, "icon position middle")
CHECK("an unknown position is refused and kept", style() == "10 CENTER 60" and CHAT_HAS("/soc icon"), style())
local st = panel and panel.iconStyle
CHECK("settings panel has the mark icon controls", st ~= nil and panel.iconSample ~= nil)
local ib = panel and panel.introButton
CHECK("intro button is wide enough for its label", ib and ib:GetWidth() >= ib:GetTextWidth() + 24, ib and ib:GetWidth())
CHECK("settings content scrolls inside the page", panel and panel.scroll ~= nil and panel.content ~= nil and type(panel.FitPanel) == "function")
CALL("settings panel fits its content", function() panel.FitPanel() end)
if st then
  CALL("panel: Size +", rawget(st.sizePlus, "__s_OnClick"), st.sizePlus)
  local posMenu = MENU_RADIOS(st.pos)
  CHECK("Position is a dropdown of the five positions", st.pos.isDropdown and #posMenu == 5 and posMenu[1].text == "Bottom left", #posMenu)
  CHECK("Position's menu checks the current one (Center)", posMenu[5] and posMenu[5].selected() and not posMenu[1].selected())
  CALL("panel: pick Bottom left", posMenu[1] and posMenu[1].pick)
  CALL("panel: Opacity -", rawget(st.alphaMinus, "__s_OnClick"), st.alphaMinus)
  CHECK("panel: Size +5, Center -> Bottom left, Opacity -5", style() == "15 BOTTOMLEFT 55", style())
end
CALL("/soc icon reset", SlashCmdList.SOC, "icon reset")
CHECK("/soc icon reset goes back to the defaults", style() == "40 BOTTOMLEFT 75", style())

-- Mark icon styles (Icons.lua): game icons (the default: the game's art, item icons cropped, a dark edge) or addon icons.
CHECK("icon style: game icons by default", KS.GetIconStyleName() == "game")
local styleMenu = st and MENU_RADIOS(st.style) or {}
CHECK("settings: the Style dropdown offers two styles", #styleMenu == 2 and styleMenu[1].text == "Game icons" and styleMenu[2].text == "Addon icons", #styleMenu)
local tex = STUB("Texture")
KS.MarkTexture(tex, L.MAIL)
CHECK("game icons: an item icon (the letter) is cropped", tex:GetTexture() == KS.ICONS[L.MAIL] and rawget(tex, "__coord")[1] == 0.08)
KS.MarkTexture(tex, L.JUNK)
CHECK("game icons: the coin isn't an item icon, so it isn't cropped", rawget(tex, "__coord")[1] == 0)
CHECK("game icons: the intro's icons are cropped too", KS.IconTag(L.MAIL):find(":5:59:5:59", 1, true) ~= nil, KS.IconTag(L.MAIL))
CALL("/soc icon style addon", SlashCmdList.SOC, "icon style addon")
KS.MarkTexture(tex, L.LOCK)
CHECK("addon icons: Locked is Media\\Locked", tex:GetTexture() == "Interface\\AddOns\\StandingOrders_Custodian\\Media\\Locked", tex:GetTexture())
CHECK("addon icons: the bags follow", bagButtons[1].favesIcon:GetTexture() == "Interface\\AddOns\\StandingOrders_Custodian\\Media\\OnMe", bagButtons[1].favesIcon:GetTexture())
CHAT = {}
CALL("/soc icon style shiny", SlashCmdList.SOC, "icon style shiny")
CHECK("an unknown style is refused and kept", KS.GetIconStyleName() == "addon" and CHAT_HAS("/soc icon style"), KS.GetIconStyleName())
CALL("/soc icon style trimmed", SlashCmdList.SOC, "icon style trimmed")
CHECK("the test builds' \"trimmed\" means game icons", KS.GetIconStyleName() == "game")
StandingOrdersCustodianDB.icon.style = "badges"
CHECK("a saved \"badges\" reads as addon icons", KS.GetIconStyleName() == "addon")
CALL("/soc icon compare", SlashCmdList.SOC, "icon compare")
local cmp = SOCustodianIconCompare
CHECK("the compare window shows five marks in two styles", cmp and cmp:IsShown() and #cmp.cells == 10, cmp and #cmp.cells)
CHECK("its cells show items from the bags", cmp.cells[1].item:GetTexture() ~= nil)
CALL("Use game icons", cmp.use[1]:GetScript("OnClick"), cmp.use[1])
CHECK("Use puts the style on", KS.GetIconStyleName() == "game" and StandingOrdersCustodianDB.icon.style == "game")
CALL("/soc icon style addon", SlashCmdList.SOC, "icon style addon")
CALL("/soc icon reset", SlashCmdList.SOC, "icon reset")
CHECK("/soc icon reset: the game's art again", KS.GetIconStyleName() == "game")

-- ElvUI bags, AdiBags and BetterBags: Alt+Click on a live bag button marks the item in that slot; a
-- closed bank's buttons (and a BetterBags button showing another item) are left alone.
for id = 7001, 7003 do STUB_ITEMDB[id] = { name = "Test Ring " .. id, quality = 1, sellPrice = 0, classID = 4, subclassID = 0 } end
STUB_BAGS[2] = { 7001, 7002, 7003 }
STUB_BAGS[-1] = { 7001 }
local function plain(fields)
  local b = button(0, 0)
  b.GetBagID, b.GetID = nil, nil
  for k, v in pairs(fields) do b[k] = v end
  return b
end
local function altClick(label, btn, id, want)
  STUB_ALT = true
  CALL("Alt+Left-click: " .. label, btn.__h_PreClick, btn, "LeftButton")
  STUB_ALT = false
  CHECK(label .. ": level is " .. tostring(want), KS.GetLevel(id) == want, KS.GetLevel(id))
end
local elv = plain({ BagID = 2, SlotID = 1 })
CALL("ElvUI UpdateSlot", ElvB.UpdateSlot, ElvB, { Bags = { [2] = { [1] = elv } } }, 2, 1)
altClick("ElvUI bags", elv, 7001, STEP_UP)
local elvBank = plain({ BagID = -1, SlotID = 1 })
CALL("ElvUI bank UpdateSlot", ElvB.UpdateSlot, ElvB, { isBank = true, Bags = { [-1] = { [1] = elvBank } } }, -1, 1)
altClick("ElvUI closed bank", elvBank, 7001, STEP_UP)
-- Vendor and mailbox highlights (Highlights.lua): red can't go, blue is marked for it; a tint only.
local function tintOf(level, place) local c = KS.HighlightColor(level, place); return c == nil and "none" or (c[3] > 0.5 and "blue" or "red") end
CHECK("at a vendor: Locked, Always on me and Disenchant red, Junk blue, Mail and Normal none", tintOf(L.LOCK, "vendor") == "red" and tintOf(L.ONME, "vendor") == "red" and tintOf(L.DISENCHANT, "vendor") == "red" and tintOf(L.JUNK, "vendor") == "blue" and tintOf(L.MAIL, "vendor") == "none" and tintOf(L.NORMAL, "vendor") == "none")
CHECK("at the mailbox: Locked and Always on me red, Mail blue, Disenchant and Junk none", tintOf(L.LOCK, "mail") == "red" and tintOf(L.ONME, "mail") == "red" and tintOf(L.MAIL, "mail") == "blue" and tintOf(L.DISENCHANT, "mail") == "none" and tintOf(L.JUNK, "mail") == "none")
local was7001 = KS.GetLevel(7001)
KS.SetLevel(7001, L.LOCK, nil, { quiet = true, scope = "account" })
CHECK("no tint away from a vendor or the mailbox", not KS.HighlightShown(elv))
FIRE("MERCHANT_SHOW")
CHECK("at a vendor, a Locked item is tinted", KS.HighlightPlace() == "vendor" and KS.HighlightShown(elv) ~= nil)
KS.SetLevel(7001, L.NORMAL, nil, { quiet = true, scope = "account" })
CHECK("a Normal item isn't (the tint follows a mark change)", not KS.HighlightShown(elv))
KS.SetLevel(7001, L.JUNK, nil, { quiet = true, scope = "account" })
CHECK("a Junk item is tinted", KS.HighlightShown(elv) ~= nil)
CALL("/soc highlight off", SlashCmdList.SOC, "highlight off")
CHECK("/soc highlight off: no tints, and off is saved", not KS.HighlightShown(elv) and StandingOrdersCustodianDB.highlight == false)
CALL("/soc highlight on", SlashCmdList.SOC, "highlight on")
CHECK("/soc highlight on: tints again, nothing saved", KS.HighlightShown(elv) ~= nil and StandingOrdersCustodianDB.highlight == nil)
FIRE("MERCHANT_CLOSED")
CHECK("closing the vendor clears the tints", KS.HighlightPlace() == nil and not KS.HighlightShown(elv))
local hooks = {}
MerchantFrame = { shown = true, IsVisible = function(s) return s.shown end, HookScript = function(_, k, fn) hooks[k] = fn end }
KS.SetLevel(7001, L.LOCK, nil, { quiet = true, scope = "account" })
FIRE("MERCHANT_SHOW")
CHECK("with the vendor window up, the tint shows", KS.HighlightShown(elv) ~= nil)
MerchantFrame.shown = false
if hooks.OnHide then hooks.OnHide() end
CHECK("the vendor window gone without MERCHANT_CLOSED: no tint", KS.HighlightPlace() == nil and not KS.HighlightShown(elv))
FIRE("BAG_UPDATE_DELAYED")
CHECK("...and none after a bag update either", not KS.HighlightShown(elv))
FIRE("MERCHANT_CLOSED")
MerchantFrame = nil
KS.SetLevel(7001, L.JUNK, nil, { quiet = true, scope = "account" })
FIRE("MAIL_SHOW")
CHECK("at the mailbox a Junk item isn't tinted", KS.HighlightPlace() == "mail" and not KS.HighlightShown(elv))
KS.SetLevel(7001, L.MAIL, nil, { quiet = true, scope = "account" })
CHECK("...a Mail item is", KS.HighlightShown(elv) ~= nil)
FIRE("MAIL_CLOSED")
KS.SetLevel(7001, was7001, nil, { quiet = true, scope = "account" })
-- At the mailbox with Posty's (or Postal's) Express on and hooked into the default bags' click, Alt+Left-click on a
-- default bag button is Express's (it attaches the item): no mark change. A bag addon's buttons (ElvUI here) stay
-- Custodian's: Express never sees those clicks (in game: ArkInventory, where Express attached nothing).
local express = { enabled = true, hooked = true, IsEnabled = function(self) return self.enabled end,
  IsHooked = function(self, name) return self.hooked and name == "ContainerFrameItemButton_OnModifiedClick" end }
PostyForever = { GetModule = function(_, name) return name == "Express" and express or nil end }
SendMailFrame = { IsVisible = function() return true end }
local blizz = bagButtons[1]
CHECK("mailbox: Posty's Express owns Alt+Left-click on the default bags", KS.MailAddonOwnsAltClick(blizz) == true)
CHECK("mailbox: not on a bag addon's buttons", KS.MailAddonOwnsAltClick(elv) == false)
local before = KS.GetLevel(7001)
altClick("ElvUI bags at the mailbox: Custodian still changes the mark", elv, 7001, KS.ClickStep(before, true))
KS.SetLevel(7001, before, nil, { quiet = true, scope = "account" })
express.hooked = false
CHECK("mailbox: Express not hooked into the bags' click (another client): Custodian keeps it", KS.MailAddonOwnsAltClick(blizz) == false)
express.hooked = true
express.enabled = false
CHECK("mailbox: Express off, Custodian keeps Alt+Click", KS.MailAddonOwnsAltClick(blizz) == false)
express.enabled = true
PostyForever, Postal = nil, PostyForever
CHECK("Postal (the global Postal) counts too", KS.MailAddonOwnsAltClick(blizz) == true)
SendMailFrame = { IsVisible = function() return false end }
CHECK("away from the Send Mail page, Custodian keeps Alt+Click", KS.MailAddonOwnsAltClick(blizz) == false)
Postal, SendMailFrame = nil, nil
CHECK("without Postal or Posty, Custodian keeps Alt+Click", KS.MailAddonOwnsAltClick(blizz) == false)
-- On Forever, AdiBags' secure overlay takes right-clicks; the item button's PreClick never sees them.
local adiOverlay = { HookScript = function(self, script, fn) self["__h_" .. script] = fn end }
local adi = plain({ bag = 2, slot = 2, IsBank = function() return false end, ForeverSecureUse = adiOverlay })
CALL("AdiBags_UpdateButton", ADI_MSG.AdiBags_UpdateButton, "AdiBags_UpdateButton", adi)
altClick("AdiBags", adi, 7002, STEP_UP)
CALL("AdiBags overlay: plain right-click", adiOverlay.__h_PreClick, adiOverlay, "RightButton")
CHECK("a plain right-click on the overlay leaves the level", KS.GetLevel(7002) == STEP_UP, KS.GetLevel(7002))
STUB_ALT = true
CALL("AdiBags overlay: Alt+Right-click", adiOverlay.__h_PreClick, adiOverlay, "RightButton")
STUB_ALT = false
CHECK("Alt+Right-click on AdiBags' overlay lowers the level", KS.GetLevel(7002) == L.NORMAL, KS.GetLevel(7002))
STUB_ALT = true
CALL("Alt+Left-click: AdiBags (back up)", adi.__h_PreClick, adi, "LeftButton")
STUB_ALT = false
local adiBank = plain({ bag = -1, slot = 1, IsBank = function() return true end })
CALL("AdiBags_UpdateButton (bank)", ADI_MSG.AdiBags_UpdateButton, "AdiBags_UpdateButton", adiBank)
altClick("AdiBags closed bank", adiBank, 7001, STEP_UP)
local function bbItem(bag, slot, id) return { button = plain({}), currentData = { bagid = bag, slotid = slot, itemInfo = { itemLink = STUB_LINK(id) } } } end
local bb = bbItem(2, 3, 7003)
CALL("BetterBags item/Updated", BB_MSG["item/Updated"], {}, bb, {})
altClick("BetterBags", bb.button, 7003, STEP_UP)
local bbStale = bbItem(2, 3, 7001)
CALL("BetterBags item/Updated (stale)", BB_MSG["item/Updated"], {}, bbStale, {})
altClick("BetterBags showing another item", bbStale.button, 7003, STEP_UP)
local function parentWithID(id) return { GetID = function() return id end } end
local bag8r = plain({ BGR = { itemLocation = {}, itemID = 7001 }, GetParent = function() return parentWithID(2) end, GetID = function() return 1 end })
bag8r.SetItemDetails = BaganatorClassicLiveContainerItemButtonMixin.SetItemDetails -- Mixin() copies it onto the button
CHECK("Baganator's mixin is frozen (hooking it fails)", not pcall(hooksecurefunc, BaganatorClassicLiveContainerItemButtonMixin, "SetItemDetails", function() end))
CHECK("Custodian listens to Baganator's skin API", #BAGANATOR_LISTENERS == 1, #BAGANATOR_LISTENERS)
for _, fn in ipairs(BAGANATOR_LISTENERS) do CALL("Baganator hands over a button", fn, { regionType = "ItemButton", region = bag8r }) end
CALL("Baganator SetItemDetails", bag8r.SetItemDetails, bag8r, {})
altClick("Baganator", bag8r, 7001, KS.CONFIRM_ENABLED and L.LOCK or L.ONME) -- a second step up
local bagnon = plain({ GetBag = function() return 2 end, GetID = function() return 2 end, IsCached = function() return false end })
CALL("Bagnon Item:Update", Bagnon.Item.Update, bagnon)
altClick("Bagnon", bagnon, 7002, KS.CONFIRM_ENABLED and L.LOCK or L.ONME)
local cached = plain({ GetBag = function() return 2 end, GetID = function() return 3 end, IsCached = function() return true end })
CALL("Bagnon Item:Update (cached)", Bagnon.Item.Update, cached)
altClick("Bagnon cached view", cached, 7003, STEP_UP)

-- The Alt+Click sequence (Clicks.lua). This saved data is from 1.0.0 (no sequence yet), so it kept 1.0.0's clicks,
-- the Protection dial (the steps up above), and is offered the Quick loop once, after the intro.
CHECK("an install from 1.0.0 keeps the Protection dial", KS.ClickPreset() == "dial", KS.ClickPreset())
CHECK("test builds' wrap-around switch is gone", StandingOrdersCustodianDB.wrap == nil)
CHECK("the Quick loop offer waits for the intro to close", StandingOrdersCustodianDB.clickOffer == true and rawget(SOCustodianIntro, "__h_OnHide") ~= nil)
altClick("dial: Alt+Left-click on Always on me stops there", elv, 7001, L.ONME)
STUB_POPUP = nil
CALL("the intro closes", function() SOCustodianIntro:Hide(); rawget(SOCustodianIntro, "__h_OnHide")() end)
RUN_TIMERS()
CHECK("then the Quick loop is offered", STUB_POPUP and STUB_POPUP.which == "SOC_CLICK_OFFER" and StandingOrdersCustodianDB.clickOffer == nil)
CHECK("the offer explains the Quick loop", StaticPopupDialogs.SOC_CLICK_OFFER.text:find("Junk, then Locked, then Mail, then no mark again", 1, true) ~= nil)
STUB_POPUP = nil
CALL("offer again", KS.OfferQuickLoop)
CHECK("it's offered only once", STUB_POPUP == nil)
CALL("Switch", StaticPopupDialogs.SOC_CLICK_OFFER.OnAccept)
CHECK("Switch: the Quick loop", KS.ClickPreset() == "loop", KS.ClickPreset())
-- Quick loop: Junk, Locked, Mail, no mark; Always on me steps on like Locked; Alt+Right-click takes the mark off.
altClick("loop: Always on me goes on to Mail", elv, 7001, L.MAIL)
altClick("loop: Mail goes on to no mark", elv, 7001, L.NORMAL)
altClick("loop: no mark becomes Junk", elv, 7001, L.JUNK)
altClick("loop: Junk becomes Locked", elv, 7001, L.LOCK)
altClick("loop: Locked becomes Mail", elv, 7001, L.MAIL)
STUB_ALT = true
CALL("loop: Alt+Right-click", elv.__h_PreClick, elv, "RightButton")
STUB_ALT = false
CHECK("loop: Alt+Right-click takes the mark off", KS.GetLevel(7001) == L.NORMAL, KS.GetLevel(7001))
CHECK("loop: its words", KS.ClickText():find("then no mark again", 1, true) ~= nil and KS.ClickText():find("takes its mark off", 1, true) ~= nil, KS.ClickText())
-- Warnings: only when one click can take Locked or Always on me straight to Junk while Vendor sells Junk by itself.
StandingOrdersVendorDB = { autopilot = "junk" }
CHECK("the Quick loop has no risky step, so no warning", #KS.RiskySteps() == 0 and KS.WrapWarning() == nil)
CALL("/soc click dial", SlashCmdList.SOC, "click dial")
CHECK("the Protection dial has no risky step either", KS.ClickPreset() == "dial" and KS.WrapWarning() == nil)
CALL("/soc click ends loop", SlashCmdList.SOC, "click ends loop")
local warning = KS.WrapWarning()
CHECK("a dial whose ends loop is Custom, and warns", KS.ClickPreset() == "custom" and warning and warning:find("Standing Orders: Vendor", 1, true) ~= nil and warning:find("Always on me", 1, true) ~= nil, warning)
KS.SetLevel(7001, L.ONME, nil, { quiet = true, scope = "account" })
CHAT = {}
altClick("looping dial: Always on me wraps to Junk", elv, 7001, L.JUNK)
CHECK("that click says Vendor will sell it", CHAT_HAS("from Always on me to Junk"), CHAT[1])
CHAT = {}
CALL("login warning", KS.CheckWrapWarning)
CALL("login warning again", KS.CheckWrapWarning)
CHECK("the login warning shows once per combination", #CHAT == 1 and CHAT_HAS("Careful"), #CHAT)
StandingOrdersVendorDB = { autopilot = "off" }
CHECK("no warning while Vendor doesn't sell by itself", KS.WrapWarning() == nil)
StandingOrdersVendorDB = { autopilot = "junk" }
CALL("/soc click ends stop", SlashCmdList.SOC, "click ends stop")
CHECK("ends that stop: the Protection dial again", KS.ClickPreset() == "dial")
-- Your own order: Normal goes first when it's missing; an unknown mark is refused.
CALL("/soc click order lock junk", SlashCmdList.SOC, "click order lock junk")
local cfg = KS.GetClick()
CHECK("a custom order keeps Normal in it", KS.ClickPreset() == "custom" and #cfg.order == 3 and cfg.order[1] == L.NORMAL and cfg.order[2] == L.LOCK, #cfg.order)
CALL("/soc click right clear", SlashCmdList.SOC, "click right clear")
CHECK("custom: Alt+Right-click takes the mark off", KS.ClickStep(L.LOCK, false) == L.NORMAL)
CHAT = {}
CALL("/soc click order lock nonsense", SlashCmdList.SOC, "click order lock nonsense")
CHECK("an unknown mark is refused and the order kept", #KS.GetClick().order == 3 and CHAT_HAS("/soc click order"), #KS.GetClick().order)
StandingOrdersVendorDB = nil
CALL("/soc click loop", SlashCmdList.SOC, "click loop")
CHECK("/soc click loop: the Quick loop", KS.ClickPreset() == "loop")
local seqMenu = MENU_RADIOS(panel.clickChoice)
CHECK("settings: the sequence dropdown offers Quick loop and Protection dial", #seqMenu == 2 and seqMenu[1].text == "Quick loop" and seqMenu[1].selected(), #seqMenu)
CALL("settings: pick Protection dial", seqMenu[2] and seqMenu[2].pick)
CHECK("settings: Protection dial picked, and the note says so", KS.ClickPreset() == "dial" and panel.clickNote:GetText():find("protect it more", 1, true) ~= nil, panel.clickNote:GetText())
CALL("settings: pick Quick loop", seqMenu[1] and seqMenu[1].pick)
-- The sequence editor (advanced options): the marks in order, then those left out; Up and Down move, the box puts in.
local ed = panel.clickEditor
CHECK("editor: the Quick loop's marks in order, Disenchant and Always on me left out", ed.rows[1].level == L.NORMAL and ed.rows[2].level == L.JUNK and ed.rows[3].level == L.LOCK and ed.rows[4].level == L.MAIL and ed.rows[5].level == L.DISENCHANT and ed.rows[6].level == L.ONME and not ed.rows[6].check:GetChecked())
CALL("editor: Down on Junk", ed.rows[2].down:GetScript("OnClick"), ed.rows[2].down)
CHECK("editor: Junk moved after Locked, so it's Custom", KS.GetClick().order[2] == L.LOCK and KS.GetClick().order[3] == L.JUNK and KS.ClickPreset() == "custom")
ed.rows[6].check:SetChecked(true)
CALL("editor: put Always on me in", ed.rows[6].check:GetScript("OnClick"), ed.rows[6].check)
CHECK("editor: Always on me joins at the end", KS.GetClick().order[5] == L.ONME, KS.GetClick().order[5])
panel.clickBack:SetChecked(true)
CALL("settings: tick Alt+Right-click goes back", panel.clickBack:GetScript("OnClick"), panel.clickBack)
CHECK("settings: Alt+Right-click now steps back", KS.GetClick().back == true and KS.ClickStep(L.JUNK, false) == L.LOCK)
CALL("/soc click loop", SlashCmdList.SOC, "click loop")

-- The Disenchant level (1.2.0): kept from vendors, free to disenchant, trade and mail.
CHECK("Disenchant sits between Junk and Mail", L.DISENCHANT > L.JUNK and L.DISENCHANT < L.MAIL and KS.ORDER[2] == L.DISENCHANT)
CHAT = {}
CALL("/soc disenchant 7001", SlashCmdList.SOC, "disenchant 7001")
CHECK("/soc disenchant marks it Disenchant", KS.GetLevel(7001) == L.DISENCHANT, KS.GetLevel(7001))
CHECK("it isn't Locked", not KS.IsLocked(7001))
CHAT = {}
CHECK("selling it is stopped", KS.Guard(7001, nil, "sell") == true)
CHECK("the error says to disenchant it or lower it to Junk", CHAT_HAS("marked Disenchant"), CHAT[1])
CHECK("disenchanting, trading, mailing and destroying it are allowed", not KS.Guard(7001, nil, "disenchant") and not KS.Guard(7001, nil, "trade") and not KS.Guard(7001, nil, "mail") and not KS.Guard(7001, nil, "destroy"))
CALL("/soc de 7001", SlashCmdList.SOC, "de 7001")
CHECK("/soc de works too", KS.GetLevel(7001) == L.DISENCHANT)
CHECK("Disenchant is an advanced mark: offered once the advanced options are shown", (function()
  local was = KS.GetShowAdvanced(); KS.SetShowAdvanced(false)
  local hidden = true; for _, l in ipairs(KS.ShownLevels(L.NORMAL)) do if l == L.DISENCHANT then hidden = false end end
  KS.SetShowAdvanced(true)
  local shown = false; for _, l in ipairs(KS.ShownLevels(L.NORMAL)) do if l == L.DISENCHANT then shown = true end end
  KS.SetShowAdvanced(was); return hidden and shown end)())
KS.SetLevel(7001, L.NORMAL, nil, { quiet = true, scope = "account" })

-- Per-copy marks (Copies.lua, 1.2.0): a mark for an item's bound copies and for copies with an enchant.
local ENCHANTED = "|cffffffff|Hitem:7001:1897::::::::60:::::|h[Test]|h|r"
local PLAIN = "|cffffffff|Hitem:7001::::::::60:::::|h[Test]|h|r"
CHECK("the enchant comes from the link", KS.LinkEnchant(ENCHANTED) == 1897 and KS.LinkEnchant(PLAIN) == nil, KS.LinkEnchant(ENCHANTED))
CHECK("no copy marks: a copy has the item's mark", KS.GetCopyLevel(7001, ENCHANTED, true) == KS.GetLevel(7001) and not KS.HasCopyMarks(7001))
KS.SetCopyMark(7001, 1897, "account", L.LOCK)
CHECK("an enchant mark applies to copies with that enchant", KS.GetCopyLevel(7001, ENCHANTED, false) == L.LOCK, KS.GetCopyLevel(7001, ENCHANTED, false))
CHECK("...and not to copies without it", KS.GetCopyLevel(7001, PLAIN, false) == L.NORMAL, KS.GetCopyLevel(7001, PLAIN, false))
CHAT = {}
CHECK("selling the enchanted copy is stopped", KS.Guard(7001, ENCHANTED, "sell") == true)
CHECK("selling a plain copy isn't", KS.Guard(7001, PLAIN, "sell") == false)
KS.SetCopyMark(7001, 1897, "account", nil)
KS.SetCopyMark(7001, "bound", "account", L.LOCK)
CHECK("a bound-copies mark applies to bound copies", KS.GetCopyLevel(7001, PLAIN, true) == L.LOCK)
CHECK("...and not to unbound ones", KS.GetCopyLevel(7001, PLAIN, false) == L.NORMAL)
CHECK("disenchanting a bound copy is stopped, an unbound one isn't", KS.Guard(7001, PLAIN, "disenchant", true) == true and KS.Guard(7001, PLAIN, "disenchant", false) == false)
KS.SetCopyMark(7001, "bound", "char", L.NORMAL)
CHECK("this character's copy mark comes first (Normal here frees them)", KS.GetCopyLevel(7001, PLAIN, true) == L.NORMAL)
KS.SetCopyMark(7001, "bound", "char", nil)
KS.SetCopyMark(7001, 1897, "account", L.JUNK)
CHECK("an enchant mark comes before the bound one", KS.GetCopyLevel(7001, ENCHANTED, true) == L.JUNK and KS.GetCopyLevel(7001, PLAIN, true) == L.LOCK)
STUB_BOUND[7001] = true
CHECK("a bag slot's level uses that copy's bound status", KS.GetSlotLevel(2, 1) == L.LOCK, KS.GetSlotLevel(2, 1))
STUB_BOUND[7001] = nil
CHECK("...an unbound copy in the slot keeps the item's mark", KS.GetSlotLevel(2, 1) == L.NORMAL, KS.GetSlotLevel(2, 1))
KS.SetCopyMark(7001, 1897, "account", nil)
KS.SetCopyMark(7001, "bound", "account", nil)
CHECK("clearing every copy mark leaves no copies entry", not KS.HasCopyMarks(7001) and StandingOrdersCustodianDB.copies[7001] == nil)

-- Alt+Click can open the mark menu instead; /soc mark <item> opens it for any item
CHECK("Alt+Click cycles by default", KS.GetAltClick() == "cycle" and StandingOrdersCustodianDB.altClick == "cycle")
CALL("/soc altclick menu", SlashCmdList.SOC, "altclick menu")
KS.SetLevel(7001, L.NORMAL, nil, { quiet = true, scope = "account" })
altClick("menu mode: Alt+Left-click opens the menu", elv, 7001, L.NORMAL)
local menu = SOCustodianMarkMenu
CHECK("the mark menu is open on the item", menu and menu:IsShown() and menu.itemID == 7001)
CHECK("the menu has one button per level, own mark ticked", menu and #menu.buttons == #KS.ORDER and menu.buttons[4].check:IsShown() and not menu.buttons[1].check:IsShown())
if menu then
  for _, b in ipairs(menu.buttons) do if b.level == L.LOCK then CALL("pick Locked", b:GetScript("OnClick"), b) end end
end
CHECK("picking Locked marks it and closes the menu", KS.GetLevel(7001) == L.LOCK and not menu:IsShown(), KS.GetLevel(7001))
CALL("/soc mark 7001", SlashCmdList.SOC, "mark 7001")
CHECK("/soc mark opens the menu", menu:IsShown() and menu.itemID == 7001)
CALL("pick the ticked Locked again", KS.PickMark, L.LOCK)
CHECK("picking the ticked mark takes it off", KS.GetLevel(7001) == L.NORMAL and not menu:IsShown(), KS.GetLevel(7001))
CALL("/soc mark 7001", SlashCmdList.SOC, "mark 7001")
menu.char:SetChecked(true)
CALL("pick Mail for this character only", KS.PickMark, L.MAIL)
CHECK("the menu's This character only applies", KS.GetLevel(7001) == L.MAIL and KS.GetItemScope(7001) == "char", KS.GetItemScope(7001))
CALL("/soc altclick cycle", SlashCmdList.SOC, "altclick cycle")
KS.SetLevel(7001, L.ONME, nil, { quiet = true, scope = "account" })

-- The Marked items window: marked items plus bag items; the search narrows as you type; rows open the mark menu
CALL("/soc list", SlashCmdList.SOC, "list")
local marks = SOCustodianMarks
CHECK("/soc list opens the Marked items window", marks and marks:IsShown())
local function shownNames() local t = {} for _, e in ipairs(marks.entries or {}) do t[#t + 1] = e.name end return table.concat(t, ", ") end
CHECK("it lists marked items and unmarked bag items", marks.entries and #marks.entries >= 6 and shownNames():find("Hearthstone", 1, true) and shownNames():find("Silk Cloth", 1, true), shownNames())
CHECK("most protected first", marks.entries[1].level == L.ONME, marks.entries[1] and marks.entries[1].level)
local function search(text)
  marks.search:SetText(text)
  CALL("type " .. text, marks.search:GetScript("OnTextChanged"), marks.search)
end
search("ring")
CHECK("the search narrows as you type", #marks.entries >= 1 and shownNames():find("Test Ring", 1, true) and not shownNames():find("Hearthstone", 1, true), shownNames())
search("always on me")
local allOnMe = #marks.entries > 0
for _, e in ipairs(marks.entries) do if e.level ~= L.ONME then allOnMe = false end end
CHECK("the search matches mark names too", allOnMe, shownNames())
search("no such item")
CHECK("no match: an empty list and a note", #marks.entries == 0 and marks.count:GetText() == "Nothing matches.")
search("silk")
CHECK("an unmarked bag item shows as Normal", #marks.entries == 1 and marks.entries[1].level == L.NORMAL and marks.entries[1].scope == nil)
-- Two dropdown columns (This character, All characters) and the mark that counts.
local row = marks.rows[1]
CHECK("both columns are dropdowns", row.char.isDropdown and row.account.isDropdown)
local charMenu, acctMenu = MENU_RADIOS(row.char), MENU_RADIOS(row.account)
CHECK("This character starts at Account default", charMenu[1] and charMenu[1].text:find("Account default", 1, true) and charMenu[1].selected(), charMenu[1] and charMenu[1].text)
CHECK("All characters has no default choice and starts at Normal", acctMenu[1] and not acctMenu[1].text:find("default", 1, true) and #acctMenu == #charMenu - 1, #acctMenu)
local function pick(menu, level)
  for _, r in ipairs(menu) do if r.text == KS.LevelText(level) then CALL("pick " .. KS.NAMES[level], r.pick); return end end
  CHECK("menu offers " .. KS.NAMES[level], false)
end
pick(acctMenu, L.LOCK)
CHECK("All characters: Locked is saved and the list follows", KS.GetMarkIn(4306, "account") == L.LOCK and KS.GetLevel(4306) == L.LOCK and marks.entries[1].level == L.LOCK, marks.entries[1] and marks.entries[1].level)
CHECK("the Mark column says Locked", row.mark:GetText() == KS.LevelText(L.LOCK), row.mark:GetText())
pick(MENU_RADIOS(row.char), L.JUNK)
CHECK("This character: Junk wins and keeps the account-wide Locked", KS.GetLevel(4306) == L.JUNK and KS.GetMarkIn(4306, "account") == L.LOCK and KS.GetItemScope(4306) == "char", KS.GetLevel(4306))
CALL("pick Account default", MENU_RADIOS(row.char)[1].pick)
CHECK("Account default clears this character's mark: Locked again", KS.GetMarkIn(4306, "char") == nil and KS.GetLevel(4306) == L.LOCK, KS.GetLevel(4306))
-- Rows keep their place while the window is open; Re-sort (and opening it again) sorts afresh.
search("")
local function placeOf(id) for i, e in ipairs(marks.entries) do if e.id == id then return i end end end
local before = placeOf(4306)
KS.SetMarkIn(4306, "account", L.JUNK)
CHECK("changing a mark doesn't move its row", placeOf(4306) == before, placeOf(4306) .. " vs " .. tostring(before))
CALL("Re-sort", marks.resort:GetScript("OnClick"), marks.resort)
CHECK("Re-sort puts it with the other Junk, below the protected items", placeOf(4306) > before, placeOf(4306) .. " vs " .. tostring(before))
KS.SetMarkIn(4306, "account", L.LOCK)
search("silk")
pick(MENU_RADIOS(row.char), L.NORMAL)
CHECK("This character: Normal overrides the account-wide mark", KS.GetLevel(4306) == L.NORMAL and KS.GetMarkIn(4306, "char") == L.NORMAL, KS.GetLevel(4306))
CALL("pick Account default", MENU_RADIOS(row.char)[1].pick)
search("junk")
CHECK("the search matches either column's mark", #marks.entries == 0 or marks.entries[1].id ~= 4306)
search("locked")
local found = false
for _, e in ipairs(marks.entries) do if e.id == 4306 then found = true end end
CHECK("the search finds the account-wide Locked", found)
-- Shift-click an item, or drop one on the search box: it searches for that item.
search("")
CALL("shift-click Silk Cloth", ChatEdit_InsertLink, select(2, GetItemInfo(4306)))
CHECK("a shift-clicked item fills the search", marks.search:GetText() == "Silk Cloth" and #marks.entries == 1 and marks.entries[1].id == 4306, marks.search:GetText())
search("")
STUB_CURSOR = { id = 4306 }
CALL("drop Silk Cloth on the search box", marks.search:GetScript("OnReceiveDrag"), marks.search)
CHECK("a dropped item fills the search and goes back to the bags", marks.search:GetText() == "Silk Cloth" and STUB_CURSOR == nil, marks.search:GetText())
CALL("click the search box with nothing held", marks.search:GetScript("OnReceiveDrag"), marks.search)
CHECK("nothing held: the search is left alone", marks.search:GetText() == "Silk Cloth")
-- Shift+Left-click on a bag button (a stack too): Custodian's own click hook searches, not the game's link insert.
search("")
STUB_SHIFT = true
CALL("Shift+Left-click a bag item", elv.__h_PreClick, elv, "LeftButton")
CALL("its PostClick", elv.__h_PostClick, elv, "LeftButton")
STUB_SHIFT = false
CHECK("a shift-clicked bag item fills the search", marks.search:GetText() == GetItemInfo(7001), marks.search:GetText())
marks:Hide()
CHECK("with the window closed, shift-click is the game's again", not KS.MarkListTakesShiftClick())
marks:Show()
search("")
marks.bags:SetChecked(false)
CALL("untick Items in my bags", marks.bags:GetScript("OnClick"), marks.bags)
search("")
local onlyMarked = true
for _, e in ipairs(marks.entries) do if not e.scope then onlyMarked = false end end
CHECK("untick Items in my bags: only marked items", onlyMarked and #marks.entries > 0)
-- Taking a mark off (Account default and Normal) keeps the row in place until Re-sort.
local function shown(id) for i, e in ipairs(marks.entries) do if e.id == id then return i end end end
local at = shown(4306)
KS.SetMarkIn(4306, "char", nil)
KS.SetMarkIn(4306, "account", L.NORMAL)
CHECK("an unmarked row stays where it was", at and shown(4306) == at, tostring(shown(4306)) .. " vs " .. tostring(at))
CALL("Re-sort", marks.resort:GetScript("OnClick"), marks.resort)
CHECK("Re-sort drops it (Items in my bags is off)", shown(4306) == nil)
KS.SetMarkIn(4306, "account", L.LOCK)
CALL("/soc list print", SlashCmdList.SOC, "list print")
KS.SetLevel(4306, L.NORMAL, nil, { quiet = true, scope = "account" })
CHECK("status lists the hooked bag addons", #KS.BagAddonStatus() == 6, #KS.BagAddonStatus())

-- Back to simple: asks first, naming what changes; then every advanced option is at its simple default; marks stay.
KS.SetChat(true)
STUB_POPUP = nil
CALL("Back to simple", panel.simpleButton:GetScript("OnClick"), panel.simpleButton)
CHECK("Back to simple asks first, naming the options", STUB_POPUP and STUB_POPUP.which == "SOC_BACK_TO_SIMPLE" and tostring(STUB_POPUP.a1):find("chat logging", 1, true) ~= nil, STUB_POPUP and STUB_POPUP.a1)
local hearth = KS.GetLevel(6948)
CALL("confirm Back to simple", StaticPopupDialogs.SOC_BACK_TO_SIMPLE.OnAccept)
CHECK("every advanced option is back at its simple default", #KS.AdvancedOn() == 0 and not KS.GetChat() and not KS.GetAuto("whiteJunk") and KS.ClickPreset() == "loop", table.concat(KS.AdvancedOn(), ", "))
CHECK("marks stay as they are", KS.GetLevel(6948) == hearth, KS.GetLevel(6948))
CHAT = {}
CALL("/soc simple with nothing on", SlashCmdList.SOC, "simple")
CHECK("/soc simple says there's nothing to put back", CHAT_HAS("already at their simple defaults"), CHAT[1])

-- /soc why <item>: the unusable-gear rule for any item, no soulbound copy needed (2.2.5's easy test).
STUB_ITEMDB[7100] = { name = "Test Plate Chest", quality = 2, sellPrice = 100, classID = 4, subclassID = 4, minLevel = 10, equipLoc = "INVTYPE_CHEST" }
STUB_ITEMDB[7101] = { name = "Test Cloth Robe", quality = 1, sellPrice = 10, classID = 4, subclassID = 1, minLevel = 5, equipLoc = "INVTYPE_ROBE" }
STUB_CLASS, STUB_LEVEL = "MAGE", 20
CHAT = {}
CALL("/soc why a plate chest, as a Mage", SlashCmdList.SOC, "why 7100")
CHECK("/soc why: a Mage can never use plate, and the rule is off by default", CHAT_HAS("this class can't use it") and CHAT_HAS("The rule is off"), CHAT[1])
CHAT = {}
CALL("/soc why a cloth robe, as a Mage", SlashCmdList.SOC, "why 7101")
CHECK("/soc why: cloth is usable, left alone", CHAT_HAS("left alone"), CHAT[1])
STUB_CLASS, STUB_LEVEL = "WARRIOR", 60
local undefined = {}
for k in pairs(UNDEFINED) do undefined[#undefined + 1] = k end
table.sort(undefined)
print("info: globals Custodian looked for that the stub doesn't have: " .. table.concat(undefined, ", "))
