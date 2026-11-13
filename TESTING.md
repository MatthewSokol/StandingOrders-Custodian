# Release testing checklist

Run through this before each CurseForge release. To check items off, open a GitHub issue with this list as its body: GitHub makes the boxes clickable and remembers them.

Part of the release pipeline in `RELEASING.md`. Before you start: `node tools/green.js` is green, `/reload`, `/faves debug`, and keep BugSack open (and Mechanic, if installed). At the end: `/faves selftest`, `/reload`, then `node tools/green.js --game`.

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
- [ ] Auto-marks: a gray becomes Junk, a white weapon/armor piece becomes Junk, an unbound BoE green or blue becomes Mail
- [ ] Crafting materials: on a character without Tailoring, Linen Cloth becomes Mail "(this character)"; on a tailor it's left alone once the Tailoring window has been opened
- [ ] Opening a profession window takes the Mail mark off materials its recipes use; /faves status lists professions and which still need their window opened
- [ ] Enchanting materials (Strange Dust, Lesser Magic Essence, shards) are never auto-marked
- [ ] Auto-marks leave alone: quest items, food/drink, bags, ammo, shirts, tabards, soulbound gear, VendorFlip's held items
- [ ] Items traded to you, bought from a vendor or the AH, or mailed by a player aren't auto-marked; one already auto-marked elsewhere becomes Normal on this character
- [ ] Consumables, reagents (Ankh, Light Feather) and vendor trade goods (thread, vials) are never auto-marked; old auto-marks on them are removed at login
- [ ] Alt+Clicking one of those marks it "(this character)" even with new marks set to all characters
- [ ] A trade good first seen on a vendor (not in the built-in list) becomes per-character after opening that vendor
- [ ] Changing an auto-marked item's level sticks after /reload and more loot
- [ ] /faves settings: each switch stops its rule; turning one back on marks matching items in your bags
- [ ] With Faves auto-marks, SellAll's own auto-mark Junk doesn't run and its panel points to /faves settings
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
- [ ] With ArkInventory: `/faves status` says "ArkInventory: supported"
- [ ] With ArkInventory: Alt+Click in its bag window raises the level; the icon shows on the Ark button
- [ ] With ArkInventory: viewing another character's bags, Alt+Click does nothing in Faves
- [ ] With ArkInventory: Disenchant targeting covers Locked items in the Ark window in red
- [ ] With ArkInventory: vendor, destroy, trade and mail guards still work
- [ ] After a selling session, opening the bank, the auction house and talents shows no "AddOn has been blocked" messages

## 6. Release
- [ ] CurseForge project created; its ID added to the `.toc` as `## X-Curse-Project-ID:`
- [ ] Candidate picked (`pipeline.js candidates`; default the newest) and `pipeline.js prep <version>` passed
- [ ] Release tag `v<version>` on the candidate's commit on `main` (`pipeline.js released <version>`, lightweight)
- [ ] `powershell -File ./release.ps1` builds `dist\Faves-<version>.zip` and the release notes from the tag
- [ ] The zip unpacks to a single `Faves\` folder, its .toc shows the version, and that install loads in game
- [ ] After your go-ahead: `git push origin v<version>` (only that tag), then the zip uploaded to CurseForge with the notes from `dist\`
- [ ] Released before (or together with) SellAll, whose warning links to it
