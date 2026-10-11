// polygon_imgui_insp_materials — material collection + preview rows.

// ---------------------------------------------------------------------------
// Collection and naming
// ---------------------------------------------------------------------------

// Collects raw materials across a node subtree (live instance state).
function __polygon_collect_node_mats(_node) {
  var _out = [];

  if (_node == undefined) return _out;
  var _comps = [];
  __polygon_walk_collect_tree(_node, _comps);

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++) {
    var _mat = _comps[_i].comp.getMaterial();

    if (_mat != undefined) array_push(_out, _mat);
  }

  return _out;
}

// Collects raw materials of a library model (source state).
function __polygon_collect_asset_mats(_entry) {
  var _out = [];

  if (!is_struct(_entry) || _entry.model == undefined) return _out;
  var _get = _entry.model[$ "getMaterials"];

  if (_get == undefined) return _out;
  var _list = method(_entry.model, _get)();

  if (!is_array(_list)) return _out;
  for (var _i = 0, _n = array_length(_list); _i < _n; _i++) if (_list[_i] != undefined) array_push(_out, _list[_i]);
  return _out;
}

// Reads a material name ("material" fallback).
function __polygon_mat_name(_mm) {
  if (_mm == undefined) return "material";
  var _get = _mm[$ "getName"];

  if (_get == undefined) return "material";
  var _got = method(_mm, _get)();
  return (is_string(_got) && _got != "") ? _got : "material";
}

function __polygon_imgui_mat_slot_meta(_mats) {
  var _keys = [];

  if (is_array(_mats)) {
    for (var _i = 0, _n = array_length(_mats); _i < _n; _i++) {
      var _mat = _mats[_i];

      if (_mat == undefined) continue;
      var _key = __polygon_mat_key(_mat);

      if (!array_contains(_keys, _key)) array_push(_keys, _key);
    }
  }

  var _count = array_length(_keys);
  return string(_count) + (_count == 1 ? " slot" : " slots");
}

// ---------------------------------------------------------------------------
// Shader labels
// ---------------------------------------------------------------------------

// Labels a shader handle by name (string, asset id, struct field, method).
function __polygon_shader_handle_label(_sh) {
  if (is_string(_sh) && _sh != "") return _sh;
  if (is_numeric(_sh)) return shader_exists(_sh) ? shader_get_name(_sh) : "Custom";

  if (is_struct(_sh)) {
    var _fields = [ "name", "Name", "shader", "id" ];

    for (var _i = 0, _n = array_length(_fields); _i < _n; _i++) {
      var _val = _sh[$ _fields[_i]];

      if (is_string(_val) && _val != "") return _val;
      if (is_numeric(_val) && shader_exists(_val)) return shader_get_name(_val);
    }

    var _get = _sh[$ "getName"];

    if (_get != undefined) {
      var _got = method(_sh, _get)();

      if (is_string(_got) && _got != "") return _got;
    }
  }

  return "Custom";
}

// Labels a material by its forward shader name (Custom when unknown).
function __polygon_mat_shader_label(_mm) {
  if (_mm == undefined) return "Custom";
  var _get = _mm[$ "getShader"];

  if (_get == undefined) return "Custom";
  var _sh = undefined;
  _sh = method(_mm, _get)(GM3D_ERenderPass.Forward);

  if (_sh == undefined) {
    // No shader assigned: the engine renders with its default fallback.
    return "Default";
  }

  return __polygon_shader_handle_label(_sh);
}

// Builds a display key for a material (name + forward shader).
function __polygon_mat_key(_mm) {
  if (_mm == undefined) return undefined;
  return __polygon_mat_name(_mm) + "|" + string(__polygon_mat_shader_label(_mm));
}

// ---------------------------------------------------------------------------
// Texture probing
// ---------------------------------------------------------------------------

// Probes whether a texture id is a real image (not an invalid or 1x1 default).
function __polygon_imgui_mat_tex_valid(_tex) {
  if (!is_numeric(_tex) || _tex == 0) return false;
  var _tw = texture_get_texel_width(_tex);
  var _th = texture_get_texel_height(_tex);

  if (!is_numeric(_tw) || !is_numeric(_th) || _tw <= 0 || _th <= 0) return false;
  // texel >= 1 means 1px (or smaller): a bound default, not an image.
  if (_tw >= 1 && _th >= 1) return false;
  return true;
}

// Reads path/name detail from a texture struct.
function __polygon_tex_struct_detail(_tex) {
  var _path = _tex[$ "path"];

  if (is_string(_path) && _path != "") return _path;
  var _name = _tex[$ "name"];

  if (is_string(_name) && _name != "") return _name;
  return undefined;
}

// Best-effort texture info for material uniforms (read-only).
// Probes gm_* names first (what the shaders actually sample), then u_* fallbacks.
function __polygon_imgui_mat_tex_info(_mm, _candidates) {
  var _get = _mm[$ "getTexture"];

  if (_get == undefined) {
    return { assigned: false, detail: "Not exposed", tex: undefined };
  }

  var _names = is_array(_candidates) ? _candidates : [ _candidates ];
  var _tex = undefined;

  for (var _i = 0, _n = array_length(_names); _i < _n; _i++) {
    _tex = method(_mm, _get)(_names[_i]);

    if (_tex != undefined) break;
  }

  if (_tex == undefined) {
    return { assigned: false, detail: "Not assigned", tex: undefined };
  }

  if (is_numeric(_tex)) {
    if (_tex == 0 || !__polygon_imgui_mat_tex_valid(_tex)) {
      return { assigned: false, detail: "Not assigned", tex: undefined };
    }

    return { assigned: true, detail: "Assigned", tex: _tex };
  }

  if (is_string(_tex) && _tex != "") {
    return { assigned: true, detail: _tex, tex: undefined };
  }

  if (is_struct(_tex)) {
    var _detail = __polygon_tex_struct_detail(_tex);

    if (_detail != undefined) {
      return { assigned: true, detail: _detail, tex: undefined };
    }
  }

  // Raw GPU texture id: assigned, but ImGui cannot display it directly
  // (Image/draw-list want sprites or surfaces, not texture ids).
  return { assigned: true, detail: "Assigned", tex: _tex };
}

// Returns texture pixel dimensions as "W x H" (best effort).
function __polygon_imgui_tex_dims(_tex) {
  var _tw = texture_get_texel_width(_tex);
  var _th = texture_get_texel_height(_tex);

  if (is_numeric(_tw) && is_numeric(_th) && _tw > 0 && _th > 0) return string(round(1 / _tw)) + " x " + string(round(1 / _th));
  return "Unknown";
}

// Reads sampler state for a texture id (read-only, undefined when unavailable).
function __polygon_imgui_tex_sampler(_tex) {
  return {
    filter: GM3D_Texture.getFilter(_tex),
    repeat_mode: GM3D_Texture.getRepeat(_tex),
    aniso: GM3D_Texture.getMaxAniso(_tex),
    min_mip: GM3D_Texture.getMinMip(_tex),
    max_mip: GM3D_Texture.getMaxMip(_tex),
    bias: GM3D_Texture.getMipBias(_tex),
    mip_enable: GM3D_Texture.getMipEnable(_tex),
    mip_filter: GM3D_Texture.getMipFilter(_tex),
  };
}

// ---------------------------------------------------------------------------
// GMRT texture thumbnails
// ---------------------------------------------------------------------------

// Renders one texture slot on the flat preview quad through GMRT itself
// (same id namespace as getTexture): scratch material with the slot bound
// as base texture, flat unlit shader, shot to a 96px sprite.
function __polygon_texview_render(_ed, _tex) {
  var _src = __polygon_tri_src(_ed);

  if (_src == undefined) return undefined;
  var _st = __polygon_tex_stage(_ed);

  if (_st == undefined) return undefined;
  var _node = _src.spawnInto(_st.ts, undefined);

  if (_node == undefined) return undefined;
  var _spr = undefined;
  var _view = new GM3D_Material("texview");
  _view.setTexture("gm_BaseTexture", _tex);
  _view.setFloatArray("gm_BaseColorFactor", [ 1, 1, 1, 1 ]);
  _view.setFloatArray("gm_BaseTexture_Offset", [ 0, 0 ]);
  _view.setFloatArray("gm_BaseTexture_Scale", [ 1, 1 ]);
  _view.setFloat("gm_BaseTexture_Rotation", 0.0);
  _view.setInt("gm_AlphaMode", 0);
  _view.setShader(GM3D_ERenderPass.Forward, shPolygonEditorUnlit);
  var _comps = [];
  __polygon_walk_collect_tree(_node, _comps);

  for (var _c = 0, _n = array_length(_comps); _c < _n; _c++) _comps[_c].comp.setMaterial(_view);
  _st.ts.update(0);
  _spr = __polygon_pv_shoot_sprite(_st, 96);

  __polygon_destroy_subtree(_node);
  _st.ts.update(0);
  _view.destroy();
  return sprite_exists(_spr) ? _spr : undefined;
}

// Returns a cached GMRT-rendered sprite for a texture id, or undefined.
function __polygon_imgui_mat_tex_thumb(_ed, _tex) {
  if (!is_numeric(_tex) || _tex == 0) return undefined;
  if (!variable_struct_exists(_ed, "mat_tex_pv") || !is_array(_ed.mat_tex_pv)) _ed.mat_tex_pv = [];

  if (!variable_struct_exists(_ed, "mat_tex_fail") || !is_struct(_ed.mat_tex_fail)) {
    _ed.mat_tex_fail = {};
  }

  var _fkey = string(_tex);

  if (variable_struct_exists(_ed.mat_tex_fail, _fkey)) return undefined;

  for (var _i = 0, _n = array_length(_ed.mat_tex_pv); _i < _n; _i++) {
    if (_ed.mat_tex_pv[_i].tex == _tex) {
      var _hit = _ed.mat_tex_pv[_i].spr;
      return sprite_exists(_hit) ? _hit : undefined;
    }
  }

  var _spr = undefined;
  _spr = __polygon_texview_render(_ed, _tex);

  if (_spr != undefined && sprite_exists(_spr)) {
    array_push(_ed.mat_tex_pv, { tex: _tex, spr: _spr });
    return _spr;
  }

  _ed.mat_tex_fail[$ _fkey] = true;
  return undefined;
}

// Frees baked texture thumbnails.
function __polygon_mat_tex_pv_free(_ed) {
  if (_ed == undefined) return;

  if (variable_struct_exists(_ed, "mat_tex_pv") && is_array(_ed.mat_tex_pv)) {
    for (var _i = 0, _n = array_length(_ed.mat_tex_pv); _i < _n; _i++) if (sprite_exists(_ed.mat_tex_pv[_i].spr)) sprite_delete(_ed.mat_tex_pv[_i].spr);
    _ed.mat_tex_pv = [];
  }

  _ed.mat_tex_fail = {};
}

// ---------------------------------------------------------------------------
// Headers and rows
// ---------------------------------------------------------------------------

// Shared header for the Material, Prefab and prefab-instance inspectors.
function __polygon_imgui_inspector_asset_header(_name, _type, _thumb, _size) {
  var _x = ImGui.GetCursorScreenPosX();
  var _y = ImGui.GetCursorScreenPosY();
  var _avail = ImGui.GetContentRegionAvailX();
  var _dl = ImGui.GetWindowDrawList();
  var _gap = 12;
  var _max_name_w = max(40, _avail - _size - _gap);
  var _short = __polygon_short_name(_name);
  var _label = __polygon_imgui_trunc_text(_short, _max_name_w);
  var _line_h = ImGui.GetTextLineHeight();
  var _name_scale = 1.12;
  var _text_h = _line_h * (_name_scale + 1) + 2;
  var _text_y = _y + max(0, (_size - _text_h) * 0.5);

  ImGui.Dummy(_avail, _size);

  if (_dl != undefined) {
    if (sprite_exists(_thumb)) {
      ImGui.DrawListAddImage(_dl, _thumb, 0, _x, _y, _x + _size, _y + _size, c_white);
    } else {
      ImGui.DrawListAddRectFilled(_dl, _x, _y, _x + _size, _y + _size, make_colour_rgb(29, 34, 44));
    }

    ImGui.DrawListAddRect(_dl, _x, _y, _x + _size, _y + _size, make_colour_rgb(78, 91, 113));

    ImGui.SetWindowFontScale(_name_scale);
    ImGui.DrawListAddText(_dl, _x + _size + _gap, _text_y, _label, make_colour_rgb(232, 236, 244));
    ImGui.SetWindowFontScale(1);
    ImGui.DrawListAddText(_dl, _x + _size + _gap, _text_y + _line_h * _name_scale + 2, _type, make_colour_rgb(151, 162, 180));
  }

  var _ax = ImGui.GetCursorScreenPosX();
  var _ay = ImGui.GetCursorScreenPosY();
  var _tx = _x + _size + _gap;
  var _tw = max(0, _avail - _size - _gap);
  ImGui.SetCursorScreenPos(_tx, _text_y);
  ImGui.InvisibleButton("##tip_assethead", max(1, _tw), max(1, _text_h));
  var _hov = ImGui.IsItemHovered();
  ImGui.SetCursorScreenPos(_ax, _ay);
  __polygon_imgui_tip_delayed("insp|assethead|" + string(_name), string(_name), _hov);

  ImGui.Spacing();
  ImGui.Separator();
  ImGui.Spacing();
}

// Keeps the native collapsing header behavior and paints a right-aligned hint.
function __polygon_imgui_section_meta(_label, _meta) {
  var _x = ImGui.GetCursorScreenPosX();
  var _y = ImGui.GetCursorScreenPosY();
  var _avail = ImGui.GetContentRegionAvailX();
  var _open = ImGui.CollapsingHeader(_label);

  if (is_string(_meta) && _meta != "") {
    var _dl = ImGui.GetWindowDrawList();
    var _tw = ImGui.CalcTextWidth(_meta);

    if (_dl != undefined && is_real(_x) && is_real(_y)) ImGui.DrawListAddText(_dl, _x + max(0, _avail - _tw - 24), _y + max(0, (ImGui.GetFrameHeight() - ImGui.GetTextLineHeight()) * 0.5), _meta, make_colour_rgb(170, 181, 198));
  }

  return _open;
}

// Shows a tooltip only after 500ms of continuous hover (standard delay).
// Switching hover target restarts the delay (stale timers are dropped).
function __polygon_imgui_tip_delayed(_key, _tip, _hovering) {
  static _since = {};
  static _cur = "";
  var _now = current_time;

  if (!is_string(_tip) || _tip == "") return;

  if (!_hovering) {
    if (variable_struct_exists(_since, _key)) variable_struct_remove(_since, _key);
    if (_cur == _key) _cur = "";
    return;
  }

  if (_cur != _key) {
    _since = {};
    _cur = _key;
    _since[$ _key] = _now;
    return;
  }

  if (!variable_struct_exists(_since, _key) || !is_real(_since[$ _key])) {
    _since[$ _key] = _now;
    return;
  }

  if (_now - _since[$ _key] >= 500) ImGui.SetTooltip(_tip);
}

// Draws one read-only label/value row, with an optional hover tooltip.
// Text() alone is not hoverable, so a transparent button overlays the row.
function __polygon_imgui_tex_field(_label, _value, _tip = undefined) {
  var _rx = ImGui.GetCursorScreenPosX();
  var _ry = ImGui.GetCursorScreenPosY();
  var _rw = ImGui.GetContentRegionAvailX();
  ImGui.AlignTextToFramePadding();
  ImGui.Text(_label);
  ImGui.SameLine(120);

  if (_value == undefined) {
    ImGui.TextDisabled("Unknown");
  } else {
    ImGui.Text(string(_value));
  }

  var _rh = ImGui.GetCursorScreenPosY() - _ry;

  if (_rh <= 0) _rh = ImGui.GetTextLineHeight();
  ImGui.SetCursorScreenPos(_rx, _ry);
  ImGui.InvisibleButton("##tip_" + _label, max(0, _rw), max(1, _rh));
  var _hov = ImGui.IsItemHovered();
  ImGui.SetCursorScreenPos(_rx, _ry + _rh);

  if (is_string(_tip) && _tip != "") __polygon_imgui_tip_delayed(_label, _tip, _hov);
}

// ---------------------------------------------------------------------------
// Base color
// ---------------------------------------------------------------------------

// Returns base color factor [r, g, b, a?] or undefined when not exposed.
function __polygon_imgui_mat_base_factor(_mm) {
  var _get = _mm[$ "getFloatArray"];

  if (_get == undefined) return undefined;
  var _factor = method(_mm, _get)("gm_BaseColorFactor");

  if (!is_array(_factor)) _factor = method(_mm, _get)("u_tint");
  if (!is_array(_factor) || array_length(_factor) < 3) return undefined;
  return _factor;
}

// Returns the transparency mode label (read-only).
function __polygon_imgui_mat_alpha_label(_mm) {
  var _get = _mm[$ "getInt"];

  if (_get == undefined) return "Not exposed";
  var _alpha = method(_mm, _get)("gm_AlphaMode");

  if (!is_numeric(_alpha)) return "Not exposed";
  static _labels = { "1": "Mask", "2": "Blend", "0": "Opaque" };
  var _key = string(_alpha);
  return variable_struct_exists(_labels, _key) ? _labels[$ _key] : "Not exposed";
}

// Converts a 0..1 channel to 2 uppercase hex digits.
function __polygon_hex2(_v) {
  static _digits = "0123456789ABCDEF";
  var _b = clamp(round(_v * 255), 0, 255);
  return string_char_at(_digits, (_b div 16) + 1) + string_char_at(_digits, (_b mod 16) + 1);
}

// Read-only Col4 swatch: static rect. (The ImGui ColorEdit4 widget is NOT
// used here on purpose: its packed variant takes an integer color, not a
// float array, and the struct variant needs the ImColor sample helper,
// which is not vendored in this project. Passing [_r,_g,_b,_a] crashes
// with "argument 'col' was invalid ... REAL argument is object".)
function __polygon_imgui_mat_color_ro(_r, _g, _b) {
  var _cx = ImGui.GetCursorScreenPosX();
  var _cy = ImGui.GetCursorScreenPosY();
  var _dl = ImGui.GetWindowDrawList();
  var _s = ImGui.GetFrameHeight();
  ImGui.Dummy(_s, _s);

  if (_dl != undefined) {
    ImGui.DrawListAddRectFilled(_dl, _cx, _cy, _cx + _s, _cy + _s, make_colour_rgb(round(_r * 255), round(_g * 255), round(_b * 255)));
    ImGui.DrawListAddRect(_dl, _cx, _cy, _cx + _s, _cy + _s, make_colour_rgb(78, 91, 113));
  }
}

// Draws the read-only base color row (swatch + hex + copy).
function __polygon_imgui_mat_color_section(_ed, _mm) {
  var _factor = __polygon_imgui_mat_base_factor(_mm);
  ImGui.AlignTextToFramePadding();
  ImGui.Text("Color");

  if (!is_array(_factor)) {
    ImGui.SameLine(120);
    ImGui.TextDisabled("Not exposed");
    ImGui.Spacing();
    return;
  }

  var _r = clamp(_factor[0], 0, 1);
  var _g = clamp(_factor[1], 0, 1);
  var _b = clamp(_factor[2], 0, 1);
  var _a = array_length(_factor) >= 4 ? clamp(_factor[3], 0, 1) : 1;
  ImGui.SameLine(120);
  __polygon_imgui_mat_color_ro(_r, _g, _b);
  ImGui.SameLine();
  var _hex = "#" + __polygon_hex2(_r) + __polygon_hex2(_g) + __polygon_hex2(_b) + __polygon_hex2(_a);
  ImGui.Text(_hex);
  ImGui.SameLine();

  var _copied = variable_struct_exists(_ed.imgui, "mat_copy_ms") && is_real(_ed.imgui.mat_copy_ms) && (current_time - _ed.imgui.mat_copy_ms) < 3000;

  if (ImGui.Button((_copied ? "Copied!##mat_basecolor" : "Copy##mat_basecolor"), 64, 0)) {
    clipboard_set_text(_hex);
    _ed.imgui.mat_copy_ms = current_time;
  }

  ImGui.Spacing();
}

// ---------------------------------------------------------------------------
// Texture rows
// ---------------------------------------------------------------------------

// Draws one read-only texture row (thumb + name + path).
function __polygon_imgui_mat_tex_row(_ed, _mm, _label, _uniform, _sep_before) {
  var _info = __polygon_imgui_mat_tex_info(_mm, _uniform);

  if (!_info.assigned) return false;

  if (_sep_before) {
    ImGui.Separator();
    ImGui.Spacing();
  }

  ImGui.PushID(_label);
  var _tsz = 40;
  var _gap = 8;
  var _row_w = ImGui.GetContentRegionAvailX();
  var _sx = ImGui.GetCursorScreenPosX();
  var _sy = ImGui.GetCursorScreenPosY();
  var _dl = ImGui.GetWindowDrawList();
  var _thumb = __polygon_imgui_mat_tex_thumb(_ed, _info.tex);
  var _line_h = ImGui.GetTextLineHeight();
  ImGui.Dummy(_row_w, _tsz);

  if (_thumb != undefined) {
    ImGui.SetCursorScreenPos(_sx, _sy);
    ImGui.Image(_thumb, 0, c_white, 1, _tsz, _tsz);
  } else if (_dl != undefined) {
    ImGui.DrawListAddRectFilled(_dl, _sx, _sy, _sx + _tsz, _sy + _tsz, make_colour_rgb(90, 90, 110));
    ImGui.DrawListAddRect(_dl, _sx, _sy, _sx + _tsz, _sy + _tsz, make_colour_rgb(78, 91, 113));
  }

  ImGui.SetCursorScreenPos(_sx + _tsz + _gap, _sy + max(0, (_tsz - _line_h) * 0.5));
  ImGui.Text(_label);

  ImGui.SetCursorScreenPos(_sx + max(0, _row_w - 60), _sy + max(0, (_tsz - ImGui.GetFrameHeight()) * 0.5));

  if (ImGui.Button("Select", 56, 0)) {
    _ed.tex_inspector = { tex: _info.tex, label: _label };
  }

  ImGui.SetCursorScreenPos(_sx, _sy + _tsz);
  ImGui.PopID();
  ImGui.Spacing();
  return true;
}

// Texture slots shown in the material inspector.
function __polygon_mat_tex_slots() {
  static _slots = [
    [ "Albedo", [ "gm_BaseTexture", "u_baseTexture" ] ],
    [ "Normal Map", [ "gm_NormalTexture", "u_normalTexture" ] ],
    [ "Metallic/Roughness Map", [ "gm_MetallicRoughnessTexture", "u_metallicRoughnessTexture" ] ],
    [ "Emissive Map", [ "gm_EmissiveTexture", "u_emissiveTexture" ] ],
  ];
  return _slots;
}

// Draws all assigned texture rows, returning the count.
function __polygon_imgui_mat_tex_section(_ed, _mm) {
  ImGui.Spacing();
  var _slots = __polygon_mat_tex_slots();
  var _shown = 0;

  for (var _i = 0, _n = array_length(_slots); _i < _n; _i++) if (__polygon_imgui_mat_tex_row(_ed, _mm, _slots[_i][0], _slots[_i][1], _shown > 0)) _shown++;
  if (_shown == 0) ImGui.TextDisabled("No textures");
  ImGui.Spacing();
}

// ---------------------------------------------------------------------------
// Material rows
// ---------------------------------------------------------------------------

// Dedupes materials by display key (clones share both name and shader).
function __polygon_mat_uniq(_mats) {
  var _uniq = [];

  if (!is_array(_mats)) return _uniq;

  for (var _i = 0, _n = array_length(_mats); _i < _n; _i++) {
    var _mm = _mats[_i];

    if (_mm == undefined) continue;
    var _key = __polygon_mat_key(_mm);
    var _found = false;

    for (var _j = 0, _nu = array_length(_uniq); _j < _nu; _j++) {
      if (_uniq[_j].key == _key) {
        _uniq[_j].n++;
        _found = true;
        break;
      }
    }

    if (!_found) {
      array_push(_uniq, { key: _key, nm: __polygon_mat_name(_mm), lb: string(__polygon_mat_shader_label(_mm)), mm: _mm, n: 1 });
    }
  }

  return _uniq;
}

// Opens the material inspector for one deduped entry.
function __polygon_mat_open(_ed, _u) {
  _ed.mat_inspect_key = _u.key;
  _ed.mat_inspector = _u;
  // Opened from an object/prefab inspector: Back button allowed.
  // Future generic entry points (material library) leave this unset.
  _ed.mat_inspector_back = true;
  var _context = [];

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) array_push(_context, _ed.sel[_i]);
  _ed.mat_inspector_sel = _context;
  _ed.mat_inspector_lib_sel = _ed.lib_sel;
}

// Draws one material row (sphere preview + name + shader + select).
function __polygon_imgui_mat_row(_ed, _u, _idx) {
  ImGui.PushID(_idx);
  var _tsz = 40;
  var _gap = 8;
  var _sx = ImGui.GetCursorScreenPosX();
  var _sy = ImGui.GetCursorScreenPosY();
  var _dl = ImGui.GetWindowDrawList();
  var _selected = variable_struct_exists(_ed, "mat_inspect_key") && _ed.mat_inspect_key == _u.key;
  var _row_w = ImGui.GetContentRegionAvailX();
  var _button_w = 54;
  var _label = __polygon_imgui_trunc_text(_u.nm, max(40, _row_w - _tsz - _gap - _button_w - 8));

  ImGui.Dummy(_row_w, _tsz);

  if (_selected && _dl != undefined) ImGui.DrawListAddRectFilled(_dl, _sx, _sy, _sx + _row_w, _sy + _tsz, make_colour_rgb(39, 51, 72));

  if (_sx != undefined && _sy != undefined && _dl != undefined) {
    var _spr = __polygon_mat_thumb(_ed, _u.mm);

    if (sprite_exists(_spr)) ImGui.DrawListAddImage(_dl, _spr, 0, _sx, _sy, _sx + _tsz, _sy + _tsz, c_white);
    ImGui.DrawListAddText(_dl, _sx + _tsz + _gap, _sy + (_tsz - ImGui.GetTextLineHeight()) * 0.5, _label, c_white);
  }

  ImGui.SameLine(max(0, _row_w - _button_w));
  var _pad_y = max(0, (_tsz - ImGui.GetFrameHeight()) * 0.5);
  ImGui.BeginGroup();
  ImGui.Dummy(0, _pad_y);

  if (ImGui.Button("Select", 0, 0)) __polygon_mat_open(_ed, _u);
  ImGui.Dummy(0, _pad_y);
  ImGui.EndGroup();

  ImGui.PopID();
}

// Draws one row per unique material (sphere preview + name + shader).
// Dedupes by display key (name + shader): clones share both.
function __polygon_imgui_mat_rows(_ed, _mats) {
  var _uniq = __polygon_mat_uniq(_mats);

  if (array_length(_uniq) == 0) {
    ImGui.TextDisabled("No materials");
    return;
  }

  ImGui.Spacing();

  for (var _k = 0, _n = array_length(_uniq); _k < _n; _k++) __polygon_imgui_mat_row(_ed, _uniq[_k], _k);
}

// ---------------------------------------------------------------------------
// Material inspector
// ---------------------------------------------------------------------------

// Dedicated read-only Material view shown inside the main Inspector panel.
// Organized in sections like the instance inspector. Standalone: it only
// reads the inspected material, never the object that opened it.
// (No Overview section: getShader(Forward) returns undefined in this GMRT
// build, so there is no real value to show.)
function __polygon_imgui_mat_inspector(_ed) {
  var _u = _ed.mat_inspector;

  if (!is_struct(_u) || _u.mm == undefined) return;
  var _mm = _u.mm;
  var _spr = __polygon_mat_thumb(_ed, _mm);
  __polygon_imgui_inspector_asset_header(_u.nm, "Material", _spr, 96);

  ImGui.Spacing();
  __polygon_imgui_sec_open();

  if (ImGui.CollapsingHeader("Base Color")) __polygon_imgui_mat_color_section(_ed, _mm);
  ImGui.Spacing();
  __polygon_imgui_sec_open();

  if (ImGui.CollapsingHeader("Textures")) __polygon_imgui_mat_tex_section(_ed, _mm);
  ImGui.Spacing();
  __polygon_imgui_sec_open();

  if (ImGui.CollapsingHeader("Transparency")) {
    __polygon_imgui_tex_field("Mode", __polygon_imgui_mat_alpha_label(_mm), "Alpha mode: Opaque writes opaque pixels, Mask discards pixels below the alpha cutoff, Blend enables true transparency.");
    ImGui.Spacing();
  }
}

// ---------------------------------------------------------------------------
// Texture inspector
// ---------------------------------------------------------------------------

// Draws one sampler row set for the texture inspector.
function __polygon_imgui_tex_sampler_section(_s) {
  __polygon_imgui_tex_field("Filter", _s.filter == true ? "Linear" : (_s.filter == false ? "Point" : undefined), "Magnification filter: Linear smooths texels, Point keeps them sharp (pixelated).");
  __polygon_imgui_tex_field("Repeat", _s.repeat_mode == true ? "On" : (_s.repeat_mode == false ? "Off" : undefined), "Wrap mode: On tiles the texture outside 0..1 UVs, Off clamps to the edge.");
  __polygon_imgui_tex_field("Max aniso", _s.aniso, "Anisotropic filtering level: higher preserves detail on surfaces at grazing angles.");
  __polygon_imgui_tex_field("Min mip", _s.min_mip, "Smallest mip level the sampler may use.");
  __polygon_imgui_tex_field("Max mip", _s.max_mip, "Largest mip level the sampler may use.");
  __polygon_imgui_tex_field("Mip bias", _s.bias, "LOD offset added when the sampler picks a mip level (negative = sharper).");
  __polygon_imgui_tex_field("Mip enable", _s.mip_enable, "Whether mipmapping is enabled for this texture.");
  __polygon_imgui_tex_field("Mip filter", _s.mip_filter, "Minification filter used when sampling across mip levels.");
}

// Dedicated read-only Texture view shown inside the main Inspector panel.
function __polygon_imgui_tex_inspector(_ed) {
  var _t = _ed.tex_inspector;

  if (!is_struct(_t)) return;
  var _thumb = undefined;

  if (is_numeric(_t.tex)) _thumb = __polygon_imgui_mat_tex_thumb(_ed, _t.tex);
  __polygon_imgui_inspector_asset_header(_t.label, "Texture", _thumb, 96);

  ImGui.Spacing();
  __polygon_imgui_sec_open();

  if (ImGui.CollapsingHeader("Overview")) {
    __polygon_imgui_tex_field("Dimensions", is_numeric(_t.tex) ? __polygon_imgui_tex_dims(_t.tex) : undefined);
    ImGui.Spacing();
  }

  ImGui.Spacing();
  __polygon_imgui_sec_open();

  if (ImGui.CollapsingHeader("Sampler")) {
    var _s = is_numeric(_t.tex) ? __polygon_imgui_tex_sampler(_t.tex) : undefined;

    if (_s == undefined) {
      ImGui.TextDisabled("Not exposed");
    } else {
      __polygon_imgui_tex_sampler_section(_s);
    }

    ImGui.Spacing();
  }
}
