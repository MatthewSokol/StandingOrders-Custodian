# Faves

WoW **Forever** addon (interface 16001, modern `C_Container` and bag frame APIs). The addon lives in `Faves/`; `README.md` documents its features. SellAll (`C:\Users\Matt\code\SellAll`) and VendorFlip depend on its API.

## Workflow after every edit (always, without being asked)

Pipeline: .devroutine/pipeline.json, run with the dev-routine skill (`pipeline.js loop` runs the check, test, install and verify steps below). Mechanics come from the wow-mod-dev skill; bugs go through wow-mod-debug.

1. **Check** (there's no Lua interpreter on this machine): `node tools/green.js` must end with `GREEN`. It runs the bracket check, the Lua 5.1 limits check (60 upvalues, 200 locals), the chat pipes check (a bare `|` in chat text is a WoW escape such as `|n` or `|c`: write `||`, or end the line with `-- pipes:ok` when it's a real escape or a pattern), the TOC and version checks, the smoke test (`tools/smoke.lua`: Faves loaded in a Lua VM with the stubbed API in `tools/wowstub.lua`), and a privacy scan. Extend `smoke.lua` and `wowstub.lua` when adding features. Only register events that exist on Forever (add them to `KNOWN_EVENTS` after checking), or register them with `pcall`.
2. **Install:** `powershell -ExecutionPolicy Bypass -File ./install.ps1` installs into `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Faves`. Then verify with `node ~/.claude/skills/wow-mod-dev/scripts/install.js --verify` (it ignores the .toc Version line, which the install fills in from `git describe`).
3. **Commit** on a feature/fix branch (not `main`), push, and open a PR or add to the open one. Update the PR title and description when its scope grows.
4. **Don't merge** until the user has tested in game and says it's good. Then merge, switch to `main`, pull, and confirm the installed copy matches.
5. **End every reply that changed the addon with "How to test"**: `/reload`, then concrete in-game steps and what should happen. Mention `/soq status`, `/soq selftest` and `/soq debug` where they help. After the user reloads, `node tools/green.js --game` reads the self-test results and any Faves Lua errors from SavedVariables.

## Notes

- Every action that would lose an item must go through `Faves.Guard(itemID, link, action)`. Add new guards (auction house, a future confirm window) there instead of writing separate checks.
- The public API (`GetLevel`, `IsLocked`, `Guard`, `LEVELS`, `ImportLevels`) is used by SellAll and VendorFlip: don't change it without updating them.
- Levels: Junk 1, Mail 1.5, Normal 2 (stored as nil), Confirm 3, Locked 4, Always on me 5. Confirm ("temp hold") is stopped like Locked, then Guard opens a window offering a one-time pass (`UsePass`); never let the pass redo the action itself. SellAll compares against the numbers 2 and 3, so never renumber.
- Don't replace Blizzard functions (`UseContainerItem`, `C_AuctionHouse.*`) to block actions: that taints them. Block before the action (PreClick, the red blocker over bag slots) or undo it afterwards (buyback, removing trade/mail items).
- **Mechanic** (the in-game dev tool, `!Mechanic` + `Mechanic`) is optional: `## OptionalDeps` only, never a dependency, since players won't have it. When it's loaded, Faves registers its self-tests (Tests tab), guard log (Console) and debug setting, and runs the self-tests once at login, so every session's results are saved for `green.js --game`. MechanicLib's `tests.runAll` must return `passed, total`. Keep the self-tests in the "Self-tests and Mechanic" section read-only.
- **Releases:** follow `RELEASING.md` (the pipeline: lessons learned → task list → Mechanic output → green run → deploy steps). `TESTING.md` is the in-game checklist; `release.ps1` builds `dist/Faves-<version>.zip`.
- Test tools need fengari once: `cd tools && npm install` (`node_modules` is ignored by git).
