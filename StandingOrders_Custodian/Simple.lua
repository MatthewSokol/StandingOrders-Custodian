-- Custodian: simple and advanced options. The settings page always shows the simple ones (how Alt+Click works,
-- "Gray items become Junk", the intro and the Marked items window); "Show advanced options" shows the rest.
-- Showing or hiding them changes nothing about what Custodian does: only the options' values do. The simple page
-- names the advanced options that aren't at their simple defaults, and "Back to simple" puts them back.
-- A field-only file: Custodian.lua's main chunk is at Lua's 200-local limit.

local KS = StandingOrdersCustodian
local L = KS.LEVELS

local AUTO_LABELS = {
  whiteJunk = "white gear becomes Junk",
  unusableJunk = "unusable soulbound gear becomes Junk",
  matsMail = "crafting materials become Mail",
  boeMail = "Bind on Equip items become Mail",
  keepReceived = "items you got on purpose can be auto-marked",
}

function KS.GetShowAdvanced()
  local db = StandingOrdersCustodianDB
  return (db and db.showAdvanced) and true or false
end

function KS.SetShowAdvanced(on)
  local db = StandingOrdersCustodianDB
  if db then db.showAdvanced = on and true or false end
end

-- The advanced options that aren't at their simple defaults, as short labels, in settings order.
function KS.AdvancedOn()
  local out = {}
  if KS.ClickPreset() ~= "loop" then out[#out + 1] = "Alt+Click sequence (" .. KS.CLICK_PRESET_NAMES[KS.ClickPreset()] .. ")" end
  if KS.GetAltClick() == "menu" then out[#out + 1] = "Alt+Click opens a menu" end
  for _, key in ipairs(KS.AUTO_KEYS) do
    if AUTO_LABELS[key] and (KS.GetAuto(key) and true or false) ~= KS.AUTO_DEFAULTS[key] then out[#out + 1] = AUTO_LABELS[key] end
  end
  if KS.GetScope() == "char" then out[#out + 1] = "new marks for this character only" end
  if KS.GetChat() then out[#out + 1] = "messages in chat" end
  local size, anchor, alpha = KS.GetIconStyle()
  local d = KS.ICON_DEFAULTS
  if size ~= d.size or anchor ~= d.anchor or alpha ~= d.alpha or (d.style and KS.GetIconStyleName and KS.GetIconStyleName() ~= d.style) then
    out[#out + 1] = "mark icons"
  end
  local sets = KS.GetSetDefault() ~= L.LOCK
  for _, set in ipairs(KS.EquipmentSets()) do if KS.GetSetChoice(set.id) ~= "default" then sets = true end end
  if sets then out[#out + 1] = "equipment set levels" end
  return out
end

-- Every advanced option back to its simple default. Marks stay as they are.
function KS.ResetToSimple()
  KS.ApplyClickPreset("loop")
  KS.SetAltClick("cycle")
  for _, key in ipairs(KS.AUTO_KEYS) do
    if AUTO_LABELS[key] then KS.SetAuto(key, KS.AUTO_DEFAULTS[key]) end
  end
  KS.SetScope("account")
  KS.SetChat(false)
  for key, value in pairs(KS.ICON_DEFAULTS) do KS.SetIconStyle(key, value) end
  for _, set in ipairs(KS.EquipmentSets()) do KS.SetSetChoice(set.id, "default") end
  KS.SetSetChoice(nil, L.LOCK)
end

StaticPopupDialogs.SOC_BACK_TO_SIMPLE = {
  text = "Put these advanced options back to their simple defaults?\n\n%s\n\nYour marks stay as they are.",
  button1 = "Back to simple",
  button2 = CANCEL or "Cancel",
  OnAccept = function()
    KS.ResetToSimple()
    KS.Print("Back to the simple options. %s", KS.ClickText())
    if KS.RefreshSettings then KS.RefreshSettings() end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- "Back to simple" (the settings button, /soc simple): asks first, naming what changes.
function KS.AskBackToSimple()
  local on = KS.AdvancedOn()
  if #on == 0 then return KS.Print("All advanced options are already at their simple defaults.") end
  StaticPopup_Show("SOC_BACK_TO_SIMPLE", table.concat(on, ", "))
end

-- The marks to offer (the mark menu, the intro's short view): Always on me only with the advanced options shown,
-- when it's in the Alt+Click sequence, or when it's the item's own mark (own).
function KS.ShownLevels(own)
  local inSequence = {}
  for _, level in ipairs(KS.GetClick().order) do inSequence[level] = true end
  local out = {}
  for _, level in ipairs(KS.ORDER) do
    if level ~= L.ONME or KS.GetShowAdvanced() or inSequence[level] or own == level then out[#out + 1] = level end
  end
  return out
end

-- /soc why <item>: what the "soulbound gear this character can't use" rule decides for an item, without needing a
-- soulbound copy: shift-click any link (chat, the auction house). For testing the rule and for curious players.
function KS.WhyUnusable(id, link)
  local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, _, quality, _, _, _, _, _, equipLoc, _, _, classID, subclassID = GetInfo(id)
  if not name then return KS.Print("That item isn't loaded yet; try again in a moment.") end
  local minLevel = select(5, GetInfo(id))
  local class, level = UnitClass and UnitClass("player") or "?", UnitLevel and UnitLevel("player") or 1
  local reason = KS.UnusableReason(classID, subclassID, minLevel)
  local verdict
  if classID ~= 2 and classID ~= 4 then
    verdict = "not a weapon or armor, so this rule leaves it alone"
  elseif equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then
    verdict = "shirts and tabards are never marked"
  elseif not reason then
    verdict = "usable by this character now or within 5 levels, so it's left alone"
  elseif (quality or 0) >= 2 and KS.IsEnchanter() then
    verdict = (reason == "never" and "this class can't use it" or "not usable for 5+ levels")
      .. ", but this character is an enchanter: green and better stays Normal to disenchant"
  else
    verdict = (reason == "never" and "this class can't use it" or "not usable for 5+ levels")
      .. ": a soulbound copy becomes Junk on this character only"
  end
  KS.Print("%s for this %s (level %d): %s.%s", link, class, level, verdict,
    KS.GetAuto("unusableJunk") and "" or " (The rule is off: /soc settings > Show advanced options > More auto-marks.)")
end
