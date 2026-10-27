# GM3D in GameMaker

Operational guide to the GMRT runtime 3D module (0.22.4), based on the official project [YoYoGames/GM3D-Samples](https://github.com/YoYoGames/GM3D-Samples) and the reference included in the repository (`notes/GM3D_API.md`).

## Contents

- [Mental model](#mental-model)
- [Quick start](#quick-start)
- [Lifecycle](#lifecycle)
- [Scenes and nodes](#scenes-and-nodes)
- [Transformations and math](#transformations-and-math)
- [Components](#components)
- [Materials, shaders and textures](#materials-shaders-and-textures)
- [Shadows and render passes](#shadows-and-render-passes)
- [Animation](#animation)
- [Camera and rendering](#camera-and-rendering)
- [Lights, environment and fog](#lights-environment-and-fog)
- [glTF loading and instances](#gltf-loading-and-instances)
- [Physics](#physics)
- [Character controller](#character-controller)
- [Vehicles](#vehicles)
- [FPS patterns: hitscan, pickups, debris](#fps-patterns-hitscan-pickups-debris)
- [The seven official samples](#the-seven-official-samples)
- [Performance and ownership](#performance-and-ownership)
- [API by type](#api-by-type)
- [Documentation limits](#documentation-limits)
- [Sources](#sources)

## Mental model

GM3D is a **scene graph** renderer with an optional parallel physics
simulation:

```text
GM3D_Scene
└── GM3D_SceneNode
    ├── local transformation
    ├── child nodes
    └── components
        ├── GM3D_CameraComponent
        ├── GM3D_LightComponent (+ shadows)
        ├── GM3D_EnvironmentVolumeComponent
        ├── GM3D_MeshComponent / GM3D_SkinnedMeshComponent (+ flags)
        ├── GM3D_AnimationComponent
        ├── GM3D_PhysicsBodyComponent + GM3D_PhysicsShapeComponent
        ├── GM3D_PhysicsConstraintComponent
        ├── GM3D_CharacterControllerComponent
        └── GM3D_PhysicsVehicle* (Wheel, Powertrain, Differential,
            AntiRollBar, Motorcycle, Tracked, Vehicle)
```

A `GM3D_Renderer` traverses the scene and draws it. A `GM3D_PhysicsWorld`
simulates the bodies registered from that same scene. The typical pipeline is:

1. create the scenes live and the renderer (+ optional `GM3D_PhysicsWorld`);
2. load one or more glTF scenes as source assets;
3. assign **two** shaders per material (Forward + Shadow);
4. call `freeze()` on the source asset;
5. create instances with `spawnInto()` and attach physics/vehicle/character components;
6. add a camera, shadow-casting directional light, and environment volume;
7. per Step: input → `scene.update(dt)` → `physicsWorld.step(dt)` → `physicsWorld.interpolateForRender()`;
8. in Draw: `renderer.render(scene)` then `physicsWorld.restoreSimulationPositions()`;
9. destroy live scene, assets, and physics world in Clean Up.

Non-physics content skips the `physicsWorld` steps entirely.

## Quick start

The `GM3D_*` module is provided by GMRT: the sample repository does not contain an extension to import. Eight shaders **are** part of the sample project.

### Create

```gml
#macro DELTA_SECONDS (delta_time * 0.000001)

scene = GM3D_Scene.createEmpty();
renderer = new GM3D_Renderer();
assets = [];

var model = GM3D_Scene.loadGltf(working_directory + "models/tree.glb");

// One shader per render pass (see Materials, shaders and textures).
model.forEachMaterial(method({ shStatic, shAnimated, shStaticShadow, shAnimatedShadow }, function(_mat, _ctx) {
    var _skinned = (_ctx.skinnedMeshCount > 0);
    _mat.setShader(GM3D_ERenderPass.Forward, _skinned ? _shAnimated : _shStatic);
    _mat.setShader(GM3D_ERenderPass.Shadow, _skinned ? _shAnimatedShadow : _shStaticShadow);
}));

model.freeze();
array_push(assets, model);

var root = model.spawnInto(scene, undefined);
root.setLocalPosition(new GM3D_Vec3(0, 0, 0));

var camera_node = scene.createNode("Camera");
var camera = new GM3D_CameraComponent();
camera_node.addComponent(camera);
camera.setProjection(GM3D_ECameraProjection.Perspective);
camera.setFovY(degtorad(60));
camera.setNear(0.1);
camera.setFar(1000);
```

### Step (no physics)

```gml
scene.update(DELTA_SECONDS);
```

`delta_time` is expressed in microseconds; GM3D uses seconds.

### Step (with physics)

```gml
// 1. write inputs (character velocity, vehicle input, kinematic poses)
scene.update(DELTA_SECONDS);
physicsWorld.step(DELTA_SECONDS);
physicsWorld.interpolateForRender();
// ... camera follow, HUD reads ...
```

### Draw

```gml
renderer.render(scene);
// physics only:
physicsWorld.restoreSimulationPositions();
```

`restoreSimulationPositions()` must run **after** render, otherwise the
interpolated pose leaks into the next simulation step.

### Clean Up

```gml
if (physicsWorld != undefined) physicsWorld.destroy();

scene.destroy();

for (var i = 0; i < array_length(assets); ++i) {
  assets[i].destroy();
}

assets = [];
renderer = undefined;
```

## Lifecycle

### Initialization

`GM3D_Scene.createEmpty()` creates the live container. Assets loaded with `GM3D_Scene.loadGltf()` remain separate scenes: `spawnInto(dest, parent)` copies their hierarchy into the destination scene and returns the root node of the new instance. `parent = undefined` spawns at scene root; any node spawns as child (used for visuals parented to physics bodies, avatars parented to character nodes, weapons parented to cameras).

Do not use the asset scenes directly as the live world when you expect multiple instances. Keep the asset instead and create copies in the main scene.

Physics registration happens **once at startup**, after a stabilizing
`scene.update(0.0)`:

```gml
scene.update(0.0);
physicsWorld.syncScene(); // bulk register
// or granular:
physicsWorld.addNode(node); // body + shape required
physicsWorld.addCharacter(node); // character controller required
physicsWorld.addVehicle(vehicle); // configured vehicle component
```

Constructor observed in samples:

```gml
physicsWorld = new GM3D_PhysicsWorld(scene, {
  maxBodies: 512,
  fixedTimeStep: 1 / 60,
  maxSubSteps: 4,
});
physicsWorld.setGravity(new GM3D_Vec3(0, -9.81, 0));
physicsWorld.setDebugDrawEnabled(false); // P toggles it in samples
```

### Updating

Non-physics: `scene.update(delta_seconds)` once per Step.

Physics: strict order used by the physics samples:

```text
input → setCharacterVelocity / setVehicleInput / setBodyPositionRotation
      → scene.update(dt) → physicsWorld.step(dt) → interpolateForRender()
      → readback (ground state, velocity, speed) → camera → render
```

After structural changes or when a scene has just been created, `scene.update(0.0)` forces synchronization without advancing time.

### Rendering

```gml
renderer.render(scene, deltaTime?);
```

The renderer uses enabled cameras in `order` sequence, each clipped to its `screenRect`. It accepts an optional `deltaTime` (seconds since last render); samples call it with one argument.

### Destruction

Whoever creates a `GM3D_Scene` owns its lifetime. Destroy in reverse order of creation: vehicles/characters/nodes are owned by the scene, but the world must be destroyed **before** the scene:

```gml
physicsWorld.destroy();
scene.destroy();
asset.destroy(); // once per loadScene() entry
```

After `destroy()`, remove application references to avoid accidental reuse.

## Scenes and nodes

### `GM3D_Scene`

Creation and queries:

```gml
var scene = GM3D_Scene.createEmpty();
var asset = GM3D_Scene.loadGltf(working_directory + path);

var node = scene.createNode("Player");
var by_name = scene.getNode("Player");
var by_index = scene.getNode(0);
var nodes = scene.getNodes();
var names = scene.getNodeNames();

scene.forEachNode(function (_node) {
  /* stable order, created-during-callback not visited */
});
scene.forEachMaterial(function (_mat, _ctx) {
  // _ctx.staticMeshCount, _ctx.skinnedMeshCount
});
```

Materials and animations:

```gml
var material = asset.getMaterial(0); // also by name
var materials = asset.getMaterials();
var material_names = asset.getMaterialNames();
scene.setMaterial(0, replacement); // swap a slot by name/index

var animation = asset.getAnimation(0); // also by name
var animations = asset.getAnimations();
var animation_names = asset.getAnimationNames();
var exists = asset.hasAnimation(0);
scene.applyAnimation(index_or_name_or_struct, time_seconds); // pose without component
```

Bounds (replaces manual min/max math):

```gml
var bb = asset.getBoundingBox(); // { min: GM3D_Vec3, max: GM3D_Vec3 } world space
var bs = asset.getBoundingSphere(); // { origin: GM3D_Vec3, radius: real } world space
```

The static sample frames the orbit camera from `getBoundingSphere()`; the physics sample centers coin visuals from `getBoundingBox()`; vehicle setup derives wheel radius/width from mesh bounds (see Vehicles).

Useful read-only properties: `nodeCount`, `materialCount`, `animationCount` and `path`.

### `GM3D_SceneNode`

Hierarchy:

```gml
parent.addChild(child);
var children = parent.getChildren();
child.removeFromParent();
node.destroy(); // destroy(recursive?) - true destroys subtree,
// false reparents children to own parent
node.forEachNode(function (_n) {
  /* depth-first self + descendants */
});
var found = root.findNodeByName("wheel-front-left");
```

Components:

```gml
node.addComponent(component);
node.removeComponent(component);
node.removeAllComponents();

var camera = node.getCameraComponent();
var light = node.getLightComponent();
var environment = node.getEnvironmentVolumeComponent();
var mesh = node.getMeshComponent();
var meshes = node.getMeshComponents();
var skinned = node.getSkinnedMeshComponent();
var animation = node.getAnimationComponent();
var animations = node.getAnimationComponents();
```

Recursive search (preferred over hand-rolled recursion after `spawnInto()`):

```gml
var animator = root.findAnimationComponent();
var cam = root.findCameraComponent();
var light = root.findLightComponent();
var env = root.findEnvironmentVolumeComponent();
var mesh = root.findMeshComponent();
var skinned = root.findSkinnedMeshComponent();
var body = root.findPhysicsBodyComponent();
var shape = root.findPhysicsShapeComponent();
var constraint = root.findPhysicsConstraintComponent();
var character = root.findCharacterControllerComponent();
var vehicle = root.findPhysicsVehicleComponent();
var wheel = root.findPhysicsVehicleWheelComponent();
// + AntiRollBar, Differential, Motorcycle, Powertrain, Tracked variants
```

`getAnimationComponent()` returns the first component **on that node only**; `findAnimationComponent()` searches the subtree depth-first.

Node identity: `name`, `parent` (undefined at root).

## Transformations and math

Local transformations are relative to the parent; world transformations derive from the entire hierarchy chain.

```gml
node.setLocalPosition(new GM3D_Vec3(x, y, z));
node.setLocalRotation(GM3D_Quaternion.fromAxisAngle(GM3D_Vec3.up(), angle));
node.setLocalScale(new GM3D_Vec3(sx, sy, sz));
node.setLocalMatrix(matrix);

var local_matrix = node.getLocalMatrix();
var world_matrix = node.getWorldMatrix();
var world_position = node.getWorldPosition();
var forward = node.getWorldForward();
var right = node.getWorldRight();
var up = node.getWorldUp();
// + getLocalForward/Right/Up, getLocalPosition/Rotation/Scale,
//   getWorldRotation/Scale
```

Helpers used across samples:

```gml
// Orient node along a direction (lights, cameras, orbit):
node.setLocalRotation(GM3D_Quaternion.fromLookRotation(direction));
// Safe normalize after fromAxisAngle:
_root.setLocalRotation(_rot.normalizeSafe(0.000001));
// Planar movement basis:
var fwd = camNode.getLocalForward();
var planar = new GM3D_Vec3(fwd.x, 0, fwd.z).normalize();
```

### Mathematical types

| Type                                           | Main use                                                                 |
| ---------------------------------------------- | ------------------------------------------------------------------------ |
| `GM3D_Vec2`, `GM3D_Vec3`, `GM3D_Vec4`          | vectors, products, normalization, interpolation and transformations      |
| `GM3D_Matrix2`, `GM3D_Matrix3`, `GM3D_Matrix4` | composition, inversion, projection and transformations                   |
| `GM3D_Quaternion`                              | robust rotations, `slerp`, axis-angle/Euler/matrix conversion            |
| `GM3D_Euler`                                   | angles with configurable rotation order                                  |
| `GM3D_DualQuaternion`                          | combined rotation and translation, useful for interpolation and skinning |

Common operations:

```gml
var direction = target.subtract(position).normalize();
var rotation = GM3D_Quaternion.fromAxisAngle(GM3D_Vec3.up(), degtorad(yaw));

var matrix = new GM3D_Matrix4();
matrix.compose(position, rotation, scale);
matrix.decompose(out_position, out_rotation, out_scale);
```

Practical additions:

| Addition                                      | Use                                |
| --------------------------------------------- | ---------------------------------- |
| `GM3D_Quaternion.fromLookRotation(fwd[, up])` | aim camera/light/node, orbit logic |
| `Quaternion.normalizeSafe(eps)`               | guard degenerate yaw rotations     |
| `GM3D_Mesh.getBoundingBox()` → `{min, max}`   | single-call mesh bounds            |
| `GM3D_Scene.getBoundingBox/Sphere()`          | auto-framing, spawn layout         |
| `GM3D_Vec3.forward/up/right/one/zero`         | canonical axes                     |

Matrices expose `elements` in column-major order. Prefer GM3D methods to native array matrices when working with GM3D nodes and components.

## Components

### Camera

```gml
var component = new GM3D_CameraComponent();
node.addComponent(component);

component.setEnabled(true);
component.setProjection(GM3D_ECameraProjection.Perspective);
component.setFovY(degtorad(60));
component.setNear(0.1);
component.setFar(500); // 0 = infinite in perspective mode
component.setAspectRatio(16 / 9);
```

For orthographic projection, use `setOrthoWidth()` and `setOrthoHeight()`.

Camera utilities:

```gml
// Free-look without manual Euler math (RMB + limits):
camComponent.updateMouselook(deltaYawDeg, deltaPitchDeg, -85, 85);
// delta from: window_mouse_get_delta_x() / window_mouse_get_delta_y()

// Gameplay queries:
var ray = camComponent.screenPointToRay({ x: 0.5, y: 0.5 });
// → { origin, direction } or undefined (FPS crosshair raycast)

var ndc = camComponent.worldToScreen(worldPos);
// → GM3D_Vec3 with camera screenRect applied, z = 0..1 depth, or undefined
//   (FPS ammo labels, viewport outlines)
```

Properties `renderTexture`, `depthTexture` expose render-to-texture results (see Camera and rendering).

### Light

```gml
var component = new GM3D_LightComponent();
node.addComponent(component);

component.setType(GM3D_ELightType.Directional);
component.setColor(c_white); // packed 0x00BBGGRR
component.setIntensity(1.0);
component.setEnabled(true);
```

Point and spot lights also use `setRange()` (0 = infinite). Spot lights expose `setInnerConeAngle()` and `setOuterConeAngle()`, in radians.

Shadows (directional only):

```gml
component.setShadowEnabled(true);
component.setShadowResolution(2048);
component.setShadowDistance(20.0);
component.setShadowNormalOffset(0.05);
// getters: getShadowEnabled/Resolution/Distance/NormalOffset
```

### Environment volume

```gml
var component = new GM3D_EnvironmentVolumeComponent();
node.addComponent(component);

component.setSize(new GM3D_Vec3(100, 100, 100));
component.setAmbientColor(make_color_rgb(80, 90, 100));
component.setFogEnabled(true);
component.setFogColor(c_silver);
component.setFogStart(20);
component.setFogEnd(100);
// getters: getSize/AmbientColor/FogColor/FogStart/FogEnd/FogEnabled
```

The volume is an AABB centered on its node. Size it so that it contains the rendered area; samples size it generously (`20000`, `50000`) and tune fog per scene (e.g. forest `22 → 95`, physics `14 → 78`, vehicle `25 → 140`, FPS `30 → 180`).

### Mesh

```gml
var component = new GM3D_MeshComponent(mesh, material);
component.setMaterial(material);
component.setEnabled(true);
```

`GM3D_SkinnedMeshComponent(mesh, material)` has the same shape and adds `jointCount`.

Shadow flags (both default **on**):

```gml
component.setFlags(
  GM3D_EMeshComponentFlags.CastShadows | GM3D_EMeshComponentFlags.ReceiveShadows
);
var flags = component.getFlags();
// GM3D_EMeshComponentFlags.CastShadows = 1, ReceiveShadows = 2
```

`GM3D_Mesh` exposes `name`, `isSkinned`, `primitiveType`, `vertexBuffer`, `vertexFormat` and `getBoundingBox()` (single call returning `{min, max}`).

## Materials, shaders and textures

### Shader assignment

`material.setShader(pass, shader)` / `material.getShader(pass)`, where `pass` is `GM3D_ERenderPass`:

```gml
GM3D_ERenderPass.Shadow = 0; // shadow-map pass
GM3D_ERenderPass.Forward = 1; // scene geometry
GM3D_ERenderPass.Custom = 2; // base for user passes: Custom + N in [0, 255]
```

Passing `undefined` clears a non-forward pass or restores the default forward shader. Canonical helper:

```gml
function assignShaders(_scene, _instanced = false) {
  var _shStatic = _instanced ? shStaticInstanced : shStatic;
  var _shAnimated = _instanced ? shAnimatedInstanced : shAnimated;
  var _shStaticShadow = _instanced ? shStaticInstancedShadow : shStaticShadow;
  var _shAnimatedShadow = _instanced
    ? shAnimatedInstancedShadow
    : shAnimatedShadow;
  var _ctx = { _shStatic, _shAnimated, _shStaticShadow, _shAnimatedShadow };
  _scene.forEachMaterial(
    method(_ctx, function (_material, _context) {
      var _skinned = _context.skinnedMeshCount > 0;
      var _shader = _skinned ? _shAnimated : _shStatic;
      var _shadowShader = _skinned ? _shAnimatedShadow : _shStaticShadow;
      _material.setShader(GM3D_ERenderPass.Forward, _shader);
      _material.setShader(GM3D_ERenderPass.Shadow, _shadowShader);
    })
  );
}
```

Eight shader variants ship with the project:

| Geometry | Forward      | Forward instanced     | Shadow             | Shadow instanced            |
| -------- | ------------ | --------------------- | ------------------ | --------------------------- |
| static   | `shStatic`   | `shStaticInstanced`   | `shStaticShadow`   | `shStaticInstancedShadow`   |
| skinned  | `shAnimated` | `shAnimatedInstanced` | `shAnimatedShadow` | `shAnimatedInstancedShadow` |

Shaders show required attributes (`in_Position/Normais/Colour/TextureCoord/Tangent`), TBN frame, world position, fog factor, and `gm_ShadowNormalOffset`.

### `GM3D_Material`

```gml
var material = new GM3D_Material("Ground");
material.setShader(GM3D_ERenderPass.Forward, shStatic);
material.setTexture("gm_BaseTexture", texture_id);
material.setFloat("u_roughness", 0.8);
material.setFloatArray("u_tint", [1, 1, 1, 1]);
material.setInt("u_mode", 0);
```

Grouped inventory (every setter has a `get*` counterpart, verified against `notes/GM3D_API.md` in GM3D-Samples `develop`):

- identity: constructor with name, `getName`/`setName`, `clone()` (independent handle), `destroy()`;
- shaders: `getShader(pass)` / `setShader(pass, shader)`, pass in `[0, 255]` (`GM3D_ERenderPass.Shadow = 0`, `Forward = 1`, `Custom = 2 + N`). `getShader` returns `undefined` when the pass is unassigned - documented behavior, treat it as "engine default". Passing `undefined` to `setShader` clears a non-forward pass or restores the default forward shader;
- textures: `getTexture(name): int32` / `setTexture(name, texture)`. There is **no enumeration API**: bindings are name-addressed, so the caller must know the uniform names. glTF import populates the `gm_*` bindings consumed by the sample shaders (`gm_BaseTexture` + `gm_BaseColorFactor` vec4, `gm_AlphaMode` int with `0 = Opaque / 1 = Mask / 2 = Blend`, UV transform `gm_BaseTexture_Offset/Scale/Rotation`);
- uniforms: `get/setFloat`, `get/setFloatArray`, `get/setInt`, `get/setIntArray` by name;
- blend: `BlendEnable`, `BlendMode` (plus `Ext`/`SepAlpha` factor variants), `BlendEquation` (plus `SepAlpha`), source/destination factors (color + alpha), `ColorWriteEnable` as `[red, green, blue, alpha]`;
- depth: `ZTestEnable`, `ZWriteEnable`, `ZFunc`;
- stencil: `StencilEnable/Func/Ref/ReadMask/WriteMask/Fail/Pass/DepthFail`;
- misc: `CullMode`, `AlphaTestEnable/Ref`, `FogEnable`, `LightingEnable`.

Texture ids are opaque `int32` handles: they can only be rebound (`setTexture`, `setGlobalTexture`) or tuned through `GM3D_Texture` sampler state. There is no CPU readback and no conversion to GameMaker surfaces/sprites - a `getTexture` id is not directly drawable in 2D.

`setMaterial()` on scene swaps a slot by name/index.

### Global uniforms

`GM3D_Shader` is a static class with the full getter/setter set:

```gml
GM3D_Shader.setGlobalFloat("u_time", current_time * 0.001);
GM3D_Shader.setGlobalFloatArray("u_wind", [1, 0, 0]);
GM3D_Shader.setGlobalInt("u_quality", 2);
GM3D_Shader.setGlobalIntArray("u_flags", [1, 0]);
GM3D_Shader.setGlobalTexture("u_noise", texture_id);
```

Read back with `getGlobalFloat/FloatArray/Int/IntArray/Texture`. `GM3D_Texture` exposes static sampler get/set, addressed by texture id:

```gml
GM3D_Texture.setFilter(texture_id, true);
GM3D_Texture.setRepeat(texture_id, true);
GM3D_Texture.setMaxAniso(texture_id, 8);
```

Full sampler list: `Filter` (linear bool), `Repeat` (wrap bool), `MaxAniso` (int), `MinMip`/`MaxMip` (real), `MipBias` (real), `MipEnable`/`MipFilter` (enum int).

Texture sources: glTF import (per-material `gm_*` bindings), camera render targets (`GM3D_ECameraTarget.Texture` + `Fixed` size exposes color in `renderTexture` and depth in `depthTexture`, both `int32`, rebindable like any texture id), and `setTexture` overrides per material.

## Shadows and render passes

- Directional light owns the shadow map: enable + resolution + distance + normal offset.
- Each mesh component opts in/out via `GM3D_EMeshComponentFlags`.
- Each material binds **two** shaders: Forward (visible) and Shadow (depth). Forgetting the Shadow pass = correct lighting but no shadows.
- Instanced variants exist for both passes; the forest sample proves the combination (`assignShaders(src, true)` + `CastShadows` default).
- Debug: `physicsWorld.setDebugDrawEnabled()` is physics debug, unrelated to shadow maps.

```gml
// Minimal shadow setup:
var _light = new GM3D_LightComponent();
_light.setType(GM3D_ELightType.Directional);
_light.setColor(_color);
_light.setShadowEnabled(true);
_light.setShadowResolution(2048);
_light.setShadowDistance(20.0);
_light.setShadowNormalOffset(0.05);
_node.setLocalRotation(GM3D_Quaternion.fromLookRotation(_direction));
```

## Animation

An asset glTF can contain clips and one or more `GM3D_AnimationComponent` instances.

```gml
var animation = asset.getAnimation(index); // path, duration
show_debug_message(animation.path);
show_debug_message(animation.duration);

animator.play(index, true);
animator.setSpeed(1.0);
animator.setTime(0.0);
```

Available controls:

```gml
animator.pause();
animator.resume();
animator.setEnabled(false);

var playing = animator.isPlaying;
var time = animator.getTime();
var speed = animator.getSpeed();
```

Lookup pattern (exact name → substring → index 0), then enable before play:

```gml
animator = root.findAnimationComponent(); // NOT getAnimationComponent()
animator.setEnabled(true);
var idx = findAnimIndex(asset, "idle");
animator.setTime(0);
animator.setSpeed(1.0);
animator.play(idx, true);
```

The forest sample desynchronizes 2000 foxes with random `setSpeed(0.85–1.15)` and `setTime(random(10))` per instance. `GM3D_Scene.applyAnimation(nameOrIndexOrStruct, time)` poses a scene without a component - useful for thumbnails/debris.

## Camera and rendering

### Projection and target

```gml
camera.setProjection(GM3D_ECameraProjection.Perspective);
camera.setTarget(GM3D_ECameraTarget.Screen);
camera.setRenderSizeMode(GM3D_ECameraRenderSizeMode.Auto);
```

For render-to-texture:

```gml
camera.setTarget(GM3D_ECameraTarget.Texture);
camera.setRenderSizeMode(GM3D_ECameraRenderSizeMode.Fixed);
camera.setRenderWidth(1024);
camera.setRenderHeight(1024);

var color_texture = camera.renderTexture;
var depth_texture = camera.depthTexture;
```

### Rectangle, order, and alpha

`setScreenRect([x, y, width, height])` uses normalized coordinates. The split-screen sample sets:

```gml
left_camera.setScreenRect([0.0, 0.0, 0.5, 1.0]);
right_camera.setScreenRect([0.5, 0.0, 0.5, 1.0]);
left_camera.setOrder(0);
right_camera.setOrder(1);
```

`setAlpha()` controls camera compositing; `setEnabled()` includes or excludes it from rendering. Toggle with `P`, switch active viewport with `Tab`; viewport outline in Draw GUI Begin via `getScreenRect()`.

### Free-look controller

The samples store position, yaw, and pitch in the application, then apply the result to the camera node - canonically with `updateMouselook` under right mouse button:

```gml
if (mouse_check_button(mb_right)) {
  camComponent.updateMouselook(
    window_mouse_get_delta_x() * lookSense,
    -window_mouse_get_delta_y() * lookSense,
    -85,
    85
  );
}
camPos = moveCam(camPos, camNode, camSpeed, fastMult); // WASD + Q/E + Shift
camNode.setLocalPosition(camPos);
// moveCam uses getLocalForward/Right planarized on XZ, Q/E on Y
```

Follow cameras: `getWorldPosition/Forward`, `getLinearVelocity`, `lerp` smoothing, occlusion raycast, head-bob + recoil offsets.

## Lights, environment and fog

Official light types:

```gml
GM3D_ELightType.Directional;
GM3D_ELightType.Point;
GM3D_ELightType.Spot;
```

A directional light uses the node orientation. Point and spot lights also use position; a spot light uses orientation and cone angles. GameMaker colors and intensity are separate properties. Lights additionally expose the shadow configuration (directional only, see Shadows and render passes).

Fog is configured on the `GM3D_EnvironmentVolumeComponent` and can be disabled per volume. `fogStart` and `fogEnd` define the linear range; each mesh contributes via its shadow/cast flags.

## glTF loading and instances

### Pattern asset

```gml
function loadScene(_fileName) {
  var _scene = GM3D_Scene.loadGltf(working_directory + _fileName);
  if (_scene == undefined) return undefined;
  assignShaders(_scene);
  _scene.freeze();
  array_push(assets, _scene);
  return _scene;
}
```

`freeze()` completes preparation of the source scene (uploads meshes to GPU - call once after shader assignment). Call it after changes to materials that must be shared by instances and before `spawnInto()`.

The included assets are `.glb`, that is, binary glTF with meshes, materials, skinning, and animations. The repository does not demonstrate OBJ or FBX import. Physics `Mesh`, `ConvexHull` and `ConvexDecomposition` shape types approximate meshes, but there is no asset-pipeline physics import.

### Spawn and parent

```gml
var root = asset.spawnInto(scene, undefined); // root instance
var child_root = asset.spawnInto(scene, parent_node); // visual under body
```

The returned node is the control point for the instance: position, rotation, and scale applied to the root affect the entire imported hierarchy.

Visual offset/scale pattern (physics samples): spawn under a unit-scaled physics node, center via bounding box, scale visual independently.

## Physics

Jolt-style API surfaced as components + world.

### Body and shape

```gml
var body = new GM3D_PhysicsBodyComponent();
body.setMotionType(GM3D_EPhysicsMotionType.Static); // Static | Kinematic | Dynamic
body.setLayer(GM3D_EPhysicsLayer.Static); // Static=1 Default=2 Character=4 Trigger=8 Debris=16 All=31
body.setMass(2.0);
body.setLinearDamping(0.15);
body.setAngularDamping(0.35);
body.setGravityFactor(1.0);
body.setIsSensor(false); // true for triggers
body.setStartAwake(false);
body.setMotionQuality(GM3D_EPhysicsMotionQuality.Discrete);
body.setAllowSleeping(true);
// + center-of-mass offset, locked axes, collision group/subgroup,
//   contact callbacks (below)

var shape = new GM3D_PhysicsShapeComponent();
shape.setShapeType(GM3D_EPhysicsShapeType.Box); // Box Sphere Capsule Cylinder Mesh ConvexHull ConvexDecomposition
// NOTE: the API index declares the setter range as [0,5], which would exclude ConvexDecomposition=6 - verify at runtime
shape.setHalfExtents(new GM3D_Vec3(hx, hy, hz)); // sphere/capsule/cylinder: x=radius y=half-height
shape.setLocalOffset(offset);
shape.setLocalRotation(rot);
shape.setFriction(0.95); // clamped [0,1]
shape.setRestitution(0.0); // clamped [0,1]

node.addComponent(body);
node.addComponent(shape);
```

Helpers in the samples: visual-only spawn (transform only), static box (node + body + box), scene-driven collider, coin pickup (visual + point light + sensor sphere + trigger body), dynamic convex-hull cones.

### World

```gml
world = new GM3D_PhysicsWorld(scene, {
  maxBodies: 512,
  fixedTimeStep: 1 / 60,
  maxSubSteps: 4,
});
world.setGravity(new GM3D_Vec3(0, -9.81, 0));
world.syncScene();
world.step(DELTA_SECONDS);
world.interpolateForRender();
world.restoreSimulationPositions(); // after render
world.destroy();
```

Registration: `addNode / removeNode / rebuildNode / addTree`.
Simulation control: `activateBody / deactivateBody / isBodyActive`, `getBodyPosition / getBodyRotation`, `setBodyPositionRotation(node, pos, rot, activate)`, `get/setLinearVelocity/AngularVelocity`, `addForce / addTorque / addLinearImpulse / addAngularImpulse` (+ `AtPoint` variants), `get/setBodyFriction/Restitution/MotionQuality/AllowSleeping/DOFLock`, `setMass/LinearDamping/AngularDamping/GravityFactor/IsSensor` per node.
Layers: `setLayerCollision(a, b, collides)` / `getLayerCollision`.
Groups: `setCollisionGroupPair(subA, subB, collides)`.
Gravity: `setGravity / getGravity`. Debug: `setDebugDrawEnabled / getDebugDrawEnabled`. World props: `fixedTimeStep`, `maxSubSteps`, `interpolationAlpha` (read-only).

### Queries

```gml
var hit = world.raycast(origin, dir, maxDist, layerMask, ignoreNodes);
// → GM3D_RaycastHit { node, point, normal, distance } or undefined
var hits = world.raycastAll(origin, dir, maxDist, mask, ignore, maxHits); // default 256
var swept = world.shapeCast(
  shapeType,
  halfExtents,
  origin,
  rot,
  sweep,
  mask,
  ignore,
  max
);
var ov = world.overlapSphere(center, radius, mask, ignore, max);
var ov = world.overlapBox(center, halfExtents, rot, mask, ignore, max);
var ov = world.overlapCapsule(
  center,
  radius,
  halfHeight,
  rot,
  mask,
  ignore,
  max
);
var ov = world.overlapPoint(point, mask, ignore, max); // default 256
// → GM3D_OverlapHit { node, closestPoint }
var cp = world.getClosestPointOnBody(node, worldPoint);
```

Used: camera occlusion raycast, FPS hitscan raycast with `[playerNode]` exclusion. Overlap/shapeCast are available but unused by current samples.

### Contacts and callbacks

```gml
// Per-body:
id = body.addContactCallback(function (_ev) {
  // _ev: GM3D_ContactEvent { nodeA, nodeB, point, normal,
  //   impactVelocity, type, selfNode, otherNode }
}, GM3D_EPhysicsContactEventMask.Enter);
body.removeContactCallback(id);
body.clearContactCallbacks();
body.setContactCallbacksEnabled(true);

// World poll:
var evs = world.getContactEvents();
var evs = world.getContactEventsFiltered(eventMask, layerMask, node);
var acts = world.getActivationEvents();
```

Enums: `GM3D_EPhysicsContactEvent.Enter/Stay/Exit = 0/1/2`, `...Mask.Enter/Stay/Exit/All = 1/2/4/7`. Used: coin/ammo pickups filter `type == Enter && otherNode == playerNode`, then `node.destroy(true)`.

### Constraints

Component + world factory (available, unused by current samples):

```gml
var c = new GM3D_PhysicsConstraintComponent();
// type Fixed/Point/Hinge/Slider/Cone/Distance, nodeB, pivots, axes,
// limits, cone/twist angles, spring frequency/damping, friction
world.addConstraint(c);
world.createPointConstraintBetween(a, b, pivotA, pivotB);
world.createDistanceConstraintBetween(a, b, pivotA, pivotB);
world.createHingeConstraintBetween(a, b, pivotA, pivotB, axisA, normalA);
world.createSliderConstraintBetween(a, b, pivotA, pivotB, axisA);
// + removeConstraint, setConstraintEnabled/Limits/Motor*/Pivots/Frame
```

## Character controller

New component + world interface:

```gml
var cc = new GM3D_CharacterControllerComponent();
cc.setRadius(0.33);
cc.setHalfHeight(0.92); // cylinder part, hemispheres excluded
cc.setStepHeight(0.3);
cc.setMaxSlopeAngle(degtorad(55));
cc.setLayer(GM3D_EPhysicsLayer.Character);
cc.setMass(80);
cc.setMaxStrength(160);
cc.setPredictiveContactDistance(0.12);
// + padding, penetration speed, edge removal, supporting volume,
//   push flags
node.addComponent(cc);
physicsWorld.addCharacter(node);
physicsWorld.setCharacterVelocity(node, new GM3D_Vec3(vx, vy, vz));
```

Per-frame (third-person and first-person samples):

```gml
// planar WASD from camera, vertical gravity/double-jump manual:
physicsWorld.setCharacterVelocity(playerNode, nextVel);
scene.update(dt);
physicsWorld.step(dt);
physicsWorld.interpolateForRender();
var state = physicsWorld.getCharacterGroundState(playerNode);
// OnGround | OnSteepGround | NotSupported | InAir
var vel = physicsWorld.getCharacterVelocity(playerNode);
var nrm = physicsWorld.getCharacterGroundNormal(playerNode);
var groundNode = physicsWorld.getCharacterGroundNode(playerNode);
// + setCharacterShape(node, radius, halfHeight, maxPen), characterJump(node, jumpSpeed),
//   setCharacterStickToGroundEnabled(node, enabled), getCharacterContacts(node),
//   removeCharacter(node)
```

Avatar animation follows state: `idle / walk / run / sprint / jump / fall` clips selected by name, `play` + `setSpeed` scaled by horizontal speed. Camera: third-person smoothed follow + occlusion raycast, eye-level follow + head-bob.

## Vehicles

Vehicle stack (`kenney_car-kit/race.glb` + cones):

```gml
// 1. rig node + visual + dynamic body
carRig = scene.createNode("carRig");
visual = assetCar.spawnInto(scene, carRig);
bodyNode = visual.findNodeByName("body"); // fallback: createNode + addChild
var body = new GM3D_PhysicsBodyComponent();
body.setMotionType(GM3D_EPhysicsMotionType.Dynamic);
body.setLayer(GM3D_EPhysicsLayer.Default);
body.setMass(1325);
body.setLinearDamping(0.08);
body.setAngularDamping(1.05);
var shape = new GM3D_PhysicsShapeComponent();
shape.setShapeType(GM3D_EPhysicsShapeType.ConvexHull);
shape.setFriction(0.22);

// 2. wheels (found by name wheel-*, else created)
var dims = sampleGetWheelDimensionsFromMesh(wheelNode, 0.33, 0.24);
var wheel = new GM3D_PhysicsVehicleWheelComponent();
wheel.setRadius(dims.radius);
wheel.setWidth(dims.width);
wheel.setMaxSteerAngle(isFront ? 0.5 : 0.0); // values < 0 ignored
wheel.setTrackSide(
  isLeft ? GM3D_EPhysicsTrackSide.Left : GM3D_EPhysicsTrackSide.Right
);
// + suspension dir/axes/lengths/frequency (<=0 ignored)/damping, inertia (<=0 ignored),
//   friction curves, stiffness, brake torques, driven flag

// 3. powertrain / differentials / anti-roll bars
var pt = new GM3D_PhysicsVehiclePowertrainComponent();
pt.setMaxTorque(500);
pt.setMinRPM(900);
pt.setMaxRPM(6000);
pt.setShiftUpRPM(5200);
pt.setShiftDownRPM(2200);
pt.setFinalDriveRatio(3.4);
pt.setGearCount(6);
pt.setGearRatio(i, r);
pt.setReverseGearRatio(-3.2);
pt.setClutchStrength(8.0);
pt.setAutomaticTransmission(true);

var diff = new GM3D_PhysicsVehicleDifferentialComponent();
diff.setLeftWheelIndex(li);
diff.setRightWheelIndex(ri);
// + limited slip / torque ratios

var arb = new GM3D_PhysicsVehicleAntiRollBarComponent();
arb.setLeftWheelIndex(li);
arb.setRightWheelIndex(ri);
arb.setStiffness(12000);

// 4. vehicle
var veh = new GM3D_PhysicsVehicleComponent();
// wheels/diffs/bars added as components to wheel/body nodes,
// then handles registered:
veh.addWheel(wheel);
veh.setPowertrain(pt);
veh.addDifferential(diff);
veh.addAntiRollBar(arb);
veh.setControllerType(GM3D_EPhysicsVehicleControllerType.Wheeled);
// + local up/forward, steering curves, collision tester, pitch/roll, gravity

scene.update(0.0);
physicsWorld.syncScene();
physicsWorld.addVehicle(veh);
physicsWorld.setVehicleTransmissionMode(veh, true);
physicsWorld.setVehicleTargetGear(veh, 1);
```

Per-frame:

```gml
physicsWorld.setVehicleInput(veh, throttle, steering, brake, handBrake);
// throttle/steering in [-1,1], brake/handBrake in [0,1]
if (speed > 2) physicsWorld.addForce(carNode, downforce);
// + tracked input (setTrackedVehicleInput needs non-zero left/right ratios),
//   clutch, engine running, lean controllers,
//   wheel steer/brake/omega overrides, collision tester
var kmh = physicsWorld.getVehicleSpeedMPS(veh) * 3.6;
var rpm = physicsWorld.getVehicleEngineRPM(veh);
var gear = physicsWorld.getVehicleCurrentGear(veh);
// + wheel/track state getters (getVehicleWheelState → steer rad, omega rad/s,
//   suspension m, impulses N*s), rebuildVehicle/removeVehicle
```

Motorcycle (`Motorcycle` component: lean angles/springs/smoothing) and tracked (`Tracked` component: per-side wheels/inertia/damping/brake/ratios) variants exist in the index but have no sample yet.

## FPS patterns: hitscan, pickups, debris

The Mini FPS Range sample (816-line Create) is the reference for shooters:

- Weapon visual parented to camera: `weaponNode = scene.createNode(); camNode.addChild(weaponNode); blasterAsset.spawnInto(scene, weaponNode)`.
- Aim with pointer lock: `window_mouse_set_locked(aiming)`.
- Hitscan from screen center:

```gml
var ray = camComponent.screenPointToRay({ x: 0.5, y: 0.5 });
var hit = physicsWorld.raycast(
  ray.origin,
  ray.direction,
  95,
  GM3D_EPhysicsLayer.Default | GM3D_EPhysicsLayer.Static,
  [playerNode]
);
```

- Targets: `Kinematic / Default / ConvexHull` bodies created per slot, resolved via parent-chain walk, destroyed with `physicsWorld.removeNode + node.destroy(true)` + debris burst (`Dynamic / Debris / ConvexHull` + `addLinearImpulse/AngularImpulse`) + smoke visual.
- Ammo: `Kinematic / Trigger / IsSensor` sphere + point light + `addContactCallback(..., Enter)` + bob animation via `setBodyPositionRotation` before step.
- HUD labels projected with `camComponent.worldToScreen()`, crosshair drawn in Draw GUI End, score/accuracy/combo tracked in GML (not GM3D).
- Dynamic cleanup: expired bursts `removeNode/destroy`.

## The seven official samples

| #   | Object                 | Title              | What it proves                                                                                                                                                                               |
| --- | ---------------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0   | `objSample_0_Static`   | Static Model       | `loadGltf → forEachMaterial → freeze → spawnInto`, `getBoundingSphere` auto-framing, `orbitCamera`                                                                                           |
| 1   | `objSample_1_Animated` | Animated Model     | `findAnimationComponent`, `animationCount/getAnimation`, `findAnimIndex`, `play/speed/time`, skinned shaders                                                                                 |
| 2   | `objSample_2_Scene`    | Composed Scene     | multi-asset composition, quaternion placement, dual camera split-screen (`ScreenRect/Order/Alpha`), `updateMouselook` + `moveCam`, fog volume, GUI overlay + viewport outline                |
| 3   | `objSample_3_Forest`   | Instanced Forest   | `assignShaders(src, true)`, 20k trees + 2k foxes, seeded `random_set_seed(12345)`, per-instance yaw/scale/anim-time/speed, fog to limit visible distance                                     |
| 4   | `objSample_4_Physics`  | Physics Playground | `PhysicsWorld` lifecycle, static boxes/scene shapes, character capsule, sensor coin triggers + contact callbacks, ground-state avatar switching, camera occlusion raycast, debug-draw toggle |
| 5   | `objSample_5_Vehicle`  | Vehicle Showcase   | convex-hull car body, wheel discovery + `sampleGetWheelDimensionsFromMesh`, powertrain/diff/anti-roll setup, `setVehicleInput`, speed/RPM/gear telemetry, downforce, follow camera           |
| 6   | `objSample_6_FPS`      | Mini FPS Range     | pointer-lock look, `screenPointToRay` hitscan, kinematic targets + dynamic debris impulses, sensor ammo + lights, `worldToScreen` labels, head-bob/recoil, combo scoring                     |

Navigation: `objMain` owns `samples[]`, `gotoSample/shiftSample`, `createNavButton`, `DELTA_SECONDS` macro. `objSample` parent owns `scene/renderer/assets`, `scene.update` in Step, `renderer.render` in Draw, full destroy in Clean Up. Physics children override Step/Draw/Clean Up but call `event_inherited()` to reuse the base.

Sample helpers (`scripts/`):

| Script                  | Helpers                                                                       |
| ----------------------- | ----------------------------------------------------------------------------- |
| `scrMain`               | `gotoSample`, `shiftSample`                                                   |
| `scrSampleScene`        | `loadScene`, `assignShaders(scene[, instanced])`                              |
| `scrSampleNodeFactory`  | `createCamera`, `createDirLight` (shadowed), `createEnvVolume`, `orbitCamera` |
| `scrSampleCameraInput`  | `moveCam` (planar WASD + Q/E + Shift)                                         |
| `scrSampleAnimation`    | `findAnimIndex`                                                               |
| `scrSamplePhysicsSpawn` | visual/box/scene-shape/coin/cone spawners                                     |
| `scrSampleVehicleSetup` | cone spawners, `sampleGetWheelDimensionsFromMesh`                             |
| `scrUI`                 | `CButtonBase/CButton/CIconButton`, `createNavButton`                          |

## API by type

This is a quick-reference map, not a complete reproduction of the reference.

### Scene graph

| Type             | Main members                                                                                                                                                                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GM3D_Scene`     | `createEmpty`, `loadGltf`, `createNode`, `getNode(s)`, `getMaterial(s)`, `setMaterial`, `getAnimation(s)`, `applyAnimation`, `hasAnimation`, `forEachMaterial`, `forEachNode`, `getBoundingBox/Sphere`, `spawnInto`, `freeze`, `update`, `destroy` |
| `GM3D_SceneNode` | hierarchy + `destroy(recursive?)`, direct + `find*` components, `forEachNode`, `findNodeByName`, local/world transforms + axes, `setLocalMatrix`                                                                                                   |

### Components

| Type                                | Main members                                                                                                                                                                                                                            |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GM3D_CameraComponent`              | projection, FOV/ortho, near/far (0 = infinite), target, render size, screen rect, order, alpha, enabled, `renderTexture/depthTexture`, `updateMouselook`, `screenPointToRay`, `worldToScreen`                                           |
| `GM3D_AnimationComponent`           | `play`, `pause`, `resume`, time, speed, enabled, `isPlaying`                                                                                                                                                                            |
| `GM3D_LightComponent`               | type, color, intensity, range, cone angles, enabled, shadow enabled/resolution/distance/normal-offset                                                                                                                                   |
| `GM3D_EnvironmentVolumeComponent`   | size (Vec3), ambient color, fog color/start/end, enabled                                                                                                                                                                                |
| `GM3D_MeshComponent`                | mesh, material, enabled, flags                                                                                                                                                                                                          |
| `GM3D_SkinnedMeshComponent`         | mesh, material, enabled, flags, `jointCount`                                                                                                                                                                                            |
| `GM3D_PhysicsBodyComponent`         | motion type, layer, mass, damping, gravity, sensor, awake, quality, sleeping, COM, locks, groups, contact callbacks                                                                                                                     |
| `GM3D_PhysicsShapeComponent`        | shape type, half extents, offset, rotation, friction, restitution                                                                                                                                                                       |
| `GM3D_PhysicsConstraintComponent`   | type, nodes, pivots, axes, limits, cone/twist, springs, friction                                                                                                                                                                        |
| `GM3D_CharacterControllerComponent` | radius, half-height, slope, step, layer, mass, strength, prediction, padding, recovery, edge removal, push flags                                                                                                                        |
| `GM3D_PhysicsVehicle*`              | Wheel, Powertrain, Differential, AntiRollBar, Motorcycle, Tracked, Vehicle                                                                                                                                                              |
| `GM3D_PhysicsWorld`                 | construct, gravity, sync/add/remove/rebuild, step/interpolate/restore, velocities/forces/impulses, raycast/overlap/shapeCast/closest-point, contacts/activations, layers/groups, constraints, characters, vehicles, debug draw, destroy |

### Resources and rendering

| Type             | Main members                                                                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GM3D_Renderer`  | `render(scene, deltaTime?)`                                                                                                                                               |
| `GM3D_Material`  | `getShader` (undefined = default) / `setShader` per pass `[0, 255]`, `get/setTexture` by name (no enumeration), float/int/array uniforms, full blend/depth/stencil/cull/alpha/fog/lighting state, `getName/setName`, clone/destroy |
| `GM3D_Shader`    | `get/setGlobal` Float/FloatArray/Int/IntArray/Texture                                                                                                                     |
| `GM3D_Texture`   | static sampler get/set: Filter, Repeat, MaxAniso, Min/MaxMip, MipBias, MipEnable/MipFilter (ids are opaque int32, no readback)                                           |
| `GM3D_Mesh`      | name, buffer/format/primitive, skinning, `getBoundingBox`                                                                                                                 |
| `GM3D_Animation` | `path`, `duration`                                                                                                                                                        |
| Hits             | `GM3D_RaycastHit{node,point,normal,distance}`, `GM3D_OverlapHit{node,closestPoint}`, `GM3D_ContactEvent{nodeA,nodeB,point,normal,impactVelocity,type,selfNode,otherNode}` |

### Enums

```gml
GM3D_ECameraProjection.Perspective / Orthographic
GM3D_ECameraRenderSizeMode.Auto / Fixed
GM3D_ECameraTarget.Screen / Texture
GM3D_ELightType.Directional / Point / Spot
GM3D_EMeshComponentFlags.CastShadows(=1) / ReceiveShadows(=2)
GM3D_ERenderPass.Shadow(=0) / Forward(=1) / Custom(=2 + N)
// Physics:
GM3D_EPhysicsMotionType.Static / Kinematic / Dynamic
GM3D_EPhysicsShapeType.Box / Sphere / Capsule / Cylinder / Mesh / ConvexHull / ConvexDecomposition
GM3D_EPhysicsLayer.Static(=1) / Default(=2) / Character(=4) / Trigger(=8) / Debris(=16) / All(=31)
GM3D_ECharacterGroundState.OnGround / OnSteepGround / NotSupported / InAir
GM3D_EPhysicsConstraintType.Fixed / Point / Hinge / Slider / Cone / Distance
GM3D_EPhysicsContactEvent.Enter / Stay / Exit
GM3D_EPhysicsContactEventMask.Enter(=1) / Stay(=2) / Exit(=4) / All(=7)
GM3D_EConstraintMotorMode.Off / Velocity / Position
GM3D_EPhysicsMotionQuality.Discrete / LinearCast
GM3D_EPhysicsAxisLock.None / X / Y / Z / All
GM3D_EPhysicsVehicleControllerType.Wheeled / Motorcycle / Tracked
GM3D_EPhysicsVehicleCollisionTesterType.Ray / CastSphere / CastCylinder
GM3D_EPhysicsTrackSide.Left / Right
```

## Documentation limits

- The upstream index lists signatures + one-line descriptions, not semantics, units (mostly metres / seconds / radians - verify per method), or error cases.
- Constraint, motorcycle, tracked, overlap, and shape-cast APIs are indexed but have no sample coverage - behavior unverified here.
- `.glb` is the only format demonstrated; physics `Mesh` shape fidelity, skinning limits, and platform performance are not documented upstream.
- Textures: no binding enumeration (`getTexture` needs exact uniform names; unknown names return `undefined`), ids are opaque `int32` (sampler state only, no CPU readback or GM surface/sprite conversion), and `getShader` returning `undefined` is documented behavior rather than an error.

## Sources

- `https://github.com/YoYoGames/GM3D-Samples` (`scripts/`, `objects/`, `shaders/`, `notes/GM3D_API.md` - the API index is the authority for signatures; verified here against branch `develop`).
