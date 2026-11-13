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
| Mechanic is for development only: `OptionalDeps`, never `Dependencies`. Players won't have it. | `green.js` TOC check; the "Without dev addons" pass |
| A bare `\|` in chat text is a WoW escape (`\|n` newline, `\|c` color): write `\|\|`. | `tools/pipes.js` in `green.js` |
| Every addon page and the README show the main features in screenshots, with every character, player, guild and realm name blurred, blacked out or made up. | By hand: `docs/screenshots/README.md` has the shot list |
| Nothing crosses the game's terms or the botting line. Faves' automatic actions (buying back a protected item, moving an Always on me item out of the bank, auto-marks) only run inside a window you opened, and never buy, post or cast. Re-check any new automatic action. | By hand, each release |
| Test against known states: a clean install, an upgrade from the last release's saved data, the game without Mechanic, and the release zip itself. | `wow-env.js` passes in the checklist |

## Release checklist (step 3)

Put the build under test at the top (`git describe --tags --always` and the commit). `<env>` is
`node ~/.claude/skills/wow-mod-dev/scripts/wow-env.js --client _forever_`; every `<env>` command needs the game
fully closed.

**Ids:** every row starts with an outline id (`2.4`), so you can say "2.4 is in trouble". `TESTING.md`'s rows sit under
row 2.8 (`2.8.3.2` is its row 3.2). With more than one client pass, each pass gets a letter in front (`A.2.4`). Ids only
need to hold for the pass under way. Each section folds open and closed: its summary shows the id, title and done count (`7 / 12`, plus open
problems); finished sections start closed, and a section with an open problem or the row Claude is waiting on stays open.

**Who does each row** (dev-routine's convention; on a checklist page they're badges):
- **auto executed · \<trigger\>**: Claude runs the row unasked as soon as the trigger is met, and ticks it when it succeeds.
- **auto validated**: a check proves it (`green.js --game`: the saved self-test and BugGrabber's errors). Your checkbox
  is disabled and Claude ticks it when the proof passes. If the proof fails or can't run, you can **Override** it with a
  note: the row shows "overridden: known issue" and the note goes into the release notes' known issues. Only you override.
- **Both** tags: rows Claude runs that prove themselves, like the gate.
- **Untagged**: yours to do and tick, because they need eyes in game.

<details open>
<summary><b>1 Automated</b> · 0 / 2</summary>

- [ ] 1.1 Candidate picked (`pipeline.js candidates`; default the newest) and `pipeline.js prep <version>` passed in a clean checkout `auto executed · when you say you're ready` `auto validated`
- [ ] 1.2 `node tools/green.js` is GREEN, and `install.ps1` installed it `auto executed · after each change` `auto validated`

</details>

<details open>
<summary><b>2 Smoke, then acceptance</b> · 0 / 10</summary>

- [ ] 2.1 `<env> snapshot pre-<version>` `auto executed · game closed`
- [ ] 2.2 Clean install: `<env> profile clean --addon Faves`; full game restart; `/faves selftest` passes `auto validated`
- [ ] 2.3 The intro shows on that first login, and "Got it" closes it
- [ ] 2.4 Without dev addons: `<env> profile disable !Mechanic Mechanic`; log in, open bags, a vendor and the bank; `/faves selftest`; no Faves errors `auto validated`
- [ ] 2.5 With no other addons: `<env> profile only Faves !BugGrabber BugSack`; `/reload`; `/faves selftest`; it works alone `auto validated`
- [ ] 2.6 Upgrade (skip for the first release): `<env> restore`, then `<env> profile upgrade --addon Faves --from <last release tag>`; your marks and settings are kept
- [ ] 2.7 `<env> restore` `auto executed · after you say the pass is done`
- [ ] 2.8 Acceptance: `TESTING.md`, its rows as `2.8.<id>` (open a GitHub issue with it as the body to tick it off)
- [ ] 2.9 No step is still flagged as a problem
- [ ] 2.10 Gate: `<env> watch -- node tools/green.js --game` is GREEN `auto executed · when the game exits` `auto validated`

</details>

<details open>
<summary><b>3 Deploy</b> · 0 / 5</summary>

- [ ] 3.1 Release PR merged (fast-forward); `pipeline.js released <version>` tags the candidate's commit on `main` (lightweight, local) `auto executed · after the gate`
- [ ] 3.2 `powershell -ExecutionPolicy Bypass -File ./release.ps1` builds `dist/Faves-<version>.zip` and its notes `auto executed · after the tag`
- [ ] 3.3 Zip under test: `<env> profile zip dist\Faves-<version>.zip`; log in once; the addon list shows the version; `/faves selftest` passes `auto validated`
- [ ] 3.4 `<env> restore` `auto executed · after the zip test`
- [ ] 3.5 After your go-ahead: `git push origin v<version>` (only that tag), then the uploads below

</details>

A fix sends the build back to stage 1: restamp it, and untick the smoke rows and every row the fix touches.

**Problems.** A problem you note on a row (a Problem button on a checklist page, or a comment on the issue) is a failed
test. Claude triages every open one the next time it reads the checklist (when you finish a pass, or ask):
- **Blocks the release** (the default): Claude adds a **Fix** row under it (`<id>.fix`: find the cause with
  wow-mod-debug, fix on a branch, restamp the build) and **Re-test** rows for you (`<id>.retest`): that step, the smoke
  rows, and every row the fix touches.
  The flag clears only when the re-test passes.
- **Deferred**, only on your word ("not this release"): filed in `BACKLOG.md` or an issue with your note, and listed
  as a known issue in the release notes.
- **The step was wrong**, not the code: Claude fixes the row's text and you re-check that row.

The gate needs zero open problems.

## What "Mechanic output" means here

- **In-game (installed):** `!Mechanic`/`Mechanic` show Faves under Tests (the self-test checks), Console (the guard log) and Errors (BugGrabber). Faves registers only when Mechanic is loaded; without it nothing changes for players.
- **Saved to disk:** `/faves selftest` saves its results in `FavesDB.selfTest`. `green.js --game` reads that, `!BugGrabber.lua` and `!Mechanic.lua` from `WTF\Account\<account>\SavedVariables` after a `/reload`.
- **Mechanic's desktop CLI and MCP (`mech`)** aren't installed on this PC (they need Python 3.10+). If you add them, its `addon.validate`, `addon.lint` (uses `.luacheckrc`) and `addon.output` steps slot into checklist steps 2 and 4.

## Deploy (step 6)

Check before uploading: the TOC's `## Interface:` matches the current Forever build (`/dump (select(4, GetBuildInfo()))`), and the screenshots are current and name-free.

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
