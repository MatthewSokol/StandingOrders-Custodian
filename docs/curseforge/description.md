# Standing Orders: Custodian

**Item lock** for World of Warcraft **Forever** (interface 16001): lock the items you care about, and Standing Orders stops you losing them by accident: selling, disenchanting, destroying, trading or mailing them. It also marks junk to sell and materials to send to your bank alt.

Part of **Standing Orders**, a set of addons that deal with the items you've already decided about, so the interesting ones stand out. Each works on its own:

| Addon | Command | Does |
|---|---|---|
| **Standing Orders: Custodian** (this one) | `/soc` | Marks items Junk, Mail, Locked or Always on me, and guards the protected ones |
| [Standing Orders: Vendor](https://www.curseforge.com/wow/addons/standing-orders-vendor) (**coming soon**) | `/sov` | Sells your junk at any vendor in one click, skipping what Custodian protects |
| [Standing Orders: Mail](https://www.curseforge.com/wow/addons/standing-orders-mail) (**coming soon**) | `/som` | Mails items marked Mail to your bank alt in one click |

Custodian's marks and guards work today on their own; Junk and Mail marks are what Vendor and Mail will act on when they're out.

Other addons use its API through the `StandingOrdersCustodian` global (see below); its folder is `StandingOrders_Custodian`.

## Item levels

Levels are per item ID. A mark applies to all your characters, or to one character only:

- **Alt+Shift+Left-click** an item to move its mark between all characters and this character only.
- `/soc scope char` makes new marks this-character-only by default (`/soc scope account` switches back), or use the switch in `/soc settings`.
- A character's own mark wins over an account-wide one, so one character can treat an item differently (even as Normal).
- Tooltips and `/soc list` show *(this character)* for character marks.

| Level | Icon | What happens |
|---|---|---|
| Junk | coin | Safe to lose. Standing Orders: Vendor (coming soon) will sell these when a vendor opens |
| Mail | letter | To send to your bank character. Standing Orders: Mail (coming soon) will mail these |
| Normal | none | The default |
| Locked | key | Never sold, disenchanted, destroyed, traded or mailed |
| Always on me | purple diamond | Locked, and also kept out of the bank: anything you put in the bank is moved straight back to your bags |

Change a level with **Alt+Left-click** in your bags (more protected) or **Alt+Right-click** (less protected). It wraps around: after Always on me comes Junk, and before Junk comes Always on me (`/soc wrap off` stops at both ends). With Standing Orders: Vendor selling Junk or Standing Orders: Mail sending Mail on their own, that's one click from losing a protected item, so Custodian warns you.

Prefer picking from a list? `/soc altclick menu` (or the switch in `/soc settings`) makes Alt+Click open a **mark menu**: every level with its icon, the current one ticked, and "This character only". `/soc mark <item>` opens the same menu for any item. You can also use `/soc junk|mail|normal|lock|onme <shift-clicked item or ID> [char|account]`. `/soc list` shows every marked item. Item tooltips show the level.

The icons sit in the bottom left of the item button, 40% of its width across (so they cover about a sixth of it), at 75% opacity, so stack counts stay readable. Change their size (10% to 100% of the button's width), corner (or center) and opacity in `/soc settings` under Mark icons, or with `/soc icon size 50`, `/soc icon position center`, `/soc icon opacity 60` and `/soc icon reset`.

## Auto-marks

New items in your bags are marked for you (all on by default; turn each off in `/soc settings`):

| Item | Becomes |
|---|---|
| Gray | Junk |
| White gear, weapons and junk with no profession or quest use | Junk |
| Crafting materials none of this character's professions use (cloth, herbs, ore, leather...) | Mail, on this character only |
| Bind on Equip, green and up, not yet bound | Mail |
| Soulbound gear this character can't use, or not for more than 5 levels (**off by default**) | Junk, on this character only |

**Per-character items** are never auto-marked: consumables (food, drink, potions, scrolls...), reagents (ankhs, light feathers, powders...) and trade goods that vendors sell (thread, vials, flux, dyes, salt, spices...). Each character keeps its own stock of these, so when you mark one, the mark is for that character only (add `account` to the command, or Alt+Shift+Left-click it, to share it). Standing Orders knows the common vendor trade goods and learns the rest from every vendor you open.

**Crafting materials follow your professions.** Each character reads the reagents of its known recipes whenever you open one of its profession windows. A material that none of its recipes use is marked Mail for that character only; one that a recipe uses is left alone (and loses an earlier Mail mark). Until a profession's window has been opened once, Standing Orders guesses from the item's kind (cloth for Tailoring and First Aid, herbs for Alchemy...) and leaves items it can't place unmarked until it knows. `/soc status` lists your professions and which ones still need their window opened. Enchanting materials (dusts, essences, shards) are never auto-marked.

Quest items, profession tools (fishing poles, mining picks, blacksmith hammers, spanners, skinning knives, enchanting rods...), bags, ammo, recipes, keys, shirts and tabards are left alone too, and so is anything VendorFlip is holding to flip. **Items you got on purpose are left alone** on the character that got them: traded to you, bought on the AH or from a vendor, or mailed to you by a player (your other characters included). If another character had already auto-marked one, it's Normal on this character.

Only unmarked items are marked, and each item only once: change an auto-marked item's level and it stays changed. Junk and BoE Mail marks apply to all your characters; crafting-material Mail marks to one.

## Guards

Every action that would lose an item goes through one check, `StandingOrdersCustodian.Guard(itemID, link, action)`. When the item is Locked (or Always on me), the action is blocked and an error says so.

| Action | How it's blocked |
|---|---|
| Vendor | Anything that sells it (right-click, dragging it to the vendor, any addon's auto-sell) is **bought straight back** |
| Disenchant / Prospect / Mill | While the spell's targeting cursor is up, protected bag slots are covered in red and the click is blocked |
| Destroy | The delete confirmation is closed and the item goes back to your bag |
| Trade | The item is taken back out of the trade window |
| Mail | The attachment is removed |
| Bank (Always on me only) | While the bank is open, the item is moved straight back to your bags (if they have room) |

**Limits:** Alt+Click, bag icons and the disenchant guard work in the default bags and the bag addons listed below. The vendor, destroy, trade and mail guards work everywhere. Auction house posting isn't guarded yet.

## Equipment sets

Items in your equipment sets (the game's equipment manager) are protected automatically: **Locked** by default, or Always on me or not at all, for every set or one set: in `/soc settings` (pick a set's level from its dropdown), or `/soc sets onme` and `/soc set <name> lock`. `/soc sets` lists them. It works on top of your marks: an item keeps the higher of its own mark and its set's level, and goes back to its own mark when you take it out of the set. Sets belong to one character, so do their choices; the default is for all characters.

## Bag addons

| Bag addon | Alt+Click, level icons, disenchant blocker |
|---|---|
| Blizzard bags | Yes |
| ArkInventory | Yes (bags and bank; not other characters' offline bags) |
| Bagnon, Bagnonium (was Combuctor), Baganator, AdiBags, BetterBags, ElvUI bags | Yes (live views; not other characters' bags or a closed bank) |

Everything else (the vendor, destroy, trade, mail and bank guards, auto-marks, tooltips, `/soc <level> <item>`) works with any bag addon.

## Marking one specific copy of an item

Not supported yet: marks are per item ID, so every copy of an item shares a level. It's planned for a later version.

## For addon developers using Mechanic

If the [Mechanic](https://github.com/Falkicon/Mechanic) dev tool is installed, Standing Orders shows up in its Tests tab (the same checks as `/soc selftest`) and Console (the guard log). Players don't need Mechanic, and Standing Orders doesn't change without it.

## For addon authors

```lua
if StandingOrdersCustodian and StandingOrdersCustodian.IsLocked(itemID) then --[[ skip it ]] end
if StandingOrdersCustodian and StandingOrdersCustodian.Guard(itemID, link, "disenchant") then return end -- shows the error for you
local level = StandingOrdersCustodian and StandingOrdersCustodian.GetLevel(itemID) -- StandingOrdersCustodian.LEVELS.JUNK / MAIL / NORMAL / LOCK / ONME (CONFIRM exists but is held back: GetLevel never returns it yet)
-- MAIL is 1.5 (between JUNK 1 and NORMAL 2), so compare with StandingOrdersCustodian.LEVELS, not with level + 1.
if StandingOrdersCustodian and StandingOrdersCustodian.GetLevel(itemID) == StandingOrdersCustodian.LEVELS.MAIL then --[[ send it to the bank character ]] end
```

## Commands

Every command also works as `/custodian` instead of `/soc` (handy if another addon has taken `/soc`).

`/soc selftest` (checks this install and saves the results; handy for bug reports), `/soc settings` (auto-marks, where new marks go, mark icons, equipment sets), `/soc icon` (mark icon size, position and opacity), `/soc help`, `/soc intro` (what protection covers, also shown once on first login), `/soc status` (which guards are active), `/soc log` (recent guard decisions and Custodian's own messages), `/soc chat on|off` (also show those messages in chat: what it auto-marked, bought back or moved back, and actions it blocked; off by default), `/soc debug`.
