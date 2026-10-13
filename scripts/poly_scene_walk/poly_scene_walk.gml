// poly_scene_walk — subtree walks (roots, mesh components, flags).

// Collects mesh components from node (all of them: the importer expands
// one multi-material mesh into one component per primitive, and the
// singular getter only returns the first — leaving the other parts
// unpickable, unoutlined and shadow-flagged wrong).
function __poly_walk_collect_comps(_node, _out) {
  var _all = _node.getMeshComponents();

  if (is_array(_all) && array_length(_all) > 0) {
    for (var _i = 0, _n = array_length(_all); _i < _n; _i++) {
      if (_all[_i] != undefined) array_push(_out, { comp: _all[_i], skinned: false });
    }
  } else {
    var _mesh = _node.getMeshComponent();

    if (_mesh != undefined) {
      array_push(_out, { comp: _mesh, skinned: false });
    }
  }

  var _skin = _node.getSkinnedMeshComponent();

  if (_skin != undefined) {
    array_push(_out, { comp: _skin, skinned: true });
  }
}

// Collects mesh components across a node subtree.
function __poly_walk_collect_tree(_node, _out) {
  var _stack = [ _node ];

  while (array_length(_stack) > 0) {
    var _cur = array_pop(_stack);

    if (_cur == undefined) continue;
    __poly_walk_collect_comps(_cur, _out);
    var _kids = _cur.getChildren();

    for (var _k = 0, _n = array_length(_kids); _k < _n; _k++) array_push(_stack, _kids[_k]);
  }
}

// Calls _fn(_cur, _ctx) for every node in the subtree (explicit stack,
// pre-order). Single traversal used by all per-node passes (outline,
// unlit, magenta, gpu-pick, hide) instead of cloned stack loops.
function __poly_walk_tree(_node, _fn, _ctx = undefined) {
  var _stack = [ _node ];

  while (array_length(_stack) > 0) {
    var _cur = array_pop(_stack);

    if (_cur == undefined) continue;
    _fn(_cur, _ctx);
    var _kids = _cur.getChildren();

    for (var _k = array_length(_kids) - 1; _k >= 0; _k--) array_push(_stack, _kids[_k]);
  }
}

// Same, threading inherited state down the tree: _fn(_cur, _ctx, _inh)
// returns the state for the children (e.g. gpu-pick muted-by-ancestor).
function __poly_walk_tree_inherit(_node, _fn, _ctx, _inh) {
  var _stack = [ _node ];
  var _inhs = [ _inh ];

  while (array_length(_stack) > 0) {
    var _cur = array_pop(_stack);
    var _ci = array_pop(_inhs);

    if (_cur == undefined) continue;
    var _next = _fn(_cur, _ctx, _ci);
    var _kids = _cur.getChildren();

    for (var _k = array_length(_kids) - 1; _k >= 0; _k--) {
      array_push(_stack, _kids[_k]);
      array_push(_inhs, _next);
    }
  }
}

// Reads shadow flags across a node subtree.
function __poly_flags_read(_node) {
  var _cast = true;
  var _recv = true;
  var _found = false;
  var _cb = GM3D_EMeshComponentFlags.CastShadows;
  var _rb = GM3D_EMeshComponentFlags.ReceiveShadows;
  var _comps = [];
  __poly_walk_collect_tree(_node, _comps);

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++) {
    var _flags = _comps[_i].comp.getFlags();

    if (!is_real(_flags)) continue;
    _found = true;

    if ((_flags & _cb) == 0) _cast = false;
    if ((_flags & _rb) == 0) _recv = false;
  }

  if (!_found) {
    return { castShadows: true, receiveShadows: true };
  }

  return { castShadows: _cast, receiveShadows: _recv };
}

// Pushes shadow flags across a node subtree.
function __poly_flags_apply(_node, _cast, _receive) {
  var _cb = GM3D_EMeshComponentFlags.CastShadows;
  var _rb = GM3D_EMeshComponentFlags.ReceiveShadows;
  var _bits = (_cast == true ? _cb : 0) | (_receive == true ? _rb : 0);
  var _comps = [];
  __poly_walk_collect_tree(_node, _comps);

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++) _comps[_i].comp.setFlags(_bits);
}

// Applies shadow flags from a data struct with safe reads
// (missing keys default to false, never crash on file data).
function __poly_flags_apply_data(_node, _d) {
  var _cast = is_struct(_d) && _d[$ "castShadows"] == true;
  var _recv = is_struct(_d) && _d[$ "receiveShadows"] == true;
  __poly_flags_apply(_node, _cast, _recv);
}

// Disables node meshes and records state.
function __poly_walk_mute_node(_node, _muted) {
  var _comps = [];
  __poly_walk_collect_comps(_node, _comps);

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++) {
    var _comp = _comps[_i].comp;

    if (_comp.getEnabled()) {
      _comp.setEnabled(false);
      array_push(_muted, { comp: _comp, was: true });
    }
  }
}

// Restores materials and enabled states.
function __poly_walk_restore(_swapped, _muted) {
  for (var _s = 0, _ns = array_length(_swapped); _s < _ns; _s++) _swapped[_s].comp.setMaterial(_swapped[_s].orig);
  for (var _m = 0, _nm = array_length(_muted); _m < _nm; _m++) if (_muted[_m].was) _muted[_m].comp.setEnabled(true);
}
