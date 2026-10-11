// polygon_selection — selection set, visibility/lock state, gizmo tool gating.

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

// Clears current node selection.
function __polygon_sel_clear(_ed) {
  _ed.sel = [];
  _ed.giz.drag = -1;
  _ed.giz.hover = -1;

  if (variable_struct_exists(_ed, "scene_anchor"))  _ed.scene_anchor = undefined;
}

// Checks if node is selected.
function __polygon_sel_has(_ed, _node) {
  return _ed != undefined && __polygon_node_list_has(_ed.sel, _node);
}

// Assigns selection, resets the gizmo drag and refreshes the tool.
function __polygon_sel_assign(_ed, _nodes) {
  _ed.sel = _nodes;
  _ed.giz.drag = -1;
  __polygon_sel_apply_tool(_ed);
}

// Toggles node in selection set.
function __polygon_sel_toggle(_ed, _node) {
  if (_node == undefined)  return;
  var _at = __polygon_node_list_index(_ed.sel, _node);

  if (_at >= 0) {
    array_delete(_ed.sel, _at, 1);
    return;
  }

  if (__polygon_locked_get(_ed, _node))  return;
  array_push(_ed.sel, _node);
}

// ---------------------------------------------------------------------------
// Per-frame lookup
// ---------------------------------------------------------------------------

// Builds per-frame selection lookup (nodes resolved once).
function __polygon_sel_set(_ed) {
  var _nodes = [];

  if (!variable_struct_exists(_ed, "sel_lookup_epoch"))  _ed.sel_lookup_epoch = 0;
  _ed.sel_lookup_epoch++;
  var _epoch = _ed.sel_lookup_epoch;

  if (is_array(_ed.sel)) {
    for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
      var _node = _ed.sel[_i];

      if (_node == undefined)  continue;
      array_push(_nodes, _node);
      __polygon_epoch_tag(__polygon_registry_find(_ed, _node), "__polygon_sel_epoch", _epoch);
    }
  }

  return { nodes: _nodes, epoch: _epoch };
}

// Checks node against a prebuilt selection set (no lookup).
function __polygon_sel_in(_set, _node, _en = undefined) {
  if (_en != undefined && __polygon_epoch_check(_en, "__polygon_sel_epoch", _set.epoch))  return true;
  return array_contains(_set.nodes, _node);
}

// ---------------------------------------------------------------------------
// Gizmo tools
// ---------------------------------------------------------------------------

// Reads the light type of a node (defaults to directional).
function __polygon_sel_light_type(_ed, _node) {
  var _en = __polygon_registry_find(_ed, _node);

  if (_en != undefined && is_struct(_en.data) && is_string(_en.data.type))  return _en.data.type;
  return "directional";
}

// Checks if gizmo tool applies.
function __polygon_tool_allowed(_ed, _node, _tool) {
  if (_node == undefined)  return false;
  var _kind = __polygon_kind_of(_ed, _node);

  if (_kind == undefined || _kind == "instance")  return true;
  if (_kind == "environment")  return false;
  if (_tool == PolygonEditorTool.Scale)  return false;
  if (_kind == "camera")  return true;
  if (_tool == PolygonEditorTool.Translate)  return true;
  if (_tool == PolygonEditorTool.Rotate)  return __polygon_sel_light_type(_ed, _node) != "point";
  return true;
}

// Checks if gizmo can manipulate selection.
function __polygon_gizmo_allowed(_ed) {
  if (_ed == undefined || _ed.giz.tool == PolygonEditorTool.View || !is_array(_ed.sel) || array_length(_ed.sel) == 0)  return false;
  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    var _node = _ed.sel[_i];

    if (__polygon_hidden_get(_ed, _node))  continue;
    if (__polygon_tool_allowed(_ed, _node, _ed.giz.tool))  return true;
  }

  return false;
}

// Auto selects gizmo tool for light.
function __polygon_sel_apply_tool(_ed) {
  if (_ed == undefined || !is_array(_ed.sel) || array_length(_ed.sel) != 1)  return;
  var _node = _ed.sel[0];

  if (__polygon_kind_of(_ed, _node) != "light")  return;
  var _type = __polygon_sel_light_type(_ed, _node);

  if (_type == "directional") {
    _ed.giz.tool = PolygonEditorTool.Rotate;
  } else if (_type == "point") {
    _ed.giz.tool = PolygonEditorTool.Translate;
  }
}

// ---------------------------------------------------------------------------
// Visibility and lock
// ---------------------------------------------------------------------------

// Sets mesh enabled flags on one node (walk visitor).
function __polygon_meshes_visit(_cur, _ctx) {
  var _comps = [];
  __polygon_walk_collect_comps(_cur, _comps);

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++)  _comps[_i].comp.setEnabled(_ctx.on);
}

// Reads a boolean registry flag (hidden/locked) safely.
function __polygon_flag_get(_ed, _node, _field) {
  if (_ed == undefined || _node == undefined)  return false;
  var _en = __polygon_registry_find(_ed, _node);

  if (_en == undefined)  return false;
  return _en[$ _field] == true;
}

// Checks if node is hidden.
function __polygon_hidden_get(_ed, _node) {
  return __polygon_flag_get(_ed, _node, "hidden");
}

// Hides or unhides node meshes.
function __polygon_hidden_set(_ed, _node, _hide) {
  if (_ed == undefined || _node == undefined)  return false;
  var _en = __polygon_registry_find(_ed, _node);

  if (_en == undefined)  return false;
  _en.hidden = (_hide == true);
  _ed.view_dirty = true;
  __polygon_walk_tree(_node, __polygon_meshes_visit, { on: !_en.hidden });

  if (_ed.rt != undefined && _ed.rt.scene != undefined)  _ed.rt.scene.update(0);
  return true;
}

// Checks if node selection is disabled (locked).
function __polygon_locked_get(_ed, _node) {
  return __polygon_flag_get(_ed, _node, "locked");
}

// Locks or unlocks node selection (locked = cannot be selected).
function __polygon_locked_set(_ed, _node, _lock) {
  if (_ed == undefined || _node == undefined)  return false;
  var _en = __polygon_registry_find(_ed, _node);

  if (_en == undefined)  return false;
  _en.locked = (_lock == true);
  _ed.view_dirty = true;

  // If node got locked and it was selected, remove it from selection.
  if (_en.locked && is_array(_ed.sel)) {
    var _kept = [];

    for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++)  if (!__polygon_node_same(_ed.sel[_i], _node))  array_push(_kept, _ed.sel[_i]);
    __polygon_sel_assign(_ed, _kept);
  }

  return true;
}
