# Faves

A World of Warcraft **Forever** addon (interface 16001). Mark the items you care about, and Faves stops you losing them by accident: selling, disenchanting, destroying, trading or mailing them.

Pairs with [SellAll](https://github.com/MatthewSokol/SellAll), a one-click Sell All button that skips everything Faves protects. Faves works fine on its own, too: it protects against any vendor addon or a stray right-click.

## Item levels

Levels are per item ID and shared across all your characters.

| Level | Icon | What happens |
|---|---|---|
| Junk | coin | Safe to lose. SellAll sells these automatically when a vendor opens |
| Normal | none | The default |
| Confirm | star | Levelling favorite. Meant to ask before it's lost; until that window exists it acts as **Locked** |
| Locked | key | Never sold, disenchanted, destroyed, traded or mailed |

Change a level with **Alt+Left-click** in your bags (more protected) or **Alt+Right-click** (less protected). You can also use `/faves junk|normal|confirm|lock <shift-clicked item or ID>`. `/faves list` shows every marked item. Item tooltips show the level.

## Guards

Every action that would lose an item goes through one check, `Faves.Guard(itemID, link, action)`. When the item is Confirm or Locked, the action is blocked and you see *"… is Locked. Unfavorite it to … it"*.

| Action | How it's blocked |
|---|---|
| Vendor | Anything that sells it (right-click, dragging it to the vendor, any addon's auto-sell) is **bought straight back** |
| Disenchant / Prospect / Mill | While the spell's targeting cursor is up, protected bag slots are covered in red and the click is blocked |
| Destroy | The delete confirmation is closed and the item goes back to your bag |
| Trade | The item is taken back out of the trade window |
| Mail | The attachment is removed |

**Limits:** Alt+Click, bag icons and the disenchant guard only work in the default bags (not ArkInventory). The vendor, destroy, trade and mail guards work everywhere. Auction house posting isn't guarded yet.

## For addon authors

```lua
if Faves and Faves.IsLocked(itemID) then --[[ skip it ]] end
if Faves and Faves.Guard(itemID, link, "disenchant") then return end -- shows the error for you
local level = Faves and Faves.GetLevel(itemID) -- Faves.LEVELS.JUNK / NORMAL / CONFIRM / LOCK
```

## Commands

`/faves help`, `/faves intro` (what protection covers, also shown once on first login), `/faves status` (which guards are active), `/faves log` (recent guard decisions), `/faves debug`.
