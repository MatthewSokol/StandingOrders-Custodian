# Releasing Custodian

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
| The zip needs forward-slash paths and one top-level `StandingOrders_Custodian/` folder (PowerShell 5.1's `Compress-Archive` writes backslashes). | `release.ps1` |
| The version lives only in git tags (dev-routine: a `candidate/vX.Y.Z` per merged change, kept local; one pushed `vX.Y.Z` per release). The `.toc` says `@project-version@`; changes go under `## [Unreleased]` in `CHANGELOG.md`. | `green.js` version check; `install.ps1` and `release.ps1` fill the token |
| Tags are lightweight (`git tag vX.Y.Z`): an annotated tag, including the one `mech release` makes, records the real time. Push only the release tag, by name. | `pipeline.js released` |
| Add `## X-Curse-Project-ID` once the CurseForge project exists. | `green.js` warns until it's there |
| Only register events that exist on Forever; an unknown one stops the file loading. Use `pcall` for events that may not exist. | `tools/wowstub.lua` `KNOWN_EVENTS` (the smoke test fails on unknown ones) |
| WoW runs Lua 5.1: at most 60 upvalues per function and 200 locals per scope. The test VM is 5.3 and doesn't catch this. Custodian is at about 160 file-level locals. | `tools/limits.js` |
| Read BugGrabber after a real play session. That's how the nil bag-slot error (123 hits) was found. | `green.js --game` |
| Mechanic is for development only: `OptionalDeps`, never `Dependencies`. Players won't have it. | `green.js` TOC check; the "Without dev addons" pass |
| A bare `\|` in chat text is a WoW escape (`\|n` newline, `\|c` color): write `\|\|`. | `tools/pipes.js` in `green.js` |
| Every addon page and the README show the main features in screenshots, with every character, player, guild and realm name blurred, blacked out or made up. | By hand: `docs/screenshots/README.md` has the shot list |
| Nothing crosses the game's terms or the botting line. Custodian' automatic actions (buying back a protected item, moving an Always on me item out of the bank, auto-marks) only run inside a window you opened, and never buy, post or cast. Re-check any new automatic action. | By hand, each release |
| Test against known states: a clean install, an upgrade from the last release's saved data, the game without Mechanic, and the release zip itself. | `wow-env.js` passes in the checklist |

## Release checklist (step 3)

**Waiting since the last release (1.0.0): 5 changes, 5 rows.**

To tick rows off, use the **Custodian Release Checklist** page (https://claude.ai/artifact/Nu3af5cDhQkgSfLGdWM3bt, private to you): ticks, Problem and Override buttons, saved into the page. `node tools/checklist-page.js <out.html> --state <state.json>` builds it from this checklist and `TESTING.md` (each 2.2 group's `TESTING.md` rows written out), keeping the page's ticks; Claude republishes it whenever the checklist changes.

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
- [ ] 2.1.2 A new player's setup: `<env> profile clean --addon StandingOrders_Custodian --addon !BugGrabber` (no saved data, and BugSack starts with no errors; restore brings the old ones back), then `<env> profile only StandingOrders_Custodian !BugGrabber BugSack` (every other addon off) `auto executed · game closed` `auto validated · wow-env status`
- [ ] 2.1.3 Start the game. At character select, open AddOns: only Standing Orders: Custodian (with its ledger icon, not "Out of date"), !BugGrabber and BugSack are ticked
- [ ] 2.1.4 Log in: no Lua errors; the intro window shows after a few seconds, and "Got it" closes it
- [ ] 2.1.5 `/soc selftest` passes, then `/reload` so the result is saved `auto validated · saved self-test`
- [ ] 2.1.6 Exit the game fully and tell Claude the clean install is done (closing the game restores nothing, so restart as often as you like)
- [ ] 2.1.7 `<env> restore` puts your saved marks and every addon's on/off state back `auto executed · after you say the clean install is done` `auto validated · restore verified`
- [ ] 2.1.8 Upgrade: start the game and log in with your own data and addons: your marks are back, `/soc selftest` passes, no Custodian errors `auto validated · saved self-test and BugGrabber`

</details>

<details open>
<summary><b>2.2 Acceptance: changes since the last release</b> · 0 / 5</summary>

One group per unit of work, added when the work starts; the candidate version goes in its header once it merges. Rows
point at `TESTING.md` rows (the regression suite), so a group is done when those rows are. No Custodian row is journal-proven
yet (no test journal; see `BACKLOG.md`).

<details open>
<summary><b>2.2.1 The mailbox: Alt+Left-click is Postal's</b> (#40) · open · 0 / 1</summary>

- [ ] 2.2.1.1 `TESTING.md` 5.38: with Posty Forever's Express on, Alt+Left-click at the Send Mail page attaches the item and leaves its mark alone; elsewhere, and with Express off, Alt+Left-click still raises marks

</details>

<details open>
<summary><b>2.2.2 Profession tools aren't Junk</b> (#41) · open · 0 / 1</summary>

- [ ] 2.2.2.1 `TESTING.md` 5.39: a Fishing Pole (and other profession tools) in your bags stays unmarked, and 1.0.0's Junk auto-mark on one comes off at login

</details>

<details open>
<summary><b>2.2.3 Custodian's own messages: log only unless chat is on</b> (#42) · open · 0 / 1</summary>

- [ ] 2.2.3.1 `TESTING.md` 5.40: auto-mark, buyback and blocked-action messages stay out of chat by default (the red error still shows) and are in `/soc log`; `/soc chat on` or the Chat switch brings them back

</details>

<details open>
<summary><b>2.2.4 Alt+Click wraps around, with a warning when Vendor or Mail act on their own</b> (#43) · open · 0 / 1</summary>

- [ ] 2.2.4.1 `TESTING.md` 5.41: Alt+Click wraps between Always on me and Junk (off with `/soc wrap off`); with Vendor selling on its own, the warning shows in settings, when turning wrap-around on, once at login, and on a click that wraps onto Junk

</details>

<details open>
<summary><b>2.2.5 Unusable soulbound gear becomes Junk on that character (off by default)</b> (#44) · open · 0 / 1</summary>

- [ ] 2.2.5.1 `TESTING.md` 5.42: with the new rule on, soulbound gear the class can never use (or not for 5+ levels) becomes Junk "(this character)"; usable gear, trainable weapon types and an enchanter's green and better stay Normal

</details>

</details>

- [ ] 2.3 No step is still flagged as a problem
- [ ] 2.4 Gate: `<env> watch -- node tools/green.js --game` is GREEN `auto executed · when the game exits` `auto validated · green.js --game`

</details>

<details open>
<summary><b>3 Deploy</b> · 0 / 29</summary>

- [ ] 3.1 The CurseForge project ID is in the `.toc` (`## X-Curse-Project-ID`), so `green.js` has no warning for it `auto validated · green.js`
- [ ] 3.2 SEO tuned with the wow-mod-seo skill: `docs/listing.md` drafted or refreshed (search keywords checked against similar addons such as Keep or Toss: Forever, iGuard and ItemGuard; the name, summary, categories per site, the README as the description, screenshot captions), and the `.toc` `## Title`, `## Notes`, `## Category` and `## IconTexture` match it; `node ~/.claude/skills/wow-mod-seo/scripts/lint-listing.js docs/listing.md --toc StandingOrders_Custodian/StandingOrders_Custodian.toc --readme README.md` is clean `auto executed · before prep` `auto validated · lint-listing.js`
- [ ] 3.3.1 Shot `bags-levels`: in a quiet spot (no players near, or face a wall), the default bags with one item at each level (Junk coin, Mail letter, Locked key, Always on me purple diamond)
- [ ] 3.3.2 Shot `disenchant-blocker`: cast Disenchant and, with the targeting cursor up, hover over a Locked item so its red cover and "blocked" line show (Esc to cancel)
- [ ] 3.3.3 Shot `guard`: at a vendor, sell a Locked item; capture the red error ("… Lower it to Normal to sell it …") with the item back in your bags
- [ ] 3.3.4 Shot `settings`: in a quiet spot (the window is see-through, so names behind it show): `/soc settings` scrolled to the top
- [ ] 3.3.5 Shot `equipment-sets`: `/soc settings` scrolled to Equipment sets, with a set's dropdown open
- [ ] 3.3.6 Shot `bag-addon`: the same marks in Baganator or another bag addon (needs that addon's profile and a restart)
- [ ] 3.3.7 Shot `intro`: `/soc intro`
- [ ] 3.3.8 Claude takes the new files from `_forever_\Screenshots`, crops them, hides every name, saves them as `docs/screenshots/<shot>.png` and adds them to `docs/listing.md`; you check each picture `auto executed · when you say the shots are done`
- [ ] 3.3 You review the listing: name, summary, first lines of the description, categories and screenshots, side by side with two or three similar addons, with every character name hidden, and say it's good
- [ ] 3.4 Candidate picked (`pipeline.js candidates`; default the newest) and `pipeline.js prep <version>` passed in a clean checkout `auto executed · when you say you're ready` `auto validated · prep`
- [ ] 3.5 Release PR merged (fast-forward); `pipeline.js released <version>` tags the candidate's commit on `main` (lightweight, local) `auto executed · after prep passes` `auto validated · git tag`
- [ ] 3.6 `powershell -ExecutionPolicy Bypass -File ./release.ps1` builds `dist/StandingOrders_Custodian-<version>.zip` and its notes `auto executed · after the tag` `auto validated · zip listing`
- [ ] 3.7 Zip under test: `<env> profile zip dist\StandingOrders_Custodian-<version>.zip`; log in once; the addon list shows the version; `/soc selftest` passes `auto validated · saved self-test`
- [ ] 3.8 `<env> restore` `auto executed · after the zip test` `auto validated · restore verified`
- [ ] 3.9 After your go-ahead: `git push origin v<version>` (only that tag), then the CurseForge steps 3.9.1–3.9.5 (the project already exists, so only the description, images and file) (before, or together with, Standing Orders: Vendor, whose warning links to this addon)
- [ ] 3.9.1 CurseForge → your project → Description: set the editor to Markdown, select everything in it, and paste this (the README without its repo-only logo and links; Vendor and Mail say coming soon) `paste · docs/curseforge/description.md`
- [ ] 3.9.2 Images → Upload: the seven screenshots, each with its title and description, in this order; star (feature) only the first, `bags-levels`, so it is the project's main image
- [ ] 3.9.2.1 File `<repo>\docs\screenshots\bags-levels.png`; title `Item levels`; description `Mark items with Alt+Click; an icon shows each level (Junk coin, Mail letter, Locked key, Always on me diamond).`
- [ ] 3.9.2.2 File `<repo>\docs\screenshots\guard.png`; title `Sell guard`; description `Sold by mistake? It's bought straight back.`
- [ ] 3.9.2.3 File `<repo>\docs\screenshots\disenchant-blocker.png`; title `Disenchant blocker`; description `Disenchant, Prospect and Mill can't touch a Locked item.`
- [ ] 3.9.2.4 File `<repo>\docs\screenshots\settings.png`; title `Settings`; description `Choose what's marked for you and how the icons look.`
- [ ] 3.9.2.5 File `<repo>\docs\screenshots\equipment-sets.png`; title `Equipment sets`; description `Items in your equipment sets are Locked automatically.`
- [ ] 3.9.2.6 File `<repo>\docs\screenshots\bag-addon.png`; title `Bag addons`; description `Works in Blizzard bags and seven bag addons (Baganator shown).`
- [ ] 3.9.2.7 File `<repo>\docs\screenshots\intro.png`; title `Intro`; description `What Locked protects, shown once on first login.`
- [ ] 3.9.3 Files → Upload File: file `<repo>\dist\StandingOrders_Custodian-1.0.0.zip`; display name `Standing Orders: Custodian 1.0.0`; release type Release; game version WoW Forever (Interface 16001)
- [ ] 3.9.4 In the same upload form, Changelog: set it to Markdown and paste this `paste · docs/curseforge/changelog-1.0.0.md`
- [ ] 3.9.5 When CurseForge approves the file (minutes to hours), install it from the CurseForge app on a clean profile, `/reload` once and check the addon list shows 1.0.0

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

- **In-game (installed):** `!Mechanic`/`Mechanic` show Custodian under Tests (the self-test checks), Console (the guard log) and Errors (BugGrabber). Custodian registers only when Mechanic is loaded; without it nothing changes for players.
- **Saved to disk:** `/soc selftest` saves its results in `StandingOrdersCustodianDB.selfTest`. `green.js --game` reads that, `!BugGrabber.lua` and `!Mechanic.lua` from `WTF\Account\<account>\SavedVariables` after a `/reload`.
- **Mechanic's desktop CLI and MCP (`mech`)** aren't installed on this PC (they need Python 3.10+). If you add them, its `addon.validate`, `addon.lint` (uses `.luacheckrc`) and `addon.output` steps slot into checklist steps 2 and 4.

## Deploy (step 6)

Check before uploading: the TOC's `## Interface:` matches the current Forever build (`/dump (select(4, GetBuildInfo()))`), and the screenshots are current and name-free.

### CurseForge
First release only (done for Custodian: project 1806484 exists):
1. Go to authors.curseforge.com → Create Project → World of Warcraft → Addon.
2. Fill it in:
   - **Name:** Standing Orders: Custodian (renamed from Quartermaster; the slug is still `standing-orders-quartermaster` unless CurseForge lets you change it, and Standing Orders: Vendor and Mail link to that slug).
   - **Summary:** the `.toc` Notes line.
   - **Description:** `docs/curseforge/description.md` (made from `README.md` by `node tools/curseforge-text.js`; rerun it after README changes).
   - **Category:** Bags & Inventory.
   - **License:** MIT.
   - **Logo:** 400×400.
   - **Source:** `https://github.com/MatthewSokol/StandingOrders-Custodian` (only if the repo is public).
3. Copy the project ID into `StandingOrders_Custodian/StandingOrders_Custodian.toc` as `## X-Curse-Project-ID: <id>`. Commit that, then rebuild the zip.

Every release:
1. Project → Files → Upload File → `dist/StandingOrders_Custodian-<version>.zip`.
2. Set the details:
   - **Display name:** `Standing Orders: Custodian <version>`.
   - **Release type:** Release (or Beta).
   - **Game version:** the WoW Forever / Interface 16001 entry.
   - **Changelog:** paste this version's `CHANGELOG.md` entry, as Markdown (the first release uses `docs/curseforge/changelog-1.0.0.md`).
3. Wait for approval (usually minutes to hours), then install it from the CurseForge app on a clean profile and `/reload` once.

### Other sites (if you choose them)
- **GitHub release:** `gh release create v<version> dist/StandingOrders_Custodian-<version>.zip --notes-file <changelog entry>`. Only if the repo is public.
- **Wago Addons** (addons.wago.io → Developer): create the project, then add `## X-Wago-ID: <id>` to the `.toc` and upload the same zip.
- **WoWInterface:** Upload → new addon. Uses the same zip and changelog.
