// poly_imgui_scene — Hierarchy window (rows, filter, rubber band).

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

// Draws Hierarchy window (scene nodes tree).
function __poly_imgui_scene_win(_ed) {
  var _ui = _ed.imgui;

  if (!_ui.win_hier.open) return;
  var _place = __poly_imgui_place(_ed).hier;

  if (!__poly_imgui_dock_fresh(_ed)) {
    ImGui.SetNextWindowPos(_place.x, _place.y, _ui.cond);
    ImGui.SetNextWindowSize(_place.w, _place.h, _ui.cond);
  }

  ImGui.SetNextWindowBgAlpha(1);

  var _flags = __poly_imgui_panel_flags(_ed, "hier");

  if (__poly_imgui_lock_move(_ed)) _flags = _flags | ImGuiWindowFlags.NoMove;

  if (!ImGui.Begin("Hierarchy", _ui.win_hier, _flags)) {
    __poly_imgui_panel_save(_ed, "hier");
    ImGui.End();
    return;
  }

  __poly_imgui_panel_save(_ed, "hier");
  _ui.hier_focused = __poly_imgui_safe("IsWindowFocused", false);
  __poly_imgui_scene_list(_ed);
  ImGui.End();
}

// ---------------------------------------------------------------------------
// Eye and lock buttons
// ---------------------------------------------------------------------------

// Draws visibility toggle eye button.
function __poly_imgui_eye(_hidden, _ghost, _tipkey) {
  static _eye_open = -2;
  static _eye_shut = -2;

  if (_eye_open == -2) _eye_open = asset_get_index("sprPolygonEditorIconEye");
  if (_eye_shut == -2) _eye_shut = asset_get_index("sprPolygonEditorIconEyeClosed");
  var _spr = _hidden ? _eye_shut : _eye_open;
  var _tint = c_white;

  if (_spr == -1 && _hidden) {
    _spr = _eye_open;
    _tint = make_colour_rgb(105, 115, 135);
  }

  var _hit = false;

  if (_spr != -1) {
    _hit = ImGui.ImageButton("eye", _spr, 0, _tint, _ghost ? 0 : 1, c_black, 0, sprite_get_width(_spr), sprite_get_height(_spr));
  } else {
    _hit = ImGui.SmallButton(_hidden ? "Show##eye" : "Hide##eye");
  }

  if (ImGui.IsItemHovered()) __poly_imgui_tip_delayed(_tipkey, _hidden ? "Show in viewport" : "Hide from viewport", true);
  return _hit;
}

// Draws selection lock toggle handpoint button.
function __poly_imgui_lock(_locked, _ghost, _tipkey) {
  static _hand = -2;
  static _hand_off = -2;

  if (_hand == -2) _hand = asset_get_index("sprPolygonEditorIconHandpoint");
  if (_hand_off == -2) _hand_off = asset_get_index("sprPolygonEditorIconHandpointDisabled");
  var _tint = c_white;
  var _spr = _hand;

  if (_locked && _hand_off != -1) {
    _spr = _hand_off;
  } else if (_hand == -1 && _locked) {
    _tint = make_colour_rgb(105, 115, 135);
  }

  var _hit = false;

  if (_spr != -1) {
    var _sx = ImGui.GetCursorScreenPosX();
    var _sy = ImGui.GetCursorScreenPosY();
    ImGui.SetCursorScreenPos(_sx, _sy);
    _hit = ImGui.ImageButton("lock", _spr, 0, _tint, _ghost ? 0 : 1, c_black, 0, sprite_get_width(_spr), sprite_get_height(_spr));
  } else {
    _hit = ImGui.SmallButton(_locked ? "Unlock##lock" : "Lock##lock");
  }

  if (ImGui.IsItemHovered()) __poly_imgui_tip_delayed(_tipkey, _locked ? "Unlock selection" : "Lock selection", true);
  return _hit;
}

// ---------------------------------------------------------------------------
// Rename (custom instance name)
// ---------------------------------------------------------------------------

// Starts in-place node rename mode.
function __poly_rename_begin(_ed, _node) {
  if (_node == undefined) return;
  if (_ed.giz.drag != -1) return;
  if (__poly_registry_find(_ed, _node) == undefined) return;
  _ed.rename_name = __poly_node_display(_ed, _node);
  _ed.rename_id = _node.name;
  _ed.imgui.win_hier.open = true;
}

// Cancels active node rename.
function __poly_rename_cancel(_ed) {
  _ed.rename_name = undefined;
  _ed.rename_id = undefined;
}

// ---------------------------------------------------------------------------
// Kind icons
// ---------------------------------------------------------------------------

// Resolves the icon sprite and tooltip for a node kind.
function __poly_kind_icon_info(_ed, _node, _kind, _cache) {
  if (_kind == "camera") {
    return { spr: _cache.cam, tip: "Camera", dir: false };
  }

  if (_kind == "environment") {
    return { spr: _cache.pt, tip: "Environment", dir: false };
  }

  if (_kind == "light") {
    var _en = __poly_registry_find(_ed, _node);

    if (_en != undefined && is_struct(_en.data) && variable_struct_exists(_en.data, "type") && _en.data.type == "directional") {
      return { spr: _cache.dir, tip: "Directional light", dir: true };
    }

    return { spr: _cache.pt, tip: "Point light", dir: false };
  }

  return { spr: _cache.obj, tip: "Model", dir: false };
}

// Draws node type icon with tooltip.
function __poly_imgui_kind_icon(_ed, _node, _kind, _hidden, _idx) {
  static _cache = undefined;

  _cache ??= {
    obj: asset_get_index("sprPolygonEditorIconObject"),
    cam: asset_get_index("sprPolygonEditorIconCamera"),
    pt: asset_get_index("sprPolygonEditorIconPointLight"),
    dir: asset_get_index("sprPolygonEditorIconDirectionalLight"),
  };

  var _info = __poly_kind_icon_info(_ed, _node, _kind, _cache);

  if (_info.spr == -1) return;
  var _iw = sprite_get_width(_info.spr);
  var _ih = sprite_get_height(_info.spr);
  var _tint = _hidden ? make_colour_rgb(105, 115, 135) : c_white;

  if (_info.dir) {
    ImGui.Dummy(1, 0);
    ImGui.SameLine(0, 0);
  }

  ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 3);
  ImGui.Image(_info.spr, 0, _tint, 1, _iw, _ih);

  if (ImGui.IsItemHovered()) {
    __poly_imgui_tip_delayed("hier|icon|" + string(_node.name), _info.tip, true);

    // Child rows (idx < 0) do not own an eye/lock pair to reveal.
    if (_idx >= 0) {
      _ed.imgui.scene_eye_idx = _idx;
      _ed.imgui.scene_eye_till = current_time + 500;
    }
  }
}

// ---------------------------------------------------------------------------
// Row metadata and rubber band
// ---------------------------------------------------------------------------

// Builds one metadata record per node with a single registry lookup.
// Pass the entry and/or selection set when known (no lookup at all).
function __poly_scene_row_meta(_ed, _node, _en = undefined, _selset = undefined) {
  _en ??= __poly_registry_find(_ed, _node);

  var _label = __poly_node_display(_ed, _node, _en);

  var _kind = undefined;

  if (_en != undefined && is_string(_en.kind) && _en.kind != "") {
    _kind = _en.kind;
  } else if (_node.getLightComponent() != undefined) {
    _kind = "light";
  } else if (_node.getCameraComponent() != undefined) {
    _kind = "camera";
  } else if (_node.getEnvironmentVolumeComponent() != undefined) {
    _kind = "environment";
  } else if (_en != undefined) {
    _kind = "instance";
  }

  var _sel = _selset != undefined ? __poly_sel_in(_selset, _node, _en) : __poly_node_list_has(_ed.sel, _node);
  return {
    node: _node,
    display: _label,
    kind: _kind,
    hidden: _en != undefined && _en.hidden == true,
    locked: _en != undefined && _en.locked == true,
    sel: _sel,
  };
}

// Steps the hierarchy rubber-band selection (call inside the rows child).
function __poly_hier_rect_step(_ed) {
  var _down = false;
  _down = ImGui.IsMouseDown(0);
  var _was_down = _ed.hier_mdown == true;
  _ed.hier_mdown = _down;

  if (_ed.hier_rect == undefined) {
    if (!_down || _was_down || _ed.rename_name != undefined) return;
    if (!__poly_imgui_safe("IsWindowHovered", false)) return;
    var _mx = ImGui.GetMousePosX();
    var _my = ImGui.GetMousePosY();
    _ed.hier_rect = { x0: _mx, y0: _my, x1: _mx, y1: _my, active: false, on_item: __poly_imgui_safe("IsAnyItemHovered", true) };
    return;
  }

  var _rect = _ed.hier_rect;

  if (_down) {
    _rect.x1 = ImGui.GetMousePosX();
    _rect.y1 = ImGui.GetMousePosY();

    if (!_rect.active && max(abs(_rect.x1 - _rect.x0), abs(_rect.y1 - _rect.y0)) > 6) _rect.active = true;

    if (_rect.active) {
      var _dl = ImGui.GetWindowDrawList();

      if (_dl != undefined) ImGui.DrawListAddRect(_dl, min(_rect.x0, _rect.x1), min(_rect.y0, _rect.y1), max(_rect.x0, _rect.x1), max(_rect.y0, _rect.y1), make_colour_rgb(120, 170, 255));
    }

    return;
  }

  var _was_active = _rect.active == true;
  var _from_item = _rect.on_item == true;
  _ed.hier_rect = undefined;

  if (!_was_active) {
    if (_from_item) return;
    __poly_sel_assign(_ed, []);
    _ed.scene_click_idx = -1;
    _ed.scene_click_time = -10000;
    return;
  }

  __poly_hier_rect_commit(_ed, min(_rect.y0, _rect.y1), max(_rect.y0, _rect.y1));
}

// ---------------------------------------------------------------------------
// Filter and rows
// ---------------------------------------------------------------------------

// Checks if a row kind passes the kind filter.
function __poly_kind_shown(_filter, _kind) {
  if (_kind == "light") return _filter.l;
  if (_kind == "camera") return _filter.c;
  if (_kind == "environment") return _filter.e;
  return _filter.m;
}

// Builds filtered row metadata for visible roots.
function __poly_scene_filter(_ed, _pairs, _selset, _kinds, _flt) {
  var _rows = [];

  for (var _r = 0, _n = array_length(_pairs); _r < _n; _r++) {
    var _meta = __poly_scene_row_meta(_ed, _pairs[_r].node, _pairs[_r].en, _selset);

    if (!__poly_kind_shown(_kinds, _meta.kind)) continue;
    if (_flt != "" && string_pos(_flt, string_lower(_meta.display)) <= 0) continue;
    array_push(_rows, _meta);
  }

  return _rows;
}

// Draws the rename editor for a row, committing on focus loss.
function __poly_scene_row_rename(_ed, _meta) {
  var _res = __poly_imgui_text("rename", "##rename", _meta.display);

  if (_res.was_active && !_res.active) {
    var _next = string_trim(_res.text);

    if (_next != "" && _next != _meta.display) __poly_scene_commit_rename(_ed, _meta.node, _next);
    __poly_rename_cancel(_ed);
  }
}

// Pokes the eye/lock reveal timer for a row.
function __poly_scene_row_reveal(_ui, _idx) {
  _ui.scene_eye_idx = _idx;
  _ui.scene_eye_till = current_time + 500;
}

// Vertical frame padding (per side) that makes a tree node frame as tall as the
// row. The eye/lock buttons are the tallest row content: their image plus the
// frame padding. With the default style this is a couple of pixels taller than
// ImGui's text-based frame height.
function __poly_scene_row_pad_y() {
  var _line_h = ImGui.GetTextLineHeight();
  var _btn_h = _line_h;
  var _eye = asset_get_index("sprPolygonEditorIconEye");

  if (_eye != -1) _btn_h = sprite_get_height(_eye) + ImGui.GetFrameHeight() - _line_h;

  return max(0, (_btn_h - _line_h) * 0.5);
}

// Draws one node row as an ImGui tree node and recurses into its children.
// Tracked roots (_is_root) own eye/lock buttons, selection, rename and the
// context menu; child rows are display-only structure. Returns the row pitch.
function __poly_scene_tree_row(_ed, _ui, _node, _is_root, _idx, _meta, _hidden, _pending) {
  var _sel = false;
  var _kind = undefined;
  var _label = string(_node.name);

  if (_is_root) {
    _sel = _meta.sel;
    _kind = _meta.kind;
    _label = _meta.display;
  }

  var _renaming = _is_root
    && _ed.rename_name != undefined
    && _ed.rename_id != undefined
    && string(_node.name) == string(_ed.rename_id)
    && _meta.display == _ed.rename_name;

  var _kids = _node.getChildren();
  var _has_kids = false; // temporarily hide child nodes
  var _flags = ImGuiTreeNodeFlags.SpanFullWidth | ImGuiTreeNodeFlags.OpenOnArrow | ImGuiTreeNodeFlags.AllowOverlap | ImGuiTreeNodeFlags.FramePadding;

  if (!_has_kids) _flags = _flags | ImGuiTreeNodeFlags.Leaf;
  if (_sel) _flags = _flags | ImGuiTreeNodeFlags.Selected;

  var _row_y = ImGui.GetCursorPosY();

  if (_is_root) _ed.hier_row_y[$ string(_idx)] = ImGui.GetCursorScreenPosY();

  ImGui.PushID(string(_node.name));
  ImGui.SetNextItemAllowOverlap();
  // The node label is hidden, so TreeNodeEx would size its frame from the font
  // height alone and the hover/selection fill would be shorter than the row.
  // Padding the frame up to the eye/lock button height makes the frame, the
  // click area and the row content coincide.
  // 11 = ImGuiStyleVar.FramePadding (raw index, the binding has no enum for it);
  // 4 is its default .x, so the arrow and content offsets do not move.
  ImGui.PushStyleVar(11, 4, __poly_scene_row_pad_y());
  var _open = ImGui.TreeNodeEx("##node", _flags);
  var _row_clicked = ImGui.IsItemClicked();
  ImGui.PopStyleVar();
  ImGui.SameLine(0, 0);

  // Clicks on the eye/lock buttons must not also select the row.
  var _over_btn = false;

  if (_is_root) {
    var _eye_on = _meta.hidden || (_ui.scene_eye_idx == _idx && current_time <= _ui.scene_eye_till);

    if (__poly_imgui_eye(_meta.hidden, !_eye_on, "hier|eye|" + string(_node.name))) __poly_hidden_set(_ed, _node, !_meta.hidden);

    if (ImGui.IsItemHovered()) {
      _over_btn = true;
      __poly_scene_row_reveal(_ui, _idx);
    }

    ImGui.SameLine(0, 0);
    var _lock_on = _meta.locked || (_ui.scene_eye_idx == _idx && current_time <= _ui.scene_eye_till);

    if (__poly_imgui_lock(_meta.locked, !_lock_on, "hier|lock|" + string(_node.name))) __poly_locked_set(_ed, _node, !_meta.locked);

    if (ImGui.IsItemHovered()) {
      _over_btn = true;
      __poly_scene_row_reveal(_ui, _idx);
    }

    ImGui.SameLine();
  }

  __poly_imgui_kind_icon(_ed, _node, _kind, _hidden, _is_root ? _idx : -1);
  ImGui.SameLine();

  if (_renaming) {
    __poly_scene_row_rename(_ed, _meta);
  } else if (_is_root) {
    ImGui.TextUnformatted(__poly_short_name(_label));

    if (ImGui.IsItemHovered()) {
      __poly_scene_row_reveal(_ui, _idx);
      __poly_imgui_tip_delayed("hier|name|" + string(_node.name), _label, true);
    }
  } else {
    ImGui.TextUnformatted(__poly_short_name(_label));

    if (ImGui.IsItemHovered()) __poly_imgui_tip_delayed("hier|name|" + string(_node.name), _label, true);
  }

  var _pitch = ImGui.GetCursorPosY() - _row_y;

  if (_is_root && !_renaming && !_over_btn && _row_clicked) __poly_scene_click(_ed, _node, _idx, _ed.hier_rows);

  if (_is_root && !_renaming) {
    ImGui.SetNextWindowBgAlpha(1);
    __poly_scene_row_menu(_ed, _meta, _node, _idx, _pending);
  }

  if (_open) ImGui.TreePop();

  ImGui.PopID();
  return _pitch;
}

// Draws the right-click context menu for a row.
function __poly_scene_row_menu(_ed, _meta, _node, _idx, _pending) {
  if (!ImGui.BeginPopupContextItem("ctx##" + string(_node.name))) return;
  if (!_meta.sel) __poly_scene_select(_ed, _node);

  if (array_length(_ed.sel) <= 1) {
    if (ImGui.MenuItem("Focus", __poly_bind_label(_ed.cfg.keys, "focus"))) {
      _pending.foc = _node;
      ImGui.CloseCurrentPopup();
    }

    if (ImGui.MenuItem("Rename", __poly_bind_label(_ed.cfg.keys, "rename"))) {
      _pending.ren = _node;
      ImGui.CloseCurrentPopup();
    }
  }

  if (ImGui.MenuItem("Duplicate", __poly_bind_label(_ed.cfg.keys, "dupe"))) {
    _pending.dup = _node;
    ImGui.CloseCurrentPopup();
  }

  if (ImGui.MenuItem("Copy", __poly_bind_label(_ed.cfg.keys, "copy"))) {
    _pending.cop = true;
    ImGui.CloseCurrentPopup();
  }

  if (ImGui.MenuItem("Cut", __poly_bind_label(_ed.cfg.keys, "cut"))) {
    _pending.cut = true;
    ImGui.CloseCurrentPopup();
  }

  if (ImGui.MenuItem("Paste", __poly_bind_label(_ed.cfg.keys, "paste"))) {
    _pending.pas = true;
    ImGui.CloseCurrentPopup();
  }

  if (ImGui.MenuItem("Delete", __poly_bind_label(_ed.cfg.keys, "del"))) {
    _pending.del = _node;
    ImGui.CloseCurrentPopup();
  }

  ImGui.EndPopup();
}

// Draws the hierarchy status bar ("N items"). Measures its own height so
// the rows child can reserve exactly that much space next frame.
function __poly_hier_status(_ed, _shown, _total) {
  var _y0 = ImGui.GetCursorPosY();
  ImGui.Separator();

  if (_shown == _total) {
    ImGui.TextDisabled(string(_shown) + (_shown == 1 ? " item" : " items"));
  } else {
    ImGui.TextDisabled(string(_shown) + " of " + string(_total) + " items");
  }

  var _h = ImGui.GetCursorPosY() - _y0;

  if (is_real(_h) && _h > 0 && is_struct(_ed.imgui)) _ed.imgui.hier_status_h = _h;
}

// Draws filterable scene list with selection actions.
function __poly_imgui_scene_list(_ed) {
  var _ui = _ed.imgui;

  if (!variable_struct_exists(_ui, "show_kind")) {
    _ui.show_kind = { m: true, l: true, c: true, e: true };
  }

  if (!variable_struct_exists(_ui, "scene_eye_idx")) {
    _ui.scene_eye_idx = -1;
    _ui.scene_eye_till = 0;
  }

  ImGui.SetNextItemWidth(max(80, ImGui.GetContentRegionAvailX() - 60));
  if (!variable_struct_exists(_ui, "scene_focus_search")) _ui.scene_focus_search = false;
  var _want_search = _ui.scene_focus_search == true;
  _ui.scene_focus_search = false;
  _ui.scene_filter = __poly_imgui_text_hint("##scenefilter", "Filter nodes...", _ui.scene_filter, _want_search);
  ImGui.SameLine();

  if (__poly_imgui_icon_btn("##scenefilters", "Filter asset types", false, "Fl", "sprPolygonEditorIconFilters", 13, 13)) ImGui.OpenPopup("##scenekindfilters");

  ImGui.SameLine();
  if (__poly_imgui_icon_btn("##scenecreate", "Create", false, "Cr", "sprPolygonEditorIconPlus", 13, 13)) ImGui.OpenPopup("##scenecreatepopup");

  ImGui.SameLine(0, 6);
  ImGui.Dummy(2, 0);

  if (ImGui.BeginPopup("##scenecreatepopup")) {
    if (__poly_light_count(_ed) >= 8) {
      ImGui.TextDisabled("Lights (8 max reached)");
    } else {
      if (ImGui.MenuItem("Directional Light")) __poly_create_light(_ed, "directional");
      if (ImGui.MenuItem("Point Light")) __poly_create_light(_ed, "point");
    }
    ImGui.Separator();
    if (ImGui.MenuItem("Perspective Camera")) __poly_create_camera(_ed, "perspective");
    if (ImGui.MenuItem("Ortho Camera")) __poly_create_camera(_ed, "ortho");
    ImGui.Separator();
    if (__poly_env_node(_ed) == undefined) {
      if (ImGui.MenuItem("Environment")) __poly_create_env(_ed);
    } else {
      ImGui.TextDisabled("Environment (already in scene)");
    }
    ImGui.EndPopup();
  }

  if (ImGui.BeginPopup("##scenekindfilters")) {
    _ui.show_kind.m = ImGui.Checkbox("Models", _ui.show_kind.m);
    _ui.show_kind.l = ImGui.Checkbox("Lights", _ui.show_kind.l);
    _ui.show_kind.c = ImGui.Checkbox("Cameras", _ui.show_kind.c);
    _ui.show_kind.e = ImGui.Checkbox("Environment", _ui.show_kind.e);
    ImGui.EndPopup();
  }

  ImGui.Spacing();

  if (_ed.rt == undefined) {
    ImGui.TextDisabled("No scene");
    _ed.hier_rect = undefined;
    __poly_hier_status(_ed, 0, 0);
    return;
  }

  var _pending = { ren: undefined, foc: undefined, dup: undefined, del: undefined, cop: false, cut: false, pas: false };

  if (!variable_struct_exists(_ed, "scene_click_idx")) {
    _ed.scene_click_idx = -1;
    _ed.scene_click_time = -10000;
  }

  if (!variable_struct_exists(_ed, "scene_anchor")) _ed.scene_anchor = undefined;
  var _pairs = __poly_root_pairs(_ed);
  var _rows = __poly_scene_filter(_ed, _pairs, __poly_sel_set(_ed), _ui.show_kind, string_lower(_ui.scene_filter));
  var _n = array_length(_rows);
  var _total = array_length(_pairs);
  // Reserve bottom space for the status bar: exact measured height once
  // known, compact estimate on the first frame.
  var _status_h = ImGui.GetTextLineHeight() + 10;

  if (variable_struct_exists(_ui, "hier_status_h") && is_real(_ui.hier_status_h) && _ui.hier_status_h > 0) _status_h = _ui.hier_status_h;

  if (!ImGui.BeginChild("##hierarchy_node_rows", 0, -_status_h, ImGuiChildFlags.None)) {
    ImGui.EndChild();
    __poly_scene_list_commit(_ed, _pending.ren, _pending.foc, _pending.dup, _pending.del, _pending.cop, _pending.cut, _pending.pas);
    __poly_hier_status(_ed, _n, _total);
    return;
  }

  ImGui.PushStyleColor(ImGuiCol.Button, c_black, 0);
  ImGui.PushStyleColor(ImGuiCol.ButtonHovered, make_colour_rgb(47, 111, 237), 0.35);
  ImGui.PushStyleColor(ImGuiCol.ButtonActive, make_colour_rgb(47, 111, 237), 0.5);

  _ed.hier_rows = _rows;
  _ed.hier_row_y = {};
  var _row_h = _ed.hier_row_h;

  if (!is_real(_row_h) || _row_h <= 0) _row_h = ImGui.GetFrameHeightWithSpacing();

  for (var _i = 0; _i < _n; _i++) {
    var _meta = _rows[_i];
    var _pitch = __poly_scene_tree_row(_ed, _ui, _meta.node, true, _i, _meta, _meta.hidden, _pending);

    // Root rows share one pitch: calibrate the rubber-band height from the
    // first one instead of relying on a hard-coded row estimate.
    if (_i == 0 && is_real(_pitch) && _pitch > 0) _row_h = _pitch;
  }

  __poly_imgui_pop(3);

  _ed.hier_row_h = _row_h;
  __poly_hier_rect_step(_ed);

  ImGui.EndChild();
  __poly_hier_status(_ed, _n, _total);
  __poly_scene_list_commit(_ed, _pending.ren, _pending.foc, _pending.dup, _pending.del, _pending.cop, _pending.cut, _pending.pas);
}
