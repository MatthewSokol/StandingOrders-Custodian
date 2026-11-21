// The release gate: one command that says whether this build is "green".
//   node tools/green.js          offline checks (Lua syntax, Lua 5.1 limits, TOC, version, smoke test, privacy)
//   node tools/green.js --game   also reads what the game saved after a /reload: the self-test results
//                                (also shown in Mechanic's Tests tab) and Lua errors from BugGrabber
//   --wtf <path to WTF\Account\<account>>   if the WoW install isn't in the default place
// Exit code 0 = green. FAIL lines block a release; WARN lines need a look but don't block.
const fs = require("fs"), path = require("path"), cp = require("child_process");
const root = path.resolve(__dirname, "..");
const ADDON = "StandingOrders_Custodian";
const args = process.argv.slice(2);
const game = args.includes("--game");
const wtfArg = args.includes("--wtf") ? args[args.indexOf("--wtf") + 1] : null;
const DEFAULT_ACCOUNTS = "C:\\Program Files (x86)\\World of Warcraft\\_forever_\\WTF\\Account";

let fails = 0, warns = 0;
const say = (kind, step, msg) => {
  if (kind === "FAIL") fails++;
  if (kind === "WARN") warns++;
  console.log(`${kind.padEnd(4)} ${step}: ${msg}`);
};
const node = (script, ...a) => cp.spawnSync(process.execPath, [path.join(__dirname, script), ...a], { cwd: root, encoding: "utf8" });

// --- TOC
const addonDir = path.join(root, ADDON);
const tocText = fs.readFileSync(path.join(addonDir, ADDON + ".toc"), "utf8");
const tag = (k) => { const m = tocText.match(new RegExp("^## " + k + ":\\s*(.+)$", "m")); return m && m[1].trim(); };
const files = tocText.split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith("#"));
const version = tag("Version");
for (const k of ["Interface", "Title", "Notes", "Author", "Version", "SavedVariables"]) {
  if (!tag(k)) say("FAIL", "toc", `missing ## ${k}`);
}
if (tag("Interface") && !/\b16001\b/.test(tag("Interface"))) say("FAIL", "toc", `Interface ${tag("Interface")} doesn't include 16001 (Forever)`);
if (/^##\s*Dependencies:.*Mechanic/im.test(tocText) || /^##\s*RequiredDeps:.*Mechanic/im.test(tocText)) say("FAIL", "toc", "Mechanic must stay optional (OptionalDeps), never a dependency");
if (!tag("X-Curse-Project-ID")) say("WARN", "toc", "no ## X-Curse-Project-ID yet (add it once the CurseForge project exists)");
const missing = files.filter(f => !fs.existsSync(path.join(addonDir, f)));
if (missing.length) say("FAIL", "toc", "lists files that don't exist: " + missing.join(", "));
const code = files.filter(f => f.endsWith(".lua")).map(f => fs.readFileSync(path.join(addonDir, f), "utf8")).join("\n");
for (const sv of [tag("SavedVariables"), tag("SavedVariablesPerCharacter")].filter(Boolean).join(",").split(",").map(s => s.trim())) {
  if (!code.includes(sv)) say("FAIL", "toc", `${sv} is saved but never used in the code`);
}
if (!fails) say("PASS", "toc", `${ADDON} ${version}, ${files.length} file(s), Interface ${tag("Interface")}`);

// --- Version and changelog
const changelog = fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8");
// The version lives only in git tags (dev-routine candidates, vX.Y.Z releases); the .toc carries the
// packager's token, and install.ps1 / release.ps1 fill it in.
if (version !== "@project-version@") say("FAIL", "version", `.toc says ## Version: ${version}; it must be @project-version@ (the number comes from the tag)`);
const top = (changelog.match(/^## \[([^\]]+)\]/m) || [])[1];
if (!top) say("FAIL", "version", "CHANGELOG.md has no '## [Unreleased]' or '## [X.Y.Z] - date' heading");
else say("PASS", "version", `.toc uses @project-version@; newest CHANGELOG section is [${top}]`);

// --- Lua syntax and limits
for (const f of files.filter(f => f.endsWith(".lua"))) {
  const r1 = node("check.js", path.join(ADDON, f));
  say(r1.status === 0 && /balance/.test(r1.stdout) && !/error|unbalanced|unclosed/i.test(r1.stdout) ? "PASS" : "FAIL", "lua syntax", r1.stdout.trim().split("\n").pop());
  const r2 = node("limits.js", path.join(ADDON, f));
  say(r2.status === 0 ? "PASS" : "FAIL", "lua 5.1 limits", r2.stdout.trim().split("\n").pop());
  const r3 = node("pipes.js", path.join(ADDON, f)); // a bare "|" in chat text is a WoW escape: write "||"
  if (r3.status === 0) say("PASS", "chat pipes", `${f}: no bare pipes`);
  else r3.stdout.trim().split("\n").forEach(l => say("FAIL", "chat pipes", l));
  // Protected on Forever: an addon call gets ADDON_ACTION_FORBIDDEN (seen in game 2026-11-20).
  const code = fs.readFileSync(path.join(ADDON, f), "utf8").split("\n").map(l => l.replace(/--.*$/, ""));
  const hits = code.map((l, i) => /\bSpellStopTargeting\s*\(/.test(l) ? i + 1 : 0).filter(Boolean);
  say(hits.length ? "FAIL" : "PASS", "protected calls", hits.length ? `${f}: SpellStopTargeting() at line ${hits.join(", ")}` : `${f}: none`);
}

// --- Smoke test (addon loaded in a Lua VM with a stubbed WoW API)
const smoke = node("harness.js", ADDON, "", path.join("tools", "smoke.lua"));
const smokeOut = (smoke.stdout || "") + (smoke.stderr || "");
const checks = (smokeOut.match(/^ok /gm) || []).length;
if (smoke.status === 0) say("PASS", "smoke test", `${checks} checks ok`);
else {
  say("FAIL", "smoke test", "see below");
  smokeOut.split("\n").filter(l => /^(ERROR|FAIL|LOAD ERROR|COMPILE ERROR|HARNESS)/.test(l)).forEach(l => console.log("       " + l));
}

// --- Privacy: no character, account or player names in anything that gets published, and neutral
// commit times. Names come from this machine's WTF folder, so they're never written down here.
const accounts = wtfArg ? path.dirname(wtfArg) : DEFAULT_ACCOUNTS;
// Name parts that are also ordinary words in this project (a surname can be the game's name).
const IGNORE = new Set(["forever"]);
const names = new Set();
if (fs.existsSync(accounts)) {
  for (const acct of fs.readdirSync(accounts)) {
    const ap = path.join(accounts, acct);
    if (!fs.statSync(ap).isDirectory() || acct === "SavedVariables") continue;
    names.add(acct);
    for (const realm of fs.readdirSync(ap)) {
      const rp = path.join(ap, realm);
      if (!fs.statSync(rp).isDirectory() || realm === "SavedVariables") continue;
      for (const ch of fs.readdirSync(rp)) {
        if (fs.statSync(path.join(rp, ch)).isDirectory()) ch.split("-").forEach(n => n.length >= 4 && !IGNORE.has(n.toLowerCase()) && names.add(n));
      }
    }
  }
}
const tracked = cp.spawnSync("git", ["ls-files"], { cwd: root, encoding: "utf8" }).stdout.split("\n").filter(Boolean)
  .filter(f => !f.startsWith("tools/node_modules/"));
const history = cp.spawnSync("git", ["log", "--format=%an%n%ae%n%B"], { cwd: root, encoding: "utf8" }).stdout;
const hits = [];
for (const n of names) {
  const re = new RegExp("\\b" + n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b", "i");
  for (const f of tracked) {
    let text; try { text = fs.readFileSync(path.join(root, f), "utf8"); } catch { continue; }
    if (re.test(text)) hits.push(`${f} mentions "${n}" (a character/account name on this PC)`);
  }
  if (re.test(history)) hits.push(`a commit message mentions "${n}" (a character/account name on this PC)`);
}
if (!names.size) say("WARN", "privacy", "no WTF folder found: couldn't check for character names (pass --wtf)");
else if (hits.length) [...new Set(hits)].forEach(h => say("FAIL", "privacy", h));
else say("PASS", "privacy", `no character or account names in ${tracked.length} tracked files or the commit history`);
const dates = cp.spawnSync("git", ["log", "--format=%h %aI %cI", "origin/main..HEAD"], { cwd: root, encoding: "utf8" }).stdout.split("\n").filter(Boolean);
const timed = dates.filter(l => !/T00:00:00Z \S+T00:00:00Z$/.test(l) && !/T00:00:00\+00:00 \S+T00:00:00\+00:00$/.test(l));
if (timed.length) say("FAIL", "privacy", "commits with real times (want 00:00 UTC): " + timed.map(l => l.split(" ")[0]).join(", "));
else say("PASS", "privacy", `${dates.length} unmerged commit(s), all dated 00:00 UTC`);

// --- In-game results (Mechanic / self-test / BugGrabber), from the SavedVariables written at /reload
if (game) {
  const acctDir = wtfArg || (fs.existsSync(accounts) && fs.readdirSync(accounts)
    .map(a => path.join(accounts, a)).find(a => fs.existsSync(path.join(a, "SavedVariables", ADDON + ".lua"))));
  const svDir = acctDir && path.join(acctDir, "SavedVariables");
  if (!svDir || !fs.existsSync(path.join(svDir, ADDON + ".lua"))) say("FAIL", "game", "no Custodian SavedVariables found: log in, /soc selftest, /reload");
  else {
    const { lua, lauxlib, lualib, to_luastring } = require("fengari");
    const read = (file, expr) => {
      const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
      const ser = `local function s(v, d) d = d or 0
        if type(v) == "table" then if d > 6 then return "null" end
          local isArr = #v > 0; local out = {}
          if isArr then for _, x in ipairs(v) do out[#out+1] = s(x, d+1) end return "[" .. table.concat(out, ",") .. "]" end
          for k, x in pairs(v) do out[#out+1] = string.format("%q", tostring(k)) .. ":" .. s(x, d+1) end
          return "{" .. table.concat(out, ",") .. "}"
        elseif type(v) == "string" then return string.format("%q", v):gsub("\\\\\\n", "\\\\n")
        elseif v == nil then return "null" else return tostring(v) end end
        RESULT = s(${expr})`;
      const src = fs.readFileSync(file, "utf8") + "\n" + ser;
      if (lauxlib.luaL_loadstring(L, to_luastring(src)) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) return { error: lua.lua_tojsstring(L, -1) };
      lua.lua_getglobal(L, to_luastring("RESULT"));
      try { return JSON.parse(lua.lua_tojsstring(L, -1)); } catch (e) { return { error: String(e) }; }
    };
    const st = read(path.join(svDir, ADDON + ".lua"), "StandingOrdersCustodianDB and StandingOrdersCustodianDB.selfTest");
    if (!st || st.error) say("FAIL", "self-test", st && st.error ? st.error : "no results saved: run /soc selftest, then /reload");
    else {
      // The build under test is the installed one: install.ps1 wrote its git describe into the installed .toc.
      const installedToc = path.join(accounts, "..", "..", "Interface", "AddOns", ADDON, ADDON + ".toc");
      const installed = fs.existsSync(installedToc) && (fs.readFileSync(installedToc, "utf8").match(/^## Version:\s*(.+)$/m) || [])[1];
      const stale = installed && st.version !== installed.trim();
      say(stale ? "FAIL" : "PASS", "self-test", `ran ${st.at} on build ${st.version}${stale ? ` (installed is ${installed.trim()}: /reload, /soc selftest, /reload)` : ""}`);
      for (const [id, r] of Object.entries(st.tests || {})) {
        say(r.passed ? (r.warnings ? "WARN" : "PASS") : "FAIL", "self-test " + id, r.message);
        for (const d of r.details || []) if (d.status !== "pass") console.log(`       ${d.status} ${d.label}: ${d.value}`);
      }
    }
    const bgFile = path.join(svDir, "!BugGrabber.lua");
    if (!fs.existsSync(bgFile)) say("WARN", "lua errors", "BugGrabber isn't installed: can't check for errors");
    else {
      const errs = read(bgFile, "BugGrabberDB and BugGrabberDB.errors");
      const mine = (Array.isArray(errs) ? errs : []).filter(e => /StandingOrders_Custodian[\\/]/.test(String(e.message) + String(e.stack)));
      if (mine.length) {
        say("FAIL", "lua errors", `${mine.length} error(s) from Custodian`);
        mine.slice(0, 5).forEach(e => console.log("       " + String(e.message).split("\n")[0].slice(0, 200)));
      } else say("PASS", "lua errors", "none from Custodian in BugGrabber");
    }
    const mech = path.join(svDir, "!Mechanic.lua");
    if (fs.existsSync(mech)) {
      const text = fs.readFileSync(mech, "utf8");
      say("PASS", "mechanic", `MechanicDB saved (${Math.round(text.length / 1024)} KB); Custodian ${text.includes('"StandingOrders_Custodian"') ? "appears in it" : "isn't in it yet"}`);
    } else say("WARN", "mechanic", "no MechanicDB saved yet (enable !Mechanic and Mechanic, then /reload); the self-test above covers the same checks");
  }
}

console.log(`\n${fails ? "NOT GREEN" : "GREEN"}: ${fails} fail(s), ${warns} warning(s)${game ? "" : " (offline only; add --game after a /reload for in-game results)"}`);
process.exitCode = fails ? 1 : 0;
