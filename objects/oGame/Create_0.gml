demo_create();

// Custom-variables example: the female character declares two variables from
// code. Edit them in the Inspector (prefab defaults from the Models panel, or
// per-instance overrides); Polygon saves them in the scene file and hands the
// resolved map back on load (on_create 5th argument / poly_node_vars).
var assets = demo_load_models([
  "demo/terrain.glb",
  "kenney_platformer-kit/platform.glb",
  "kenney_platformer-kit/tree.glb",
  "kenney_platformer-kit/tree-pine.glb",
  "kenney_platformer-kit/flowers.glb",
  "kenney_platformer-kit/grass.glb",
  "kenney_platformer-kit/rocks.glb",
  "kenney_mini-characters/character-female-b.glb",
  "kenney_cube-pets_1.0/animal-fox.glb",
  "__PolygonEditor__/models/cube.glb",
  "__PolygonEditor__/models/sphere.glb",
]);

var _hero = "kenney_mini-characters/character-female-b.glb";

if (variable_struct_exists(assets, _hero)) {
  var _hero_asset = assets[$ _hero];

  _hero_asset.variables = [
    { name: "life", type: "int", def: 100, min: 0, max: 999 },
    { name: "speed", type: "float", def: 4.5, min: 0, max: 20 },
  ];
}

var config = {
  scene: demo_scene,
  cam: demo_cam,
  // The game owns the physics world: hand its settings to the editor so the
  // Physics World panel (gravity, step, substeps, capacity) and the per-object
  // Physics sections describe the world that actually simulates the scene.
  physics_world: demo_physics_settings,
  editor_camera_z_offset: 8.1,
  editor_camera_yaw_offset: 180.0,
  // Hooks are called from the editor instance: bind them to oGame so they can
  // use this instance's variables (demo_scene, demo_physics, ...).
  on_create: method(id, demo_on_create),
  on_close: method(id, demo_on_close),
  assets: assets,
};

instance_create_layer(0, 0, layer, oEditor, { config });
