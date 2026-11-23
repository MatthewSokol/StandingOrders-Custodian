-- Custodian: more ways to change a mark besides Alt+Click cycling and the /soc commands, so there's always one
-- that works: the mark menu (pick the level from a list; Alt+Click opens it when /soc altclick menu is set, and
-- /soc mark <item> opens it for any item).

local KS = StandingOrdersCustodian
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

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
  for _, b in ipairs(menu.buttons) do
    b.text:SetText(KS.LevelText(b.level))
    b.check[b.level == own and "Show" or "Hide"](b.check)
  end
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
