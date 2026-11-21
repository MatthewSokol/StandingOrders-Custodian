// Builds the release checklist page (an Artifact with ticks, Problem and Override buttons; same look as the
// Waterboy release checklist) from RELEASING.md's checklist and TESTING.md. Each 2.2 group's "`TESTING.md` 5.9–5.12" row becomes
// the TESTING.md rows it names. The page's look and script are tools/checklist-page.template.html.
// Usage: node tools/checklist-page.js <out.html> [--state <state.json>] [--build <text>]
// --state keeps ticks, problems and overrides (the JSON in the live page's <script id="state">); rows keep their
// ids across rebuilds, so ticks stay on the right rows.
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const read = f => fs.readFileSync(path.join(root, f), "utf8").replace(/\r\n/g, "\n");
const arg = name => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : null; };
const out = process.argv[2];
if (!out || out.startsWith("--")) throw new Error("usage: node tools/checklist-page.js <out.html> [--state f] [--build text]");

// A checklist row: "- [ ] 2.1.3 text `auto executed · trigger` `auto validated`" -> {id, text, exec, valid}
function row(line) {
  const m = line.match(/^- \[[ x]\] ([\w.]+) (.*)$/);
  if (!m) return null;
  const r = { id: m[1] };
  let text = m[2];
  text = text.replace(/\s*`auto executed · ([^`]+)`/, (_, t) => { r.exec = t; return ""; });
  text = text.replace(/\s*`auto validated(?: · ([^`]+))?`/, (_, proof) => { r.valid = proof || true; return ""; });
  // `paste · docs/x.md`: the page shows that file in full with a Copy button
  text = text.replace(/\s*`paste · ([^`]+)`/, (_, file) => { r.paste = { file, text: read(file).trimEnd() }; return ""; });
  r.text = text.trim();
  return r;
}
const testing = {};
for (const line of read("TESTING.md").split("\n")) { const r = row(line); if (r) testing[r.id] = r; }

function ids(ranges) {
  const list = [];
  for (const r of ranges.split(/,\s*/)) {
    const [a, b = a] = r.split(/[–-]/).map(s => s.trim());
    // A single sub-row id such as 8.3.1 names just that row (ranges are by whole rows: 8.1–8.8).
    if (a === b && a.split(".").length > 2) {
      if (!testing[a]) throw new Error("no TESTING.md row " + a);
      list.push(a);
      continue;
    }
    const sec = a.split(".")[0], from = Number(a.split(".")[1]), to = Number(b.split(".")[1]);
    const before = list.length;
    // Rows dropped from TESTING.md leave gaps in a range; skip them, but a range must name at least one row.
    for (let n = from; n <= to; n++) if (testing[`${sec}.${n}`]) list.push(`${sec}.${n}`);
    if (list.length === before) throw new Error("no TESTING.md rows in " + r);
  }
  return list;
}

const PART = { "1": "1 · Build and smoke", "2.1": "1 · Build and smoke", "2.2": "2 · Changes since the last release", "2.3": "3 · Gate and deploy", "3": "3 · Gate and deploy" };
const NOTES = {
  "1": "Claude runs these, like CI. When a fix lands, the build at the top changes, these rerun, and the smoke test and any steps the fix touches are unticked.",
  "2.1": "Done on every new build, before the changes below. Claude sets up each test profile with the game fully closed; you play. If anything here fails, stop and flag it.",
  "2.3": "Exit the game when the rows above are done.",
  "3": "Nothing goes to CurseForge until the gate is GREEN, nothing is flagged, and you say so.",
};
const TITLES = { "1": "Automated checks", "2.1": "Smoke test", "2.3": "Problems and gate", "3": "Deploy" };

const rel = read("RELEASING.md");
const start = rel.indexOf("<details open>\n<summary><b>1 Automated");
const end = rel.indexOf("</details>", rel.indexOf("<summary><b>3 Deploy")) + 10;
const sections = [];
let cur = null;
function open(num, title, extra) {
  const part = PART[num] || PART[num.split(".").slice(0, 2).join(".")];
  cur = Object.assign({ id: "s" + num.replace(/\./g, "-"), oid: num, part, title, items: [] }, extra || {});
  if (NOTES[num]) cur.note = NOTES[num];
  sections.push(cur);
}
for (const line of rel.slice(start, end).split("\n")) {
  const h = line.match(/^<summary><b>([\d.]+) ([^<]+)<\/b>(.*)<\/summary>$/);
  if (h) {
    const [, num, title, rest] = h;
    if (num === "2" || num === "2.2") continue; // wrappers: their rows live in the sections inside
    const prs = (rest.match(/\(([^)]*#[^)]*)\)/) || [])[1];
    const ver = (rest.match(/· (\d+\.\d+\.\d+|open)\b/) || [])[1];
    const extra = {};
    if (num.startsWith("2.2.")) extra.version = ver === "open" ? "open PR" : ver ? "candidate " + ver : "";
    open(num, (TITLES[num] || title.trim()) + (prs ? " (" + prs + ")" : ""), extra);
    continue;
  }
  const g = line.match(/^- \[[ x]\] (2\.2\.\d+)\.\d+ `TESTING\.md` ([\d.,–\s-]+): (.*)$/);
  if (g && cur) {
    for (const id of ids(g[2])) {
      const t = testing[id];
      if (!t) throw new Error("TESTING.md row not found: " + id);
      cur.items.push({ id: `${g[1]}.T${id}`, oid: `${cur.oid}.${cur.items.length + 1}`, text: t.text, hint: "TESTING.md " + id, exec: t.exec, valid: t.valid });
    }
    continue;
  }
  const r = row(line);
  if (r) {
    if (/^2\.[34]$/.test(r.id) && cur.oid !== "2.3") open("2.3", TITLES["2.3"]); // problems and gate get their own section
    cur.items.push({ id: r.id, oid: r.id, text: r.text, exec: r.exec, valid: r.valid, paste: r.paste });
  }
}
for (const s of sections) if (!s.items.length) throw new Error("empty section " + s.oid);
const units = sections.filter(s => s.oid.startsWith("2.2."));
const urows = units.reduce((n, s) => n + s.items.length, 0);
// The last release comes from RELEASING.md's own Waiting line, e.g. "(1.0.0)".
const lastRel = (rel.match(/Waiting since the last release \(([^)]+)\)/) || [])[1] || "none yet";
const waiting = `Waiting since the last release (${lastRel}): ${units.length} ${units.length === 1 ? "change" : "changes"}, ${urows} ${urows === 1 ? "row" : "rows"}`;

let state = { build: arg("--build") || "not stamped", checked: {}, flags: {}, overrides: {}, triage: {} };
const stateFile = arg("--state");
if (stateFile) {
  const old = JSON.parse(fs.readFileSync(stateFile, "utf8"));
  if (old.problems && !old.flags) old.flags = old.problems; // the earlier page called them problems
  delete old.problems; delete old.added;
  state = Object.assign(state, old);
  if (arg("--build")) state.build = arg("--build");
}
// <repo> in a row becomes this checkout's folder, on the private page only (RELEASING.md stays free of local paths)
const json = v => JSON.stringify(v).split("<repo>").join(JSON.stringify(path.resolve(root)).slice(1, -1)).replace(/</g, "\\u003c");
const html = read("tools/checklist-page.template.html")
  .replace("__SECTIONS__", () => json(sections))
  .replace("__WAITING__", () => json(waiting))
  .replace("__STATE__", () => json(state));
fs.writeFileSync(out, html);
console.log(`${sections.length} sections, ${sections.reduce((n, s) => n + s.items.length, 0)} rows; ${waiting}`);
