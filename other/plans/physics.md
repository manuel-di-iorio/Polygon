# Revisione confermata — 2026-10-22

Questa revisione sostituisce le decisioni incompatibili nelle sezioni successive del piano. I dettagli architetturali restano validi solo dove non contraddicono questa sezione.

## Obiettivo e perimetro V1

Integrare nell'editor Polygon i collider GM3D per oggetto, la visualizzazione debug, le impostazioni fisiche per oggetto e per mondo e la configurazione del character controller. V1 comprende **Body + Shape + Character**. La modalità editor resta di sola visualizzazione: nessuno step o anteprima di simulazione.

- Modalità: `none`, `static`, `kinematic`, `dynamic`, `character`. Un trigger è un body sensore, non una modalità.
- Un oggetto è fisico se `physics.mode != "none"` oppure se nasce da un prefab con default physics.
- Il blocco `physics` opzionale per istanza vive nel descrittore dell'istanza; se assente, l'istanza non è fisica.
- I default physics dei prefab vivono nella mappa top-level `assets`, accanto ad `actor`; si applicano solo a nuovi spawn e duplicati.
- I dati `world` vivono al top-level della scena: `gravity`, `fixedTimeStep`, `maxSubSteps`, `maxBodies`.
- JSON resta `version: 1` con campi opzionali. Il binario PLYB passa a v2 e mantiene la lettura v1.
- Shape V1: Box, Sphere, Capsule, Cylinder. Mesh/ConvexHull restano sperimentali fino allo spike. Fuori scope: constraints, veicoli, ragdoll, collider composti, anteprima simulazione e matrice layer.

## Inspector, prefab e cronologia

Le impostazioni World non hanno un pannello separato né una finestra dockable. La UI usa l'Inspector nello stato senza selezione:

- nessun oggetto e nessun prefab selezionato: suggerimento + `__poly_imgui_world_sec(_ed)`;
- prefab selezionato: resta l'Inspector prefab esistente;
- oggetto selezionato: Inspector oggetto.

Il comportamento di selezione prefab non cambia: il suo Inspector ha precedenza sulla sezione World. Non creare `win_world`, una finestra World dockable o `poly_imgui_world.gml`.

Le impostazioni World partecipano a undo/redo: gli snapshot includono `world` e `__poly_history_commit` lo confronta. I default physics del prefab si applicano soltanto a nuovi spawn/duplicati, senza alterare istanze già esistenti.

## Debug collider nell'editor

Usare il debug draw nativo GM3D, `GM3D_PhysicsWorld.setDebugDrawEnabled`, controllato da un pulsante icona nella toolbar. La modalità mostra i collider ma non simula.

Il debug world è uno snapshot statico: crearlo pigramente quando `show_colliders` viene attivato, abilitare `setDebugDrawEnabled(true)`, chiamare `syncScene()`, aggiungere i character e non chiamare mai step/interpolate/restore. Ricostruirlo dopo modifiche strutturali o ai dati fisici e distruggerlo prima della scena.

## Character

Il capsule character è centrato sull'origine del wrapper. Il modello visuale viene allineato tramite `character.visualOffset`, automatico ma modificabile; offrire un'azione Recenter.

## Fasi aggiornate

1. **Fase 0 — spike API (da completare):** verificare che `setDebugDrawEnabled` renda i collider senza simulazione; verificare il rapporto tra scala del nodo e half-extents; verificare Mesh/ConvexHull con mesh figlia del wrapper. Annotare risultati e limiti prima di esporre le shape sperimentali.
2. **Fase 1 — dati e runtime comune (implementata, da validare):** `poly_physics` per apply/read/validate/fit/default World; `physics` nei descrittori istanza e `world` al top-level; JSON v1 e PLYB v2 con lettura v1; caricamento runtime e report physics.
3. **Fase 1 — UI e debug editor (implementata, da validare):** Inspector Body/Shape, toolbar e scorciatoia `P`, debug world statico; impostazioni World nello stato Inspector senza selezione. La sezione prefab conserva la precedenza.
4. **Fase 2 — character e prefab (implementata, da validare):** controller, capsule centrata sul wrapper, `visualOffset` automatico/modificabile con Recenter, default fisici applicati alle nuove istanze e helper runtime.
5. **Fase 3 — integrazioni (implementata, da validare a runtime):** physics mantenuta in duplicate, copy/cut/paste e bridge AI; adozione della fisica anche nel track manuale e automatico; tooltip aggiunti a controlli Physics, Physics World, default prefab e flag Shadows. Restano le verifiche runtime e l'eventuale spike Mesh/ConvexHull.
6. **Fase 5 — Shape Mesh e ConvexHull (implementata):** Mesh e ConvexHull validate a runtime con mesh figlia del wrapper; abilitate nelle shape selezionabili (Inspector singolo e prefab) senza etichetta sperimentale. Mesh usa la geometria della mesh (ideale per statici), ConvexHull l'involucro convesso (adatto anche a dinamici).
7. **Fase 4 — Trigger di gioco (parzialmente implementata):** il sensore è già rappresentato come body sensore (`isSensor` + layer `Trigger`); aggiunti i flag evento `triggerEnter`/`triggerStay`/`triggerExit` ai dati physics, all'Inspector e alla validazione; documentato il contratto runtime (payload `GM3D_ContactEvent`, callback dopo `step()`, cleanup). Resta la verifica runtime di più sensori, ordine eventi, distruzione/rimozione e rebuild.
8. **Fase 6 — Collider composti (parzialmente implementata):** aggiunto il campo opzionale `shapes` (array di shape locali con tipo, dimensioni, offset e rotazione) ai dati physics, alla normalizzazione e alla validazione; backward-compatible con la shape singola V1. Restano UI lista/add/remove, apply multi-shape e verifica runtime dei limiti GM3D.
9. **Fase 7 — Vincoli/giunti (parzialmente implementata):** aggiunto campo opzionale `constraint` ai dati physics (tipo, nodeB, pivotA/B, axisA, limiti, motore), normalizzazione, validazione, UI nell'Inspector (tipo + target id) e rimozione componente su re-apply. Il gioco crea il giunto dal payload dopo `syncScene()` via `world.createXConstraintBetween`/`addConstraint`. Restano pivot/assi/limiti/motore nell'UI, validazione riferimenti mancanti, duplicazione e rebuild.
10. **Fase 8 — Veicoli (parzialmente implementata):** aggiunto campo opzionale `vehicle` ai dati physics (mass, damping, friction, ruote, powertrain, gears, clutch, anti-roll), normalizzazione, validazione e UI nell'Inspector (sezione Vehicle per body dinamici). Il gioco costruisce il veicolo dai dati dopo `syncScene()` (convex hull, ruote, powertrain, differenziali, anti-roll). Restano UI avanzata (curve sterzo, collision tester, pitch/roll) e verifica runtime.
11. **Fase 10 — Matrice collisioni (implementata):** aggiunta matrice layer-layer 5x5 ai dati World, normalizzazione, applicazione nel debug world e UI nel pannello Physics World (checkbox per ogni coppia). Resta la verifica runtime che `setLayerCollision` venga applicato anche al world di gioco.
12. **Fase 9 — Ragdoll (non implementata):** resta nella roadmap documentata; richiede validazione runtime (bone mapping, blend animazione/fisica).

### Lavoro svolto in questa implementazione

- Aggiunti dati e applicazione GM3D per Body, Shape, Character e World, senza simulazione nell'editor.
- Aggiunte impostazioni per istanza e default prefab, Inspector World nello stato senza selezione, undo/redo e rebuild della visualizzazione debug.
- Aggiornati salvataggio/caricamento, formati JSON/PLYB e bridge runtime/AI; PLYB v2 conserva la lettura dei file v1.
- Aggiunti tooltip descrittivi ai parametri fisici, alle azioni Fit/Clear/Recenter, ai parametri World, ai default prefab e alle checkbox Shadows Cast/Receive.
- Corretto un accesso a `physics` opzionale che causava `ReferenceError` aprendo l'Inspector; aggiunti controlli analoghi ad altri campi opzionali. Va confermato nel runtime che l'errore non si ripresenti.
- In un avvio runtime sono comparsi warning GM3D che clampano `m_maxBodyPairs` e `m_maxContactConstraints` da 65536 a 1024. Non è ancora verificato se siano innocui nel percorso debug; la documentazione API disponibile non indica opzioni pubbliche per quei limiti.
- Il duplicate conserva la fisica dell'istanza sorgente (mode, shape, body, controller e `visualOffset`); se la sorgente non è fisica resta il default prefab applicato dallo spawn. Copy/cut/paste passano dai descrittori e quindi conservano il blocco `physics`.
- Il track manuale (`poly_track`) e l'adozione automatica (`__poly_track_adopt_auto`) ora leggono body/shape/character dal nodo live nella stessa helper di piazzamento, così una scena con fisica non viene reimportata come solo visuale.
- Aggiunto il badge fisica nella gerarchia (`S` static, `K` kinematic, `D` dynamic, `C` character, `T` sensore) con tooltip su mode e shape.
- Aggiunta la sezione Physics per la multiselezione: Mode, Layer e Mass comuni, valore `Mixed` quando differiscono, applicazione a tutte le istanze selezionate in un singolo passo di undo.
- Normalizzati i nomi dei layer e clampati i parametri del character in `__poly_physics_data`; aggiunte le letture live di `character.mass` e `character.maxStrength`.
- Aggiunto `__poly_physics_data_auto` per i percorsi di apply diretti (bridge AI): quando il character viene aggiunto a un nodo esistente senza `visualOffset` esplicito, il modello viene centrato sulla capsula.
- Il debug world viene distrutto in disattivazione e su nuova scena, ricostruito dopo nuova scena, paste, undo/redo, modifiche fisiche e caricamento; la nuova scena ripristina anche i default World.
- Aggiornato `README.md` con multiselezione, conservazione della fisica in duplicate/copy/paste/track e il contratto trigger (eventi Enter/Stay/Exit, payload, cleanup).
- Esteso `__poly_imgui_prefab_physics` per esporre tutte le opzioni fisiche (layer, damping, friction, restitution, gravity factor, sensor, half-extents, offset, parametri character, trigger events), non solo mode/shape/mass.
- Fase 6: aggiunto campo opzionale `shapes` (array di shape locali: tipo, halfExtents, offset, rotation) ai dati physics, alla normalizzazione e alla validazione; backward-compatible (se assente si usa la shape singola). UI/apply multi-shape restano come lavoro successivo.
- Fase 8: aggiunto campo opzionale `vehicle` ai dati physics (enabled, mass, damping, friction, wheel radius/width/count, steer, powertrain, gears, clutch, anti-roll), normalizzazione, validazione e UI nell'Inspector (sezione Vehicle per body dinamici) con toggle Enable.
- Fase 10: aggiunta matrice di collisione layer-layer (5x5) ai dati World, normalizzazione, applicazione nel debug world e UI nel pannello Physics World (checkbox per ogni coppia di layer).
- Fase 9 (ragdoll) resta nella roadmap documentata: richiede validazione runtime (bone mapping, blend animazione/fisica) e non è stata implementata.
- Fase 7–10 (giunti, veicoli, ragdoll, matrice collisioni/query) restano nella roadmap documentata: richiedono validazione runtime GM3D e sono fuori dal perimetro implementato in questa sessione.

### Blocco di validazione noto

Il runtime/compiler GameMaker-LTS2026 installato (`runtime-2026.0.0.23`) rifiutava le espressioni ternarie nidificate (operatore `? :` concatenato senza parentesi) in `poly_bin`, `poly_camera`, `poly_gizmo`, `poly_imgui_chrome`, `poly_imgui_insp_fields`, `poly_imgui_insp_prefab`, `poly_library`, `poly_load_internal`, `poly_physics`, `poly_serialize`, più un argomento in più in una chiamata `sprite_add` in `poly_imgui_viewport`. Queste espressioni sono state parentesizzate (o riscritte con `if/else` dove più chiaro) e l'argomento superfluo rimosso; la build Igor ora termina con exit code 0 (`output/polygon/polygon.win` generato). Il codice aggiunto in questa fase non usa nuovi ternari e non ha prodotto errori propri.

La validazione runtime resta bloccata da una dipendenza esterna: il progetto usa `GM3D_Scene`/`GM3D_PhysicsWorld` (libreria GM3D) che non è bundlata nel repository né installata in questo ambiente. La compilazione riesce (i riferimenti sono globali risolti a runtime), ma l'esecuzione si ferma su `GM3D_Scene(100717, -2147483648) not set before reading it` in `demo_create`. Serve importare/installare la libreria GM3D nel progetto per eseguire l'editor. La correzione dei ternari e dei path di apply/debug è comunque verificabile staticamente e a compile-time.

### Prossimo passo

1. Importare/installare la libreria GM3D nel progetto (o eseguirlo da un ambiente dove è già disponibile) e poi riprodurre l'apertura dell'Inspector per confermare la correzione del `ReferenceError`.
2. Attivare/disattivare il debug collider e confermare che i warning di clamp non diventino errori e che i collider restino visibili senza `step`, `interpolateForRender` o `restoreSimulationPositions` nell'editor.
3. Verificare visivamente scala nodo vs half-extents per Box, Sphere, Capsule e Cylinder; correggere fit e tooltip se il comportamento osservato differisce.
4. Provare Mesh/ConvexHull con mesh figlia del wrapper. Tenerle fuori dalle shape selezionabili se lo spike non conferma supporto corretto.
5. Completare la verifica di duplicate/copy/paste, badge gerarchia, multiselezione e round-trip di undo/redo e salvataggio JSON/PLYB; annotare gli esiti qui prima di chiudere le fasi.

### Roadmap successiva — dopo la validazione V1

Le fasi sotto sono proposte successive alla verifica runtime della V1 e vanno affrontate in ordine di dipendenza. I sistemi avanzati restano fuori dal perimetro V1 finché non viene approvata la relativa fase.

#### Fase 4 — Trigger di gioco

La V1 rappresenta già il trigger come body sensore (`isSensor`), non come modalità fisica autonoma. Prima di ampliare l'editor, verificare che la scelta del layer `Trigger` e il flag `Sensor` producano un comportamento coerente; mantenere un'unica invariante chiara per il body sensore.

- Definire gli eventi supportati dal contratto Polygon (almeno inizio e fine overlap, se GM3D li distingue in modo affidabile).
- Definire il payload runtime stabile: identificativi dei due nodi, tipo evento ed eventuali dati di contatto disponibili.
- Esporre gli eventi al gioco dopo `GM3D_PhysicsWorld.step()` tramite helper/callback documentati; l'editor continua a non simulare.
- Verificare più sensori, distruzione/rimozione dei nodi, ordine degli eventi e compatibilità con load/rebuild.
- Non aggiungere una modalità `trigger`: si configura un body sensore attraverso i dati physics esistenti.

#### Fase 5 — Collider Mesh e Convex

Abilitare le shape sperimentali solo dopo gli spike con mesh figlia del wrapper e la verifica di scala/rotazione.

- Provare `Mesh`, `ConvexHull` e, se disponibile e valido nella versione GM3D usata, `ConvexDecomposition` su asset rappresentativi.
- Determinare compatibilità con body statici/dinamici, mesh skinned, gerarchie figlie, trasformazioni e salvataggio/caricamento.
- Documentare limiti di precisione, costo di cooking/performance e casi non supportati.
- Esporre nell'Inspector soltanto le shape validate; segnalare esplicitamente quelle che restano sperimentali.

#### Fase 6 — Collider composti

- Passare dal singolo `physics.shape` a una lista versionabile di shape locali per istanza, ciascuna con tipo, dimensioni, offset e rotazione.
- Aggiungere nell'Inspector lista, aggiunta/rimozione, selezione e modifica delle shape; includere preview debug, undo/redo e duplicazione.
- Aggiornare validazione, JSON, PLYB e caricamento runtime mantenendo la lettura dei dati V1 come singola shape.
- Verificare quali combinazioni e limiti di numero componenti sono supportati da GM3D.

#### Fase 7 — Vincoli e giunti

- Definire il formato per joint tra due istanze: tipo, riferimenti stabili ai nodi, ancoraggi locali, assi, limiti e parametri opzionali di motore.
- Implementare selezione dei corpi collegati e UI per configurazione/visualizzazione del joint.
- Validare riferimenti mancanti, cancellazione o duplicazione di un corpo collegato, prefab e rebuild della scena.
- Aggiornare undo/redo, serializzazione e helper runtime; i vincoli non entrano nei dati V1.

#### Fase 8 — Veicoli

- Modellare il veicolo come configurazione collegata al body: wheel nodes, assi/posizioni, raggio e larghezza, sospensione e sterzo.
- Aggiungere configurazione di powertrain, cambio, differenziale e anti-roll; includere collision tester e validazione dei riferimenti alle ruote.
- Creare UI per assegnare e ispezionare le ruote e visualizzarne i parametri senza simulazione editoriale.
- Esporre helper runtime per input (acceleratore, sterzo, freno, freno a mano) e lettura di velocità/stato ruote.
- Provare veicoli a ruote e decidere separatamente se supportare moto o veicoli cingolati.

#### Fase 9 — Ragdoll

- Mappare nodi/corpi ai bone di una mesh skinned e definire joint e collider per segmento.
- Gestire passaggio tra animazione e controllo fisico, sincronizzazione dello scheletro e ritorno all'animazione.
- Costruire una UI di setup scheletrico e uno strumento debug per collider e giunti.
- Verificare costi, limiti di rig e serializzazione prima di definire un formato stabile.

#### Fase 10 — Matrice collisioni e query

- Aggiungere una matrice layer-layer con regole di collisione modificabili e salvate a livello World.
- Valutare strumenti editor non simulati per raycast/overlap di diagnostica e documentare la differenza rispetto alle query runtime.
- Includere migrazione per scene esistenti e undo/redo delle regole World.

#### Fase 11 — Eventuale anteprima di simulazione editoriale

Resta fuori scope finché non viene richiesta e progettata separatamente. Dovrà usare un world temporaneo isolato, controlli Play/Pause/Reset e ripristino deterministico dei transform, senza riusare o contaminare il world statico impiegato dal collider debug.

---
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
