# Piano: Fisica in Polygon (GM3D 0.22.4)

## 1. Obiettivo

Integrare la fisica GM3D nell'editor come **dati serializzati**, senza portare dentro un engine esterno.

- L'editor salva solo dati `physics` per-istanza + default per-modello.
- Il gioco possiede il `GM3D_PhysicsWorld` e simula a runtime via `poly_load`.
- Nessuna simulazione o world fisico dentro l'editor: solo editing dati + visualizzazione collisori.

Riferimento API: `other/GM3D.md` (sezione Physics), branch `develop` di GM3D-Samples.

## 2. Vincoli confermati

- GM3D = scene-graph + simulazione parallela (`GM3D_PhysicsWorld`).
- Ordine obbligatorio a runtime: `input -> scene.update(dt) -> world.step(dt) -> world.interpolateForRender() -> render -> world.restoreSimulationPositions()`.
- Registrazione una tantum dopo `scene.update(0.0)`: `syncScene()` oppure `addNode / addTree`.
- Distruzione inversa: prima `world.destroy()`, poi `scene.destroy()`.
- GameMaker Box2D 2D non usato: solo componenti GM3D.
- V1 = solo `Body + Shape`. Fuori scope: Character, Vehicle, Constraint, query avanzate (`shapeCast`, `overlap*`).

## 3. Modello dati

### 3.1 Descrittore per-istanza

Campo opzionale `physics` su descrittore `kind: "instance"`, parallelo a `shadows`:

```json
{
  "kind": "instance",
  "id": "__PolygonEditor__3",
  "assetId": "models/crate.glb",
  "transform": {
    "position": [0, 0, 0],
    "rotation": [0, 0, 0, 1],
    "scale": [1, 1, 1]
  },
  "shadows": { "cast": true, "receive": true },
  "physics": {
    "motion": "Static",
    "shape": "Box",
    "layer": 1,
    "mass": 1.0,
    "linearDamping": 0.05,
    "angularDamping": 0.05,
    "gravityFactor": 1.0,
    "isSensor": false,
    "friction": 0.8,
    "restitution": 0.0,
    "halfExtents": [0.5, 0.5, 0.5],
    "offset": [0, 0, 0]
  }
}
```

Assenti = `shape: "None"` = nessun componente fisico (comportamento attuale).

Mapping diretto sui setter GM3D:

Body (`GM3D_PhysicsBodyComponent`):
- `motion` -> `setMotionType(GM3D_EPhysicsMotionType.Static|Kinematic|Dynamic)`
- `layer` -> `setLayer(...)` (1=Static, 2=Default, 4=Character, 8=Trigger, 16=Debris)
- `mass`, `linearDamping`, `angularDamping`, `gravityFactor`, `isSensor`
- default V1: `setStartAwake(true)`, `setMotionQuality(Discrete)`, `setAllowSleeping(true)`

Shape (`GM3D_PhysicsShapeComponent`):
- `shape` -> `setShapeType(Box|Sphere|Capsule|ConvexHull|Mesh)`
- `halfExtents` -> `setHalfExtents(GM3D_Vec3)` (per Sphere/Capsule: `x=radius, y=half-height`)
- `offset` -> `setLocalOffset(...)`, `friction` clamp `[0,1]`, `restitution` clamp `[0,1]`

V1 supporta `Box, Sphere` + `ConvexHull` best-effort. `Mesh, Capsule, Cylinder, ConvexDecomposition` in fase 2 (nota: range setter `[0,5]` da verificare a runtime per `ConvexDecomposition=6`).

### 3.2 Default per-modello

Come `actor` in `__poly_write_file_assets`:

```json
"assets": {
  "models/crate.glb": {
    "type": "model",
    "physics": { "motion": "Dynamic", "shape": "Box", "mass": 2.0 }
  }
}
```

Regole:
- default = suggerimento allo spawn, non vincolo.
- override per-istanza salvato nel nodo.
- se `actor.object` mancante si avverte senza fallire: stessa tolleranza per `physics` invalido.

## 4. Architettura

### 4.1 Dove vivono i componenti

Sul **wrapper**, non sul model-root.

Motivo: invariante attuale `poly_registry.gml` = wrapper vuoto -> model root con transform resettato (`__poly_spawn_reset_child`). Luci/camere/env sono già così. Body+shape sul wrapper = transform editor = transform fisico, visual figlio con offset/scale indipendenti (stesso pattern dei sample vehicle/physics).

### 4.2 Registry

Estendere `en.data`:

```gml
en.data = {
  castShadows: bool,
  receiveShadows: bool,
  physics: undefined | { motion, shape, layer, mass, ... }
}
```

Nuovi helper (stile `__poly_flags_*`):
- `__poly_physics_read(node)` -> struct da componenti live.
- `__poly_physics_apply(wrapper, data)` -> crea/aggiorna `body+shape`.
- `__poly_physics_clear(wrapper)` -> rimuove componenti.
- `__poly_physics_fit(ed, node)` -> calcola `halfExtents` da `asset.getBoundingBox()` / `getBoundingSphere()`.

### 4.3 Spawn pipeline

Estendere `__poly_spawn` (`poly_registry.gml:409`):
1. `createNode(id)` -> `spawnInto` -> reset child -> TRS wrapper (invariato).
2. se `_opt.data.physics` valido: `__poly_physics_apply`.
3. hook `on_create` invariato.
4. `__poly_kind_register` con `data` esteso.

Tocca anche:
- `__poly_place`, `__poly_track_place_asset`
- `__poly_track_adopt_auto`: deve leggere `body+shape` dal nodo live via `__poly_physics_read` e copiarli nel wrapper editor; senza questo, aprire l'editor su una scena con fisica la reimporta come visuali puri (fisica silenziosamente persa)
- `__poly_rebuild_place_asset` (ricrea da descrittore)

### 4.4 Nessun world in editor

L'editor **non** crea mai un `GM3D_PhysicsWorld`: niente `syncScene`, `step`, `interpolateForRender`, `restoreSimulationPositions` o `destroy` lato editor.

I componenti `body+shape` possono esistere sui wrapper come dati, ma restano inerti finché il gioco non crea il proprio world a runtime. Gizmo, drag e undo lavorano solo su TRS.

Ownership (già così per le scene, vale anche per la fisica):
- l'editor possiede solo la sua scena (`GM3D_Scene.createEmpty()` in `__poly_create_rt`); `live_scene` è un ref non-owning per l'import.
- il gioco possiede `live_scene` + il suo `PhysicsWorld`; l'editor non li distrugge né vi registra nodi.
- mai passare il `PhysicsWorld` del gioco all'editor.

## 5. Inspector UI

Nuovo file `poly_imgui_insp_physics.gml`, sezione `Physics` per selezione singola `kind=="instance"` (dopo `Shadows`, prima di `Materials` in `poly_imgui_inspector.gml:173`):

- `Enable collision` (shape None <-> Box)
- `Shape: [Box|Sphere|ConvexHull|Mesh]` (Mesh disabilitato in V1 o con warning)
- `Body: [Static|Kinematic|Dynamic]`
- `Layer: [Static|Default|Character|Trigger|Debris]` (+ bitmask avanzata dopo)
- `Mass, Linear/Angular damping, Gravity factor`
- `Friction [0,1], Restitution [0,1], IsSensor`
- `HalfExtents XYZ, Offset XYZ` (widget assi esistenti)
- Bottoni: `Fit to mesh`, `Clear`

Multiselezione: mostra solo `Motion/Layer/Mass` comuni, come già fai per Transform.

Prefab overrides: includi `physics` nel menu Revert/Apply esistente.

## 6. Serializzazione

File: `scripts/poly_serialize/poly_serialize.gml`

- `__poly_asset_desc`: legge `en.data.physics` + fallback `asset_meta`.
- `__poly_node_desc`: include `physics` solo se `shape != "None"`.
- `__poly_validate_asset_desc`: valida nuovo sottostruct (shape/motion enum, `halfExtents` num3, `offset` num3, `friction/restitution` real).
- `__poly_rebuild_place_asset`: passa `physics` in `_opt.data`.
- `__poly_write_file_assets`: overlay `physics` default per-modello.
- Compatibilità: resta `version: 1` perché il campo è opzionale; i file vecchi caricano con `physics=None`.

Validazione tollerante: `motion/shape` sconosciuti -> `None` + `report.warnings`, mai throw (stesso principio actor).

## 7. Runtime `poly_load`

`poly_load(scene, path, assets, on_create?, on_finish?)` deve:

1. `spawnInto` come ora.
2. applicare `physics` dal descrittore via stesso `__poly_physics_apply` (codice condiviso editor/game, come `__poly_flags_apply_data`).
3. chiamare `on_create` globale + per-modello dopo i componenti (ordine attuale invariato).
4. `report.placements[i].physics` esposto per debug.

Il gioco poi fa il setup standard GM3D:

```gml
scene.update(0.0);
physicsWorld = new GM3D_PhysicsWorld(scene, {maxBodies:512, fixedTimeStep:1/60, maxSubSteps:4});
physicsWorld.setGravity(new GM3D_Vec3(0, -9.81, 0));
physicsWorld.syncScene();
```

Nessuna dipendenza Polygon a runtime oltre i dati: se il gioco non crea il world, i componenti restano inerti.

### 7.1 Contratto gioco-aperto-con-world (obbligatorio)

Se il gioco ha un `PhysicsWorld` e poi apre l'editor:

1. **Pausa totale mentre l'editor è attivo** (come già `oGame/Step_0` e `Draw_0` fanno per `demo_step/demo_draw`):

```gml
// oGame Step
if (!poly_is_active()) {
  scene.update(dt);
  physicsWorld.step(dt);
  physicsWorld.interpolateForRender();
  // ... letture gameplay ...
}
// oGame Draw
if (!poly_is_active()) {
  renderer.render(scene);
  physicsWorld.restoreSimulationPositions();
}
```

Senza pausa il world continua a simulare in background una scena invisibile e le posizioni divergono da quelle importate dall'editor.

2. **Import con fisica**: `__poly_import_live` (su ogni `poly_enable`) deve adottare anche `body+shape`, non solo TRS/luci/camere.
3. **Close con rebuild**: `__poly_deactivate` chiama solo `on_close` e non ripusha nulla. Il gioco in `on_close` deve ricostruire la `live_scene` dai descrittori editor (stesso percorso di `poly_load`) e poi fare `scene.update(0)` + `world.syncScene()` (o `rebuildNode` per i nodi toccati). Se riprende semplicemente la vecchia scena, le modifiche editor sono perse e restano i vecchi body.

## 8. Viewport

- Wireframe collisori calcolato dai dati (niente world): verde=Static, giallo=Dynamic, blu=Kinematic, rosso=Sensor.
- Picking invariato (ID-buffer). I nodi sensor restano selezionabili/trasformabili.

## 9. AI bridge

Estensione minima in `poly_ai`:
- `details` include `physics`.
- `create/transform/batch` accettano `physics` opzionale.
- nessun nuovo op fisico in V1 (`raycast_down` resta geometrico, non `world.raycast`).

## 10. Fasi di implementazione

### Fase 1 - Dati + spawn
- [ ] `__poly_physics_*`: read/apply/clear/fit/validate
- [ ] registry `en.data.physics`
- [ ] `__poly_spawn` + rebuild + adopt (incluso adopt di body+shape da scena live)
- [ ] test: spawn programmatico static/dynamic, `scene.update(0)` senza crash

### Fase 2 - Save/load
- [ ] serialize/deserialize/validate `physics`
- [ ] `asset_meta` default per-modello
- [ ] `poly_load` runtime + report
- [ ] test: round-trip JSON, file v1 senza physics, file con physics corrotto

### Fase 3 - Inspector + viewport
- [ ] `poly_imgui_insp_physics.gml` + sezione in inspector
- [ ] Fit to mesh da bounds
- [ ] overrides Revert/Apply
- [ ] wireframe collisori da dati
- [ ] test: edit -> save -> reload, undo/redo conserva physics

### Fase 4 - Polish
- [ ] `details` AI con physics
- [ ] docs `README.md` + sample `scr_demo` con casse
- [ ] Capriccio: `Capsule/Cylinder/Mesh` se verificato a runtime

## 11. File impattati (stima)

- `scripts/poly_registry/poly_registry.gml` - spawn, adopt, nuovi helper physics
- `scripts/poly_serialize/poly_serialize.gml` - descrittori, validazione, rebuild, file assets
- `scripts/poly_imgui_inspector/poly_imgui_inspector.gml` - dispatcher sezione
- `scripts/poly_imgui_insp_physics/poly_imgui_insp_physics.gml` - **nuovo**
- `scripts/poly_load*/poly_load*.gml` - apply a runtime + report
- `scripts/poly_history/poly_history.gml` - snapshot physics in undo/redo
- `scripts/poly_ai/poly_ai.gml` - `details` esteso
- `README.md`, `other/GM3D.md` - docs

## 12. Rischi

- `ConvexDecomposition` ha range dichiarato `[0,5]` contro enum `0..6` - verificare a runtime prima di esporlo.
- `Mesh` shape su mesh complesse: costo CPU, meglio `ConvexHull` di default.
- Mass/damping estremi instabili: clamp UI (`mass > 0`, `damping >= 0`).
- Simulazione in background con editor aperto: se il gioco non mette in pausa `step/interpolate/restore` sotto `poly_is_active()`, live e editor divergono.
- `world.syncScene()` dopo rebuild live registra tutto: nodi chrome/grid/sky/camera editor non devono finire nel world di gioco (import solo da descrittori `instance`).

## 13. Criteri di accettazione V1

- Creo Box statico + Sphere dinamica da Inspector, salvo, ricarico, ritrovo tutto.
- `poly_load` senza world non crasha; con world i corpi cadono/collidono.
- Apro l'editor su scena con fisica: i body vengono adottati (non persi); chiudo e `on_close` ricostruisce live + `syncScene`.
- Con editor aperto il gioco non avanza `step/interpolate/restore`.
- File v1 esistenti continuano a caricarsi.
