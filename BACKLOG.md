# Backlog

Work to pick from. One line per item: `- [ ] **Title:** what and why (source; level)`.

## Inbox

## Next

- [ ] **Screenshots:** the main features (levels and icons in bags, the settings panel, the intro, a guard message) in `docs/screenshots/`, every name hidden; then show them in the README (wow-mod-dev ground rule 4; level: none)
- [ ] **CurseForge project:** create it and add `## X-Curse-Project-ID` to the .toc (release prep; level: none)
- [ ] **Test journal:** log self-test results and key events (an auto-mark, a buyback, a bank move) with the build version and checklist step ids in StandingOrdersQuartermasterDB, so the gate can tick those rows (wow-mod-dev; level: none)

## Later

- [ ] **Marks in offline bag views:** bag addons' views of another character's bags and of your bank away from a banker (Bagnon/BagBrother, Baganator, ArkInventory) show no mark icons and ignore Alt+Click today; the adapters skip cached buttons. Showing icons and the tooltip line there (read-only) helps plan an alt's cleanup without logging it in. Alt+Click there could set account-wide marks, which are item-ID based and safe; it needs a clear rule for "(this character)" marks, which live in the other character's per-character saved data and can't be written from here: refuse with a chat line, or keep per-character marks in the account data keyed by character. Today Alt+Click there does nothing at all, with no feedback (seen in release testing 2026-11-20, TESTING.md 8.2-8.4; level: minor)

- [ ] **Marks on one copy of an item:** protect "my" copy and leave the rest of the same item free, e.g. a Mooncloth Robe you wear and copies you craft to sell. The mark would key on the item's GUID (`C_Item.GetItemGUID` with an ItemLocation; AdiBags and Baganator already use it on Forever) instead of the item ID. A per-copy mark beats the item ID mark, and the vendor/destroy/trade/mail guards check the copy that moves. Check first that a GUID survives logout, the bank and the mail; it changes on a trade. Equipment sets have the same gap today: they protect by item ID, so a set item blocks selling every copy. Alt+Ctrl+Click could mark just this copy (user request 2026-11-20, after the first release; level: minor)

- [ ] **Protection per action:** choose for each level (or each item) what happens per action: vendor, destroy, disenchant, trade, mail, bank. For example, never sell but ask before disenchanting. Today a level sets them all at once (Confirm asks for all, Locked blocks all). Could be a matrix in `/soq settings` (level x action: allow, ask, block), or custom levels built from it (user request 2026-11-20, after the first release; level: minor)

- [ ] **Reagents by need:** at login and when a spell is learned (LEARNED_SPELL_IN_TAB / SPELLS_CHANGED), check which spell reagents this character uses (e.g. a mage with Slow Fall needs Light Feathers); reagents it has no spell for get Mail "(this character)" so they go to the bank alt, and ones it now needs lose that auto-mark. Needs a reagent -> spell table (or the spell tooltips) per class (user request 2026-11-20, after the first release; level: minor)

- [ ] **Always on me: a target quantity** (e.g. 20, or 1 stack): keep that many on you and let the rest go to the bank, mail or vendor; set per item (Alt+Click menu or `/soq onme <item> 20`) (user request 2026-11-20, after the first release; level: minor)

- [ ] **Test: VendorFlip's Disenchant button skips a Locked item** (TESTING.md 4.9): deferred from the first release on the user's word, 2026-11-20; it needs an EnchantFlip item (bought by hand) to test with. VendorFlip asks Standing Orders: Vendor, which reads Quartermaster's marks (release testing; level: none)


## Done

- [x] **Bagnon support** (and Combuctor, same core): Alt+Click, icons, disenchant blocker (level: minor)
- [x] **Baganator support** (level: minor)
- [x] **AdiBags support** (level: minor)
- [x] **BetterBags support** (level: minor)
- [x] **ElvUI bags support** (level: minor)
