# Bag addons

Most of Faves works with any bag addon: the vendor, destroy, trade, mail and bank guards, auto-marks, tooltips and the
`/faves <level> <item>` commands don't touch bag buttons. Three features need the bag addon's own item buttons:
**Alt+Click** to change a level, the **level icons**, and the **disenchant blocker** (the red cover over protected slots).

## Support today

| Bag addon | Alt+Click, icons, disenchant blocker | How |
|---|---|---|
| Blizzard bags (combined or separate) | Yes | Hooks `ContainerFrame*` item buttons |
| ArkInventory | Yes: bags and bank, live views only | Its public API: `ArkInventory.API.ItemFrameLoaded` / `ItemFrameUpdated`. Offline views (another character, the bank away from a banker) are left alone, and a button is only acted on when Ark's item matches the item in that bag slot. |
| Anything else | No (the other guards still work) | Planned, below |

## Plan: the next five

Ordered by how many players use them (CurseForge downloads) and how likely they are on Forever. Before starting
each one, install it on Forever and confirm it loads (interface 16001); if it has no Forever build, skip to the next.

| # | Bag addon | Likely hook (confirm against its current code) | Offline views to skip |
|---|---|---|---|
| 1 | **Bagnon** (and Combuctor, same core) | Its item button class: hook its update method; buttons know their bag and slot | Cached (other character) views |
| 2 | **Baganator** | Its public API (corner widgets for the icon) plus a hook on its item buttons for clicks | Other characters' bags, the bank when closed |
| 3 | **AdiBags** | Its per-button update message (`AdiBags_UpdateButton`); buttons carry bag and slot | Bank when closed |
| 4 | **BetterBags** | Its item button module's update; check its plugin API first | Bank when closed |
| 5 | **ElvUI bags** | Its bags module's slot update (`B:UpdateSlot`); buttons carry bag and slot IDs | Only when ElvUI's bags module is on |

Each one becomes an **adapter** next to the ArkInventory one: detect the addon, hook its buttons (`HookButton`,
`UpdateButton`), and answer "which bag and slot is this, and is the view live?" (`ArkSlot` is the model). Rules for
every adapter:

- Optional: only when that addon is loaded, wrapped in `pcall`, never a dependency.
- Never act on an offline or cached view, and check the shown item against the real bag slot before acting.
- Never replace the addon's functions: hook them (`hooksecurefunc`, `HookScript`), like the default bags.
- A smoke-test stub of its API, like `ArkInventory` in `tools/smoke.lua`, with live, offline and mismatched cases.
- A row in `TESTING.md` and in the table above.

When the second adapter lands, move the ArkInventory code into the same adapter shape so all of them share it.
