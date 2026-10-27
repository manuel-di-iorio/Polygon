// Finds statically dead GML code: functions, macros and enums that are never
// referenced, plus write-only globals.
//
// Usage:
//   node other/tools/find-deadcode.js [root] [--json] [--fail] [--help] [--roots=scripts,objects]
//
// Scope: all .gml files under the project root (excluding .git, Build and
// node_modules). Comments and string literals are blanked before counting
// references; names that appear ONLY inside them are reported in a separate
// bucket ("string/comment-only") instead of as dead. Exit code is 0 unless
// --fail is given and something is reported.
//
// Naming convention: `__poly_*` (leading double underscore) is internal,
// everything else (`poly_*`, `demo_*`, `ImGui*`, ...) is public API or
// binding surface. Public names with no internal callers are reported
// separately - they may be called by the game project, so they are NOT
// necessarily dead code. Only "dead internal" entries are safe-ish removal
// candidates (still verify: dynamic access by name string is invisible).
//
// Known limits: local `var` declarations are NOT tracked (only cross-file
// `global.x` variables are); dynamic access (e.g. variable_struct_get with a
// computed name) cannot be seen; a name referenced only from non-GML files
// (.yy, .md, .js) counts as unreferenced.

var fs = require("fs");
var path = require("path");

var DEFAULT_IGNORED = { ".git": true, "Build": true, "node_modules": true };
var GENERATED_FILES = { "polygon_merged.gml": true };

function parseArgs(argv) {
  var opts = { root: null, json: false, fail: false, help: false, roots: null };
  for (var i = 0; i < argv.length; i++) {
    var a = argv[i];
    if (a === "--json") {
      opts.json = true;
    } else if (a === "--fail") {
      opts.fail = true;
    } else if (a === "--help" || a === "-h") {
      opts.help = true;
    } else if (a.indexOf("--roots=") === 0) {
      opts.roots = a.slice("--roots=".length).split(",").filter(function (s) {
        return s.length > 0;
      });
    } else if (a.indexOf("--") === 0) {
      fail("unknown flag: " + a);
    } else if (opts.root === null) {
      opts.root = a;
    } else {
      fail("unexpected argument: " + a);
    }
  }
  return opts;
}

function fail(msg) {
  process.stderr.write("find-deadcode: " + msg + "\n");
  process.stderr.write("usage: node find-deadcode.js [root] [--json] [--fail] [--help] [--roots=a,b]\n");
  process.exit(2);
}

// Internal by convention: leading double underscore. Everything else is
// public API / binding surface / sample code.
function isPublicName(name) {
  return name.indexOf("__") !== 0;
}

function toRel(root, file) {
  return path.relative(root, file).split(path.sep).join("/");
}

function collectGmlFiles(directory, files) {
  var entries;
  try {
    entries = fs.readdirSync(directory);
  } catch (e) {
    return files;
  }
  for (var i = 0; i < entries.length; i++) {
    var full = path.join(directory, entries[i]);
    var st;
    try {
      st = fs.statSync(full);
    } catch (e) {
      continue;
    }
    if (st.isDirectory()) {
      if (!DEFAULT_IGNORED[entries[i]]) {
        collectGmlFiles(full, files);
      }
    } else if (st.isFile() && entries[i].toLowerCase().lastIndexOf(".gml") === entries[i].length - 4) {
      if (!GENERATED_FILES[entries[i]]) {
        files.push(full);
      }
    }
  }
  return files;
}

// Blanks comments and string literals, preserving newlines so line numbers
// of the masked text match the original file.
function maskSource(src) {
  var out = [];
  var i = 0;
  var n = src.length;
  var state = "code";
  while (i < n) {
    var c = src.charAt(i);
    var nx = i + 1 < n ? src.charAt(i + 1) : "";
    if (state === "code") {
      if (c === "/" && nx === "/") {
        state = "line";
        out.push("  ");
        i += 2;
      } else if (c === "/" && nx === "*") {
        state = "block";
        out.push("  ");
        i += 2;
      } else if (c === '"') {
        state = "str";
        out.push(" ");
        i += 1;
      } else {
        out.push(c);
        i += 1;
      }
    } else if (state === "line") {
      if (c === "\n") {
        state = "code";
        out.push("\n");
        i += 1;
      } else if (c === "\r") {
        out.push(c);
        i += 1;
      } else {
        out.push(" ");
        i += 1;
      }
    } else if (state === "block") {
      if (c === "*" && nx === "/") {
        state = "code";
        out.push("  ");
        i += 2;
      } else if (c === "\n" || c === "\r") {
        out.push(c);
        i += 1;
      } else {
        out.push(" ");
        i += 1;
      }
    } else {
      // inside string literal
      if (c === "\\" && i + 1 < n) {
        out.push("  ");
        i += 2;
      } else if (c === '"') {
        state = "code";
        out.push(" ");
        i += 1;
      } else if (c === "\n" || c === "\r") {
        out.push(c);
        i += 1;
      } else {
        out.push(" ");
        i += 1;
      }
    }
  }
  return out.join("");
}

function lineStartsOf(text) {
  var starts = [0];
  for (var i = 0; i < text.length; i++) {
    if (text.charAt(i) === "\n") {
      starts.push(i + 1);
    }
  }
  return starts;
}

// 1-based line number for offset (offsets arrive in ascending order).
function makeLineFinder(starts) {
  var idx = 0;
  return function (offset) {
    while (idx + 1 < starts.length && starts[idx + 1] <= offset) {
      idx += 1;
    }
    return idx + 1;
  };
}

// word -> array of 1-based line numbers, built from masked text.
function indexWords(masked) {
  var map = {};
  var starts = lineStartsOf(masked);
  var lineOf = makeLineFinder(starts);
  var re = /[A-Za-z_][A-Za-z0-9_]*/g;
  var m;
  while ((m = re.exec(masked)) !== null) {
    var w = m[0];
    var line = lineOf(m.index);
    if (map[w] === undefined) {
      map[w] = [];
    }
    map[w].push(line);
  }
  return map;
}

function pushDef(list, kind, name, file, line) {
  list.push({ kind: kind, name: name, file: file, line: line });
}

function extractDefs(maskedLines) {
  var defs = [];
  var reFunc = /(?:^|[^A-Za-z0-9_#])function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/g;
  var reMacro = /^\s*#macro\s+([A-Za-z_][A-Za-z0-9_]*)/;
  var reEnum = /(?:^|[^A-Za-z0-9_])enum\s+([A-Za-z_][A-Za-z0-9_]*)/g;
  for (var li = 0; li < maskedLines.length; li++) {
    var line = maskedLines[li];
    var m;
    reFunc.lastIndex = 0;
    while ((m = reFunc.exec(line)) !== null) {
      pushDef(defs, "function", m[1], null, li + 1);
    }
    var mm = reMacro.exec(line);
    if (mm !== null) {
      pushDef(defs, "macro", mm[1], null, li + 1);
    }
    reEnum.lastIndex = 0;
    var me;
    while ((me = reEnum.exec(line)) !== null) {
      pushDef(defs, "enum", me[1], null, li + 1);
    }
  }
  return defs;
}

function rawHasRefOutside(rawLines, name, skipFile, skipLine) {
  var re = new RegExp("\\b" + name + "\\b");
  for (var i = 0; i < rawLines.length; i++) {
    if (re.test(rawLines[i])) {
      return true;
    }
  }
  return false;
}

function main() {
  var opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    process.stdout.write(
      "find-deadcode: static dead-code report for GML sources.\n" +
        "usage: node find-deadcode.js [root] [--json] [--fail] [--help] [--roots=a,b]\n" +
        "  root      project root (default: two levels above this script)\n" +
        "  --json    machine-readable output instead of text\n" +
        "  --fail    exit 1 when anything is reported (for CI)\n" +
        "  --roots   comma-separated subdirectories to scan, relative to root\n" +
        "Only `__*` (double underscore) counts as internal dead code; other\n" +
        "unused names are listed as public API that external code may call.\n"
    );
    return;
  }
  var root = opts.root ? path.resolve(opts.root) : path.resolve(__dirname, "..", "..");

  var allFiles = collectGmlFiles(root, []);
  var files = allFiles;
  if (opts.roots !== null) {
    files = allFiles.filter(function (f) {
      var rel = toRel(root, f);
      for (var i = 0; i < opts.roots.length; i++) {
        var r = opts.roots[i].replace(/\\/g, "/").replace(/\/$/, "");
        if (rel === r || rel.indexOf(r + "/") === 0) {
          return true;
        }
      }
      return false;
    });
  }
  files.sort();

  // Per-file data: masked lines, raw lines, word index.
  var fileData = files.map(function (f) {
    var src = fs.readFileSync(f, "utf8");
    var masked = maskSource(src);
    return {
      file: f,
      rel: toRel(root, f),
      rawLines: src.split(/\r\n|\n/),
      maskedLines: masked.split("\n"),
      words: indexWords(masked),
      globals: [],
    };
  });

  // Definitions.
  var defs = [];
  fileData.forEach(function (fd) {
    var ds = extractDefs(fd.maskedLines);
    ds.forEach(function (d) {
      d.file = fd.rel;
      defs.push(d);
    });
  });

  // References per defined name: count word occurrences outside the def line.
  var byName = {};
  defs.forEach(function (d) {
    if (byName[d.name] === undefined) {
      byName[d.name] = [];
    }
    byName[d.name].push(d);
  });

  var dead = { "function": [], macro: [], enum: [] };
  var stringOnly = { "function": [], macro: [], enum: [] };

  Object.keys(byName).forEach(function (name) {
    var ds = byName[name];
    var refCount = 0;
    fileData.forEach(function (fd) {
      var lines = fd.words[name];
      if (lines === undefined) {
        return;
      }
      for (var i = 0; i < lines.length; i++) {
        var isOwnDef = false;
        for (var j = 0; j < ds.length; j++) {
          if (ds[j].file === fd.rel && ds[j].line === lines[i]) {
            isOwnDef = true;
            break;
          }
        }
        if (!isOwnDef) {
          refCount += 1;
        }
      }
    });
    if (refCount > 0) {
      return;
    }
    // No code references: check raw text (strings/comments) per defining file.
    var elsewhere = false;
    var checked = {};
    ds.forEach(function (d) {
      if (checked[d.file]) {
        return;
      }
      checked[d.file] = true;
      var fd = null;
      for (var i = 0; i < fileData.length; i++) {
        if (fileData[i].rel === d.file) {
          fd = fileData[i];
          break;
        }
      }
      if (fd === null) {
        return;
      }
      var re = new RegExp("\\b" + name + "\\b");
      for (var li = 0; li < fd.rawLines.length; li++) {
        if (li + 1 !== d.line && re.test(fd.rawLines[li])) {
          elsewhere = true;
          break;
        }
      }
    });
    // Also scan OTHER files' raw text.
    if (!elsewhere) {
      var names = {};
      ds.forEach(function (d) {
        names[d.file] = true;
      });
      var reAll = new RegExp("\\b" + name + "\\b");
      for (var f = 0; f < fileData.length && !elsewhere; f++) {
        if (names[fileData[f].rel]) {
          continue;
        }
        for (var l = 0; l < fileData[f].rawLines.length; l++) {
          if (reAll.test(fileData[f].rawLines[l])) {
            elsewhere = true;
            break;
          }
        }
      }
    }
    var bucket = elsewhere ? stringOnly : dead;
    ds.forEach(function (d) {
      bucket[d.kind].push({ name: d.name, file: d.file, line: d.line });
    });
  });

  // Write-only globals: global.x assigned but never read.
  var globals = {};
  var reGlobal = /global\.([A-Za-z_][A-Za-z0-9_]*)/g;
  fileData.forEach(function (fd) {
    fd.maskedLines.forEach(function (line, li) {
      reGlobal.lastIndex = 0;
      var m;
      while ((m = reGlobal.exec(line)) !== null) {
        var gname = m[1];
        var rest = line.slice(m.index + m[0].length).replace(/^\s+/, "");
        var isWrite = rest.charAt(0) === "=" && rest.charAt(1) !== "=";
        if (globals[gname] === undefined) {
          globals[gname] = { name: gname, writes: [], reads: [] };
        }
        var site = { file: fd.rel, line: li + 1 };
        if (isWrite) {
          globals[gname].writes.push(site);
        } else {
          globals[gname].reads.push(site);
        }
      }
    });
  });
  var writeOnly = Object.keys(globals)
    .map(function (k) {
      return globals[k];
    })
    .filter(function (g) {
      return g.writes.length > 0 && g.reads.length === 0;
    })
    .sort(function (a, b) {
      return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
    });

  ["function", "macro", "enum"].forEach(function (k) {
    dead[k].sort(byFileLine);
    stringOnly[k].sort(byFileLine);
  });

  var deadInternal = {};
  var publicUnused = {};
  ["function", "macro", "enum"].forEach(function (k) {
    var parts = partitionByVisibility(dead[k]);
    deadInternal[k] = parts.internal;
    publicUnused[k] = parts.pub;
  });

  var report = {
    root: root,
    filesScanned: files.length,
    defined: {
      "function": countKind(defs, "function"),
      macro: countKind(defs, "macro"),
      enum: countKind(defs, "enum"),
    },
    deadInternal: deadInternal,
    publicUnused: publicUnused,
    stringOrCommentOnly: stringOnly,
    writeOnlyGlobals: writeOnly,
  };

  var totalDead =
    deadInternal["function"].length + deadInternal.macro.length + deadInternal.enum.length;

  if (opts.json) {
    process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  } else {
    printReport(report);
  }

  if (opts.fail && totalDead > 0) {
    process.exit(1);
  }
}

function partitionByVisibility(list) {
  var internal = [];
  var pub = [];
  list.forEach(function (d) {
    if (isPublicName(d.name)) {
      pub.push(d);
    } else {
      internal.push(d);
    }
  });
  return { internal: internal, pub: pub };
}

function countKind(defs, kind) {
  var n = 0;
  for (var i = 0; i < defs.length; i++) {
    if (defs[i].kind === kind) {
      n += 1;
    }
  }
  return n;
}

function byFileLine(a, b) {
  if (a.file !== b.file) {
    return a.file < b.file ? -1 : 1;
  }
  return a.line - b.line;
}

function printSection(title, items, render) {
  process.stdout.write(title + " (" + items.length + "):\n");
  if (items.length === 0) {
    process.stdout.write("  (none)\n");
    return;
  }
  items.forEach(function (it) {
    process.stdout.write("  " + render(it) + "\n");
  });
}

function printReport(r) {
  process.stdout.write(
    "find-deadcode: scanned " +
      r.filesScanned +
      " .gml files (" +
      r.defined["function"] +
      " functions, " +
      r.defined.macro +
      " macros, " +
      r.defined.enum +
      " enums)\n"
  );
  printSection("Dead internal functions", r.deadInternal["function"], function (d) {
    return d.file + ":" + d.line + "  " + d.name + "()";
  });
  printSection("Dead internal macros", r.deadInternal.macro, function (d) {
    return d.file + ":" + d.line + "  " + d.name;
  });
  printSection("Dead internal enums", r.deadInternal.enum, function (d) {
    return d.file + ":" + d.line + "  " + d.name;
  });
  process.stdout.write("Public API with no internal callers (may be called by the game project or binding users - do not delete blindly):\n");
  printSection("  functions", r.publicUnused["function"], function (d) {
    return d.file + ":" + d.line + "  " + d.name + "()";
  });
  printSection("  macros", r.publicUnused.macro, function (d) {
    return d.file + ":" + d.line + "  " + d.name;
  });
  printSection("  enums", r.publicUnused.enum, function (d) {
    return d.file + ":" + d.line + "  " + d.name;
  });
  printSection("Referenced only in strings/comments", flattenBuckets(r.stringOrCommentOnly), function (d) {
    return d.file + ":" + d.line + "  " + d.kind + " " + d.name;
  });
  printSection(
    "Write-only globals",
    r.writeOnlyGlobals,
    function (g) {
      var sites = g.writes
        .map(function (w) {
          return w.file + ":" + w.line;
        })
        .join(", ");
      return "global." + g.name + "  written at " + sites + ", never read";
    }
  );
}

function flattenBuckets(b) {
  var out = [];
  ["function", "macro", "enum"].forEach(function (k) {
    b[k].forEach(function (d) {
      out.push(d);
    });
  });
  out.sort(byFileLine);
  return out;
}

main();
