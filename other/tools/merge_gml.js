// Merge all editor .gml sources into a single dump for external analysis.
// Run: node other/tools/merge_gml.js [output]
// Default output: other/tools/polygon_merged.gml (git-ignored, generated).
var fs = require("fs");
var path = require("path");

var ROOT = path.join(__dirname, "..", "..");
var DIRS = ["scripts", "objects"];
var EXT = ".gml";
var DEFAULT_OUT = path.join(__dirname, "polygon_merged.gml");

function collectGmlFiles(dir) {
  var out = [];
  var entries = fs.readdirSync(dir, { withFileTypes: true });
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i];
    var full = path.join(dir, e.name);
    if (e.isDirectory()) {
      out = out.concat(collectGmlFiles(full));
    } else if (e.isFile() && e.name.slice(-EXT.length) === EXT) {
      out.push(full);
    }
  }
  return out;
}

function splitLines(text) {
  var lines = String(text).split(/\r\n|\r|\n/);
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

var files = [];
for (var d = 0; d < DIRS.length; d++) {
  files = files.concat(collectGmlFiles(path.join(ROOT, DIRS[d])));
}
files.sort();

if (files.length === 0) {
  console.log("No .gml files found.");
  process.exit(0);
}

// First pass: read everything, collect per-file function defs.
var blobs = [];
var totalCode = 0;
for (var f = 0; f < files.length; f++) {
  var rel = path.relative(ROOT, files[f]).split(path.sep).join("/");
  var lines = splitLines(fs.readFileSync(files[f], "utf8"));
  var funcs = [];
  for (var l = 0; l < lines.length; l++) {
    var m = /^[ \t]*function[ \t]+([A-Za-z_][A-Za-z0-9_]*)/.exec(lines[l]);
    if (m) funcs.push({ name: m[1], line: l + 1 });
  }
  blobs.push({ rel: rel, lines: lines, funcs: funcs });
  totalCode += lines.length;
}

// Second pass: emit with global line numbers for the TOC.
var toc = [];
var body = [];
var lineno = 1;
function emit(line) {
  body.push(line);
  lineno++;
}

var funcTotal = 0;
for (var b = 0; b < blobs.length; b++) {
  funcTotal += blobs[b].funcs.length;
}

var header = [
  "// polygon_merged.gml -- GENERATED, do not edit.",
  "// Source: " + files.length + " .gml files, " + totalCode + " lines, " + funcTotal + " functions.",
  "// Generated: " + new Date().toISOString() + " via node other/tools/merge_gml.js",
  "//",
  "// TABLE OF CONTENTS (file -> functions with merged-file line numbers)",
];
for (var t = 0; t < blobs.length; t++) {
  header.push("//   " + blobs[t].rel + " (" + blobs[t].lines.length + " lines, " + blobs[t].funcs.length + " funcs)");
}
header.push("//");

var headerSize = header.length + 1; // +1 for the blank line after header
// Compute section start lines: TOC lines first, then body.
var tocLines = [];
for (var c = 0; c < blobs.length; c++) {
  var entries = [];
  for (var q = 0; q < blobs[c].funcs.length; q++) {
    entries.push("  " + blobs[c].funcs[q].name);
  }
  tocLines.push({ rel: blobs[c].rel, funcs: entries });
}
// TOC block size = sum over files of (1 + funcs)
var tocSize = 0;
for (var z = 0; z < tocLines.length; z++) tocSize += 1 + tocLines[z].funcs.length;
var bodyStart = headerSize + tocSize + 2; // TOC + blank + separator comment

var cursor = bodyStart;
var tocOut = [];
for (var k = 0; k < blobs.length; k++) {
  var secHead = 2; // section header lines before code
  tocOut.push("// " + blobs[k].rel + " @ " + (cursor + secHead));
  for (var g = 0; g < blobs[k].funcs.length; g++) {
    tocOut.push("//   " + blobs[k].funcs[g].name + " @ " + (cursor + secHead + blobs[k].funcs[g].line - 1));
  }
  cursor += secHead + blobs[k].lines.length + 1; // +1 blank line after section
}

var out = header.concat(tocOut, [""], ["//", "// MERGED BODY", "//"]);
for (var s = 0; s < blobs.length; s++) {
  out.push("// ===== FILE: " + blobs[s].rel + " (" + blobs[s].lines.length + " lines) =====");
  out.push("// -----");
  out = out.concat(blobs[s].lines);
  out.push("");
}

var dest = DEFAULT_OUT;
for (var ai = 2; ai < process.argv.length; ai++) {
  if (process.argv[ai].slice(0, 2) !== "--")  dest = path.resolve(process.argv[ai]);
}
var noToc = process.argv.indexOf("--no-toc") >= 0;
if (noToc) {
  var bodyOnly = ["// polygon_merged.gml -- GENERATED, do not edit (no TOC)."];
  for (var s2 = 0; s2 < blobs.length; s2++) {
    bodyOnly.push("// ===== FILE: " + blobs[s2].rel + " (" + blobs[s2].lines.length + " lines) =====");
    bodyOnly.push("// -----");
    bodyOnly = bodyOnly.concat(blobs[s2].lines);
    bodyOnly.push("");
  }
  fs.writeFileSync(dest, bodyOnly.join("\n") + "\n", "utf8");
  console.log("merge_gml: " + files.length + " files, " + totalCode + " source lines -> " + path.relative(ROOT, dest) + " (" + bodyOnly.length + " lines, no TOC)");
} else {
  fs.writeFileSync(dest, out.join("\n") + "\n", "utf8");
  console.log(
    "merge_gml: " + files.length + " files, " + totalCode + " source lines, " +
    funcTotal + " functions -> " + path.relative(ROOT, dest) + " (" + out.length + " lines)"
  );
}
