-- Lint settings for luacheck (Mechanic's addon.lint step). WoW runs Lua 5.1.
std = "lua51"
max_line_length = false
exclude_files = { "tools/", "dist/" }
ignore = {
  "212", -- unused argument (event handlers and hooks take fixed signatures)
  "213", -- unused loop variable
}

-- Globals Custodian writes
globals = { "StandingOrdersCustodian", "StandingOrdersCustodianDB", "StandingOrdersCustodianCharDB", "SLASH_SOC1", "SlashCmdList" }

-- WoW API and UI globals Custodian reads (all optional ones are checked before use)
read_globals = {
  "ATTACHMENTS_MAX_RECEIVE", "ATTACHMENTS_MAX_SEND", "AutoLootMailItem", "BANK_CONTAINER", "BugGrabber",
  "BuyMerchantItem", "BuybackItem", "C_AddOns", "C_AuctionHouse", "C_Bank", "C_Container", "C_Item", "C_Spell",
  "C_SpellBook", "C_Timer", "C_TradeSkillUI", "CastSpell", "CastSpellByID", "ClearCursor",
  "ClickSendMailItemButton", "ClickTradeButton", "ContainerFrameCombinedBags", "CreateFrame", "DEFAULT_CHAT_FRAME",
  "DoCraft", "DoTradeSkill", "Enum", "GameTooltip", "GameTooltip_Hide", "GetActionInfo", "GetAddOnMetadata",
  "GetBuybackItemLink", "GetCraftDisplaySkillLine", "GetCraftInfo", "GetCraftName", "GetCraftNumReagents",
  "GetCraftReagentItemLink", "GetCursorInfo", "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItemLink",
  "GetItemInfo", "GetItemInfoInstant", "GetMacroSpell", "GetMerchantItemLink", "GetMerchantNumItems",
  "GetNumBuybackItems", "GetNumCrafts", "GetNumSkillLines", "GetNumTradeSkills", "GetProfessionInfo",
  "GetProfessions", "GetSendMailItemLink", "GetSkillLineInfo", "GetSpellBookItemInfo", "GetSpellInfo", "GetTime",
  "GetTradePlayerItemLink", "GetTradeSkillInfo", "GetTradeSkillLine", "GetTradeSkillNumReagents",
  "GetTradeSkillReagentItemLink", "GetTradeTargetItemLink", "InterfaceOptionsFrame_OpenToCategory",
  "InterfaceOptions_AddCategory", "IsAltKeyDown", "IsControlKeyDown", "IsCurrentSpell", "IsShiftKeyDown",
  "IsTradeSkillLinked", "LibStub", "MAX_TRADABLE_ITEMS", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS",
  "NUM_CONTAINER_FRAMES", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "PutItemInBackpack", "PutItemInBag", "Settings",
  "SpellIsTargeting", "SpellStopTargeting", "StaticPopup_Hide", "StaticPopup_Show", "TakeInboxItem",
  "TooltipDataProcessor", "UIErrorsFrame", "UIParent", "UISpecialFrames", "UseAction", "UseItemByName",
  "VendorFlip", "date", "debugprofilestop", "hooksecurefunc", "tinsert",
  "_G",
}
