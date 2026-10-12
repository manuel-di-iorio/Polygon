// Drop unused params from defs and all call sites. Run: node other/tools/drop_unused_params.js
// Rules: function name -> param indices to drop (0-based).
// Writes .tmpdrop files for review; does NOT overwrite originals.
var fs = require("fs");
var path = require("path");

var ROOT = path.join(__dirname, "..", "..");

var RULES = {
  "__poly_overlay_light": [0]
};

function collect(dir, out) {
  out = out || [];
  fs.readdirSync(dir, { withFileTypes: true }).forEach(function (e) {
    var full = path.join(dir, e.name);
    if (e.isDirectory()) collect(full, out);
    else if (e.isFile() && e.name.slice(-4) === ".gml") out.push(full);
  });
  return out;
}

// 0=code, 1=string, 2=comment
function classify(src) {
  var cls = new Array(src.length).fill(0);
  var i = 0, quote = null, escaped = false, block = false, line = false;
  while (i < src.length) {
    var c = src[i], n = src[i + 1];
    if (line) { cls[i] = 2; if (c === "\n") line = false; i++; continue; }
    if (block) {
      cls[i] = 2;
      if (c === "*" && n === "/") { cls[i + 1] = 2; block = false; i += 2; }
      else i++;
      continue;
    }
    if (quote) {
      cls[i] = 1;
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === quote) quote = null;
      i++;
      continue;
    }
    if (c === "/" && n === "/") { cls[i] = cls[i + 1] = 2; line = true; i += 2; continue; }
    if (c === "/" && n === "*") { cls[i] = cls[i + 1] = 2; block = true; i += 2; continue; }
    if (c === '"' || c === "'") { cls[i] = 1; quote = c; i++; continue; }
    i++;
  }
  return cls;
}

function splitArgs(src, cls, openIdx) {
  var args = [], depth = 0, start = openIdx + 1, i = openIdx;
  while (i < src.length) {
    if (cls[i] !== 0) { i++; continue; }
    var c = src[i];
    if (c === "(" || c === "[" || c === "{") depth++;
    else if (c === ")" || c === "]" || c === "}") {
      depth--;
      if (depth === 0 && c === ")") { args.push([start, i]); return { args: args, close: i }; }
      if (depth < 0) return null;
    } else if (c === "," && depth === 1) { args.push([start, i]); start = i + 1; }
    i++;
  }
  return null;
}

function trimSpan(src, s, e) {
  while (s < e && /[ \t\r\n]/.test(src[s])) s++;
  while (e > s && /[ \t\r\n]/.test(src[e - 1])) e--;
  return [s, e];
}

var files = collect(path.join(ROOT, "scripts")).concat(collect(path.join(ROOT, "objects"))).sort();
var report = [];
var ruleNames = Object.keys(RULES);

files.forEach(function (f) {
  var src = fs.readFileSync(f, "utf8");
  var cls = classify(src);
  var head = "", pos = 0, changed = 0, idx = 0;
  var hits = [];
  ruleNames.forEach(function (fn) {
    var drops = RULES[fn];
    var i2 = 0;
    while (i2 < src.length) {
      var at = src.indexOf(fn, i2);
      if (at < 0) break;
      var before = at > 0 ? src[at - 1] : " ";
      if (/[A-Za-z0-9_$]/.test(before) || cls[at] !== 0) { i2 = at + fn.length; continue; }
      var rest = src.slice(at + fn.length).match(/^[ \t]*\(/);
      if (!rest) { i2 = at + fn.length; continue; }
      var openIdx = at + fn.length + rest[0].length - 1;
      if (cls[openIdx] !== 0) { i2 = at + fn.length; continue; }
      var split = splitArgs(src, cls, openIdx);
      if (!split) { i2 = at + fn.length; continue; }
      if (split.args.length === 1) {
        var only = trimSpan(src, split.args[0][0], split.args[0][1]);
        if (only[0] >= only[1]) { i2 = split.close + 1; continue; }
      }
      var bad = drops.some(function (di) { return di < 0 || di >= split.args.length; });
      if (bad) { i2 = split.close + 1; continue; }
      hits.push({ fn: fn, drops: drops, split: split });
      i2 = split.close + 1;
    }
  });
  if (hits.length === 0) return;
  // apply hits left-to-right
  hits.sort(function (x, y) { return x.split.args[0][0] - y.split.args[0][0]; });
  hits.forEach(function (h) {
    var cuts = h.drops.map(function (di) {
      var t = trimSpan(src, h.split.args[di][0], h.split.args[di][1]);
      if (h.split.args.length === 1) return [t[0], t[1]];
      if (di < h.split.args.length - 1) {
        var nt = trimSpan(src, h.split.args[di + 1][0], h.split.args[di + 1][1]);
        return [t[0], nt[0]];
      }
      var pt = trimSpan(src, h.split.args[di - 1][0], h.split.args[di - 1][1]);
      return [pt[1], t[1]];
    });
    cuts.sort(function (x, y) { return x[0] - y[0]; });
    head += src.slice(pos, cuts[0][0]);
    var prevEnd = cuts[0][1];
    for (var ci = 1; ci < cuts.length; ci++) {
      head += src.slice(prevEnd, cuts[ci][0]);
      prevEnd = cuts[ci][1];
    }
    head += src.slice(prevEnd, h.split.close + 1);
    pos = h.split.close + 1;
    changed++;
  });
  head += src.slice(pos);
  fs.writeFileSync(f + ".tmpdrop", head, "utf8");
  var byFn = {};
  hits.forEach(function (h) { byFn[h.fn] = (byFn[h.fn] || 0) + 1; });
  Object.keys(byFn).forEach(function (fn) {
    report.push(fn + " :: " + path.relative(ROOT, f) + " :: " + byFn[fn] + " site(s)");
  });
});

report.forEach(function (r) { console.log(r); });
console.log("Wrote .tmpdrop files. Review, then rename over originals.");
