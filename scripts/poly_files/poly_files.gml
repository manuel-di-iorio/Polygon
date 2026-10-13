// poly_files — scene file dialogs, save/load, confirm actions.

// ---------------------------------------------------------------------------
// Paths and names
// ---------------------------------------------------------------------------

// Folder (relative to working_directory) holding editor scene files.
function __poly_scenes_dir() {
  return working_directory + "__PolygonEditor__/scenes/";
}

// Builds relative scene file path for name.
function __poly_scene_file_for(_name) {
  return "__PolygonEditor__/scenes/" + _name + ".json";
}

// Strips directory prefixes from a path.
function __poly_base_name(_path) {
  var _base = is_string(_path) ? _path : "";
  var _at = max(string_last_pos("/", _base), string_last_pos("\\", _base));

  if (_at > 0) _base = string_copy(_base, _at + 1, string_length(_base) - _at);
  return _base;
}

// Strips a trailing .json extension.
function __poly_strip_json(_name) {
  if (string_length(_name) > 5 && string_lower(string_copy(_name, string_length(_name) - 4, 5)) == ".json") return string_copy(_name, 1, string_length(_name) - 5);
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

// Lists saved scene names (case-insensitive sort).
function __poly_scene_list() {
  var _out = [];
  var _found = file_find_first(__poly_scenes_dir() + "*.json", 0);
  var _guard = 0;

  while (_found != "" && _guard < 500) {
    _guard++;
    var _name = __poly_strip_json(__poly_base_name(_found));

    if (_name != "") array_push(_out, _name);
    _found = file_find_next();
  }

  file_find_close();

  for (var _i = 1, _n = array_length(_out); _i < _n; _i++) {
    var _item = _out[_i];
    var _j = _i - 1;

    while (_j >= 0 && string_lower(_out[_j]) > string_lower(_item)) {
      _out[_j + 1] = _out[_j];
      _j--;
    }

    _out[_j + 1] = _item;
  }

  return _out;
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

  if (_clean == "") {
    _dlg.error = "Type a valid scene name.";
    _dlg.err_name = _dlg.name;
    return;
  }

  _dlg.name = _clean;

  if (!__poly_save_named(_ed, _clean)) {
    _dlg.error = "Could not write file.";
    _dlg.err_name = _dlg.name;
    return;
  }

  var _after = _dlg.after;
  _ed.scene_dlg = undefined;

  if (_after != undefined && _after != "") __poly_confirm_do(_ed, _after);
}

// Confirms load dialog.
function __poly_scene_dlg_do_load(_ed) {
  var _dlg = _ed.scene_dlg;

  if (_dlg == undefined) return;
  var _clean = __poly_sanitize_scene_name(_dlg.name);

  if (_clean == "") {
    _dlg.error = "Type a valid scene name.";
    _dlg.err_name = _dlg.name;
    return;
  }

  _dlg.name = _clean;

  // Chunked load: the dialog stays open showing progress, finish closes it.
  var _err = __poly_load_named_begin(_ed, _clean);

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

// Saves scene under given name.
function __poly_save_named(_ed, _name) {
  var _clean = __poly_sanitize_scene_name(_name);

  if (_clean == "") return false;
  _ed.scene_file = __poly_scene_file_for(_clean);
  return __poly_save_scene(_ed);
}

// Loads scene by name.
function __poly_load_named(_ed, _name) {
  var _clean = __poly_sanitize_scene_name(_name);

  if (_clean == "") return false;
  var _old = _ed.scene_file;
  _ed.scene_file = __poly_scene_file_for(_clean);

  if (__poly_load_scene(_ed)) return true;
  _ed.scene_file = _old;
  return false;
}

// Starts a chunked load by name (progress dialog, no freeze).
// Returns "" on start, else an error message for the dialog.
function __poly_load_named_begin(_ed, _name) {
  var _clean = __poly_sanitize_scene_name(_name);

  if (_clean == "") return "Type a valid scene name.";
  var _old = _ed.scene_file;
  _ed.scene_file = __poly_scene_file_for(_clean);
  var _err = __poly_load_scene_begin(_ed);

  if (_err == "") return "";
  _ed.scene_file = _old;
  return "Scene not found or invalid.";
}

// Deletes a saved scene file by name. Returns true on success.
function __poly_delete_scene_named(_name) {
  var _clean = __poly_sanitize_scene_name(_name);

  if (_clean == "") return false;
  var _path = __poly_scenes_dir() + _clean + ".json";

  if (!file_exists(_path)) return false;
  file_delete(_path);
  return true;
}
