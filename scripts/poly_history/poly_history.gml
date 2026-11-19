// poly_history - undo/redo snapshots of scene + selection.

// ---------------------------------------------------------------------------
// Stacks and snapshots
// ---------------------------------------------------------------------------

// Clears undo and redo history stacks.
function __poly_history_clear(_ed) {
  if (_ed == undefined) return;
  _ed.undo = [];
  _ed.redo = [];
}

// Ensures undo/redo stacks exist.
function __poly_history_stacks(_ed) {
  if (!is_array(_ed.undo)) _ed.undo = [];
  if (!is_array(_ed.redo)) _ed.redo = [];
}

// Formats a Vec3 or [x,y,z] array as "x/y/z" for History entry details.
function __poly_fmt_xyz(_v) {
  if (_v == undefined) return "0/0/0";

  if (is_array(_v)) {
    if (array_length(_v) < 3) return "0/0/0";
    return string_format(_v[0], 0, 2) + "/" + string_format(_v[1], 0, 2) + "/" + string_format(_v[2], 0, 2);
  }

  return string_format(_v.x, 0, 2) + "/" + string_format(_v.y, 0, 2) + "/" + string_format(_v.z, 0, 2);
}

// Formats one value for History entry details ("1.5", "on"/"off", "name",
// "a/b/c").
function __poly_fmt_value(_v) {
  if (_v == undefined) return "-";
  if (is_bool(_v)) return _v ? "on" : "off";

  if (is_array(_v)) {
    var _s = "";

    for (var _i = 0, _n = array_length(_v); _i < _n; _i++) _s += ((_i > 0) ? "/" : "") + __poly_fmt_value(_v[_i]);
    return _s;
  }

  if (is_real(_v)) {
    if (floor(_v) == _v) return string(_v);
    return string_format(_v, 0, 3);
  }

  if (is_string(_v)) return "\"" + _v + "\"";
  return string(_v);
}

// Builds the "from A to B" detail of a move-like action. Entries are
// { name, from, to }; the label already names the single-instance case.
function __poly_history_move_detail(_moved, _label) {
  if (!is_array(_moved) || array_length(_moved) == 0) return _label;

  if (array_length(_moved) == 1) return _label + " from " + __poly_fmt_xyz(_moved[0].from) + " to " + __poly_fmt_xyz(_moved[0].to);
  var _s = "";

  for (var _i = 0, _n = array_length(_moved); _i < _n; _i++) _s += ((_i > 0) ? "; " : "") + _moved[_i].name + " from " + __poly_fmt_xyz(_moved[_i].from) + " to " + __poly_fmt_xyz(_moved[_i].to);
  return _s;
}

// Joins instance names for a History detail line (bounded length).
function __poly_history_names_detail(_names) {
  var _n = is_array(_names) ? array_length(_names) : 0;
  var _max = 8;
  var _s = "";

  for (var _i = 0; _i < min(_n, _max); _i++) _s += ((_i > 0) ? ", " : "") + string(_names[_i]);
  if (_n > _max) _s += ", +" + string(_n - _max) + " more";
  return _s;
}

// Replaces non-finite reals inside a snapshot payload.
// json_stringify writes NaN/Infinity as bare tokens, json_parse rejects them:
// one unreadable entry would make every undo/redo of the session a no-op.
function __poly_history_sanitize(_v) {
  if (is_array(_v)) {
    for (var _i = 0, _n = array_length(_v); _i < _n; _i++) {
      var _e = _v[_i];

      if (is_real(_e)) {
        // NaN and +/-Infinity both give NaN here (see __json_write_primitive).
        if ((_e - _e) != 0) _v[_i] = 0.0;
      } else if (is_array(_e) || is_struct(_e)) {
        __poly_history_sanitize(_e);
      }
    }

    return;
  }

  if (!is_struct(_v)) return;
  var _names = variable_struct_get_names(_v);

  for (var _j = 0, _m = array_length(_names); _j < _m; _j++) {
    var _k = _names[_j];
    var _val = _v[$ _k];

    if (is_real(_val)) {
      if ((_val - _val) != 0) _v[$ _k] = 0.0;
    } else if (is_array(_val) || is_struct(_val)) {
      __poly_history_sanitize(_val);
    }
  }
}

// Captures current scene and selection as snapshot.
function __poly_history_snap(_ed) {
  var _nodes = __poly_serialize_scene(_ed);
  var _scene = { physics: __poly_world_data(_ed.world), assets: __poly_write_file_assets(_ed), nodes: _nodes };
  var _sel = [];

  // Descriptors are rebuilt on every snapshot: sanitizing them in place is
  // safe and keeps the JSON parseable (see __poly_history_sanitize).
  __poly_history_sanitize(_scene);

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    var _desc = __poly_node_desc(_ed, _ed.sel[_i]);

    if (_desc != undefined) array_push(_sel, _desc);
  }

  return { json: json_stringify(_scene), sel: _sel };
}

// Human-readable name stored on a history entry.
function __poly_history_entry_label(_entry) {
  if (is_struct(_entry) && variable_struct_exists(_entry, "label") && is_string(_entry.label) && _entry.label != "") return _entry.label;
  return "Scene edit";
}

// Optional longer description stored on a history entry (used for tooltips).
function __poly_history_entry_detail(_entry) {
  if (is_struct(_entry) && variable_struct_exists(_entry, "detail") && is_string(_entry.detail) && _entry.detail != "") return _entry.detail;
  return "";
}

// Builds a natural-language label for an action affecting the current selection.
function __poly_history_sel_label(_ed, _verb_past) {
  var _n = (is_array(_ed.sel)) ? array_length(_ed.sel) : 0;

  if (_n <= 0) return _verb_past + " objects";
  if (_n == 1) {
    var _name = __poly_node_display(_ed, _ed.sel[0]);

    if (is_string(_name) && _name != "") return _verb_past + " instance " + _name;
  }

  return _verb_past + " " + string(_n) + " instances";
}

// Pushes prior snapshot onto undo stack.
// Coalescing: when a command is open (_ed.cmd_open struct), the first
// commit pushes the command's canonical before-snapshot once; further
// commits while the same command stays open only refresh dirty flags
// (no new stack entries). Plain callers (no cmd_open) behave as before.
// _label names the action in the History panel; _detail is an optional
// longer description used for tooltips.
function __poly_history_commit(_ed, _before, _label = undefined, _detail = undefined) {
  if (_ed != undefined && variable_struct_exists(_ed, "cmd_open") && is_struct(_ed.cmd_open)) {
    var _open = _ed.cmd_open;

    if (_label == undefined || _open.label == _label) {
      if (_open.done == true) {
        _ed.dirty = true;
        _ed.view_dirty = true;
        return;
      }

      var _src = _open.before != undefined ? _open.before : _before;
      var _cur = __poly_history_snap(_ed);

      if (_cur.json == _src.json) {
        _open.done = true;
        return;
      }

      var _cmd_label = (is_string(_label) && _label != "") ? _label : _open.label;
      if (is_struct(_src) && is_string(_cmd_label) && _cmd_label != "") _src.label = _cmd_label;
      var _cmd_detail = (is_string(_detail) && _detail != "") ? _detail : (is_string(_open.detail) ? _open.detail : undefined);
      if (is_struct(_src) && is_string(_cmd_detail) && _cmd_detail != "") _src.detail = _cmd_detail;
      __poly_history_stacks(_ed);
      array_push(_ed.undo, _src);
      _ed.redo = [];
      var _excess = array_length(_ed.undo) - 100;
      if (_excess > 0) array_delete(_ed.undo, 0, _excess);
      _ed.dirty = true;
      _ed.view_dirty = true;
      if (variable_struct_exists(_ed, "outline") && is_struct(_ed.outline)) _ed.outline.cheap = undefined;
      _open.done = true;
      return;
    }
  }

  var _cur2 = __poly_history_snap(_ed);

  if (_cur2.json == _before.json) return;
  var _name = (is_string(_label) && _label != "") ? _label : "Scene edit";
  if (is_struct(_before)) _before.label = _name;
  if (is_struct(_before) && is_string(_detail) && _detail != "") _before.detail = _detail;
  __poly_history_stacks(_ed);
  array_push(_ed.undo, _before);
  _ed.redo = [];

  var _excess2 = array_length(_ed.undo) - 100;
  if (_excess2 > 0) array_delete(_ed.undo, 0, _excess2);
  _ed.dirty = true;
  _ed.view_dirty = true;

  if (variable_struct_exists(_ed, "outline") && is_struct(_ed.outline)) _ed.outline.cheap = undefined;
}

// ---------------------------------------------------------------------------
// Command pattern (coalesced commits, e.g. gizmo drag)
// ---------------------------------------------------------------------------

// Opens a named command, capturing the before-snapshot once. Re-entering
// with the same label keeps the original snapshot (coalescing).
function __poly_cmd_begin(_ed, _label, _detail = undefined) {
  if (_ed == undefined) return undefined;
  if (variable_struct_exists(_ed, "cmd_open") && is_struct(_ed.cmd_open) && _ed.cmd_open.label == _label) return _ed.cmd_open.before;
  var _before = __poly_history_snap(_ed);
  _ed.cmd_open = { label: _label, detail: _detail, before: _before, done: false };
  return _before;
}

// Commits the named command (single undo entry) and closes it.
function __poly_cmd_commit(_ed, _before, _label, _detail = undefined) {
  if (_ed == undefined) return;

  if (!(variable_struct_exists(_ed, "cmd_open") && is_struct(_ed.cmd_open))) {
    __poly_history_commit(_ed, _before, _label, _detail);
    return;
  }

  var _open = _ed.cmd_open;
  var _src = _open.before != undefined ? _open.before : _before;
  _open.done = false;
  __poly_history_commit(_ed, _src, _label, _detail);
  // __poly_history_commit marks done without clearing; close here.
  _ed.cmd_open = undefined;
  if (variable_struct_exists(_ed, "hist_before")) _ed.hist_before = undefined;
}

// ---------------------------------------------------------------------------
// Selection restore (by wrapper id)
// ---------------------------------------------------------------------------

// Restores selection from saved node descriptors (matched by id).
function __poly_history_restore_sel(_ed, _sel_descs) {
  var _out = [];

  if (is_array(_sel_descs)) {
    for (var _i = 0, _nsel = array_length(_sel_descs); _i < _nsel; _i++) {
      var _want = _sel_descs[_i];

      if (_want == undefined || !is_string(_want.id)) continue;
      var _node = __poly_find_by_id(_ed, _want.id);

      if (_node != undefined) array_push(_out, _node);
    }
  }

  _ed.sel = _out;
  _ed.giz.drag = -1;
}

// ---------------------------------------------------------------------------
// Undo and redo
// ---------------------------------------------------------------------------

// Peeks the top stack entry with parsed scene data (undefined when empty).
function __poly_history_peek(_stack) {
  if (!is_array(_stack) || array_length(_stack) == 0) return undefined;
  var _entry = _stack[array_length(_stack) - 1];
  var _data = json_parse(_entry.json);

  if (!is_struct(_data) || !is_array(_data[$ "nodes"])) return undefined;
  return { entry: _entry, data: _data };
}

// Moves one snapshot between stacks and rebuilds the scene from it.
// A restore that cannot be applied leaves the stacks untouched and reports
// the reason, instead of consuming the entry and doing nothing on screen.
function __poly_history_apply(_ed, _from, _to) {
  __poly_history_stacks(_ed);
  var _peek = __poly_history_peek(_from);

  if (_peek == undefined) {
    // Unreadable entry: drop it so the next undo/redo can still work.
    if (is_array(_from) && array_length(_from) > 0) {
      array_pop(_from);
      __poly_console_log(_ed, "History: dropped an unreadable entry.");
    }

    return false;
  }

  var _cur = __poly_history_snap(_ed);
  _cur.label = __poly_history_entry_label(_peek.entry);
  var _peek_detail = __poly_history_entry_detail(_peek.entry);

  if (_peek_detail != "") _cur.detail = _peek_detail;
  array_pop(_from);
  array_push(_to, _cur);
  var _report = __poly_rebuild(_ed, _peek.data);

  if (is_struct(_report) && is_string(_report[$ "err"]) && _report.err != "") {
    // Nothing was rebuilt: put the entry back where it was.
    array_pop(_to);
    array_push(_from, _peek.entry);
    __poly_console_log(_ed, "History: could not restore the scene (" + _report.err + ").");
    return false;
  }

  __poly_history_restore_sel(_ed, _peek.entry.sel);
  _ed.view_dirty = true;
  return true;
}

// Rebuilds the scene from a stack entry (used by history jumps).
function __poly_history_restore_entry(_ed, _entry) {
  if (!is_struct(_entry) || !is_string(_entry[$ "json"])) return false;
  var _data = json_parse(_entry.json);

  if (!is_struct(_data) || !is_array(_data[$ "nodes"])) return false;
  __poly_rebuild(_ed, _data);
  __poly_history_restore_sel(_ed, _entry[$ "sel"]);
  return true;
}

// Restores the state before undo entry _index (0 = oldest action).
// Intermediate states are moved to the redo stack exactly like repeated
// Ctrl+Z presses, but the scene is rebuilt only once at the destination.
function __poly_history_jump(_ed, _index) {
  __poly_history_stacks(_ed);
  var _len = array_length(_ed.undo);

  if (!is_real(_index) || _index < 0 || _index >= _len) return false;
  var _steps = _len - _index;

  if (_steps <= 0) return false;
  var _cur = __poly_history_snap(_ed);

  for (var _i = 0; _i < _steps; _i++) {
    var _entry = _ed.undo[array_length(_ed.undo) - 1];

    if (!is_struct(_entry)) return false;
    array_pop(_ed.undo);
    _cur.label = __poly_history_entry_label(_entry);
    array_push(_ed.redo, _cur);
    _cur = _entry;
  }

  if (!__poly_history_restore_entry(_ed, _cur)) return false;
  _ed.view_dirty = true;
  return true;
}

// Redoes up to redo entry _index (0 = oldest undone action).
function __poly_history_redo_to(_ed, _index) {
  __poly_history_stacks(_ed);
  var _len = array_length(_ed.redo);

  if (!is_real(_index) || _index < 0 || _index >= _len) return false;
  var _steps = _len - _index;

  if (_steps <= 0) return false;
  var _cur = __poly_history_snap(_ed);

  for (var _i = 0; _i < _steps; _i++) {
    var _entry = _ed.redo[array_length(_ed.redo) - 1];

    if (!is_struct(_entry)) return false;
    array_pop(_ed.redo);
    _cur.label = __poly_history_entry_label(_entry);
    array_push(_ed.undo, _cur);
    _cur = _entry;
  }

  if (!__poly_history_restore_entry(_ed, _cur)) return false;
  _ed.view_dirty = true;
  return true;
}
