// poly_history — undo/redo snapshots of scene + selection.

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

// Captures current scene and selection as snapshot.
function __poly_history_snap(_ed) {
  var _nodes = __poly_serialize_scene(_ed);
  var _scene = { physics: __poly_world_data(_ed.world), assets: __poly_write_file_assets(_ed), nodes: _nodes };
  var _sel = [];

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    var _desc = __poly_node_desc(_ed, _ed.sel[_i]);

    if (_desc != undefined) array_push(_sel, _desc);
  }

  return { json: json_stringify(_scene), sel: _sel };
}

// Pushes prior snapshot onto undo stack.
// Coalescing: when a command is open (_ed.cmd_open struct), the first
// commit pushes the command's canonical before-snapshot once; further
// commits while the same command stays open only refresh dirty flags
// (no new stack entries). Plain callers (no cmd_open) behave as before.
function __poly_history_commit(_ed, _before, _label = undefined) {
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
function __poly_cmd_begin(_ed, _label) {
  if (_ed == undefined) return undefined;
  if (variable_struct_exists(_ed, "cmd_open") && is_struct(_ed.cmd_open) && _ed.cmd_open.label == _label) return _ed.cmd_open.before;
  var _before = __poly_history_snap(_ed);
  _ed.cmd_open = { label: _label, before: _before, done: false };
  return _before;
}

// Commits the named command (single undo entry) and closes it.
function __poly_cmd_commit(_ed, _before, _label) {
  if (_ed == undefined) return;

  if (!(variable_struct_exists(_ed, "cmd_open") && is_struct(_ed.cmd_open))) {
    __poly_history_commit(_ed, _before, _label);
    return;
  }

  var _open = _ed.cmd_open;
  var _src = _open.before != undefined ? _open.before : _before;
  _open.done = false;
  __poly_history_commit(_ed, _src, _label);
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
function __poly_history_apply(_ed, _from, _to) {
  var _peek = __poly_history_peek(_from);

  if (_peek == undefined) return false;
  __poly_history_stacks(_ed);
  var _cur = __poly_history_snap(_ed);
  array_pop(_from);
  array_push(_to, _cur);
  __poly_rebuild(_ed, _peek.data);
  __poly_history_restore_sel(_ed, _peek.entry.sel);
  return true;
}
