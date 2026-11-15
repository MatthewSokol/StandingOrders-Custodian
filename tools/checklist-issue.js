// Builds the body of the standing "Next release testing" GitHub issue from RELEASING.md's checklist and
// TESTING.md: each 2.2 group's "`TESTING.md` 5.9–5.12" row is written out as the TESTING.md rows it
// names (ids 2.2.<group>.<TESTING id>), so every row can be ticked on the issue.
// Usage: node tools/checklist-issue.js [--build <text>] [--keep <current issue body file>] > body.md
// --keep carries ticks over from the current issue body (matched by row id).
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const read = f => fs.readFileSync(path.join(root, f), "utf8").replace(/\r\n/g, "\n");
const arg = name => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : null; };

// TESTING.md rows by id
const testing = {};
for (const m of read("TESTING.md").matchAll(/^- \[( |x)\] (\d+\.\d+) (.*)$/gm)) testing[m[2]] = m[3];

// Ticks already on the issue, by id
const kept = {};
const keepFile = arg("--keep");
if (keepFile) for (const m of fs.readFileSync(keepFile, "utf8").matchAll(/^- \[x\] ([\d.]+[a-z.]*) /gim)) kept[m[1]] = true;

const rel = read("RELEASING.md");
const start = rel.indexOf("<details open>\n<summary><b>1 Automated");
const end = rel.indexOf("</details>", rel.indexOf("<summary><b>3 Deploy")) + "</details>".length;
if (start < 0 || end < start) throw new Error("checklist not found in RELEASING.md");
const waiting = (rel.match(/\*\*(Waiting since the last release[^*]*)\*\*/) || [])[1] || "";

// Expand "`TESTING.md` 1.1–1.7, 5.13–5.32: title" rows
function ids(ranges) {
  const out = [];
  for (const r of ranges.split(/,\s*/)) {
    const [a, b = a] = r.split(/[–-]/).map(s => s.trim());
    const [sec, from] = a.split(".").map(Number), to = Number(b.split(".")[1]);
    for (let n = from; n <= to; n++) out.push(`${sec}.${n}`);
  }
  return out;
}
let rows = 0, missing = [];
let body = rel.slice(start, end).replace(/^- \[ \] (2\.2\.\d+)\.\d+ `TESTING\.md` ([\d.,–\s-]+): (.*)$/gm, (_, group, ranges, title) => {
  const lines = [`*From \`TESTING.md\` ${ranges.trim()}: ${title}*`, ""];
  for (const id of ids(ranges)) {
    if (!testing[id]) { missing.push(id); continue; }
    lines.push(`- [ ] ${group}.${id} ${testing[id]}`);
  }
  return lines.join("\n");
});
if (missing.length) throw new Error("TESTING.md rows not found: " + missing.join(", "));

// Ticks from the issue; count rows
body = body.replace(/^- \[ \] ([\d.]+[a-z.]*) /gm, (m, id) => { rows++; return kept[id] ? `- [x] ${id} ` : m; });
const done = (body.match(/^- \[x\] /gm) || []).length;
const problems = (body.match(/\.fix /g) || []).length;

const build = arg("--build") || "(not stamped)";
process.stdout.write(`Standing checklist for the next release: rows are added as each unit of work starts (see \`RELEASING.md\` for the rules and row tags; \`TESTING.md\` is the full regression suite). Built from both with \`node tools/checklist-issue.js\`.

\`\`\`
Build under test: ${build}        Open problems: ${problems}
${waiting}        Done: ${done} / ${rows}
\`\`\`

\`<env>\` below means \`node ~/.claude/skills/wow-mod-dev/scripts/wow-env.js --client _forever_\`. The game must be fully closed for every \`<env>\` command.

${body}
`);
