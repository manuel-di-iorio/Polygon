// polygon_imgui_insp_anim — animation lists + click-to-open preview window.

// ---------------------------------------------------------------------------
// Model lookup and counts
// ---------------------------------------------------------------------------

// Draws animation section for asset nodes.
function __polygon_imgui_node_model(_ed, _node) {
  var _en = __polygon_registry_find(_ed, _node);

  if (_en == undefined || !is_string(_en.asset) || !is_array(_ed.assets))  return undefined;
  var _entry = __polygon_asset_get(_ed, _en.asset);
  return _entry == undefined ? undefined : _entry.model;
}

function __polygon_imgui_anim_count(_model) {
  if (_model == undefined)  return 0;
  var _count = _model.animationCount;
  return _count == undefined ? 0 : max(0, _count);
}

// ---------------------------------------------------------------------------
// Preview window state
// ---------------------------------------------------------------------------

// Checks if the preview card is open for model+index.
function __polygon_anim_ui_is_open(_ed, _model, _index) {
  if (!variable_struct_exists(_ed, "anim_ui") || !is_struct(_ed.anim_ui))  return false;
  return _ed.anim_ui.model == _model && _ed.anim_ui.index == _index;
}

// Toggles the preview window (click again to close, click another to switch).
// A plain window never eats outside clicks, so switching takes a single click.
function __polygon_anim_ui_toggle(_ed, _model, _index) {
  if (__polygon_anim_ui_is_open(_ed, _model, _index)) {
    _ed.anim_ui = undefined;
  } else {
    _ed.anim_ui = {
      model: _model,
      index: _index,
      playing: true,
      loop: true,
      speed: 1.0,
      restart: false,
      finished: false,
    };
    _ed.anim_win = { open: true };
    // Spawn under the mouse: recorded once, applied with Appearing cond.
    _ed.anim_win_at = [ ImGui.GetMousePosX() - 300, ImGui.GetMousePosY() + 10 ];
  }

  _ed.anim_row_clicked = true;
}

// Places the preview window under the cursor on first open (clamped on screen).
function __polygon_anim_win_place(_ed) {
  if (!variable_struct_exists(_ed, "anim_win_at") || !is_array(_ed.anim_win_at) || array_length(_ed.anim_win_at) < 2)  return;
  var _x = _ed.anim_win_at[0];
  var _y = _ed.anim_win_at[1];
  _ed.anim_win_at = undefined;

  if (is_real(_x) && is_real(_y) && is_real(_ed.gw) && is_real(_ed.gh)) {
    // Leave room for the 200px preview, playback controls, title bar and padding.
    // The window is auto-sized, so clamp against a conservative footprint.
    _x = clamp(_x, 0, max(0, _ed.gw - 260));
    _y = clamp(_y, 0, max(0, _ed.gh - 330));
    ImGui.SetNextWindowPos(_x, _y, ImGuiCond.Appearing);
  }
}

// Reads current preview playback time.
function __polygon_anim_pv_time(_ed) {
  if (variable_struct_exists(_ed, "anim_pv") && is_struct(_ed.anim_pv)) {
    var _pv = _ed.anim_pv;

    if (_pv.comp != undefined) {
      var _get = _pv.comp[$ "getTime"];

      if (_get != undefined) {
        var _t = method(_pv.comp, _get)();

        if (is_real(_t))  return _t;
      }
    } else if (is_real(_pv.t)) {
      return _pv.t;
    }
  }

  return 0;
}

// Draws play/pause, loop and speed controls.
function __polygon_anim_controls(_ui) {
  if (ImGui.Button(_ui.playing == true && _ui.finished != true ? "Pause" : "Play", 60, 0)) {
    if (_ui.finished == true) {
      _ui.restart = true;
      _ui.playing = true;
      _ui.finished = false;
    } else {
      _ui.playing = !_ui.playing;
    }
  }

  ImGui.SameLine();
  var _loop = ImGui.Checkbox("Loop", _ui.loop == true);

  if (_loop != (_ui.loop == true))  _ui.loop = _loop;
  ImGui.SameLine();
  ImGui.SetNextItemWidth(50);
  var _speed = __polygon_imgui_dragfloat("Speed", _ui.speed, 0.01);

  if (is_real(_speed))  _ui.speed = clamp(_speed, 0, 4);
}

// Draws the 256px preview as a non-modal floating window with playback controls.
// Unlike BeginPopup, this never blocks outside clicks: clicking another animation
// row switches the preview in one click, clicking anywhere else both activates
// the target and closes the preview.
function __polygon_anim_ui_window(_ed) {
  var _row_clicked = variable_struct_exists(_ed, "anim_row_clicked") && _ed.anim_row_clicked == true;
  _ed.anim_row_clicked = false;

  if (!variable_struct_exists(_ed, "anim_ui") || !is_struct(_ed.anim_ui) || _ed.anim_ui.model == undefined)  return;
  if (!variable_struct_exists(_ed, "anim_win") || !is_struct(_ed.anim_win)) {
    _ed.anim_win = { open: true };
  }

  var _ui = _ed.anim_ui;
  // First open: place the window under the cursor (clamped on screen).
  // Appearing = only the frame the window shows up, so switching animation
  // or moving the window afterwards never snaps it back.
  __polygon_anim_win_place(_ed);

  var _flags =
  ImGuiWindowFlags.AlwaysAutoResize |
  ImGuiWindowFlags.NoCollapse |
  ImGuiWindowFlags.NoDocking;
  ImGui.SetNextWindowBgAlpha(1);

  if (!ImGui.Begin("Animation Preview##anim_pv_win", _ed.anim_win, _flags)) {
    ImGui.End();

    if (_ed.anim_win.open != true)  _ed.anim_ui = undefined;
    return;
  }

  var _hovered = ImGui.IsWindowHovered();

  if (surface_exists(_ed.anim_surf)) {
    ImGui.Surface(_ed.anim_surf, c_white, 1, 200, 200);
  } else {
    ImGui.TextDisabled("Loading...");
  }

  var _dur = __polygon_anim_pv_duration(_ui.model, _ui.index);
  var _now = __polygon_anim_pv_time(_ed);

  if (_ui.loop == true && _dur > 0) {
    _now = _now mod _dur;
  } else {
    _now = min(_now, _dur);
  }

  ImGui.Text(string_format(_now, 0, 2) + "/" + string_format(_dur, 0, 2) + "s");
  ImGui.Spacing();
  __polygon_anim_controls(_ui);
  ImGui.End();

  if (_ed.anim_win.open != true) {
    _ed.anim_ui = undefined;
    return;
  }

  // Closed by clicking outside: drop the state so the preview stops.
  // The click itself is NOT eaten (non-modal window), it already reached
  // its target this frame — row switches set _row_clicked, window controls
  // are covered by _hv — so this only clears the preview.
  if (!_row_clicked && !_hovered && (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right)))  _ed.anim_ui = undefined;
}

// ---------------------------------------------------------------------------
// Clip lists
// ---------------------------------------------------------------------------

// Reads a clip display name ("Animation i" fallback).
function __polygon_anim_clip_name(_src, _idx) {
  var _clip = _src.getAnimation(_idx);

  if (_clip == undefined)  return undefined;
  var _name = _clip.path;
  return is_string(_name) ? _name : "Animation " + string(_idx);
}

// Draws a clickable animation clip list inside an open child.
function __polygon_anim_clip_list(_ed, _src, _count) {
  for (var _i = 0; _i < _count; _i++) {
    var _name = __polygon_anim_clip_name(_src, _i);

    if (_name == undefined)  continue;
    ImGui.PushID(_i);
    var _clicked = ImGui.Selectable(_name, __polygon_anim_ui_is_open(_ed, _src, _i));
    ImGui.PopID();

    if (_clicked)  __polygon_anim_ui_toggle(_ed, _src, _i);
  }
}

function __polygon_imgui_anim_sec(_ed, _node) {
  __polygon_imgui_anim_list(_ed, __polygon_imgui_node_model(_ed, _node), "##node_anim_list");
}

// Draws the shared animation clip list for a model source.
function __polygon_imgui_anim_list(_ed, _src, _id) {
  if (_src == undefined)  return;
  var _count = __polygon_imgui_anim_count(_src);

  if (_count <= 0)  return;
  ImGui.Indent(8);

  if (ImGui.BeginChild(_id, 0, min(180, _count * 24), ImGuiChildFlags.Borders))  __polygon_anim_clip_list(_ed, _src, _count);
  ImGui.EndChild();

  ImGui.Unindent(8);
}

// Draws animation section for prefab assets.
function __polygon_imgui_prefab_anim_sec(_ed, _entry) {
  __polygon_imgui_anim_list(_ed, (is_struct(_entry) ? _entry[$ "model"] : undefined), "##prefab_anim_list");
}
