-- Custodian: what Alt+Click in your bags does. One sequence of marks (StandingOrdersCustodianDB.click =
-- { order = { levels }, back = bool, loop = bool }), from a preset or your own:
--   Quick loop (new installs): Alt+Left-click goes Junk, Locked, Mail, then no mark again; Alt+Right-click takes
--     the mark off. Going forward, a protected item is never one click from Junk.
--   Protection dial (1.0.0's clicks, kept for players who had 1.0.0): Alt+Left-click protects more (Junk, Mail,
--     Normal, Locked, Always on me), Alt+Right-click less, stopping at both ends.
--   Custom: any order of the marks (Normal always in it), Alt+Right-click unmarks or steps back, the ends loop or stop.
-- A field-only file: Custodian.lua's main chunk is at Lua's 200-local limit.

local KS = StandingOrdersCustodian
local L = KS.LEVELS
local JUNK, MAIL, NORMAL, LOCK, ONME = L.JUNK, L.MAIL, L.NORMAL, L.LOCK, L.ONME

local PRESETS = {
  loop = { order = { NORMAL, JUNK, LOCK, MAIL }, back = false, loop = true },
  dial = { order = { JUNK, MAIL, NORMAL, LOCK, ONME }, back = true, loop = false },
}
KS.CLICK_PRESETS = PRESETS
KS.CLICK_PRESET_NAMES = { loop = "Quick loop", dial = "Protection dial", custom = "Custom" }

local KNOWN = { [JUNK] = true, [L.DISENCHANT] = true, [MAIL] = true, [NORMAL] = true, [LOCK] = true, [ONME] = true }
if KS.CONFIRM_ENABLED then KNOWN[L.CONFIRM] = true end

local function DB() return StandingOrdersCustodianDB end

-- Known levels, each once, with Normal (no mark) in it: put first when it's missing.
local function Clean(order)
  local out, seen = {}, {}
  for _, level in ipairs(type(order) == "table" and order or {}) do
    if KNOWN[level] and not seen[level] then seen[level] = true; out[#out + 1] = level end
  end
  if not seen[NORMAL] then table.insert(out, 1, NORMAL) end
  return out
end

local function Copy(cfg)
  return { order = Clean(cfg.order), back = cfg.back and true or false, loop = cfg.loop and true or false }
end

-- The sequence in use (a copy; the Quick loop when nothing valid is saved).
function KS.GetClick()
  local db = DB()
  local c = db and db.click
  if type(c) ~= "table" or type(c.order) ~= "table" then return Copy(PRESETS.loop) end
  return Copy(c)
end

-- Saves a sequence; false when it has fewer than two marks.
function KS.SetClick(cfg)
  local db = DB()
  if not (db and type(cfg) == "table") then return false end
  local c = Copy(cfg)
  if #c.order < 2 then return false end
  db.click = c
  return true
end

-- "loop", "dial" or "custom".
function KS.ClickPreset(cfg)
  cfg = cfg or KS.GetClick()
  for name, p in pairs(PRESETS) do
    local same = p.back == cfg.back and p.loop == cfg.loop and #p.order == #cfg.order
    for i, level in ipairs(p.order) do if cfg.order[i] ~= level then same = false end end
    if same then return name end
  end
  return "custom"
end

function KS.ApplyClickPreset(name) return PRESETS[name] ~= nil and KS.SetClick(PRESETS[name]) end

-- The mark one Alt+Click gives an item at level cur (forward: Alt+Left-click). Returns cur when it stays (an end
-- that doesn't loop). A mark that isn't in the sequence (Always on me in the Quick loop) counts as the nearest one
-- in it, the more protected on a tie: Always on me steps on like Locked.
function KS.ClickStep(cur, forward, cfg)
  cfg = cfg or KS.GetClick()
  if not forward and not cfg.back then return NORMAL end
  local order, i, best = cfg.order, nil, nil
  for n, level in ipairs(order) do
    local d = math.abs(level - cur)
    if not best or d < best or (d == best and level > order[i]) then i, best = n, d end
  end
  local j = i + (forward and 1 or -1)
  if j < 1 or j > #order then
    if not cfg.loop then return cur end
    j = (j - 1) % #order + 1
  end
  return order[j]
end

-- Steps where one Alt+Click takes a protected item (Locked or Always on me) straight to Junk.
function KS.RiskySteps(cfg)
  cfg = cfg or KS.GetClick()
  local out = {}
  for _, from in ipairs({ LOCK, ONME }) do
    for _, forward in ipairs({ true, false }) do
      if KS.ClickStep(from, forward, cfg) == JUNK then out[#out + 1] = { from = from, forward = forward } end
    end
  end
  return out
end

-- Standing Orders addons that act on marks by themselves: Vendor sells Junk when a vendor opens (its autopilot,
-- on by default) and Mail sends Mail items when a mailbox opens (its autopilot).
function KS.SelfActing()
  local v, m = rawget(_G, "StandingOrdersVendorDB"), rawget(_G, "StandingOrdersMailDB")
  return {
    vendor = type(v) == "table" and v.autopilot ~= nil and v.autopilot ~= "off",
    mail = type(m) == "table" and m.autopilot == true,
  }
end

-- The warning (and a key for the combination), or nil: when one Alt+Click can take a Locked or Always on me item
-- to Junk while Standing Orders: Vendor sells Junk by itself. A step onto Mail only sends the item to your bank
-- character, so it isn't warned about. The name is older than the sequences; Standing Orders: Mail calls it too.
function KS.WrapWarning()
  if KS.GetAltClick() == "menu" or not KS.SelfActing().vendor then return nil end
  local risky = KS.RiskySteps()
  if #risky == 0 then return nil end
  local parts, key = {}, "vendor"
  for _, r in ipairs(risky) do
    parts[#parts + 1] = (r.forward and "Alt+Left-click" or "Alt+Right-click") .. " on " .. KS.LevelText(r.from)
    key = key .. ":" .. r.from .. (r.forward and "+" or "-")
  end
  return "Careful: in your Alt+Click sequence, one " .. table.concat(parts, " or one ") .. " makes the item Junk, and "
    .. "Standing Orders: Vendor sells Junk when you open a vendor. Pick another sequence in /soc settings if that's a risk for you.", key
end

-- Shown once per combination (at login, so turning on Vendor's autopilot later is caught too).
function KS.CheckWrapWarning()
  local db = DB()
  if not db then return end
  local w, key = KS.WrapWarning()
  if not w then db.wrapWarned = nil return end
  if db.wrapWarned == key then return end
  db.wrapWarned = key
  KS.Print("|cffff8040%s|r", w)
end

-- Alt+Left-click (forward) or Alt+Right-click on an item in your bags (at bag, slot). The mark goes to that copy when
-- it's soulbound, has a mark of its own, or new marks are per copy (Copies.lua); otherwise to the item.
function KS.ClickMark(id, link, forward, bag, slot)
  local copy = bag and KS.CopyToMark and KS.CopyToMark(bag, slot)
  local cur = copy and KS.GetSlotLevel(bag, slot) or KS.GetLevel(id)
  local new = KS.ClickStep(cur, forward)
  if new == cur then return KS.Notify("%s is already %s.", link, KS.LevelText(cur)) end
  if copy then KS.SetCopyMark(copy, new) else KS.SetLevel(id, new, link) end
  if new == JUNK and cur >= LOCK and KS.SelfActing().vendor then
    KS.Print("|cffff8040That took it from %s to Junk: Standing Orders: Vendor sells it the next time you open a vendor.|r", KS.NAMES[cur])
  end
end

-- How Alt+Click works now, in a sentence or two (settings, the intro, /soc click).
function KS.ClickText(cfg)
  if KS.GetAltClick() == "menu" then return "Alt+Click an item in your bags to pick its mark from a menu." end
  cfg = cfg or KS.GetClick()
  local o, names = cfg.order, {}
  if KS.ClickPreset(cfg) == "dial" then
    for k, level in ipairs(o) do names[k] = KS.LevelText(level) end
    return "Alt+Left-click an item in your bags to protect it more (" .. table.concat(names, " > ")
      .. "), Alt+Right-click to protect it less."
  end
  local right = cfg.back and "Alt+Right-click goes back one step." or "Alt+Right-click takes its mark off."
  if not cfg.loop then
    for k, level in ipairs(o) do names[k] = KS.LevelText(level) end
    return "Alt+Left-click an item in your bags moves its mark along " .. table.concat(names, " > ") .. ", stopping at the end. " .. right
  end
  local start = 1
  for n, level in ipairs(o) do if level == NORMAL then start = n end end
  for k = 1, #o do
    local level = o[(start + k - 1) % #o + 1]
    names[k] = level == NORMAL and "no mark" or KS.LevelText(level)
  end
  return "Alt+Left-click an item in your bags: " .. table.concat(names, ", then ", 1, #o - 1) .. ", then " .. names[#o]
    .. " again. " .. right
end

-- At load: a new install starts on the Quick loop; an install from 1.0.0 (saved data, no sequence yet) keeps 1.0.0's
-- clicks (the Protection dial) and is offered the Quick loop once after login.
function KS.InitClick(db, fresh)
  if type(db.click) ~= "table" then
    db.click = Copy(PRESETS[fresh and "loop" or "dial"])
    if not fresh then db.clickOffer = true end
  end
  db.wrap = nil -- test builds' wrap-around switch, now the sequence's "loop"
  if db.altClick == nil then db.altClick = "cycle" end -- or "menu"
end

StaticPopupDialogs.SOC_CLICK_OFFER = {
  text = "|T" .. KS.ICON .. ":16:16|t Standing Orders: Custodian has a simpler Alt+Click now: Alt+Left-click an item "
    .. "goes Junk, then Locked, then Mail, then no mark again, and Alt+Right-click takes the mark off.\n\n"
    .. "Switch to it? Your marks stay as they are, and /soc settings can change it back.",
  button1 = "Switch",
  button2 = "Keep mine",
  OnAccept = function()
    KS.ApplyClickPreset("loop")
    KS.Print("Alt+Click now: %s", KS.ClickText())
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- The one-time offer to 1.0.0 players, after the intro if it's showing.
function KS.OfferQuickLoop()
  local db = DB()
  if not (db and db.clickOffer) then return end
  local intro = rawget(_G, "SOCustodianIntro")
  if intro and intro:IsShown() then
    if not KS.offerWaits then
      KS.offerWaits = true
      intro:HookScript("OnHide", function() C_Timer.After(1, KS.OfferQuickLoop) end)
    end
    return
  end
  db.clickOffer = nil
  StaticPopup_Show("SOC_CLICK_OFFER")
end

local WORDS = { junk = JUNK, disenchant = L.DISENCHANT, de = L.DISENCHANT, mail = MAIL, normal = NORMAL, none = NORMAL, lock = LOCK, locked = LOCK, onme = ONME, always = ONME }

-- /soc click [loop | dial | order <marks> | right clear|back | ends loop|stop]
function KS.ClickCommand(rest)
  local cmd, arg = (rest or ""):lower():match("^(%a*)%s*(.-)%s*$")
  local cfg, ok = KS.GetClick(), true
  if cmd == "loop" or cmd == "dial" then
    ok = KS.ApplyClickPreset(cmd)
  elseif cmd == "order" then
    local order = {}
    for word in arg:gmatch("%a+") do
      if not WORDS[word] then ok = false end
      order[#order + 1] = WORDS[word]
    end
    cfg.order = order
    ok = ok and #order > 0 and KS.SetClick(cfg)
  elseif cmd == "right" and (arg == "clear" or arg == "back") then
    cfg.back = arg == "back"
    ok = KS.SetClick(cfg)
  elseif cmd == "ends" and (arg == "loop" or arg == "stop") then
    cfg.loop = arg == "loop"
    ok = KS.SetClick(cfg)
  elseif cmd ~= "" then
    ok = false
  end
  if not ok then
    return KS.Print("|cffff4040Use /soc click loop, /soc click dial, /soc click order junk lock mail (marks: junk, mail, normal, lock, onme), /soc click right clear||back or /soc click ends loop||stop.|r")
  end
  KS.Print("Alt+Click (%s): %s", KS.CLICK_PRESET_NAMES[KS.ClickPreset()], KS.ClickText())
  local w = KS.WrapWarning()
  if w then KS.Print("|cffff8040%s|r", w) end
end

-- The sequence editor on the settings page (advanced options): one row per mark, the ones in the sequence first, in
-- order, then the ones left out. Each row: a box to put the mark in or take it out (Normal always stays in), its
-- icon and name, and Up and Down to move it. changed() runs after each change. Returns the editor's frame.
function KS.ClickEditor(parent, changed)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(330, #KS.ORDER * 24)
  box.rows = {}
  local function Move(level, by)
    local cfg = KS.GetClick()
    for i, l in ipairs(cfg.order) do
      if l == level and cfg.order[i + by] then
        cfg.order[i], cfg.order[i + by] = cfg.order[i + by], cfg.order[i]
        KS.SetClick(cfg)
        break
      end
    end
    changed()
  end
  local function Include(level, on)
    local cfg, at = KS.GetClick(), nil
    for i, l in ipairs(cfg.order) do if l == level then at = i end end
    if on and not at then cfg.order[#cfg.order + 1] = level
    elseif not on and at and level ~= NORMAL and #cfg.order > 2 then table.remove(cfg.order, at) end
    KS.SetClick(cfg)
    changed()
  end
  for i = 1, #KS.ORDER do
    local r = CreateFrame("Frame", nil, box)
    r:SetSize(330, 22)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(22, 22)
    r.check:SetPoint("LEFT")
    r.check:SetScript("OnClick", function(self) Include(r.level, self:GetChecked()) end)
    r.num = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    r.num:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.num:SetWidth(16)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", r.num, "RIGHT", 2, 0)
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.up = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.up:SetSize(54, 20)
    r.up:SetPoint("LEFT", 200, 0)
    r.up:SetText("Up")
    r.up:SetScript("OnClick", function() Move(r.level, -1) end)
    r.down = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.down:SetSize(54, 20)
    r.down:SetPoint("LEFT", r.up, "RIGHT", 4, 0)
    r.down:SetText("Down")
    r.down:SetScript("OnClick", function() Move(r.level, 1) end)
    box.rows[i] = r
  end
  function box.Refresh()
    local cfg, list, inSequence = KS.GetClick(), {}, {}
    for n, level in ipairs(cfg.order) do list[n] = level; inSequence[level] = n end
    for _, level in ipairs(KS.ORDER) do if not inSequence[level] then list[#list + 1] = level end end
    for i, r in ipairs(box.rows) do
      local level, pos = list[i], inSequence[list[i]]
      r.level = level
      r.check:SetChecked(pos ~= nil)
      r.check:SetEnabled(level ~= NORMAL)
      r.num:SetText(pos and (pos .. ".") or "")
      if KS.MarkTexture(r.icon, level) then r.icon:Show() else r.icon:Hide() end
      r.text:SetText(KS.LevelText(level) .. (level == NORMAL and " (no mark)" or ""))
      r.up:SetEnabled(pos ~= nil and pos > 1)
      r.down:SetEnabled(pos ~= nil and pos < #cfg.order)
    end
  end
  return box
end
