# ADR-0001: Базовая архитектура Blueprint Editor

- **Статус:** Принято (Accepted)
- **Дата:** 2026-09-03
- **Контекст:** Это исходный design-документ мода, зафиксированный как ADR-0001 — базовый (baseline) для всех последующих архитектурных решений. ADR по конвенции неизменяемы после принятия: любое новое архитектурное решение фиксируется отдельным ADR (0002 и далее), который может дополнять или заменять (superseded) часть этого документа — сам файл не редактируется задним числом. Живой статус выполнения фаз вынесен в отдельный документ `docs/roadmap.md`, чтобы не нарушать неизменяемость этого ADR.

Статус: **design only — реализация ещё не начата на момент принятия этого ADR**. Документ фиксирует архитектуру и обоснование, согласованные до написания кода мода.

## 1. Overview & Goals

The mod lets a Factorio player create or edit a blueprint by placing entities and tiles directly, instead of the vanilla workflow (build for real in the world, then capture the area as a blueprint, then only ever *remove* things from what was captured).

### Why build this instead of reusing an existing mod

The first pass at this justification only checked whether an existing mod already covers our exact feature niche. That's a weak test — a mod can occupy adjacent territory and still be the better choice if reuse would ship a comparable UX faster. So this section was redone with **UX for the target workflow as the primary comparison criterion**: given "open a blueprint, add/remove/move an entity or tile, save it back," how does each realistic whole-mod reuse candidate's *actual* in-game experience compare to building fresh? Findings below are sourced from each mod's current mod-portal page/changelog, user reviews and comments, and relevant forum/Steam discussion threads — not assumptions about what the mod probably does.

| Mod | Status | Actual UX workflow | Key friction | Verdict |
|---|---|---|---|---|
| [Blueprint Sandboxes](https://mods.factorio.com/mod/blueprint-sandboxes) | Active, 1.1–2.1, 116K downloads | Teleport to a hidden god-mode surface → build *real* entities/ghosts with instant construction → select an area → capture via the normal blueprint tool → teleport out | Editor-mode toggle has poor discoverability; even with instant construction, placing entities still involves roboport/bot/power/chest logistics per user reports; capture-by-area *recomputes* the blueprint from whatever now physically exists on the surface rather than performing a targeted edit; blueprint-library items don't transfer cleanly via cursor (engine limitation) | Closest living candidate, but its core loop is still build-then-capture — the opposite of a targeted data edit |
| [bp100 (Staged Blueprint Planning)](https://mods.factorio.com/mod/bp100) | Active, 1.1–2.1 | Click an entity → inline panel → add/remove/move/rotate/rewire directly, propagated across "stages" → export | Has the strongest direct-manipulation *interaction pattern* found anywhere, but entities are still real placed objects on a real surface, and its data model is built around multi-stage speedrun planning — not extractable without dragging that model along | Pattern worth borrowing (see Section 7), mod itself not a reuse candidate |
| [Editor Extensions](https://mods.factorio.com/mod/EditorExtensions) | Active | General map-editor/testing sandbox toggle, not blueprint-specific | No blueprint-targeted workflow exists at all | Not a candidate |
| [BlueprintTools](https://mods.factorio.com/mod/BlueprintTools) (raiguard) | Active, 1.1–2.1, 29.1K downloads | Config window on a held blueprint: wire-color swap, tile placement under existing entities | Never touches entity add/remove/move | Not a candidate |
| [Blueprint Designer Lab](https://mods.factorio.com/mod/BlueprintLab_design) | Superseded — its own discussion thread names Blueprint Sandboxes as its "modern replacement" | Same god-mode-lab-then-capture pattern as Sandboxes, older/rougher | — | Not a candidate |
| [Edit-Blueprints](https://mods.factorio.com/mod/Edit-Blueprints) | Abandoned 6 years, Factorio 0.18 only, 224 downloads | Editor-surface edit, auto-pause | Author's own words: blueprint books broken since 1.0, "requires significant rewriting," not MP-compatible | Dead end |
| [BPEdit](https://mods.factorio.com/mod/BPEdit) | Abandoned 8 years, Factorio 0.15 only, 46 downloads total | Direct library edit — closest conceptual match to our goal | Author's own words: "not yet fully tested," told users to back up their blueprint library before use; never left early beta even in its own era | Dead end, and a weaker precedent than it first appeared |
| [factorio-blueprint-editor](https://github.com/teoxoy/factorio-blueprint-editor) (teoxoy) | Unmaintained, browser-based, not an in-game mod | True data-only editing — no real entities instantiated | Lives outside the game; can't read a live blueprint library or cursor stack | Not a reuse candidate, but validates that pure-data editing is a proven, good UX pattern that has simply never shipped in-game |

**Conclusion.** Every living reuse candidate is bottlenecked by the same root cause: they all edit a blueprint by instantiating real entities in a real (if god-mode) world first, which imposes spatial placement precision, a teleport/context-switch, build-logistics friction even under "instant construction" (confirmed by user reports on Blueprint Sandboxes), and a capture step that recomputes the blueprint from whatever now physically exists rather than performing a targeted mutation. None offers the actual UX ceiling for this task: open a blueprint, change one thing, save — with zero spatial precision demands and zero context-switch overhead beyond entering/leaving the editor itself. That gap, not mere niche-uniqueness, is what justifies building fresh with the synthetic-data + `LuaRendering` approach (next subsection) instead of forking or depending on an existing mod. bp100's click-entity → inline-panel interaction is the one thing worth carrying over from this research — folded into Section 7's palette/GUI design below.

### Chosen architecture

Entities and tiles are edited as **data** (a Lua table of `BlueprintEntity`/`Tile`-shaped records) and rendered as a visual overlay via `LuaRendering`. They are **never instantiated as real game objects** — no ghosts, no real entities, no god-mode building. This is deliberately different from Blueprint Sandboxes' approach.

## 2. API Grounding

These are the Factorio 2.0/Space Age Lua API facts the design relies on, gathered from the official docs before designing the mechanics. Each is labeled by confidence.

**Confirmed:**
- `LuaRendering` (`draw_sprite`, `draw_rectangle`, `draw_text`, `draw_line`, `draw_circle`, `draw_animation`, …) draws shapes/sprites anchored to an absolute world `target` position on a specific `surface`, restricted to specific `players`/`forces`, with `render_layer`/`tint`/`orientation` control. This is how canvas contents are visualized without being real.
- `CustomInputEvent` (fired by a `CustomInputPrototype` bound to a key) carries `cursor_position` — the world position under the mouse at the moment of input. Useful for keyboard-triggered actions relative to the cursor (rotate/delete "what's under the mouse").
- `selection-tool` item prototypes (the base of the blueprint and deconstruction-planner items) drive `on_player_selected_area` / `on_player_alt_selected_area` / `on_player_reverse_selected_area` / `on_player_alt_reverse_selected_area`, each delivering `{player_index, surface, area, item, quality, entities, tiles}`. This is the primary click/drag input transport for placing and removing things on the canvas.
- `LuaItemStack` blueprint methods operate purely on data: `get_blueprint_entities()` / `set_blueprint_entities(entities)`, `get_blueprint_tiles()` / `set_blueprint_tiles(tiles)`, `is_blueprint`, `is_blueprint_setup()`, `create_blueprint{surface=, force=, area=, ...}`. Critically, `set_blueprint_entities` can populate a blueprint item **entirely from synthetic data** — zero real entities need to ever have existed. This is the core mechanism for both exporting the canvas to a real blueprint item, and (via `get_blueprint_entities` on an existing blueprint) importing one for editing.
- `BlueprintEntity` fields: `entity_number` (transient, blueprint-local, 1-based, referenced by wires), `name`, `position`, `direction`, `mirror`, `quality`, `items` (`BlueprintInsertPlan[]`), `tags`, `wires` (`BlueprintWire[]`), plus many entity-type-specific fields (`control_behavior`, `recipe`, `filters`, `inventory`, `bar`, `request_filters`, `grid`, `orientation`, `color`, `filter_mode`, `override_stack_size`, `drop_position`, `pickup_position`, etc.) that only apply to certain entity types.

**Unverified — treat as spikes, not foundations:**
- Whether a `LuaGuiElement` of type `camera` can report clicks mapped back to world coordinates. If it could, the canvas could be a floating GUI window with no player teleport at all. Not confirmed in research — deferred to a Phase 7 stretch spike. The safe default is a dedicated surface + teleport instead.
- Whether `generate_with_lab_tiles` behaves as expected for a cheap, flat, resource/enemy-free surface in 2.0 — assumed from prior Factorio versions, to be verified in Phase 0.
- Whether a plain click (no drag) with an equipped `selection-tool` still fires `on_player_selected_area` with a small area — this is load-bearing for the whole input model and must be verified in Phase 0. If it doesn't behave this way, fall back to raw `custom-input` + `cursor_position` as the primary click handler instead.
- Whether blueprints dragged directly out of the in-game Blueprint Library transfer cleanly via `cursor_stack` (a limitation reportedly hit by Blueprint Sandboxes) — to verify in Phase 1; if confirmed broken, document "drag into an inventory/blueprint-book first" as a known limitation rather than working around it in v0.1.

## 3. Project Layout

```
info.json
data.lua
data/
  custom-input.lua      -- eb-toggle-editor, eb-rotate, eb-flip, eb-delete, eb-cancel,
                            eb-cycle-palette-next/prev, eb-pick-entity
  selection-tool.lua     -- eb-cursor-tool item (type="selection-tool")
  shortcut.lua            -- optional toolbar button to enter editor (nice-to-have)
control.lua               -- thin bootstrap: requires scripts/*, registers event handlers
scripts/
  state.lua               -- storage schema, session accessors, migration entry point
  migrations.lua          -- on_configuration_changed step table
  surface.lua             -- canvas surface lifecycle, per-player region allocation, teleport in/out
  rendering.lua           -- LuaRendering wrappers: grid, entity sprites, tile sprites, cleanup
  catalog.lua             -- generic prototype enumeration -> entity/tile/quality catalogs
  palette_gui.lua         -- palette window construction + gui event handlers
  input.lua               -- on_player_selected_area / alt / custom-input handlers -> canvas.lua calls
  canvas.lua               -- core mutation API: place/remove/move/rotate entity, place/remove tile, snapping
  blueprint_io.lua         -- import from stack, export to arrays, save-new, save-back-to-stack
  debug.lua                -- dev-only command to dump session state via serpent
```

**info.json**: `factorio_version = "2.0"`, base dependency `"base >= 2.0"`, Space Age as an *optional* dependency (`"? space-age"`) — the quality selector only shows up if `script.active_mods["space-age"]` is true at runtime, no hard dependency.

**Data stage**: custom-input prototypes listed above (none bound to mouse buttons — see Section 5); one `selection-tool` item `eb-cursor-tool` (`flags = {"only-in-cursor","not-stackable"}`, `stack_size = 1`, hidden from crafting, granted only via script). No new art required for MVP — palette buttons reuse `item/<name>` sprites automatically; GUI reuses base game styles for vanilla-familiar look. Custom icons/styles are Phase 7 polish, not blockers.

## 4. State Management

Everything lives under a single `storage` table (Factorio 2.0 renamed `global` → `storage`), owned exclusively by `scripts/state.lua` — other modules call accessors like `state.get_session(player_index)`, never touch `storage` directly. This encapsulation is what makes migrations tractable.

```lua
storage = {
  mod_version = "0.1.0",
  canvas_surface_name = "eb-canvas",
  catalog = { entities = {...}, tiles = {...}, qualities = {...} }, -- plain data, rebuilt on config change
  sessions = { [player_index] = Session },
}

Session = {
  player_index,
  mode = "new" | "edit",
  origin = nil | { kind = "cursor" } | { kind = "inventory_pinned", inventory = <LuaInventory>, slot = 1 },
  pre_edit = { surface_name, position, controller_type, ... }, -- for exact restore on exit
  canvas_offset = { x = ..., y = ... },   -- this player's private region on the shared surface
  next_internal_id = 1,
  entities = { [internal_id] = EntityRecord },
  tiles = { ["x,y"] = TileRecord },
  render_ids = { grid = {...}, entities = { [internal_id] = {...} }, tiles = {...} },
  selected_palette_item = nil,
  selected_quality = "normal",
  label = nil, icons = nil,
  blueprint_snap = nil,   -- carried-through snap-to-grid / absolute-snapping metadata
}

EntityRecord = {
  internal_id,
  raw = <BlueprintEntity-shaped table>,  -- untouched import data, or minimal fresh table for new placements
  wires = { { target_internal_id, wire_type, this_conn, target_conn }, ... },
}
```

**Migration discipline** is mandatory from day one, not deferred: `storage.catalog` must be rebuilt on `on_configuration_changed` whenever mods/prototypes change, and any `Session`/`EntityRecord` schema change ever made must ship with an explicit migration step keyed by `storage.mod_version`. Rule: only ever *add* optional/nil-safe fields; never repurpose or remove one without a migration pass. `scripts/migrations.lua` holds an ordered `{version, fn}` list applied in `on_configuration_changed`.

Known MVP limitation: sessions are **not** persisted across a save/reload boundary. If `on_load` finds an active session for a player no longer on the canvas surface, discard it and any orphaned render objects — treat it as "editor was cancelled" rather than engineering full crash-safe resume.

## 5. Canvas Mechanics

### Dedicated surface

Created once, lazily, in `on_init` and defensively re-verified in `on_configuration_changed` (in case something deleted it): `surface.lua#ensure_canvas_surface()`. Use `game.create_surface(name, {...})` with `generate_with_lab_tiles = true` for a cheap, infinite, flat, resource/enemy-free floor (**to verify in Phase 0**), plus `always_day = true`, `freeze_daytime = true`, `show_clouds = false`, `peaceful_mode = true` as belt-and-suspenders.

**Single shared surface, per-player offset regions** rather than one surface per session: each player's canvas lives at `(player_index * REGION_SPACING, 0)` with `REGION_SPACING` large (1000+ tiles), so concurrent editors never see each other's canvases even though the surface is physically shared — all `LuaRendering` calls are scoped `players = {player_index}` regardless. This avoids surface create/destroy churn and keeps the save file's surface count constant.

### Transport in/out

`surface.lua#teleport_in(player)`: record `pre_edit` state (surface, position, controller type — refuse entry or force-exit first if the player is in a vehicle or remote view), then `player.teleport(canvas_offset, canvas_surface)`. `surface.lua#teleport_out(player)`: restore exactly from `pre_edit`, then clear the session. On entering, set `player.cursor_stack` to `eb-cursor-tool` and re-enforce it staying equipped via `on_player_cursor_stack_changed` while a session is active.

### Grid / snapping

`rendering.lua#draw_grid(session)` draws a bounded grid (e.g. 128×128 tiles) once per session via `draw_line`, storing render ids for later cleanup — cheap compared to per-cell rectangles. Hover/placement preview comes for free from the equipped selection-tool's native drag-box; there is no generic "mouse moved" event available to mods, so this native feedback is important (see input-model rationale below). `canvas.lua#snap_position(prototype_name, raw_position)` replicates vanilla odd/even `tile_width`/`tile_height` centering, read from `prototypes.entity[name].tile_width/tile_height`.

### Input model: selection-tool drag, not raw mouse custom-input

The primary click transport is the equipped `eb-cursor-tool` selection-tool (`on_player_selected_area` for place, `on_player_alt_selected_area` for remove), not a `custom-input` bound directly to a mouse button. Two concrete reasons:

1. **Free hover feedback.** Factorio natively draws the colored selection box under the mouse for any held selection-tool with zero mod code. There's no generic "mouse moved" event, so a raw-custom-input-only approach would have no visual feedback between clicks.
2. **Input-conflict avoidance.** Binding `custom-input` directly to `mouse-button-1`/`mouse-button-2` while the base game's own build/mine handling is live on the same buttons is a known source of subtle conflicts. Selection-tool clicks go through their own dedicated event pipeline instead.

`CustomInputEvent.cursor_position` is still used, but for keyboard-triggered actions relative to the mouse: `eb-rotate` finds the entity at that position and cycles its `direction` (in 2.0, direction is in 1/16ths; cycle step depends on the entity's own rotation granularity), `eb-delete` finds and removes it.

**Phase 0 spike required**: confirm a plain click (no drag) with a selection tool still fires `on_player_selected_area` with a small area. This is load-bearing for the whole model; if it doesn't hold, fall back to raw custom-input + `cursor_position`.

## 6. `entity_number` / Wire Bookkeeping

This is the trickiest correctness issue: removing an entity must not corrupt other entities' wire connections.

**Core design**: blueprint `entity_number` is a transient, export-time-only concept. Internally, entities are tracked by a monotonically increasing `internal_id` that is never reused and never renumbered. All wire references are stored by `internal_id`, not `entity_number` — sidestepping any ambiguity about whether `set_blueprint_entities` requires dense/positional numbering.

```lua
-- import (blueprint_io.import_from_stack):
map = {}                                   -- bp_entity_number -> internal_id
for bp_entity in stack.get_blueprint_entities() do
  id = session.next_internal_id; session.next_internal_id = id + 1
  session.entities[id] = { internal_id = id, raw = bp_entity, wires = {} }
  map[bp_entity.entity_number] = id
end
for bp_entity, id in (paired iteration) do
  for each wire reference in bp_entity.wires do
    session.entities[id].wires[#+1] = {
      target_internal_id = map[wire.target_entity_number],
      wire_type = wire.wire_type, this_conn = wire.this_conn, target_conn = wire.target_conn,
    }
  end
end

-- delete (canvas.remove_entity):
session.entities[internal_id] = nil
for _, rec in pairs(session.entities) do          -- O(N) sweep, acceptable at blueprint scale
  rec.wires = filter(rec.wires, w -> w.target_internal_id ~= internal_id)
end
rendering.destroy_entity_render(session, internal_id)
-- no renumbering needed anywhere -- references are id-based, not position-based

-- export (blueprint_io.export_to_entities_array):
export_map = {}                                    -- internal_id -> fresh sequential entity_number
n = 0
for id, rec in stable_order(session.entities) do
  n = n + 1; export_map[id] = n
end
entities_out = {}
for id, rec in stable_order(session.entities) do
  e = shallow_copy(rec.raw)
  e.entity_number = export_map[id]
  e.wires = { for w in rec.wires: {export_map[id], w.this_conn, export_map[w.target_internal_id], w.target_conn} }
  entities_out[#+1] = e
end
return entities_out
```

Regression check worth asserting explicitly in Phase 4: if nothing changed during an edit session, re-exporting should reproduce the same array modulo `entity_number` renumbering.

**Preserve-unknown-fields principle**: for entities imported and never touched beyond move/rotate, `rec.raw` is the untouched table from `get_blueprint_entities()` (recipe, filters, control_behavior, request filters, equipment grid, everything), with only `position`/`direction`/`quality` overlaid if moved/rotated/requalitied. Only newly palette-placed entities get a freshly constructed minimal `raw` table (`name`, `position`, `direction`, `quality`). This is both the simplest implementation and the strongest mod-compatibility guarantee (Section 9).

## 7. Palette / GUI

`scripts/catalog.lua` builds catalogs generically, with **zero hardcoded entity/tile names**, cached into `storage.catalog`, rebuilt in `on_init` + `on_configuration_changed`:

- **Entities**: iterate `prototypes.item`, keep items where `item.place_result ~= nil` and not `item.flags.hidden` — mirrors how the vanilla build palette itself decides what's placeable, automatically includes anything any mod adds an item+entity pair for.
- **Tiles**: iterate `prototypes.tile`, keep tiles where `tile.items_to_place_this` is non-empty and not hidden — naturally excludes non-placeable tiles like raw water.
- **Quality**: iterate `prototypes.quality`, keep `not quality.hidden`; only surface the selector if the resulting list has more than `"normal"` (effectively gated on Space Age's quality feature, without a hard dependency).
- Store only plain serializable fields (name, group, subgroup, order) in `storage.catalog` — never store live prototype objects across a save boundary.

`scripts/palette_gui.lua` builds a group-tab bar + subgroup rows of `sprite-button`s (`sprite = "item/" .. name`), reusing `item.group`/`.subgroup`/`.order` so the layout mirrors the vanilla crafting menu. Tooltips use `prototype.localised_name` directly (auto-translated client-side for free).

**Search limitation to plan around**: Factorio has no synchronous way for mods to read a translated/localized string at runtime — matching a search box against a `LocalisedString` requires the async `LuaPlayer.request_translation` / `on_string_translated` dance. Plan: filter search by raw prototype `name` (English identifier) through Phase 4, upgrade to real localized-name search only in Phase 5 once the translation-cache plumbing exists.

**Entity inspector panel, borrowed from bp100's interaction pattern**: reuse research (Section 1) found that [bp100](https://mods.factorio.com/mod/bp100) has the strongest direct-manipulation interaction of any mod surveyed — click an already-placed entity, get an inline panel, edit it in place. Rather than editing an entity purely through hotkeys at cursor position (`eb-rotate`/`eb-delete`, Section 5), add a click-to-inspect flow: clicking an entity already on the canvas (via the same `eb-cursor-tool` selection-tool, a single-tile selection resolved to the entity under it) opens a small GUI panel showing that `EntityRecord`'s editable fields — quality, recipe, filters, `entity_number`-independent id for debugging — with direct-mutate controls instead of requiring a hotkey per field. This is a Phase 5 concern (full palette/GUI), not a Phase 0–2 blocker; the MVP hotkey-only interaction (Section 5) stays as the Phase 2 baseline and the inspector panel layers on top of it once `canvas.lua`'s mutation API already exists.

## 8. Blueprint I/O

**(a) New blueprint from canvas**
1. Player opens an empty session (`eb-toggle-editor` with no valid blueprint in cursor) and builds via the palette.
2. On export: `blueprint_io.save_new_blueprint(session)` — prefer the player's empty `cursor_stack`; else `player.insert{name="blueprint"}` and locate/configure that stack; else `surface.spill_item_stack` as a last resort.
3. `stack.set_blueprint_entities(entities_out)`, `stack.set_blueprint_tiles(tiles_out)`, plus `stack.label`/`stack.blueprint_icons` from a small metadata form (name field + up to 4 icon pickers, same `elem-button` pattern as vanilla).

**(b) Edit an existing blueprint**
1. MVP interaction: player holds the target blueprint in cursor, presses `eb-toggle-editor`. Verify `stack.is_blueprint and stack.is_blueprint_setup()`. A full blueprint-library/inventory browser GUI is deferred, not MVP-blocking.
2. Copy data out via `get_blueprint_entities()`/`get_blueprint_tiles()`, also capturing `label`, `blueprint_icons`, and snap-to-grid metadata (`blueprint_snap_to_grid`, `blueprint_absolute_snapping`, `blueprint_position_relative_to_grid`) for later round-trip.
3. **Pin the source stack**: move it into a mod-owned hidden `LuaInventory` (`game.create_inventory(1)`, not tied to any entity) for the session's duration, immune to the player clearing cursor/reordering inventory. Swap back on save/cancel.
4. Build session state from the imported data via the `internal_id` remap (Section 6), teleport in, render.
5. On save/update: `export_to_entities_array` → `set_blueprint_entities`/`set_blueprint_tiles` on either the same pinned stack (in-place) or a fresh copy ("save as new"), re-applying preserved `label`/`icons`/snap metadata.
6. Return the finished stack: cursor if empty → else insert into inventory → else spill on ground. Restore player position via `surface.teleport_out`.
7. **Named risk to verify early (Phase 1)**: Blueprint Library-sourced blueprints reportedly can't transfer cleanly via `cursor_stack` (an engine limitation hit by Blueprint Sandboxes). If confirmed, document "drag into an inventory/blueprint-book first" as a known MVP limitation rather than working around it.

## 9. Mod Compatibility

The `item.place_result` / `tile.items_to_place_this` enumeration (Section 7) is inherently generic — nothing in palette construction, import, or export ever names a specific entity/tile. The **preserve-unknown-fields** rule (Section 6) is the real compatibility guarantee: an imported entity of a type this mod has never heard of round-trips correctly through an edit session as long as the player doesn't touch it, since its fields are never reconstructed from a hardcoded schema.

| Entity class | MVP handling | Deferred/stretch |
|---|---|---|
| Rolling stock (locomotives/wagons) | Placed like any other entity (position/direction/orientation), no smart rail-snapping | Snap rolling stock to nearest virtual rail curvature |
| Rails, rail signals/chain signals | Placed as plain data, no connectivity validation (same as hand-edited blueprint JSON) | Connectivity assist/validation |
| Wires (circuit + copper) | Preserved verbatim for imported entities via preserve-unknown-fields; delete-cleanup (Section 6) implemented from Phase 2 regardless, since it's required for correctness even before wire *editing* exists | Full in-canvas wire-drawing UI (Phase 6) |
| Spidertron / equipment-grid entities | Round-trips fine via preserve-unknown-fields when imported; freshly placed instances get an empty grid, matching vanilla "blueprint a spidertron from scratch" | No special handling needed once preserve-unknown-fields is in place |
| Power pole auto-connect-by-proximity | Not simulated/previewed on canvas; real auto-connect happens once the player pastes the finished blueprint in-world | Proximity-based auto-connect preview |
| Underground belts/pipes (paired by direction+distance) | No special handling needed — positional like any entity | — |

## 10. Verification Approach (for future implementation)

No existing test harness, and Factorio mods have no standard automated test runner for API-touching code.

- **Dev loop**: place/symlink the mod folder (unzipped, valid `info.json`) into `%APPDATA%\Factorio\mods\`. `data.lua` prototype changes require a full game restart (prototypes load once at startup); `control.lua`/`scripts/*` changes take effect on save-reload (close/reopen the save) without restarting.
- **In-game debug command**: `scripts/debug.lua` registers a command that `serpent.block()`-dumps the current session's `entities`/`tiles`/`wires` to the log or `script-output/`, for field-by-field inspection between edits.
- **Ground-truth cross-check**: compare a canvas-exported blueprint's `get_blueprint_entities()` output against a real vanilla-placed reference blueprint of the same layout — the engine is the best available oracle for "is this a valid blueprint."
- **Real-paste validation**: the strongest end-to-end check for Phase 4+ is pasting the exported blueprint into the real world and letting Factorio's own ghost-preview/placement validation catch structural errors (bad positions, dangling wire refs).
- **Pure-logic unit testing**: functions with no direct Factorio API dependency (the `internal_id`/`entity_number` remap, catalog filter/sort logic) take/return plain Lua tables specifically so they can be exercised by a standalone `busted` runner outside the game. Per `docs/sdlc.md`, this is a **mandatory TDD target**, not optional — tests are written before the implementation for these modules.
- **Manual play-test checklists** per phase (see `docs/roadmap.md` and each `docs/phases/phase-N-implementation.md`) are the primary verification method for everything that does depend on the Factorio API, since GUI/canvas behavior is inherently interactive.
