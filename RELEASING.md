# Releasing Quartermaster

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
| The zip needs forward-slash paths and one top-level `StandingOrders_Quartermaster/` folder (PowerShell 5.1's `Compress-Archive` writes backslashes). | `release.ps1` |
| The version lives only in git tags (dev-routine: a `candidate/vX.Y.Z` per merged change, kept local; one pushed `vX.Y.Z` per release). The `.toc` says `@project-version@`; changes go under `## [Unreleased]` in `CHANGELOG.md`. | `green.js` version check; `install.ps1` and `release.ps1` fill the token |
| Tags are lightweight (`git tag vX.Y.Z`): an annotated tag, including the one `mech release` makes, records the real time. Push only the release tag, by name. | `pipeline.js released` |
| Add `## X-Curse-Project-ID` once the CurseForge project exists. | `green.js` warns until it's there |
| Only register events that exist on Forever; an unknown one stops the file loading. Use `pcall` for events that may not exist. | `tools/wowstub.lua` `KNOWN_EVENTS` (the smoke test fails on unknown ones) |
| WoW runs Lua 5.1: at most 60 upvalues per function and 200 locals per scope. The test VM is 5.3 and doesn't catch this. Quartermaster is at about 160 file-level locals. | `tools/limits.js` |
| Read BugGrabber after a real play session. That's how the nil bag-slot error (123 hits) was found. | `green.js --game` |
| Mechanic is for development only: `OptionalDeps`, never `Dependencies`. Players won't have it. | `green.js` TOC check; the "Without dev addons" pass |
| A bare `\|` in chat text is a WoW escape (`\|n` newline, `\|c` color): write `\|\|`. | `tools/pipes.js` in `green.js` |
| Every addon page and the README show the main features in screenshots, with every character, player, guild and realm name blurred, blacked out or made up. | By hand: `docs/screenshots/README.md` has the shot list |
| Nothing crosses the game's terms or the botting line. Quartermaster' automatic actions (buying back a protected item, moving an Always on me item out of the bank, auto-marks) only run inside a window you opened, and never buy, post or cast. Re-check any new automatic action. | By hand, each release |
| Test against known states: a clean install, an upgrade from the last release's saved data, the game without Mechanic, and the release zip itself. | `wow-env.js` passes in the checklist |

## Release checklist (step 3)

**Waiting since the last release (none yet): 13 changes, 79 rows.**

To tick rows off, use the **Quartermaster Release Checklist** page (https://claude.ai/artifact/Nu3af5cDhQkgSfLGdWM3bt, private to you): ticks, Problem and Override buttons, saved into the page. `node tools/checklist-page.js <out.html> --state <state.json>` builds it from this checklist and `TESTING.md` (each 2.2 group's `TESTING.md` rows written out), keeping the page's ticks; Claude republishes it whenever the checklist changes.

This is a standing checklist: it fills as work happens, so you can cut a release when it gets too long. When a unit of
work starts, Claude adds its group under 2.2 (`2.2.n <title> (#PR)`) with its rows, keeps them current as the PRs
change, removes the group if the work is dropped, writes the candidate version into its header once it merges, and
updates the count above (How to test mentions the new count). Smoke (2.1), the gate and deploy are standing rows. After
a release ships, the released groups are removed and the standing rows unticked.

Put the build under test at the top (`git describe --tags --always` and the commit). `<env>` is
`node ~/.claude/skills/wow-mod-dev/scripts/wow-env.js --client _forever_`; every `<env>` command needs the game
fully closed.

**Ids:** every row starts with an outline id (`2.4`), so you can say "2.4 is in trouble". Unit groups under 2.2 point at `TESTING.md`'s
rows by their own ids (`TESTING.md` 5.9). With more than one client pass, each pass gets a letter in front (`A.2.4`). Ids only
need to hold for the pass under way. Each section folds open and closed: its summary shows the id, title and done count (`7 / 12`, plus open
problems); finished sections start closed, and a section with an open problem or the row Claude is waiting on stays open.

**Who does each row** (dev-routine's convention; on a checklist page they're badges):
- **auto executed · \<trigger\>**: Claude runs the row unasked as soon as the trigger is met, and ticks it when it succeeds.
- **auto validated · \<proof\>**: a check proves it: the command's own output (a saved snapshot, `wow-env status`, a verified restore) or `green.js --game` (the saved self-test and BugGrabber's errors). Your checkbox
  is disabled and Claude ticks it when the proof passes. If the proof fails or can't run, you can **Override** it with a
  note: the row shows "overridden: known issue" and the note goes into the release notes' known issues. Only you override.
- **Both** tags: rows Claude runs that prove themselves, like the gate.
- **Untagged**: yours to do and tick, because they need eyes in game.

<details open>
<summary><b>1 Automated</b> · 0 / 1</summary>

- [ ] 1.1 `node tools/green.js` is GREEN, and `install.ps1` installed it `auto executed · after each change` `auto validated · green.js`

</details>

<details open>
<summary><b>2 Smoke, then acceptance</b> · 0 / 2 sections</summary>

<details open>
<summary><b>2.1 Smoke</b> (standing) · 0 / 8</summary>

- [ ] 2.1.1 `<env> snapshot pre-<version>` `auto executed · game closed` `auto validated · snapshot saved`
- [ ] 2.1.2 A new player's setup: `<env> profile clean --addon StandingOrders_Quartermaster --addon !BugGrabber` (no saved data, and BugSack starts with no errors; restore brings the old ones back), then `<env> profile only StandingOrders_Quartermaster !BugGrabber BugSack` (every other addon off) `auto executed · game closed` `auto validated · wow-env status`
- [ ] 2.1.3 Start the game. At character select, open AddOns: only Standing Orders: Quartermaster (with its ledger icon, not "Out of date"), !BugGrabber and BugSack are ticked
- [ ] 2.1.4 Log in: no Lua errors; the intro window shows after a few seconds, and "Got it" closes it
- [ ] 2.1.5 `/soq selftest` passes, then `/reload` so the result is saved `auto validated · saved self-test`
- [ ] 2.1.6 Exit the game fully and tell Claude the clean install is done (closing the game restores nothing, so restart as often as you like)
- [ ] 2.1.7 `<env> restore` puts your saved marks and every addon's on/off state back `auto executed · after you say the clean install is done` `auto validated · restore verified`
- [ ] 2.1.8 Upgrade: start the game and log in with your own data and addons: your marks are back, `/soq selftest` passes, no Quartermaster errors `auto validated · saved self-test and BugGrabber`

</details>

<details open>
<summary><b>2.2 Acceptance: changes since the last release</b> · 0 / 79</summary>

One group per unit of work, added when the work starts; the candidate version goes in its header once it merges. Rows
point at `TESTING.md` rows (the regression suite), so a group is done when those rows are. No Quartermaster row is journal-proven
yet (no test journal; see `BACKLOG.md`).

<details open>
<summary><b>2.2.1 First build: levels, guards, auto-marks, ArkInventory</b> (#1, #3, #4, #11) · 0.1.0 · 0 / 45</summary>

- [ ] 2.2.1.1 `TESTING.md` 1.1–1.7: fresh install
- [ ] 2.2.1.2 `TESTING.md` 2.1–2.9: per-character marks
- [ ] 2.2.1.3 `TESTING.md` 3.1–3.2: moving from SellAll test builds
- [ ] 2.2.1.4 `TESTING.md` 4.1–4.9: disenchant guard
- [ ] 2.2.1.5 `TESTING.md` 5.1–5.8, 5.13–5.32: vendor, destroy, trade, mail and bank guards, Alt+Click, auto-marks, icons
- [ ] 2.2.1.6 `TESTING.md` 6.1–6.8: combat and blocked actions (ArkInventory is in 2.2.5)

</details>

<details open>
<summary><b>2.2.2 Confirm is a temp hold: allow once from a window</b> (#13) · open · 0 / 4</summary>

- [ ] 2.2.2.1 `TESTING.md` 5.9–5.12: sell, disenchant, trade and mail a Confirm item; Allow once; Keep it

</details>

<details open>
<summary><b>2.2.3 Checklists: outline ids, folding sections</b> (#14) · open · 0 / 1</summary>

- [ ] 2.2.3.1 On GitHub, [`RELEASING.md`](https://github.com/MatthewSokol/StandingOrders-Quartermaster/blob/fix/intro-button-width/RELEASING.md) and [`TESTING.md`](https://github.com/MatthewSokol/StandingOrders-Quartermaster/blob/fix/intro-button-width/TESTING.md) sections fold open and closed, and every row starts with its id

</details>

<details open>
<summary><b>2.2.4 Equipment sets protect their items</b> (#15, #16, #29, #31) · open · 0 / 5</summary>

- [ ] 2.2.4.1 `TESTING.md` 5.33–5.37: set items protected, per-set and default levels by command and in `/soq settings`, back to own mark

</details>

<details open>
<summary><b>2.2.5 More bag addons</b> (#17, #32, #33) · open · 0 / 8</summary>

- [ ] 2.2.5.1 `TESTING.md` 8.1–8.8: a spot check each for ArkInventory, Bagnon, Baganator, AdiBags, BetterBags and ElvUI bags

</details>

<details open>
<summary><b>2.2.6 Renamed to Standing Orders: Quartermaster</b> (#19, #20) · open · 0 / 3</summary>

- [ ] 2.2.6.1 The AddOn List, Esc > Options > AddOns, the intro, chat lines and item tooltips say "Standing Orders" (the panel: "Standing Orders: Quartermaster"); none say "Faves"
- [ ] 2.2.6.2 `/soq` and `/soq help` work; `/faves` is gone (the game answers with its unknown-command line)
- [ ] 2.2.6.4 Character select > AddOns lists Standing Orders: Quartermaster once, with the ledger icon, and no Faves (the old folder is in `_forever_\AddOns-backup`)

</details>

<details open>
<summary><b>2.2.7 Quartermaster icon</b> (#21) · open · 0 / 1</summary>

- [ ] 2.2.7.1 Covered by 2.1.3 and 2.2.6.4 (the ledger icon in the AddOn List) `auto validated · same rows`

</details>

<details open>
<summary><b>2.2.8 The icon on Quartermaster's windows</b> (#22) · open · 0 / 3</summary>

- [ ] 2.2.8.1 `/soq settings`: the ledger icon sits left of the "Standing Orders: Quartermaster" title
- [ ] 2.2.8.2 `/soq intro`: a small ledger icon sits left of the window title
- [ ] 2.2.8.3 Sell a Confirm item: the hold window shows the ledger above "… is on hold"; Allow once and Keep it still work

</details>

<details open>
<summary><b>2.2.9 Mark icon size, position and opacity</b> (#24) · open · 0 / 5</summary>

- [ ] 2.2.9.1 `TESTING.md` 9.1–9.5: mark icons

</details>

<details open>
<summary><b>2.2.10 Disenchant guard without protected calls</b> (#25) · open · 0 / 1</summary>

- [ ] 2.2.10.1 After `TESTING.md` 4.1–4.6 pass again on this build, `/soq selftest` passes and BugSack has no `ADDON_ACTION_FORBIDDEN` from Quartermaster; `/soq log` names spells and says just "item" for item uses `auto validated · green.js --game`

</details>

<details open>
<summary><b>2.2.11 Old per-character auto-marks on reagents come off</b> (#27) · open · 0 / 1</summary>

- [ ] 2.2.11.1 `TESTING.md` 5.19: consumables, reagents and vendor trade goods

</details>

<details open>
<summary><b>2.2.12 The intro button fits its label</b> (#28) · open · 0 / 1</summary>

- [ ] 2.2.12.1 `/soq settings`: the "What Standing Orders protects" button shows its whole label (try a larger UI scale too), and clicking it opens the intro

</details>

<details open>
<summary><b>2.2.13 The settings panel scrolls</b> (#30) · open · 0 / 1</summary>

- [ ] 2.2.13.1 `/soq settings`: nothing spills past the bottom of the settings window; scroll down to reach the equipment set rows; the opacity text (e.g. "70% opaque (30% see-through)") fits on one line

</details>

</details>

- [ ] 2.3 No step is still flagged as a problem
- [ ] 2.4 Gate: `<env> watch -- node tools/green.js --game` is GREEN `auto executed · when the game exits` `auto validated · green.js --game`

</details>

<details open>
<summary><b>3 Deploy</b> · 0 / 9</summary>

- [ ] 3.1 The CurseForge project ID is in the `.toc` (`## X-Curse-Project-ID`), so `green.js` has no warning for it `auto validated · green.js`
- [ ] 3.2 SEO tuned with the wow-mod-seo skill: `docs/listing.md` drafted or refreshed (search keywords checked against similar addons such as Keep or Toss: Forever, iGuard and ItemGuard; the name, summary, categories per site, the README as the description, screenshot captions), and the `.toc` `## Title`, `## Notes`, `## Category` and `## IconTexture` match it; `node ~/.claude/skills/wow-mod-seo/scripts/lint-listing.js docs/listing.md --toc StandingOrders_Quartermaster/StandingOrders_Quartermaster.toc --readme README.md` is clean `auto executed · before prep` `auto validated · lint-listing.js`
- [ ] 3.3 You review the listing: name, summary, first lines of the description, categories and screenshots, side by side with two or three similar addons, with every character name hidden, and say it's good
- [ ] 3.4 Candidate picked (`pipeline.js candidates`; default the newest) and `pipeline.js prep <version>` passed in a clean checkout `auto executed · when you say you're ready` `auto validated · prep`
- [ ] 3.5 Release PR merged (fast-forward); `pipeline.js released <version>` tags the candidate's commit on `main` (lightweight, local) `auto executed · after prep passes` `auto validated · git tag`
- [ ] 3.6 `powershell -ExecutionPolicy Bypass -File ./release.ps1` builds `dist/StandingOrders_Quartermaster-<version>.zip` and its notes `auto executed · after the tag` `auto validated · zip listing`
- [ ] 3.7 Zip under test: `<env> profile zip dist\StandingOrders_Quartermaster-<version>.zip`; log in once; the addon list shows the version; `/soq selftest` passes `auto validated · saved self-test`
- [ ] 3.8 `<env> restore` `auto executed · after the zip test` `auto validated · restore verified`
- [ ] 3.9 After your go-ahead: `git push origin v<version>` (only that tag), then the uploads below (before, or together with, Standing Orders: Vendor, whose warning links to this addon)

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

- **In-game (installed):** `!Mechanic`/`Mechanic` show Quartermaster under Tests (the self-test checks), Console (the guard log) and Errors (BugGrabber). Quartermaster registers only when Mechanic is loaded; without it nothing changes for players.
- **Saved to disk:** `/soq selftest` saves its results in `StandingOrdersQuartermasterDB.selfTest`. `green.js --game` reads that, `!BugGrabber.lua` and `!Mechanic.lua` from `WTF\Account\<account>\SavedVariables` after a `/reload`.
- **Mechanic's desktop CLI and MCP (`mech`)** aren't installed on this PC (they need Python 3.10+). If you add them, its `addon.validate`, `addon.lint` (uses `.luacheckrc`) and `addon.output` steps slot into checklist steps 2 and 4.

## Deploy (step 6)

Check before uploading: the TOC's `## Interface:` matches the current Forever build (`/dump (select(4, GetBuildInfo()))`), and the screenshots are current and name-free.

### CurseForge
First release only:
1. Go to authors.curseforge.com → Create Project → World of Warcraft → Addon.
2. Fill it in:
   - **Name:** Standing Orders: Quartermaster (slug `standing-orders-quartermaster`: Standing Orders: Vendor and Mail link to it).
   - **Summary:** the `.toc` Notes line.
   - **Description:** adapted from `README.md`, with no character names.
   - **Category:** Bags & Inventory.
   - **License:** MIT.
   - **Logo:** 400×400.
   - **Source:** `https://github.com/MatthewSokol/StandingOrders-Quartermaster` (only if the repo is public).
3. Copy the project ID into `StandingOrders_Quartermaster/StandingOrders_Quartermaster.toc` as `## X-Curse-Project-ID: <id>`. Commit that, then rebuild the zip.

Every release:
1. Project → Files → Upload File → `dist/StandingOrders_Quartermaster-<version>.zip`.
2. Set the details:
   - **Display name:** `Standing Orders: Quartermaster <version>`.
   - **Release type:** Release (or Beta).
   - **Game version:** the WoW Forever / Interface 16001 entry.
   - **Changelog:** paste this version's `CHANGELOG.md` entry, as Markdown.
3. Wait for approval (usually minutes to hours), then install it from the CurseForge app on a clean profile and `/reload` once.

### Other sites (if you choose them)
- **GitHub release:** `gh release create v<version> dist/StandingOrders_Quartermaster-<version>.zip --notes-file <changelog entry>`. Only if the repo is public.
- **Wago Addons** (addons.wago.io → Developer): create the project, then add `## X-Wago-ID: <id>` to the `.toc` and upload the same zip.
- **WoWInterface:** Upload → new addon. Uses the same zip and changelog.
