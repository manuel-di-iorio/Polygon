// Find guards (X == undefined) where X was already dereferenced earlier
// in the same function body (guard provably dead).
var fs = require("fs");
var path = require("path");
var ROOT = path.join(__dirname, "..", "..");
function collect(dir, out) {
  out = out || [];
  fs.readdirSync(dir, { withFileTypes: true }).forEach(function (e) {
    var full = path.join(dir, e.name);
    if (e.isDirectory()) collect(full, out);
    else if (e.isFile() && e.name.slice(-4) === ".gml") out.push(full);
  });
  return out;
}
var files = collect(path.join(ROOT, "scripts")).sort();
files.forEach(function (f) {
  var lines = fs.readFileSync(f, "utf8").split("\n");
  var fnStart = -1, fnName = "";
  for (var i = 0; i < lines.length; i++) {
    var m = /^[ \t]*function[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(/.exec(lines[i]);
    if (m) { fnStart = i; fnName = m[1]; continue; }
    var g = /^[ \t]*if[ \t]*\(([^)]*)\)/.exec(lines[i]);
    if (g && fnStart >= 0) {
      var vars = [];
      var gm = /([A-Za-z_][A-Za-z0-9_$]*) == undefined/g, vm;
      while ((vm = gm.exec(g[1])) !== null) vars.push(vm[1]);
      if (vars.length === 0) continue;
      vars.forEach(function (v) {
      var deref = new RegExp(v.replace(/\$/g, "\\$") + "[.\\[]");
      for (var k = fnStart; k < i; k++) {
        var code = lines[k].replace(/\/\/.*$/, "");
        var nos = code.replace(/"([^"\\]|\\.)*"/g, '""');
        if (deref.test(nos)) {
          console.log(path.relative(ROOT, f) + ":" + (i + 1) + " " + fnName + " dead-guard on " + v + " (deref at " + (k + 1) + " :: " + lines[k].trim().slice(0, 90) + ")");
          console.log("    guard: " + lines[i].trim().slice(0, 140));
          break;
        }
      }
      });
    }
  }
});
console.log("done");
