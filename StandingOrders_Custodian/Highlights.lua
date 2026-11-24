-- Custodian: tint bag slots at a vendor and at the mailbox, so you see at a glance what can go and what can't.
--   vendor   red: can't be sold (Locked, Always on me, Disenchant); blue: Junk
--   mailbox  red: can't be mailed (Locked, Always on me); blue: Mail
-- A tint only: unlike the disenchant cover it never takes the click. Each slot uses that copy's mark (Copies.lua).
-- On unless turned off (StandingOrdersCustodianDB.highlight = false): /soc highlight on|off, or the switch under
-- Mark icons in the advanced options.

local KS = StandingOrdersCustodian
local L = KS.LEVELS
local RED, BLUE = { 1, 0.1, 0.1, 0.35 }, { 0.2, 0.55, 1, 0.38 }
local tints = setmetatable({}, { __mode = "k" }) -- bag button -> its tint texture (no new fields on other addons' frames)
local where -- "vendor", "mail" or nil

function KS.GetHighlight() local db = StandingOrdersCustodianDB; return not (db and db.highlight == false) end
function KS.SetHighlight(on)
  local db = StandingOrdersCustodianDB
  if db then -- only "off" is saved (not "x and false or nil": that is always nil)
    if on then db.highlight = nil else db.highlight = false end
  end
  KS.RefreshHighlights()
end
function KS.HighlightPlace() return where end

-- The tint a level gets here: RED, BLUE or nil.
function KS.HighlightColor(level, place)
  place = place or where
  if place == "vendor" then
    if level >= L.CONFIRM or level == L.DISENCHANT then return RED end
    if level == L.JUNK then return BLUE end
  elseif place == "mail" then
    if level >= L.CONFIRM then return RED end
    if level == L.MAIL then return BLUE end
  end
end

-- Called for each bag button when its icon is updated (Custodian.lua's UpdateButton) and on a refresh.
function KS.UpdateHighlight(btn, bag, slot)
  local color = where and KS.GetHighlight() and bag and slot and KS.HighlightColor(KS.GetSlotLevel(bag, slot))
  local tex = tints[btn]
  if not color then
    if tex then tex:Hide() end
    return
  end
  if not tex then
    tex = btn:CreateTexture(nil, "OVERLAY", nil, 5) -- under the mark icon (sublevel 7)
    tex:SetAllPoints(btn)
    tints[btn] = tex
  end
  tex:SetColorTexture(color[1], color[2], color[3], color[4])
  tex:Show()
end

-- The tint shown on a bag button right now (for the self-test and the smoke test), or nil.
function KS.HighlightShown(btn) local tex = tints[btn]; return (tex and tex:IsShown()) and tex or nil end

function KS.RefreshHighlights()
  if not KS.BagButtons then return end
  for btn in pairs(KS.BagButtons()) do
    local bag, slot = KS.ButtonSlot(btn)
    KS.UpdateHighlight(btn, bag, slot)
  end
end

local function SetPlace(place)
  where = place
  KS.RefreshHighlights()
end

local f = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "BAG_UPDATE_DELAYED" }) do
  pcall(f.RegisterEvent, f, event)
end
f:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_SHOW" then SetPlace("vendor")
  elseif event == "MAIL_SHOW" then SetPlace("mail")
  elseif event == "MERCHANT_CLOSED" or event == "MAIL_CLOSED" then SetPlace(nil)
  elseif where then KS.RefreshHighlights() end -- items moved while the window is open
end)

-- /soc highlight [on|off]
function KS.HighlightCommand(rest)
  if rest == "on" or rest == "off" then KS.SetHighlight(rest == "on") else KS.SetHighlight(not KS.GetHighlight()) end
  KS.Print("Vendor and mailbox highlights: %s (red: can't be sold or mailed; blue: Junk at a vendor, Mail at the mailbox).",
    KS.GetHighlight() and "on" or "off")
  if KS.RefreshSettings then KS.RefreshSettings() end
end
