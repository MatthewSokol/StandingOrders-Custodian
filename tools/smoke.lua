-- Smoke test: loads Faves with the stubbed API, then walks through its main features and checks the
-- results. Run: node tools/harness.js Faves "" tools/smoke.lua   (green = no ERROR/FAIL lines)
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
  }
end
local bagButtons = { button(0, 1), nil, button(0, 3) }
ContainerFrame1 = STUB("ContainerFrame1")
rawset(ContainerFrame1, "EnumerateValidItems", function()
  local i = 0
  return function() i = i + 1; if i <= 3 then return i, bagButtons[i] end end
end)

FIRE("ADDON_LOADED", "Faves")
FIRE("PLAYER_LOGIN")
local KS = Faves
local L = KS.LEVELS
CHECK("Faves global and levels", KS and L and L.MAIL == 1.5 and L.ONME == 5)
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
  CALL("/faves " .. cmd, SlashCmdList.FAVES, cmd)
end
CALL("/faves lock <item>", SlashCmdList.FAVES, "lock " .. STUB_LINK(25))
CHECK("/faves lock sets Locked", KS.GetLevel(25) == L.LOCK, KS.GetLevel(25))
CALL("/faves mail <id> char", SlashCmdList.FAVES, "mail 25 char")
CHECK("/faves mail ... char marks this character", KS.GetLevel(25) == L.MAIL and KS.GetItemScope(25) == "char")

-- Self-test and Mechanic (with a stand-in MechanicLib)
local registered
LibStub = function(name) if name == "MechanicLib-1.0" then return {
  Register = function(_, addon, caps) registered = { addon = addon, caps = caps } end,
  Log = function() end, Categories = { CORE = "[Core]" },
} end end
FIRE("PLAYER_LOGIN") -- registers again now that MechanicLib is here (hooks are idempotent enough for a stub)
RUN_TIMERS()
CHECK("registered with Mechanic", registered and registered.addon == "Faves" and registered.caps.tests ~= nil)
if registered then
  CALL("Mechanic runAll", registered.caps.tests.runAll)
  local all = registered.caps.tests.getAll()
  CHECK("Mechanic sees the tests", #all >= 5, #all)
  for _, t in ipairs(all) do
    local r = registered.caps.tests.getResult(t.id)
    CHECK("self-test " .. t.id .. " passes (" .. tostring(r and r.message) .. ")", r and r.passed)
  end
end
CALL("/faves selftest", SlashCmdList.FAVES, "selftest")
CHECK("self-test saved", FavesDB.selfTest and FavesDB.selfTest.passed == true)

local undefined = {}
for k in pairs(UNDEFINED) do undefined[#undefined + 1] = k end
table.sort(undefined)
print("info: globals Faves looked for that the stub doesn't have: " .. table.concat(undefined, ", "))
