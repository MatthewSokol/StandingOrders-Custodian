// Loads the addon in a Lua VM (fengari, Lua 5.3) with a stubbed WoW API, then runs a script that fires
// events and slash commands and checks the results.
// Usage: node tools/harness.js Faves [SavedVariables.lua] tools/smoke.lua
// Setup once: (cd tools && npm install)
// A green run has no line starting with ERROR, FAIL, LOAD ERROR, COMPILE ERROR or HARNESS; the exit
// code is 1 otherwise, so a script can tell.
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const fs = require("fs"), path = require("path");
const [dir, sv, ...script] = process.argv.slice(2);
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
// Count problem lines from both sides: fengari's Lua print() writes straight to stdout, not console.log.
let bad = 0, partial = "";
const write = process.stdout.write.bind(process.stdout);
process.stdout.write = (chunk, ...rest) => {
  const lines = (partial + String(chunk)).split("\n");
  partial = lines.pop();
  for (const line of lines) if (/^(ERROR|FAIL|LOAD ERROR|COMPILE ERROR|HARNESS)/.test(line)) bad++;
  return write(chunk, ...rest);
};
const log = (s) => write(s + "\n"); // the final verdict line, not counted
function run(src, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring(name)) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
    console.log("HARNESS ERROR " + name + ": " + lua.lua_tojsstring(L, -1)); lua.lua_pop(L, 1);
  }
}
const addon = path.basename(path.resolve(dir));
run(fs.readFileSync(path.join(__dirname, "wowstub.lua"), "utf8"), "wowstub");
if (sv) run(fs.readFileSync(sv, "utf8"), "SavedVariables");
const toc = fs.readFileSync(path.join(dir, addon + ".toc"), "utf8").split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith("#"));
for (const f of toc) {
  lua.lua_getglobal(L, to_luastring("LOADFILE"));
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(dir, f), "utf8")));
  lua.lua_pushstring(L, to_luastring(f));
  lua.lua_pushstring(L, to_luastring(addon));
  if (lua.lua_pcall(L, 3, 0, 0) !== 0) { console.log("HARNESS " + lua.lua_tojsstring(L, -1)); lua.lua_pop(L, 1); }
}
for (const s of script) run(fs.readFileSync(s, "utf8"), path.basename(s));
log(bad ? `\n${bad} problem line(s): NOT green` : "\nGREEN: no errors or failed checks");
process.exitCode = bad ? 1 : 0;
