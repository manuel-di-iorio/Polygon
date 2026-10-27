# ImGui in GameMaker

Guide to the Dear ImGui compatibility module integrated into GMRT, based on the official project [YoYoGames/ImGUI-Sample](https://github.com/YoYoGames/ImGUI-Sample), from the demo GML and from the reference included.

## Contents

- [What the binding is](#what-the-binding-is)
- [Quick start](#quick-start)
- [Fundamental rules](#fundamental-rules)
- [Windows and layout](#windows-and-layout)
- [Widgets](#widgets)
- [Menus, popups and tooltips](#menus-popups-and-tooltips)
- [Tables and tabs](#tables-and-tabs)
- [Docking](#docking)
- [Drag and drop](#drag-and-drop)
- [Images, sprites and surfaces](#images-sprites-and-surfaces)
- [Fonts and Unicode](#fonts-and-unicode)
- [Styles and colors](#styles-and-colors)
- [Draw lists](#draw-lists)
- [Multi-select](#multi-select)
- [Input and queries](#input-and-queries)
- [GML helpers](#gml-helpers)
- [Enums](#enums)
- [Performance, common errors and cleanup](#performance-common-errors-and-cleanup)
- [API map](#api-map)
- [Sources](#sources)

## What the binding is

Dear ImGui is an **immediate-mode** GUI: the interface is declared again every frame. GMRT exposes the binding as the global static `ImGui` class; no extension is present in the repository.

```text
Step event GML
  └── ImGui.Begin / widget / ImGui.End
      └── binding GMRT
          └── Dear ImGui
              └── GameMaker graphics and input backend
```

The binding manages frames, input, and rendering automatically. The application instead keeps the domain values: text, sliders, selections, open windows, and displayed data.

The official demo uses a single object and builds the entire UI in the Step event. The window is 1366x768 and docking is enabled through application state.

## Quick start

### Create

```gml
window_state = { open: true };
player_name = "Player";
volume = 0.8;
show_demo = false;
```

The `ImGui*` enums are plain GML: copy them from the official Create event `#region Enums` block, or use the ones already included in this project in `scripts/imgui_enums`.

### Step

```gml
if (window_state.open) {
  if (ImGui.Begin("Settings", window_state)) {
    ImGui.Text("ImGui " + ImGui.GetVersion());
    player_name = ImGui.InputText("Name", player_name);
    volume = ImGui.SliderFloat("Volume", volume, 0, 1);

    if (ImGui.Button("Reset")) {
      volume = 0.8;
    }
  }
  ImGui.End();
}

if (show_demo) {
  show_demo = ImGui.ShowDemoWindow(show_demo);
}
```

`End()` must be called after every `Begin()`, even when `Begin()` returns `false`. The same rule applies to the other Begin/End pairs unless the reference states otherwise.

## Fundamental rules

### 1. The UI is rebuilt each frame

Do not create a persistent control hierarchy. Keep only the data:

```gml
// Persistent application state
health = ImGui.SliderInt("Health", health, 0, 100);
```

### 2. Scalar values are often returned

```gml
enabled = ImGui.Checkbox("Enabled", enabled);
count = ImGui.DragInt("Count", count, 1, 0, 100);
label = ImGui.InputText("Label", label);
```

Vector/array variants modify the passed array according to their specific signature:

```gml
position = [0, 0, 0];
ImGui.DragFloat3("Position", position, 0.1);
```

Always check the signature in the reference: do not assign the result of a function documented as `void`.

### 3. Some functions modify structs

```gml
window_state = { open: true };

if (ImGui.Begin("Closable", window_state)) {
  ImGui.Text("Content");
}
ImGui.End();
```

When the user presses X, `window_state.open` becomes `false`. If persistence is needed, do not recreate the literal struct from scratch every frame.

### 4. IDs must be unique

Text after `##` participates in the ID but is not displayed:

```gml
ImGui.Button("Delete##node_12");
ImGui.Button("Delete##node_27");
```

For loops and reusable components, also use `PushID()`/`PopID()`:

```gml
for (var i = 0; i < array_length(items); ++i) {
  ImGui.PushID(i);
  ImGui.Selectable(items[i]);
  ImGui.PopID();
}
```

### 5. Stacks must be balanced

Every `Push*`, `Begin*`, or stack opening must have its matching `Pop*`/`End*` in the same frame. Do not return early from a function while leaving a window, table, child, popup, style, font, or ID open.

### 6. British and American spelling

The `Color`/`Colour` and `StyleColors*`/`StyleColours*` forms are aliases in the binding. Choose one convention and keep it throughout the project.

## Windows and layout

### Windows

```gml
ImGui.SetNextWindowPos(20, 20, ImGuiCond.FirstUseEver);
ImGui.SetNextWindowSize(420, 300, ImGuiCond.FirstUseEver);

if (
  ImGui.Begin(
    "Inspector",
    inspector_state,
    ImGuiWindowFlags.NoCollapse | ImGuiWindowFlags.MenuBar
  )
) {
  ImGui.Text("Selected node");
}
ImGui.End();
```

Main queries:

- `IsWindowAppearing()`, `IsWindowCollapsed()`;
- `IsWindowFocused(flags)`, `IsWindowHovered(flags)`;
- `GetWindowX/Y()`, `GetWindowWidth/Height()`;
- `SetWindowPos/Size/Collapsed/Focus()` by window name;
- `SetNextWindowPos/Size/Collapsed/Focus/BgAlpha()` before `Begin()`.

### Titlebar-only moving

The binding exposes no `ConfigWindowsMoveFromTitleBarOnly`, so windows can
be dragged from any empty area by default. To restrict moving to the
titlebar, pass a dynamic `NoMove` flag instead: before each `Begin()`,
compare the cached window rect from the previous frame against the mouse
position - `NoMove` when the cursor is over the body, no flag on the
titlebar or outside. Latch the flags while the left button is held so a
titlebar drag is never cancelled mid-gesture:

```gml
var flags = flags_for_cached_rect(
  cached_rect,
  ImGui.GetMousePosX(),
  ImGui.GetMousePosY()
);
if (!ImGui.Begin("Scene", win_state, flags)) {
  ImGui.End();
  return;
}
cache_rect_from(
  ImGui.GetWindowX(),
  ImGui.GetWindowY(),
  ImGui.GetWindowWidth(),
  ImGui.GetWindowHeight(),
  ImGui.GetFrameHeight()
);
```

Windows without a titlebar get a permanent `NoMove` since there is no
titlebar to drag from.

### Child region

```gml
if (
  ImGui.BeginChild(
    "Hierarchy",
    280,
    0,
    ImGuiChildFlags.Borders | ImGuiChildFlags.ResizeX
  )
) {
  ImGui.Text("Nodes");
}
ImGui.EndChild();
```

Values of `0` use the available space; negative values leave the indicated margin according to Dear ImGui semantics.

### Layout

```gml
ImGui.Text("X");
ImGui.SameLine();
ImGui.SetNextItemWidth(120);
x_value = ImGui.DragFloat("##x", x_value, 0.1);

ImGui.SeparatorText("Transform");
ImGui.Indent(16);
ImGui.TextWrapped(description);
ImGui.Unindent(16);
```

Useful functions:

- rows and space: `SameLine`, `NewLine`, `Spacing`, `Dummy`, `Separator`, `SeparatorText`;
- groups: `BeginGroup`, `EndGroup`, `Indent`, `Unindent`;
- cursor: `GetCursor*` and `SetCursor*` getters/setters;
- dimensions: `GetContentRegionAvailX/Y`, `GetTextLineHeight`, `GetFrameHeight`;
- width item: `SetNextItemWidth`, `PushItemWidth`, `PopItemWidth`.

## Widgets

### Text

```gml
ImGui.Text("Plain text");
ImGui.TextDisabled("Unavailable");
ImGui.TextWrapped(long_text);
ImGui.TextColored("Warning", c_yellow);
ImGui.LabelText("FPS", string(fps_real));
ImGui.BulletText("One item");
```

`CalcTextWidth()` and `CalcTextHeight()` measure text using the active font.

### Buttons and booleans

```gml
if (ImGui.Button("Apply", 100, 0)) {
  apply_changes();
}
if (ImGui.SmallButton("Reset")) {
  reset_values();
}
if (ImGui.ArrowButton("Next", ImGuiDir.Right)) {
  next_item();
}

visible = ImGui.Checkbox("Visible", visible);
selected_mode = ImGui.RadioButton("Local", selected_mode == 0)
  ? 0
  : selected_mode;
```

Also available are `InvisibleButton`, `ColorButton`, `ProgressBar`, `Bullet`, `TextLink`, and `TextLinkOpenURL`.

### Slider and drag

```gml
speed = ImGui.SliderFloat("Speed", speed, 0, 20, "%.2f");
count = ImGui.SliderInt("Count", count, 0, 100);
angle = ImGui.SliderAngle("Angle", angle, -180, 180);

position_x = ImGui.DragFloat("X", position_x, 0.05, -1000, 1000);
ImGui.DragFloat3("Position", position, 0.05);
```

The float/int families include 2-, 3-, and 4-component variants. `ImGuiSliderFlags.Logarithmic` is useful for very wide ranges.

### Input

```gml
name = ImGui.InputText("Name", name);
query = ImGui.InputTextWithHint("##search", "Search...", query);
notes = ImGui.InputTextMultiline("Notes", notes, 400, 120);

value = ImGui.InputFloat("Value", value, 0.1, 1.0, "%.3f");
count = ImGui.InputInt("Count", count, 1, 10);
```

Common flags: `CharsDecimal`, `CharsHexadecimal`, `CharsNoBlank`, `ReadOnly`, `Password`, `EnterReturnsTrue`.

### Combo, list box and selectable

```gml
current = ImGui.Combo("Asset", current, asset_names);

if (ImGui.BeginCombo("Mode", modes[current])) {
  for (var i = 0; i < array_length(modes); ++i) {
    if (ImGui.Selectable(modes[i], current == i)) {
      current = i;
    }
  }
  ImGui.EndCombo();
}
```

`BeginListBox`/`EndListBox` build custom lists. `Selectable` is the basic building block for multi-select, custom menus, and hierarchies.

### Tree and collapsing header

```gml
if (ImGui.TreeNodeEx("Transform", ImGuiTreeNodeFlags.DefaultOpen)) {
  ImGui.Text("Position");
  ImGui.TreePop();
}

if (ImGui.CollapsingHeader("Rendering")) {
  ImGui.Text("Material settings");
}
```

Only an open `TreeNode*()` requires `TreePop()`. `CollapsingHeader()` does not.

### Colors

```gml
tint = ImGui.ColorEdit3("Tint", tint);

rgba = new ImColor(c_aqua, 0.75);
ImGui.ColorPicker4s("Accent", rgba, ImGuiColorEditFlags.DisplayHex);
```

Packed variants work with integer colors; variants with the `s` suffix work with structs such as `ImColor`.

### Plot

```gml
ImGui.PlotLines("Frame time", samples, 0, "ms", 0, 33, 300, 80);
ImGui.PlotHistogram("Counts", bins, 0, "", 0, max_count, 300, 80);
```

## Menus, popups and tooltips

### Menu bar

```gml
if (ImGui.BeginMainMenuBar()) {
  if (ImGui.BeginMenu("File")) {
    if (ImGui.MenuItem("Save", "Ctrl+S")) {
      save_scene();
    }
    if (ImGui.MenuItem("Quit")) {
      game_end();
    }
    ImGui.EndMenu();
  }
  ImGui.EndMainMenuBar();
}
```

For an internal menu bar, add `ImGuiWindowFlags.MenuBar` and use `BeginMenuBar()`/`EndMenuBar()`.

### Popup and modal

```gml
if (ImGui.Button("Delete")) {
  ImGui.OpenPopup("Confirm delete");
}

if (
  ImGui.BeginPopupModal(
    "Confirm delete",
    modal_state,
    ImGuiWindowFlags.AlwaysAutoResize
  )
) {
  ImGui.Text("This action cannot be undone.");

  if (ImGui.Button("Confirm")) {
    delete_selection();
    ImGui.CloseCurrentPopup();
  }
  ImGui.SameLine();
  if (ImGui.Button("Cancel")) {
    ImGui.CloseCurrentPopup();
  }
  ImGui.EndPopup();
}
```

Context menu available: `BeginPopupContextItem`, `BeginPopupContextWindow` and `BeginPopupContextVoid`. All close with `EndPopup()` when return `true`.

### Tooltip

```gml
ImGui.Button("?");
if (ImGui.IsItemHovered()) {
  ImGui.SetTooltip("Help text");
}
```

For complex content, use `BeginTooltip()`/`EndTooltip()` or `BeginItemTooltip()`/`EndTooltip()`.

## Tables and tabs

### Tables

```gml
var flags =
  ImGuiTableFlags.Borders |
  ImGuiTableFlags.RowBg |
  ImGuiTableFlags.Resizable |
  ImGuiTableFlags.ScrollY;

if (ImGui.BeginTable("Assets", 3, flags, 0, 300)) {
  ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch);
  ImGui.TableSetupColumn("Type", ImGuiTableColumnFlags.WidthFixed, 90);
  ImGui.TableSetupColumn("Visible", ImGuiTableColumnFlags.WidthFixed, 60);
  ImGui.TableSetupScrollFreeze(0, 1);
  ImGui.TableHeadersRow();

  for (var row = 0; row < array_length(assets); ++row) {
    ImGui.TableNextRow();
    ImGui.TableSetColumnIndex(0);
    ImGui.Text(assets[row].name);
    ImGui.TableSetColumnIndex(1);
    ImGui.Text(assets[row].type);
    ImGui.TableSetColumnIndex(2);
    assets[row].visible = ImGui.Checkbox(
      "##visible_" + string(row),
      assets[row].visible
    );
  }
  ImGui.EndTable();
}
```

Other APIs: `TableNextColumn`, `TableGetColumnIndex/Count/Name/Flags`, `TableSetColumnEnabled`, `TableSetBgColor`, and sort specs. With scrolling and many records, pair the table with a clipper or virtualization if available in the current version.

### Tab

```gml
if (ImGui.BeginTabBar("Inspector tabs", ImGuiTabBarFlags.Reorderable)) {
  if (ImGui.BeginTabItem("Transform")) {
    draw_transform_tab();
    ImGui.EndTabItem();
  }
  if (ImGui.BeginTabItem("Material")) {
    draw_material_tab();
    ImGui.EndTabItem();
  }
  ImGui.EndTabBar();
}
```

`TabItemButton()` adds a command to the bar without creating tab content.

## Docking

Docking is enabled through the config flags and driven per frame: create a
dockspace over the viewport with a stable ID, then declare windows as usual.

### Simple dockspace

```gml
ImGui.DockSpaceOverViewport(
  ImGui.GetID("MyDockspace"),
  0,
  ImGuiDockNodeFlags.PassthruCentralNode
);
```

Use an explicit stable ID (not `0`) when you need to address the node later
with the DockBuilder API. `DockSpaceOverViewport()` returns the root node ID.

### Programmatic layout

```gml
var dock_id = ImGui.GetID("EditorDockspace");

if (!dock_layout_created) {
  ImGui.DockBuilderRemoveNode(dock_id);
  ImGui.DockBuilderAddNode(dock_id, ImGuiDockNodeFlags.DockSpace);
  ImGui.DockBuilderSetNodePos(dock_id, 0, 30);
  ImGui.DockBuilderSetNodeSize(
    dock_id,
    window_get_width(),
    window_get_height() - 30
  );

  // Carve the full-height side first, then the bottom strip, then the side.
  var s1 = ImGui.DockBuilderSplitNode(dock_id, ImGuiDir.Left, 0.19);
  var left_id = s1[0];
  var rest1 = s1[array_length(s1) - 1];
  var s2 = ImGui.DockBuilderSplitNode(rest1, ImGuiDir.Down, 0.32);
  var bottom_id = s2[0];
  var rest2 = s2[array_length(s2) - 1];
  var s3 = ImGui.DockBuilderSplitNode(rest2, ImGuiDir.Right, 0.26);
  var right_id = s3[0];

  ImGui.DockBuilderDockWindow("Hierarchy", right_id);
  ImGui.DockBuilderDockWindow("Assets", bottom_id);
  ImGui.DockBuilderDockWindow("Scene", left_id);
  ImGui.DockBuilderFinish(dock_id);
  dock_layout_created = true;
}

ImGui.DockSpace(dock_id);
```

- `DockBuilderSplitNode()` returns an array: index `0` is the node carved
  off "at dir", the last element is the remainder to keep splitting. Index
  defensively (`rest = s[array_length(s) - 1]`) instead of hardcoding
  positions, since the exact shape varies across binding versions.
- Split order defines the geometry; `DockWindow` call order defines tab order
  when several windows share one node (first call = first tab).
- Names passed to `DockBuilderDockWindow()` must match the names used by
  `Begin()` exactly.
- `SetNodePos/Size` on the root can reserve room for the main menu bar;
  docked `SetNextWindowPos/Size` calls are ignored while docked, so keeping
  them as floating fallbacks is harmless - undocked windows keep working.
- A window with a dynamic `NoMove` flag (body locked, titlebar free) still
  undocks from its tab/titlebar drag, so titlebar-only moving composes with
  docking.
- `ImGuiDockNodeFlags.DockSpace` (`1 << 10`) is missing from some sample GML
  enum blocks; add it if yours lacks it.

API related: `SetNextWindowDockID`, `SetNextWindowClass`, `GetWindowDockID`,
`IsWindowDocked`, `DockBuilderGetNode`, `DockBuilderFinish`,
`DockBuilderSetNodePos/Size`, `DockBuilderRemoveNodeChildNodes`,
`DockBuilderRemoveNodeDockedWindows`, `DockBuilderCopyDockSpace` and
`DockBuilderCopyNode`.

## Drag and drop

```gml
// Source: immediately after the draggable item.
if (ImGui.BeginDragDropSource()) {
  ImGui.SetDragDropPayload("ASSET", asset_index);
  ImGui.Text(asset_names[asset_index]);
  ImGui.EndDragDropSource();
}

// Target: immediately after the destination item.
if (ImGui.BeginDragDropTarget()) {
  var payload = ImGui.AcceptDragDropPayload("ASSET");
  if (payload != undefined) {
    assign_asset(payload);
  }
  ImGui.EndDragDropTarget();
}
```

The type string is the contract between source and target. Keep it short and stable. The demo shows copy, move, and swap modes implemented in application code: ImGui transports the payload but does not decide the operation semantics.

## Images, sprites and surfaces

The binding accepts GameMaker resources directly:

```gml
ImGui.Image(spr_thumbnail, 0, c_white, 1, 64, 64);

if (
  ImGui.ImageButton(
    "asset_12",
    spr_thumbnail,
    0,
    c_white,
    1,
    c_black,
    0,
    64,
    64
  )
) {
  select_asset(12);
}

if (surface_exists(view_surface)) {
  ImGui.Surface(view_surface, c_white, 1, 640, 360);
}
```

UVs allow cropping and flipping. Dimensions of `0` use the resource's native dimensions. Check `surface_exists()` because surfaces can be lost and recreated by the runtime.

## Fonts and Unicode

The fonts included in `datafiles/fonts/` are read at runtime from `assets/fonts/`:

```gml
font_ui = ImGui.AddFontFromFileTTF(
  "assets/fonts/NotoSans-Main.ttf",
  18,
  {},
  [0x0020, 0x00ff, 0x0400, 0x04ff]
);
```

Usage:

```gml
ImGui.PushFont(font_ui);
ImGui.Text("Custom font");
ImGui.PopFont();
```

The demo includes Noto Sans Main, Noto Sans Hiragana Bold, and Roboto, but loads only Noto Sans Main. Glyph ranges are concatenable start/end pairs. Including large ranges increases atlas memory usage and build time.

Arabic glyphs may be available, but the demo warns that the binding does not handle bidirectional ordering or letter joining. Glyph availability does not imply correct shaping.

## Styles and colors

### Themes

```gml
ImGui.StyleColorsDark();
ImGui.StyleColorsLight();
ImGui.StyleColorsClassic();
```

### Temporary overrides

```gml
ImGui.PushStyleColor(ImGuiCol.Button, make_color_rgb(45, 110, 180));
ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 3);
ImGui.Button("Primary");
ImGui.PopStyleVar();
ImGui.PopStyleColor();
```

For multiple values, pass the count to the Pop functions if supported by the current signature. `SetStyleColor()` and `SetStyleVar()` apply persistent changes to the current style.

GameMaker colors are BGR packed; `ImColor` simplifies color and alpha conversion for the four-channel editor/picker format.

## Draw lists

Draw lists allow custom primitives inside or above the interface:

```gml
var draw_list = ImGui.GetWindowDrawList();
var x = ImGui.GetCursorScreenPosX();
var y = ImGui.GetCursorScreenPosY();

ImGui.Dummy(240, 120); // Reserves layout space and hit area.
ImGui.DrawListAddRectFilled(draw_list, x, y, x + 240, y + 120, c_black);
ImGui.DrawListAddCircleFilled(draw_list, x + 60, y + 60, 24, c_aqua);
ImGui.DrawListAddText(draw_list, x + 100, y + 52, "Preview", c_white);
```

Available lists: window, background, and foreground. Main primitives:

- lines, rectangles, quad and triangles, filled or outline;
- circles, n-gon and polylines;
- curve Bézier quadratic and cubic;
- text with font and wrapping;
- sprites and rounded images;
- path API with `PathClear`, `PathLineTo`, arcs, curve, fill and stroke.

When using clip rect or texture ID push/pop, always balance the stack. `Dummy()` is important: custom drawing alone does not occupy layout space or create an interactive item.

## Multi-select

The demo provides `ImGuiSelectionBasicStorage`, a GML helper with an internal native resource:

### Create

```gml
selection = new ImGuiSelectionBasicStorage();
```

### Step

```gml
var flags =
  ImGuiMultiSelectFlags.ClearOnEscape | ImGuiMultiSelectFlags.BoxSelect1d;

var request = ImGui.BeginMultiSelect(
  flags,
  selection.GetSize(),
  array_length(items)
);
selection.ApplyRequests(request);

for (var i = 0; i < array_length(items); ++i) {
  ImGui.SetNextItemSelectionUserData(i);
  ImGui.Selectable(items[i].name, selection.Contains(i));
}

request = ImGui.EndMultiSelect();
selection.ApplyRequests(request);
```

### Clean Up

```gml
selection.Destroy();
```

Applying requests after both `BeginMultiSelect()` and `EndMultiSelect()` is part of the protocol. User-data IDs must remain stable during the frame.

## Input and queries

### Last-item state

```gml
ImGui.IsItemHovered();
ImGui.IsItemActive();
ImGui.IsItemFocused();
ImGui.IsItemClicked();
ImGui.IsItemEdited();
ImGui.IsItemDeactivatedAfterEdit();
ImGui.IsItemToggledOpen();
ImGui.IsItemToggledSelection();
```

IDs, rectangles, and dimensions of the last item are also available. Call these queries immediately after the widget they refer to.

### Keyboard and shortcut

The APIs accept numeric keyboard/chord codes (`int32`): `IsKeyDown/Pressed/Released`, `IsKeyChordPressed`, `Shortcut`, `GetKeyName`, `GetKeyChordName`, `SetNextItemShortcut`, keyboard focus, and key ownership. `Shortcut` and `SetNextItemShortcut` also require an `ImGuiInputFlags` value.

The reference names the conceptual types `ImGuiKey` and `ImGuiKeyChord`, but the official sample does not publish GML enums `ImGuiKey` or `ImGuiMod`, nor an example that constructs their values. Do not use Dear ImGui values copied from a C++ version without verifying them in the installed runtime: this part of the interface is experimental and the values are not documented by the sample.

### Mouse

API: `IsMouseDown/Clicked/Released/DoubleClicked`, `IsMouseDragging`, position, drag delta, rectangle hover, and drag-delta reset. Prefer `IsItem*()` when the interaction belongs to the widget; use global mouse queries for custom canvases and tools.

### Clipboard

```gml
ImGui.SetClipboardText(serialized_value);
var value = ImGui.GetClipboardText();
```

### Debug

```gml
ImGui.ShowDemoWindow();
ImGui.ShowMetricsWindow();
ImGui.ShowDebugLogWindow();
ImGui.ShowStackToolWindow();
ImGui.ShowStyleEditor();
ImGui.ShowUserGuide();
```

The demo window is the fastest reference for verifying behavior and flags available in the installed runtime.

## GML helpers

The binding provides `ImGui`; these three constructors belong to the sample code instead and must be copied if needed.

### `ImColor`

```gml
var a = new ImColor(c_aqua, 0.5);
var b = new ImColor(128, 255, 255);

var gm_color = a.Color();
var alpha = a.Alpha();
```

It accepts a GameMaker color with alpha or RGB(A) components. It is intended for `Color*4s` APIs that modify a struct.

### `ImGuiWindowClass`

```gml
var window_class = new ImGuiWindowClass(
  class_id,
  parent_viewport_id,
  viewport_flags_set,
  viewport_flags_clear
);
ImGui.SetNextWindowClass(window_class);
```

It encapsulates the fields required by the window class/viewport APIs. In the sample, `Destroy()` is a placeholder.

### `ImGuiSelectionBasicStorage`

It manages a sparse selection by user-data ID. It exposes `GetSize`, `SetSize`, `ApplyRequests`, `Contains`, and `Destroy`. Unlike `ImGuiWindowClass`, it owns a resource that must be destroyed.

## Enums

Enums do not arrive automatically from the module: they are defined in GML in the sample. The main families are:

| Enum                                                                                   | Associated APIs                        |
| -------------------------------------------------------------------------------------- | -------------------------------------- |
| `ImGuiWindowFlags`, `ImGuiChildFlags`                                                  | window and child                       |
| `ImGuiCond`                                                                            | position, size, and initial state      |
| `ImGuiInputTextFlags`                                                                  | input text                             |
| `ImGuiTreeNodeFlags`                                                                   | tree and collapsing header             |
| `ImGuiPopupFlags`                                                                      | popup and context menu                 |
| `ImGuiSelectableFlags`                                                                 | selectable                             |
| `ImGuiComboFlags`                                                                      | combo                                  |
| `ImGuiTabBarFlags`, `ImGuiTabItemFlags`                                                | tab                                    |
| `ImGuiTableFlags`, `ImGuiTableColumnFlags`, `ImGuiTableRowFlags`, `ImGuiTableBgTarget` | tables                                 |
| `ImGuiDockNodeFlags`                                                                   | docking                                |
| `ImGuiDragDropFlags`                                                                   | drag and drop                          |
| `ImGuiColorEditFlags`                                                                  | color editor/picker                    |
| `ImGuiSliderFlags`                                                                     | slider and drag numeric                |
| `ImGuiHoveredFlags`, `ImGuiFocusedFlags`                                               | queries item/window                    |
| `ImGuiConfigFlags`                                                                     | global configuration                   |
| `ImGuiCol`, `ImGuiStyleVar`                                                            | style                                  |
| `ImGuiInputFlags`                                                                      | routing and behavior of shortcut/input |
| `ImGuiMouseButton`, `ImGuiDir`                                                         | mouse and directions                   |
| `ImGuiMultiSelectFlags`                                                                | multi-select                           |
| `ImDrawFlags`, `ImDrawListFlags`                                                       | draw list                              |

Combine flags with `|`. Use `None` when the family defines it, and do not replace constants with hardcoded numeric values.

## Performance, common errors and cleanup

### Common errors

1. Calling `End()` only inside the branch `if (Begin())`. `End()` must still be executed.
2. Forgetting `TreePop`, `EndTable`, `EndChild`, `EndPopup`, `EndTabBar`, `PopID`, `PopFont`, or `PopStyle*`.
3. Recreating a `{ open: true }` struct every frame for a window that should remain closed.
4. Using duplicate labels without `##id` or `PushID`.
5. Assigning the result of an array variant that changes in place.
6. Loading fonts from an IDE path instead of `assets/...`.
7. Using a surface without `surface_exists()`.
8. Forgetting `ImGuiSelectionBasicStorage.Destroy()`.
9. Using `static_get(ImGui)` without `try/catch`: this is introspection of internal details and is not a stable API.
10. Reading a struct field that may not exist yet (e.g. a session flag set
    later) with direct dot access: this runtime raises `ReferenceError`
    instead of returning `undefined`. Guard every such read with
    `variable_struct_exists()`, or use the `$` accessor which returns
    `undefined` for missing keys. Writes are safe - they create the field.

### Performance

- Build only the necessary windows; you can skip expensive content when `Begin()` returns `false`.
- Use child/table containers with clipping or virtualization for large lists.
- Do not rebuild font atlases, textures, or persistent resources every Step.
- Avoid temporary strings and arrays in loops with thousands of rows.
- Custom draw lists do not automatically perform logical clipping or application hit testing.
- `NoSavedSettings` avoids `.ini` persistence; use it for transient windows, not as an indiscriminate default.
- Cache expensive offscreen content (thumbnails, previews, masks) and
  re-render it only when its inputs change; verify the backing surface still
  exists before reuse.

### Cleanup

The main context, input, and rendering are managed by GMRT. Destroy the explicitly documented helper resources, especially `ImGuiSelectionBasicStorage`. If you create additional ImGui contexts through advanced APIs, you are responsible for their lifetime.

## API map

The official reference contains about 2,400 lines. This table serves as an index for finding the correct family.

| Family         | Representative functions                                                                  |
| -------------- | ----------------------------------------------------------------------------------------- |
| context/config | `CreateContext`, `DestroyContext`, `Get/SetCurrentContext`, `ConfigFlags*`, `GetVersion`  |
| windows        | `Begin/End`, `BeginChild/EndChild`, `SetNextWindow*`, queries window                      |
| layout         | cursor, region, `SameLine`, group, indent, width, text metrics                            |
| basic widgets  | text, button, checkbox, radio, progress, bullet, links                                    |
| inputs         | drag, slider, input scalar/vector/text, combo, list box                                   |
| trees          | `TreeNode*`, `TreePush/Pop`, `CollapsingHeader`                                           |
| menus/popups   | menu bar, menu, popup, modal, context menu, tooltip                                       |
| tables         | setup, row/column navigation, headers, sort, background                                   |
| tabs           | tab bar, tab item, tab button                                                             |
| docking        | dockspace, next dock ID, DockBuilder (add/split/dock/finish, node pos/size), window class |
| drag/drop      | source, target, payload set/accept/queries                                                |
| images         | `Image`, `ImageButton`, `Surface`                                                         |
| fonts          | default/TTF loading, `Push/PopFont`, font selector                                        |
| style          | theme, style colors/vars, item flags, disabled state                                      |
| draw list      | primitives, text, image, clip/texture stacks, path API                                    |
| selection      | `Begin/EndMultiSelect`, user data, basic storage helper                                   |
| item state     | hover, active, focus, edit, activation, rect and ID                                       |
| keyboard/mouse | key, chord, shortcut, ownership, click, drag, position                                    |
| utility/debug  | clipboard, time/frame, demo, metrics, debug log, stack tool                               |
