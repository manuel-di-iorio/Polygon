// poly_play - public API.

// Closes the editor without saving or asking: the edited scene stays in
// memory for on_close. Returns true when the editor was
// active and is now closed.
// _sync (optional): when true the editor state is pushed into the live game
// scene first (same as calling poly_sync_live() before closing).
function poly_play(_sync = false) {
  var _ed = __poly_inst();

  if (_ed == undefined || _ed.active != true) return false;
  if (_sync == true) poly_sync_live();
  __poly_set_active(_ed, false);
  return true;
}

// Closes the editor and goes back to the live game exactly as it was when the
// editor opened: the edits are dropped, so on_close receives no snapshot.
function __poly_reset_exit(_ed) {
  if (_ed == undefined || _ed.active != true) return false;
  __poly_set_active(_ed, false, "reset");
  return true;
}

// Returns the edited scene as an in-memory descriptor ({ physics, assets,
// nodes }): same shape as a scene file, never written to disk. Published when
// the editor closes; while it is open the scene is serialized on demand.
function poly_scene_snapshot() {
  var _ed = __poly_inst();

  if (_ed == undefined) return undefined;
  // Close Editor (reset exit): the live scene was never touched, so there is nothing to hand over.
  if (_ed[$ "close_reason"] == "reset") return undefined;
  if (is_struct(_ed[$ "close_data"])) return _ed.close_data;
  return __poly_close_data_build(_ed);
}

// Applies the editor state to the live game scene (config.scene) in place:
// existing nodes get transform, shadows, visibility, physics, prop data and
// resolved custom variables; nodes created in the editor are spawned; nodes
// removed in the editor are destroyed. Nodes the editor never tracked (game
// controllers, colliders, helpers) are left alone.
// Returns { applied, created, removed }. Call it from on_close to play the
// edited scene without saving anything.
function poly_sync_live() {
  var _ed = __poly_inst();

  if (_ed == undefined) return { applied: 0, created: 0, removed: 0 };
  if (!is_struct(poly_scene_snapshot())) return { applied: 0, created: 0, removed: 0 };
  return __poly_play_sync(_ed);
}

// Builds the in-memory scene descriptor (same shape as a scene file).
function __poly_close_data_build(_ed) {
  if (!is_struct(_ed)) return undefined;
  return {
    physics: __poly_world_data(_ed[$ "world"]),
    assets: __poly_write_file_assets(_ed),
    nodes: __poly_serialize_scene(_ed),
  };
}

// Records the editor node -> live node pairing used by poly_sync_live().
// Needed because bare live roots (Sun, MainCamera, terrain) keep their own
// name while the editor wrapper gets a fresh __PolygonEditor__ id.
function __poly_live_link(_ed, _ed_node, _live_node) {
  if (!is_struct(_ed) || _ed_node == undefined || _live_node == undefined) return;
  if (!is_string(_ed_node.name) || !is_string(_live_node.name)) return;
  if (!variable_struct_exists(_ed, "live_links") || !is_struct(_ed.live_links)) _ed.live_links = {};
  _ed.live_links[$ _ed_node.name] = _live_node.name;
}

// Finds a live scene node by name (root list scan as fallback).
function __poly_live_find(_scene, _name) {
  if (_scene == undefined || !is_string(_name) || _name == "") return undefined;
  var _got = _scene.getNode(_name);

  if (_got != undefined) return _got;
  var _nodes = _scene.getNodes();

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    if (_nodes[_i] != undefined && _nodes[_i].name == _name) return _nodes[_i];
  }

  return undefined;
}

// Runtime { key: { model } } map used to spawn editor-only nodes live.
function __poly_play_assets(_ed) {
  var _out = {};

  if (!is_array(_ed[$ "assets"])) return _out;

  for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) {
    var _entry = _ed.assets[_i];

    if (!is_struct(_entry) || !is_string(_entry[$ "key"])) continue;
    _out[$ _entry.key] = { model: _entry[$ "model"] };
  }

  return _out;
}

// Applies one editor descriptor to its live counterpart in place.
function __poly_play_apply(_ed, _node, _desc) {
  if (_node == undefined || !is_struct(_desc)) return;
  var _t = is_struct(_desc[$ "transform"]) ? _desc.transform : undefined;

  if (is_struct(_t)) {
    var _p = _t[$ "position"];
    var _r = _t[$ "rotation"];
    var _s = _t[$ "scale"];

    if (is_array(_p) && array_length(_p) == 3) _node.setLocalPosition(new GM3D_Vec3(_p[0], _p[1], _p[2]));
    if (is_array(_s) && array_length(_s) == 3) _node.setLocalScale(new GM3D_Vec3(_s[0], _s[1], _s[2]));
    if (is_array(_r) && array_length(_r) == 4) _node.setLocalRotation(__poly_quat_from_array(_r));
  }

  if (_desc.kind == "instance" && is_struct(_desc[$ "shadows"])) {
    __poly_flags_apply(_node, _desc.shadows[$ "cast"] == true, _desc.shadows[$ "receive"] == true);
  }

  var _en = (is_struct(_ed[$ "reg"]) && is_string(_desc[$ "id"])) ? _ed.reg[$ _desc.id] : undefined;

  if (is_struct(_en)) __poly_walk_tree(_node, __poly_meshes_visit, { on: _en.hidden != true });

  // Physics only when the descriptor carries it: game-owned bodies on nodes
  // the editor never made physical stay untouched.
  if (is_struct(_desc[$ "physics"])) __poly_physics_apply(_node, _desc.physics);

  if (is_struct(_en) && is_struct(_en[$ "data"])) {
    // The live component may sit on the root or on its first child.
    var _pnode = __poly_adopt_comp_node(_node);

    if (_pnode == undefined) _pnode = _node;
    if (_desc.kind == "light") __poly_light_apply(_pnode, _en.data);
    else if (_desc.kind == "camera") __poly_camera_apply(_pnode, _en.data);
    else if (_desc.kind == "environment") __poly_env_apply(_pnode, _en.data);
  }

  if (_desc.kind == "instance" && is_string(_desc[$ "assetId"]) && _desc.assetId != "") {
    var _over = (is_struct(_en) && is_struct(_en[$ "data"])) ? _en.data[$ "vars"] : undefined;
    var _vars = __poly_vars_resolve_entry(_ed, _desc.assetId, _over);

    // Keep the resolved map readable on the live node afterwards.
    if (__poly_vars_has(_vars)) __poly_runtime_vars_set(_node, _vars);
  }
}

// Spawns one editor descriptor into the live scene (instances, props, audio),
// running the same hooks as a runtime load so the game can wire it up.
function __poly_play_create(_ed, _live, _desc, _assets) {
  var _pl = __poly_load_node(_live, _assets, _desc, _ed[$ "asset_meta"], undefined);

  if (_pl == undefined || _pl[$ "node"] == undefined) return undefined;
  var _node = _pl.node;

  if (_pl.kind == "instance") {
    var _vars = __poly_vars_clone(_pl[$ "vars"]);

    __poly_runtime_vars_set(_node, _vars);

    if (variable_struct_exists(_ed.rt, "on_create") && is_method(_ed.rt.on_create)) {
      _ed.rt.on_create(_node, _pl.asset, _pl.model, _pl.id, __poly_vars_clone(_vars));
    }

    var _hook = __poly_asset_get(_ed, _pl.asset);

    if (is_struct(_hook) && is_method(_hook[$ "on_create"])) {
      _hook.on_create(_node, _pl.asset, _pl.model, _pl.id, __poly_vars_clone(_vars));
    }
  }

  return _node;
}

// Pushes the editor scene into the live scene and reports what changed.
function __poly_play_sync(_ed) {
  var _report = { applied: 0, created: 0, removed: 0 };

  if (!is_struct(_ed) || !is_struct(_ed[$ "rt"])) return _report;
  var _live = _ed.rt[$ "live_scene"];

  if (_live == undefined) return _report;
  if (!variable_struct_exists(_ed, "live_links") || !is_struct(_ed.live_links)) _ed.live_links = {};
  var _assets = __poly_play_assets(_ed);
  var _descs = __poly_serialize_scene(_ed);

  for (var _i = 0, _n = array_length(_descs); _i < _n; _i++) {
    var _desc = _descs[_i];

    if (!is_struct(_desc) || !is_string(_desc[$ "id"]) || _desc.id == "") continue;
    var _id = _desc.id;
    var _link = _ed.live_links[$ _id];
    var _node = is_string(_link) ? __poly_live_find(_live, _link) : undefined;

    if (_node != undefined) {
      __poly_play_apply(_ed, _node, _desc);
      _report.applied++;
    } else {
      _node = __poly_play_create(_ed, _live, _desc, _assets);
      if (_node != undefined) _report.created++;
    }

    if (_node != undefined && is_string(_node.name)) _ed.live_links[$ _id] = _node.name;
  }

  // Nodes removed in the editor leave the live scene too. The registry is the
  // source of truth: the gameplay camera lives in it but is not serialized,
  // so it is never destroyed here.
  var _link_ids = variable_struct_get_names(_ed.live_links);

  for (var _j = 0, _m = array_length(_link_ids); _j < _m; _j++) {
    var _lid = _link_ids[_j];

    if (is_struct(_ed[$ "reg"]) && variable_struct_exists(_ed.reg, _lid)) continue;
    var _gone = __poly_live_find(_live, _ed.live_links[$ _lid]);

    if (_gone != undefined) {
      _gone.destroy();
      _report.removed++;
    }

    variable_struct_remove(_ed.live_links, _lid);
  }

  _live.update(0);
  return _report;
}
