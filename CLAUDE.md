# Faves

WoW **Forever** addon (interface 16001, modern `C_Container` and bag frame APIs). The addon lives in `Faves/`; `README.md` documents its features. SellAll (`C:\Users\Matt\code\SellAll`) and VendorFlip depend on its API.

## Workflow after every edit (always, without being asked)

1. **Check** (there's no Lua interpreter on this machine): at minimum verify blocks and brackets balance with `node tools/check.js Faves/Faves.lua`.
2. **Install:** `powershell -ExecutionPolicy Bypass -File ./install.ps1` installs into `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Faves`. Then verify each installed file with `diff --strip-trailing-cr -q`.
3. **Commit** on a feature/fix branch (not `main`), push, and open a PR or add to the open one. Update the PR title and description when its scope grows.
4. **Don't merge** until the user has tested in game and says it's good. Then merge, switch to `main`, pull, and confirm the installed copy matches.
5. **End every reply that changed the addon with "How to test"**: `/reload`, then concrete in-game steps and what should happen. Mention `/faves status` and `/faves debug` where they help.

## Notes

- Every action that would lose an item must go through `Faves.Guard(itemID, link, action)`. Add new guards (auction house, a future confirm window) there instead of writing separate checks.
- The public API (`GetLevel`, `IsLocked`, `Guard`, `LEVELS`, `ImportLevels`) is used by SellAll and VendorFlip: don't change it without updating them.
- Levels: Junk 1, Normal 2 (stored as nil), Confirm 3, Locked 4. Confirm acts as Locked until a confirm window is built.
- Don't replace Blizzard functions (`UseContainerItem`, `C_AuctionHouse.*`) to block actions: that taints them. Block before the action (PreClick, the red blocker over bag slots) or undo it afterwards (buyback, removing trade/mail items).
- Releases: `TESTING.md` is the pre-release checklist (open it as a GitHub issue to tick items off). `package.ps1` builds `dist/Faves-<version>.zip` from the `.toc` version; upload it to CurseForge with the `CHANGELOG.md` entry.
