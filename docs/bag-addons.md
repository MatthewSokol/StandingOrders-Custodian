# Bag addons

Most of Quartermaster works with any bag addon: the vendor, destroy, trade, mail and bank guards, auto-marks, equipment sets,
tooltips and the `/soq <level> <item>` commands don't touch bag buttons. Three features need the bag addon's own item
buttons: **Alt+Click** to change a level, the **level icons**, and the **disenchant blocker** (the red cover over
protected slots). `/soq status` lists the bag addons Quartermaster has hooked.

## Support

| Bag addon | How Quartermaster finds its buttons | Views left alone |
|---|---|---|
| Blizzard bags (combined or separate) | `ContainerFrame*` item buttons | (none: always live) |
| ArkInventory | Its public API: `ArkInventory.API.ItemFrameLoaded` / `ItemFrameUpdated` (bag and bank windows) | Offline views (another character, the bank away from a banker); a button whose item doesn't match its slot |
| Bagnon, Combuctor | `Item:Update` on its BagBrother item class; `GetBag()` / `GetID()` | `IsCached()` views (another character, the bank away from a banker) |
| Baganator | Its live-button mixins' `SetItemDetails` (hooked while Quartermaster loads); the parent's ID is the bag | Cached views use other buttons and never reach Quartermaster; the shown item must match the slot |
| AdiBags | The `AdiBags_UpdateButton` message on its `ABEvent-1.0` library; `button.bag` / `button.slot` | Bank buttons while the bank is closed |
| BetterBags | The `item/Updated` message on its Events module; `item.currentData` bag and slot | Bank slots while the bank is closed; a button whose item doesn't match its slot |
| ElvUI bags (with its bags module on) | `B:UpdateSlot(frame, bagID, slotID)`; `slot.BagID` / `slot.SlotID` | The bank frame while the bank is closed |

All of them were checked against the Forever builds (interface 16001) installed at the time; the smoke test
(`tools/smoke.lua`) has a stub of each with live, closed-bank and stale cases.

**Alt+Click is shared** with some of them, and both things happen: Bagnon's flash find and Baganator's "highlight
similar items" also react to Alt+Click, and so does AuctionDB's price graph in any bag.

## Adding another bag addon

Each one is an **adapter** in `Quartermaster/Adapters.lua`: `KS.AddBagAddon({ name, loaded, hook, slot })`. `loaded()` says
whether the addon is there, `hook(add)` hooks its buttons and hands each one to `add`, and `slot(btn)` answers which
real bag and slot the button shows, or nothing. Rules:

- Optional: only when that addon is loaded; a failing adapter switches itself off (Quartermaster wraps it in `pcall`). Never a
  dependency.
- Never act on an offline or cached view, and where the addon tells you which item a button shows, check it against
  the real bag slot.
- Never replace the addon's functions: hook them (`hooksecurefunc`, its own messages), like the default bags.
- A smoke-test stub of its API, with live, offline and mismatched cases.
- A row in the table above and a pass in `TESTING.md` (section 8).
