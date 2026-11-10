# Release testing checklist

Run through this before each CurseForge release. To check items off, open a GitHub issue with this list as its body: GitHub makes the boxes clickable and remembers them.

Before you start: `/reload`, `/faves debug`, and keep BugSack open.

## 1. Fresh install
- [ ] The intro window appears a few seconds after the first login; "Got it" closes it and it doesn't come back
- [ ] Esc closes the intro without acknowledging it, so it shows again next login
- [ ] `/faves intro` reopens it
- [ ] Delete `WTF\Account\<account>\SavedVariables\Faves.lua`, log in: no Lua errors
- [ ] `/faves list` says nothing is marked
- [ ] `/faves status` shows every guard on
- [ ] Mark an item, log in a second character: the mark is there too (levels are account wide)

## 1b. Per-character marks
- [ ] Alt+Shift+Left-click a marked item: chat says it's now for this character only; the tooltip shows "(this character)"
- [ ] Log in a second character: that item isn't marked there
- [ ] Alt+Shift+Left-click it again on the first character: back to all characters
- [ ] `/faves scope char`, then Alt+Click a new item: it's marked for this character only; `/faves scope account` switches back
- [ ] `/faves lock <item> char` marks for this character only
- [ ] Mark an item Locked account wide, then `/faves normal <item> char`: Normal on this character, still Locked on others
- [ ] `/faves list` shows both kinds, character marks labelled
- [ ] `/reload` a few times: no errors at login or when the bags first open
- [ ] Works with SellAll disabled (Faves alone loads with no errors)

## 2. Moving from SellAll test builds
- [ ] Items marked in an older SellAll build show the same levels after updating both addons
- [ ] SellAll prints how many levels it moved, once; it doesn't repeat after `/reload`

## 3. Disenchant guard
- [ ] With Disenchant targeting up, Confirm/Locked bag slots turn red; hovering one shows the tooltip plus a "blocked" line
- [ ] `/faves log` shows "targeting started: destructive" and "blocker caught click" lines
- [ ] Disenchant from an action bar button, then click a Locked item: targeting cancels, error shown, item kept
- [ ] Same with a `/cast Disenchant` macro
- [ ] Same with Disenchant cast from the spellbook
- [ ] Disenchanting a Normal item still works
- [ ] An enchant from the profession window can still go on a Locked item
- [ ] An oil or scroll can still be applied to a Locked item
- [ ] VendorFlip's Disenchant button refuses a Locked item

## 4. Other guards
- [ ] A Locked item sold by right-click is bought straight back
- [ ] A Locked item dragged onto the vendor is bought straight back
- [ ] Buyback only ever buys back the Locked item, never a neighbouring buyback slot
- [ ] With ForeverPlus / Leatrix junk-selling on, a Locked gray item is bought back
- [ ] Destroy: dragging a Locked item out of the bags closes the delete popup, item kept
- [ ] Trade: a Locked item put into a trade pops back out, Normal items stay
- [ ] Mail: a Locked attachment is removed, Normal attachments stay
- [ ] Alt+Left-click steps an item through Junk, Mail, Normal, Confirm, Locked, Always on me
- [ ] Looting an unbound BoE green or blue marks it Mail (letter icon, chat line); a soulbound or white one isn't
- [ ] A BoE taken from another character's mail isn't marked Mail (and stays Normal on that character if it was Mail); one bought on the AH is
- [ ] Changing an auto-marked item to Normal sticks after /reload and more loot
- [ ] `/faves automail off` stops auto-marking; SellAll's Sell All and Up to skip Mail items
- [ ] Alt+Right-click steps it back down
- [ ] At a vendor, Alt+Right-click changes the level without selling the item
- [ ] Icons and tooltip lines show in the combined bag
- [ ] Icons and tooltip lines show in separate bags
- [ ] Icons and tooltip lines show in bank bags
- [ ] Bank: an Always on me item right-clicked or dragged into the bank (or a bank bag) is moved back to your bags; a Locked item stays banked
- [ ] Bank with full bags: one "bags are full" error, the item stays in the bank
- [ ] Opening the bank with an Always on me item already in it moves it out

## 5. Edge cases
- [ ] In combat: opening bags and Alt+Click give no "action blocked" errors
- [ ] In combat: potions can still be used from the bags
- [ ] With ArkInventory: `/faves status` shows the warning
- [ ] With ArkInventory: vendor, destroy, trade and mail guards still work
- [ ] After a selling session, opening the bank, the auction house and talents shows no "AddOn has been blocked" messages

## 6. Release
- [ ] `powershell -File ./package.ps1` builds `dist\Faves-<version>.zip`
- [ ] The zip unpacks to a single `Faves\` folder, and that install loads in game
- [ ] CurseForge project created; its ID added to the `.toc` as `## X-Curse-Project-ID:`
- [ ] Release tagged on `main` (for example `v1.0.0`) and pushed
- [ ] Zip uploaded to CurseForge with the `CHANGELOG.md` entry as the release notes
- [ ] Released before (or together with) SellAll, whose warning links to it
