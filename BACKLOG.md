# Backlog

Work to pick from. One line per item: `- [ ] **Title:** what and why (source; level)`.

## Inbox

## Next

**1.2.0 (user's pick 2026-11-23): the Disenchant tier and per-copy marks.** Built in this order, one PR each:

- [ ] 1 **Disenchant level** (the item below, without the option and the button).
- [x] 2 **Treat Disenchant marks as Mail:** nothing to build in Custodian. Standing Orders: Mail already reads `LEVELS.DISENCHANT` and mails Disenchant items like Mail (to the enchanter's route or the bank), except from a character with Enchanting, which keeps them. An off/always switch, if wanted, belongs in Mail's settings.
- [ ] 3 **Per-copy marks, data and guards:** besides the item's mark, an item can have a mark for its **bound copies** and marks for copies **with a given enchant**. A copy's mark is: its enchant's mark if it has one, else the bound-copies mark if this copy is bound, else the item's mark (this character's before all characters', as now). Stored next to the item marks (`items` in the account and character data stays as is; per-copy marks go in a new `copies` table keyed by item ID: `{ bound = level, ench = { [enchantID] = level } }`), so 1.1.0 data needs no migration. Every guard already has the link (it carries the enchant); bound status comes from `C_Item.IsBound(ItemLocation)` for bag slots (disenchant, destroy, bank) and from the buyback tooltip's "Soulbound" line for the sell guard. Bound items can't be traded or mailed, so those guards only need the enchant. `GetLevel(id)` keeps meaning the item's mark for other addons; a new `GetCopyLevel(bag, slot)` / `GetLinkLevel(link, bound)` gives a copy's. Bag icons and tooltips show the copy's mark.
- [ ] 4 **Per-copy marks, UI:** the mark menu gets "Bound copies only" (for a bound item) and "Copies with this enchant only" (for an enchanted one); the Marked items window shows each item's per-copy marks as rows under it ("bound copies", "with <enchant>"), with the same columns; `/soc <level> <item> bound` and `/soc <level> <shift-clicked enchanted item> enchant`.
- [ ] 5 Optional, if time allows: the **Disenchant next** button described below.

- [ ] **Junk (disenchant), a second junk tier, for 1.2.0:** today's Junk means "vendor it". A new mark, Disenchant (shown as "Junk (disenchant)", between Junk and Mail), is for gear to disenchant: **protected from vendoring** (bought straight back, like Locked; Standing Orders: Vendor never sells it, so check Vendor compares against `LEVELS.JUNK` exactly, not `<= MAIL`), but **free to disenchant and to mail**. Needs: a level value (e.g. 1.25) and name, a game icon (the Disenchant spell's) and an addon badge (`tools/badges.js`), a place in the mark menu, the Marked items columns, the Alt+Click presets and the sequence editor, the intro, `/soc disenchant <item>`, the API docs. Advanced option **"Treat Disenchant marks as Mail"** so Standing Orders: Mail sends them to the enchanter (probably: off, on characters without Enchanting, always). Optional, careful with the game's terms: a **"Disenchant next"** button (`SecureActionButtonTemplate`, type macro, macrotext `/cast Disenchant` + `/use <bag> <slot>` for the first Disenchant-marked item, refreshed out of combat on BAG_UPDATE_DELAYED) that players bind to a key or call with `/click`: one keypress, one disenchant, no loop, no timer, never in combat; the same one-hardware-event-per-action rule as buying. More than one test step, so not in 1.1.0 (user request 2026-11-23, release testing; level: minor)

- [ ] **Screenshots:** the main features (levels and icons in bags, the settings panel, the intro, a guard message) in `docs/screenshots/`, every name hidden; then show them in the README (wow-mod-dev ground rule 4; level: none)
- [ ] **CurseForge project:** create it and add `## X-Curse-Project-ID` to the .toc (release prep; level: none)
- [ ] **Test journal:** log self-test results and key events (an auto-mark, a buyback, a bank move) with the build version and checklist step ids in StandingOrdersCustodianDB, so the gate can tick those rows (wow-mod-dev; level: none)

## Later

- [ ] **Light Feathers still auto-marked Mail, and its retest (TESTING.md 5.19):** found in release testing 2026-11-20: one character's saved data still had Light Feather (17056) in `items` and `autoMarked` as Mail "(this character)" after logging in on a build with the #27 cleanup. The cleanup and the "never auto-marked" rule both go by item class (`KS.IsPersonal`: consumable, reagent, or a known vendor trade good), and this client apparently doesn't class Light Feather as a reagent, so the crafting-materials rule marks it Mail again on characters with no matching profession; Standing Orders: Mail would then send a mage's feathers away. Fix: a built-in list of class reagents (Light Feather, Ankh, Rune of Teleportation/Portals, Holy/Sacred Candle, Arcane Powder, Symbol of Divinity, druid seeds and berries, Flash/Blinding Powder, Soul Shard, Infernal Stone, Demonic Figurine, Fish Oil, Shiny Fish Scales...) that `IsPersonal` treats as per character whatever their class, plus a smoke check with Light Feather reported as a trade good. Retest needs Light Feathers in a character's bags (deferred on the user's word: farming them for the test isn't worth holding the release) (release testing; level: patch)

- [ ] **Confirm (temp hold), back from the first release:** held back on 2026-11-20 because "Allow once" didn't let a sale through in testing, even after allowing (TESTING.md 5.9), and allowing a mail let another copy through without asking (5.12). Find why the allowed sale is still bought back (the pass vs. the buyback guard's timing), make the pass cover one item, not its item ID, then set `CONFIRM_ENABLED = true` in Custodian.lua: the menus, Alt+Click, `/soc confirm`, the hold window and the smoke checks all come back with it, and saved Confirm marks return as they were. Retest TESTING.md 5.9-5.12 and RELEASING 2.2.8.3 (user decision 2026-11-20, release testing; level: minor)

- [ ] **Marks in offline bag views:** bag addons' views of another character's bags and of your bank away from a banker (Bagnon/BagBrother, Baganator, ArkInventory) show no mark icons and ignore Alt+Click today; the adapters skip cached buttons. Showing icons and the tooltip line there (read-only) helps plan an alt's cleanup without logging it in. Alt+Click there could set account-wide marks, which are item-ID based and safe; it needs a clear rule for "(this character)" marks, which live in the other character's per-character saved data and can't be written from here: refuse with a chat line, or keep per-character marks in the account data keyed by character. Today Alt+Click there does nothing at all, with no feedback (seen in release testing 2026-11-20, TESTING.md 8.2-8.4; level: minor)

- [ ] **Marks on one copy of an item (by GUID; 1.2.0 covers the common cases with bound-copy and enchant marks, so this waits for a case they miss):** protect "my" copy and leave the rest of the same item free, e.g. a Mooncloth Robe you wear and copies you craft to sell. The mark would key on the item's GUID (`C_Item.GetItemGUID` with an ItemLocation; AdiBags and Baganator already use it on Forever) instead of the item ID. A per-copy mark beats the item ID mark, and the vendor/destroy/trade/mail guards check the copy that moves. Check first that a GUID survives logout, the bank and the mail; it changes on a trade. Equipment sets have the same gap today: they protect by item ID, so a set item blocks selling every copy. Alt+Ctrl+Click could mark just this copy (user request 2026-11-20, after the first release; level: minor)

- [ ] **Protection per action:** choose for each level (or each item) what happens per action: vendor, destroy, disenchant, trade, mail, bank. For example, never sell but ask before disenchanting. Today a level sets them all at once (Confirm asks for all, Locked blocks all). Could be a matrix in `/soc settings` (level x action: allow, ask, block), or custom levels built from it (user request 2026-11-20, after the first release; level: minor)

- [ ] **Reagents by need:** at login and when a spell is learned (LEARNED_SPELL_IN_TAB / SPELLS_CHANGED), check which spell reagents this character uses (e.g. a mage with Slow Fall needs Light Feathers); reagents it has no spell for get Mail "(this character)" so they go to the bank alt, and ones it now needs lose that auto-mark. Needs a reagent -> spell table (or the spell tooltips) per class (user request 2026-11-20, after the first release; level: minor)

- [ ] **Always on me: a target quantity** (e.g. 20, or 1 stack): keep that many on you and let the rest go to the bank, mail or vendor; set per item (Alt+Click menu or `/soc onme <item> 20`) (user request 2026-11-20, after the first release; level: minor)

- [ ] **Choose which commands Custodian registers:** `/soc` and `/custodian` are both on by default; let each be switched off in `/soc settings` (keeping at least one on), so a player whose other addon wants `/soc` (Pocket Social - Forever uses `/social` or `/soc`) can give it up. A switched-off command must be removed from `SlashCmdList`/`hash_SlashCmdList` on the next login (or `/reload`), not left half registered (user request 2026-11-20, release testing; level: minor)

- [ ] **Test: VendorFlip's Disenchant button skips a Locked item** (TESTING.md 4.9): deferred from the first release on the user's word, 2026-11-20; it needs an EnchantFlip item (bought by hand) to test with. VendorFlip asks Standing Orders: Vendor, which reads Custodian's marks (release testing; level: none)


## Done

- [x] **Bagnon support** (and Combuctor, same core): Alt+Click, icons, disenchant blocker (level: minor)
- [x] **Baganator support** (level: minor)
- [x] **AdiBags support** (level: minor)
- [x] **BetterBags support** (level: minor)
- [x] **ElvUI bags support** (level: minor)
