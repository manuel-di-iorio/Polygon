// poly_registry — tracked node registry (struct by id, wrapper roots).
//
// Invariant: every tracked root is a wrapper.
// Assets are wrapper (empty) -> model root; lights/cameras/envs are a
// single wrapper node carrying the component. Lookup is always direct
// via the node name, which IS the id.

// ---------------------------------------------------------------------------
// Id helpers
// ---------------------------------------------------------------------------

// Returns the wrapper prefix.
function __poly_wrap_prefix() {
  return "__PolygonEditor__";
}

// Returns the wrapper id of a node, or undefined when not wrapped.
function __poly_wrap_id_of(_node) {
  if (_node == undefined || !is_string(_node.name)) return undefined;
  var _prefix = __poly_wrap_prefix();

  if (string_copy(_node.name, 1, string_length(_prefix)) != _prefix) return undefined;
  return _node.name;
}

// Compares two scene nodes by stable identity: the node name, which IS the
// wrapper id. Never compare node references with ==: GMRT queries may hand
// out fresh structs for the same native node, so == misses across queries
// (duplicated selection, stale anchors, chrome leaking into passes).
function __poly_node_same(_a, _b) {
  if (_a == undefined || _b == undefined) return false;
  if (!is_string(_a.name) || !is_string(_b.name) || _a.name == "") return false;
  return _a.name == _b.name;
}

// Checks whether a node list contains a node (by stable identity).
function __poly_node_list_has(_list, _node) {
  return __poly_node_list_index(_list, _node) >= 0;
}

// Finds the index of a node in a list (by stable identity), else -1.
function __poly_node_list_index(_list, _node) {
  if (!is_array(_list) || _node == undefined) return -1;
  for (var _i = 0, _n = array_length(_list); _i < _n; _i++) if (__poly_node_same(_list[_i], _node)) return _i;
  return -1;
}

// Tags a struct with an epoch value under a key (per-frame mark).
function __poly_epoch_tag(_s, _k, _v) {
  if (!is_struct(_s)) return;
  variable_struct_set(_s, _k, _v);
}

// Checks a struct against an epoch value (no lookup).
function __poly_epoch_check(_s, _k, _v) {
  return is_struct(_s) && variable_struct_exists(_s, _k) && variable_struct_get(_s, _k) == _v;
}

// Parses the numeric suffix of a wrapper id (or -1).
function __poly_wrap_id_num(_id) {
  if (!is_string(_id)) return -1;
  var _prefix = __poly_wrap_prefix();

  if (string_copy(_id, 1, string_length(_prefix)) != _prefix) return -1;
  var _num = real(string_copy(_id, string_length(_prefix) + 1, 32));

  if (!is_real(_num)) return -1;
  return floor(_num);
}

// Ensures the registry struct and id counter exist.
function __poly_reg_ensure(_ed) {
  if (!variable_struct_exists(_ed, "reg") || !is_struct(_ed.reg)) {
    _ed.reg = {};
  }

  if (!variable_struct_exists(_ed, "id_seq") || !is_real(_ed.id_seq)) _ed.id_seq = 1;
}

// Clears the registry (ids stay monotonic via id_seq).
function __poly_reg_clear(_ed) {
  _ed.reg = {};
  __poly_reg_ensure(_ed);
}

// Counts tracked entries.
function __poly_reg_count(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "reg") || !is_struct(_ed.reg)) return 0;
  return array_length(variable_struct_get_names(_ed.reg));
}

// Lists all registry entries.
function __poly_reg_each(_ed) {
  var _out = [];

  if (_ed == undefined || !variable_struct_exists(_ed, "reg") || !is_struct(_ed.reg)) return _out;
  var _names = variable_struct_get_names(_ed.reg);

  for (var _i = 0, _n = array_length(_names); _i < _n; _i++) {
    var _en = _ed.reg[$ _names[_i]];

    if (is_struct(_en)) array_push(_out, _en);
  }

  return _out;
}

// Generates a fresh wrapper id.
function __poly_wrap_new(_ed) {
  __poly_reg_ensure(_ed);
  var _id = __poly_wrap_prefix() + string(_ed.id_seq);
  _ed.id_seq++;
  return _id;
}

// Claims a wrapper id: keeps _want when free, else generates fresh.
// Call BEFORE createNode so the node is born with its final id.
function __poly_wrap_claim(_ed, _want) {
  __poly_reg_ensure(_ed);

  if (is_string(_want) && _want != "" && __poly_wrap_id_num(_want) >= 0
  && !variable_struct_exists(_ed.reg, _want)) {
    var _num = __poly_wrap_id_num(_want);

    if (_num >= _ed.id_seq) _ed.id_seq = _num + 1;
    return _want;
  }

  var _fresh = __poly_wrap_prefix() + string(_ed.id_seq);

  while (variable_struct_exists(_ed.reg, _fresh)) {
    _ed.id_seq++;
    _fresh = __poly_wrap_prefix() + string(_ed.id_seq);
  }

  _ed.id_seq++;
  return _fresh;
}

// Reseeds the counter above every id seen in the registry.
function __poly_seq_reseed(_ed) {
  __poly_reg_ensure(_ed);
  var _max = _ed.id_seq - 1;
  var _names = variable_struct_get_names(_ed.reg);

  for (var _i = 0, _n = array_length(_names); _i < _n; _i++) _max = max(_max, __poly_wrap_id_num(_names[_i]));
  _ed.id_seq = _max + 1;
}

// Finds a scene node by wrapper id (direct, with scan fallback).
function __poly_find_by_id(_ed, _id) {
  if (_ed == undefined || !is_string(_id) || _id == "" || _ed.rt == undefined || _ed.rt.scene == undefined) return undefined;
  var _got = undefined;
  _got = _ed.rt.scene.getNode(_id);
  if (_got != undefined) return _got;
  var _nodes = _ed.rt.scene.getNodes();

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) if (_nodes[_i] != undefined && _nodes[_i].name == _id) return _nodes[_i];
  return undefined;
}

// ---------------------------------------------------------------------------
// Registration and lookup
// ---------------------------------------------------------------------------

// Resets a freshly spawned model root to identity so the wrapper fully
// owns the instance transform. Matches the pre-wrapper behavior where
// place/track/load overwrote the spawned root transform (baked file
// offsets must not compose with the editor transform).
function __poly_spawn_reset_child(_child) {
  if (_child == undefined) return;
  _child.setLocalPosition(new GM3D_Vec3(0, 0, 0));
  _child.setLocalScale(new GM3D_Vec3(1, 1, 1));
  var _ident = new GM3D_Quaternion();
  _ident.x = 0;
  _ident.y = 0;
  _ident.z = 0;
  _ident.w = 1;
  _child.setLocalRotation(_ident);
}

// Registers spawned asset node for tracking.
function __poly_spawn_register(_ed, _node, _asset, _label = undefined) {
  var _data = __poly_flags_read(_node);
  var _physics = __poly_physics_live_read(_node);
  if (_physics != undefined && _physics.mode != "none") _data.physics = _physics;
  __poly_kind_register(_ed, _node, "instance", _asset, _label, _data);
}

// Registers a wrapper node with kind and metadata.
// The node name IS the id; _label is the optional custom instance name
// (display falls back to the asset file name + id number).
function __poly_kind_register(_ed, _node, _kind, _asset, _label = undefined, _data = undefined) {
  if (_ed == undefined || _node == undefined) return;
  if (_kind == undefined || !is_string(_kind) || _kind == "") _kind = "instance";
  if (_kind == "instance" && (_asset == undefined || _asset == "")) return;
  __poly_reg_ensure(_ed);
  var _id = __poly_wrap_id_of(_node);

  if (_id == undefined) return;
  if (variable_struct_exists(_ed.reg, _id) && _ed.reg[$ _id].node != _node) return;
  _ed.reg[$ _id] = {
    id: _id,
    kind: _kind,
    asset: _asset,
    label: _label,
    data: _data,
    hidden: false,
    locked: false,
    node: _node,
  };

  if (_ed.unlit_quiet != true) __poly_unlit_apply(_ed);
}

// Removes a wrapper node from the registry (direct by id).
function __poly_spawn_unregister(_ed, _node) {
  if (_ed == undefined || _node == undefined) return;
  __poly_reg_ensure(_ed);
  var _id = __poly_wrap_id_of(_node);

  if (_id != undefined && variable_struct_exists(_ed.reg, _id)) variable_struct_remove(_ed.reg, _id);
}

// Finds the registry entry for a node (direct by wrapper id).
function __poly_registry_find(_ed, _node) {
  if (_ed == undefined || _node == undefined) return undefined;
  __poly_reg_ensure(_ed);
  var _id = __poly_wrap_id_of(_node);

  if (_id == undefined || !variable_struct_exists(_ed.reg, _id)) return undefined;
  return _ed.reg[$ _id];
}

// Returns asset id for node.
function __poly_asset_name(_ed, _node) {
  var _en = __poly_registry_find(_ed, _node);

  if (_en == undefined) return undefined;
  return _en.asset;
}

// ---------------------------------------------------------------------------
// Descriptors and root lists
// ---------------------------------------------------------------------------

// Builds asset descriptor with transform.
function __poly_asset_desc(_ed, _node) {
  var _en = __poly_registry_find(_ed, _node);

  if (_en == undefined) return undefined;
  var _pos = _node.getLocalPosition();
  var _rot = _node.getLocalRotation();
  var _sca = _node.getLocalScale();
  var _cast = true;
  var _recv = true;

  if (is_struct(_en.data)) {
    _cast = _en.data.castShadows == true;
    _recv = _en.data.receiveShadows == true;
  }

  var _out = {
    id: _en.id,
    asset: _en.asset,
    label: _en.label,
    transform: {
      position: [ _pos.x, _pos.y, _pos.z ],
      rotation: [ _rot.x, _rot.y, _rot.z, _rot.w ],
      scale: [ _sca.x, _sca.y, _sca.z ],
    },
    shadows: { cast: _cast, receive: _recv },
  };
  if (is_struct(_en.data) && is_struct(_en.data[$ "physics"]) && _en.data.physics.mode != "none") _out.physics = __poly_physics_data(_en.data.physics);
  return _out;
}

// Lists tracked root scene nodes (via stored refs, no lookup).
function __poly_root_tracked(_ed) {
  var _out = [];
  var _ens = __poly_reg_each(_ed);

  for (var _i = 0, _n = array_length(_ens); _i < _n; _i++) {
    var _node = _ens[_i][$ "node"];

    if (_node == undefined || _node.parent != undefined) continue;
    array_push(_out, _node);
  }

  return _out;
}

// Lists tracked root nodes, optionally with entries (single pass, no lookup).
function __poly_root_list(_ed, _pairs) {
  var _out = [];

  if (_ed == undefined) return _out;
  var _ens = __poly_reg_each(_ed);

  for (var _i = 0, _n = array_length(_ens); _i < _n; _i++) {
    var _en = _ens[_i];
    var _node = _en[$ "node"];

    if (_node == undefined || _node.parent != undefined) continue;
    if (__poly_is_grid(_ed, _node)) continue;
    if (variable_struct_exists(_ed, "drag_preview") && __poly_node_same(_node, _ed.drag_preview)) continue;
    array_push(_out, _pairs ? { node: _node, en: _en } : _node);
  }

  return _out;
}

// Lists tracked root nodes with their entries (single pass, no lookup).
function __poly_root_pairs(_ed) {
  return __poly_root_list(_ed, true);
}

// Resolves registry entries to scene nodes (via stored refs, no lookup).
function __poly_tracked_nodes(_ed) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.scene == undefined) return [];
  return __poly_root_list(_ed, false);
}

// Returns the first child of a node, if any.
function __poly_first_child(_node) {
  if (_node == undefined) return undefined;
  var _kids = _node.getChildren();

  if (!is_array(_kids) || array_length(_kids) == 0) return undefined;
  return _kids[0];
}

// Checks one node for a light/camera/environment component.
function __poly_comp_kind(_node) {
  if (_node == undefined) return undefined;
  if (_node.getLightComponent() != undefined) return "light";
  if (_node.getCameraComponent() != undefined) return "camera";
  if (_node.getEnvironmentVolumeComponent() != undefined) return "environment";
  return undefined;
}

// Determines node kind from registry, else components (self, then child).
function __poly_kind_of(_ed, _node) {
  if (_node == undefined) return undefined;
  var _en = __poly_registry_find(_ed, _node);

  if (_en != undefined && is_string(_en.kind) && _en.kind != "") return _en.kind;
  var _self = __poly_comp_kind(_node);

  if (_self != undefined) return _self;
  var _child = __poly_comp_kind(__poly_first_child(_node));

  if (_child != undefined) return _child;
  if (_en != undefined) return "instance";
  return undefined;
}

// ---------------------------------------------------------------------------
// Unified spawn pipeline (single createNode + spawnInto + TRS + data/hook/register).
// ---------------------------------------------------------------------------

// Spawns one node through the single pipeline. _ed is editor state, or a
// raw GM3D_Scene (load path: registry/hook steps are skipped).
// _opt: { kind, asset, model, data, x, y, z, rx, ry, rz, rw, sx, sy, sz,
// pos, rot, scale, rotation, label, id, adopt_src, skip_hook, skip_register }.
// kind: "prefab"/"primitive"/"instance" (model inside a wrapper),
// "light"/"camera"/"environment" (component on the wrapper),
// "chrome" (model at scene root, untracked: grid/sky).
// Rotation is a quaternion object via _opt.rot, a [x,y,z,w] array via
// _opt.rot/_opt.rotation, or quaternion components via rx,ry,rz,rw.
// Wrappers pre-claim ids (wrap_new/wrap_claim) into _opt.id and keep their
// own validation; only the common body lives here.
function __poly_spawn(_ed, _opt) {
  if (_opt == undefined || !is_struct(_opt)) return undefined;
  var _is_ed = is_struct(_ed) && variable_struct_exists(_ed, "rt") && is_struct(_ed.rt)
    && variable_struct_exists(_ed.rt, "scene") && _ed.rt.scene != undefined;
  var _scene = _is_ed ? _ed.rt.scene : undefined;

  if (!_is_ed && is_struct(_ed) && variable_struct_exists(_ed, "createNode")) _scene = _ed;
  if (_scene == undefined) return undefined;
  var _kind = "instance";

  if (variable_struct_exists(_opt, "kind") && is_string(_opt.kind) && _opt.kind != "") _kind = _opt.kind;
  if (_kind == "prefab" || _kind == "primitive") _kind = "instance";
  var _is_chrome = (_kind == "chrome");
  var _is_inst = (_kind == "instance");
  var _is_prop = (_kind == "light" || _kind == "camera" || _kind == "environment");

  if (!_is_inst && !_is_prop && !_is_chrome) return undefined;
  var _model = _opt[$ "model"];

  if (_model == undefined && _is_ed && (_is_inst || _is_chrome)
  && variable_struct_exists(_opt, "asset") && is_string(_opt.asset) && _opt.asset != "") {
    _model = __poly_asset_find(_ed, _opt.asset);
  }

  if ((_is_inst || _is_chrome) && _model == undefined) return undefined;
  var _data = _opt[$ "data"];
  var _asset = (variable_struct_exists(_opt, "asset") && is_string(_opt.asset)) ? _opt.asset : "";
  var _label = _opt[$ "label"];

  var _px = 0;
  var _py = 0;
  var _pz = 0;
  var _sx = 1;
  var _sy = 1;
  var _sz = 1;
  var _rot = undefined;

  if (variable_struct_exists(_opt, "pos") && is_array(_opt.pos) && array_length(_opt.pos) == 3
  && is_real(_opt.pos[0]) && is_real(_opt.pos[1]) && is_real(_opt.pos[2])) {
    _px = _opt.pos[0];
    _py = _opt.pos[1];
    _pz = _opt.pos[2];
  } else {
    if (variable_struct_exists(_opt, "x") && is_real(_opt.x)) _px = _opt.x;
    if (variable_struct_exists(_opt, "y") && is_real(_opt.y)) _py = _opt.y;
    if (variable_struct_exists(_opt, "z") && is_real(_opt.z)) _pz = _opt.z;
  }

  if (variable_struct_exists(_opt, "scale") && is_array(_opt.scale) && array_length(_opt.scale) == 3
  && is_real(_opt.scale[0]) && is_real(_opt.scale[1]) && is_real(_opt.scale[2])) {
    _sx = _opt.scale[0];
    _sy = _opt.scale[1];
    _sz = _opt.scale[2];
  } else {
    if (variable_struct_exists(_opt, "sx") && is_real(_opt.sx)) _sx = _opt.sx;
    if (variable_struct_exists(_opt, "sy") && is_real(_opt.sy)) _sy = _opt.sy;
    if (variable_struct_exists(_opt, "sz") && is_real(_opt.sz)) _sz = _opt.sz;
  }

  if (variable_struct_exists(_opt, "rot") && _opt.rot != undefined) {
    if (is_array(_opt.rot)) {
      if (array_length(_opt.rot) == 4 && is_real(_opt.rot[0])) _rot = __poly_quat_from_array(_opt.rot);
    } else {
      _rot = _opt.rot;
    }
  } else if (variable_struct_exists(_opt, "rotation") && is_array(_opt.rotation)
  && array_length(_opt.rotation) == 4 && is_real(_opt.rotation[0])) {
    _rot = __poly_quat_from_array(_opt.rotation);
  } else if (variable_struct_exists(_opt, "rx") && is_real(_opt.rx)) {
    var _qy = (variable_struct_exists(_opt, "ry") && is_real(_opt.ry)) ? _opt.ry : 0;
    var _qz = (variable_struct_exists(_opt, "rz") && is_real(_opt.rz)) ? _opt.rz : 0;
    var _qw = (variable_struct_exists(_opt, "rw") && is_real(_opt.rw)) ? _opt.rw : 1;
    var _qq = new GM3D_Quaternion();
    _qq.x = _opt.rx;
    _qq.y = _qy;
    _qq.z = _qz;
    _qq.w = _qw;
    _rot = _qq.normalizeSafe(0.000001);
  }

  var _wrap = undefined;

  if (!_is_chrome) {
    var _nid = (variable_struct_exists(_opt, "id") && is_string(_opt.id) && _opt.id != "") ? _opt.id : undefined;

    if (_nid == undefined) _nid = _is_ed ? __poly_wrap_new(_ed) : "node";
    _wrap = _scene.createNode(_nid);

    if (_wrap == undefined) return undefined;
  }

  if (_is_inst || _is_chrome) {
    var _grown = _model.spawnInto(_scene, _is_chrome ? undefined : _wrap);

    if (_grown == undefined) {
      if (_wrap != undefined) _wrap.destroy();
      return undefined;
    }

    if (_is_chrome) {
      _wrap = _grown;
    } else {
      __poly_spawn_reset_child(_grown);
    }
  } else if (_kind == "light") {
    _wrap.addComponent(new GM3D_LightComponent());
  } else if (_kind == "camera") {
    _wrap.addComponent(new GM3D_CameraComponent());
  } else {
    _wrap.addComponent(new GM3D_EnvironmentVolumeComponent());
  }

  _wrap.setLocalPosition(new GM3D_Vec3(_px, _py, _pz));
  _wrap.setLocalScale(new GM3D_Vec3(_sx, _sy, _sz));

  if (_rot != undefined) _wrap.setLocalRotation(_rot);
  var _skip_hook = variable_struct_exists(_opt, "skip_hook") && _opt.skip_hook == true;
  var _skip_reg = variable_struct_exists(_opt, "skip_register") && _opt.skip_register == true;

  if (_is_chrome) return _wrap;

  if (_is_inst) {
    var _physics = undefined;
    if (is_struct(_data) && variable_struct_exists(_data, "physics")) {
      _physics = __poly_physics_data(_data.physics);
      var _instance_character = _data[$ "physics"][$ "character"];
      if (_physics.mode == "character" && (!is_struct(_instance_character) || !variable_struct_exists(_instance_character, "visualOffset"))) _physics = __poly_physics_fit_visual(_model, _physics);
    }
    else if (_is_ed && _data == undefined) {
      var _meta = is_struct(_ed.asset_meta) ? _ed.asset_meta[$ _asset] : undefined;
      if (is_struct(_meta) && is_struct(_meta[$ "physics"])) {
        _physics = __poly_physics_data(_meta.physics);
        var _meta_character = _meta[$ "physics"][$ "character"];
        if (_physics.mode == "character" && (!is_struct(_meta_character) || !variable_struct_exists(_meta_character, "visualOffset"))) _physics = __poly_physics_fit_visual(_model, _physics);
      }
      var _lib_entry = __poly_asset_get(_ed, _asset);
      if (_physics == undefined && _lib_entry != undefined && is_struct(_lib_entry[$ "physics_default"])) {
        _physics = __poly_physics_data(_lib_entry.physics_default);
        var _default_character = _lib_entry[$ "physics_default"][$ "character"];
        if (_physics.mode == "character" && (!is_struct(_default_character) || !variable_struct_exists(_default_character, "visualOffset"))) _physics = __poly_physics_fit_visual(_model, _physics);
      }
    }
    if (_physics != undefined && _physics.mode != "none") __poly_physics_apply(_wrap, _physics);
    if (is_struct(_data)) {
      if (_physics != undefined) _data.physics = _physics;
      else if (variable_struct_exists(_data, "physics")) _data.physics = __poly_physics_data(_data.physics);
    } else if (_physics != undefined) {
      _data = { castShadows: true, receiveShadows: true, physics: _physics };
    }
    if (_is_ed) {
      __poly_magenta_fix(_ed, _wrap);
    } else {
      __poly_load_magenta_fix(_wrap);
    }

    if (_is_ed && !_skip_hook) {
      // Unified spawn contract (editor and runtime): global hook first,
      // then the per-model hook from the library entry.
      // (node, asset, model, id): model stays 3rd so existing
      // 3-arg hooks keep working unchanged.
      if (variable_struct_exists(_ed.rt, "on_create") && is_method(_ed.rt.on_create)) _ed.rt.on_create(_wrap, _asset, _model, _wrap.name);
      var _hook_entry = __poly_asset_get(_ed, _asset);
      if (_hook_entry != undefined && is_method(_hook_entry[$ "on_create"])) _hook_entry.on_create(_wrap, _asset, _model, _wrap.name);
    }

    if (_is_ed && !_skip_reg) {
      var _pp = _wrap.getLocalPosition();

      if (is_struct(_data) && (variable_struct_exists(_data, "castShadows") || variable_struct_exists(_data, "physics"))) {
        __poly_kind_register(_ed, _wrap, "instance", _asset, _label, _data);
        if (variable_struct_exists(_data, "castShadows")) __poly_flags_apply_data(_wrap, _data);
      } else {
        __poly_spawn_register(_ed, _wrap, _asset, _label);
      }
    } else if (!_is_ed && is_struct(_data) && variable_struct_exists(_data, "castShadows")) {
      __poly_flags_apply_data(_wrap, _data);
    }

    if (variable_struct_exists(_opt, "adopt_src") && _opt.adopt_src != undefined) __poly_track_adopt_flags(_opt.adopt_src, _wrap);
    if (_is_ed) __poly_physics_debug_rebuild(_ed);
    return _wrap;
  }

  if (!_is_ed) {
    _wrap.destroy();
    return undefined;
  }

  if (_data != undefined) {
    if (_kind == "light") {
      __poly_light_apply(_wrap, _data);
    } else if (_kind == "camera") {
      __poly_camera_apply(_wrap, _data);
    } else {
      __poly_env_apply(_wrap, _data);
    }
  }

  _scene.update(0);

  if (!_skip_reg) {
    var _qp = _wrap.getLocalPosition();
    __poly_kind_register(_ed, _wrap, _kind, "", _label, _data);
  }

  if (variable_struct_exists(_opt, "adopt_src") && _opt.adopt_src != undefined) __poly_track_adopt_flags(_opt.adopt_src, _wrap);
  return _wrap;
}

// ---------------------------------------------------------------------------
// Placement (wrappers over __poly_spawn; validation stays here)
// ---------------------------------------------------------------------------

function __poly_place(_ed, _asset, _model, _pos3, _rot, _scale3, _label = undefined) {
  if (_ed == undefined || _model == undefined) return undefined;
  return __poly_spawn(_ed, {
    kind: "prefab",
    asset: _asset,
    model: _model,
    pos: _pos3,
    rot: _rot,
    scale: _scale3,
    label: _label,
    id: __poly_wrap_new(_ed),
  });
}

// Respawns a library model at a live node's transform, inside a wrapper
// that preserves the live id when present.
function __poly_track_place_asset(_ed, _key, _model, _node, _label = undefined) {
  if (_ed == undefined || _model == undefined || _node == undefined) return undefined;
  var _pos = _node.getLocalPosition();
  var _sca = _node.getLocalScale();
  var _data = { castShadows: true, receiveShadows: true };

  // Adopt the live body/shape/controller so tracking (manual or automatic)
  // never silently imports a physical instance as a visual-only node. Passing
  // it as spawn data applies it before the debug world is rebuilt.
  var _live_physics = __poly_physics_live_read(_node);

  if (_live_physics != undefined && _live_physics.mode != "none") _data.physics = _live_physics;

  return __poly_spawn(_ed, {
    kind: "prefab",
    asset: _key,
    model: _model,
    x: _pos.x,
    y: _pos.y,
    z: _pos.z,
    rot: _node.getLocalRotation().clone(),
    sx: _sca.x,
    sy: _sca.y,
    sz: _sca.z,
    label: _label,
    id: __poly_wrap_claim(_ed, __poly_wrap_id_of(_node)),
    adopt_src: _node,
    data: _data,
  });
}


// ---------------------------------------------------------------------------
// Auto-import matching
// ---------------------------------------------------------------------------

// Lists library entries whose model root name equals the live node name.
// Entries are keyed by load path, so duplicate root names can coexist;
// the caller adopts only on a unique candidate.
function __poly_asset_cands(_ed, _name) {
  var _out = [];

  if (!is_string(_name) || _name == "" || !is_array(_ed.assets)) return _out;

  for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) {
    var _entry = _ed.assets[_i];

    if (!is_struct(_entry) || !is_string(_entry.name) || _entry.name == "") continue;
    if (_entry.name == _name && is_string(_entry.key) && _entry.key != "") array_push(_out, _entry);
  }

  return _out;
}

// Returns the matchable content of a live node: the first child when the
// node itself is a wrapper, else the node.
function __poly_adopt_content(_node) {
  if (_node != undefined && __poly_wrap_id_of(_node) != undefined) {
    var _child = __poly_first_child(_node);

    if (_child != undefined) return _child;
  }

  return _node;
}

// Resolves a live node to a library id by model root name only: the
// wrapper id (which IS the node name) is the single identity. A unique
// name candidate wins, anything else (none or ambiguous) is skipped.
function __poly_track_match(_ed, _node) {
  var _content = __poly_adopt_content(_node);
  var _cands = __poly_asset_cands(_ed, _content.name);

  if (array_length(_cands) == 1) return _cands[0].key;
  return undefined;
}

// Imports one live root node, inferring kind from components.
// Non-root nodes are skipped (they arrive with their model subtree).
function __poly_track_adopt_auto(_ed, _node) {
  if (_node == undefined || _node.parent != undefined) return undefined;
  var _content = __poly_adopt_content(_node);

  if (__poly_comp_kind(_content) != undefined || __poly_comp_kind(_node) != undefined) {
    var _pkind = __poly_comp_kind(_node);

    if (_pkind == undefined) _pkind = __poly_comp_kind(_content);
    if (_pkind == "light") return __poly_track_adopt_light(_ed, _node);
    if (_pkind == "camera") return __poly_track_adopt_camera(_ed, _node);
    return __poly_track_adopt_env(_ed, _node);
  }

  var _matched = __poly_track_match(_ed, _node);

  if (_matched == undefined) return undefined;
  var _model = __poly_asset_find(_ed, _matched);

  if (_model == undefined) return undefined;
  var _new = __poly_track_place_asset(_ed, _matched, _model, _node);

  if (_new == undefined) return undefined;
  __poly_track_adopt_flags(_node, _new);
  return _new;
}

// Copies mesh shadow flags from a live subtree to an adopted copy.
// Both trees share structure, so a parallel walk aligns components.
function __poly_track_adopt_flags(_src_node, _dst_node) {
  var _src_list = [];
  var _dst_list = [];
  __poly_walk_collect_tree(_src_node, _src_list);
  __poly_walk_collect_tree(_dst_node, _dst_list);
  var _n = min(array_length(_src_list), array_length(_dst_list));

  for (var _i = 0; _i < _n; _i++) {
    var _src_comp = _src_list[_i].comp;
    var _dst_comp = _dst_list[_i].comp;

    if (_src_comp == undefined || _dst_comp == undefined) continue;
    var _get = _src_comp[$ "getFlags"];
    var _set = _dst_comp[$ "setFlags"];

    if (_get == undefined || _set == undefined) continue;
    method(_dst_comp, _set)(method(_src_comp, _get)());
  }
}

// ---------------------------------------------------------------------------
// Prop adoption (wrapper node carries the component + id)
// ---------------------------------------------------------------------------

// Finds the component-bearing node in a live subtree (self, then child).
function __poly_adopt_comp_node(_node) {
  if (_node == undefined) return undefined;
  if (__poly_comp_kind(_node) != undefined) return _node;
  var _child = __poly_first_child(_node);

  if (_child != undefined && __poly_comp_kind(_child) != undefined) return _child;
  return undefined;
}

// Creates a positioned editor wrapper node, preserving the live id.
function __poly_track_make_node(_ed, _node) {
  var _pos = _node.getLocalPosition();
  var _new = _ed.rt.scene.createNode(__poly_wrap_claim(_ed, __poly_wrap_id_of(_node)));

  if (_new == undefined) return undefined;
  _new.setLocalPosition(new GM3D_Vec3(_pos.x, _pos.y, _pos.z));
  _new.setLocalRotation(_node.getLocalRotation().clone());
  return _new;
}

// Finishes adopting a prop node: component, data, register, hide, mute.
function __poly_track_adopt_finish(_ed, _new, _node, _kind, _data, _label = undefined) {
  if (_kind == "light") _new.addComponent(new GM3D_LightComponent());
  else if (_kind == "camera")  _new.addComponent(new GM3D_CameraComponent());
  else  _new.addComponent(new GM3D_EnvironmentVolumeComponent());
  if (_kind == "light") __poly_light_apply(_new, _data);
  else if (_kind == "camera")  __poly_camera_apply(_new, _data);
  else  __poly_env_apply(_new, _data);
  _ed.rt.scene.update(0);
  __poly_kind_register(_ed, _new, _kind, "", _label, _data);
  if (_kind == "camera") __poly_cameras_mute(_ed);
  return _new;
}

// Adopts a live light node into the editor scene.
function __poly_track_adopt_light(_ed, _node, _label = undefined) {
  var _src = __poly_adopt_comp_node(_node);

  if (_src == undefined || _src.getLightComponent() == undefined) return undefined;
  var _new = __poly_track_make_node(_ed, _node);

  if (_new == undefined) return undefined;
  return __poly_track_adopt_finish(_ed, _new, _node, "light", __poly_light_read(_src), _label);
}

// Adopts a live camera node into the editor scene.
function __poly_track_adopt_camera(_ed, _node, _label = undefined) {
  var _src = __poly_adopt_comp_node(_node);

  if (_src == undefined || _src.getCameraComponent() == undefined) return undefined;
  var _new = __poly_track_make_node(_ed, _node);

  if (_new == undefined) return undefined;
  return __poly_track_adopt_finish(_ed, _new, _node, "camera", __poly_camera_read(_src), _label);
}

// Adopts a live environment node into the editor scene.
function __poly_track_adopt_env(_ed, _node, _label = undefined) {
  var _src = __poly_adopt_comp_node(_node);

  if (_src == undefined || _src.getEnvironmentVolumeComponent() == undefined) return undefined;
  var _pos = _node.getLocalPosition();
  var _new = _ed.rt.scene.createNode(__poly_wrap_claim(_ed, __poly_wrap_id_of(_node)));

  if (_new == undefined) return undefined;
  _new.setLocalPosition(new GM3D_Vec3(_pos.x, _pos.y, _pos.z));
  return __poly_track_adopt_finish(_ed, _new, _node, "environment", __poly_env_read(_src), _label);
}
