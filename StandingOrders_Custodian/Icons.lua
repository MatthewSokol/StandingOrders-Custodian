-- Custodian: mark icon styles, picked in /soc settings (advanced options) or with /soc icon style:
--   game     the game's own art (a coin, a letter, a key, a purple diamond), as in 1.0.0; the default for now
--   trimmed  the same art, with the item icons' painted borders cropped off and a thin dark edge instead
--   badges   Custodian's own badges (Media\*.tga, drawn by tools/badges.js): a colored circle with a white glyph
-- /soc icon compare opens a window with each mark in each style over items from your own bags.
-- A field-only file: Custodian.lua's main chunk is at Lua's 200-local limit.

local ADDON = ...
local KS = StandingOrdersCustodian
local L = KS.LEVELS
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local BADGES = { [L.JUNK] = "Junk", [L.MAIL] = "Mail", [L.LOCK] = "Locked", [L.ONME] = "OnMe" }

KS.ICON_STYLES = { "game", "trimmed", "badges" }
KS.ICON_STYLE_NAMES = { game = "Game icons", trimmed = "Trimmed game icons", badges = "Badges" }

function KS.GetIconStyleName()
  local db = StandingOrdersCustodianDB
  local style = db and db.icon and db.icon.style
  return KS.ICON_STYLE_NAMES[style] and style or "game"
end

-- Item icons (Interface\Icons\...) have a painted border; the coin and the raid marker don't.
local function IsItemIcon(path) return type(path) == "string" and path:sub(1, 16):lower() == "interface\\icons\\" end

-- Puts level's mark on a texture in a style (default: the one in use). False when the level has no mark icon.
function KS.MarkTexture(tex, level, style)
  local path = KS.ICONS[level]
  if not path then return false end
  style = style or KS.GetIconStyleName()
  if style == "badges" and BADGES[level] then
    tex:SetTexture(MEDIA .. BADGES[level], nil, nil, "TRILINEAR")
    tex:SetTexCoord(0, 1, 0, 1)
  else
    tex:SetTexture(path)
    if style == "trimmed" and IsItemIcon(path) then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
  end
  return true
end

-- The thin dark edge around a trimmed item icon, on the frame that holds the mark (owner), behind the mark. Kept
-- here by owner, not on the frame, so other addons' frames get no new fields.
local edges = setmetatable({}, { __mode = "k" })
function KS.MarkEdge(owner, tex, level, style)
  style = style or KS.GetIconStyleName()
  local edge = edges[owner]
  if not (style == "trimmed" and IsItemIcon(KS.ICONS[level]) and tex:IsShown()) then
    if edge then edge:Hide() end
    return
  end
  if not edge then
    edge = owner:CreateTexture(nil, "OVERLAY", nil, 6)
    edge:SetColorTexture(0, 0, 0, 1)
    edges[owner] = edge
  end
  edge:ClearAllPoints()
  edge:SetPoint("TOPLEFT", tex, "TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 1, -1)
  edge:SetAlpha(tex:GetAlpha() or 1)
  edge:Show()
end

-- The mark as a chat or font-string icon (the intro), in the style in use.
function KS.IconTag(level, size)
  local path, style = KS.ICONS[level], KS.GetIconStyleName()
  if not path then return "" end
  size = size or 16
  if style == "badges" and BADGES[level] then path = MEDIA .. BADGES[level]
  elseif style == "trimmed" and IsItemIcon(path) then
    return "|T" .. path .. ":" .. size .. ":" .. size .. ":0:0:64:64:5:59:5:59|t"
  end
  return "|T" .. path .. ":" .. size .. ":" .. size .. "|t"
end

---------------------------------------------------------------------------------------------------
-- The compare window (/soc icon compare): one row per mark, one column per style, each over an item from your
-- bags (one with that mark when you have one), at your icon size, position and opacity. Use picks a style.

local SHOWN = { L.JUNK, L.MAIL, L.LOCK, L.ONME }
local win

-- Item icons from your bags: the first one with each mark, and up to eight of any kind.
local function BagIcons()
  local byLevel, any, C = {}, {}, C_Container
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
      local info = C.GetContainerItemInfo(bag, slot)
      if info and info.iconFileID then
        local level = KS.GetLevel(info.itemID)
        byLevel[level] = byLevel[level] or info.iconFileID
        if #any < 8 then any[#any + 1] = info.iconFileID end
      end
    end
  end
  return byLevel, any
end

local function Build()
  win = CreateFrame("Frame", "SOCustodianIconCompare", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(430, 120 + #SHOWN * 44)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetClampedToScreen(true)
  win:EnableMouse(true)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("Mark icon styles")
  local note = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 16, -32)
  note:SetWidth(398)
  note:SetJustifyH("LEFT")
  note:SetText("Items from your bags under each mark, at your icon size, position and opacity. Use puts a style on your bags.")
  win.cells, win.heads, win.use = {}, {}, {}
  for r, level in ipairs(SHOWN) do
    local label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 16, -96 - (r - 1) * 44)
    label:SetText(KS.LevelText(level))
  end
  for c, style in ipairs(KS.ICON_STYLES) do
    local x = 130 + (c - 1) * 100
    win.heads[c] = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.heads[c]:SetPoint("TOP", win, "TOPLEFT", x + 18, -62)
    for r, level in ipairs(SHOWN) do
      local cell = CreateFrame("Frame", nil, win)
      cell:SetSize(37, 37)
      cell:SetPoint("TOPLEFT", x, -84 - (r - 1) * 44)
      cell.item = cell:CreateTexture(nil, "ARTWORK")
      cell.item:SetAllPoints()
      cell.mark = cell:CreateTexture(nil, "OVERLAY", nil, 7)
      cell.level, cell.style = level, style
      win.cells[#win.cells + 1] = cell
    end
    local use = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    use:SetSize(84, 22)
    use:SetPoint("TOP", win, "TOPLEFT", x + 18, -88 - #SHOWN * 44)
    use:SetScript("OnClick", function()
      KS.SetIconStyle("style", style)
      KS.ShowIconCompare()
      if KS.RefreshSettings then KS.RefreshSettings() end
    end)
    win.use[c] = use
  end
  tinsert(UISpecialFrames, "SOCustodianIconCompare") -- Esc closes it
end

function KS.ShowIconCompare()
  if not win then Build() end
  local byLevel, any = BagIcons()
  local current = KS.GetIconStyleName()
  for c, style in ipairs(KS.ICON_STYLES) do
    local name = KS.ICON_STYLE_NAMES[style]
    win.heads[c]:SetText(style == current and ("|cff33ff99" .. name .. "|r") or name) -- pipes:ok (a color code)
    win.use[c]:SetText(style == current and "In use" or "Use")
    win.use[c]:SetEnabled(style ~= current)
  end
  for i, cell in ipairs(win.cells) do
    cell.item:SetTexture(byLevel[cell.level] or any[(i - 1) % math.max(1, #any) + 1] or "Interface\\Icons\\INV_Misc_Bag_08")
    KS.StyleIcon(cell.mark, cell)
    KS.MarkTexture(cell.mark, cell.level, cell.style)
    cell.mark:Show()
    KS.MarkEdge(cell, cell.mark, cell.level, cell.style)
  end
  win:Show()
end
