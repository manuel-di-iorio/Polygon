// poly_input - owners, hotkeys, gizmo/library/rect/hover steps, mouse wrap.

// ---------------------------------------------------------------------------
// Owners and context
// ---------------------------------------------------------------------------

// Synchronizes active input gesture owner.
function __poly_input_owner_sync(_ed) {
  var _owner = _ed.input_owner;

  if (_owner == undefined) {
    if (_ed.giz.drag != -1) {
      _owner = "gizmo";
    } else if (_ed.drag_lib != undefined) {
      _owner = "library";
    } else if (_ed.cube_armed == true) {
      _owner = "viewcube";
    } else if (_ed.rect != undefined) {
      _owner = "rect";
    } else if (_ed.cam_orbit) {
      _owner = "camera_orbit";
    } else if (_ed.cam_zoom) {
      _owner = "camera_zoom";
    } else if (_ed.cam_fly) {
      _owner = "camera_fly";
    } else if (_ed.cam_pan) {
      _owner = "camera_pan";
    }
  }

  if (
    (_owner == "gizmo" && _ed.giz.drag == -1) ||
    (_owner == "library" && _ed.drag_lib == undefined) ||
    (_owner == "viewcube" && _ed.cube_armed != true) ||
    (_owner == "rect" && _ed.rect == undefined) ||
    (_owner == "camera_orbit" && !_ed.cam_orbit) ||
    (_owner == "camera_zoom" && !_ed.cam_zoom) ||
    (_owner == "camera_fly" && !_ed.cam_fly) ||
    (_owner == "camera_pan" && !_ed.cam_pan)
    ) {
    _owner = undefined;
  }

  _ed.input_owner = _owner;
  return _owner;
}

// Checks if owner is camera operation.
function __poly_input_owner_is_camera(_owner) {
  return (
    _owner == "camera_orbit" ||
    _owner == "camera_zoom" ||
    _owner == "camera_fly" ||
    _owner == "camera_pan"
  );
}

// Clears specified input owner if active.
function __poly_input_owner_clear(_ed, _owner) {
  if (_ed.input_owner == _owner) _ed.input_owner = undefined;
}

// Builds mouse keyboard and viewport input context.
function __poly_input_context(_ed, _keys) {
  var _mx = device_mouse_x_to_gui(0);
  var _my = device_mouse_y_to_gui(0);
  var _mouse_capture = ImGui.WantMouseCapture();
  var _keyboard_capture = ImGui.WantKeyboardCapture();
  var _text_input = ImGui.WantTextInput();

  var _typing = _keyboard_capture || _text_input;
  var _in_viewport = !_mouse_capture && _mx >= 0 && _mx <= _ed.gw && _my >= 0 && _my <= _ed.gh;
  var _pox = 0;
  var _poy = 0;
  var _pww = _ed.gw;
  var _phh = _ed.gh;

  if (variable_struct_exists(_ed, "svp") && is_struct(_ed.svp) && _ed.svp.w > 0 && _ed.svp.h > 0) {
    _pox = _ed.svp.x;
    _poy = _ed.svp.y;
    _pww = _ed.svp.w;
    _phh = _ed.svp.h;
  }

  var _vin =
    __poly_scene_panel_open(_ed) &&
    _ed.svp_hover == true &&
    _mx >= _pox &&
    _mx < _pox + _pww &&
    _my >= _poy &&
    _my < _poy + _phh;
  var _vp = __poly_viewport_cached(_ed);
  var _owner = __poly_input_owner_sync(_ed);
  return {
    keys: _keys,
    mx: _mx,
    my: _my,
    vmx: _mx - _pox,
    vmy: _my - _poy,
    vin: _vin,
    vp: _vp,
    mouse_capture: _mouse_capture,
    keyboard_capture: _keyboard_capture,
    text_input: _text_input,
    typing: _typing,
    in_viewport: _in_viewport,
    owner: _owner,
    gesture_active:
      _owner != undefined && !__poly_input_owner_is_camera(_owner),
    camera_keys: false,
    camera_viewport: _in_viewport,
    camera_zoom: false,
  };
}

// ---------------------------------------------------------------------------
// Hotkeys
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Binding evaluation
// ---------------------------------------------------------------------------

// Binding element = struct { key, mouse?, modifier? }.
//   key      the key code (vk_* / ord("X") for keys, mb_* for mouse)
//   mouse    true when the code is a mouse button (else a keyboard key)
//   modifier true when the entry must be held (else it is a trigger)
// A bare real is accepted as a keyboard trigger. Several triggers in one array
// are alternatives; the type is always explicit, never inferred from the code,
// so mouse buttons and keys can never be confused.

// Key code of a binding element, or undefined when malformed. Accepts a bare
// real (keyboard) for the short form.
function __poly_elem_key(_e) {
  if (is_real(_e)) return _e;

  if (is_struct(_e) && variable_struct_exists(_e, "key")) {
    var _k = _e[$ "key"];

    if (is_real(_k)) return _k;
  }

  return undefined;
}

// True when the element is an explicitly declared mouse button.
function __poly_elem_mouse(_e) {
  return is_struct(_e) && variable_struct_exists(_e, "mouse") && _e[$ "mouse"] == true;
}

// True when the element is a required hold rather than a trigger.
function __poly_elem_mod(_e) {
  return is_struct(_e) && variable_struct_exists(_e, "modifier") && _e[$ "modifier"] == true;
}

// Evaluates a binding. _press: trigger pressed this frame, else held.
// _exact: keyboard modifiers not declared as holds must be up. Exact suits
// one-shot shortcuts; camera movement passes false so extra modifiers
// (e.g. the Shift boost) do not cancel the movement keys.
function __poly_bind_run(_keys, _name, _press, _exact) {
  if (!variable_struct_exists(_keys, _name)) return false;
  var _b = _keys[$ _name];

  if (is_real(_b) || is_struct(_b)) _b = [ _b ];
  if (!is_array(_b) || array_length(_b) == 0) return false;
  var _n = array_length(_b);
  var _ctrl = false;
  var _shift = false;
  var _alt = false;
  var _i;
  var _e;
  var _k;

  // Required holds first, so an unmet hold short-circuits.
  for (_i = 0; _i < _n; _i++) {
    _e = _b[_i];

    if (!__poly_elem_mod(_e)) continue;
    _k = __poly_elem_key(_e);

    if (_k == undefined) continue;

    if (__poly_elem_mouse(_e)) {
      if (!mouse_check_button(_k)) return false;
    } else if (_k == vk_control) {
      _ctrl = true;
    } else if (_k == vk_shift) {
      _shift = true;
    } else if (_k == vk_alt) {
      _alt = true;
    } else if (!keyboard_check(_k)) {
      return false;
    }
  }

  if (_ctrl && !keyboard_check(vk_control)) return false;
  if (_shift && !keyboard_check(vk_shift)) return false;
  if (_alt && !keyboard_check(vk_alt)) return false;

  if (_exact) {
    if (!_ctrl && keyboard_check(vk_control)) return false;
    if (!_shift && keyboard_check(vk_shift)) return false;
    if (!_alt && keyboard_check(vk_alt)) return false;
  }

  // Any trigger fires; several are alternatives.
  for (_i = 0; _i < _n; _i++) {
    _e = _b[_i];

    if (__poly_elem_mod(_e)) continue;
    _k = __poly_elem_key(_e);

    if (_k == undefined) continue;

    if (__poly_elem_mouse(_e)) {
      if (_press ? mouse_check_button_pressed(_k) : mouse_check_button(_k)) return true;
    } else if (_press ? keyboard_check_pressed(_k) : keyboard_check(_k)) {
      return true;
    }
  }

  return false;
}

// One-shot shortcut: trigger pressed, keyboard modifiers exact.
function __poly_bind_pressed(_keys, _name) {
  return __poly_bind_run(_keys, _name, true, true);
}

// Continuous binding that ignores extra modifiers (camera movement, buttons).
function __poly_bind_key(_keys, _name) {
  return __poly_bind_run(_keys, _name, false, false);
}

// True when all keyboard-modifier holds of a binding are held. Used to gate
// camera keys while a text field is focused: the camera gesture modifiers
// (Alt by default) let the camera start.
function __poly_bind_mods(_keys, _name) {
  if (!variable_struct_exists(_keys, _name)) return false;
  var _b = _keys[$ _name];

  if (is_real(_b) || is_struct(_b)) _b = [ _b ];
  if (!is_array(_b)) return false;
  var _found = false;

  for (var _i = 0; _i < array_length(_b); _i++) {
    var _e = _b[_i];

    if (!__poly_elem_mod(_e) || __poly_elem_mouse(_e)) continue;
    var _k = __poly_elem_key(_e);

    if (_k == undefined) continue;
    if (!keyboard_check(_k)) return false;
    _found = true;
  }

  return _found;
}

// Display name for a single code (used by the menu shortcut labels).
function __poly_bind_key_name(_key, _mouse) {
  if (_mouse) {
    switch (_key) {
      case mb_left: return "Mouse Left";
      case mb_right: return "Mouse Right";
      case mb_middle: return "Mouse Middle";
      case mb_side1: return "Mouse 4";
      case mb_side2: return "Mouse 5";
    }

    return "Mouse";
  }

  switch (_key) {
    case vk_control: return "Ctrl";
    case vk_shift: return "Shift";
    case vk_alt: return "Alt";
    case vk_left: return "Left";
    case vk_right: return "Right";
    case vk_up: return "Up";
    case vk_down: return "Down";
    case vk_enter: return "Enter";
    case vk_escape: return "Esc";
    case vk_space: return "Space";
    case vk_backspace: return "Backspace";
    case vk_tab: return "Tab";
    case vk_delete: return "Del";
    case vk_insert: return "Ins";
    case vk_home: return "Home";
    case vk_end: return "End";
    case vk_pageup: return "PageUp";
    case vk_pagedown: return "PageDown";
    case vk_pause: return "Pause";
    case vk_printscreen: return "PrtSc";
    case vk_f1: return "F1";
    case vk_f2: return "F2";
    case vk_f3: return "F3";
    case vk_f4: return "F4";
    case vk_f5: return "F5";
    case vk_f6: return "F6";
    case vk_f7: return "F7";
    case vk_f8: return "F8";
    case vk_f9: return "F9";
    case vk_f10: return "F10";
    case vk_f11: return "F11";
    case vk_f12: return "F12";
    case vk_numpad0: return "Num0";
    case vk_numpad1: return "Num1";
    case vk_numpad2: return "Num2";
    case vk_numpad3: return "Num3";
    case vk_numpad4: return "Num4";
    case vk_numpad5: return "Num5";
    case vk_numpad6: return "Num6";
    case vk_numpad7: return "Num7";
    case vk_numpad8: return "Num8";
    case vk_numpad9: return "Num9";
    case vk_multiply: return "Num *";
    case vk_divide: return "Num /";
    case vk_add: return "Num +";
    case vk_subtract: return "Num -";
    case vk_decimal: return "Num .";
  }

  if (_key >= 32 && _key <= 126) return chr(_key);
  return "Key " + string(_key);
}

// Human-readable shortcut label for a binding (e.g. "Ctrl+D"), for menus and
// tooltips. Modifiers come first (Ctrl, Shift, Alt), then the first trigger.
// Returns "" when the binding is unknown or empty.
function __poly_bind_label(_keys, _name) {
  if (!variable_struct_exists(_keys, _name)) return "";
  var _b = _keys[$ _name];

  if (is_real(_b) || is_struct(_b)) _b = [ _b ];
  if (!is_array(_b)) return "";
  var _ctrl = false;
  var _shift = false;
  var _alt = false;
  var _main = "";

  for (var _i = 0; _i < array_length(_b); _i++) {
    var _e = _b[_i];
    var _k = __poly_elem_key(_e);

    if (_k == undefined) continue;
    var _mouse = __poly_elem_mouse(_e);
    var _hold = __poly_elem_mod(_e);

    if (_hold && !_mouse) {
      if (_k == vk_control) {
        _ctrl = true;
        continue;
      }

      if (_k == vk_shift) {
        _shift = true;
        continue;
      }

      if (_k == vk_alt) {
        _alt = true;
        continue;
      }
    }

    if (_main == "") _main = __poly_bind_key_name(_k, _mouse);
  }

  var _s = "";

  if (_ctrl) _s += "Ctrl+";
  if (_shift) _s += "Shift+";
  if (_alt) _s += "Alt+";
  return _s + _main;
}

// Tool shortcuts table: [key name, tool].
function __poly_tool_hotkeys() {
  static _tools = [
    [ "tool_view", PolygonEditorTool.View ],
    [ "tool_move", PolygonEditorTool.Translate ],
    [ "tool_rotate", PolygonEditorTool.Rotate ],
    [ "tool_scale", PolygonEditorTool.Scale ],
  ];
  return _tools;
}

// Nudges selection with the nudge bindings (arrows by default).
function __poly_step_nudge(_ed, _keys) {
  var _nx = __poly_bind_pressed(_keys, "nudge_right") - __poly_bind_pressed(_keys, "nudge_left");
  var _nz = __poly_bind_pressed(_keys, "nudge_down") - __poly_bind_pressed(_keys, "nudge_up");

  if ((_nx == 0 && _nz == 0) || array_length(_ed.sel) == 0) return;
  var _step = _ed.snap_on ? __poly_snap_step(_ed) : 0.25;
  var _before = __poly_history_snap(_ed);

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    if (!__poly_tool_allowed(_ed, _ed.sel[_i], PolygonEditorTool.Translate) || __poly_hidden_get(_ed, _ed.sel[_i])) continue;
    var _pos = _ed.sel[_i].getLocalPosition();
    _ed.sel[_i].setLocalPosition(new GM3D_Vec3(_pos.x + _nx * _step, _pos.y, _pos.z + _nz * _step));
  }

  __poly_history_commit(_ed, _before);
  __poly_physics_debug_rebuild(_ed);
}

// Handles editor keyboard shortcuts and nudging.
function __poly_step_hotkeys(_ed, _input) {
  var _keys = _input.keys;

  if (_input.typing) return;
  var _gesture = _input.gesture_active;

  if (_gesture) return;
  var _tools = __poly_tool_hotkeys();
  // QWER double as fly keys: while the right button flies the camera,
  // letters fly instead of switching tools.
  // NB: _input.in_viewport is false while ImGui owns the mouse, so gate
  // on the raw button + camera owner instead.
  var _flying = __poly_bind_key(_keys, "cam_fly") && (_input.owner == undefined || __poly_input_owner_is_camera(_input.owner));

  for (var _t = 0, _nt = array_length(_tools); _t < _nt; _t++) if (!_flying && __poly_bind_pressed(_keys, _tools[_t][0])) _ed.giz.tool = _tools[_t][1];
  if (__poly_bind_pressed(_keys, "del")) __poly_delete_ask(_ed);
  if (!_flying && __poly_bind_pressed(_keys, "deselect")) __poly_sel_clear(_ed);
  if (__poly_bind_pressed(_keys, "focus")) __poly_focus_selection(_ed);
  if (__poly_bind_pressed(_keys, "snap")) _ed.snap_on = !_ed.snap_on;
  if (__poly_bind_pressed(_keys, "pivot")) __poly_toggle_pivot(_ed);
  if (__poly_bind_pressed(_keys, "orient")) __poly_toggle_orient(_ed);

  if (__poly_bind_pressed(_keys, "colliders")) {
    _ed.show_colliders = !_ed.show_colliders;
    if (_ed.show_colliders) __poly_physics_debug_rebuild(_ed); else __poly_physics_debug_destroy(_ed);
    _ed.view_dirty = true;
  }

  if (__poly_bind_pressed(_keys, "rename") && array_length(_ed.sel) > 0) __poly_rename_begin(_ed, _ed.sel[0]);
  __poly_step_nudge(_ed, _keys);

  if (__poly_bind_pressed(_keys, "save")) __poly_save_or_ask(_ed);
  if (__poly_bind_pressed(_keys, "dupe")) __poly_duplicate_sel(_ed);
  if (__poly_bind_pressed(_keys, "copy")) __poly_clipboard_copy(_ed);
  if (__poly_bind_pressed(_keys, "cut")) __poly_clipboard_cut(_ed);
  if (__poly_bind_pressed(_keys, "paste")) __poly_clipboard_paste(_ed);
  if (__poly_bind_pressed(_keys, "invert")) __poly_invert_sel(_ed);
  if (__poly_bind_pressed(_keys, "select_all")) __poly_select_all(_ed);
  if (__poly_bind_pressed(_keys, "focus_search")) __poly_focus_search(_ed);
  if (__poly_bind_pressed(_keys, "new_scene")) __poly_confirm_ask(_ed, "new");
  if (__poly_bind_pressed(_keys, "close")) __poly_confirm_ask(_ed, "close");
  if (__poly_bind_pressed(_keys, "load")) __poly_confirm_ask(_ed, "load");
  if (__poly_bind_pressed(_keys, "snap_grid")) __poly_push_sel_to_grid(_ed);

  if (__poly_bind_pressed(_keys, "undo")) {
    __poly_history_apply(_ed, _ed.undo, _ed.redo);
  } else if (__poly_bind_pressed(_keys, "redo") || __poly_bind_pressed(_keys, "redo_shift")) {
    __poly_history_apply(_ed, _ed.redo, _ed.undo);
  }
}

// ---------------------------------------------------------------------------
// Cancel and gizmo step
// ---------------------------------------------------------------------------

// Restores gizmo-dragged nodes to drag-start transforms.
function __poly_cancel_gizmo(_ed) {
  var _g = _ed.giz;

  if (is_array(_g.starts) && array_length(_g.starts) == array_length(_ed.sel)) {
    for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
      _ed.sel[_i].setLocalPosition(_g.starts[_i].pos.clone());
      _ed.sel[_i].setLocalRotation(_g.starts[_i].rot.clone());
      _ed.sel[_i].setLocalScale(_g.starts[_i].sca.clone());
    }

    _ed.rt.scene.update(0);
  }

  _ed.giz.drag = -1;
  __poly_wrap_end(_ed);
  _ed.hist_before = undefined;
  _ed.cmd_open = undefined;
  // Restore mutates the scene: flag it like a commit, or the surface and
  // the outline mask keep showing the dragged (uncommitted) state.
  _ed.dirty = true;
  _ed.view_dirty = true;
  __poly_physics_debug_rebuild(_ed);
  if (variable_struct_exists(_ed, "outline") && is_struct(_ed.outline)) _ed.outline.cheap = undefined;
  __poly_input_owner_clear(_ed, "gizmo");
}

// Handles Escape cancellation of active operations.
function __poly_step_cancel(_ed, _input) {
  if (_input.typing || !__poly_bind_pressed(_input.keys, "cancel")) return;

  if (_ed.scene_dlg != undefined) {
    _ed.scene_dlg = undefined;
  } else if (_ed.confirm != undefined) {
    _ed.confirm = undefined;
  } else if (_ed.rename_name != undefined) {
    __poly_rename_cancel(_ed);
  } else if (_ed.drag_lib != undefined) {
    __poly_drop_preview_clear(_ed);
    _ed.drag_lib = undefined;
    _ed.drag_moved = false;
    __poly_input_owner_clear(_ed, "library");
  } else if (_ed.cube_armed == true) {
    _ed.cube_armed = undefined;
    _ed.cube_face = undefined;
    _ed.cube_moved = false;
    _ed.press_vp = false;
    __poly_input_owner_clear(_ed, "viewcube");
  } else if (_ed.rect != undefined) {
    _ed.rect = undefined;
    _ed.press_vp = false;
    __poly_input_owner_clear(_ed, "rect");
  } else if (_ed.giz.drag != -1) {
    __poly_cancel_gizmo(_ed);
  } else {
    __poly_sel_clear(_ed);
  }
}

// Updates active gizmo drag operation.
function __poly_step_gizmo(_ed, _input) {
  var _vp = _input.vp;
  var _mx = _input.mx;
  var _my = _input.my;

  if (_ed.giz.drag == -1) return false;

  if (!mouse_check_button(mb_left)) {
    _ed.giz.drag = -1;

    if (_ed.hist_before != undefined) __poly_cmd_commit(_ed, _ed.hist_before, "gizmo-drag");
    __poly_physics_debug_rebuild(_ed);
    __poly_wrap_end(_ed);

    _ed.hist_before = undefined;
    __poly_input_owner_clear(_ed, "gizmo");
  } else {
    if (_ed.wrap == undefined) {
      _ed.wrap = { on: true, vx: _mx, vy: _my, lx: _mx, ly: _my };
    }

    var _wrapped = __poly_wrap_step(_ed, _mx, _my);
    __poly_gizmo_drag(_ed, _vp, _wrapped[0] - _vp.offX, _wrapped[1] - _vp.offY);
  }

  _ed.giz.hover = _ed.giz.drag;
  _ed.rect = undefined;
  _ed.press_vp = false;
  return true;
}

// ---------------------------------------------------------------------------
// Library drop
// ---------------------------------------------------------------------------

// Computes the drop point (ground plane, else fixed distance ahead).
function __poly_libdrop_point(_ed, _input, _in_vp, _moved) {
  if (_moved && _in_vp) return __poly_drop_point(_input.vp, _input.vmx, _input.vmy);

  if (!_moved) {
    var _pos = _ed.rt.cam.getLocalPosition();
    var _fwd = __poly_view_forward_cached(_ed);
    var _dist = 5.0;
    return new GM3D_Vec3(
      _pos.x - _fwd.x * _dist,
      _pos.y - _fwd.y * _dist,
      _pos.z - _fwd.z * _dist
    );
  }

  return undefined;
}

// Commits a drag-preview node as a real placement.
function __poly_libdrop_commit_preview(_ed, _asset, _spawn, _drop) {
  _ed.drag_preview.setLocalPosition(new GM3D_Vec3(_drop.x, _drop.y, _drop.z));

  if (_spawn.rot != undefined) _ed.drag_preview.setLocalRotation(_spawn.rot);
  _ed.drag_preview.setLocalScale(new GM3D_Vec3(_spawn.sca[0], _spawn.sca[1], _spawn.sca[2]));

  if (variable_struct_exists(_ed.rt, "on_create")) _ed.rt.on_create(_ed.drag_preview, _asset.key, _asset.model);
  var _at = _ed.drag_preview.getLocalPosition();
  __poly_spawn_register(
    _ed,
    _ed.drag_preview,
    _asset.key
  );
  __poly_spawn_shadow_apply(_ed, _asset, _ed.drag_preview);
  __poly_physics_debug_rebuild(_ed);
  _ed.sel = [ _ed.drag_preview ];
  _ed.giz.drag = -1;
  _ed.drag_preview = undefined;
}

// Places a fresh node from the library.
function __poly_libdrop_place_new(_ed, _asset, _spawn, _drop) {
  var _node = __poly_place(
    _ed,
    _asset.key,
    _asset.model,
    [ _drop.x, _drop.y, _drop.z ],
    _spawn.rot,
    _spawn.sca
  );

  if (_node != undefined) {
    __poly_spawn_shadow_apply(_ed, _asset, _node);
    _ed.sel = [ _node ];
    _ed.giz.drag = -1;
  }
}

// Handles asset drag preview and placement.
function __poly_step_libdrop(_ed, _input) {
  if (_ed.drag_lib == undefined) return false;
  var _in_vp = __poly_drag_in_viewport(_ed, _input.mx, _input.my);

  if (point_distance(_input.mx, _input.my, _ed.press_x, _ed.press_y) > 4) _ed.drag_moved = true;

  if (_ed.drag_moved && _in_vp) {
    var _preview_at = __poly_drop_point(_input.vp, _input.vmx, _input.vmy);

    if (_preview_at == undefined) {
      __poly_drop_preview_clear(_ed);
    } else {
      __poly_drop_preview_update(_ed, _preview_at);
    }
  }

  if (mouse_check_button(mb_left)) return true;
  var _drop = __poly_libdrop_point(_ed, _input, _in_vp, _ed.drag_moved);

  if (_drop != undefined) {
    var _before = __poly_history_snap(_ed);
    var _asset = _ed.drag_lib.asset;
    var _spawn = __poly_spawn_apply(_asset);

    if (_ed.drag_preview != undefined) {
      __poly_libdrop_commit_preview(_ed, _asset, _spawn, _drop);
    } else {
      __poly_libdrop_place_new(_ed, _asset, _spawn, _drop);
    }

    __poly_history_commit(_ed, _before);
  } else {
    __poly_drop_preview_clear(_ed);
  }

  _ed.drag_lib = undefined;
  _ed.drag_moved = false;
  __poly_input_owner_clear(_ed, "library");
  return true;
}

// ---------------------------------------------------------------------------
// Rectangle selection
// ---------------------------------------------------------------------------

// Handles rectangle selection drag completion.
function __poly_step_rect(_ed, _input) {
  if (_ed.giz.tool == PolygonEditorTool.View) return false;
  var _mx = _input.mx;
  var _my = _input.my;

  if (_ed.rect == undefined || !_ed.rect.on) return false;
  _ed.rect.x1 = _mx;
  _ed.rect.y1 = _my;

  if (!mouse_check_button(mb_left)) {
    var _r = __poly_rect_norm(_ed.rect);

    if (abs(_r.x1 - _r.x0) > 6 || abs(_r.y1 - _r.y0) > 6) {
      var _ox = 0;
      var _oy = 0;

      if (variable_struct_exists(_ed, "svp") && is_struct(_ed.svp)) {
        _ox = _ed.svp.x;
        _oy = _ed.svp.y;
      }

      var _local = {
        x0: _r.x0 - _ox,
        y0: _r.y0 - _oy,
        x1: _r.x1 - _ox,
        y1: _r.y1 - _oy,
      };
      __poly_gpupick_request_rect(_ed, _local, __poly_bind_key(_ed.cfg.keys, "select_add"));
    }

    _ed.rect = undefined;
    _ed.press_vp = false;
    // The rect was baked into the surface every drag frame: force one
    // re-render even when the pick selects nothing (key would not change).
    _ed.view_dirty = true;
    __poly_input_owner_clear(_ed, "rect");
  }

  return true;
}

// ---------------------------------------------------------------------------
// Hover, press, release
// ---------------------------------------------------------------------------

// Arms a press gesture (viewcube, gizmo, view-pan or rect).
function __poly_hover_press(_ed, _input, _vp, _vmx, _vmy) {
  var _mx = _input.mx;
  var _my = _input.my;

  if (!(mouse_check_button_pressed(mb_left) && _input.vin && !_input.typing && !__poly_bind_key(_input.keys, "cam_orbit") && _input.owner == undefined)) return;

  if (_ed.cube_geom != undefined && __poly_viewcube_box_at(_ed.cube_geom, _vmx, _vmy)) {
    _ed.input_owner = "viewcube";
    _input.owner = "viewcube";
    _input.gesture_active = true;
    _ed.press_vp = true;
    _ed.press_x = _mx;
    _ed.press_y = _my;
    _ed.cube_armed = true;
    _ed.cube_face = _ed.cube_hover;
    _ed.cube_moved = false;
    _ed.cube_gx = _vmx - _ed.cube_geom.cx;
    _ed.cube_gy = _vmy - _ed.cube_geom.cy;
  } else if (_ed.giz.hover != -1 && array_length(_ed.sel) > 0) {
    _ed.input_owner = "gizmo";
    _input.owner = "gizmo";
    _input.gesture_active = true;
    _ed.giz.drag = _ed.giz.hover;
    __poly_gizmo_begin(_ed, _vp, _vmx, _vmy);
  } else if (_ed.giz.tool == PolygonEditorTool.View) {
    _ed.input_owner = "viewpan";
    _input.owner = "viewpan";
    _input.gesture_active = true;
    _ed.press_vp = true;
    _ed.press_x = _mx;
    _ed.press_y = _my;
    _ed.viewpan_moved = false;
  } else {
    _ed.input_owner = "rect";
    _input.owner = "rect";
    _input.gesture_active = true;
    _ed.press_vp = true;
    _ed.press_x = _mx;
    _ed.press_y = _my;
    _ed.rect = { x0: _mx, y0: _my, x1: _mx, y1: _my, on: false };
  }
}

// Drags the viewcube widget itself (moves it on screen).
function __poly_cube_drag(_ed, _input, _vmx, _vmy) {
  if (!(_ed.cube_armed == true && mouse_check_button(mb_left))) return;
  if (point_distance(_input.mx, _input.my, _ed.press_x, _ed.press_y) > 6) _ed.cube_moved = true;
  if (!_ed.cube_moved) return;
  var _pw = _ed.gw;
  var _ph = _ed.gh;

  if (variable_struct_exists(_ed, "svp") && is_struct(_ed.svp) && _ed.svp.w > 0 && _ed.svp.h > 0) {
    _pw = _ed.svp.w;
    _ph = _ed.svp.h;
  }

  var _nx = clamp(_vmx - _ed.cube_gx, 48, max(49, _pw - 48));
  var _ny = clamp(_vmy - _ed.cube_gy, 48, max(49, _ph - 48));
  _ed.cube_off = [ _pw - _nx, _ny ];
}

// Handles hover picking and click selection.
function __poly_step_hover(_ed, _input) {
  var _vp = _input.vp;
  var _mx = _input.mx;
  var _my = _input.my;
  var _vmx = _input.vmx;
  var _vmy = _input.vmy;
  var _in_vp = _input.vin;
  _ed.cube_geom = _ed.imgui.win_cube.open ? __poly_viewcube(_ed) : undefined;
  _ed.cube_hover = undefined;

  if (_in_vp && !__poly_bind_key(_input.keys, "cam_fly") && _ed.cube_geom != undefined) _ed.cube_hover = __poly_viewcube_cone_at(_ed.cube_geom, _vmx, _vmy);
  _ed.giz.hover = -1;

  if (_in_vp && !__poly_bind_key(_input.keys, "cam_fly")) _ed.giz.hover = __poly_gizmo_hover(_ed, _vp, _vmx, _vmy);
  if (_ed.cube_geom != undefined && __poly_viewcube_box_at(_ed.cube_geom, _vmx, _vmy)) _ed.giz.hover = -1;
  __poly_hover_press(_ed, _input, _vp, _vmx, _vmy);

  if (_ed.press_vp && _ed.rect != undefined && mouse_check_button(mb_left)) if (point_distance(_mx, _my, _ed.press_x, _ed.press_y) > 6) _ed.rect.on = true;

  if (_ed.input_owner == "viewpan" && mouse_check_button(mb_left)) {
    if (point_distance(_mx, _my, _ed.press_x, _ed.press_y) > 6) _ed.viewpan_moved = true;
    if (_ed.viewpan_moved == true) __poly_view_pan(_ed, _vp);
  }

  __poly_cube_drag(_ed, _input, _vmx, _vmy);

  if (mouse_check_button_released(mb_left) && _ed.press_vp && (_ed.rect == undefined || !_ed.rect.on)) __poly_hover_release(_ed, _vmx, _vmy, _in_vp);
}

// Handles left-button release (click select, cube face, view focus).
function __poly_hover_release(_ed, _vmx, _vmy, _in_vp) {
  var _was_view = _ed.input_owner == "viewpan";
  var _view_drag = _was_view && _ed.viewpan_moved == true;
  _ed.press_vp = false;
  _ed.rect = undefined;
  _ed.viewpan_moved = false;
  __poly_input_owner_clear(_ed, "rect");
  __poly_input_owner_clear(_ed, "viewpan");

  if (_was_view) {
    if (!_view_drag && _in_vp) __poly_gpupick_request_click(_ed, _vmx, _vmy, __poly_bind_key(_ed.cfg.keys, "select_add"));
  } else if (_ed.cube_armed == true) {
    _ed.cube_armed = undefined;
    __poly_input_owner_clear(_ed, "viewcube");

    if (_ed.cube_moved) __poly_ui_save(_ed);

    if (_in_vp && !_ed.cube_moved && _ed.cube_face != undefined && _ed.cube_geom != undefined) {
      var _hit = __poly_viewcube_cone_at(_ed.cube_geom, _vmx, _vmy);

      if (_hit != undefined && _hit[0] == _ed.cube_face[0] && _hit[1] == _ed.cube_face[1]) {
        for (var _fi = 0, _n = array_length(_ed.cube_geom.faces); _fi < _n; _fi++) {
          var _face = _ed.cube_geom.faces[_fi];

          if (_face.a == _hit[0] && _face.s == _hit[1]) {
            __poly_viewcube_snap(_ed, _face.n);
            break;
          }
        }
      }
    }

    _ed.cube_face = undefined;
  } else if (_in_vp) {
    __poly_gpupick_request_click(_ed, _vmx, _vmy, __poly_bind_key(_ed.cfg.keys, "select_add"));
  }
}

// ---------------------------------------------------------------------------
// Mouse wrap
// ---------------------------------------------------------------------------

// Wraps cursor coordinates at window edges, returning the wrapped pair.
function __poly_wrap_edge(_mx, _my, _ww, _wh) {
  var _nx = _mx;
  var _ny = _my;

  if (_mx < 8) {
    _nx = _ww - 9;
  } else if (_mx > _ww - 9) {
    _nx = 8;
  }

  if (_my < 8) {
    _ny = _wh - 9;
  } else if (_my > _wh - 9) {
    _ny = 8;
  }

  return [ _nx, _ny ];
}

// Begins infinite mouse wrap tracking.
// Ends mouse wrap tracking.
function __poly_wrap_end(_ed) {
  if (_ed != undefined) _ed.wrap = undefined;
}

// Updates wrapped mouse virtual coordinates.
function __poly_wrap_step(_ed, _mx, _my) {
  var _wrap = _ed.wrap;

  if (_wrap == undefined || !_wrap.on) return [ _mx, _my ];
  _wrap.vx += _mx - _wrap.lx;
  _wrap.vy += _my - _wrap.ly;
  _wrap.lx = _mx;
  _wrap.ly = _my;
  var _ww = window_get_width();
  var _wh = window_get_height();

  if (_ww > 16 && _wh > 16) {
    var _edge = __poly_wrap_edge(_mx, _my, _ww, _wh);

    if (_edge[0] != _mx || _edge[1] != _my) {
      window_mouse_set(round(_edge[0]), round(_edge[1]));

      _wrap.lx = _edge[0];
      _wrap.ly = _edge[1];
    }
  }

  return [ _wrap.vx, _wrap.vy ];
}

// Wraps cursor at window edges.
function __poly_wrap_camera(_ed) {
  if (_ed == undefined) return;
  var _mx = device_mouse_x_to_gui(0);
  var _my = device_mouse_y_to_gui(0);
  var _ww = window_get_width();
  var _wh = window_get_height();

  if (_ww <= 16 || _wh <= 16) return;
  var _edge = __poly_wrap_edge(_mx, _my, _ww, _wh);

  if (_edge[0] != _mx || _edge[1] != _my) window_mouse_set(round(_edge[0]), round(_edge[1]));
}

// Checks if mouse is inside viewport.
function __poly_drag_in_viewport(_ed, _mx, _my) {
  if (!__poly_scene_panel_open(_ed) || !variable_struct_exists(_ed, "svp") || !is_struct(_ed.svp)) return false;
  return (
    _mx >= _ed.svp.x &&
    _mx < _ed.svp.x + _ed.svp.w &&
    _my >= _ed.svp.y &&
    _my < _ed.svp.y + _ed.svp.h
  );
}
