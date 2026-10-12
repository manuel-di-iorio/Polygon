demo_create();

var config = {
  scene: demo_scene,
  cam: demo_cam,
  on_create: demo_on_create,
  assets: demo_load_models([
    "kenney_platformer-kit/platform.glb",
    "kenney_platformer-kit/tree.glb",
    "kenney_platformer-kit/tree-pine.glb",
    "kenney_platformer-kit/flowers.glb",
    "kenney_platformer-kit/grass.glb",
    "kenney_platformer-kit/rocks.glb",
    "kenney_mini-characters/character-female-b.glb",
    "kenney_cube-pets_1.0/animal-fox.glb",
  ]),
};

instance_create_layer(0, 0, layer, oEditor, { config });
