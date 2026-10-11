// polygon_shaders — shader providers, unlit preview mode, magenta fallbacks.

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

// Returns list of editor shaders.
function __polygon_editor_shaders() {
  return [
    shPolygonEditorGrid, shPolygonEditorMask, shPolygonEditorMaskSkin, shPolygonEditorOutline, shPolygonEditorId, shPolygonEditorIdSkin, shPolygonEditorUnlit,
    shPolygonEditorUnlitSkin, shPolygonEditorSky, shPolygonEditorMagenta, shPolygonEditorMagentaSkin,
    shPolygonEditorLit, shPolygonEditorLitSkin, shPolygonEditorLitShadow, shPolygonEditorLitSkinShadow
  ];
}

// Central content-shader provider: editor-owned lit duplicates.
// Editor code must resolve sStatic/sAnimated-style shaders through here
// instead of referencing content shader assets directly.
function __polygon_lit_shaders() {
  return {
    fwd: shPolygonEditorLit,
    fwd_skin: shPolygonEditorLitSkin,
    sh: shPolygonEditorLitShadow,
    sh_skin: shPolygonEditorLitSkinShadow,
  };
}

// ---------------------------------------------------------------------------
// Unlit preview mode
// ---------------------------------------------------------------------------

// Swaps model materials between lit and unlit forward shaders.
function __polygon_unlit_apply(_ed) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.scene == undefined)  return;
  if (!variable_struct_exists(_ed, "unlit_orig") || !is_array(_ed.unlit_orig))  _ed.unlit_orig = [];
  if (_ed.show_unlit != true) {
    __polygon_unlit_restore(_ed);
    return;
  }

  var _roots = _ed.rt.scene.getNodes();

  for (var _i = 0, _n = array_length(_roots); _i < _n; _i++) {
    __polygon_walk_tree(_roots[_i], __polygon_unlit_visit, { ed: _ed });
  }

  _ed.view_dirty = true;
}

// Records original forward shader once per material.
function __polygon_unlit_record(_ed, _mat, _skinned) {
  var _list = _ed.unlit_orig;

  for (var _i = 0, _n = array_length(_list); _i < _n; _i++)  if (_list[_i].mat == _mat)  return;
  array_push(_list, { mat: _mat, sh: _mat.getShader(GM3D_ERenderPass.Forward), skinned: _skinned });
}

// Restores recorded forward shaders.
function __polygon_unlit_restore(_ed) {
  var _list = _ed.unlit_orig;
  var _lit = __polygon_lit_shaders();
  _ed.unlit_orig = [];

  for (var _i = 0, _n = array_length(_list); _i < _n; _i++) {
    var _entry = _list[_i];
    var _sh = _entry.sh;

    if (_sh == undefined)  _sh = _entry.skinned ? _lit.fwd_skin : _lit.fwd;
    _entry.mat.setShader(GM3D_ERenderPass.Forward, _sh);
  }
}

// Applies unlit shader to one node's materials, recording originals.
function __polygon_unlit_node(_ed, _node) {
  var _comps = [];
  __polygon_walk_collect_comps(_node, _comps);

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++) {
    var _mat = _comps[_i].comp.getMaterial();

    if (_mat == undefined)  continue;
    __polygon_unlit_record(_ed, _mat, _comps[_i].skinned);
    _mat.setShader(GM3D_ERenderPass.Forward, shPolygonEditorUnlit);
    _mat.setFloat("u_skinned", _comps[_i].skinned ? 1.0 : 0.0);
  }
}

// Applies unlit shader to one subtree node (walk visitor).
function __polygon_unlit_visit(_cur, _ctx) {
  if (!(is_string(_cur.name) && (_cur.name == "__editor_grid" || _cur.name == "__skybox")))  __polygon_unlit_node(_ctx.ed, _cur);
}

// ---------------------------------------------------------------------------
// Magenta fallbacks
// ---------------------------------------------------------------------------

// Ensures shared missing-material magenta materials exist.
function __polygon_magenta_mats(_ed) {
  if (_ed == undefined)  return false;
  if (_ed.magenta_mat != undefined && _ed.magenta_mat_skin != undefined)  return true;
  var _lit = __polygon_lit_shaders();

  if (_ed.magenta_mat == undefined) {
    var _flat = new GM3D_Material("polygon_magenta");
    _flat.setShader(GM3D_ERenderPass.Forward, shPolygonEditorMagenta);
    _flat.setShader(GM3D_ERenderPass.Shadow, _lit.sh);
    _ed.magenta_mat = _flat;
  }

  if (_ed.magenta_mat_skin == undefined) {
    var _skin = new GM3D_Material("polygon_magenta_skin");
    _skin.setShader(GM3D_ERenderPass.Forward, shPolygonEditorMagentaSkin);
    _skin.setShader(GM3D_ERenderPass.Shadow, _lit.sh_skin);
    _ed.magenta_mat_skin = _skin;
  }

  return true;
}

// Assigns fallback materials to material-less meshes on one node.
function __polygon_magenta_fix_node(_node, _mat, _mat_skin) {
  var _comps = [];
  __polygon_walk_collect_comps(_node, _comps);

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++) {
    var _fb = _comps[_i].skinned ? _mat_skin : _mat;

    if (_fb != undefined && _comps[_i].comp.getMaterial() == undefined)  _comps[_i].comp.setMaterial(_fb);
  }
}

// Assigns fallback materials to one subtree node (walk visitor).
function __polygon_magenta_visit(_cur, _ctx) {
  __polygon_magenta_fix_node(_cur, _ctx.mat, _ctx.skin);
}

// Assigns fallback materials to material-less meshes in subtree.
function __polygon_magenta_fix_mats(_node, _mat, _mat_skin) {
  if (_node == undefined || _mat == undefined)  return;
  __polygon_walk_tree(_node, __polygon_magenta_visit, { mat: _mat, skin: _mat_skin });
}

// Paints material-less meshes magenta.
function __polygon_magenta_fix(_ed, _node) {
  if (_ed == undefined || _node == undefined)  return;
  if (!__polygon_magenta_mats(_ed))  return;
  __polygon_magenta_fix_mats(_node, _ed.magenta_mat, _ed.magenta_mat_skin);
}

// Paints material-less meshes magenta without editor state.
function __polygon_load_magenta_fix(_node) {
  static _flat = undefined;
  static _skin = undefined;

  if (_node == undefined)  return;
  var _lit = __polygon_lit_shaders();

  if (_flat == undefined) {
    _flat = new GM3D_Material("polygon_load_magenta");
    _flat.setShader(GM3D_ERenderPass.Forward, shPolygonEditorMagenta);
    _flat.setShader(GM3D_ERenderPass.Shadow, _lit.sh);
  }

  if (_skin == undefined) {
    _skin = new GM3D_Material("polygon_load_magenta_skin");
    _skin.setShader(GM3D_ERenderPass.Forward, shPolygonEditorMagentaSkin);
    _skin.setShader(GM3D_ERenderPass.Shadow, _lit.sh_skin);
  }

  __polygon_magenta_fix_mats(_node, _flat, _skin);
}
