-- Smoke test for a new install (no saved data at all): the defaults a new player starts with. tools/smoke.lua
-- starts from 1.0.0's saved data instead. Run: node tools/harness.js StandingOrders_Custodian "" tools/smoke-fresh.lua
-- (tools/green.js runs both). Item names are made up; nothing here is a character or player name.

-- An epic ring no auto-mark touches, in the first slot of the default bags.
STUB_ITEMDB = { [7001] = { name = "Test Ring", quality = 4, sellPrice = 0, classID = 4, subclassID = 0, bindType = 1, equipLoc = "INVTYPE_FINGER" } }
local slot = {
  GetBagID = function() return 0 end,
  GetID = function() return 1 end,
  HookScript = function(self, script, fn) self["__h_" .. script] = fn end,
  CreateTexture = function() return STUB("Texture") end,
  GetWidth = function() return 37 end,
}
ContainerFrame1 = STUB("ContainerFrame1")
rawset(ContainerFrame1, "EnumerateValidItems", function()
  local done = false
  return function() if not done then done = true; return 1, slot end end
end)
STUB_BAGS[0] = { 7001 }
FIRE("ADDON_LOADED", "StandingOrders_Custodian")
FIRE("PLAYER_LOGIN")
RUN_TIMERS()
local KS = StandingOrdersCustodian
local L = KS.LEVELS
local db = StandingOrdersCustodianDB

-- The Alt+Click sequence: the Quick loop, with no offer (that's for players who had 1.0.0).
CHECK("a new install starts on the Quick loop", KS.ClickPreset() == "loop", KS.ClickPreset())
CHECK("...and isn't offered it", db.clickOffer == nil and not (STUB_POPUP and STUB_POPUP.which == "SOC_CLICK_OFFER"))
CHECK("the intro shows, and its short view has the Quick loop's words", SOCustodianIntro and SOCustodianIntro:IsShown() and KS.IntroText("short"):find("then no mark again", 1, true) ~= nil, KS.IntroText("short"))
KS.SetLevel(7001, L.NORMAL, nil, { quiet = true, scope = "account" })
local function click(mouse)
  STUB_ALT = true
  CALL("Alt+" .. mouse, slot.__h_PreClick, slot, mouse)
  STUB_ALT = false
  return KS.GetLevel(7001)
end
CHECK("default bags are hooked", slot.__h_PreClick ~= nil)
CHECK("Alt+Left-click: Junk", click("LeftButton") == L.JUNK, KS.GetLevel(7001))
CHECK("again: Locked", click("LeftButton") == L.LOCK, KS.GetLevel(7001))
CHECK("again: Mail", click("LeftButton") == L.MAIL, KS.GetLevel(7001))
CHECK("again: no mark", click("LeftButton") == L.NORMAL, KS.GetLevel(7001))
click("LeftButton")
click("LeftButton")
CHECK("Alt+Right-click on Locked takes the mark off", click("RightButton") == L.NORMAL, KS.GetLevel(7001))
CHECK("Alt+Right-click with no mark leaves it", click("RightButton") == L.NORMAL, KS.GetLevel(7001))

-- Simple options: only grays are auto-marked; the advanced options are hidden and all at their simple defaults.
CHECK("only the gray rule (and leaving items you got on purpose alone) is on", KS.GetAuto("grayJunk") and KS.GetAuto("keepReceived") and not KS.GetAuto("whiteJunk") and not KS.GetAuto("boeMail") and not KS.GetAuto("matsMail") and not KS.GetAuto("unusableJunk"))
local panel = SOCustodianSettings
CALL("settings panel OnShow", rawget(panel, "__s_OnShow"), panel)
CHECK("advanced options are hidden", not panel.advanced:IsShown() and not panel.advCheck:GetChecked())
CHECK("...and all at their simple defaults", #KS.AdvancedOn() == 0 and panel.advNote:GetText():find("simple defaults", 1, true) ~= nil, panel.advNote:GetText())
CHECK("the simple page says how Alt+Click works", panel.clickNote:GetText():find("then no mark again", 1, true) ~= nil, panel.clickNote:GetText())
CHECK("the intro's short view leaves Always on me out", not KS.IntroText("short"):find("Always on me", 1, true), KS.IntroText("short"))
local full = KS.IntroText()
CHECK("the detailed intro lists only the gray rule, and where the others are", full:find("• Grays", 1, true) ~= nil and not full:find("• White gear", 1, true) and full:find("Show advanced options", 1, true) ~= nil)
CALL("/soc mark 7001", SlashCmdList.SOC, "mark 7001")
local onme
for _, b in ipairs(SOCustodianMarkMenu.buttons) do if b.level == L.ONME then onme = b end end
CHECK("the mark menu leaves Always on me out", onme and not onme:IsShown())
KS.SetShowAdvanced(true)
CALL("/soc mark 7001 again", SlashCmdList.SOC, "mark 7001")
CHECK("...and shows it with the advanced options", onme and onme:IsShown())
KS.SetShowAdvanced(false)
