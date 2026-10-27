// poly_imgui_insp_sections - per-kind sections (light, camera, env, asset, spawn).

// ---------------------------------------------------------------------------
// Generic edit wrappers (snap, mutate, apply, commit)
// ---------------------------------------------------------------------------

// Generic field edit: snapshots undo, assigns, applies, commits.
// Thin wrappers below delegate here so undo/apply stay in one place.
// _undo=false skips history (live color edits: history is grouped inside
// __poly_imgui_color_edit via col_gest, the caller marks dirty itself).
function __poly_edit_field(_ed, _node, _data, _field, _apply, _newval, _undo = true) {
  var _before = undefined;

  if (_undo) _before = __poly_history_snap(_ed);
  _data[$ _field] = _newval;
  _apply(_node, _data);

  if (_undo && _before != undefined) __poly_history_commit(_ed, _before);
}

// Edits a bool field with undo.
function __poly_edit_bool(_ed, _node, _data, _field, _label, _apply) {
  var _nv = ImGui.Checkbox(_label, _data[$ _field] == true);

  if (_nv != (_data[$ _field] == true)) __poly_edit_field(_ed, _node, _data, _field, _apply, _nv);
}

// Edits a float field with undo and optional clamping.
function __poly_edit_float(_ed, _node, _data, _id, _label, _field, _apply, _min = undefined, _max = undefined) {
  var _nv = __poly_imgui_prop_float(_ed, _id, _label, _data[$ _field], 120);

  if (_nv == undefined) return;
  var _v = _nv;

  if (_min != undefined) _v = max(_v, _min);
  if (_max != undefined) _v = min(_v, _max);
  __poly_edit_field(_ed, _node, _data, _field, _apply, _v);
}

// Edits a radio option with undo. Returns true when picked.
function __poly_edit_radio(_ed, _node, _data, _field, _value, _label, _apply) {
  if (!ImGui.RadioButton(_label, _data[$ _field] == _value)) return false;
  __poly_edit_field(_ed, _node, _data, _field, _apply, _value);
  return true;
}

// Edits an rgb color field live (no undo here, marks dirty).
// History grouping stays inside __poly_imgui_color_edit (col_gest).
function __poly_edit_color(_ed, _node, _data, _id, _label, _field, _apply) {
  var _cur = _data[$ _field];
  var _nv = __poly_imgui_color_edit(_ed, _id, _label, make_colour_rgb(_cur[0], _cur[1], _cur[2]));

  if (_nv == undefined) return;
  __poly_edit_field(_ed, _node, _data, _field, _apply, [ colour_get_red(_nv), colour_get_green(_nv), colour_get_blue(_nv) ], false);
  _ed.dirty = true;
}

// ---------------------------------------------------------------------------
// Asset and light sections
// ---------------------------------------------------------------------------

// Edits asset shadow flags in Inspector.
function __poly_imgui_asset_sec(_ed, _node, _en) {
  var _d = _en.data;
  ImGui.Spacing();
  __poly_edit_bool(_ed, _node, _d, "castShadows", "Cast", __poly_flags_apply_data);
  if (ImGui.IsItemHovered()) ImGui.SetTooltip("Controls whether this object casts shadows onto other surfaces.");
  ImGui.SameLine(0, 18);
  __poly_edit_bool(_ed, _node, _d, "receiveShadows", "Receive", __poly_flags_apply_data);
  if (ImGui.IsItemHovered()) ImGui.SetTooltip("Controls whether shadows from other objects appear on this object.");
  ImGui.Spacing();
}

function __poly_physics_ui_change(_ed, _node, _en, _data, _field, _value, _child = "") {
  var _before = __poly_history_snap(_ed);
  if (_child != "") _data[$ _child][$ _field] = _value; else _data[$ _field] = _value;

  if (_field == "mode" && _value == "character" && _child == "") {
    var _model_for_fit = __poly_imgui_node_model(_ed, _node);
    _data = __poly_physics_fit_visual(_model_for_fit, _data);
  }

  _data = __poly_physics_data(_data);
  _en.data.physics = _data;
  __poly_physics_debug_destroy(_ed);
  __poly_physics_apply(_node, _data);
  _ed.rt.scene.update(0.0);
  __poly_physics_debug_rebuild(_ed);
  _ed.view_dirty = true;
  if (_before != undefined) __poly_history_commit(_ed, _before);
}

function __poly_imgui_physics_tip(_text) {
  if (ImGui.IsItemHovered()) ImGui.SetTooltip(_text);
}

function __poly_imgui_physics_float(_ed, _node, _en, _data, _field, _label, _speed, _min, _max, _child = "", _tip = "") {
  var _value = _child != "" ? _data[$ _child][$ _field] : _data[$ _field];
  var _id = "physics_" + _child + "_" + _field;
  var _next = __poly_imgui_prop_float(_ed, _id, _label, _value, 120);
  if (_tip != "") __poly_imgui_physics_tip(_tip);
  if (_next == undefined || _next == _value) return;
  _next = clamp(_next, _min, _max);
  __poly_physics_ui_change(_ed, _node, _en, _data, _field, _next, _child);
}

function __poly_imgui_physics_sec(_ed, _node, _en) {
  if (!_ed.physics_enabled) return;
  if (!is_struct(_en.data)) _en.data = __poly_flags_read(_node);
  if (!variable_struct_exists(_en.data, "physics") || !is_struct(_en.data[$ "physics"])) _en.data.physics = __poly_physics_defaults();
  var _d = __poly_physics_data(_en.data.physics);
  _en.data.physics = _d;
  ImGui.Spacing();
  __poly_imgui_sec_open();
  if (!ImGui.CollapsingHeader("Physics")) return;
  var _enabled = _d.mode != "none";
  var _was_enabled = ImGui.Checkbox("Physical", _enabled);
  __poly_imgui_physics_tip("Enables a collider on this object. Choose a mode below to set its behavior.");

  if (_was_enabled != _enabled) {
    __poly_physics_ui_change(_ed, _node, _en, _d, "mode", _was_enabled ? "static" : "none");
    _d = _en.data.physics;
  }

  if (_d.mode == "none") return;
  var _modes = [ "static", "kinematic", "dynamic", "character" ];
  var _mode_open = ImGui.BeginCombo("Mode", _d.mode);
  __poly_imgui_physics_tip("Static does not move; Kinematic is moved by code; Dynamic is simulated by the game; Character uses a character controller.");

  if (_mode_open) {

    for (var _i = 0; _i < array_length(_modes); _i++) if (ImGui.Selectable(_modes[_i], _d.mode == _modes[_i])) {
      // Mesh shape is only supported on static bodies: switching mode away
      // from static drops Mesh to a primitive shape.
      if (_modes[_i] != "static" && _d.shape == "Mesh") {
        __poly_physics_ui_change(_ed, _node, _en, _d, "shape", "Box");
        _d = _en.data.physics;
      }

      __poly_physics_ui_change(_ed, _node, _en, _d, "mode", _modes[_i]);
      _d = _en.data.physics;
    }

    ImGui.EndCombo();
  }

  var _layers = [ "Static", "Default", "Character", "Trigger", "Debris" ];

  if (_d.mode != "character") {
    var _layer_open = ImGui.BeginCombo("Layer", _d.layer);
    __poly_imgui_physics_tip("Collision layer used with GM3D's collision rules. Trigger selects the trigger layer; Sensor makes the collider overlap-only.");

    if (_layer_open) {

      for (var _l = 0; _l < array_length(_layers); _l++) if (ImGui.Selectable(_layers[_l], _d.layer == _layers[_l])) {
        __poly_physics_ui_change(_ed, _node, _en, _d, "layer", _layers[_l]);
        _d = _en.data.physics;
      }

      ImGui.EndCombo();
    }
  }

  if (_d.mode == "character") {
    __poly_imgui_physics_float(_ed, _node, _en, _d, "radius", "Radius", 0.01, 0.01, 100, "character", "Radius of the character capsule.");
    __poly_imgui_physics_float(_ed, _node, _en, _d, "halfHeight", "Half height", 0.01, 0.01, 100, "character", "Half of the capsule's cylindrical section height; total capsule height also includes both rounded ends.");
    __poly_imgui_physics_float(_ed, _node, _en, _d, "stepHeight", "Step height", 0.01, 0, 20, "character", "Maximum height of a step the controller can climb.");
    __poly_imgui_physics_float(_ed, _node, _en, _d, "maxSlopeAngle", "Max slope", 0.5, 0, 89, "character", "Steepest slope, in degrees, the controller can stand on.");
    var _stg = ImGui.Checkbox("Stick to ground##char", _d.character.stickToGround == true);
    __poly_imgui_physics_tip("Keeps the controller snapped to the ground on small steps and bumps.");

    if (_stg != (_d.character.stickToGround == true)) {
      __poly_physics_ui_change(_ed, _node, _en, _d, "stickToGround", _stg, "character");
      _d = _en.data.physics;
    }

    __poly_imgui_physics_float(_ed, _node, _en, _d, "mass", "Mass", 0.5, 0.001, 100000, "character", "Character controller mass used by GM3D's character movement and contacts.");
    __poly_imgui_physics_float(_ed, _node, _en, _d, "maxStrength", "Max strength", 1, 0.001, 100000, "character", "Maximum force the controller can apply to push other bodies.");

    for (var _a = 0; _a < 3; _a++) {
      var _axes = [ "X", "Y", "Z" ];
      var _nv = __poly_imgui_prop_float(_ed, "physics_visual_" + _axes[_a], "Visual offset " + _axes[_a], _d.character.visualOffset[_a], 120);
      __poly_imgui_physics_tip("Local model offset on the " + _axes[_a] + " axis. The character capsule stays centered on the wrapper origin.");

      if (_nv != undefined && _nv != _d.character.visualOffset[_a]) {
        var _offset = __poly_physics_copy3(_d.character.visualOffset);
        _offset[_a] = _nv;
        __poly_physics_ui_change(_ed, _node, _en, _d, "visualOffset", _offset, "character");
        _d = _en.data.physics;
      }
    }

    if (ImGui.Button("Recenter visual")) {
      var _model = __poly_imgui_node_model(_ed, _node);
      var _bb = _model != undefined ? _model.getBoundingBox() : undefined;
      if (is_struct(_bb) && _bb.min != undefined && _bb.max != undefined) __poly_physics_ui_change(_ed, _node, _en, _d, "visualOffset", [ -(_bb.min.x + _bb.max.x) * 0.5, -(_bb.min.y + _bb.max.y) * 0.5, -(_bb.min.z + _bb.max.z) * 0.5 ], "character");
    }

    if (ImGui.IsItemHovered()) ImGui.SetTooltip("Centers the visual model on the wrapper origin using its bounds. The Character capsule remains centered at the origin; adjust Visual offset to fine-tune.");
    return;
  }

  var _shapes = _d.mode == "static" ? [ "Box", "Sphere", "Capsule", "Cylinder", "Mesh", "ConvexHull" ] : [ "Box", "Sphere", "Capsule", "Cylinder", "ConvexHull" ];
  var _shape_open = ImGui.BeginCombo("Shape", _d.shape);
  __poly_imgui_physics_tip("Collider geometry: Box, Sphere, Capsule, Cylinder, Mesh or ConvexHull. Mesh uses the mesh geometry (static bodies only); ConvexHull uses the convex hull (good for dynamic bodies). Dimensions below are half-extents (ignored for Mesh).");

  if (_shape_open) {

    for (var _s = 0; _s < array_length(_shapes); _s++) if (ImGui.Selectable(_shapes[_s], _d.shape == _shapes[_s])) {
      // Selecting Mesh on a non-static body switches the body to static
      // (Mesh is only supported on static bodies).
      if (_shapes[_s] == "Mesh" && _d.mode != "static") {
        __poly_physics_ui_change(_ed, _node, _en, _d, "mode", "static");
        _d = _en.data.physics;
      }

      __poly_physics_ui_change(_ed, _node, _en, _d, "shape", _shapes[_s]);
      _d = _en.data.physics;
    }

    ImGui.EndCombo();
  }

  if (_d.mode == "dynamic") {
    __poly_imgui_physics_float(_ed, _node, _en, _d, "mass", "Mass", 0.1, 0.001, 100000, "", "Mass of this dynamic body; higher mass makes it harder to accelerate or push.");
    __poly_imgui_physics_float(_ed, _node, _en, _d, "linearDamping", "Linear damping", 0.01, 0, 1000, "", "Slows straight-line motion over time. Zero applies no damping.");
    __poly_imgui_physics_float(_ed, _node, _en, _d, "angularDamping", "Angular damping", 0.01, 0, 1000, "", "Slows rotation over time. Zero applies no damping.");
    __poly_imgui_physics_float(_ed, _node, _en, _d, "gravityFactor", "Gravity factor", 0.1, -100, 100, "", "Scales world gravity for this body: 1 is normal, 0 disables gravity, negative values reverse it.");
  }

  __poly_imgui_physics_float(_ed, _node, _en, _d, "friction", "Friction", 0.01, 0, 1, "", "Surface grip during contact. Higher values resist sliding more.");
  __poly_imgui_physics_float(_ed, _node, _en, _d, "restitution", "Restitution", 0.01, 0, 1, "", "Bounciness during contact: 0 absorbs bounce, 1 is highly elastic.");
  var _sensor = ImGui.Checkbox("Sensor", _d.isSensor == true);
  __poly_imgui_physics_tip("Detects overlaps without physically blocking or pushing other bodies.");
  if (_sensor != (_d.isSensor == true)) __poly_physics_ui_change(_ed, _node, _en, _d, "isSensor", _sensor);
  _d = _en.data.physics;

  // Optional constraint (joint) to another instance.
  ImGui.Spacing();
  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Constraint")) {
    var _ctypes = [ "None", "Fixed", "Point", "Hinge", "Slider", "Cone", "Distance" ];
    var _cur_type = is_struct(_d[$ "constraint"]) ? _d.constraint.type : "None";
    var _ctype_open = ImGui.BeginCombo("Type", _cur_type);
    __poly_imgui_physics_tip("Optional joint to another instance. 'None' disables it. The game creates the constraint from this data after loading.");

    if (_ctype_open) {

      for (var _ci = 0; _ci < array_length(_ctypes); _ci++) if (ImGui.Selectable(_ctypes[_ci], _cur_type == _ctypes[_ci])) {
        var _before = __poly_history_snap(_ed);

        if (_ctypes[_ci] == "None") {
          if (variable_struct_exists(_d, "constraint")) variable_struct_remove(_d, "constraint");
        } else {
          if (!is_struct(_d[$ "constraint"])) _d.constraint = { type: _ctypes[_ci], nodeB: "", pivotA: [ 0, 0, 0 ], pivotB: [ 0, 0, 0 ], axisA: [ 0, 1, 0 ], minLimit: 0, maxLimit: 0, motorEnabled: false, motorVelocity: 0, motorMaxForce: 0 };
          else _d.constraint.type = _ctypes[_ci];
        }

        _d = __poly_physics_data(_d);
        _en.data.physics = _d;
        __poly_physics_debug_destroy(_ed);
        __poly_physics_apply(_node, _d);
        _ed.rt.scene.update(0.0);
        __poly_physics_debug_rebuild(_ed);
        _ed.view_dirty = true;
        if (_before != undefined) __poly_history_commit(_ed, _before);
      }

      ImGui.EndCombo();
    }

    if (is_struct(_d[$ "constraint"])) {
      var _nb_res = __poly_imgui_text("constraint_nodeB", "Target id", _d.constraint.nodeB);
      __poly_imgui_physics_tip("Registry id of the other instance (nodeB).");

      if (_nb_res.was_active && !_nb_res.active) {
        var _nb = string_trim(_nb_res.text);

        if (_nb != _d.constraint.nodeB) {
          var _before = __poly_history_snap(_ed);
          _d.constraint.nodeB = _nb; _d = __poly_physics_data(_d); _en.data.physics = _d;
          if (_before != undefined) __poly_history_commit(_ed, _before);
        }
      }
    }
  }

  // Vehicle (dynamic body only).
  if (_d.mode == "dynamic") {
    __poly_imgui_sec_open();

    if (ImGui.CollapsingHeader("Vehicle")) {
      var _venabled = ImGui.Checkbox("Enable vehicle", is_struct(_d[$ "vehicle"]) && _d.vehicle.enabled == true);
      __poly_imgui_physics_tip("Treats this dynamic body as a wheeled vehicle. The game builds the vehicle from these defaults after loading.");

      if (_venabled != (is_struct(_d[$ "vehicle"]) && _d.vehicle.enabled == true)) {
        var _before = __poly_history_snap(_ed);
        if (!is_struct(_d[$ "vehicle"])) _d.vehicle = { enabled: true, mass: 1325.0, linearDamping: 0.08, angularDamping: 1.05, friction: 0.22, wheelRadius: 0.33, wheelWidth: 0.24, wheelCount: 4, maxSteerAngle: 0.5, maxTorque: 500.0, minRPM: 900.0, maxRPM: 6000.0, shiftUpRPM: 5200.0, shiftDownRPM: 2200.0, finalDriveRatio: 3.4, gearCount: 6, reverseGearRatio: -3.2, clutchStrength: 8.0, automatic: true, antiRollStiffness: 12000.0 };
        _d.vehicle.enabled = _venabled;
        if (!_venabled) variable_struct_remove(_d, "vehicle");
        _d = __poly_physics_data(_d); _en.data.physics = _d;
        _ed.rt.scene.update(0.0); __poly_physics_debug_rebuild(_ed); _ed.view_dirty = true;
        if (_before != undefined) __poly_history_commit(_ed, _before);
      }

      if (is_struct(_d[$ "vehicle"])) {
        var _v = _d.vehicle;
        var _vf = [ [ "mass","Mass",0.001,100000 ],[ "wheelRadius","Wheel radius",0.001,10 ],[ "wheelWidth","Wheel width",0.001,10 ],[ "maxSteerAngle","Max steer",0,3.14 ],[ "maxTorque","Max torque",0,100000 ],[ "maxRPM","Max RPM",1,100000 ],[ "gearCount","Gears",1,12 ],[ "antiRollStiffness","Anti-roll",0,100000 ] ];

        for (var _vi = 0; _vi < array_length(_vf); _vi++) {
          var _f = _vf[_vi];
          var _val = __poly_imgui_prop_float(_ed, "veh_" + _f[0], _f[1] + "##veh_" + _f[0], _v[$ _f[0]], 120);
          __poly_imgui_physics_tip("Vehicle default: " + _f[1] + ".");

          if (_val != undefined && _val != _v[$ _f[0]]) {
            var _before = __poly_history_snap(_ed);
            _v[$ _f[0]] = clamp(_val, _f[2], _f[3]);
            _d.vehicle = _v; _d = __poly_physics_data(_d); _en.data.physics = _d;
            if (_before != undefined) __poly_history_commit(_ed, _before);
          }
        }

        var _auto = ImGui.Checkbox("Automatic", _v.automatic == true);

        if (_auto != (_v.automatic == true)) {
          var _before = __poly_history_snap(_ed);
          _v.automatic = _auto; _d.vehicle = _v; _d = __poly_physics_data(_d); _en.data.physics = _d;
          if (_before != undefined) __poly_history_commit(_ed, _before);
        }
      }
    }
  }

  if (_d.isSensor == true) {
    var _te = ImGui.Checkbox("On enter", _d.triggerEnter == true);
    __poly_imgui_physics_tip("Fires when another body starts overlapping this sensor.");
    if (_te != (_d.triggerEnter == true)) __poly_physics_ui_change(_ed, _node, _en, _d, "triggerEnter", _te);
    _d = _en.data.physics;
    var _ts = ImGui.Checkbox("On stay", _d.triggerStay == true);
    __poly_imgui_physics_tip("Fires every step while another body overlaps this sensor.");
    if (_ts != (_d.triggerStay == true)) __poly_physics_ui_change(_ed, _node, _en, _d, "triggerStay", _ts);
    _d = _en.data.physics;
    var _tx = ImGui.Checkbox("On exit", _d.triggerExit == true);
    __poly_imgui_physics_tip("Fires when another body stops overlapping this sensor.");
    if (_tx != (_d.triggerExit == true)) __poly_physics_ui_change(_ed, _node, _en, _d, "triggerExit", _tx);
    _d = _en.data.physics;
  }

  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Collider size")) {
    var _labels = [ "X", "Y", "Z" ];

    for (var _v = 0; _v < 3; _v++) {
      var _half = __poly_imgui_prop_float(_ed, "physics_extent_" + _labels[_v], "Half extent " + _labels[_v], _d.halfExtents[_v], 120);
      __poly_imgui_physics_tip("Half-size of the collider on the " + _labels[_v] + " axis; full size is twice this value.");

      if (_half != undefined && _half != _d.halfExtents[_v]) {
        var _he = __poly_physics_copy3(_d.halfExtents); _he[_v] = max(0.001, _half);
        __poly_physics_ui_change(_ed, _node, _en, _d, "halfExtents", _he);
        _d = _en.data.physics;
      }

      var _off = __poly_imgui_prop_float(_ed, "physics_offset_" + _labels[_v], "Offset " + _labels[_v], _d.offset[_v], 120);
      __poly_imgui_physics_tip("Local collider offset on the " + _labels[_v] + " axis, relative to the wrapper origin.");

      if (_off != undefined && _off != _d.offset[_v]) {
        var _of = __poly_physics_copy3(_d.offset); _of[_v] = _off;
        __poly_physics_ui_change(_ed, _node, _en, _d, "offset", _of);
        _d = _en.data.physics;
      }
    }

    if (ImGui.Button("Fit to mesh")) {
      var _model = __poly_imgui_node_model(_ed, _node);
      var _box = _model != undefined ? _model.getBoundingBox() : undefined;
      if (is_struct(_box) && _box.min != undefined && _box.max != undefined) __poly_physics_ui_change(_ed, _node, _en, _d, "halfExtents", [ max(0.001, abs(_box.max.x - _box.min.x) * 0.5), max(0.001, abs(_box.max.y - _box.min.y) * 0.5), max(0.001, abs(_box.max.z - _box.min.z) * 0.5) ]);
    }

    __poly_imgui_physics_tip("Sets collider half-extents from the model's bounding box. You can adjust them afterward.");
  }
}

// Applies one physics field to every selected instance with a single undo
// entry (multi-selection Inspector: common Mode / Layer / Mass).
function __poly_physics_multi_apply(_ed, _nodes, _field, _value) {
  var _before = __poly_history_snap(_ed);
  __poly_physics_debug_destroy(_ed);

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _node = _nodes[_i];

    if (__poly_kind_of(_ed, _node) != "instance") continue;
    var _en = __poly_registry_find(_ed, _node);

    if (_en == undefined) continue;
    if (!is_struct(_en.data)) _en.data = __poly_flags_read(_node);
    var _d = __poly_physics_data(_en.data[$ "physics"]);
    var _old_mode = _d.mode;

    _d[$ _field] = _value;
    if (_field == "mode" && _value == "character" && _old_mode != "character") _d = __poly_physics_fit_visual(__poly_imgui_node_model(_ed, _node), _d);
    if (_field == "mode" && _value != "static" && _d.shape == "Mesh") _d.shape = "Box";
    _d = __poly_physics_data(_d);
    _en.data.physics = _d;
    __poly_physics_apply(_node, _d);
  }

  _ed.rt.scene.update(0.0);
  __poly_physics_debug_rebuild(_ed);
  _ed.view_dirty = true;
  if (_before != undefined) __poly_history_commit(_ed, _before);
}

// Draws the common physics fields for a multi-selection. Values that differ
// across the selection show as "Mixed"; editing them applies to every
// selected instance.
function __poly_imgui_physics_multi_sec(_ed, _nodes) {
  if (!_ed.physics_enabled) return;
  var _count = 0;
  var _mode = undefined;
  var _layer = undefined;
  var _mass = undefined;
  var _mixed_mode = false;
  var _mixed_layer = false;
  var _mixed_mass = false;

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    if (__poly_kind_of(_ed, _nodes[_i]) != "instance") continue;
    var _en = __poly_registry_find(_ed, _nodes[_i]);

    if (_en == undefined) continue;
    var _d = __poly_physics_data(is_struct(_en.data) ? _en.data[$ "physics"] : undefined);

    if (_count == 0) {
      _mode = _d.mode;
      _layer = _d.layer;
      _mass = _d.mass;
    } else {
      if (_d.mode != _mode) _mixed_mode = true;
      if (_d.layer != _layer) _mixed_layer = true;
      if (abs(_d.mass - _mass) > 0.00001) _mixed_mass = true;
    }

    _count++;
  }

  if (_count < 2) return;
  ImGui.Spacing();
  __poly_imgui_sec_open();
  if (!ImGui.CollapsingHeader("Physics")) return;
  var _modes = [ "none", "static", "kinematic", "dynamic", "character" ];
  var _mode_txt = _mixed_mode ? "Mixed" : _mode;
  var _mode_open = ImGui.BeginCombo("Mode", _mode_txt);
  __poly_imgui_physics_tip("Applies the same physics mode to every selected instance.");

  if (_mode_open) {
    for (var _m = 0; _m < array_length(_modes); _m++) if (ImGui.Selectable(_modes[_m], !_mixed_mode && _mode == _modes[_m])) __poly_physics_multi_apply(_ed, _nodes, "mode", _modes[_m]);
    ImGui.EndCombo();
  }

  var _layers = [ "Static", "Default", "Character", "Trigger", "Debris" ];
  var _layer_txt = _mixed_layer ? "Mixed" : _layer;
  var _layer_open = ImGui.BeginCombo("Layer", _layer_txt);
  __poly_imgui_physics_tip("Applies the same collision layer to every selected non-character instance.");

  if (_layer_open) {
    for (var _l = 0; _l < array_length(_layers); _l++) if (ImGui.Selectable(_layers[_l], !_mixed_layer && _layer == _layers[_l])) __poly_physics_multi_apply(_ed, _nodes, "layer", _layers[_l]);
    ImGui.EndCombo();
  }

  var _mass_value = _mixed_mass ? 1.0 : _mass;
  var _mass_next = __poly_imgui_prop_float(_ed, "physics_multi_mass", "Mass", _mass_value, 120);
  __poly_imgui_physics_tip("Applies the same mass to every selected instance. It only affects dynamic bodies.");
  if (_mass_next != undefined && (_mixed_mass || abs(_mass_next - _mass) > 0.00001)) __poly_physics_multi_apply(_ed, _nodes, "mass", max(0.001, _mass_next));
}

function __poly_world_ui_change(_ed, _field, _value, _axis = -1) {
  var _before = __poly_history_snap(_ed);
  var _d = __poly_world_data(_ed.world);
  if (_axis >= 0) _d.gravity[_axis] = _value; else _d[$ _field] = _value;
  _ed.world = __poly_world_data(_d);
  __poly_physics_debug_rebuild(_ed);
  _ed.view_dirty = true;
  if (_before != undefined) __poly_history_commit(_ed, _before);
}

function __poly_imgui_world_sec(_ed) {
  if (!is_struct(_ed.world)) _ed.world = __poly_world_defaults();
  var _d = __poly_world_data(_ed.world);
  ImGui.Spacing();
  __poly_imgui_sec_open();
  if (!ImGui.CollapsingHeader("Physics World")) return;
  var _pe = ImGui.Checkbox("Enable Physics", _ed.physics_enabled == true);
  __poly_imgui_physics_tip("Master switch for the physics editor: shows Physics World settings and per-object Physics sections.");

  if (_pe != (_ed.physics_enabled == true)) {
    __poly_world_ui_change(_ed, "enabled", _pe);
    _ed.physics_enabled = _pe;
  }

  if (!_ed.physics_enabled) return;
  var _axis = [ "X", "Y", "Z" ];

  for (var _i = 0; _i < 3; _i++) {
    var _nv = __poly_imgui_prop_float(_ed, "world_gravity_" + _axis[_i], "Gravity " + _axis[_i], _d.gravity[_i], 120);
    __poly_imgui_physics_tip("World gravity acceleration on the " + _axis[_i] + " axis, in scene units per second squared.");

    if (_nv != undefined && _nv != _d.gravity[_i]) { __poly_world_ui_change(_ed, "gravity", _nv, _i); _d = _ed.world; }
  }

  var _step = __poly_imgui_prop_float(_ed, "world_step", "Fixed time step", _d.fixedTimeStep, 120);
  __poly_imgui_physics_tip("Time interval used by each physics simulation step. The game controls when the world is stepped.");
  if (_step != undefined && _step != _d.fixedTimeStep) __poly_world_ui_change(_ed, "fixedTimeStep", clamp(_step, 0.001, 1));
  var _sub = __poly_imgui_prop_float(_ed, "world_substeps", "Max substeps", _d.maxSubSteps, 120);
  __poly_imgui_physics_tip("Maximum catch-up steps the game world may run for one update.");
  if (_sub != undefined && _sub != _d.maxSubSteps) __poly_world_ui_change(_ed, "maxSubSteps", clamp(round(_sub), 1, 64));
  var _bodies = __poly_imgui_prop_float(_ed, "world_bodies", "Max bodies", _d.maxBodies, 120);
  __poly_imgui_physics_tip("Capacity reserved for physics bodies in the game world.");
  if (_bodies != undefined && _bodies != _d.maxBodies) __poly_world_ui_change(_ed, "maxBodies", clamp(round(_bodies), 1, 65535));
  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Layer collision")) {
    var _lnames = [ "St", "Df", "Ch", "Tr", "Db" ];
    var _full = [ "Static", "Default", "Character", "Trigger", "Debris" ];
    ImGui.TextDisabled("Uncheck a cell to disable collision");
    ImGui.TextDisabled("between two layers.");
    // header row
    ImGui.Text("   ");

    for (var _j = 0; _j < 5; _j++) { ImGui.SameLine(30 + _j * 26); ImGui.Text(_lnames[_j]); if (ImGui.IsItemHovered()) ImGui.SetTooltip(_full[_j]); }

    for (var _i = 0; _i < 5; _i++) {
      ImGui.Text(_lnames[_i]); if (ImGui.IsItemHovered()) ImGui.SetTooltip(_full[_i]);

      for (var _j = 0; _j < 5; _j++) {
        ImGui.SameLine(30 + _j * 26);
        var _val = _d.layerCollision[_i][_j] == true;
        var _nv = ImGui.Checkbox("##lc_" + string(_i) + "_" + string(_j), _val);

        if (_nv != _val) {
          var _before = __poly_history_snap(_ed);
          _d.layerCollision[_i][_j] = _nv;
          _ed.world = __poly_world_data(_d);
          _ed.view_dirty = true;
          if (_before != undefined) __poly_history_commit(_ed, _before);
        }
      }
    }
  }
}

// Edits light properties in Inspector.
function __poly_imgui_light_sec(_ed, _node, _en) {
  var _d = _en.data;

  if (__poly_edit_radio(_ed, _node, _d, "type", "directional", "Directional", __poly_light_apply)) __poly_sel_apply_tool(_ed);

  if (__poly_edit_radio(_ed, _node, _d, "type", "point", "Point", __poly_light_apply)) {
    if (_d.range < 0.5) {
      _d.range = 50.0;
      __poly_light_apply(_node, _d);
    }

    __poly_sel_apply_tool(_ed);
  }

  __poly_edit_bool(_ed, _node, _d, "enabled", "Enabled", __poly_light_apply);
  __poly_edit_float(_ed, _node, _d, "light_int", "Intensity", "intensity", __poly_light_apply, 0);
  __poly_edit_color(_ed, _node, _d, "light_col", "Color", "color", __poly_light_apply);

  if (_d.type != "directional") __poly_edit_float(_ed, _node, _d, "light_range", "Range", "range", __poly_light_apply, 0.01);

  if (_d.type == "spot") {
    __poly_edit_float(_ed, _node, _d, "light_inner", "Inner cone", "inner", __poly_light_apply, 0, 89);
    __poly_edit_float(_ed, _node, _d, "light_outer", "Outer cone", "outer", __poly_light_apply, 1, 89);
  }
}

// Notes when another light owns the single shadow map. Returns true when drawn.
function __poly_shadow_owner_note(_ed, _node) {
  var _owner = __poly_shadow_owner(_ed, _node);

  if (_owner == undefined) return false;
  ImGui.TextDisabled("Shadow maps already enabled on light:");
  ImGui.TextDisabled("\"" + __poly_node_display(_ed, _owner) + "\"");
  ImGui.SameLine();

  if (ImGui.SmallButton("Select")) __poly_sel_assign(_ed, [ _owner ]);
  return true;
}

// Edits light shadow properties in Inspector.
function __poly_imgui_light_shadow_sec(_ed, _node, _en) {
  var _d = _en.data;

  if (_d.shadow != true && __poly_shadow_owner_note(_ed, _node)) return;
  __poly_edit_bool(_ed, _node, _d, "shadow", "Cast shadows", __poly_light_apply);

  if (_d.shadow == true) {
    __poly_edit_shadow_float(_ed, _node, _d, "light_shadow_res", "Resolution", "shadowRes");
    __poly_edit_float(_ed, _node, _d, "light_shadow_dist", "Distance", "shadowDist", __poly_light_apply, 1);
    __poly_edit_float(_ed, _node, _d, "light_shadow_normal", "Normal bias", "shadowNormal", __poly_light_apply, 0, 1);
  }
}

// Edits shadow resolution (snapped to accepted powers of two) with undo.
function __poly_edit_shadow_float(_ed, _node, _d, _id, _label, _field) {
  var _nv = __poly_imgui_prop_float(_ed, _id, _label, _d[$ _field], 120);

  if (_nv == undefined) return;
  __poly_edit_field(_ed, _node, _d, _field, __poly_light_apply, __poly_shadow_res_snap(_nv));
}

// ---------------------------------------------------------------------------
// Camera and environment sections
// ---------------------------------------------------------------------------

// Edits camera properties in Inspector.
function __poly_imgui_camera_sec(_ed, _node, _en) {
  var _d = _en.data;

  __poly_edit_radio(_ed, _node, _d, "projection", "perspective", "Perspective", __poly_camera_apply);
  __poly_edit_radio(_ed, _node, _d, "projection", "ortho", "Ortho", __poly_camera_apply);
  __poly_edit_bool(_ed, _node, _d, "enabled", "Enabled", __poly_camera_apply);

  if (_d.projection == "ortho") {
    __poly_edit_float(_ed, _node, _d, "cam_ow", "Ortho width", "ow", __poly_camera_apply, 0.01);
    __poly_edit_float(_ed, _node, _d, "cam_oh", "Ortho height", "oh", __poly_camera_apply, 0.01);
  } else {
    __poly_edit_float(_ed, _node, _d, "cam_fov", "Fov", "fov", __poly_camera_apply, 1, 179);
  }

  __poly_edit_float(_ed, _node, _d, "cam_near", "Near", "near", __poly_camera_apply, 0.01);
  __poly_edit_cam_far(_ed, _node, _d);
  __poly_cameras_mute(_ed);
}

// Edits a float clamped above a sibling field (+0.01) with undo.
function __poly_edit_float_above(_ed, _node, _d, _id, _label, _field, _apply, _ref) {
  var _nv = __poly_imgui_prop_float(_ed, _id, _label, _d[$ _field], 120);

  if (_nv == undefined) return;
  __poly_edit_field(_ed, _node, _d, _field, _apply, max(_nv, _d[$ _ref] + 0.01));
}

// Edits camera far plane (clamped above near) with undo.
function __poly_edit_cam_far(_ed, _node, _d) {
  __poly_edit_float_above(_ed, _node, _d, "cam_far", "Far", "far", __poly_camera_apply, "near");
}

// Edits the environment size vector with undo.
function __poly_edit_env_size(_ed, _node, _d) {
  ImGui.Text("Size");
  var _size = [ _d.size[0], _d.size[1], _d.size[2] ];
  var _axes = [ "X", "Y", "Z" ];
  var _changed = false;

  for (var _a = 0; _a < 3; _a++) {
    if (_a == 0) {
      ImGui.SameLine(80);
    } else {
      ImGui.SameLine();
    }

    var _nv = __poly_imgui_prop_float(_ed, "env_size" + _axes[_a], "##envsize" + _axes[_a], _size[_a], 46);

    if (_nv != undefined) {
      _size[_a] = max(_nv, 0.01);
      _changed = true;
    }
  }

  if (_changed) __poly_edit_field(_ed, _node, _d, "size", __poly_env_apply, _size);
}

// Edits environment properties in Inspector.
function __poly_imgui_env_sec(_ed, _node, _en) {
  var _d = _en.data;
  __poly_edit_bool(_ed, _node, _d, "enabled", "Enabled", __poly_env_apply);
  __poly_edit_env_size(_ed, _node, _d);
  __poly_edit_color(_ed, _node, _d, "env_amb", "Ambient", "ambient", __poly_env_apply);
  __poly_edit_bool(_ed, _node, _d, "fog", "Fog", __poly_env_apply);

  if (_d.fog == true) {
    __poly_edit_color(_ed, _node, _d, "env_fogc", "Fog color", "fogcolor", __poly_env_apply);
    __poly_edit_float(_ed, _node, _d, "env_fogs", "Fog start", "fogstart", __poly_env_apply);
    __poly_edit_env_fog_end(_ed, _node, _d);
  }
}

// Edits environment fog end (clamped above fog start) with undo.
function __poly_edit_env_fog_end(_ed, _node, _d) {
  __poly_edit_float_above(_ed, _node, _d, "env_foge", "Fog end", "fogend", __poly_env_apply, "fogstart");
}

// ---------------------------------------------------------------------------
// Spawn defaults section
// ---------------------------------------------------------------------------

// Draws one spawn transform row (rotation or scale), returning drag-busy.
function __poly_spawn_mode_row(_ui, _t, _mode) {
  var _names = [ "X", "Y", "Z" ];
  var _arr = _mode == 0 ? _t.rot : _t.sca;
  var _speed = _mode == 0 ? 0.1 : 0.01;
  var _title = _mode == 0 ? "Rotation" : "Scale";
  var _busy = false;
  ImGui.PushID(_mode);
  ImGui.AlignTextToFramePadding();
  ImGui.Text(_title);

  for (var _ax = 0; _ax < 3; _ax++) {
    if (_ax == 0) {
      ImGui.SameLine(80);
    } else {
      ImGui.SameLine();
    }

    ImGui.SetNextItemWidth(46);
    var _key = "sp" + string(_mode) + "_" + _names[_ax];
    var _was = _ui.active[$ _key] == true;
    var _input = _arr[_ax];

    if (_was && variable_struct_exists(_ui.draft, _key) && is_real(_ui.draft[$ _key])) _input = _ui.draft[$ _key];
    var _nv = __poly_imgui_dragfloat(_names[_ax], _input, _speed);
    var _now = ImGui.IsItemActive();
    _ui.active[$ _key] = _now;
    _busy = _busy || _now;

    if (_now) {
      _ui.draft[$ _key] = _nv;
    } else {
      if (variable_struct_exists(_ui.draft, _key)) variable_struct_remove(_ui.draft, _key);
      if (_was && _nv != _arr[_ax]) _arr[_ax] = _mode == 1 ? max(_nv, 0.01) : _nv;
    }

    if (_ax < 2) {
      ImGui.SameLine();
      ImGui.Dummy(2, 0);
    }
  }

  ImGui.PopID();
  return _busy;
}

// Re-queues the thumbnail when spawn rotation changed (not while dragging).
function __poly_spawn_thumb_sync(_ed, _entry, _t, _busy) {
  if (_busy) return;
  var _known = _entry[$ "thumb_rot"];

  if (is_array(_known) && _known[0] == _t.rot[0] && _known[1] == _t.rot[1] && _known[2] == _t.rot[2]) return;
  _entry.thumb_rot = [ _t.rot[0], _t.rot[1], _t.rot[2] ];

  if (is_array(_ed.thumb_queue) && !array_contains(_ed.thumb_queue, _entry)) array_push(_ed.thumb_queue, _entry);
}

// Draws default spawn transform and shadows for a library asset.
function __poly_imgui_spawn_sec(_ed, _entry) {
  var _t = __poly_spawn_t(_entry);
  var _sh = __poly_spawn_shadow(_entry);

  if (_t == undefined || _sh == undefined) return;

  if (!variable_struct_exists(_entry, "spawn_ui") || !is_struct(_entry.spawn_ui)) {
    _entry.spawn_ui = { active: {}, draft: {} };
  }

  var _thumb = variable_struct_exists(_entry, "thumb") && sprite_exists(_entry.thumb) ? _entry.thumb : -1;
  __poly_imgui_inspector_asset_header(__poly_display_from_key(_entry.key), "Prefab", _thumb, 96);

  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Transform")) {
    var _busy = __poly_spawn_mode_row(_entry.spawn_ui, _t, 0) || __poly_spawn_mode_row(_entry.spawn_ui, _t, 1);
    __poly_spawn_thumb_sync(_ed, _entry, _t, _busy);
  }

  ImGui.Spacing();
  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Shadows")) {
    ImGui.Spacing();
    __poly_edit_spawn_shadow(_entry, "cast", "Cast");
    ImGui.SameLine(0, 18);
    __poly_edit_spawn_shadow(_entry, "recv", "Receive");
    ImGui.Spacing();
  }

  ImGui.Spacing();
  __poly_imgui_sec_open();
  if (ImGui.CollapsingHeader("Physics Defaults")) __poly_imgui_prefab_physics(_ed, _entry);

  ImGui.Spacing();
  __poly_imgui_sec_open();

  var _asset_mats = __poly_collect_asset_mats(_entry);

  if (__poly_imgui_section_meta("Materials", __poly_imgui_mat_slot_meta(_asset_mats))) __poly_imgui_mat_rows(_ed, _asset_mats);
  var _clips = __poly_imgui_anim_count(_entry.model);

  if (_clips > 0) {
    ImGui.Spacing();
    __poly_imgui_sec_open();

    if (__poly_imgui_section_meta("Animations", string(_clips) + " clips")) __poly_imgui_prefab_anim_sec(_ed, _entry);
  }

  ImGui.Spacing();
  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Actor")) {
    ImGui.Spacing();
    __poly_imgui_actor_sec(_ed, _entry);
    ImGui.Spacing();
  }
}

function __poly_imgui_prefab_physics(_ed, _entry) {
  if (!_ed.physics_enabled) return;
  if (!is_struct(_ed.asset_meta)) _ed.asset_meta = {};
  var _meta = variable_struct_exists(_ed.asset_meta, _entry.key) ? _ed.asset_meta[$ _entry.key] : undefined;
  if (!is_struct(_entry[$ "physics_default"])) _entry.physics_default = is_struct(_meta) && is_struct(_meta[$ "physics"]) ? __poly_physics_data(_meta.physics) : __poly_physics_defaults();
  var _d = __poly_physics_data(_entry.physics_default);
  var _enabled = _d.mode != "none";
  var _next = ImGui.Checkbox("Physical", _enabled);
  __poly_imgui_physics_tip("Applies these physics defaults to newly spawned instances of this prefab.");

  if (_next != _enabled) {
    var _before = __poly_history_snap(_ed);
    _d.mode = _next ? "static" : "none";
    _entry.physics_default = _d;
    if (!is_struct(_meta)) _meta = { type: "model" };
    _meta.physics = _d;
    _ed.asset_meta[$ _entry.key] = _meta;
    if (_before != undefined) __poly_history_commit(_ed, _before);
  }

  if (_d.mode == "none") return;
  var _modes = [ "static", "kinematic", "dynamic", "character" ];
  var _prefab_mode_open = ImGui.BeginCombo("Mode", _d.mode);
  __poly_imgui_physics_tip("Default behavior for new instances: fixed, code-driven, simulated, or character-controlled.");

  if (_prefab_mode_open) {

    for (var _i = 0; _i < array_length(_modes); _i++) if (ImGui.Selectable(_modes[_i], _d.mode == _modes[_i])) {
      var _before = __poly_history_snap(_ed);
      if (_modes[_i] != "static" && _d.shape == "Mesh") _d.shape = "Box";
      _d.mode = _modes[_i];
      if (_d.mode == "character") _d = __poly_physics_fit_visual(_entry.model, _d);
      _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }

    ImGui.EndCombo();
  }

  var _shapes = _d.mode == "static" ? [ "Box", "Sphere", "Capsule", "Cylinder", "Mesh", "ConvexHull" ] : [ "Box", "Sphere", "Capsule", "Cylinder", "ConvexHull" ];

  if (_d.mode != "character") {
    var _prefab_shape_open = ImGui.BeginCombo("Shape", _d.shape);
    __poly_imgui_physics_tip("Default collider geometry for new instances. Mesh is for static bodies only.");

    if (_prefab_shape_open) {

      for (var _s = 0; _s < array_length(_shapes); _s++) if (ImGui.Selectable(_shapes[_s], _d.shape == _shapes[_s])) {
        var _before = __poly_history_snap(_ed);
        if (_shapes[_s] == "Mesh" && _d.mode != "static") _d.mode = "static";
        _d.shape = _shapes[_s]; _entry.physics_default = _d;
        if (!is_struct(_meta)) _meta = { type: "model" };
        _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
        if (_before != undefined) __poly_history_commit(_ed, _before);
      }

      ImGui.EndCombo();
    }
  }

  if (_d.mode == "dynamic") {
    var _mass = __poly_imgui_prop_float(_ed, "prefab_physics_mass", "Mass", _d.mass, 120);
    __poly_imgui_physics_tip("Default mass assigned to each newly spawned dynamic instance.");

    if (_mass != undefined && _mass != _d.mass) {
      var _before = __poly_history_snap(_ed);
      _d.mass = max(0.001, _mass); _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }
  }

  // Extended defaults: layer, damping, friction, restitution, gravity, sensor, extents, offset.
  var _layers = [ "Static", "Default", "Character", "Trigger", "Debris" ];

  if (_d.mode != "character") {
    var _layer_open = ImGui.BeginCombo("Layer##prefab", _d.layer);
    __poly_imgui_physics_tip("Default collision layer for newly spawned instances.");

    if (_layer_open) {

      for (var _l = 0; _l < array_length(_layers); _l++) if (ImGui.Selectable(_layers[_l], _d.layer == _layers[_l])) {
        var _before = __poly_history_snap(_ed);
        _d.layer = _layers[_l]; _entry.physics_default = _d;
        if (!is_struct(_meta)) _meta = { type: "model" };
        _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
        if (_before != undefined) __poly_history_commit(_ed, _before);
      }

      ImGui.EndCombo();
    }
  }

  if (_d.mode == "dynamic") {
    var _ld = __poly_imgui_prop_float(_ed, "prefab_physics_ld", "Linear damping", _d.linearDamping, 120);
    __poly_imgui_physics_tip("Default linear damping for newly spawned dynamic instances.");

    if (_ld != undefined && _ld != _d.linearDamping) {
      var _before = __poly_history_snap(_ed);
      _d.linearDamping = max(0.0, _ld); _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }

    var _ad = __poly_imgui_prop_float(_ed, "prefab_physics_ad", "Angular damping", _d.angularDamping, 120);
    __poly_imgui_physics_tip("Default angular damping for newly spawned dynamic instances.");

    if (_ad != undefined && _ad != _d.angularDamping) {
      var _before = __poly_history_snap(_ed);
      _d.angularDamping = max(0.0, _ad); _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }

    var _gf = __poly_imgui_prop_float(_ed, "prefab_physics_gf", "Gravity factor", _d.gravityFactor, 120);
    __poly_imgui_physics_tip("Default gravity scale for newly spawned dynamic instances.");

    if (_gf != undefined && _gf != _d.gravityFactor) {
      var _before = __poly_history_snap(_ed);
      _d.gravityFactor = _gf; _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }
  }

  var _fr = __poly_imgui_prop_float(_ed, "prefab_physics_fr", "Friction", _d.friction, 120);
  __poly_imgui_physics_tip("Default surface friction for newly spawned instances.");

  if (_fr != undefined && _fr != _d.friction) {
    var _before = __poly_history_snap(_ed);
    _d.friction = clamp(_fr, 0.0, 1.0); _entry.physics_default = _d;
    if (!is_struct(_meta)) _meta = { type: "model" };
    _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
    if (_before != undefined) __poly_history_commit(_ed, _before);
  }

  var _re = __poly_imgui_prop_float(_ed, "prefab_physics_re", "Restitution", _d.restitution, 120);
  __poly_imgui_physics_tip("Default bounciness for newly spawned instances.");

  if (_re != undefined && _re != _d.restitution) {
    var _before = __poly_history_snap(_ed);
    _d.restitution = clamp(_re, 0.0, 1.0); _entry.physics_default = _d;
    if (!is_struct(_meta)) _meta = { type: "model" };
    _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
    if (_before != undefined) __poly_history_commit(_ed, _before);
  }

  var _sensor = ImGui.Checkbox("Sensor##prefab", _d.isSensor == true);
  __poly_imgui_physics_tip("Default overlap-only (no physical blocking) for newly spawned instances.");

  if (_sensor != (_d.isSensor == true)) {
    var _before = __poly_history_snap(_ed);
    _d.isSensor = _sensor; _entry.physics_default = _d;
    if (!is_struct(_meta)) _meta = { type: "model" };
    _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
    if (_before != undefined) __poly_history_commit(_ed, _before);
  }

  _d = __poly_physics_data(_entry.physics_default);
  var _labels = [ "X", "Y", "Z" ];

  for (var _v = 0; _v < 3; _v++) {
    var _half = __poly_imgui_prop_float(_ed, "prefab_physics_extent_" + _labels[_v], "Half extent " + _labels[_v], _d.halfExtents[_v], 120);
    __poly_imgui_physics_tip("Default half-size on the " + _labels[_v] + " axis.");

    if (_half != undefined && _half != _d.halfExtents[_v]) {
      var _before = __poly_history_snap(_ed);
      var _he = __poly_physics_copy3(_d.halfExtents); _he[_v] = max(0.001, _half);
      _d.halfExtents = _he; _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }

    var _off = __poly_imgui_prop_float(_ed, "prefab_physics_offset_" + _labels[_v], "Offset " + _labels[_v], _d.offset[_v], 120);
    __poly_imgui_physics_tip("Default collider offset on the " + _labels[_v] + " axis.");

    if (_off != undefined && _off != _d.offset[_v]) {
      var _before = __poly_history_snap(_ed);
      var _of = __poly_physics_copy3(_d.offset); _of[_v] = _off;
      _d.offset = _of; _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }
  }

  // Trigger events (when sensor).
  if (_d.isSensor == true) {
    var _te = ImGui.Checkbox("On enter##prefab", _d.triggerEnter == true);

    if (_te != (_d.triggerEnter == true)) {
      var _before = __poly_history_snap(_ed);
      _d.triggerEnter = _te; _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }

    var _ts = ImGui.Checkbox("On stay##prefab", _d.triggerStay == true);

    if (_ts != (_d.triggerStay == true)) {
      var _before = __poly_history_snap(_ed);
      _d.triggerStay = _ts; _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }

    var _tx = ImGui.Checkbox("On exit##prefab", _d.triggerExit == true);

    if (_tx != (_d.triggerExit == true)) {
      var _before = __poly_history_snap(_ed);
      _d.triggerExit = _tx; _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }
  }

  // Character params.
  if (_d.mode == "character") {
    var _char_fields = [ [ "radius","Radius",0.01,0.01,100 ],[ "halfHeight","Half height",0.01,0.01,100 ],[ "stepHeight","Step height",0.01,0,20 ],[ "maxSlopeAngle","Max slope",0.5,0,89 ],[ "mass","Mass",0.5,0.001,100000 ],[ "maxStrength","Max strength",1,0.001,100000 ] ];

    for (var _ci = 0; _ci < array_length(_char_fields); _ci++) {
      var _cf = _char_fields[_ci];
      var _cv = __poly_imgui_prop_float(_ed, "prefab_char_" + _cf[0], _cf[1], _d.character[$ _cf[0]], 120);
      __poly_imgui_physics_tip("Default " + _cf[1] + " for newly spawned character instances.");

      if (_cv != undefined && _cv != _d.character[$ _cf[0]]) {
        var _before = __poly_history_snap(_ed);
        _d.character[$ _cf[0]] = clamp(_cv, _cf[3], _cf[4]);
        _entry.physics_default = _d;
        if (!is_struct(_meta)) _meta = { type: "model" };
        _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
        if (_before != undefined) __poly_history_commit(_ed, _before);
      }
    }

    // Stick to ground toggle (prefab default).
    var _stg_p = ImGui.Checkbox("Stick to ground##prefab", _d.character.stickToGround == true);

    if (_stg_p != (_d.character.stickToGround == true)) {
      var _before = __poly_history_snap(_ed);
      _d.character.stickToGround = _stg_p;
      _entry.physics_default = _d;
      if (!is_struct(_meta)) _meta = { type: "model" };
      _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
      if (_before != undefined) __poly_history_commit(_ed, _before);
    }

    if (ImGui.Button("Recenter visual##prefab")) {
      var _bb = _entry.model != undefined ? _entry.model.getBoundingBox() : undefined;

      if (is_struct(_bb) && _bb.min != undefined && _bb.max != undefined) {
        var _before = __poly_history_snap(_ed);
        _d.character.visualOffset = [ -(_bb.min.x + _bb.max.x) * 0.5, -(_bb.min.y + _bb.max.y) * 0.5, -(_bb.min.z + _bb.max.z) * 0.5 ];
        _entry.physics_default = _d;
        if (!is_struct(_meta)) _meta = { type: "model" };
        _meta.physics = _d; _ed.asset_meta[$ _entry.key] = _meta;
        if (_before != undefined) __poly_history_commit(_ed, _before);
      }
    }
  }
}

// Edits one spawn shadow flag live (no undo: library defaults).
function __poly_edit_spawn_shadow(_entry, _field, _label) {
  var _nv = ImGui.Checkbox(_label, _entry.spawn_shadow[$ _field] == true);

  if (_nv != (_entry.spawn_shadow[$ _field] == true)) _entry.spawn_shadow[$ _field] = _nv;
}

// ---------------------------------------------------------------------------
// Actor binding section (per-model companion config, saved to file)
// ---------------------------------------------------------------------------

// Ensures the per-model file-meta map exists.
function __poly_asset_meta(_ed) {
  if (!variable_struct_exists(_ed, "asset_meta") || !is_struct(_ed.asset_meta)) _ed.asset_meta = {};
  return _ed.asset_meta;
}

// Returns the actor binding struct for an asset key, or undefined.
function __poly_actor_get(_ed, _key) {
  if (!is_string(_key) || _key == "") return undefined;
  var _meta = __poly_asset_meta(_ed);

  if (!variable_struct_exists(_meta, _key) || !is_struct(_meta[$ _key])) return undefined;
  var _entry = _meta[$ _key];

  if (!variable_struct_exists(_entry, "actor") || !is_struct(_entry.actor)) return undefined;
  return _entry.actor;
}

// Draws the Actor section for a library entry (model inspector, no undo:
// file metadata like spawn defaults). The binding counts when an object
// is set; an empty object means no companion.
function __poly_imgui_actor_sec(_ed, _entry) {
  var _key = is_struct(_entry) ? _entry[$ "key"] : undefined;

  if (!is_string(_key) || _key == "") return;
  var _ac = __poly_actor_get(_ed, _key);

  if (_ac == undefined) {
    var _meta = __poly_asset_meta(_ed);
    _meta[$ _key] = { type: "model", actor: { object: "", layer: "Instances" } };
    _ac = __poly_actor_get(_ed, _key);

    if (_ac == undefined) return;
  }

  if (!variable_struct_exists(_entry, "actor_ui") || !is_struct(_entry.actor_ui)) _entry.actor_ui = { filter: "" };
  var _cur = (is_string(_ac[$ "object"]) && _ac.object != "") ? _ac.object : "(none)";
  ImGui.AlignTextToFramePadding();
  ImGui.Text("Object");
  ImGui.SameLine(80);
  ImGui.SetNextItemWidth(220);

  if (ImGui.BeginCombo("##actor_obj", _cur)) {    _entry.actor_ui.filter = __poly_imgui_text_hint("##actor_find", "Search...", _entry.actor_ui.filter);

    if (ImGui.Selectable("(none)", _cur == "(none)", 0, 0, 0)) {
      _ac.object = "";
      _ed.dirty = true;
    }

    var _ids = asset_get_ids(asset_object);
    var _flt = string_lower(_entry.actor_ui.filter);
    var _shown = 0;

    for (var _i = 0, _n = array_length(_ids); _i < _n; _i++) {
      var _nm = object_get_name(_ids[_i]);

      if (!is_string(_nm) || _nm == "") continue;
      if (_flt != "" && string_pos(_flt, string_lower(_nm)) <= 0) continue;

      if (ImGui.Selectable(_nm, _cur == _nm, 0, 0, 0)) {
        _ac.object = _nm;
        _ed.dirty = true;
      }

      _shown++;
      if (_shown >= 200) break;
    }

    ImGui.EndCombo();
  }

  // Dangling binding (deleted object): flag it where it is
  // configured, instead of discovering it at load time.
  if (is_string(_ac[$ "object"]) && _ac.object != "") {
    var _oi = asset_get_index(_ac.object);

    if (_oi < 0 || !object_exists(_oi)) ImGui.TextColored("object not found (deleted?)", make_colour_rgb(235, 90, 90));
  }

  var _base_layer = (is_string(_ac[$ "layer"]) && _ac.layer != "") ? _ac.layer : "Instances";
  ImGui.AlignTextToFramePadding();
  ImGui.Text("Layer");
  ImGui.SameLine(80);
  ImGui.SetNextItemWidth(220);
  var _lr = __poly_imgui_text("actor_layer_" + _key, "##actor_layer", _base_layer);

  if (!_lr.active && _lr.was_active) {
    var _v = _lr.text == "" ? "Instances" : _lr.text;

    if (_v != _base_layer) {
      _ac.layer = _v;
      _ed.dirty = true;
    }
  }
}
