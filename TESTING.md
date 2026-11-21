# Release testing checklist

Run through this before each CurseForge release. To check items off, open a GitHub issue with this list as its body: GitHub makes the boxes clickable and remembers them.

Part of the release pipeline in `RELEASING.md`. Before you start: `node tools/green.js` is green, `/reload`, `/soc debug`, and keep BugSack open (and Mechanic, if installed). At the end: `/soc selftest`, `/reload`, then `node tools/green.js --game`. Each row has an outline id (`3.2`) to point at; this is the full regression suite, one row per behaviour (rows other steps already prove were dropped, so ids have gaps). The release checklist in `RELEASING.md` (stage 2.2) lists which of these rows each change since the last release needs.

<details open>
<summary><b>1 Fresh install</b> · 0 / 4</summary>

- [ ] 1.2 Esc closes the intro without acknowledging it, so it shows again next login
- [ ] 1.3 `/soc intro` reopens it
- [ ] 1.5 `/soc list` says nothing is marked and `/soc status` shows every guard on (on the clean install)
- [ ] 1.7 Mark an item, log in a second character: the mark is there too (levels are account wide)

</details>

<details open>
<summary><b>2 Per-character marks</b> · 0 / 7</summary>

- [ ] 2.1 Alt+Shift+Left-click a marked item: chat says it's now for this character only; the tooltip shows "(this character)"
- [ ] 2.2 Log in a second character: that item isn't marked there
- [ ] 2.3 Alt+Shift+Left-click it again on the first character: back to all characters
- [ ] 2.4 `/soc scope char`, then Alt+Click a new piece of gear (not a potion, food, reagent or vendor trade good: those are always per character, see 5.20): it's marked for this character only; `/soc scope account`, then Alt+Click another piece of gear: no "(this character)"
- [ ] 2.5 `/soc lock <item> char` marks for this character only
- [ ] 2.6 Mark an item Locked account wide, then `/soc normal <item> char`: Normal on this character, still Locked on others
- [ ] 2.7 `/soc list` shows both kinds, character marks labelled

</details>

<details open>
<summary><b>3 Moving from SellAll test builds</b> · 0 / 2</summary>

- [ ] 3.1 Items marked in an older SellAll build show the same levels after updating both addons
- [ ] 3.2 SellAll prints how many levels it moved, once; it doesn't repeat after `/reload`

</details>

<details open>
<summary><b>4 Disenchant guard</b> · 0 / 7</summary>

- [ ] 4.1 With Disenchant targeting up, Locked bag slots turn red; hovering one shows the tooltip plus a "blocked" line
- [ ] 4.2 `/soc log` shows "targeting started: destructive" and "blocker caught click" lines
- [ ] 4.3 Disenchant from an action bar button, a `/cast Disenchant` macro or the spellbook (try at least two), then click a Locked item: the click is blocked, error shown, item kept, and no "AddOn tried to call the protected function" error; the cursor stays until Esc or right-click
- [ ] 4.6 Disenchanting a Normal item still works
- [ ] 4.7 An enchant from the profession window can still go on a Locked item
- [ ] 4.8 An oil or scroll can still be applied to a Locked item
- [ ] 4.9 VendorFlip's Disenchant button refuses a Locked item

</details>

<details open>
<summary><b>5 Other guards</b> · 0 / 31</summary>

- [ ] 5.1 A Locked item sold by right-click or dragged onto the vendor is bought straight back
- [ ] 5.3 Buyback only ever buys back the Locked item, never a neighbouring buyback slot
- [ ] 5.4 With ForeverPlus / Leatrix junk-selling on, a Locked gray item is bought back
- [ ] 5.5 Destroy: dragging a Locked item out of the bags closes the delete popup, item kept
- [ ] 5.6 Trade: a Locked item put into a trade pops back out, Normal items stay
- [ ] 5.7 Mail: a Locked attachment is removed, Normal attachments stay
- [ ] 5.8 Alt+Left-click steps an item through Junk, Mail, Normal, Locked, Always on me (no Confirm: it's held back for a later version); Alt+Right-click steps it back down
- [ ] 5.9 (Deferred with Confirm, BACKLOG.md) Confirm item sold: it's bought back and the hold window asks; Allow once, sell it again: it stays sold; close and reopen the vendor and it's held again
- [ ] 5.10 (Deferred with Confirm) Confirm item disenchanted: the click is caught and the window asks; Allow once, Disenchant again: it works once, the next try is caught
- [ ] 5.11 (Deferred with Confirm) Confirm item put in a trade or mail: taken back out; Allow once, put it in again: it stays until the window closes
- [ ] 5.12 (Deferred with Confirm) "Keep it" (or Esc) leaves everything blocked; Locked items never show the window
- [ ] 5.13 Auto-marks: a gray becomes Junk, a white weapon/armor piece becomes Junk, an unbound BoE green or blue becomes Mail
- [ ] 5.14 Crafting materials: on a character without Tailoring, Linen Cloth becomes Mail "(this character)"; on a tailor it's left alone once the Tailoring window has been opened
- [ ] 5.15 Opening a profession window takes the **auto-marked** Mail off materials its recipes use (a Mail mark you set yourself stays); /soc status lists professions and which still need their window opened
- [ ] 5.17 Auto-marks leave alone: quest items, enchanting materials (Strange Dust, essences, shards), food/drink, bags, ammo, shirts, tabards, soulbound gear, VendorFlip's held items
- [ ] 5.18 Items traded to you, bought from a vendor or the AH, or mailed by a player aren't auto-marked; one already auto-marked elsewhere becomes Normal on this character
- [ ] 5.19 (Retest deferred, BACKLOG.md: Light Feathers can still be auto-marked Mail) Consumables, reagents (Ankh, Light Feather) and vendor trade goods (thread, vials) are never auto-marked; old auto-marks on them, account-wide or "(this character)", are removed at login
- [ ] 5.20 Alt+Clicking one of those marks it "(this character)" even with new marks set to all characters
- [ ] 5.21 A trade good first seen on a vendor (not in the built-in list) becomes per-character after opening that vendor
- [ ] 5.22 Changing an auto-marked item's level sticks after /reload and more loot
- [ ] 5.23 /soc settings: each switch stops its rule; turning one back on marks matching items in your bags
- [ ] 5.24 With Custodian auto-marks, Standing Orders: Vendor's own auto-mark Junk doesn't run and its panel points to /soc settings
- [ ] 5.26 At a vendor, Alt+Right-click changes the level without selling the item
- [ ] 5.27 Icons and tooltip lines show in the combined bag, separate bags and bank bags
- [ ] 5.30 Bank: an Always on me item right-clicked or dragged into the bank (or a bank bag), or already there when you open it, is moved back to your bags; a Locked item stays banked
- [ ] 5.31 Bank with full bags: one "bags are full" error, the item stays in the bank
- [ ] 5.33 Save an equipment set with an item in it: its tooltip says "Standing Orders: Locked (equipment set "<name>")"; selling it is bought back
- [ ] 5.34 `/soc set <name> lock`, `onme` or `off` changes that set's items; `/soc sets onme` changes the default for sets
- [ ] 5.35 Save the set again without the item: it goes back to its own mark
- [ ] 5.36 Alt+Right-click an item in a set: chat says it stays protected while it's in the set
- [ ] 5.37 `/soc settings`, Equipment sets: each row is a dropdown: pick a level and the row shows it (a set also offers "default"); the default row changes every set left on "default"

</details>

<details open>
<summary><b>6 Edge cases</b> · 0 / 3</summary>

- [ ] 6.1 In combat: opening bags and Alt+Click give no "action blocked" errors
- [ ] 6.2 In combat: potions can still be used from the bags
- [ ] 6.8 After a selling session, opening the bank, the auction house and talents shows no "AddOn has been blocked" messages

</details>

<details open>
<summary><b>8 Bag addons</b> · 0 / 9</summary>

- [ ] 8.1 `<env> snapshot pre-bag-addons` (`<env>` as in RELEASING.md) `auto executed · game closed` `auto validated · snapshot saved`
- [ ] 8.2 ArkInventory: `<env> profile only StandingOrders_Custodian ArkInventory !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window: Alt+Click marks an item and the icon shows, Disenchant targeting turns Locked slots red, `/soc status` lists ArkInventory as supported, and in another character's bags Alt+Click does nothing; no Custodian errors
- [ ] 8.3 Bagnon: `<env> profile only StandingOrders_Custodian Bagnon BagBrother !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window: Alt+Click marks an item and the icon shows, Disenchant targeting turns Locked slots red, `/soc status` lists Bagnon as supported, and in another character's bags Alt+Click does nothing; no Custodian errors
- [ ] 8.3.1 Bagnonium (Combuctor's new name): `<env> profile only StandingOrders_Custodian Bagnonium BagBrother !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window: Alt+Click marks an item and the icon shows, Disenchant targeting turns Locked slots red, `/soc status` lists Bagnonium as supported, and `/soc intro` shows Bagnonium (was Combuctor) green "(in use)" with its own icon; no Custodian errors
- [ ] 8.4 Baganator: `<env> profile only StandingOrders_Custodian Baganator Syndicator !BugGrabber BugSack` `auto executed · game closed` (Baganator needs Syndicator, though its .toc lists it as optional); full restart; in its bag window: Alt+Click marks an item and the icon shows, Disenchant targeting turns Locked slots red, `/soc status` lists Baganator as supported, and in another character's bags Alt+Click does nothing; no Custodian errors
- [ ] 8.5 AdiBags: `<env> profile only StandingOrders_Custodian AdiBags !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window: Alt+Click marks an item and the icon shows, Disenchant targeting turns Locked slots red, `/soc status` lists AdiBags as supported; no Custodian errors
- [ ] 8.6 BetterBags: `<env> profile only StandingOrders_Custodian BetterBags !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window: Alt+Click marks an item and the icon shows, Disenchant targeting turns Locked slots red, `/soc status` lists BetterBags as supported; no Custodian errors
- [ ] 8.7 ElvUI bags: `<env> profile only StandingOrders_Custodian ElvUI ElvUI_Libraries !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window: Alt+Click marks an item and the icon shows, Disenchant targeting turns Locked slots red, `/soc status` lists ElvUI bags as supported; no Custodian errors
- [ ] 8.8 `<env> restore` puts your addons back as they were `auto executed · after the last pass` `auto validated · restore verified`

</details>

<details open>
<summary><b>9 Mark icons</b> · 0 / 5</summary>

- [ ] 9.1 Upgrade or fresh install: marked items' icons sit in the bottom left of the item button, 40% of its width across (a test build's old 30% moves to 40% once), slightly see-through, and stack counts stay readable
- [ ] 9.2 `/soc settings`, Mark icons on bag items: Size reads "N% of the button's width" and -/+ moves it by 5% (10% to 100%); at 50% the icon is half the button across; the sample button and your open bags change at once
- [ ] 9.3 Position is a dropdown: Bottom left, Top left, Top right, Bottom right, Center; pick one and the dropdown shows it; the sample and your bags follow
- [ ] 9.4 Opacity -/+ moves by 5% (10% to 100%); at 100% the icon is solid; `/soc icon size 50`, `/soc icon position center`, `/soc icon opacity 60` do the same, and `/soc icon reset` goes back to 40%, bottom left, 75%
- [ ] 9.5 The settings panel still shows every equipment set row below the mark icon controls (scroll if the panel scrolls); after `/reload` and on another character the icon settings are kept

</details>
