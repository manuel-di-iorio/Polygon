demo_create();

var config = {
  scene: demo_scene,
  cam: demo_cam,
  editor_camera_z_offset: 8.1,
  editor_camera_yaw_offset: 180.0,
  on_create: demo_on_create,
  assets: demo_load_models([
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
  ]),
};

instance_create_layer(0, 0, layer, oEditor, { config });
