// Lists Lua string literals with a bare "|" that isn't a WoW escape. In chat text "|" starts an escape
// (|cAARRGGBB color, |r reset, |T texture, |H link, |n newline...), so "a|rare" shows as "aare".
// Write a literal pipe as "||". Usage: node tools/pipes.js StandingOrders_Quartermaster/*.lua  (exit 1 if any are found)
const fs = require("fs");
let found = 0;
for (const f of process.argv.slice(2)) {
  fs.readFileSync(f, "utf8").split("\n").forEach((line, i) => {
    if (/^\s*--/.test(line) || line.includes("pipes:ok")) return; // "-- pipes:ok": text never shown in chat
    for (const m of line.matchAll(/"((?:\\.|[^"\\])*)"/g)) {
      const s = m[1].replace(/\|\|/g, "");
      if (/\|(?![cC][0-9a-fA-F]{8}|[rRTtHhAaKkn])/.test(s)) {
        found++;
        console.log(`${f}:${i + 1}: ${m[1]}`);
      }
    }
  });
}
if (!found) console.log("no bare pipes");
process.exit(found ? 1 : 0);
