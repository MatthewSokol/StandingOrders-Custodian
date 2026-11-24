-- Custodian: chat logging levels (wow-mod-dev's standard, ui.md section 5). This limits logging, not chat output:
--   always in chat   warnings and errors (the red error when a guard blocks something), replies to typed commands
--   basic            Custodian's own routine lines (KS.Notify): auto-marks, buybacks, items moved back, the chat
--                    copy of a blocked action, and the replies to your Alt+Clicks ("... is now Junk.")
--   verbose          debugging detail (the old /soc debug lines)
-- Everything also goes to the log (/soc log) and Mechanic's console, whatever the level.
--
-- The default follows the build: basic in a dev build (the TOC version came from git describe, or is still the
-- unfilled packager token), off in a release. Only an explicit choice is saved (StandingOrdersCustodianDB.chatLog),
-- so the default can follow the build. 1.1.0's "Show Custodian's own messages in chat" (db.chat = true) carries
-- over as basic.

local ADDON = ...
local KS = StandingOrdersCustodian
local RANK = { off = 0, basic = 1, verbose = 2 }
KS.CHAT_LEVEL_NAMES = { off = "Off", basic = "Basic", verbose = "Verbose" }

-- A version string from a dev build: empty, "dev", the unfilled packager token, git describe (-g<hash>) or dirty.
-- Plain finds take the token literally: "@project%-version@" with plain = true would never match.
function KS.IsDevVersion(v)
  v = v or ""
  return v == "" or v == "dev" or v:find("@project-version@", 1, true) ~= nil or v:find("%-g%x+") ~= nil
    or v:find("dirty", 1, true) ~= nil
end

function KS.IsDevBuild()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return KS.IsDevVersion(get and get(ADDON, "Version"))
end

function KS.ChatLevel()
  local db = StandingOrdersCustodianDB
  local saved = db and db.chatLog
  if RANK[saved] then return saved end
  return KS.IsDevBuild() and "basic" or "off"
end

-- level: "off", "basic", "verbose", or nil to go back to the build's default.
function KS.SetChatLevel(level)
  local db = StandingOrdersCustodianDB
  if not db then return false end
  if level ~= nil and not RANK[level] then return false end
  db.chatLog = level
  return true
end

-- True when a line of this level ("basic" or "verbose") goes to chat.
function KS.ChatAllows(level) return RANK[KS.ChatLevel()] >= (RANK[level] or 1) end

-- The levels the settings dropdown offers: Verbose only on dev builds (or when it's already chosen).
function KS.ChatLevels()
  if KS.IsDevBuild() or KS.ChatLevel() == "verbose" then return { "off", "basic", "verbose" } end
  return { "off", "basic" }
end

-- 1.1.0's switch, kept for /soc chat on|off and the code that asks "are Custodian's messages in chat?".
function KS.GetChat() return KS.ChatAllows("basic") end
function KS.SetChat(on) return KS.SetChatLevel(on and "basic" or "off") end

-- Once at login: 1.1.0's db.chat = true becomes basic and db.debug = true verbose; the old false values (the
-- defaults then) are dropped.
function KS.MigrateChat(db)
  if db.debug == true and db.chatLog == nil then db.chatLog = "verbose" end -- the old /soc debug switch
  if db.chat == true and db.chatLog == nil then db.chatLog = "basic" end
  db.chat = nil
  db.debug = nil
end
