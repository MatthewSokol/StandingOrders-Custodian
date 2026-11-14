# Release testing checklist

Run through this before each CurseForge release. To check items off, open a GitHub issue with this list as its body: GitHub makes the boxes clickable and remembers them.

Part of the release pipeline in `RELEASING.md`. Before you start: `node tools/green.js` is green, `/reload`, `/sot debug`, and keep BugSack open (and Mechanic, if installed). At the end: `/sot selftest`, `/reload`, then `node tools/green.js --game`. Each row has an outline id (`3.2`) to point at; this is the full regression suite. The release checklist in `RELEASING.md` (stage 2.2) lists which of these rows each change since the last release needs.

<details open>
<summary><b>1 Fresh install</b> · 0 / 7</summary>

- [ ] 1.1 The intro window appears a few seconds after the first login; "Got it" closes it and it doesn't come back
- [ ] 1.2 Esc closes the intro without acknowledging it, so it shows again next login
- [ ] 1.3 `/sot intro` reopens it
- [ ] 1.4 Delete `WTF\Account\<account>\SavedVariables\Faves.lua`, log in: no Lua errors
- [ ] 1.5 `/sot list` says nothing is marked
- [ ] 1.6 `/sot status` shows every guard on
- [ ] 1.7 Mark an item, log in a second character: the mark is there too (levels are account wide)

</details>

<details open>
<summary><b>2 Per-character marks</b> · 0 / 9</summary>

- [ ] 2.1 Alt+Shift+Left-click a marked item: chat says it's now for this character only; the tooltip shows "(this character)"
- [ ] 2.2 Log in a second character: that item isn't marked there
- [ ] 2.3 Alt+Shift+Left-click it again on the first character: back to all characters
- [ ] 2.4 `/sot scope char`, then Alt+Click a new item: it's marked for this character only; `/sot scope account` switches back
- [ ] 2.5 `/sot lock <item> char` marks for this character only
- [ ] 2.6 Mark an item Locked account wide, then `/sot normal <item> char`: Normal on this character, still Locked on others
- [ ] 2.7 `/sot list` shows both kinds, character marks labelled
- [ ] 2.8 `/reload` a few times: no errors at login or when the bags first open
- [ ] 2.9 Works with SellAll disabled (Faves alone loads with no errors)

</details>

<details open>
<summary><b>3 Moving from SellAll test builds</b> · 0 / 2</summary>

- [ ] 3.1 Items marked in an older SellAll build show the same levels after updating both addons
- [ ] 3.2 SellAll prints how many levels it moved, once; it doesn't repeat after `/reload`

</details>

<details open>
<summary><b>4 Disenchant guard</b> · 0 / 9</summary>

- [ ] 4.1 With Disenchant targeting up, Confirm/Locked bag slots turn red; hovering one shows the tooltip plus a "blocked" line
- [ ] 4.2 `/sot log` shows "targeting started: destructive" and "blocker caught click" lines
- [ ] 4.3 Disenchant from an action bar button, then click a Locked item: targeting cancels, error shown, item kept
- [ ] 4.4 Same with a `/cast Disenchant` macro
- [ ] 4.5 Same with Disenchant cast from the spellbook
- [ ] 4.6 Disenchanting a Normal item still works
- [ ] 4.7 An enchant from the profession window can still go on a Locked item
- [ ] 4.8 An oil or scroll can still be applied to a Locked item
- [ ] 4.9 VendorFlip's Disenchant button refuses a Locked item

</details>

<details open>
<summary><b>5 Other guards</b> · 0 / 37</summary>

- [ ] 5.1 A Locked item sold by right-click is bought straight back
- [ ] 5.2 A Locked item dragged onto the vendor is bought straight back
- [ ] 5.3 Buyback only ever buys back the Locked item, never a neighbouring buyback slot
- [ ] 5.4 With ForeverPlus / Leatrix junk-selling on, a Locked gray item is bought back
- [ ] 5.5 Destroy: dragging a Locked item out of the bags closes the delete popup, item kept
- [ ] 5.6 Trade: a Locked item put into a trade pops back out, Normal items stay
- [ ] 5.7 Mail: a Locked attachment is removed, Normal attachments stay
- [ ] 5.8 Alt+Left-click steps an item through Junk, Mail, Normal, Confirm, Locked, Always on me
- [ ] 5.9 Confirm item sold: it's bought back and the hold window asks; Allow once, sell it again: it stays sold; close and reopen the vendor and it's held again
- [ ] 5.10 Confirm item disenchanted: the click is caught and the window asks; Allow once, Disenchant again: it works once, the next try is caught
- [ ] 5.11 Confirm item put in a trade or mail: taken back out; Allow once, put it in again: it stays until the window closes
- [ ] 5.12 "Keep it" (or Esc) leaves everything blocked; Locked items never show the window
- [ ] 5.13 Auto-marks: a gray becomes Junk, a white weapon/armor piece becomes Junk, an unbound BoE green or blue becomes Mail
- [ ] 5.14 Crafting materials: on a character without Tailoring, Linen Cloth becomes Mail "(this character)"; on a tailor it's left alone once the Tailoring window has been opened
- [ ] 5.15 Opening a profession window takes the Mail mark off materials its recipes use; /sot status lists professions and which still need their window opened
- [ ] 5.16 Enchanting materials (Strange Dust, Lesser Magic Essence, shards) are never auto-marked
- [ ] 5.17 Auto-marks leave alone: quest items, food/drink, bags, ammo, shirts, tabards, soulbound gear, VendorFlip's held items
- [ ] 5.18 Items traded to you, bought from a vendor or the AH, or mailed by a player aren't auto-marked; one already auto-marked elsewhere becomes Normal on this character
- [ ] 5.19 Consumables, reagents (Ankh, Light Feather) and vendor trade goods (thread, vials) are never auto-marked; old auto-marks on them are removed at login
- [ ] 5.20 Alt+Clicking one of those marks it "(this character)" even with new marks set to all characters
- [ ] 5.21 A trade good first seen on a vendor (not in the built-in list) becomes per-character after opening that vendor
- [ ] 5.22 Changing an auto-marked item's level sticks after /reload and more loot
- [ ] 5.23 /sot settings: each switch stops its rule; turning one back on marks matching items in your bags
- [ ] 5.24 With Faves auto-marks, SellAll's own auto-mark Junk doesn't run and its panel points to /sot settings
- [ ] 5.25 Alt+Right-click steps it back down
- [ ] 5.26 At a vendor, Alt+Right-click changes the level without selling the item
- [ ] 5.27 Icons and tooltip lines show in the combined bag
- [ ] 5.28 Icons and tooltip lines show in separate bags
- [ ] 5.29 Icons and tooltip lines show in bank bags
- [ ] 5.30 Bank: an Always on me item right-clicked or dragged into the bank (or a bank bag) is moved back to your bags; a Locked item stays banked
- [ ] 5.31 Bank with full bags: one "bags are full" error, the item stays in the bank
- [ ] 5.32 Opening the bank with an Always on me item already in it moves it out
- [ ] 5.33 Save an equipment set with an item in it: its tooltip says "Faves: Locked (equipment set <name>)"; selling it is bought back
- [ ] 5.34 `/sot set <name> confirm`, `onme` or `off` changes that set's items; `/sot sets onme` changes the default for sets
- [ ] 5.35 Save the set again without the item: it goes back to its own mark
- [ ] 5.36 Alt+Right-click an item in a set: chat says it stays protected while it's in the set
- [ ] 5.37 `/sot settings`, Equipment sets: left-click a row steps its level forward, right-click back; the default row changes every set left on "default"

</details>

<details open>
<summary><b>6 Edge cases</b> · 0 / 8</summary>

- [ ] 6.1 In combat: opening bags and Alt+Click give no "action blocked" errors
- [ ] 6.2 In combat: potions can still be used from the bags
- [ ] 6.3 With ArkInventory: `/sot status` says "ArkInventory: supported"
- [ ] 6.4 With ArkInventory: Alt+Click in its bag window raises the level; the icon shows on the Ark button
- [ ] 6.5 With ArkInventory: viewing another character's bags, Alt+Click does nothing in Faves
- [ ] 6.6 With ArkInventory: Disenchant targeting covers Locked items in the Ark window in red
- [ ] 6.7 With ArkInventory: vendor, destroy, trade and mail guards still work
- [ ] 6.8 After a selling session, opening the bank, the auction house and talents shows no "AddOn has been blocked" messages

</details>

<details open>
<summary><b>7 Release</b> · 0 / 7</summary>

- [ ] 7.1 CurseForge project created; its ID added to the `.toc` as `## X-Curse-Project-ID:`
- [ ] 7.2 Candidate picked (`pipeline.js candidates`; default the newest) and `pipeline.js prep <version>` passed
- [ ] 7.3 Release tag `v<version>` on the candidate's commit on `main` (`pipeline.js released <version>`, lightweight)
- [ ] 7.4 `powershell -File ./release.ps1` builds `dist\Faves-<version>.zip` and the release notes from the tag
- [ ] 7.5 The zip unpacks to a single `Faves\` folder, its .toc shows the version, and that install loads in game
- [ ] 7.6 After your go-ahead: `git push origin v<version>` (only that tag), then the zip uploaded to CurseForge with the notes from `dist\`
- [ ] 7.7 Released before (or together with) SellAll, whose warning links to it

</details>

<details open>
<summary><b>8 Bag addons</b> · 0 / 8</summary>

- [ ] 8.1 `<env> snapshot pre-bag-addons` (`<env>` as in RELEASING.md) `auto executed · game closed`
- [ ] 8.2 ArkInventory: `<env> profile only Faves ArkInventory !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window Alt+Click an item: the level changes and the icon shows; `/sot status` lists ArkInventory as supported; away from the bank and in another character's bags, Alt+Click does nothing in Faves; no Faves errors
- [ ] 8.3 Bagnon: `<env> profile only Faves Bagnon BagBrother !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window Alt+Click an item: the level changes and the icon shows; `/sot status` lists Bagnon as supported; away from the bank and in another character's bags, Alt+Click does nothing in Faves; no Faves errors
- [ ] 8.4 Baganator: `<env> profile only Faves Baganator !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window Alt+Click an item: the level changes and the icon shows; `/sot status` lists Baganator as supported; away from the bank and in another character's bags, Alt+Click does nothing in Faves; no Faves errors
- [ ] 8.5 AdiBags: `<env> profile only Faves AdiBags !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window Alt+Click an item: the level changes and the icon shows; `/sot status` lists AdiBags as supported; away from the bank, Alt+Click does nothing in Faves; no Faves errors
- [ ] 8.6 BetterBags: `<env> profile only Faves BetterBags !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window Alt+Click an item: the level changes and the icon shows; `/sot status` lists BetterBags as supported; away from the bank, Alt+Click does nothing in Faves; no Faves errors
- [ ] 8.7 ElvUI bags: `<env> profile only Faves ElvUI ElvUI_Libraries !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window Alt+Click an item: the level changes and the icon shows; `/sot status` lists ElvUI bags as supported; away from the bank, Alt+Click does nothing in Faves; no Faves errors
- [ ] 8.8 `<env> restore` puts your addons back as they were `auto executed · after the last pass`

</details>
