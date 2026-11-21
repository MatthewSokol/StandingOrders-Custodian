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
FIRE("ADDON_LOADED", "StandingOrders_Custodian")
FIRE("PLAYER_LOGIN")
local KS = StandingOrdersCustodian
local L = KS.LEVELS
CHECK("a per-character auto-mark on a reagent comes off at login", KS.GetLevel(17030) == L.NORMAL and next(StandingOrdersCustodianCharDB.autoMarked) == nil, KS.GetLevel(17030))
CHECK("Custodian global and levels", KS and L and L.MAIL == 1.5 and L.ONME == 5)
CHECK("the old global still works for Vendor, Mail and the config addon", StandingOrdersQuartermaster == KS)
CHECK("/soc is the command and /soq is gone", SlashCmdList.SOC ~= nil and SLASH_SOC1 == "/soc" and SlashCmdList.SOQ == nil)
CHECK("/custodian is the backup command", SLASH_SOC2 == "/custodian")
CHECK("slash command: /soc only (the old /faves is gone)", SLASH_SOC1 == "/soc" and SLASH_SOQ2 == nil)
CHECK("auto-mark settings default on", KS.GetAuto("grayJunk") and KS.GetAuto("matsMail") and KS.GetAuto("keepReceived"))

-- Auto-marks on what's in the bags at login
KS.SetLevel(6948, L.ONME, nil, { quiet = true })
STUB_BAGS[0] = { 6948, 4865, 25, 2589, 2770, 10940, 2320, 4540, 17030, 15210 }
RUN_TIMERS()
CALL("bag refresh with an empty slot", function() FIRE("BAG_UPDATE_DELAYED"); RUN_TIMERS() end)
CHECK("bag buttons after the empty slot still get hooked", rawget(bagButtons[3], "__h_PreClick") ~= nil)
CHECK("gray becomes Junk", KS.GetLevel(4865) == L.JUNK, KS.GetLevel(4865))
CHECK("white weapon becomes Junk", KS.GetLevel(25) == L.JUNK, KS.GetLevel(25))
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
CHECK("lowering a set item explains it stays protected", CHAT_HAS([[equipment set "Tank Gear"]]) and KS.GetLevel(9999) == L.ONME)
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
CALL("settings panel OnShow", panel and rawget(panel, "__s_OnShow"), panel)
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
CHECK("status lists the hooked bag addons", #KS.BagAddonStatus() == 6, #KS.BagAddonStatus())

local undefined = {}
for k in pairs(UNDEFINED) do undefined[#undefined + 1] = k end
table.sort(undefined)
print("info: globals Custodian looked for that the stub doesn't have: " .. table.concat(undefined, ", "))
