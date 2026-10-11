// List every call site for named functions. Run: node other/tools/callsites.js <fn...>
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
var files = collect(path.join(ROOT, "scripts")).concat(collect(path.join(ROOT, "objects"))).sort();
var names = process.argv.slice(2);
files.forEach(function (f) {
  var lines = String(fs.readFileSync(f, "utf8")).split(/\r\n|\r|\n/);
  lines.forEach(function (ln, i) {
    names.forEach(function (nm) {
      var re = new RegExp("(function[ \t]+" + nm + ")|([^A-Za-z0-9_$.]" + nm + ")(\\s*\\()", "g");
      var m;
      while ((m = re.exec(ln)) !== null) {
        var kind = m[1] ? "DEF " : (m[3] ? "CALL" : "REF ");
        console.log(nm + " " + kind + " " + path.relative(ROOT, f).split(path.sep).join("/") + ":" + (i + 1) + " :: " + ln.trim().slice(0, 140));
      }
    });
  });
});
