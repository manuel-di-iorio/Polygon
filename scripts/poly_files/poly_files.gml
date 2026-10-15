// poly_files — scene file dialogs, save/load, confirm actions.

// ---------------------------------------------------------------------------
// Paths and names
// ---------------------------------------------------------------------------

// Folder (relative to working_directory) holding editor scene files.
function __poly_scenes_dir() {
  return working_directory + "__PolygonEditor__/scenes/";
}

// Builds relative scene file path for name + format ("json" or "bin").
function __poly_scene_file_for(_name, _fmt = "json") {
  var _ext = (_fmt == "bin") ? ".bin" : ".json";
  return "__PolygonEditor__/scenes/" + _name + _ext;
}

// Returns "bin" when a path ends with .bin, else "json".
function __poly_scene_fmt_of(_path) {
  if (is_string(_path) && string_length(_path) >= 4 && string_lower(string_copy(_path, string_length(_path) - 3, 4)) == ".bin") return "bin";
  return "json";
}

// Swaps the extension of a scene path to the given format.
function __poly_scene_path_as(_path, _fmt) {
  var _base = __poly_strip_ext(__poly_base_name(_path));
  var _dir = "";
  var _at = max(string_last_pos("/", _path), string_last_pos("\\", _path));

  if (_at > 0) _dir = string_copy(_path, 1, _at);
  var _ext = (_fmt == "bin") ? ".bin" : ".json";
  return _dir + _base + _ext;
}

// Strips directory prefixes from a path.
function __poly_base_name(_path) {
  var _base = is_string(_path) ? _path : "";
  var _at = max(string_last_pos("/", _base), string_last_pos("\\", _base));

  if (_at > 0) _base = string_copy(_base, _at + 1, string_length(_base) - _at);
  return _base;
}

// Strips a trailing .json/.bin extension.
function __poly_strip_json(_name) {
  return __poly_strip_ext(_name);
}

// Strips a trailing scene extension (.json or .bin).
function __poly_strip_ext(_name) {
  if (!is_string(_name)) return "";
  var _low = string_lower(_name);

  if (string_length(_name) > 5 && string_copy(_low, string_length(_name) - 4, 5) == ".json") return string_copy(_name, 1, string_length(_name) - 5);
  if (string_length(_name) > 4 && string_copy(_low, string_length(_name) - 3, 4) == ".bin") return string_copy(_name, 1, string_length(_name) - 4);
  return _name;
}

// Derives scene name from current file.
function __poly_scene_name(_ed) {
  var _name = (_ed != undefined && is_string(_ed.scene_file)) ? _ed.scene_file : "";
  _name = string_trim(__poly_strip_json(__poly_base_name(_name)));
  return _name == "" ? "scene" : _name;
}

// Sanitizes scene name for file use.
function __poly_sanitize_scene_name(_name) {
  if (!is_string(_name)) return "";
  static _banned = [ "/", "\\", ":", "*", "?", "\"", "<", ">", "|" ];
  var _src = string_trim(_name);
  var _out = "";

  for (var _i = 1; _i <= string_length(_src); _i++) {
    var _ch = string_char_at(_src, _i);

    if (array_contains(_banned, _ch) || ord(_ch) < 32) continue;
    _out += _ch;
  }

  _out = string_trim(_out);

  while (string_length(_out) > 0) {
    var _last = string_char_at(_out, string_length(_out));

    if (_last != "." && _last != " ") break;
    _out = string_copy(_out, 1, string_length(_out) - 1);
  }

  if (string_length(_out) > 64) _out = string_copy(_out, 1, 64);
  return _out;
}

// Lists saved scene files, one entry per file: { name, fmt }.
// scene.json and scene.bin are separate entries. Sorted by name, json first.
function __poly_scene_list() {
  var _out = [];
  var _found = file_find_first(__poly_scenes_dir() + "*.json", 0);
  var _guard = 0;

  while (_found != "" && _guard < 500) {
    _guard++;
    var _name = __poly_strip_ext(__poly_base_name(_found));

    if (_name != "") array_push(_out, { name: _name, fmt: "json" });
    _found = file_find_next();
  }

  file_find_close();
  _found = file_find_first(__poly_scenes_dir() + "*.bin", 0);
  _guard = 0;

  while (_found != "" && _guard < 500) {
    _guard++;
    var _name2 = __poly_strip_ext(__poly_base_name(_found));

    if (_name2 != "") array_push(_out, { name: _name2, fmt: "bin" });
    _found = file_find_next();
  }

  file_find_close();

  for (var _i = 1, _n = array_length(_out); _i < _n; _i++) {
    var _item = _out[_i];
    var _j = _i - 1;

    while (_j >= 0 && __poly_scene_entry_key(_out[_j]) > __poly_scene_entry_key(_item)) {
      _out[_j + 1] = _out[_j];
      _j--;
    }

    _out[_j + 1] = _item;
  }

  return _out;
}

// Sort key for a scene entry (name case-insensitive, json before bin).
function __poly_scene_entry_key(_e) {
  var _canon = string_lower(_e.name);
  return _canon + (_e.fmt == "bin" ? "1" : "0");
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

// Opens the scene dialog in a mode (save/load).
function __poly_scene_dlg_open(_ed, _mode, _after = undefined) {
  if (_ed == undefined || _ed.scene_dlg != undefined) return false;
  _ed.scene_dlg = {
    mode: _mode,
    name: __poly_scene_name(_ed),
    fmt: __poly_scene_fmt_of(is_string(_ed.scene_file) ? _ed.scene_file : ""),
    error: "",
    err_name: "",
    open: true,
    after: _after,
    list: __poly_scene_list(),
  };
  return false;
}

// Prompts scene name and saves scene.
// Saves scene or prompts for name.
function __poly_save_or_ask(_ed, _after = undefined) {
  if (_ed.scene_file == undefined || _ed.scene_file == "") return __poly_scene_dlg_open(_ed, "save", _after);
  return __poly_save_scene(_ed);
}

// Confirms save dialog.
function __poly_scene_dlg_do_save(_ed) {
  var _dlg = _ed.scene_dlg;

  if (_dlg == undefined) return;
  var _clean = __poly_sanitize_scene_name(_dlg.name);
  var _fmt = (_dlg[$ "fmt"] == "bin") ? "bin" : "json";

  if (_clean == "") {
    _dlg.error = "Type a valid scene name.";
    _dlg.err_name = _dlg.name;
    return;
  }

  _dlg.name = _clean;

  if (!__poly_save_named(_ed, _clean, _fmt)) {
    _dlg.error = "Could not write file.";
    _dlg.err_name = _dlg.name;
    return;
  }

  var _after = _dlg.after;
  _ed.scene_dlg = undefined;

  if (_after != undefined && _after != "") __poly_confirm_do(_ed, _after);
}

// Confirms load dialog (selection comes from the file list).
function __poly_scene_dlg_do_load(_ed) {
  var _dlg = _ed.scene_dlg;

  if (_dlg == undefined) return;
  var _clean = __poly_sanitize_scene_name(_dlg.name);

  if (_clean == "") {
    _dlg.error = "Select a scene from the list.";
    _dlg.err_name = "";
    return;
  }

  _dlg.name = _clean;

  // Chunked load: the dialog stays open showing progress, finish closes it.
  var _err = __poly_load_named_begin(_ed, _clean, (_dlg[$ "fmt"] == "bin") ? "bin" : "json");

  if (_err != "") {
    _dlg.error = _err;
    _dlg.err_name = _dlg.name;
    return;
  }
}

// ---------------------------------------------------------------------------
// Confirm actions
// ---------------------------------------------------------------------------

// Shows confirmation dialog if dirty.
function __poly_confirm_ask(_ed, _action) {
  if (_ed.dirty != true) {
    __poly_confirm_do(_ed, _action);
    return;
  }

  _ed.confirm = { action: _action, open: true };
}

// Executes confirmed new load close action.
function __poly_confirm_do(_ed, _action) {
  if (_action == "new") {
    __poly_new_scene(_ed);
  } else if (_action == "load") {
    __poly_scene_dlg_open(_ed, "load");
  } else if (_action == "close") {
    __poly_set_active(_ed, false);
  }
}

// ---------------------------------------------------------------------------
// Named file ops
// ---------------------------------------------------------------------------

// Saves scene under given name + format.
function __poly_save_named(_ed, _name, _fmt = "json") {
  var _clean = __poly_sanitize_scene_name(_name);

  if (_clean == "") return false;
  if (_fmt != "bin") _fmt = "json";
  _ed.scene_file = __poly_scene_file_for(_clean, _fmt);
  return __poly_save_scene(_ed);
}

// Starts a chunked load by name + format (progress dialog, no freeze).
// Returns "" on start, else an error message for the dialog.
function __poly_load_named_begin(_ed, _name, _fmt = "json") {
  var _clean = __poly_sanitize_scene_name(_name);

  if (_clean == "") return "Type a valid scene name.";
  if (_fmt != "bin") _fmt = "json";
  var _old = _ed.scene_file;
  var _alts = (_fmt == "bin") ? [ "bin", "json" ] : [ "json", "bin" ];

  for (var _i = 0; _i < 2; _i++) {
    _ed.scene_file = __poly_scene_file_for(_clean, _alts[_i]);
    var _err = __poly_load_scene_begin(_ed);

    if (_err == "") return "";
  }

  _ed.scene_file = _old;
  return "Scene not found or invalid.";
}

// Deletes saved scene files by name. With _fmt ("json"/"bin") deletes only
// that file, else both. Returns true when at least one file was deleted.
function __poly_delete_scene_named(_name, _fmt = undefined) {
  var _clean = __poly_sanitize_scene_name(_name);

  if (_clean == "") return false;
  var _ok = false;

  if (_fmt == "bin" || _fmt == undefined) {
    var _pb = __poly_scenes_dir() + _clean + ".bin";

    if (file_exists(_pb)) {
      file_delete(_pb);
      _ok = true;
    }
  }

  if (_fmt == "json" || _fmt == undefined) {
    var _pj = __poly_scenes_dir() + _clean + ".json";

    if (file_exists(_pj)) {
      file_delete(_pj);
      _ok = true;
    }
  }

  return _ok;
}

