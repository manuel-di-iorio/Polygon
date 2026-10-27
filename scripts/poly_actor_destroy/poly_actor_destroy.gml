// poly_actor_destroy - public API.

// Destroys a companion actor and its bound scene node together. Accepts
// the companion instance id, the scene node, or the creation struct.
// Missing halves are skipped, so it is safe to call twice. Contract:
// kill actors only through this (never node.destroy / instance_destroy
// directly), or the other half is left orphaned.
function poly_actor_destroy(_ref) {
  var _inst = undefined;
  var _node = undefined;

  if (is_struct(_ref)) {
    if (variable_struct_exists(_ref, "node")) {
      _node = _ref.node;
    } else {
      _node = _ref;
    }
  } else {
    _inst = _ref;
  }

  if (_inst == undefined && is_struct(_node)) _inst = poly_actor_of(_node);

  if (_inst != undefined && !instance_exists(_inst)) _inst = undefined;

  if (_inst != undefined && _node == undefined
  && variable_instance_exists(_inst, "node")) {
    _node = variable_instance_get(_inst, "node");
  }

  if (is_struct(_node)) {
    _node.destroy(true);

    if (is_string(_node.name)) {
      var _map = __poly_actor_map();

      if (variable_struct_exists(_map, _node.name)) variable_struct_remove(_map, _node.name);
    }

    _node = undefined;
  }

  if (_inst != undefined && instance_exists(_inst)) instance_destroy(_inst);
}
