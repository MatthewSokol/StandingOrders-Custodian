// Builds the release checklist page (an Artifact with ticks, Problem and Override buttons) from
// RELEASING.md's checklist and TESTING.md. Each 2.2 group's "`TESTING.md` 5.9–5.12" row becomes the
// TESTING.md rows it names. The page's look and script are tools/checklist-page.template.html.
// Usage: node tools/checklist-page.js <out.html> [--state <state.json>] [--build <text>]
// --state keeps ticks, overrides and problems (the JSON in the live page's <script id="state">);
// rows keep their ids across rebuilds, so ticks stay on the right rows.
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const read = f => fs.readFileSync(path.join(root, f), "utf8").replace(/\r\n/g, "\n");
const arg = name => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : null; };
const out = process.argv[2];
if (!out || out.startsWith("--")) throw new Error("usage: node tools/checklist-page.js <out.html> [--state f] [--build text]");

const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const md = s => esc(s).replace(/`([^`]+)`/g, "<code>$1</code>").replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");

// A checklist row: "- [ ] 2.1.3 text `auto executed · trigger` `auto validated`"
function row(line) {
  const m = line.match(/^- \[[ x]\] ([\w.]+) (.*)$/);
  if (!m) return null;
  let text = m[2], tags = {};
  text = text.replace(/\s*`auto executed · ([^`]+)`/, (_, t) => { tags.exec = t; return ""; });
  text = text.replace(/\s*`auto validated`/, () => { tags.valid = "check"; return ""; });
  return { id: m[1], text: md(text.trim()), tags };
}
const testing = {};
for (const line of read("TESTING.md").split("\n")) { const r = row(line); if (r) testing[r.id] = r; }

function ids(ranges) {
  const list = [];
  for (const r of ranges.split(/,\s*/)) {
    const [a, b = a] = r.split(/[–-]/).map(s => s.trim());
    const sec = a.split(".")[0], from = Number(a.split(".")[1]), to = Number(b.split(".")[1]);
    for (let n = from; n <= to; n++) list.push(`${sec}.${n}`);
  }
  return list;
}

// Sections from RELEASING.md's <details> blocks
const rel = read("RELEASING.md");
const start = rel.indexOf("<details open>\n<summary><b>1 Automated");
const end = rel.indexOf("</details>", rel.indexOf("<summary><b>3 Deploy")) + 10;
const sections = [];
let cur = null, firstUnit = true;
const NOTES = {
  "1": "Standing: every release.",
  "2.1": "Standing: every release. Claude sets up each test profile with the game fully closed; you play.",
  "2.3": "Standing. Exit the game when the rows above are done.",
  "3": "Standing: every release.",
};
for (const line of rel.slice(start, end).split("\n")) {
  const h = line.match(/^<summary><b>([\d.]+) ([^<]+)<\/b>(.*)<\/summary>$/);
  if (h) {
    const [, num, title, rest] = h;
    if (num === "2" || num === "2.2") continue; // wrappers: their rows live in the sections inside
    const prs = (rest.match(/\(([^)]*#[^)]*)\)/) || [])[1];
    const ver = (rest.match(/· (\d+\.\d+\.\d+|open)\b/) || [])[1];
    cur = { id: "s" + num.replace(/\./g, "-"), num, title: esc(title.trim()) + (prs ? " (" + esc(prs) + ")" : ""), items: [] };
    if (num.startsWith("2.2.")) {
      cur.unit = true;
      cur.version = ver === "open" ? "open PR" : ver ? "candidate " + ver : "";
      if (firstUnit) { cur.part = "2.2 Changes since the last release"; firstUnit = false; }
    }
    if (NOTES[num]) cur.note = NOTES[num];
    sections.push(cur);
    continue;
  }
  const g = line.match(/^- \[[ x]\] (2\.2\.\d+)\.\d+ `TESTING\.md` ([\d.,–\s-]+): (.*)$/);
  if (g && cur) {
    for (const id of ids(g[2])) {
      const t = testing[id];
      if (!t) throw new Error("TESTING.md row not found: " + id);
      cur.items.push([`${g[1]}.T${id}`, t.text, "TESTING.md " + id, t.tags]);
    }
    continue;
  }
  const r = row(line);
  if (r) {
    // 2.3 and 2.4 (problems, gate) sit after the 2.2 groups: give them their own section
    if (/^2\.[34]$/.test(r.id) && cur && cur.num !== "2.3") {
      cur = { id: "s2-3", num: "2.3", title: "Problems and gate", note: NOTES["2.3"], items: [] };
      sections.push(cur);
    }
    cur.items.push([r.id, r.text, "", r.tags]);
  }
}
for (const s of sections) if (!s.items.length) throw new Error("empty section " + s.num);

let state = { build: arg("--build") || "Not stamped yet", checked: {}, overrides: {}, problems: {}, added: {} };
const stateFile = arg("--state");
if (stateFile) {
  const old = JSON.parse(fs.readFileSync(stateFile, "utf8"));
  state = Object.assign(state, old);
  if (arg("--build")) state.build = arg("--build");
}
const html = read("tools/checklist-page.template.html")
  .replace("__SECTIONS__", () => JSON.stringify(sections, null, 1).replace(/</g, "\\u003c"))
  .replace("__STATE__", () => JSON.stringify(state).replace(/</g, "\\u003c"));
fs.writeFileSync(out, html);
const rows = sections.reduce((n, s) => n + s.items.length, 0);
const units = sections.filter(s => s.unit);
console.log(`${sections.length} sections, ${rows} rows; ${units.length} changes, ${units.reduce((n, s) => n + s.items.length, 0)} rows waiting`);
