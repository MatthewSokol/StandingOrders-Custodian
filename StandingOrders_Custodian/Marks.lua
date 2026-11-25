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

-- The mark the menu ticks: the copy's own with "This copy only" (Copies.lua), else the item's.
local function MenuOwn()
  if menu.copyRef and menu.copy:GetChecked() then return KS.CopyOwnLevel(menu.copyRef) end
  return KS.GetOwnLevel(menu.itemID)
end
local function Tick()
  local own = MenuOwn()
  for _, b in ipairs(menu.buttons) do b.check[b.level == own and "Show" or "Hide"](b.check) end
end

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
  -- Opened from a bag slot: "This copy only" (Copies.lua). The two boxes take turns.
  menu.copy = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
  menu.copy:SetSize(24, 24)
  menu.copy.Text:SetText("This copy only")
  menu.char:SetScript("OnClick", function(self) if self:GetChecked() then menu.copy:SetChecked(false) end Tick() end)
  menu.copy:SetScript("OnClick", function(self) if self:GetChecked() then menu.char:SetChecked(false) end Tick() end)
  menu:SetHeight(-y + 34)
  tinsert(UISpecialFrames, "SOCustodianMarkMenu") -- Esc closes it
end

-- Gives the menu's item the picked level, for this character or all of them, and closes the menu. Picking the
-- ticked mark again takes it off (Normal), like unticking a box.
function KS.PickMark(level)
  if not (menu and menu.itemID) then return end
  if level == MenuOwn() then level = KS.LEVELS.NORMAL end
  if menu.copyRef and menu.copy:GetChecked() then
    KS.SetCopyMark(menu.copyRef, level)
  else
    KS.SetLevel(menu.itemID, level, menu.link, { scope = menu.char:GetChecked() and "char" or "account" })
  end
  menu:Hide()
end

-- Opens the menu for an item: next to beside (the bag button, like a context menu), under anchor
-- (a Marked items row), else at the mouse. It always stays on the screen.
function KS.ShowMarkMenu(id, link, anchor, beside)
  if not id then return end
  if not menu then BuildMenu() end
  menu.itemID, menu.link = id, link or ItemLink(id)
  menu.title:SetText(menu.link)
  local bag, slot
  if beside and KS.ButtonSlot then bag, slot = KS.ButtonSlot(beside) end
  local copy = bag and slot and KS.CopyAt and KS.CopyAt(bag, slot)
  if copy and copy.id ~= id then copy = nil end
  menu.copyRef = copy
  local perCopy = copy and (copy.soulbound or KS.CopyMark(copy.guid) or KS.GetScope() == "copy")
  local own = perCopy and KS.CopyOwnLevel(copy) or KS.GetOwnLevel(id)
  -- Only the marks in use (Always on me with the advanced options, in the Alt+Click sequence, or as this item's mark).
  local shown, y = {}, -32
  for _, level in ipairs(KS.ShownLevels(own)) do shown[level] = true end
  for _, b in ipairs(menu.buttons) do
    b.text:SetText(KS.LevelText(b.level))
    KS.MarkTexture(b.icon, b.level) -- in the icon style in use (Icons.lua)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 10, y)
    b[shown[b.level] and "Show" or "Hide"](b)
    if shown[b.level] then y = y - 22 end
  end
  menu.char:ClearAllPoints()
  menu.copy:ClearAllPoints()
  local height = -y + 34
  if copy and copy.soulbound then -- soulbound: per copy, always
    menu.char:Hide()
    menu.copy:SetPoint("TOPLEFT", 8, y - 2)
    menu.copy.Text:SetText("This copy only (soulbound)")
    menu.copy:Disable()
  else
    menu.char:SetPoint("TOPLEFT", 8, y - 2)
    menu.char:Show()
    menu.copy:SetPoint("TOPLEFT", 8, y - 26)
    menu.copy.Text:SetText("This copy only")
    menu.copy:Enable()
    if copy then height = height + 24 end
  end
  menu.copy[copy and "Show" or "Hide"](menu.copy)
  menu.copy:SetChecked(perCopy and true or false)
  local scope = KS.GetItemScope(id)
  menu.char:SetChecked(not perCopy and (scope == "char" or (not scope and (KS.IsPersonal(id) or KS.GetScope() == "char"))))
  menu:SetHeight(height)
  Tick()
  menu:ClearAllPoints()
  local x, y = GetCursorPosition and GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if menu.SetClampedToScreen then menu:SetClampedToScreen(true) end
  if beside then
    menu:SetPoint("TOPLEFT", beside, "TOPRIGHT", 4, 0)
  elseif anchor then
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
-- items in your bags, so new items can be marked here too. Three columns: This character (a dropdown; "Account
-- default" means no mark of its own), All characters (a dropdown) and Mark, the one that counts (this character's
-- wins; an equipment set can raise it). The search box narrows the list as you type, by item name or by mark.

local ROW_H, ROW_W = 26, 520
local COL_NAME, COL_DD, COL_MARK = 186, 124, 80
local DEFAULT = 0 -- "Account default" in the This character column: no mark of its own
local NONE = {} -- a row before it has an item: the menu system can build its menu as soon as the dropdown exists
local win

local function NameOf(id)
  local name = GetItemInfo(id)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  return name
end

local function Matches(text, e)
  if text == "" or e.name:lower():find(text, 1, true) then return true end
  for _, l in ipairs({ e.level, e.char or -1, e.account or -1 }) do
    if (KS.NAMES[l] or ""):lower():find(text, 1, true) then return true end
  end
  return false
end

local order, orderN -- itemID -> its row's place, kept while the window is open (nil: sort again)
local function ByMark(a, b)
  if a.level ~= b.level then return a.level > b.level end
  return a.name < b.name
end

-- The rows to show: { id, name, char, account, level (the one that counts), set (true when a set raises it),
-- scope }, in the window's order.
local function Entries(text, withBags)
  local list, seen = {}, {}
  for _, e in ipairs(KS.MarkedItems()) do
    list[#list + 1] = { id = e.id }
    seen[e.id] = true
  end
  if withBags then
    for bag = 0, NUM_BAG_SLOTS or 4 do
      for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local id = info and info.itemID
        if id and not seen[id] then
          seen[id] = true
          list[#list + 1] = { id = id }
        end
      end
    end
  end
  -- A row whose mark you just took off (Account default and Normal) stays until Re-sort or the next opening, so
  -- the list doesn't jump under the mouse.
  if order then
    for id in pairs(order) do
      if not seen[id] then
        seen[id] = true
        list[#list + 1] = { id = id }
      end
    end
  end
  local out = {}
  text = (text or ""):lower()
  for _, e in ipairs(list) do
    e.name = NameOf(e.id) or ("item " .. e.id)
    e.char, e.account = KS.GetMarkIn(e.id, "char"), KS.GetMarkIn(e.id, "account")
    e.scope = KS.GetItemScope(e.id)
    e.level = KS.GetLevel(e.id)
    e.set = e.level > KS.GetOwnLevel(e.id)
  end
  -- Most protected first, then by name, when the window opens (or on Re-sort); after that each row keeps its
  -- place, so changing a mark doesn't move it. Items new since then go at the end.
  if not order then
    table.sort(list, ByMark)
    order, orderN = {}, #list
    for i, e in ipairs(list) do order[e.id] = i end
  end
  for _, e in ipairs(list) do
    if not order[e.id] then orderN = orderN + 1; order[e.id] = orderN end
    if Matches(text, e) then out[#out + 1] = e end
  end
  table.sort(out, function(a, b) return order[a.id] < order[b.id] end)
  return out
end

-- A column's dropdown (a cycling button on clients without the menu system): get() is the row's choice,
-- choices() what to offer, set(c) picks it.
local function Column(parent, get, choices, label, set)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(COL_DD)
    dd:SetupMenu(function(_, root)
      for _, c in ipairs(choices()) do
        root:CreateRadio(label(c), function() return get() == c end, function() set(c) end)
      end
    end)
    dd.isDropdown = true
    dd.Update = function() dd:GenerateMenu() end
    return dd
  end
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(COL_DD, 22)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(_, mouse)
    local list, cur, n = choices(), get(), 1
    for k, c in ipairs(list) do if c == cur then n = k end end
    set(list[(n + (mouse == "RightButton" and -2 or 0)) % #list + 1])
  end)
  btn.Update = function() btn:SetText(label(get())) end
  return btn
end

local function LevelChoices(own)
  return KS.ShownLevels(own) -- Always on me only when it's in use (Simple.lua)
end

local function Row(i)
  if win.rows[i] then return win.rows[i] end
  local r = CreateFrame("Button", nil, win.content)
  r.entry = NONE
  r:SetSize(ROW_W, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetPoint("LEFT", 2, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.name:SetPoint("LEFT", 24, 0)
  r.name:SetWidth(COL_NAME - 26)
  r.name:SetJustifyH("LEFT")
  r.char = Column(r, function() return (r.entry or NONE).char or DEFAULT end,
    function()
      local list = { DEFAULT }
      for _, l in ipairs(LevelChoices((r.entry or NONE).char)) do list[#list + 1] = l end
      return list
    end,
    function(c) return c == DEFAULT and "|cff9d9d9dAccount default|r" or KS.LevelText(c) end,
    function(c) KS.SetMarkIn(r.id, "char", c ~= DEFAULT and c or nil) end)
  r.char:SetPoint("LEFT", COL_NAME, 0)
  r.account = Column(r, function() return (r.entry or NONE).account or KS.LEVELS.NORMAL end,
    function() return LevelChoices((r.entry or NONE).account) end,
    KS.LevelText,
    function(c) KS.SetMarkIn(r.id, "account", c) end)
  r.account:SetPoint("LEFT", COL_NAME + COL_DD + 8, 0)
  r.mark = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.mark:SetPoint("LEFT", COL_NAME + 2 * (COL_DD + 8), 0)
  r.mark:SetWidth(COL_MARK)
  r.mark:SetJustifyH("LEFT")
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
    r.id, r.link, r.entry = e.id, ItemLink(e.id), e
    r.icon:SetTexture((GetInstant and select(5, GetInstant(e.id))) or 134400)
    r.name:SetText(GetItemInfo(e.id) and r.link or e.name)
    r.char.Update()
    r.account.Update()
    r.mark:SetText(KS.LevelText(e.level) .. (e.set and " |cff9d9d9d(set)|r" or ""))
    r:Show()
    if e.scope then marked = marked + 1 end
  end
  for i = #list + 1, #win.rows do win.rows[i]:Hide() end
  win.content:SetHeight(math.max(1, #list * ROW_H))
  if #list == 0 then
    win.count:SetText(text ~= "" and "Nothing matches." or "Nothing marked yet: Alt+Click an item in your bags, or tick Items in my bags.")
  else
    win.count:SetText(("%d shown, %d with a mark. This character's mark wins over All characters."):format(#list, marked))
  end
end
KS.RefreshMarkList = Refresh

local function ColumnHeader(text, x)
  local fs = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 14 + x, -64)
  fs:SetText(text)
  return fs
end

local function BuildWindow()
  win = CreateFrame("Frame", "SOCustodianMarks", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(ROW_W + 50, 480)
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
  -- Drop an item on the search box (drag it there, or click the box while holding it): search for that item. The
  -- item goes back where it was.
  local function TakeCursorItem()
    local kind, id, link = GetCursorInfo()
    if kind ~= "item" then return end
    ClearCursor()
    KS.SearchMarkList(link or id)
  end
  win.search:SetScript("OnReceiveDrag", TakeCursorItem)
  win.search:HookScript("OnMouseDown", TakeCursorItem)
  win.hint = win.search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  win.hint:SetPoint("LEFT", 2, 0)
  win.hint:SetText("Search: item or mark")
  win.bags = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
  win.bags:SetSize(24, 24)
  win.bags:SetPoint("LEFT", win.search, "RIGHT", 10, 0)
  win.bags.Text:SetText("Items in my bags")
  win.bags:SetChecked(true)
  win.bags:SetScript("OnClick", function() order = nil; Refresh() end) -- a new set of rows: sort afresh

  ColumnHeader("Item", 4)
  ColumnHeader("This character", COL_NAME)
  ColumnHeader("All characters", COL_NAME + COL_DD + 8)
  ColumnHeader("Mark", COL_NAME + 2 * (COL_DD + 8))

  local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -80)
  scroll:SetPoint("BOTTOMRIGHT", -34, 34)
  win.content = CreateFrame("Frame", nil, scroll)
  win.content:SetSize(ROW_W, 1)
  scroll:SetScrollChild(win.content)
  win.count = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.count:SetPoint("BOTTOMLEFT", 18, 14)
  win.resort = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  win.resort:SetSize(80, 22)
  win.resort:SetPoint("BOTTOMRIGHT", -14, 8)
  win.resort:SetText("Re-sort")
  win.resort:SetScript("OnClick", function() KS.ResortMarkList() end)
  win.rows = {}
  win:SetScript("OnShow", function() order = nil; Refresh() end) -- sorted afresh each time it opens
  tinsert(UISpecialFrames, "SOCustodianMarks") -- Esc closes it

  -- Stay current while open: marks changed anywhere, and item names the client loads later.
  hooksecurefunc(KS, "SetLevel", Refresh)
  hooksecurefunc(KS, "SetMarkIn", Refresh)
  hooksecurefunc(KS, "ToggleItemScope", Refresh)
  hooksecurefunc(KS, "SetCopyMark", Refresh)
  local names = CreateFrame("Frame")
  pcall(names.RegisterEvent, names, "GET_ITEM_INFO_RECEIVED")
  names:SetScript("OnEvent", function()
    if not win:IsShown() or win.pending then return end
    win.pending = true
    C_Timer.After(0.3, function() win.pending = nil; Refresh() end)
  end)
end

-- Searches the Marked items window for an item (a link or an item ID), as a shift-click or a drag does.
function KS.SearchMarkList(item)
  if not item then return end
  local name = GetItemInfo(item) or (type(item) == "string" and item:match("%[(.-)%]"))
  if not name then return end
  if not (win and win:IsShown()) then KS.ShowMarkList() end
  win.search:SetText(name)
  Refresh()
end

-- True while a shift-click should search the window: it's open, and you aren't typing in a chat box (or the
-- search box has focus). Bag clicks come here from Custodian's bag-button hook (Custodian.lua's PreClick), since
-- the game's own shift-click (split the stack, or link it in chat) doesn't reliably pass through a hook here.
function KS.MarkListTakesShiftClick()
  if not (win and win:IsShown()) then return false end
  local chat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  return (win.search:HasFocus() or not chat) and true or false
end

-- Other shift-clicks (chat links, a vendor, the auction house) reach the game's link insert: a hook, so chat
-- links work as before.
if ChatEdit_InsertLink then
  hooksecurefunc("ChatEdit_InsertLink", function(link)
    if type(link) == "string" and link:find("item:", 1, true) and KS.MarkListTakesShiftClick() then
      KS.SearchMarkList(link)
    end
  end)
end

-- Re-sort: most protected first again, then by name.
function KS.ResortMarkList()
  order = nil
  Refresh()
end

-- Opens the Marked items window, with the search box set to text when given.
function KS.ShowMarkList(text)
  if not win then BuildWindow() end
  win:Show()
  if text then win.search:SetText(text) end
  Refresh()
end
