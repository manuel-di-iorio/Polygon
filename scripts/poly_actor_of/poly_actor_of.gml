// poly_actor_of - public API.

// Finds the live companion instance bound to a node id (or node struct),
// or undefined. Stale entries never leak: dead instances read as missing.
function poly_actor_of(_node_or_id) {
  var _id = _node_or_id;

  if (is_struct(_node_or_id)) {
    if (variable_struct_exists(_node_or_id, "node")) _id = _node_or_id.node;
    else _id = _node_or_id;
  }

  if (is_struct(_id)) {
    if (!variable_struct_exists(_id, "name") || !is_string(_id.name)) return undefined;
    _id = _id.name;
  }

  if (!is_string(_id) || _id == "") return undefined;
  var _map = __poly_actor_map();

  if (!variable_struct_exists(_map, _id)) return undefined;
  var _inst = _map[$ _id];

  if (_inst == undefined || !instance_exists(_inst)) {
    variable_struct_remove(_map, _id);
    return undefined;
  }

  return _inst;
}
