// Lua 5.1 limits the test VM (Lua 5.3) doesn't enforce: at most 200 locals in one scope and 60
// upvalues per function. WoW refuses to load a file that breaks either. This is an estimate from the
// source text: it counts the file-level locals each function uses (nested functions included).
// Usage: node tools/limits.js Faves/Faves.lua
const fs = require("fs");
const file = process.argv[2];
let src = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
src = src.replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, (m) => m.replace(/[^\n]/g, " "));
src = src.replace(/\[(=*)\[[\s\S]*?\]\1\]/g, (m) => m.replace(/[^\n]/g, " "));
src = src.replace(/--[^\n]*/g, "");
src = src.replace(/"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'/g, '""');

// File-level locals: declarations at column 0.
const top = new Set();
for (const line of src.split("\n")) {
  let m = line.match(/^local\s+function\s+([A-Za-z_]\w*)/);
  if (m) { top.add(m[1]); continue; }
  m = line.match(/^local\s+([^=]+?)\s*(=|$)/);
  if (m) m[1].split(",").map(s => s.trim()).filter(Boolean).forEach(n => top.add(n));
}

// Walk tokens, tracking function bodies with a block stack.
const re = /[A-Za-z_]\w*|\.\.\.|\.\.|\d+\.\d*|[.:]/g; // ".." and numbers like 0.5 aren't field access
const tokens = [];
let m;
while ((m = re.exec(src))) tokens.push({ t: m[0], line: src.slice(0, m.index).split("\n").length });
const OPEN = new Set(["function", "if", "do", "repeat"]);
const stack = [];
const funcs = [];
for (let i = 0; i < tokens.length; i++) {
  const { t, line } = tokens[i];
  const prev = tokens[i - 1] && tokens[i - 1].t;
  if (prev === "." || prev === ":") continue; // field name, not a variable
  if (OPEN.has(t)) {
    const entry = { kw: t, line, used: new Set(), own: new Set() };
    stack.push(entry);
    if (t === "function") funcs.push(entry);
    continue;
  }
  if (t === "end" || t === "until") { stack.pop(); continue; }
  if (top.has(t)) {
    // every enclosing function needs it as an upvalue (unless declared inside it; rough)
    for (const s of stack) if (s.kw === "function") s.used.add(t);
  }
}
let bad = 0;
for (const f of funcs) {
  if (f.used.size > 60) {
    bad++;
    console.log(`FAIL ${file}:${f.line} function uses ${f.used.size} file-level locals (Lua 5.1 allows 60 upvalues)`);
  }
}
const worst = funcs.reduce((a, f) => (f.used.size > (a ? a.used.size : -1) ? f : a), null);
if (top.size > 200) { bad++; console.log(`FAIL ${file}: ${top.size} file-level locals (Lua 5.1 allows 200)`); }
console.log(`${file}: ${top.size} file-level locals (max 200); most upvalues in one function: ${worst ? worst.used.size : 0} at line ${worst ? worst.line : "-"} (max 60)${bad ? "" : " - ok"}`);
process.exitCode = bad ? 1 : 0;
