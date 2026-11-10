# Changelog

## 1.0.0

First release. Item protection used to be part of SellAll; it's now its own addon so it works with any vendor addon.

- **Item levels**, shared across your characters:
  - **Junk** marks items you're happy to lose (SellAll sells them when a vendor opens).
  - **Normal** is the default.
  - **Confirm** currently acts as Locked.
  - **Locked** is protected from everything below.

  Alt+Left-click an item in your bags to make it more protected, Alt+Right-click to make it less protected. Bag icons and a tooltip line show each item's level.
- **Guards** for every action that would lose a Locked item:
  - Vendor: a Locked item sold any way is bought straight back.
  - Disenchant, Prospecting, Milling: protected bag slots turn red and the click is blocked.
  - Destroy: the delete popup closes.
  - Trade and mail: the item is removed from the window.
- **One-time intro** listing what protection covers and what it doesn't yet (`/faves intro` reopens it).
- Levels set in earlier SellAll test builds are brought over automatically.
- `Faves.IsLocked`, `Faves.GetLevel` and `Faves.Guard` for other addons.

**Known limits:**
- Auction house posting isn't guarded yet.
- Alt+Click, bag icons and the disenchant guard only work in the default bags, not ArkInventory.
