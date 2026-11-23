# Changelog

All notable changes to Custodian (Quartermaster before 1.0.0). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
follow [Semantic Versioning](https://semver.org/) and come from git tags: each merged change
gets its own version, and a release publishes one of them.

## [Unreleased]

### Added

- **Unusable soulbound gear becomes Junk** (new auto-mark, off by default; turn it on in `/soc settings`): soulbound weapons and armor this character's class can never use, or not for more than 5 levels, are marked Junk on this character only. Weapon types the class can train count as usable, and so does armor it learns later once it's within 5 levels (Mail at 40 for Hunters and Shamans, Plate at 40 for Warriors and Paladins). Enchanters keep green and better gear to disenchant.
- **Wrap-around:** Alt+Left-click on an Always on me item goes on to Junk, and Alt+Right-click on Junk to Always on me (on by default; `/soc wrap off` or the switch in `/soc settings` turns it off). If Standing Orders: Vendor sells Junk on its own or Standing Orders: Mail sends Mail on its own, Custodian warns you (in the settings, when you turn wrap-around on, once at login, and when a click wraps onto Junk).

### Changed

- **Quieter chat:** Custodian's own messages (what it auto-marked, bought back or moved back, and actions it blocked) now go to the log only (`/soc log`). Turn them back on in chat with `/soc chat on` or the new **Chat** switch in `/soc settings`. The red error on screen still shows when an action is blocked, and replies to your own clicks and commands always show.

### Fixed

- **Profession tools aren't Junk:** auto-marks no longer mark fishing poles, mining picks, blacksmith hammers, spanners, skinning knives, enchanting rods and other profession tools Junk (white ones looked like plain white weapons). A Junk auto-mark 1.0.0 put on one comes off at your next login.
- **Mailbox with Postal or Posty:** on the Send Mail page, Alt+Left-click in your bags is left to Postal's Express module (it attaches the item, or sends it with AutoSend), so Custodian no longer also changes the item's mark with that click. Alt+Right-click and the `/soc` commands still work there, and with Express turned off Custodian keeps Alt+Left-click.

## [1.0.0] - 2026-11-21

### Changed

- **New name: Standing Orders: Custodian.** Quartermaster made players think of reputation vendors. The command is `/soc`, or `/custodian` (`/soq` is gone), the folder is `StandingOrders_Custodian` and the API global is `StandingOrdersCustodian` (`StandingOrdersQuartermaster` still works for now). It stays under Standing Orders in the AddOn list.
- **Bagnonium:** Combuctor's new name is supported (Combuctor itself still works).
- **Intro:** split into sections with headings, each mark level on its own line with its icon, and the auto-marks as bullets; it ends with the bags Custodian works with, and shows which of them you have loaded. It shows once more at your next login.

### Fixed

- **Guard message:** blocking a Locked item said "Unfavorite it" (a test-build word); it now says to lower it to Normal (or to Locked, to bank an Always on me item).
- **Intro:** Standing Orders: Vendor and Mail are marked as coming soon.
- **Settings:** the "Except items you got on purpose" switch label no longer runs past the panel's edge.

## [0.2.0] - 2026-11-20

### Fixed

- **Settings panel:** it scrolls instead of running past the bottom of the settings window.
- **Settings panel:** the "What Standing Orders protects" button is now wide enough for its label.
- **Old auto-marks on reagents:** a Mail mark an earlier test build put on a reagent (such as Light Feather) for one character now comes off at login, like the account-wide ones already did.
- **Disenchant guard error:** clicking a protected item while Disenchant targeting was up gave an "AddOn tried to call the protected function SpellStopTargeting()" error. The click is still blocked and the item kept; press Esc or right-click to end targeting.

### Changed

- **Confirm is held back for a later version:** its "allow once" didn't reliably let a sale through. Nothing offers Confirm now, and an item already marked Confirm is protected as Locked (its mark is kept, so it comes back when Confirm does).
- **New icon:** a quartermaster's ledger with Locked, Junk and Mail tags, in the AddOn List, the settings panel, the intro, the hold window and on the project page.
- **New name: Standing Orders: Quartermaster.** Faves (its test-build name) is now part of the Standing Orders suite, with Standing Orders: Vendor (selling) and Standing Orders: Mail (mailing to alts). The command is `/soq` (`/faves` is gone), the folder is `StandingOrders_Quartermaster` and the API global is `StandingOrdersQuartermaster`.

### Added

- **Mark icon size, position and opacity:** in `/soq settings` (with a sample button) or `/soq icon`, choose how big the mark is (10% to 100% of the item button's width), which corner it sits in (or the center) and how opaque it is, so it doesn't hide stack counts or other addons' text. The default is now 40% of the button's width, bottom left, 75% opaque (it used to be a small solid icon in the top left).
- **More bag addons:** Alt+Click, level icons and the disenchant blocker now work in Bagnon, Combuctor, Baganator, AdiBags, BetterBags and ElvUI's bags, as well as the default bags and ArkInventory.
- **Equipment sets:** items in your equipment sets are protected automatically, Locked by default. Choose Always on me or off for all sets (`/soq sets <level>`) or per set (`/soq set <name> <level>`), in `/soq settings` or with commands.

## [0.1.0] - 2026-11-13

### Added

First release. Item protection used to be part of SellAll; it's now its own addon so it works with any vendor addon.

- **Item levels**, for all your characters or just one (Alt+Shift+Left-click an item to switch, `/soq scope` for the default):
  - **Junk** marks items you're happy to lose (SellAll sells them when a vendor opens).
  - **Mail** marks items to send to your bank character.
- **Auto-marks**, each one switchable in `/soq settings`: grays and white gear with no profession or quest use become Junk; crafting materials and unbound BoE items become Mail. Items traded to you, bought (AH or vendor) or mailed to you by a player are left alone.
- **Crafting materials follow your professions:** they're marked Mail only on characters whose known recipes don't use them (read from each profession window), and never for enchanting materials.
- **Per-character items:** consumables, reagents and vendor trade goods (thread, vials, flux, dyes...) are never auto-marked, and marking one marks it for that character only.
  - **Normal** is the default.
  - **Confirm** currently acts as Locked.
  - **Locked** is protected from everything below.
  - **Always on me** is Locked and also stays out of the bank.

  Alt+Left-click an item in your bags to make it more protected, Alt+Right-click to make it less protected. Bag icons and a tooltip line show each item's level.
- **Guards** for every action that would lose a Locked item:
  - Vendor: a Locked item sold any way is bought straight back.
  - Disenchant, Prospecting, Milling: protected bag slots turn red and the click is blocked.
  - Destroy: the delete popup closes.
  - Trade and mail: the item is removed from the window.
  - Bank (Always on me only): the item is moved straight back to your bags.
- **One-time intro** listing what protection covers and what it doesn't yet (`/soq intro` reopens it).
- Levels set in earlier SellAll test builds are brought over automatically.
- `/soq selftest` checks the install and saves the results. With the optional Mechanic dev tool, Quartermaster shows its checks and log there.
- **ArkInventory bags:** Alt+Click, level icons and the disenchant blocker work in ArkInventory's bag and bank windows too, through its public API. Offline views (another character's bags, the bank away from a banker) are left alone.
- `StandingOrdersQuartermaster.IsLocked`, `StandingOrdersQuartermaster.GetLevel` and `StandingOrdersQuartermaster.Guard` for other addons.

**Known limits:**
- Auction house posting isn't guarded yet.
- Alt+Click, bag icons and the disenchant guard work in the default bags and ArkInventory; other bag addons are planned (see README).

