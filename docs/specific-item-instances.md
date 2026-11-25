# Marking one specific copy of an item

**Status (2026-11-25):** built for 1.2.0 in #56 (Copies.lua, CopyTrack.lua). The in-game check below (the GUID lasts a logout) is `TESTING.md` 5.52; if it fails, the marks are kept rather than cleaned up (CopyTrack.lua logs it).

**Question:** can Custodian protect *this* Deviate Scale Cloak while other copies of the same cloak stay unmarked?

**Short answer:** probably yes, using the item's GUID. It works cleanly for everything that happens in your bags and bank, and needs workarounds for buyback, trade and mail. One in-game check has to pass first: the GUID must stay the same across logouts and moves on WoW Forever.

## How to tell two copies apart

| Approach | Tells copies apart? | Notes |
|---|---|---|
| Item ID (what Custodian uses now) | No | Every Deviate Scale Cloak has the same ID |
| Item link (enchant, random suffix like "of the Bear", gems, crafter) | Only different *variants* | Two plain cloaks have identical links. An enchanted one could be told apart, but the mark would break if you change the enchant |
| Bag position (bag and slot) | Only until something moves | Sorting, banking or looting can move it, so it can't be relied on |
| **Item GUID**: `C_Item.GetItemGUID(ItemLocation)` | **Yes** | The server gives every copy its own ID. The API exists on this client: ForeverFishing already calls it on interface 16001 |

## What each guard would need

A copy mark only helps if each guard can tell *which* copy is involved.

| Guard | Can it see the copy? | How |
|---|---|---|
| Bag icons, Alt+Click, bag tooltips | Yes | Bag button, then its `ItemLocation`, then the GUID |
| Sell All / Up to / Junk (Standing Orders: Vendor) | Yes | Standing Orders: Vendor scans bag slots, so it can check each copy's GUID before selling |
| Disenchant / Prospect / Mill blocker | Yes | The red cover sits on one bag slot |
| Destroy | Likely | `C_Cursor.GetCursorItem()` should give the location of the item being held. Needs checking |
| Bank (Always on me) | Yes | Bank slots have item locations too |
| Vendor buyback (right-click selling) | **Not directly** | The buyback list only gives links. Workaround: remember which bag slot held the marked copy. When it disappears and the same item ID shows up in buyback, buy back the newest one. Usually right, but not guaranteed |
| Trade / mail | **Not directly** | Trade and mail slots only give links. Workaround: snapshot bag GUIDs before. When an item goes into the window, the marked copy missing from the bags means it was that one |
| Tooltips outside bags (chat links, loot window) | No | No copy to look at. These would show the item-ID level only |

## How it could work

- **Storage:** `StandingOrdersCustodianDB.copies[guid] = { id = itemID, level = level }`. A copy mark wins over the item-ID mark, which already loses to a character mark.
- **Marking:** Ctrl+Alt+Click marks just that copy. The tooltip and bag icon show "(this copy)".
- **Cleanup:** remember when each marked copy was last seen in your bags or bank, and drop marks not seen for 30 days (sold, destroyed or traded away).
- **Cost:** about a day of work, plus testing. Most of it is the buyback, trade and mail workarounds.

## Check to run first

GUIDs are stable on retail while the item exists. Nobody has checked that on WoW Forever yet. In game:

1. Put the cloak in the first slot of your backpack, then run:
   `/dump C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(0, 1))`
2. Note the value. Then log out and back in, move the cloak to another bag, put it in the bank and take it out again, and dump it again each time. It should never change.
3. Optional: mail it to an alt and back, and check whether it's still the same.

**Verdict:** it's worth doing if step 2 holds. If the GUID changes on logout, copy marks aren't practical.
