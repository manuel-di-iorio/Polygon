// poly_imgui_assets — Models panel (list/cards), filter, drag source.

// ---------------------------------------------------------------------------
// Shared row bits
// ---------------------------------------------------------------------------

// Checks if an entry matches the lowercase filter (key or file name).
function __poly_asset_visible(_entry, _flt) {
  if (!is_struct(_entry)) return false;
  if (variable_struct_exists(_entry, "primitive") && _entry.primitive == true) return false;
  if (_flt == "") return true;
  if (string_pos(_flt, string_lower(_entry.key)) > 0) return true;
  return string_pos(_flt, string_lower(__poly_display_from_key(_entry.key))) > 0;
}

// Selects a library entry and clears the scene selection.
function __poly_asset_pick(_ed, _idx) {
  _ed.lib_sel = _idx;
  __poly_sel_clear(_ed);
}

// Starts a drag source for a library entry.
function __poly_asset_drag_begin(_ed, _entry, _idx) {
  if (!ImGui.BeginDragDropSource(ImGuiDragDropFlags.SourceNoPreviewTooltip)) return;
  ImGui.SetDragDropPayload("POLYGON_ASSET", _idx);
  ImGui.EndDragDropSource();

  if (_ed.drag_lib == undefined || _ed.drag_lib.idx != _idx) {
    _ed.drag_lib = { asset: _entry, idx: _idx };
    _ed.drag_moved = false;
    _ed.press_x = device_mouse_x_to_gui(0);
    _ed.press_y = device_mouse_y_to_gui(0);
  }
}

// Shows the model tooltip (delayed) with file name text.
function __poly_asset_tip(_entry, _hovering) {
  __poly_imgui_tip_delayed("model|" + _entry.key, __poly_display_from_key(_entry.key), _hovering);
}

// Calls a no-arg ImGui query, returning a fallback when unavailable.
function __poly_imgui_safe(_method, _fallback) {

  var _fn = ImGui[$ _method];

  if (_fn != undefined) return method(ImGui, _fn)();
  return _fallback;
}

// ---------------------------------------------------------------------------
// List view
// ---------------------------------------------------------------------------

// Lists filterable draggable model assets.
function __poly_imgui_asset_list(_ed) {
  var _ui = _ed.imgui;

  if (!variable_struct_exists(_ui, "models_view")) _ui.models_view = "cards";
  var _avail = ImGui.GetContentRegionAvailX();
  var _filter_w = min(170, max(80, _avail - 108));
  ImGui.SameLine(max(0, _avail - (_filter_w + 108)));
  ImGui.SetNextItemWidth(_filter_w);
  if (!variable_struct_exists(_ui, "models_focus_search")) _ui.models_focus_search = false;
  var _want_search = _ui.models_focus_search == true;
  _ui.models_focus_search = false;
  _ui.filter = __poly_imgui_text_hint("##filter", "Filter models...", _ui.filter, _want_search);
  ImGui.SameLine();

  if (__poly_imgui_small_btn("List", _ui.models_view == "list")) _ui.models_view = "list";
  ImGui.SameLine();

  if (__poly_imgui_small_btn("Cards", _ui.models_view == "cards")) _ui.models_view = "cards";
  ImGui.Separator();
  var _flt = string_lower(_ui.filter);

  if (_ui.models_view == "cards") {
    __poly_imgui_asset_cards(_ed, _flt);
    __poly_models_bg_step(_ed);
    return;
  }

  for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) {
    var _entry = _ed.assets[_i];

    if (!__poly_asset_visible(_entry, _flt)) continue;
    ImGui.PushID(_i);

    if (ImGui.Selectable(__poly_display_from_key(_entry.key), _ed.lib_sel == _i)) if (_ed.drag_lib == undefined) __poly_asset_pick(_ed, _i);
    __poly_asset_tip(_entry, _ed.drag_lib == undefined && ImGui.IsItemHovered());
    __poly_asset_drag_begin(_ed, _entry, _i);

    ImGui.PopID();
  }

  __poly_models_bg_step(_ed);
}

// Background click in the Models panel deselects everything.
function __poly_models_bg_step(_ed) {
  var _down = false;
  _down = ImGui.IsMouseDown(0);
  var _was_down = _ed.models_mdown == true;
  _ed.models_mdown = _down;

  if (_ed.drag_lib != undefined) {
    _ed.models_bg = undefined;
    return;
  }

  if (_ed.models_bg == undefined) {
    if (!_down || _was_down) return;
    var _hover_win = __poly_imgui_safe("IsWindowHovered", false);

    if (!_hover_win) return;
    if (__poly_imgui_safe("IsAnyItemHovered", true)) return;
    _ed.models_bg = { x0: ImGui.GetMousePosX(), y0: ImGui.GetMousePosY() };
    return;
  }

  if (_down) return;
  var _press = _ed.models_bg;
  _ed.models_bg = undefined;

  if (max(abs(ImGui.GetMousePosX() - _press.x0), abs(ImGui.GetMousePosY() - _press.y0)) > 6) return;
  if (__poly_imgui_safe("IsAnyItemHovered", true)) return;
  _ed.lib_sel = undefined;
  __poly_sel_clear(_ed);
}

// Draws small button with active highlight.
function __poly_imgui_small_btn(_label, _active) {
  return __poly_imgui_small_btn_w(_label, _active, 46);
}

// Draws small button with active highlight and custom width.
function __poly_imgui_small_btn_w(_label, _active, _w) {
  var _pushed = 0;

  if (_active) {
    ImGui.PushStyleColor(ImGuiCol.Button, make_colour_rgb(47, 111, 237), 1);
    _pushed++;
  }

  var _hit = ImGui.Button(_label, _w, 0);
  __poly_imgui_pop(_pushed);
  return _hit;
}

// ---------------------------------------------------------------------------
// Cards view
// ---------------------------------------------------------------------------

// Draws assets in grid card layout.
function __poly_imgui_asset_cards(_ed, _flt) {
  var _card = 60;
  var _gap = 12;
  var _avail = ImGui.GetContentRegionAvailX();
  var _cols = max(1, floor((_avail + _gap) / (_card + _gap)));
  var _shown = 0;

  for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) {
    if (!__poly_asset_visible(_ed.assets[_i], _flt)) continue;
    if (_shown > 0 && _shown mod _cols != 0) ImGui.SameLine(0, _gap);
    __poly_imgui_asset_card(_ed, _ed.assets[_i], _i, _card);
    _shown++;
  }
}

// Shortens object names longer than 20 chars, appending "..".
function __poly_short_name(_name) {
  if (!is_string(_name)) return _name;
  if (string_length(_name) > 20) return string_copy(_name, 1, 20) + "..";
  return _name;
}

// Truncates text to fit pixel width.
function __poly_imgui_trunc_text(_text, _maxw) {
  static _cache = {};
  var _ck = _text + "|" + string(_maxw) + "|12";

  if (variable_struct_exists(_cache, _ck)) return _cache[$ _ck];
  var _out = _text;

  if (_maxw > 8 && string_length(_text) > 3) {
    var _full = ImGui.CalcTextWidth(_text);

    if (_full > _maxw) {
      _out = "..";
      var _len = string_length(_text) - 1;

      while (_len > 1) {
        var _try = string_copy(_text, 1, _len) + "..";
        var _w = ImGui.CalcTextWidth(_try);

        if (_w <= _maxw) {
          _out = _try;
          break;
        }

        _len--;
      }
    }
  }

  _cache[$ _ck] = _out;
  return _out;
}

// Draws the card thumbnail box and caption.
function __poly_imgui_card_face(_entry, _hov, _sel, _x, _y, _cs) {
  var _thumb = -1;

  if (variable_struct_exists(_entry, "thumb") && sprite_exists(_entry.thumb)) _thumb = _entry.thumb;
  var _dl = ImGui.GetWindowDrawList();

  if (_thumb != -1) {
    ImGui.DrawListAddImage(_dl, _thumb, 0, _x, _y, _x + _cs, _y + _cs, c_white);
  } else {
    var _fill = _hov ? make_colour_rgb(84, 96, 120) : make_colour_rgb(70, 80, 100);
    ImGui.DrawListAddRectFilled(_dl, _x, _y, _x + _cs, _y + _cs, _fill);
  }

  var _edge = (_hov || _sel) ? make_colour_rgb(120, 140, 175) : make_colour_rgb(50, 58, 76);
  ImGui.DrawListAddRect(_dl, _x, _y, _x + _cs, _y + _cs, _edge);
  ImGui.SetWindowFontScale(12 / 13);

  var _caption = __poly_imgui_trunc_text(__poly_display_from_key(_entry.key), _cs - 6);
  ImGui.DrawListAddText(_dl, _x + 4, _y + _cs + 2, _caption, c_white);
  ImGui.SetWindowFontScale(1);
}

// Draws draggable asset thumbnail card.
function __poly_imgui_asset_card(_ed, _entry, _idx, _cs) {
  var _text_h = 16;
  var _pad = 4;
  var _sx = ImGui.GetCursorScreenPosX();
  var _sy = ImGui.GetCursorScreenPosY();
  var _dl = ImGui.GetWindowDrawList();
  ImGui.PushID(_idx);
  var _clicked = ImGui.InvisibleButton("##card", _cs, _pad + _cs + _text_h + _pad);

  var _hov = ImGui.IsItemHovered();
  var _sel = _ed.lib_sel == _idx;

  if (_sx != undefined && _dl != undefined) __poly_imgui_card_face(_entry, _hov, _sel, _sx, _sy + _pad, _cs);
  __poly_asset_tip(_entry, _ed.drag_lib == undefined && _hov);

  if (_clicked && _ed.drag_lib == undefined) __poly_asset_pick(_ed, _idx);
  __poly_asset_drag_begin(_ed, _entry, _idx);

  ImGui.PopID();
}
