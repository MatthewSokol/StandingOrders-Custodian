# Faves

A World of Warcraft **Forever** addon (interface 16001). Mark the items you care about, and Faves stops you losing them by accident: selling, disenchanting, destroying, trading or mailing them.

Pairs with [SellAll](https://github.com/MatthewSokol/SellAll), a one-click Sell All button that skips everything Faves protects. Faves works fine on its own, too: it protects against any vendor addon or a stray right-click.

## Item levels

Levels are per item ID. A mark applies to all your characters, or to one character only:

- **Alt+Shift+Left-click** an item to move its mark between all characters and this character only.
- `/faves scope char` makes new marks this-character-only by default (`/faves scope account` switches back). SellAll's settings panel has the same switch.
- A character's own mark wins over an account-wide one, so one character can treat an item differently (even as Normal).
- Tooltips and `/faves list` show *(this character)* for character marks.

| Level | Icon | What happens |
|---|---|---|
| Junk | coin | Safe to lose. SellAll sells these automatically when a vendor opens |
| Mail | letter | To send to your bank character (for a mailing addon). SellAll never sells these |
| Normal | none | The default |
| Confirm | star | Levelling favorite. Meant to ask before it's lost; until that window exists it acts as **Locked** |
| Locked | key | Never sold, disenchanted, destroyed, traded or mailed |
| Always on me | purple diamond | Locked, and also kept out of the bank: anything you put in the bank is moved straight back to your bags |

Change a level with **Alt+Left-click** in your bags (more protected) or **Alt+Right-click** (less protected). You can also use `/faves junk|mail|normal|confirm|lock|onme <shift-clicked item or ID> [char|account]`. `/faves list` shows every marked item. Item tooltips show the level.

## Auto-marks

New items in your bags are marked for you (all on by default; turn each off in `/faves settings`):

| Item | Becomes |
|---|---|
| Gray | Junk |
| White gear, weapons and junk with no profession or quest use | Junk |
| Crafting materials, white and up (cloth, herbs, ore, leather...) | Mail |
| Bind on Equip, green and up, not yet bound | Mail |

Quest items, food and drink, bags, ammo, recipes, keys, shirts and tabards are left alone, and so is anything VendorFlip is holding to flip. **Items you got on purpose are left alone** on the character that got them: traded to you, bought on the AH or from a vendor, or mailed to you by a player (your other characters included). If another character had already auto-marked one, it's Normal on this character.

Only unmarked items are marked, and each item only once: change an auto-marked item's level and it stays changed. Auto-marks apply to all your characters.

## Guards

Every action that would lose an item goes through one check, `Faves.Guard(itemID, link, action)`. When the item is Confirm or Locked, the action is blocked and you see *"… is Locked. Unfavorite it to … it"*.

| Action | How it's blocked |
|---|---|
| Vendor | Anything that sells it (right-click, dragging it to the vendor, any addon's auto-sell) is **bought straight back** |
| Disenchant / Prospect / Mill | While the spell's targeting cursor is up, protected bag slots are covered in red and the click is blocked |
| Destroy | The delete confirmation is closed and the item goes back to your bag |
| Trade | The item is taken back out of the trade window |
| Mail | The attachment is removed |
| Bank (Always on me only) | While the bank is open, the item is moved straight back to your bags (if they have room) |

**Limits:** Alt+Click, bag icons and the disenchant guard only work in the default bags (not ArkInventory). The vendor, destroy, trade and mail guards work everywhere. Auction house posting isn't guarded yet.

## Marking one specific copy of an item

Not supported yet: marks are per item ID, so every copy of an item shares a level. See [docs/specific-item-instances.md](docs/specific-item-instances.md) for what it would take.

## For addon authors

```lua
if Faves and Faves.IsLocked(itemID) then --[[ skip it ]] end
if Faves and Faves.Guard(itemID, link, "disenchant") then return end -- shows the error for you
local level = Faves and Faves.GetLevel(itemID) -- Faves.LEVELS.JUNK / MAIL / NORMAL / CONFIRM / LOCK / ONME
-- MAIL is 1.5 (between JUNK 1 and NORMAL 2), so compare with Faves.LEVELS, not with level + 1.
if Faves and Faves.GetLevel(itemID) == Faves.LEVELS.MAIL then --[[ send it to the bank character ]] end
```

## Commands

`/faves settings` (auto-marks and where new marks go), `/faves help`, `/faves intro` (what protection covers, also shown once on first login), `/faves status` (which guards are active), `/faves log` (recent guard decisions), `/faves debug`.
