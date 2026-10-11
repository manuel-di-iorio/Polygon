// Collapse single-statement braced if/for/while blocks onto one line.
// Run: node other/tools/compact_gml.js [--apply]
// Default is dry-run (counts only). With --apply, rewrites .gml files.
var fs = require("fs");
var path = require("path");

var ROOT = path.join(__dirname, "..", "..");
var APPLY = process.argv.indexOf("--apply") >= 0;

function collect(dir, out) {
  out = out || [];
  fs.readdirSync(dir, { withFileTypes: true }).forEach(function (e) {
    var full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if ([".git", "Build", "node_modules"].indexOf(e.name) < 0) collect(full, out);
    } else if (e.isFile() && e.name.slice(-4) === ".gml" && e.name !== "polygon_merged.gml") {
      out.push(full);
    }
  });
  return out;
}

function splitLines(t) {
  var l = String(t).split(/\r\n|\r|\n/);
  if (l.length && l[l.length - 1] === "") l.pop();
  return l;
}

function hasComment(line) {
  // conservative: any // outside strings blocks collapsing
  var q = null, esc = false;
  for (var i = 0; i < line.length - 1; i++) {
    var c = line[i];
    if (q) {
      if (esc) esc = false;
      else if (c === "\\") esc = true;
      else if (c === q) q = null;
    } else if (c === '"' || c === "'") {
      q = c;
    } else if (c === "/" && line[i + 1] === "/") {
      return true;
    }
  }
  return false;
}

function stripForCheck(line) {
  // remove string contents for brace/paren checks
  var out = "", q = null, esc = false;
  for (var i = 0; i < line.length; i++) {
    var c = line[i];
    if (q) {
      if (esc) esc = false;
      else if (c === "\\") esc = true;
      else if (c === q) q = null;
    } else if (c === '"' || c === "'") {
      q = c;
    } else {
      out += c;
    }
  }
  return out;
}

function tryCollapse(lines) {
  var total = 0, blanks = 0;
  var pass = 0;
  var changed = true;
  while (changed && pass < 10) {
    changed = false;
    pass++;
    var out = [];
    for (var i = 0; i < lines.length; i++) {
      var a = lines[i], b = lines[i + 1], c = lines[i + 2];
      var m = /^([ \t]*)(if|for|while)\b(.*)\{\s*$/.exec(a);
      var ok = false;
      if (m && b !== undefined && c !== undefined) {
        var indent = m[1], kw = m[2], cond = m[3];
        var bt = b.replace(/^\s+/, "");
        var condStripped = stripForCheck(cond);
        var stmtStripped = stripForCheck(b);
        if (bt !== "" && bt[0] !== "#" &&
          /;\s*$/.test(bt) &&
          condStripped.indexOf("{") < 0 && condStripped.indexOf("}") < 0 &&
          stmtStripped.indexOf("{") < 0 && stmtStripped.indexOf("}") < 0 &&
          !hasComment(a) && !hasComment(b) &&
          /^[ \t]*\}\s*$/.test(c)) {
          var d = lines[i + 3];
          var dTrim = (d === undefined ? "" : d.replace(/^\s+/, ""));
          if (dTrim.indexOf("else") !== 0) {
            // balanced parens in header (condition closed on this line)?
            var opens = (condStripped.match(/\(/g) || []).length;
            var closes = (condStripped.match(/\)/g) || []).length;
            if (opens === closes) {
              out.push(indent + kw + cond + " " + bt);
              total++;
              // drop immediately-following blank lines
              var j = i + 3;
              while (j < lines.length && lines[j].trim() === "") { j++; blanks++; }
              i = j - 1;
              changed = true;
              continue;
            }
          }
        }
      }
      out.push(a);
    }
    lines = out;
  }
  return { lines: lines, total: total, blanks: blanks };
}

var files = collect(ROOT).sort();
var grandT = 0, grandB = 0, changedFiles = 0;
files.forEach(function (f) {
  var src = fs.readFileSync(f, "utf8");
  var eol = src.indexOf("\r\n") >= 0 ? "\r\n" : "\n";
  var r = tryCollapse(splitLines(src));
  if (r.total > 0) {
    grandT += r.total;
    grandB += r.blanks;
    if (APPLY) {
      fs.writeFileSync(f, r.lines.join(eol) + eol, "utf8");
      changedFiles++;
    }
  }
});
console.log((APPLY ? "collapsed " : "would collapse ") + grandT + " blocks, " + grandB + " trailing blanks" +
  (APPLY ? " in " + changedFiles + " files." : "."));
