-- Faves: per-item protection levels that every item-losing action (selling, disenchanting,
-- destroying, trading, mailing) honors.
--
-- Levels (stored per item ID, account wide):
--   Junk     safe to get rid of (SellAll sells these automatically when a vendor opens)
--   Normal   the default, stored as nil
--   Confirm  "levelling favorite": meant to ask first. No confirm window yet, so for now it acts as Locked
--   Locked   never sold, disenchanted, destroyed, traded or mailed until you lower it
--
-- Other addons: Faves.GetLevel(itemID), Faves.IsLocked(itemID), Faves.LEVELS, and
-- Faves.Guard(itemID, link, action), which shows the error and returns true when the action must stop.

local ADDON = ...
local KS = {}
_G.Faves = KS

local JUNK, NORMAL, CONFIRM, LOCK = 1, 2, 3, 4
KS.LEVELS = { JUNK = JUNK, NORMAL = NORMAL, CONFIRM = CONFIRM, LOCK = LOCK }

local NAMES = { [JUNK] = "Junk", [NORMAL] = "Normal", [CONFIRM] = "Confirm", [LOCK] = "Locked" }
local COLORS = { [JUNK] = "ff9d9d9d", [NORMAL] = "ffffffff", [CONFIRM] = "ffffd100", [LOCK] = "ffff4040" }
local ICONS = {
  [JUNK] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
  [CONFIRM] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  [LOCK] = "Interface\\Icons\\INV_Misc_Key_03",
}
-- Spells that destroy the item you click: Disenchant, Prospecting, Milling (ignored if the client lacks them).
local DESTRUCTIVE_SPELLS = { 13262, 31252, 51005 }
local DELETE_POPUPS = { DELETE_ITEM = true, DELETE_GOOD_ITEM = true, DELETE_QUEST_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

local C = C_Container
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local IsCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
local NUM_BAGS = NUM_BAG_SLOTS or 4

local db
local merchantOpen = false

---------------------------------------------------------------------------------------------------
-- Output

local function Print(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Faves|r: " .. msg)
end

local function Debug(msg, ...)
  if db and db.debug then Print("|cff888888[debug]|r " .. msg, ...) end
end

-- Always-on log of guard decisions, kept in SavedVariables (FavesDB.log) so a miss can be
-- diagnosed after /reload. Also echoed to chat with /faves debug.
local function Log(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  if db then
    db.log = db.log or {}
    table.insert(db.log, date("%m-%d %H:%M:%S ") .. msg)
    while #db.log > 200 do table.remove(db.log, 1) end
  end
  Debug(msg)
end

local function Err(msg)
  UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2)
  Print("|cffff4040%s|r", msg)
end

local function LinkID(link) return link and tonumber(link:match("item:(%d+)")) end

local function ItemLink(id) return select(2, GetItemInfo(id)) or ("item:" .. id) end

local function LevelText(level)
  local text = "|c" .. COLORS[level] .. NAMES[level] .. "|r"
  if level == CONFIRM then text = text .. " (no confirm window yet: acts as Locked)" end
  return text
end
KS.LevelText = LevelText

---------------------------------------------------------------------------------------------------
-- Levels and the guard every action goes through

function KS.GetLevel(id) return (id and db and db.items[id]) or NORMAL end

-- True when the item must not leave your bags without you lowering its level first.
function KS.IsLocked(id) return KS.GetLevel(id) >= CONFIRM end

local RefreshBags -- defined with the bag hooks below

function KS.SetLevel(id, level, link)
  if not id then return end
  db.items[id] = (level ~= NORMAL) and level or nil
  Print("%s is now %s.", link or ItemLink(id), LevelText(level))
  RefreshBags()
end

-- The one check for any action that would lose an item. Returns true (and shows the error) when the
-- item is locked, so callers just do: if Faves.Guard(id, link, "sell") then <undo or block> end
function KS.Guard(id, link, action)
  if not KS.IsLocked(id) then return false end
  local level = KS.GetLevel(id)
  Err(("%s is %s. Unfavorite it to %s it (Alt+Right-click it in your bags, or /faves normal <item>).")
    :format(link or ItemLink(id), NAMES[level], action))
  Log("blocked %s of item %d (level %s)", action, id, NAMES[level])
  return true
end

-- One-time move of levels kept by SellAll 1.0 betas (SellAllDB.items). Existing Faves levels win.
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
  Log("cast/use recorded: %s %s %s", kind, tostring(name), tostring(id))
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

local function ButtonSlot(btn)
  if btn.GetBagID then return btn:GetBagID(), btn:GetID() end
  local parent = btn:GetParent()
  return parent and parent:GetID(), btn:GetID()
end

local function UpdateButton(btn)
  local bag, slot = ButtonSlot(btn)
  local info = bag and slot and C.GetContainerItemInfo(bag, slot)
  local icon = ICONS[info and KS.GetLevel(info.itemID) or NORMAL]
  local tex = btn.favesIcon
  if icon then
    if not tex then
      tex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
      tex:SetSize(14, 14)
      tex:SetPoint("TOPLEFT", 1, -1)
      btn.favesIcon = tex
    end
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

  -- Alt+Left-click raises protection (Junk > Normal > Confirm > Locked); Alt+Right-click lowers it.
  if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
    local cur = KS.GetLevel(info.itemID)
    local new = math.max(JUNK, math.min(LOCK, cur + (mouse == "LeftButton" and 1 or -1)))
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
    if KS.Guard(info.itemID, info.hyperlink, action) then
      SpellStopTargeting()
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
  for _, btn in frame:EnumerateValidItems() do
    HookButton(btn)
    UpdateButton(btn)
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

function RefreshBags()
  for _, frame in ipairs(BagFrames()) do UpdateFrame(frame) end
end

local function HookBags()
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
    SpellStopTargeting()
    Log("blocker caught click on %s", info and info.hyperlink or "?")
    if info then KS.Guard(info.itemID, info.hyperlink, BlockAction()) end
  end)
  b:SetScript("OnEnter", function(self)
    local bag, slot = ButtonSlot(btn)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if bag and slot then GameTooltip:SetBagItem(bag, slot) end
    GameTooltip:AddLine("Protected by Faves: this click is blocked.", 1, 0.3, 0.3)
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
      want = (info and info.itemID and KS.IsLocked(info.itemID)) and true or false
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
        Err(("Faves couldn't stop this cast on %s. Details are in /faves log.")
          :format(info.hyperlink))
        return
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Tooltip line

local function HookTooltip()
  if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
    local level = KS.GetLevel(data and data.id)
    if level ~= NORMAL then tip:AddLine("Faves: " .. LevelText(level)) end
  end)
end

---------------------------------------------------------------------------------------------------
-- One-time intro: what Confirm/Locked protect, and what they don't yet. Shown until "Got it" is
-- clicked; bump INTRO_VERSION when the list changes so everyone sees the new one once.

local INTRO_VERSION = 1
local INTRO_TEXT = table.concat({
  "|cffffd100Confirm|r (star icon) and |cffff4040Locked|r (key icon) items are protected. Alt+Left-click an item in your bags to protect it more, Alt+Right-click to protect it less. For now Confirm works the same as Locked.",
  "|cff9d9d9dJunk|r (coin icon) marks items you're happy to lose: SellAll sells them when a vendor opens.",
  "",
  "|cff33ff99Protected against|r",
  "- Selling it: it's bought straight back while the vendor is open (SellAll's Sell All skips it)",
  "- Disenchant, Prospecting, Milling: the click is blocked",
  "- Destroying: the delete popup closes",
  "- Trade and mail: the item is taken back out",
  "",
  "|cff33ff99Still allowed|r",
  "- Enchants, oils and scrolls",
  "",
  "|cffff8040Not protected yet|r",
  "- Auction house posting",
  "- Using or eating the item, or handing it to an NPC",
  "- Closing the vendor right after a sale, before it can be bought back",
  "- ArkInventory bags: no Alt+Click, icons or Disenchant block",
}, "\n")

local intro

function KS:ShowIntro()
  if not intro then
    intro = CreateFrame("Frame", "FavesIntro", UIParent, "BasicFrameTemplateWithInset")
    intro:SetPoint("CENTER")
    intro:SetFrameStrata("DIALOG")
    intro:SetClampedToScreen(true)
    intro:EnableMouse(true)
    intro:SetMovable(true)
    intro:RegisterForDrag("LeftButton")
    intro:SetScript("OnDragStart", intro.StartMoving)
    intro:SetScript("OnDragStop", intro.StopMovingOrSizing)

    local title = intro:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Faves: what Confirm and Locked protect")

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
      Print("You can reopen this with /faves intro.")
    end)

    intro:SetSize(480, body:GetStringHeight() + 38 + 54)
    tinsert(UISpecialFrames, "FavesIntro") -- Esc closes it (it shows again next login until "Got it")
  end
  intro:Show()
end

---------------------------------------------------------------------------------------------------
-- Slash commands

local function ListItems()
  local any = false
  for _, level in ipairs({ JUNK, CONFIRM, LOCK }) do
    for id, l in pairs(db.items) do
      if l == level then
        any = true
        Print("%s: %s", LevelText(level), ItemLink(id))
      end
    end
  end
  if not any then Print("No items are marked. Alt+Click an item in your bags to mark it.") end
end

local function Help()
  Print("Commands:")
  print("  /faves junk|normal|confirm|lock <item link or ID> - set an item's level")
  print("  /faves list - show marked items")
  print("  /faves status - check which guards are active")
  print("  /faves intro - what Confirm and Locked protect (and what they don't yet)")
  print("  /faves log [n] - show the last n guard log lines (default 25)")
  print("  /faves debug - toggle debug messages")
  print("  In bags: Alt+Left-click raises protection, Alt+Right-click lowers it.")
end

local function Status()
  Print("Status:")
  print("  bag buttons hooked: " .. hookedCount .. " (open your bags to hook more)")
  print("  disenchant guard: on (IsCurrentSpell " .. (IsCurrentSpell and "available" or "missing") ..
    ", last cast: " .. (castRecord and (castRecord.kind .. " " .. tostring(castRecord.name or castRecord.id)) or "none") .. ")")
  print("  destroy guard: " .. (StaticPopup_Show and "on" or "OFF"))
  print("  tooltip line: " .. ((TooltipDataProcessor and "on") or "OFF"))
  print("  trade/mail/vendor buyback guards: on (vendor open: " .. tostring(merchantOpen) .. ")")
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ArkInventory") then
    print("  |cffffd100ArkInventory is loaded: Alt+Click, bag icons and the disenchant guard only work in the default bags.|r")
  end
end

local LEVEL_CMDS = { junk = JUNK, normal = NORMAL, confirm = CONFIRM, lock = LOCK, locked = LOCK }

SLASH_FAVES1 = "/faves"
SlashCmdList.FAVES = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if LEVEL_CMDS[cmd] and rest ~= "" then
    local id = LinkID(rest) or tonumber(rest)
    if not id then return Err("Shift-click an item into the command, or give its item ID.") end
    KS.SetLevel(id, LEVEL_CMDS[cmd], rest:match("|c.-|r") or ItemLink(id))
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
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
f:RegisterEvent("MAIL_SEND_INFO_UPDATE")
f:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")

f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    FavesDB = FavesDB or {}
    db = FavesDB
    db.items = db.items or {}
  elseif event == "PLAYER_LOGIN" then
    HookBags()
    HookCasts()
    HookTooltip()
    HookDestroy()
    if db.introSeen ~= INTRO_VERSION then C_Timer.After(4, function() KS:ShowIntro() end) end
  elseif event == "MERCHANT_SHOW" then
    merchantOpen = true
    QueueRescue()
  elseif event == "MERCHANT_CLOSED" then
    merchantOpen = false
  elseif event == "MERCHANT_UPDATE" then
    QueueRescue()
  elseif event == "CURRENT_SPELL_CAST_CHANGED" then
    OnSpellCastChanged()
  elseif event == "UNIT_SPELLCAST_SENT" then
    OnSpellcastSent(arg2, arg4) -- unit, target, castGUID, spellID
  elseif event == "BAG_UPDATE_DELAYED" then
    RefreshBags()
    if merchantOpen then QueueRescue() end
  elseif event == "TRADE_PLAYER_ITEM_CHANGED" then
    if arg1 then CheckTrade(arg1) end
  elseif event == "MAIL_SEND_INFO_UPDATE" then
    CheckMail()
  end
end)
