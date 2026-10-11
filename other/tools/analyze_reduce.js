// Analyze editor GML for: pure forwarder functions, unused params,
// single-statement braced blocks. Run: node other/tools/analyze_reduce.js
var fs = require("fs");
var path = require("path");

var ROOT = path.join(__dirname, "..", "..");
var DIRS = ["scripts", "objects"];

function collect(dir, out) {
  out = out || [];
  var entries = fs.readdirSync(dir, { withFileTypes: true });
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i];
    var full = path.join(dir, e.name);
    if (e.isDirectory()) out = collect(full, out);
    else if (e.isFile() && e.name.slice(-4) === ".gml") out.push(full);
  }
  return out;
}

function splitLines(t) {
  var l = String(t).split(/\r\n|\r|\n/);
  if (l.length && l[l.length - 1] === "") l.pop();
  return l;
}

function stripStrings(s) {
  return s.replace(/"([^"\\]|\\.)*"/g, '""').replace(/'([^'\\]|\\.)*'/g, "''");
}

var files = [];
DIRS.forEach(function (d) { files = files.concat(collect(path.join(ROOT, d))); });
files.sort();

// file -> [{name, params, startLine, endLine, body}]
var funcs = [];
files.forEach(function (f) {
  var lines = splitLines(fs.readFileSync(f, "utf8"));
  for (var i = 0; i < lines.length; i++) {
    var m = /^[ \t]*function[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(([^)]*)\)/.exec(lines[i]);
    if (!m) continue;
    var depth = 0, j = i, seen = false;
    for (; j < lines.length; j++) {
      var code = stripStrings(lines[j].replace(/\/\/.*$/, ""));
      for (var k = 0; k < code.length; k++) {
        if (code[k] === "{") { depth++; seen = true; }
        else if (code[k] === "}") depth--;
      }
      if (seen && depth === 0) break;
    }
    funcs.push({
      file: f, name: m[1],
      params: m[2].trim() === "" ? [] : m[2].split(",").map(function (s) {
        return s.trim().split("=")[0].trim();
      }),
      start: i, end: j, lines: lines.slice(i, j + 1)
    });
    i = j;
  }
});

// call counts (exclude definitions)
var calls = {};
funcs.forEach(function (fn) {
  var key = fn.name;
  calls[key] = calls[key] || { defs: [], n: 0 };
  calls[key].defs.push(fn.file + ":" + (fn.start + 1));
});
var allText = files.map(function (f) { return fs.readFileSync(f, "utf8"); }).join("\n");
Object.keys(calls).forEach(function (name) {
  var re = new RegExp("[^A-Za-z0-9_$.]" + name.replace(/\$/g, "\\$") + "\\s*\\(", "g");
  var m = allText.match(re);
  // occurrences include the definition itself ("function name(" preceded by space)
  calls[name].n = m ? m.length : 0;
});

console.log("=== PURE FORWARDERS (1 caller or fewer besides def, body <= 3 stmts) ===");
funcs.forEach(function (fn) {
  if (fn.file.indexOf("objects") >= 0) return;
  var body = fn.lines.slice(1, -1).map(function (l) { return l.trim(); })
    .filter(function (l) { return l !== "" && l.indexOf("//") !== 0; });
  if (body.length > 4) return;
  var c = (calls[fn.name] ? calls[fn.name].n : 0) - 1; // minus def
  if (c > 1) return;
  // pure if body is single return/call/assign delegating to another __polygon_*
  var joined = body.join(" ");
  if (/__polygon_/.test(joined) || body.length <= 2) {
    console.log(fn.file.replace(ROOT, "").replace(/\\/g, "/") + ":" + (fn.start + 1) +
      " " + fn.name + "(" + fn.params.join(", ") + ") callers=" + c + " bodyLines=" + body.length);
  }
});

console.log("");
console.log("=== UNUSED PARAMS (param never appears in body) ===");
funcs.forEach(function (fn) {
  if (fn.params.length === 0) return;
  var bodyText = stripStrings(fn.lines.slice(1).join("\n").replace(/\/\/.*$/gm, ""));
  fn.params.forEach(function (p, idx) {
    if (p === "") return;
    var re = new RegExp("[^A-Za-z0-9_$.]" + p.replace(/\$/g, "\\$") + "([^A-Za-z0-9_]|$)");
    if (!re.test("\n" + bodyText)) {
      console.log(fn.file.replace(ROOT, "").replace(/\\/g, "/") + ":" + (fn.start + 1) +
        " " + fn.name + " param#" + idx + " " + p);
    }
  });
});

console.log("");
console.log("=== SINGLE-STMT BRACED IF/FOR/WHILE (collapsible) ===");
var collapseCount = 0, blankAfter = 0;
files.forEach(function (f) {
  var lines = splitLines(fs.readFileSync(f, "utf8"));
  for (var i = 0; i + 2 < lines.length; i++) {
    var a = lines[i], b = lines[i + 1], c = lines[i + 2];
    var m = /^([ \t]*)(if|for|while)\b.*\{\s*$/.exec(a);
    if (!m) continue;
    var bt = b.trim();
    if (bt === "" || bt.indexOf("//") === 0 || /\/\//.test(stripStrings(b))) continue;
    if (!/;\s*$/.test(bt) || /[{}]/.test(stripStrings(b))) continue;
    if (!/^[ \t]*\}\s*$/.test(c)) continue;
    var d = lines[i + 3] || "";
    if (/^[ \t]*else\b/.test(d)) continue;
    collapseCount++;
    if ((lines[i + 3] || "").trim() === "") blankAfter++;
  }
});
console.log("collapsible blocks: " + collapseCount + ", with blank line after: " + blankAfter);
