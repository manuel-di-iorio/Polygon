// Count code lines in all editor .gml scripts (poly_ed_*).
// Run: node tools/count_lines.js
var fs = require("fs");
var path = require("path");

var SCRIPTS_DIR = path.join(__dirname, "..", "..", "scripts");
var PREFIX = "poly_";
var EXT = ".gml";

function collectGmlFiles(dir) {
  var out = [];
  var entries = fs.readdirSync(dir, { withFileTypes: true });
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i];
    var full = path.join(dir, e.name);
    if (e.isDirectory()) {
      out = out.concat(collectGmlFiles(full));
    } else if (
      e.isFile() &&
      (e.name.indexOf(PREFIX) === 0) &&
      e.name.slice(-EXT.length) === EXT
    ) {
      out.push(full);
    }
  }
  return out;
}

function countLines(filePath) {
  var content = fs.readFileSync(filePath, "utf8");
  if (content.length === 0) return 0;
  var lines = content.split(/\r\n|\r|\n/);
  // Do not count the phantom empty line after a trailing newline.
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines.length;
}

var files = collectGmlFiles(SCRIPTS_DIR).sort();
if (files.length === 0) {
  console.log(
    "No files matching " + PREFIX + "*" + EXT + " found in " + SCRIPTS_DIR
  );
  process.exit(0);
}

var total = 0;
for (var f = 0; f < files.length; f++) {
  var n = countLines(files[f]);
  total += n;
  var rel = path.relative(path.join(__dirname, ".."), files[f]);
  console.log(n + "\t" + rel);
}
console.log("------------------------");
console.log(total + "\tTOTAL (" + files.length + " files)");
