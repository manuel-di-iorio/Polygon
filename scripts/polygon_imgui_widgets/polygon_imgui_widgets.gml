// polygon_imgui_widgets — primitive widgets, buttons, style helpers.
// Pads string with spaces to fixed length.
function __polygon_imgui_pad(_base) {
  if (!is_string(_base))  _base = "";
  var _buf = _base;

  while (string_length(_buf) < 255)  _buf += " ";
  return _buf;
}

// Renders editable text input with focus tracking.
function __polygon_imgui_text(_key, _label, _val) {
  static _active = {};
  static _bufs = {};
  var _base = _val;

  if (!is_string(_base))  _base = "";
  var _was = _active[$ _key] == true;

  if (!_was || !variable_struct_exists(_bufs, _key))  _bufs[$ _key] = __polygon_imgui_pad(_base);
  var _out = ImGui.InputText(_label, _bufs[$ _key], ImGuiInputTextFlags.AutoSelectAll);
  var _now = ImGui.IsItemActive();

  _active[$ _key] = _now;

  if (!is_string(_out)) {
    return { text: _base, active: _now, was_active: _was };
  }

  _bufs[$ _key] = _out;
  return { text: string_trim(_out), active: _now, was_active: _was };
}

// Edits float via drag control.
function __polygon_imgui_dragfloat(_label, _val, _speed) {
  var _out = ImGui.DragFloat(_label, _val, _speed, 0, 0);

  if (!is_real(_out))  return _val;
  return _out;
}

// Renders text input showing placeholder hint.
function __polygon_imgui_text_hint(_id_label, _hint, _val) {
  static _active = {};
  static _bufs = {};
  var _base = _val;

  if (!is_string(_base))  _base = "";
  var _was = _active[$ _id_label] == true;

  if (!_was || !variable_struct_exists(_bufs, _id_label))  _bufs[$ _id_label] = __polygon_imgui_pad(_base);
  var _out = ImGui.InputTextWithHint(
    _id_label,
    _hint,
    _bufs[$ _id_label],
    ImGuiInputTextFlags.AutoSelectAll,
  );
  var _now = ImGui.IsItemActive();

  _active[$ _id_label] = _now;

  if (!is_string(_out))  return _base;
  _bufs[$ _id_label] = _out;
  return string_trim(_out);
}

// Draws toolbar button with tooltip and highlight.
function __polygon_imgui_tool_btn(_tip, _label, _active, _h = 0, _w = 0) {
  var _pushed = 0;

  if (_active) {
    ImGui.PushStyleColor(ImGuiCol.Button, make_colour_rgb(47, 111, 237), 1);
    _pushed++;
  }

  var _hit = ImGui.Button(_label, _w, _h);
  __polygon_imgui_pop(_pushed);
  __polygon_imgui_tip_delayed("tool|" + _label, _tip, ImGui.IsItemHovered());

  return _hit;
}

// Draws small icon button with tooltip and highlight.
function __polygon_imgui_icon_btn(_id, _tip, _active, _fb, _spr, _w = -1, _h = -1) {
  static _cache = {};

  if (!variable_struct_exists(_cache, _spr))  _cache[$ _spr] = asset_get_index(_spr);
  var _sp = _cache[$ _spr];

  if (_sp == -1 || _sp == undefined)  _sp = asset_get_index("sprPolygonEditorIconObject");
  var _hit = false;

  if (_sp != -1 && _sp != undefined) {
    var _iw = _w;
    var _ih = _h;

    if (_iw < 0)  _iw = sprite_get_width(_sp);
    if (_ih < 0)  _ih = sprite_get_height(_sp);
    if (_active) {
      ImGui.PushStyleColor(ImGuiCol.Button, make_colour_rgb(47, 111, 237), 1);
    } else {
      ImGui.PushStyleColor(ImGuiCol.Button, c_black, 0);
    }

    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, make_colour_rgb(47, 111, 237), 0.35);
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, make_colour_rgb(47, 111, 237), 0.5);
    _hit = ImGui.ImageButton(_id, _sp, 0, c_white, 1, c_black, 0, _iw, _ih);
    __polygon_imgui_pop(3);
  } else {
    _hit = ImGui.SmallButton(_fb);
  }

  __polygon_imgui_tip_delayed("icon|" + _id, _tip, ImGui.IsItemHovered());

  return _hit;
}

// Pops specified number of style colors.
function __polygon_imgui_pop(_n) {
  for (var _i = 0; _i < _n; _i++)  ImGui.PopStyleColor();
}

// Opens a centered, fixed-size modal window (title colors included).
// Returns ImGui.Begin result; caller must always call __polygon_modal_end,
// even when Begin returns false.
function __polygon_modal_begin(_ed, _title, _w, _h, _handle) {
  static _title_bg = make_colour_rgb(33, 36, 47);
  var _gw = max(640, _ed.gw);
  var _gh = max(400, _ed.gh);
  ImGui.SetNextWindowPos(_gw * 0.5 - _w * 0.5, _gh * 0.5 - _h * 0.5, ImGuiCond.Always);
  ImGui.SetNextWindowSize(_w, _h, ImGuiCond.Always);
  ImGui.SetNextWindowBgAlpha(1);
  ImGui.PushStyleColor(ImGuiCol.TitleBg, _title_bg, 1);
  ImGui.PushStyleColor(ImGuiCol.TitleBgActive, _title_bg, 1);
  return ImGui.Begin(_title, _handle, ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoResize);
}

// Closes a modal opened with __polygon_modal_begin.
function __polygon_modal_end() {
  ImGui.End();
  __polygon_imgui_pop(2);
}

// Sets ImGui style color value.
function __polygon_imgui_style_color(_col, _rgb, _alpha) {
  ImGui.SetStyleColor(_col, _rgb, _alpha);
  return true;
}

// Checks if panels should lock movement during viewport gestures.
function __polygon_imgui_lock_move(_ed) {
  return _ed.input_owner != undefined;
}

