# Changelog

## 1.0.0

First release. Item protection used to be part of SellAll; it's now its own addon so it works with any vendor addon.

- **Item levels**, for all your characters or just one (Alt+Shift+Left-click an item to switch, `/faves scope` for the default):
  - **Junk** marks items you're happy to lose (SellAll sells them when a vendor opens).
  - **Mail** marks items to send to your bank character.
- **Auto-marks**, each one switchable in `/faves settings`: grays and white gear with no profession or quest use become Junk; crafting materials and unbound BoE items become Mail. Items traded to you, bought (AH or vendor) or mailed to you by a player are left alone.
- **Crafting materials follow your professions:** they're marked Mail only on characters whose known recipes don't use them (read from each profession window), and never for enchanting materials.
- **Per-character items:** consumables, reagents and vendor trade goods (thread, vials, flux, dyes...) are never auto-marked, and marking one marks it for that character only.
  - **Normal** is the default.
  - **Confirm** currently acts as Locked.
  - **Locked** is protected from everything below.
  - **Always on me** is Locked and also stays out of the bank.

  Alt+Left-click an item in your bags to make it more protected, Alt+Right-click to make it less protected. Bag icons and a tooltip line show each item's level.
- **Guards** for every action that would lose a Locked item:
  - Vendor: a Locked item sold any way is bought straight back.
  - Disenchant, Prospecting, Milling: protected bag slots turn red and the click is blocked.
  - Destroy: the delete popup closes.
  - Trade and mail: the item is removed from the window.
  - Bank (Always on me only): the item is moved straight back to your bags.
- **One-time intro** listing what protection covers and what it doesn't yet (`/faves intro` reopens it).
- Levels set in earlier SellAll test builds are brought over automatically.
- `Faves.IsLocked`, `Faves.GetLevel` and `Faves.Guard` for other addons.

**Known limits:**
- Auction house posting isn't guarded yet.
- Alt+Click, bag icons and the disenchant guard only work in the default bags, not ArkInventory.
