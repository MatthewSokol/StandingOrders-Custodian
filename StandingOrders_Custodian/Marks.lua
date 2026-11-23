-- Custodian: more ways to change a mark besides Alt+Click cycling and the /soc commands, so there's always one
-- that works: the mark menu (pick the level from a list; Alt+Click opens it when /soc altclick menu is set, and
-- /soc mark <item> opens it for any item) and the Marked items window (/soc list: search, then change any mark).

local KS = StandingOrdersCustodian
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local function ItemLink(id) return select(2, GetItemInfo(id)) or ("item:" .. id) end

-- A dark panel with a tooltip border where the client has backdrops.
local function Panel(name, width)
  local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetWidth(width)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
  if f.SetBackdrop then
    f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  end
  return f
end

---------------------------------------------------------------------------------------------------
-- The mark menu: the item, one button per level (its own mark ticked), and "This character only".

local menu

local function BuildMenu()
  menu = Panel("SOCustodianMarkMenu", 214)
  menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  menu.title:SetPoint("TOPLEFT", 10, -10)
  menu.title:SetWidth(172)
  menu.title:SetJustifyH("LEFT")
  local close = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  menu.buttons = {}
  local y = -32
  for i, level in ipairs(KS.ORDER) do
    local b = CreateFrame("Button", nil, menu)
    b:SetSize(194, 20)
    b:SetPoint("TOPLEFT", 10, y)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 2, 0)
    if KS.ICONS[level] then b.icon:SetTexture(KS.ICONS[level]) end
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT", 24, 0)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetSize(16, 16)
    b.check:SetPoint("RIGHT", -2, 0)
    b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.level = level
    b:SetScript("OnClick", function() KS.PickMark(level) end)
    menu.buttons[i] = b
    y = y - 22
  end
  menu.char = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
  menu.char:SetSize(24, 24)
  menu.char:SetPoint("TOPLEFT", 8, y - 2)
  menu.char.Text:SetText("This character only")
  menu:SetHeight(-y + 34)
  tinsert(UISpecialFrames, "SOCustodianMarkMenu") -- Esc closes it
end

-- Gives the menu's item the picked level, for this character or all of them, and closes the menu.
function KS.PickMark(level)
  if not (menu and menu.itemID) then return end
  KS.SetLevel(menu.itemID, level, menu.link, { scope = menu.char:GetChecked() and "char" or "account" })
  menu:Hide()
end

-- Opens the menu for an item: under anchor (a frame) when given, else at the mouse.
function KS.ShowMarkMenu(id, link, anchor)
  if not id then return end
  if not menu then BuildMenu() end
  menu.itemID, menu.link = id, link or ItemLink(id)
  menu.title:SetText(menu.link)
  local own = KS.GetOwnLevel(id)
  -- Only the marks in use (Always on me with the advanced options, in the Alt+Click sequence, or as this item's mark).
  local shown, y = {}, -32
  for _, level in ipairs(KS.ShownLevels(own)) do shown[level] = true end
  for _, b in ipairs(menu.buttons) do
    b.text:SetText(KS.LevelText(b.level))
    KS.MarkTexture(b.icon, b.level) -- in the icon style in use (Icons.lua)
    b.check[b.level == own and "Show" or "Hide"](b.check)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 10, y)
    b[shown[b.level] and "Show" or "Hide"](b)
    if shown[b.level] then y = y - 22 end
  end
  menu.char:ClearAllPoints()
  menu.char:SetPoint("TOPLEFT", 8, y - 2)
  menu:SetHeight(-y + 34)
  local scope = KS.GetItemScope(id)
  menu.char:SetChecked(scope == "char" or (not scope and (KS.IsPersonal(id) or KS.GetScope() == "char")))
  menu:ClearAllPoints()
  local x, y = GetCursorPosition and GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if anchor then
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  elseif x and y and scale then
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 8, y / scale + 8)
  else
    menu:SetPoint("CENTER")
  end
  menu:Show()
end

---------------------------------------------------------------------------------------------------
-- The Marked items window (/soc list): every item with a mark of its own, plus (ticked by default) the unmarked
-- items in your bags, so new items can be marked here too. The search box narrows the list as you type, by item
-- name or by mark ("locked", "junk"...). Each row's button opens the mark menu under it.

local ROW_H, ROW_W = 22, 356
local win

local function NameOf(id)
  local name = GetItemInfo(id)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  return name
end

-- The rows to show: { id, level, scope, name }, most protected first, then by name.
local function Entries(text, withBags)
  local list, seen = {}, {}
  for _, e in ipairs(KS.MarkedItems()) do
    list[#list + 1] = e
    seen[e.id] = true
  end
  if withBags then
    for bag = 0, NUM_BAG_SLOTS or 4 do
      for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local id = info and info.itemID
        if id and not seen[id] then
          seen[id] = true
          list[#list + 1] = { id = id, level = KS.GetOwnLevel(id) }
        end
      end
    end
  end
  local out = {}
  text = (text or ""):lower()
  for _, e in ipairs(list) do
    e.name = NameOf(e.id) or ("item " .. e.id)
    if text == "" or e.name:lower():find(text, 1, true) or (KS.NAMES[e.level] or ""):lower():find(text, 1, true) then
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return a.name < b.name
  end)
  return out
end

local function Row(i)
  if win.rows[i] then return win.rows[i] end
  local r = CreateFrame("Button", nil, win.content)
  r:SetSize(ROW_W, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetPoint("LEFT", 2, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.name:SetPoint("LEFT", 26, 0)
  r.name:SetWidth(196)
  r.name:SetJustifyH("LEFT")
  r.mark = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.mark:SetSize(126, 20)
  r.mark:SetPoint("RIGHT", -2, 0)
  r.mark:SetScript("OnClick", function(self) KS.ShowMarkMenu(r.id, r.link, self) end)
  r:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. self.id)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  win.rows[i] = r
  return r
end

local function Refresh()
  if not (win and win:IsShown()) then return end
  local text = win.search:GetText() or ""
  if text == "" then win.hint:Show() else win.hint:Hide() end
  local list = Entries(text, win.bags:GetChecked())
  win.entries = list
  local marked = 0
  for i, e in ipairs(list) do
    local r = Row(i)
    r.id, r.link = e.id, ItemLink(e.id)
    r.icon:SetTexture((GetInstant and select(5, GetInstant(e.id))) or 134400)
    local shown = GetItemInfo(e.id) and r.link or e.name
    r.name:SetText(shown .. (e.scope == "char" and " |cff9d9d9d(this character)|r" or ""))
    r.mark:SetText(KS.LevelText(e.level))
    r:Show()
    if e.scope then marked = marked + 1 end
  end
  for i = #list + 1, #win.rows do win.rows[i]:Hide() end
  win.content:SetHeight(math.max(1, #list * ROW_H))
  if #list == 0 then
    win.count:SetText(text ~= "" and "Nothing matches." or "Nothing marked yet: Alt+Click an item in your bags, or tick Items in my bags.")
  else
    win.count:SetText(("%d shown, %d with a mark. Click a mark to change it."):format(#list, marked))
  end
end
KS.RefreshMarkList = Refresh

local function BuildWindow()
  win = CreateFrame("Frame", "SOCustodianMarks", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(410, 470)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetClampedToScreen(true)
  win:EnableMouse(true)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 8, -5)
  title:SetText("Standing Orders: Custodian - Marked items")
  local icon = win:CreateTexture(nil, "OVERLAY")
  icon:SetSize(16, 16)
  icon:SetPoint("RIGHT", title, "LEFT", -4, 0)
  icon:SetTexture(KS.ICON)

  win.search = CreateFrame("EditBox", "SOCustodianMarksSearch", win, "InputBoxTemplate")
  win.search:SetSize(200, 20)
  win.search:SetPoint("TOPLEFT", 24, -34)
  win.search:SetAutoFocus(false)
  win.search:SetScript("OnTextChanged", function() Refresh() end)
  win.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  win.hint = win.search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  win.hint:SetPoint("LEFT", 2, 0)
  win.hint:SetText("Search: item or mark")
  win.bags = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
  win.bags:SetSize(24, 24)
  win.bags:SetPoint("LEFT", win.search, "RIGHT", 10, 0)
  win.bags.Text:SetText("Items in my bags")
  win.bags:SetChecked(true)
  win.bags:SetScript("OnClick", function() Refresh() end)

  local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -62)
  scroll:SetPoint("BOTTOMRIGHT", -34, 34)
  win.content = CreateFrame("Frame", nil, scroll)
  win.content:SetSize(ROW_W, 1)
  scroll:SetScrollChild(win.content)
  win.count = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.count:SetPoint("BOTTOMLEFT", 18, 14)
  win.rows = {}
  win:SetScript("OnShow", Refresh)
  tinsert(UISpecialFrames, "SOCustodianMarks") -- Esc closes it

  -- Stay current while open: marks changed anywhere, and item names the client loads later.
  hooksecurefunc(KS, "SetLevel", Refresh)
  hooksecurefunc(KS, "ToggleItemScope", Refresh)
  local names = CreateFrame("Frame")
  pcall(names.RegisterEvent, names, "GET_ITEM_INFO_RECEIVED")
  names:SetScript("OnEvent", function()
    if not win:IsShown() or win.pending then return end
    win.pending = true
    C_Timer.After(0.3, function() win.pending = nil; Refresh() end)
  end)
end

-- Opens the Marked items window, with the search box set to text when given.
function KS.ShowMarkList(text)
  if not win then BuildWindow() end
  win:Show()
  if text then win.search:SetText(text) end
  Refresh()
end
