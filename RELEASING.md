# Releasing Faves

The release pipeline, start to finish. Claude runs it when you say you're ready to release.

1. **You:** "I'm ready to release (version X)."
2. **Claude:** applies the lessons below, from earlier mod releases.
3. **Claude:** gives you the task list (the checklist below, filled in for this version).
4. **Claude:** evaluates the Mechanic output (in-game self-test and Lua errors) as part of the checklist.
5. **Together:** reach a **green run**: `node tools/green.js --game` ends with `GREEN`, and the in-game checks in `TESTING.md` are done.
6. **Claude:** gives you the steps to deploy to CurseForge (and any other sites you choose).

## Lessons learned from earlier releases

| Lesson | Where it's enforced |
|---|---|
| No character, player or account names in anything public: code, docs, examples, commit messages, screenshots, the CurseForge description. The repo is under your real name. | `green.js` privacy check (it reads the names from your WTF folder, so they're never written down). Screenshots and store text: check by hand. |
| Commit and zip times are 00:00 UTC. Never merge with GitHub's button; fast-forward locally. | Post-commit hook; `green.js` checks unmerged commits; `release.ps1` dates zip entries. |
| The zip needs forward-slash paths and one top-level `Faves/` folder (PowerShell 5.1's `Compress-Archive` writes backslashes). | `release.ps1` |
| The version lives only in git tags (dev-routine: a `candidate/vX.Y.Z` per merged change, kept local; one pushed `vX.Y.Z` per release). The `.toc` says `@project-version@`; changes go under `## [Unreleased]` in `CHANGELOG.md`. | `green.js` version check; `install.ps1` and `release.ps1` fill the token |
| Tags are lightweight (`git tag vX.Y.Z`): an annotated tag, including the one `mech release` makes, records the real time. Push only the release tag, by name. | `pipeline.js released` |
| Add `## X-Curse-Project-ID` once the CurseForge project exists. | `green.js` warns until it's there |
| Only register events that exist on Forever; an unknown one stops the file loading. Use `pcall` for events that may not exist. | `tools/wowstub.lua` `KNOWN_EVENTS` (the smoke test fails on unknown ones) |
| WoW runs Lua 5.1: at most 60 upvalues per function and 200 locals per scope. The test VM is 5.3 and doesn't catch this. Faves is at about 160 file-level locals. | `tools/limits.js` |
| Read BugGrabber after a real play session. That's how the nil bag-slot error (123 hits) was found. | `green.js --game` |
| Mechanic is for development only: `OptionalDeps`, never `Dependencies`. Players won't have it. | `green.js` TOC check |

## Release checklist (step 3)

1. Pick the candidate: `pipeline.js candidates` (dev-routine; default the newest), then `pipeline.js prep <version>` runs the full suite in a clean checkout.
2. Offline: `node tools/green.js`. Fix every `FAIL`.
3. Install (`install.ps1`), then in game, with `!Mechanic` and `Mechanic` enabled (and BugSack/BugGrabber):
   1. `/reload`, then play through `TESTING.md` (open a GitHub issue with it as the body to tick it off).
   2. `/faves selftest`, or Mechanic's Tests tab → Faves → Run all.
   3. `/reload` so the game writes the results.
4. Mechanic output: `node tools/green.js --game`. Claude reads it and fixes what's red. Repeat from step 2 until it's `GREEN`.
5. Merge the release PR (fast-forward), switch to `main`, `node tools/green.js` once more.
6. Tag the candidate's commit on `main`: `pipeline.js released <version>` (a lightweight `v<version>`, local).
7. Build: `powershell -ExecutionPolicy Bypass -File ./release.ps1` → `dist/Faves-<version>.zip` and the release notes. Open the zip and check: one `Faves/` folder holding `Faves.toc` (with the version filled in), `Faves.lua` and `LICENSE.txt`.
8. After your go-ahead: `git push origin v<version>` (only this tag, by name).

## What "Mechanic output" means here

- **In-game (installed):** `!Mechanic`/`Mechanic` show Faves under Tests (the self-test checks), Console (the guard log) and Errors (BugGrabber). Faves registers only when Mechanic is loaded; without it nothing changes for players.
- **Saved to disk:** `/faves selftest` saves its results in `FavesDB.selfTest`. `green.js --game` reads that, `!BugGrabber.lua` and `!Mechanic.lua` from `WTF\Account\<account>\SavedVariables` after a `/reload`.
- **Mechanic's desktop CLI and MCP (`mech`)** aren't installed on this PC (they need Python 3.10+). If you add them, its `addon.validate`, `addon.lint` (uses `.luacheckrc`) and `addon.output` steps slot into checklist steps 2 and 4.

## Deploy (step 6)

### CurseForge
First release only:
1. Go to authors.curseforge.com → Create Project → World of Warcraft → Addon.
2. Fill it in:
   - **Name:** Faves.
   - **Summary:** the `.toc` Notes line.
   - **Description:** adapted from `README.md`, with no character names.
   - **Category:** Bags & Inventory.
   - **License:** MIT.
   - **Logo:** 400×400.
   - **Source:** `https://github.com/MatthewSokol/Faves` (only if the repo is public).
3. Copy the project ID into `Faves/Faves.toc` as `## X-Curse-Project-ID: <id>`. Commit that, then rebuild the zip.

Every release:
1. Project → Files → Upload File → `dist/Faves-<version>.zip`.
2. Set the details:
   - **Display name:** `Faves <version>`.
   - **Release type:** Release (or Beta).
   - **Game version:** the WoW Forever / Interface 16001 entry.
   - **Changelog:** paste this version's `CHANGELOG.md` entry, as Markdown.
3. Wait for approval (usually minutes to hours), then install it from the CurseForge app on a clean profile and `/reload` once.

### Other sites (if you choose them)
- **GitHub release:** `gh release create v<version> dist/Faves-<version>.zip --notes-file <changelog entry>`. Only if the repo is public.
- **Wago Addons** (addons.wago.io → Developer): create the project, then add `## X-Wago-ID: <id>` to the `.toc` and upload the same zip.
- **WoWInterface:** Upload → new addon. Uses the same zip and changelog.
