# Release testing checklist

Run through this before each CurseForge release. To check items off, open a GitHub issue with this list as its body: GitHub makes the boxes clickable and remembers them.

Part of the release pipeline in `RELEASING.md`. Before you start: `node tools/green.js` is green, `/reload`, `/soc debug`, and keep BugSack open (and Mechanic, if installed). At the end: `/soc selftest`, `/reload`, then `node tools/green.js --game`. Each row has an outline id (`3.2`) to point at; this is the full regression suite, one row per behaviour (rows other steps already prove were dropped, so ids have gaps). The release checklist in `RELEASING.md` (stage 2.2) lists which of these rows each change since the last release needs.

<details open>
<summary><b>1 Fresh install</b> · 0 / 5</summary>

- [ ] 1.2 Esc closes the intro without acknowledging it, so it shows again next login
- [ ] 1.3 `/soc intro` reopens it
- [ ] 1.4 The intro opens short ("In short": how Alt+Click works now, the marks with their icons (Always on me only once the advanced options are shown or it's in your sequence), what Locked does, /soc list); Show details shows the full intro (only the auto-mark rules that are on) and the bag list, Show less goes back; after a /reload, `/soc intro` opens in the view you left it in; with "Alt+Click opens a menu" on, the short view says Alt+Click opens a menu
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
<summary><b>5 Other guards</b> · 0 / 43</summary>

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
- [ ] 5.13 Auto-marks: a gray becomes Junk; with the advanced rules on (an install from 1.0.0 has them; on a new install tick them under `/soc settings` > Show advanced options), a white weapon/armor piece becomes Junk and an unbound BoE green or blue becomes Mail
- [ ] 5.14 Crafting materials (with that advanced rule on): on a character without Tailoring, Linen Cloth becomes Mail "(this character)"; on a tailor it's left alone once the Tailoring window has been opened
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
- [ ] 5.38 Mailbox with Posty Forever (or Postal) and its Express module on, in the **default bags** (Express only hooks those): open the Send Mail page and Alt+Left-click an unmarked item: if Express attaches it, its mark stays unchanged (chat says once that Alt+Left-click belongs to Express there); if Express attaches nothing on this client, Custodian changes the mark as usual, so the click is never dead. In a bag addon (ArkInventory, Bagnon...) Alt+Left-click at the mailbox always changes the mark. Alt+Right-click still changes marks everywhere; with Express turned off in Posty's options, Alt+Left-click at the mailbox changes the mark as usual
- [ ] 5.39 Profession tools: put a Fishing Pole (and, if you have them, a Mining Pick, Blacksmith Hammer or Skinning Knife) in your bags: it isn't auto-marked Junk (no coin icon); a fishing pole that 1.0.0 had auto-marked Junk is unmarked after logging in on this build
- [ ] 5.40 Chat: on a fresh install (or with `/soc chat off`) looting a gray item marks it with no "Marked as" line in chat, and selling a Locked item shows the red error on screen but no chat line; `/soc log` lists both. `/soc chat on` (or Chat in the advanced options of `/soc settings`) brings those lines back to chat; Alt+Click replies ("... is now Locked.") follow the same switch (log only when off), while typed commands such as `/soc lock <item>` always answer in chat
- [ ] 5.41 Alt+Click sequence, the Quick loop (a new install, or `/soc click loop`): Alt+Left-click a Normal item: Junk, then Locked, then Mail, then no mark again; Alt+Right-click on any mark takes it off. `/soc click dial`: Alt+Left-click protects more and stops at Always on me ("... is already ..."), Alt+Right-click protects less and stops at Junk. `/soc click order lock junk`: Alt+Left-click goes Locked, then Junk. With Standing Orders: Vendor installed and selling Junk by itself, that order prints an orange warning (also under the sequence in `/soc settings`, and once at the next login), and an Alt+Left-click from Locked to Junk says Vendor will sell it. `/soc click loop` to finish
- [ ] 5.42 Unusable soulbound gear, with `/soc why <item>` (shift-click any item link: from chat, the auction house or a vendor; you don't need to own it). On a cloth class (Mage, Priest, Warlock): `/soc why` a plate or mail armor piece says "this class can't use it" and that the rule is off; `/soc why` a cloth piece says it's left alone; `/soc why` a weapon type the class can train (a staff) says left alone, one it can't (a two-handed axe) says "can't use it"; an item whose required level is more than 5 above yours says "not usable for 5+ levels". Turn the rule on (`/soc settings` > Show advanced options > More auto-marks > Soulbound gear this character can't use) and the "rule is off" note goes away. On a character with Enchanting, a green or blue unusable piece says it stays Normal to disenchant. If you happen to have a soulbound piece this class can't use in your bags, it becomes Junk "(this character)" once the rule is on
- [ ] 5.43 Mark menu: `/soc settings` > Show advanced options > "Alt+Click opens a menu to pick the mark instead" (or `/soc altclick menu`): Alt+Left-click and Alt+Right-click on an item open a small menu right next to the item (like a right-click menu, and always on the screen) with the item's name, the levels with icons (its own mark ticked; Always on me with the advanced options shown, in your sequence, or as the item's mark) and "This character only"; clicking a level sets it and closes the menu, and clicking the ticked one again takes the mark off; Esc or the X closes it without a change; the item isn't picked up. `/soc mark <shift-clicked item>` opens the same menu. Ticking "Alt+Click moves the mark along a sequence" again brings the sequence back
- [ ] 5.44 Marked items window: `/soc list` (or Marked items in `/soc settings`) opens it: your marked items, most protected first, then the items in your bags; typing in the search box narrows the list with each letter (try part of an item name, then "locked"); shift-clicking an item in your bags (or a chat link) while the window is open, or dragging an item onto the search box, searches for that item, and a dragged item goes back to your bags; each row has a This character dropdown (starting at Account default), an All characters dropdown and the Mark that counts: set All characters to Locked and Mark says Locked (and the bag icon follows); set This character to Junk and Mark says Junk while All characters stays Locked (your other characters still see Locked); set This character back to Account default and Mark is Locked again; an item in an equipment set shows "(set)" next to its Mark; a row stays where it is when you change its mark, and Re-sort (or closing and opening the window) puts the most protected first again; unticking Items in my bags leaves only marked items; hovering a row shows the item's tooltip; Esc closes the window
- [ ] 5.45 Upgrade from 1.0.0 (during 2.1.8): Alt+Click still works like 1.0.0 (the Protection dial); once the intro is closed (or right away when it doesn't show), a popup offers the Quick loop. Keep mine leaves your clicks, Switch changes to the Quick loop (`/soc click` says which), and either way it doesn't come back after a /reload
- [ ] 5.46 Simple and advanced options: on a new install `/soc settings` shows how Alt+Click works, Gray items become Junk, the two buttons and Show advanced options ("All advanced options are at their simple defaults.", Back to simple greyed out). Ticking Show advanced options shows the rest (Alt+Click sequence, More auto-marks, New marks, Chat, Mark icons, Equipment sets); unticking hides them and changes nothing. Turn on Chat: the simple page names it; Back to simple asks (naming it), then Chat is off again and your marks are unchanged
- [ ] 5.47 The sequence editor (Show advanced options > Alt+Click sequence): Up and Down move a mark, the box takes a mark out or puts it back (Normal can't be taken out), the dropdown says Custom after a change, and picking Quick loop or Protection dial brings a preset back; "Alt+Right-click goes back one step" and "Loop around at the ends" change what Alt+Click does at once; the note at the top of the page always says how Alt+Click works now
- [ ] 5.48 New install (during 2.1.4): only gray items are auto-marked; the mark menu (`/soc mark <item>`) and the intro's short view offer Junk, Mail, Normal and Locked, and Always on me only after Show advanced options is ticked
- [ ] 5.49 Mark icon styles: `/soc icon compare` opens Mark icon styles with Junk, Mail, Locked and Always on me over items from your bags in two columns, Game icons and Addon icons (no green missing-texture squares); Game icons (the default) show the letter and key without their painted border, with a thin dark edge; Use under Addon icons puts Custodian's badges on your bag items at once (and in the mark menu and the intro); Style under Mark icons (advanced options) offers the same two; `/soc icon reset` goes back to Game icons
- [ ] 5.50 Disenchant mark: with Show advanced options ticked, `/soc mark <item>` and the Marked items window offer Disenchant (between Junk and Mail, with the Disenchant spell's icon); `/soc disenchant <item>` (or `/soc de <item>`) marks it and the bag icon shows; at a vendor, selling it shows the red error "... is marked Disenchant. Disenchant it, or lower it to Junk to sell it" and it's bought straight back; disenchanting it works (no red cover, no block); with the advanced options hidden, the mark menu doesn't offer Disenchant unless the item has it; `/soc icon compare` shows a Disenchant row with a teal sparkle badge

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
- [ ] 8.3.1 Bagnonium (Combuctor's new name): `<env> profile only StandingOrders_Custodian Bagnonium BagBrother !BugGrabber BugSack` `auto executed · game closed`; full restart; in its bag window: Alt+Click marks an item and the icon shows, Disenchant targeting turns Locked slots red, `/soc status` lists Bagnonium as supported, and `/soc intro` shows Bagnonium (was Combuctor) in green with its own icon and a check at the end, on one line; no Custodian errors
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
