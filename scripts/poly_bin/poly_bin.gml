// poly_bin — optimized binary scene format (PLYB v2), buffer-based.
// Layout (little-endian, alignment 1, strings = buffer_string):
//   u8[4] magic "PLYB", u16 bin_version (=2), s32 seq
//   v2: 3x f32 gravity, f32 fixedTimeStep, u16 maxSubSteps, u16 maxBodies
//   u16 asset_count, per asset: string key, u8 has_actor, [string obj, string layer],
//     v2: u8 has_physics, [string physics_json]
//   u32 node_count, per node:
//     u8 kind (0 instance, 1 light, 2 camera, 3 env)
//     string id, string label ("" = none)
//     3x f32 pos, 4x f32 rot, 3x f32 scale
//     instance: string assetId, u8 shadow bits (1 cast, 2 receive),
//       v2: u8 has_physics, [string physics_json]
//     light: u8 type (0 dir, 1 point, 2 spot), 3x u8 color,
//       f32 intensity, range, inner, outer, u8 flags (1 enabled, 2 shadow),
//       u16 shadowRes, f32 shadowDist, f32 shadowNormal
//     camera: u8 proj (0 persp, 1 ortho), f32 fov, ow, oh, near, far, u8 enabled
//     env: 3x f32 size, 3x u8 ambient, u8 fog, 3x u8 fogColor,
//       f32 fogStart, f32 fogEnd, u8 enabled
//   v1 files omit all v2 fields and load with default world/no physics.

// Returns the binary scene extension (with dot).
function __poly_bin_ext() {
  return ".bin";
}

// Checks if a path points to a binary scene (by extension).
function __poly_bin_is_path(_path) {
  if (!is_string(_path) || string_length(_path) < 4) return false;
  return string_copy(string_lower(_path), string_length(_path) - 3, 4) == ".bin";
}

// Checks the PLYB magic without fully parsing (false on any error).
function __poly_bin_has_magic(_path) {
  if (!is_string(_path) || _path == "" || !file_exists(_path)) return false;
  var _buf = buffer_load(_path);

  if (_buf < 0) return false;
  var _ok = false;

  if (buffer_get_size(_buf) >= 4) {
    _ok = buffer_peek(_buf, 0, buffer_u8) == 80 && buffer_peek(_buf, 1, buffer_u8) == 76
      && buffer_peek(_buf, 2, buffer_u8) == 89 && buffer_peek(_buf, 3, buffer_u8) == 66;
  }

  buffer_delete(_buf);
  return _ok;
}

// Maps descriptor kind to a binary id.
function __poly_bin_kind_id(_kind) {
  if (_kind == "light") return 1;
  if (_kind == "camera") return 2;
  if (_kind == "environment") return 3;
  return 0;
}

// Writes one f32 triplet.
function __poly_bin_w_vec3(_buf, _arr, _dx, _dy, _dz) {
  var _x = _dx, _y = _dy, _z = _dz;

  if (is_array(_arr) && array_length(_arr) == 3 && is_real(_arr[0]) && is_real(_arr[1]) && is_real(_arr[2])) {
    _x = _arr[0];
    _y = _arr[1];
    _z = _arr[2];
  }

  buffer_write(_buf, buffer_f32, _x);
  buffer_write(_buf, buffer_f32, _y);
  buffer_write(_buf, buffer_f32, _z);
}

// Writes one u8 rgb triplet (clamped).
function __poly_bin_w_col(_buf, _arr, _dr, _dg, _db) {
  var _c = [ _dr, _dg, _db ];

  if (is_array(_arr) && array_length(_arr) == 3 && is_real(_arr[0]) && is_real(_arr[1]) && is_real(_arr[2])) _c = _arr;
  buffer_write(_buf, buffer_u8, clamp(round(_c[0]), 0, 255));
  buffer_write(_buf, buffer_u8, clamp(round(_c[1]), 0, 255));
  buffer_write(_buf, buffer_u8, clamp(round(_c[2]), 0, 255));
}

// Writes a string field ("" for missing).
function __poly_bin_w_str(_buf, _v) {
  buffer_write(_buf, buffer_string, is_string(_v) ? _v : "");
}

// Reads a guarded real with fallback.
function __poly_bin_r_num(_v, _def) {
  return is_real(_v) ? _v : _def;
}

// Saves descriptors to a binary file. Returns true on success.
function __poly_bin_save_descs(_path, _seq, _assets, _nodes, _world = undefined) {
  if (!is_string(_path) || _path == "") return false;
  if (!is_array(_nodes)) return false;
  if (!is_struct(_assets)) _assets = {};
  var _buf = buffer_create(1024, buffer_grow, 1);

  buffer_write(_buf, buffer_u8, 80); // P
  buffer_write(_buf, buffer_u8, 76); // L
  buffer_write(_buf, buffer_u8, 89); // Y
  buffer_write(_buf, buffer_u8, 66); // B
  buffer_write(_buf, buffer_u16, 2);
  buffer_write(_buf, buffer_s32, is_real(_seq) ? floor(_seq) : 1);
  var _wd = __poly_world_data(_world);
  __poly_bin_w_vec3(_buf, _wd.gravity, 0, -9.81, 0);
  buffer_write(_buf, buffer_f32, _wd.fixedTimeStep);
  buffer_write(_buf, buffer_u16, _wd.maxSubSteps);
  buffer_write(_buf, buffer_u16, _wd.maxBodies);
  var _akeys = variable_struct_get_names(_assets);
  // Keep only struct values (same tolerance as the JSON "assets" map).
  var _kept = [];

  for (var _a = 0, _na = array_length(_akeys); _a < _na; _a++) {
    var _av = _assets[$ _akeys[_a]];

    if (is_struct(_av)) array_push(_kept, _akeys[_a]);
  }

  buffer_write(_buf, buffer_u16, array_length(_kept));

  for (var _k = 0, _nk = array_length(_kept); _k < _nk; _k++) {
    var _key = _kept[_k];
    var _meta = _assets[$ _key];
    __poly_bin_w_str(_buf, _key);
    var _has_actor = is_struct(_meta[$ "actor"]) && is_string(_meta.actor[$ "object"]) && _meta.actor.object != "";
    buffer_write(_buf, buffer_u8, _has_actor ? 1 : 0);

    if (_has_actor) {
      __poly_bin_w_str(_buf, _meta.actor[$ "object"]);
      var _layer = _meta.actor[$ "layer"];
      __poly_bin_w_str(_buf, is_string(_layer) && _layer != "" ? _layer : "Instances");
    }
    var _has_physics = is_struct(_meta[$ "physics"]);
    buffer_write(_buf, buffer_u8, _has_physics ? 1 : 0);
    if (_has_physics) __poly_bin_w_str(_buf, json_stringify(_meta.physics));
  }

  buffer_write(_buf, buffer_u32, array_length(_nodes));

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _d = _nodes[_i];
    var _kind = is_struct(_d) && is_string(_d[$ "kind"]) ? _d.kind : "instance";
    buffer_write(_buf, buffer_u8, __poly_bin_kind_id(_kind));
    __poly_bin_w_str(_buf, _d[$ "id"]);
    __poly_bin_w_str(_buf, _d[$ "label"]);
    var _t = is_struct(_d[$ "transform"]) ? _d.transform : {};
    __poly_bin_w_vec3(_buf, _t[$ "position"], 0, 0, 0);
    var _rot = _t[$ "rotation"];
    var _rx = 0, _ry = 0, _rz = 0, _rw = 1;

    if (is_array(_rot) && array_length(_rot) == 4 && is_real(_rot[0]) && is_real(_rot[1]) && is_real(_rot[2]) && is_real(_rot[3])) {
      _rx = _rot[0];
      _ry = _rot[1];
      _rz = _rot[2];
      _rw = _rot[3];
    }

    buffer_write(_buf, buffer_f32, _rx);
    buffer_write(_buf, buffer_f32, _ry);
    buffer_write(_buf, buffer_f32, _rz);
    buffer_write(_buf, buffer_f32, _rw);
    __poly_bin_w_vec3(_buf, _t[$ "scale"], 1, 1, 1);

    if (_kind == "instance") {
      __poly_bin_w_str(_buf, _d[$ "assetId"]);
      var _cast = true, _recv = true;

      if (is_struct(_d[$ "shadows"])) {
        _cast = _d.shadows[$ "cast"] == true;
        _recv = _d.shadows[$ "receive"] == true;
      }

      buffer_write(_buf, buffer_u8, (_cast ? 1 : 0) | (_recv ? 2 : 0));
      var _has_instance_physics = is_struct(_d[$ "physics"]);
      buffer_write(_buf, buffer_u8, _has_instance_physics ? 1 : 0);
      if (_has_instance_physics) __poly_bin_w_str(_buf, json_stringify(_d.physics));
    } else if (_kind == "light") {
      var _l = is_struct(_d[$ "light"]) ? _d.light : {};
      var _lt = _l[$ "type"];
      buffer_write(_buf, buffer_u8, _lt == "point" ? 1 : (_lt == "spot" ? 2 : 0));
      __poly_bin_w_col(_buf, _l[$ "color"], 255, 255, 255);
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_l[$ "intensity"], 1));
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_l[$ "range"], 50));
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_l[$ "innerCone"], 30));
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_l[$ "outerCone"], 45));
      var _en = _l[$ "enabled"] != false ? 1 : 0;
      var _sh = 0;

      if (is_struct(_l[$ "shadow"])) if (_l.shadow[$ "enabled"] == true) _sh = 1;
      buffer_write(_buf, buffer_u8, _en | (_sh << 1));
      var _res = 2048, _dist = 20, _nrm = 0.05;

      if (is_struct(_l[$ "shadow"])) {
        if (is_real(_l.shadow[$ "resolution"])) _res = _l.shadow.resolution;
        if (is_real(_l.shadow[$ "distance"])) _dist = _l.shadow.distance;
        if (is_real(_l.shadow[$ "normalOffset"])) _nrm = _l.shadow.normalOffset;
      }

      buffer_write(_buf, buffer_u16, clamp(round(_res), 0, 65535));
      buffer_write(_buf, buffer_f32, _dist);
      buffer_write(_buf, buffer_f32, _nrm);
    } else if (_kind == "camera") {
      var _c = is_struct(_d[$ "camera"]) ? _d.camera : {};
      buffer_write(_buf, buffer_u8, _c[$ "projection"] == "ortho" ? 1 : 0);
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_c[$ "fovY"], 60));
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_c[$ "orthoWidth"], 10));
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_c[$ "orthoHeight"], 10));
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_c[$ "near"], 0.1));
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_c[$ "far"], 10000));
      buffer_write(_buf, buffer_u8, _c[$ "enabled"] != false ? 1 : 0);
    } else {
      var _e = is_struct(_d[$ "environment"]) ? _d.environment : {};
      __poly_bin_w_vec3(_buf, _e[$ "size"], 20000, 20000, 20000);
      __poly_bin_w_col(_buf, _e[$ "ambient"], 70, 70, 85);
      buffer_write(_buf, buffer_u8, _e[$ "fogEnabled"] == true ? 1 : 0);
      __poly_bin_w_col(_buf, _e[$ "fogColor"], 192, 192, 192);
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_e[$ "fogStart"], 20));
      buffer_write(_buf, buffer_f32, __poly_bin_r_num(_e[$ "fogEnd"], 100));
      buffer_write(_buf, buffer_u8, _e[$ "enabled"] != false ? 1 : 0);
    }
  }

  buffer_save(_buf, _path);
  buffer_delete(_buf);
  return file_exists(_path);
}

// Reads one u8 rgb triplet.
function __poly_bin_r_col(_buf) {
  return [ buffer_read(_buf, buffer_u8), buffer_read(_buf, buffer_u8), buffer_read(_buf, buffer_u8) ];
}

// Loads a binary scene file. Returns { seq, assets, nodes } or undefined.
function __poly_bin_load_data(_path) {
  if (!is_string(_path) || _path == "" || !file_exists(_path)) return undefined;
  var _buf = buffer_load(_path);

  if (_buf < 0) return undefined;
  var _out = undefined;

  if (buffer_read(_buf, buffer_u8) != 80 || buffer_read(_buf, buffer_u8) != 76
  || buffer_read(_buf, buffer_u8) != 89 || buffer_read(_buf, buffer_u8) != 66) {
    buffer_delete(_buf);
    return undefined;
  }

  var _ver = buffer_read(_buf, buffer_u16);

  if (_ver != 1 && _ver != 2) {
    buffer_delete(_buf);
    return undefined;
  }

  var _seq = buffer_read(_buf, buffer_s32);
  var _world = __poly_world_defaults();
  if (_ver >= 2) {
    _world.gravity = [buffer_read(_buf, buffer_f32), buffer_read(_buf, buffer_f32), buffer_read(_buf, buffer_f32)];
    _world.fixedTimeStep = buffer_read(_buf, buffer_f32);
    _world.maxSubSteps = buffer_read(_buf, buffer_u16);
    _world.maxBodies = buffer_read(_buf, buffer_u16);
  }
  var _assets = {};
  var _na = buffer_read(_buf, buffer_u16);

  for (var _a = 0; _a < _na; _a++) {
    var _key = buffer_read(_buf, buffer_string);
    var _has = buffer_read(_buf, buffer_u8);
    var _entry = { type: "model" };

    if (_has == 1) {
      var _obj = buffer_read(_buf, buffer_string);
      var _layer = buffer_read(_buf, buffer_string);

      if (_obj != "") _entry.actor = { object: _obj, layer: _layer != "" ? _layer : "Instances" };
    }
    if (_ver >= 2 && buffer_read(_buf, buffer_u8) == 1) {
      var _asset_physics_text = buffer_read(_buf, buffer_string);
      var _asset_physics_data = json_parse(_asset_physics_text);
      if (is_struct(_asset_physics_data)) _entry.physics = _asset_physics_data;
    }

    if (_key != "") _assets[$ _key] = _entry;
  }

  var _nn = buffer_read(_buf, buffer_u32);
  var _nodes = [];

  for (var _i = 0; _i < _nn; _i++) {
    var _kid = buffer_read(_buf, buffer_u8);
    var _id = buffer_read(_buf, buffer_string);
    var _label = buffer_read(_buf, buffer_string);
    var _px = buffer_read(_buf, buffer_f32);
    var _py = buffer_read(_buf, buffer_f32);
    var _pz = buffer_read(_buf, buffer_f32);
    var _qx = buffer_read(_buf, buffer_f32);
    var _qy = buffer_read(_buf, buffer_f32);
    var _qz = buffer_read(_buf, buffer_f32);
    var _qw = buffer_read(_buf, buffer_f32);
    var _sx = buffer_read(_buf, buffer_f32);
    var _sy = buffer_read(_buf, buffer_f32);
    var _sz = buffer_read(_buf, buffer_f32);
    var _kind = _kid == 1 ? "light" : (_kid == 2 ? "camera" : (_kid == 3 ? "environment" : "instance"));
    var _desc = {
      kind: _kind,
      id: _id,
      assetId: "",
      transform: { position: [ _px, _py, _pz ], rotation: [ _qx, _qy, _qz, _qw ], scale: [ _sx, _sy, _sz ] },
    };

    if (_label != "") _desc.label = _label;

    if (_kind == "instance") {
      _desc.assetId = buffer_read(_buf, buffer_string);
      var _bits = buffer_read(_buf, buffer_u8);
      _desc.shadows = { cast: (_bits & 1) != 0, receive: (_bits & 2) != 0 };
      if (_ver >= 2 && buffer_read(_buf, buffer_u8) == 1) {
        var _node_physics_text = buffer_read(_buf, buffer_string);
        var _node_physics_data = json_parse(_node_physics_text);
        if (is_struct(_node_physics_data)) _desc.physics = _node_physics_data;
      }
    } else if (_kind == "light") {
      var _lt = buffer_read(_buf, buffer_u8);
      var _col = __poly_bin_r_col(_buf);
      var _inten = buffer_read(_buf, buffer_f32);
      var _range = buffer_read(_buf, buffer_f32);
      var _inner = buffer_read(_buf, buffer_f32);
      var _outer = buffer_read(_buf, buffer_f32);
      var _flags = buffer_read(_buf, buffer_u8);
      var _res = buffer_read(_buf, buffer_u16);
      var _dist = buffer_read(_buf, buffer_f32);
      var _nrm = buffer_read(_buf, buffer_f32);
      _desc.light = {
        type: _lt == 1 ? "point" : (_lt == 2 ? "spot" : "directional"),
        color: _col, intensity: _inten, range: _range, innerCone: _inner, outerCone: _outer,
        enabled: (_flags & 1) != 0,
        shadow: { enabled: (_flags & 2) != 0, resolution: _res, distance: _dist, normalOffset: _nrm },
      };
    } else if (_kind == "camera") {
      var _proj = buffer_read(_buf, buffer_u8);
      _desc.camera = {
        projection: _proj == 1 ? "ortho" : "perspective",
        fovY: buffer_read(_buf, buffer_f32), orthoWidth: buffer_read(_buf, buffer_f32),
        orthoHeight: buffer_read(_buf, buffer_f32), near: buffer_read(_buf, buffer_f32),
        far: buffer_read(_buf, buffer_f32), enabled: buffer_read(_buf, buffer_u8) != 0,
      };
    } else {
      var _size = [ buffer_read(_buf, buffer_f32), buffer_read(_buf, buffer_f32), buffer_read(_buf, buffer_f32) ];
      var _amb = __poly_bin_r_col(_buf);
      var _fog = buffer_read(_buf, buffer_u8) != 0;
      var _fogc = __poly_bin_r_col(_buf);
      _desc.environment = {
        size: _size, ambient: _amb, fogEnabled: _fog, fogColor: _fogc,
        fogStart: buffer_read(_buf, buffer_f32), fogEnd: buffer_read(_buf, buffer_f32),
        enabled: buffer_read(_buf, buffer_u8) != 0,
      };
    }

    array_push(_nodes, _desc);
  }

  _out = { seq: _seq, assets: _assets, nodes: _nodes, world: _world };

  buffer_delete(_buf);
  return _out;
}
