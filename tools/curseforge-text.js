// Writes docs/curseforge/description.md: README.md made ready to paste into CurseForge's Markdown description
// editor. The repo is private, so its own images and docs links would break there: the logo line goes (the project
// logo shows anyway) and links to repo files become plain text. Run it after any README change:
//   node tools/curseforge-text.js
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
let text = fs.readFileSync(path.join(root, "README.md"), "utf8");
text = text.replace(/^<img [^>]*>\r?\n\r?\n/m, "");
text = text.replace(/ \[docs\/bag-addons\.md\]\(docs\/bag-addons\.md\) has the details and the plan\./, "");
text = text.replace(/ See \[docs\/specific-item-instances\.md\]\(docs\/specific-item-instances\.md\) for what it would take\./,
  " It's planned for a later version.");
const left = text.match(/\]\((?!https?:)[^)]+\)|<img /g);
if (left) { console.error("Repo-relative links left: " + left.join(", ")); process.exit(1); }
const out = path.join(root, "docs", "curseforge", "description.md");
fs.writeFileSync(out, text);
console.log("Wrote " + path.relative(root, out) + " (" + text.length + " characters)");
