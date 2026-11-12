_G.defines = _G.defines or { wire_connector_id = { pole_copper = 5, circuit_red = 1, circuit_green = 2 } }

local blueprint_io = require("scripts.blueprint_io")

describe("blueprint_io.build_import_data", function()
  it("assigns sequential internal_id starting at 1, independent of entity_number", function()
    local entities, _, next_id = blueprint_io.build_import_data({
      { entity_number = 7, name = "iron-chest", position = { x = 0, y = 0 } },
      { entity_number = 12, name = "wooden-chest", position = { x = 1, y = 0 } },
    }, {})
    assert.are.equal(1, entities[1].internal_id)
    assert.are.equal("iron-chest", entities[1].raw.name)
    assert.are.equal(2, entities[2].internal_id)
    assert.are.equal("wooden-chest", entities[2].raw.name)
    assert.is_nil(entities[7])
    assert.is_nil(entities[12])
    assert.are.equal(3, next_id)
  end)

  it("returns empty tables and next_internal_id = 1 for an empty blueprint", function()
    local entities, tiles, next_id = blueprint_io.build_import_data({}, {})
    assert.are.same({}, entities)
    assert.are.same({}, tiles)
    assert.are.equal(1, next_id)
  end)

  it("indexes tiles by an \"x,y\" position key", function()
    local _, tiles = blueprint_io.build_import_data({}, {
      { name = "lab-dark-1", position = { x = -2, y = 3 } },
    })
    assert.is_not_nil(tiles["-2,3"])
    assert.are.equal("lab-dark-1", tiles["-2,3"].raw.name)
  end)

  it("preserves the raw entity table untouched (preserve-unknown-fields)", function()
    local bp_entity = {
      entity_number = 1,
      name = "assembling-machine-2",
      position = { x = 0, y = 0 },
      recipe = "iron-gear-wheel",
      request_filters = { { index = 1, name = "iron-plate", count = 100 } },
    }
    local entities = blueprint_io.build_import_data({ bp_entity }, {})
    assert.are.equal(bp_entity, entities[1].raw)
  end)

  it("gives every entity an empty wires table when the blueprint has no wires", function()
    local entities = blueprint_io.build_import_data({
      { entity_number = 1, name = "iron-chest", position = { x = 0, y = 0 } },
    }, {})
    assert.are.same({}, entities[1].wires)
  end)

  it("builds a bidirectional wire entry from a one-sided BlueprintWire tuple", function()
    local entities = blueprint_io.build_import_data({
      { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
        wires = { { 1, defines.wire_connector_id.pole_copper, 2, defines.wire_connector_id.pole_copper } } },
      { entity_number = 2, name = "small-electric-pole", position = { x = 5, y = 0 } },
    }, {})
    assert.are.same({
      { target_internal_id = 2, this_connector_id = defines.wire_connector_id.pole_copper, target_connector_id = defines.wire_connector_id.pole_copper },
    }, entities[1].wires)
    assert.are.same({
      { target_internal_id = 1, this_connector_id = defines.wire_connector_id.pole_copper, target_connector_id = defines.wire_connector_id.pole_copper },
    }, entities[2].wires)
  end)

  it("dedups when the same wire is listed on both connected entities", function()
    local entities = blueprint_io.build_import_data({
      { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
        wires = { { 1, defines.wire_connector_id.pole_copper, 2, defines.wire_connector_id.pole_copper } } },
      { entity_number = 2, name = "small-electric-pole", position = { x = 5, y = 0 },
        wires = { { 2, defines.wire_connector_id.pole_copper, 1, defines.wire_connector_id.pole_copper } } },
    }, {})
    assert.are.equal(1, #entities[1].wires)
    assert.are.equal(1, #entities[2].wires)
  end)

  it("errors on a wire referencing an entity_number outside the blueprint", function()
    assert.has_error(function()
      blueprint_io.build_import_data({
        { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
          wires = { { 1, defines.wire_connector_id.pole_copper, 99, defines.wire_connector_id.pole_copper } } },
      }, {})
    end)
  end)
end)

describe("blueprint_io.stable_entity_order", function()
  it("returns internal_ids ascending regardless of pairs() order and gaps", function()
    local entities = {
      [12] = { internal_id = 12, raw = {}, wires = {} },
      [3] = { internal_id = 3, raw = {}, wires = {} },
      [7] = { internal_id = 7, raw = {}, wires = {} },
      [1] = { internal_id = 1, raw = {}, wires = {} },
    }
    assert.are.same({ 1, 3, 7, 12 }, blueprint_io.stable_entity_order(entities))
  end)

  it("returns {} for an empty session", function()
    assert.are.same({}, blueprint_io.stable_entity_order({}))
  end)
end)

local COPPER = defines.wire_connector_id.pole_copper
local RED = defines.wire_connector_id.circuit_red
local GREEN = defines.wire_connector_id.circuit_green

local function record(internal_id, raw, wires)
  return { internal_id = internal_id, raw = raw, wires = wires or {} }
end

local function wire(target_internal_id, this_connector_id, target_connector_id)
  return {
    target_internal_id = target_internal_id,
    this_connector_id = this_connector_id,
    target_connector_id = target_connector_id,
  }
end

describe("blueprint_io.build_export_wires", function()
  it("emits each wire exactly once, on the side with the smaller entity_number", function()
    local entities = {
      [1] = record(1, {}, { wire(2, COPPER, COPPER) }),
      [2] = record(2, {}, { wire(1, COPPER, COPPER) }),
    }
    local wires = blueprint_io.build_export_wires(entities, { [1] = 1, [2] = 2 })
    assert.are.same({ { 1, COPPER, 2, COPPER } }, wires[1])
    assert.is_true(wires[2] == nil or #wires[2] == 0)
  end)

  it("uses export_map numbers, not internal_ids, in the tuple", function()
    local entities = {
      [4] = record(4, {}, { wire(9, RED, GREEN) }),
      [9] = record(9, {}, { wire(4, GREEN, RED) }),
    }
    local wires = blueprint_io.build_export_wires(entities, { [4] = 1, [9] = 2 })
    assert.are.same({ { 1, RED, 2, GREEN } }, wires[4])
  end)

  it("exports a wire stored only on the larger side the same way as a two-sided one", function()
    local two_sided = {
      [1] = record(1, {}, { wire(2, RED, GREEN) }),
      [2] = record(2, {}, { wire(1, GREEN, RED) }),
    }
    local one_sided = {
      [1] = record(1, {}, {}),
      [2] = record(2, {}, { wire(1, GREEN, RED) }),
    }
    local map = { [1] = 1, [2] = 2 }
    local expected = blueprint_io.build_export_wires(two_sided, map)
    local actual = blueprint_io.build_export_wires(one_sided, map)
    assert.are.same({ { 1, RED, 2, GREEN } }, expected[1])
    assert.are.same(expected[1], actual[1])
    assert.is_true(actual[2] == nil or #actual[2] == 0)
  end)

  it("orders a self-wire by connector_id and emits it once", function()
    local entities = {
      [1] = record(1, {}, { wire(1, GREEN, RED) }),
    }
    local wires = blueprint_io.build_export_wires(entities, { [1] = 1 })
    assert.are.same({ { 1, RED, 1, GREEN } }, wires[1])
  end)

  it("keeps distinct wires between the same pair on different connectors", function()
    local entities = {
      [1] = record(1, {}, { wire(2, RED, RED), wire(2, GREEN, GREEN) }),
      [2] = record(2, {}, { wire(1, RED, RED), wire(1, GREEN, GREEN) }),
    }
    local wires = blueprint_io.build_export_wires(entities, { [1] = 1, [2] = 2 })
    assert.are.same({ { 1, RED, 2, RED }, { 1, GREEN, 2, GREEN } }, wires[1])
  end)

  it("errors with both ids when target_internal_id is missing from entities", function()
    local entities = {
      [3] = record(3, {}, { wire(42, COPPER, COPPER) }),
    }
    assert.error_matches(function()
      blueprint_io.build_export_wires(entities, { [3] = 1 })
    end, "wire of internal_id 3 references internal_id 42 missing from session%.entities")
  end)
end)

describe("blueprint_io.export_to_entities_array", function()
  it("numbers entities densely 1..N in internal_id order when ids have gaps", function()
    local entities = {
      [2] = record(2, { name = "iron-chest", position = { x = 0, y = 0 } }),
      [5] = record(5, { name = "wooden-chest", position = { x = 1, y = 0 } }),
      [9] = record(9, { name = "steel-chest", position = { x = 2, y = 0 } }),
    }
    local result = blueprint_io.export_to_entities_array(entities)
    assert.are.equal(3, #result)
    assert.are.same({ 1, 2, 3 }, { result[1].entity_number, result[2].entity_number, result[3].entity_number })
    assert.are.same({ "iron-chest", "wooden-chest", "steel-chest" }, { result[1].name, result[2].name, result[3].name })
  end)

  it("returns {} for an empty session", function()
    assert.are.same({}, blueprint_io.export_to_entities_array({}))
  end)

  it("does not mutate raw and carries unknown fields through by the same reference", function()
    local control_behavior = { circuit_condition = { first_signal = { type = "item", name = "iron-plate" } } }
    local tags = { note = "keep me" }
    local raw = {
      entity_number = 77,
      name = "assembling-machine-2",
      position = { x = 3, y = -142.5 },
      direction = 4,
      recipe = "iron-gear-wheel",
      control_behavior = control_behavior,
      tags = tags,
      wires = { { 77, RED, 78, RED } },
    }
    local snapshot = {
      entity_number = 77,
      name = "assembling-machine-2",
      position = { x = 3, y = -142.5 },
      direction = 4,
      recipe = "iron-gear-wheel",
      control_behavior = { circuit_condition = { first_signal = { type = "item", name = "iron-plate" } } },
      tags = { note = "keep me" },
      wires = { { 77, RED, 78, RED } },
    }
    local entities = { [10] = record(10, raw) }
    local result = blueprint_io.export_to_entities_array(entities)
    assert.are_not.equal(raw, result[1])
    assert.are.same(snapshot, raw)
    assert.are.equal(1, result[1].entity_number)
    assert.is_nil(result[1].wires)
    assert.are.equal("iron-gear-wheel", result[1].recipe)
    assert.are.equal(control_behavior, result[1].control_behavior)
    assert.are.equal(tags, result[1].tags)
    assert.are.equal(raw.position, result[1].position)
    assert.are.equal(4, result[1].direction)
  end)

  it("leaves positions in blueprint space untouched (no canvas offset involved)", function()
    local entities = {
      [1] = record(1, { name = "iron-chest", position = { x = 1234.5, y = -987 } }),
    }
    local result = blueprint_io.export_to_entities_array(entities)
    assert.are.same({ x = 1234.5, y = -987 }, result[1].position)
  end)

  it("emits a wire once with wires == nil on the wireless side", function()
    local entities = {
      [1] = record(1, { name = "small-electric-pole", position = { x = 0, y = 0 } }, { wire(2, COPPER, COPPER) }),
      [2] = record(2, { name = "small-electric-pole", position = { x = 5, y = 0 } }, { wire(1, COPPER, COPPER) }),
      [3] = record(3, { name = "iron-chest", position = { x = 9, y = 0 } }),
    }
    local result = blueprint_io.export_to_entities_array(entities)
    assert.are.same({ { 1, COPPER, 2, COPPER } }, result[1].wires)
    assert.is_nil(result[2].wires)
    assert.is_nil(result[3].wires)
  end)

  it("errors on a dangling wire reference", function()
    local entities = {
      [1] = record(1, { name = "small-electric-pole", position = { x = 0, y = 0 } }, { wire(99, COPPER, COPPER) }),
    }
    assert.has_error(function()
      blueprint_io.export_to_entities_array(entities)
    end)
  end)
end)

-- Множество симметричных ключей проводов blueprint'а: {a, ca, b, cb} и
-- {b, cb, a, ca} -- один и тот же провод, где бы и сколько раз он ни лежал.
local function wire_key_set(bp_entities)
  local set = {}
  for _, bp_entity in ipairs(bp_entities) do
    for _, w in ipairs(bp_entity.wires or {}) do
      local a, ca, b, cb = w[1], w[2], w[3], w[4]
      if a > b or (a == b and ca > cb) then
        a, ca, b, cb = b, cb, a, ca
      end
      set[a .. ":" .. ca .. ":" .. b .. ":" .. cb] = true
    end
  end
  return set
end

local function strip_wires(bp_entities)
  local stripped = {}
  for index, bp_entity in ipairs(bp_entities) do
    local copy = {}
    for field, value in pairs(bp_entity) do
      if field ~= "wires" then copy[field] = value end
    end
    stripped[index] = copy
  end
  return stripped
end

describe("blueprint_io export round-trip and no-op regression (ADR-0001 §6)", function()
  local X = {
    { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
      wires = { { 1, COPPER, 2, COPPER }, { 1, RED, 3, RED } } },
    { entity_number = 2, name = "small-electric-pole", position = { x = 5, y = 0 },
      wires = { { 2, GREEN, 3, GREEN } } },
    { entity_number = 3, name = "decider-combinator", position = { x = 2.5, y = 1 }, direction = 4,
      control_behavior = { decider_conditions = { comparator = "<" } },
      wires = { { 3, RED, 3, GREEN } } },
    { entity_number = 4, name = "iron-chest", position = { x = 9, y = 9 }, tags = { k = "v" } },
  }
  local X_tiles = {
    { name = "concrete", position = { x = 0, y = 1 } },
    { name = "concrete", position = { x = 0, y = 0 } },
    { name = "stone-path", position = { x = -1, y = 0 } },
  }

  it("export(import(X)) == X for dense numbering and unique wires, including order", function()
    local entities = blueprint_io.build_import_data(X, {})
    local result = blueprint_io.export_to_entities_array(entities)
    assert.are.same(X, result)
  end)

  it("import(export(import(X))) rebuilds the same entity and wire structure", function()
    local first = blueprint_io.build_import_data(X, {})
    local exported = blueprint_io.export_to_entities_array(first)
    local second = blueprint_io.build_import_data(exported, {})
    assert.are.same(first, second)
  end)

  it("export(import(X)) equals X modulo wire normalisation when the game listed wires on both sides", function()
    local X_dup = {
      { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
        wires = { { 1, COPPER, 2, COPPER } } },
      { entity_number = 2, name = "small-electric-pole", position = { x = 5, y = 0 },
        wires = { { 2, COPPER, 1, COPPER }, { 2, RED, 3, RED } } },
      { entity_number = 3, name = "constant-combinator", position = { x = 2.5, y = 1 },
        wires = { { 3, RED, 2, RED } } },
    }
    local entities = blueprint_io.build_import_data(X_dup, {})
    local result = blueprint_io.export_to_entities_array(entities)
    assert.are.same(strip_wires(X_dup), strip_wires(result))
    assert.are.same(wire_key_set(X_dup), wire_key_set(result))
    local total = 0
    for _, bp_entity in ipairs(result) do total = total + #(bp_entity.wires or {}) end
    assert.are.equal(2, total)
  end)

  -- Провода сессии как множество симметричных ключей по именам сущностей
  -- (не по internal_id -- те после re-import перенумеровываются). Имена в
  -- наборе должны быть уникальны, иначе ключи склеиваются.
  local function session_wire_set_by_name(entities)
    local set = {}
    for _, rec in pairs(entities) do
      for _, w in ipairs(rec.wires) do
        local a, ca = rec.raw.name, w.this_connector_id
        local b, cb = entities[w.target_internal_id].raw.name, w.target_connector_id
        if a > b or (a == b and ca > cb) then
          a, ca, b, cb = b, cb, a, ca
        end
        set[a .. ":" .. ca .. "|" .. b .. ":" .. cb] = true
      end
    end
    return set
  end

  local function session_wire_count(entities)
    local total = 0
    for _, rec in pairs(entities) do total = total + #rec.wires end
    return total
  end

  it("import(export(import(X_dup))) keeps the wire structure when the source listed wires on both sides", function()
    local X_dup = {
      { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
        wires = { { 1, COPPER, 2, COPPER } } },
      { entity_number = 2, name = "medium-electric-pole", position = { x = 5, y = 0 },
        wires = { { 2, COPPER, 1, COPPER }, { 2, RED, 3, RED } } },
      { entity_number = 3, name = "constant-combinator", position = { x = 2.5, y = 1 },
        wires = { { 3, RED, 2, RED } } },
    }
    local first = blueprint_io.build_import_data(X_dup, {})
    local second = blueprint_io.build_import_data(blueprint_io.export_to_entities_array(first), {})
    assert.are.same(session_wire_set_by_name(first), session_wire_set_by_name(second))
    assert.are.equal(4, session_wire_count(first))
    assert.are.equal(session_wire_count(first), session_wire_count(second))
    assert.are.same(strip_wires(X_dup), strip_wires(blueprint_io.export_to_entities_array(second)))
  end)

  it("round-trips a session with internal_id gaps after a deletion, keeping every remaining wire", function()
    local deleted = blueprint_io.build_import_data(X, {})
    deleted[2] = nil
    for _, rec in pairs(deleted) do
      local kept = {}
      for _, w in ipairs(rec.wires) do
        if w.target_internal_id ~= 2 then kept[#kept + 1] = w end
      end
      rec.wires = kept
    end
    local exported = blueprint_io.export_to_entities_array(deleted)
    local reimported, _, next_id = blueprint_io.build_import_data(exported, {})
    assert.are.same({ 1, 2, 3 }, blueprint_io.stable_entity_order(reimported))
    assert.are.equal(4, next_id)
    assert.are.same(session_wire_set_by_name(deleted), session_wire_set_by_name(reimported))
    assert.are.equal(3, session_wire_count(deleted))
    assert.are.equal(session_wire_count(deleted), session_wire_count(reimported))
    assert.are.same(exported, blueprint_io.export_to_entities_array(reimported))
  end)

  it("re-exports after deleting an entity with dense numbering and remapped wires", function()
    local entities = blueprint_io.build_import_data(X, {})
    -- Удаление сущности 2 так, как это делает canvas.remove_entity.
    entities[2] = nil
    for _, rec in pairs(entities) do
      local kept = {}
      for _, w in ipairs(rec.wires) do
        if w.target_internal_id ~= 2 then kept[#kept + 1] = w end
      end
      rec.wires = kept
    end
    local result = blueprint_io.export_to_entities_array(entities)
    assert.are.same({ 1, 2, 3 }, { result[1].entity_number, result[2].entity_number, result[3].entity_number })
    assert.are.same({ "small-electric-pole", "decider-combinator", "iron-chest" },
      { result[1].name, result[2].name, result[3].name })
    assert.are.same({ { 1, RED, 2, RED } }, result[1].wires)
    assert.are.same({ { 2, RED, 2, GREEN } }, result[2].wires)
    assert.is_nil(result[3].wires)
  end)

  it("export_to_tiles_array(import(X_tiles)) returns the same tiles in deterministic order", function()
    local _, tiles = blueprint_io.build_import_data({}, X_tiles)
    local result = blueprint_io.export_to_tiles_array(tiles)
    assert.are.same({ X_tiles[3], X_tiles[2], X_tiles[1] }, result)
    assert.are.same(result, blueprint_io.export_to_tiles_array(tiles))
  end)
end)

describe("blueprint_io.export_to_entities_array size logging", function()
  local saved_log

  before_each(function()
    saved_log = _G.log
  end)

  after_each(function()
    _G.log = saved_log
  end)

  local function build(count)
    local entities = {}
    for id = 1, count do
      entities[id] = record(id, { name = "iron-chest", position = { x = id, y = 0 } })
    end
    return entities
  end

  it("logs one line with entity and wire counts above the threshold", function()
    local lines = {}
    _G.log = function(message) lines[#lines + 1] = message end
    local entities = build(2001)
    entities[1].wires = { wire(2, COPPER, COPPER) }
    blueprint_io.export_to_entities_array(entities)
    assert.are.equal(1, #lines)
    assert.truthy(lines[1]:find("2001 entities", 1, true))
    assert.truthy(lines[1]:find("1 wires", 1, true))
  end)

  it("stays silent at or below the threshold", function()
    local lines = {}
    _G.log = function(message) lines[#lines + 1] = message end
    blueprint_io.export_to_entities_array(build(2000))
    assert.are.equal(0, #lines)
  end)
end)

describe("blueprint_io.export_to_tiles_array", function()
  it("returns {} for a session without tiles", function()
    assert.are.same({}, blueprint_io.export_to_tiles_array({}))
  end)

  it("orders tiles by position.y then position.x and passes raw through untouched", function()
    local raw_a = { name = "concrete", position = { x = 2, y = 0 } }
    local raw_b = { name = "stone-path", position = { x = -1, y = 0 } }
    local raw_c = { name = "concrete", position = { x = 5, y = -3 } }
    local raw_d = { name = "refined-concrete", position = { x = 0, y = 4 } }
    local tiles = {
      ["2,0"] = { raw = raw_a },
      ["-1,0"] = { raw = raw_b },
      ["5,-3"] = { raw = raw_c },
      ["0,4"] = { raw = raw_d },
    }
    local result = blueprint_io.export_to_tiles_array(tiles)
    assert.are.equal(4, #result)
    assert.are.equal(raw_c, result[1])
    assert.are.equal(raw_b, result[2])
    assert.are.equal(raw_a, result[3])
    assert.are.equal(raw_d, result[4])
    assert.are.same({ name = "concrete", position = { x = 2, y = 0 } }, raw_a)
  end)
end)

describe("blueprint_io.compute_bounding_box_center", function()
  it("returns {0, 0} for an empty blueprint", function()
    local center = blueprint_io.compute_bounding_box_center({}, {})
    assert.are.same({ x = 0, y = 0 }, center)
  end)

  it("returns the single entity's own position when there is only one", function()
    local entities = { [1] = { raw = { position = { x = 5, y = -3 } } } }
    local center = blueprint_io.compute_bounding_box_center(entities, {})
    assert.are.same({ x = 5, y = -3 }, center)
  end)

  it("returns the midpoint of the bounding box across entities and tiles", function()
    local entities = {
      [1] = { raw = { position = { x = -10, y = 0 } } },
      [2] = { raw = { position = { x = 10, y = 4 } } },
    }
    local tiles = {
      ["0,-6"] = { raw = { position = { x = 0, y = -6 } } },
    }
    local center = blueprint_io.compute_bounding_box_center(entities, tiles)
    assert.are.same({ x = 0, y = -1 }, center)
  end)

  it("handles a real far-from-origin blueprint like the one that surfaced this bug", function()
    local entities = {
      [1] = { raw = { position = { x = 3, y = -142.5 } } },
      [2] = { raw = { position = { x = 2.5, y = -143.5 } } },
      [3] = { raw = { position = { x = 5, y = -142.5 } } },
    }
    local center = blueprint_io.compute_bounding_box_center(entities, {})
    assert.are.same({ x = 3.75, y = -143 }, center)
  end)
end)

-- phase-4-plan.md «Задача 3»: origin запоминает исходник для сохранения.
describe("blueprint_io.build_origin", function()
  it("remembers the record and writable flag for a library record", function()
    local record = { valid = true, valid_for_write = true }
    local origin = blueprint_io.build_origin("cursor_record", record, nil)
    assert.are.equal("cursor_record", origin.kind)
    assert.are.equal(record, origin.record)
    assert.is_true(origin.writable)
  end)

  it("marks a read-only record (My blueprints / preview) as not writable", function()
    local record = { valid = true, valid_for_write = false }
    local origin = blueprint_io.build_origin("cursor_record", record, nil)
    assert.is_false(origin.writable)
  end)

  it("treats an invalid or missing valid_for_write as not writable", function()
    assert.is_false(blueprint_io.build_origin("cursor_record", { valid = false, valid_for_write = true }, nil).writable)
    assert.is_false(blueprint_io.build_origin("cursor_record", { valid = true }, nil).writable)
  end)

  it("keeps the book page path for an inventory blueprint and no record", function()
    local origin = blueprint_io.build_origin("cursor", { valid = true }, { 2, 1 })
    assert.are.equal("cursor", origin.kind)
    assert.are.same({ 2, 1 }, origin.page_path)
    assert.is_nil(origin.record)
    assert.is_nil(origin.writable)
  end)

  it("leaves page_path nil when the stack is not a book page", function()
    local origin = blueprint_io.build_origin("cursor", {}, {})
    assert.is_nil(origin.page_path)
  end)
end)

describe("blueprint_io.summarize_export", function()
  it("counts entities, wires and tiles and flags a non-empty export", function()
    local entities = {
      { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 }, wires = { { 1, COPPER, 2, COPPER } } },
      { entity_number = 2, name = "small-electric-pole", position = { x = 2, y = 0 } },
    }
    local tiles = { { name = "concrete", position = { x = 0, y = 0 } } }
    local summary = blueprint_io.summarize_export(entities, tiles)
    assert.are.same({ entities = 2, wires = 1, tiles = 1, empty = false, large = false }, summary)
  end)

  it("flags an export with no entities and no tiles as empty", function()
    local summary = blueprint_io.summarize_export({}, {})
    assert.is_true(summary.empty)
    assert.are.equal(0, summary.entities)
  end)

  it("is not empty when only tiles are present", function()
    assert.is_false(blueprint_io.summarize_export({}, { { name = "concrete", position = { x = 0, y = 0 } } }).empty)
  end)

  it("flags a large export above the size threshold by entities or by tiles", function()
    local many_entities = {}
    for n = 1, 2001 do
      many_entities[n] = { entity_number = n, name = "iron-chest", position = { x = n, y = 0 } }
    end
    assert.is_true(blueprint_io.summarize_export(many_entities, {}).large)
    local many_tiles = {}
    for n = 1, 2001 do
      many_tiles[n] = { name = "concrete", position = { x = n, y = 0 } }
    end
    assert.is_true(blueprint_io.summarize_export({}, many_tiles).large)
    many_entities[2001] = nil
    assert.is_false(blueprint_io.summarize_export(many_entities, {}).large)
  end)
end)

describe("blueprint_io.choose_save_target", function()
  it("saves a new-mode session as a new blueprint", function()
    local target, reason = blueprint_io.choose_save_target({ mode = "new", origin = nil })
    assert.are.equal("new", target)
    assert.are.equal("new_mode", reason)
  end)

  it("writes back into the pinned stack for an inventory blueprint", function()
    local target, reason = blueprint_io.choose_save_target({
      mode = "edit",
      origin = { kind = "pinned_stack", inventory = {}, page_path = { 2 } },
    })
    assert.are.equal("stack", target)
    assert.is_nil(reason)
  end)

  it("writes into a library record that is valid and writable at save time", function()
    local target = blueprint_io.choose_save_target({
      mode = "edit",
      origin = { kind = "cursor_record", record = { valid = true, valid_for_write = true }, writable = true },
    })
    assert.are.equal("record", target)
  end)

  it("falls back to a new blueprint when the record became invalid after entry (S1)", function()
    local target, reason = blueprint_io.choose_save_target({
      mode = "edit",
      origin = { kind = "cursor_record", record = { valid = false, valid_for_write = true }, writable = true },
    })
    assert.are.equal("new", target)
    assert.are.equal("record_invalid", reason)
  end)

  it("falls back to a new blueprint when the record is read-only at save time", function()
    local target, reason = blueprint_io.choose_save_target({
      mode = "edit",
      origin = { kind = "cursor_record", record = { valid = true, valid_for_write = false }, writable = true },
    })
    assert.are.equal("new", target)
    assert.are.equal("record_read_only", reason)
  end)

  it("reads a missing record (session from an older version) as not writable", function()
    local target, reason = blueprint_io.choose_save_target({
      mode = "edit",
      origin = { kind = "cursor_record" },
    })
    assert.are.equal("new", target)
    assert.are.equal("record_missing", reason)
  end)

  it("saves as a new blueprint when the source stayed in the player's hand", function()
    local target, reason = blueprint_io.choose_save_target({ mode = "edit", origin = { kind = "cursor" } })
    assert.are.equal("new", target)
    assert.are.equal("source_in_hand", reason)
  end)

  it("fails fast on an unknown origin kind", function()
    assert.has_error(function()
      blueprint_io.choose_save_target({ mode = "edit", origin = { kind = "teleporter" } })
    end)
  end)
end)

describe("blueprint_io.build_save_metadata", function()
  it("carries label, icons and the three snap fields from the session as is", function()
    local icons = { { signal = { type = "item", name = "iron-chest" }, index = 1 } }
    local grid = { x = 4, y = 4 }
    local offset = { x = 1, y = 0 }
    local metadata = blueprint_io.build_save_metadata({
      label = "My base",
      icons = icons,
      blueprint_snap = { snap_to_grid = grid, absolute_snapping = true, position_relative_to_grid = offset },
    })
    assert.are.equal("My base", metadata.label)
    assert.are.equal(icons, metadata.preview_icons)
    assert.are.equal(grid, metadata.blueprint_snap_to_grid)
    assert.is_true(metadata.blueprint_absolute_snapping)
    assert.are.equal(offset, metadata.blueprint_position_relative_to_grid)
  end)

  it("leaves every field nil for a new-mode session without metadata", function()
    local metadata = blueprint_io.build_save_metadata({})
    assert.are.same({}, metadata)
  end)

  it("keeps absolute_snapping false (not nil) when the source had it disabled", function()
    local metadata = blueprint_io.build_save_metadata({
      blueprint_snap = { snap_to_grid = nil, absolute_snapping = false, position_relative_to_grid = nil },
    })
    assert.is_false(metadata.blueprint_absolute_snapping)
    assert.is_nil(metadata.blueprint_snap_to_grid)
  end)
end)

describe("blueprint_io.save_result_message", function()
  local summary = { entities = 3, wires = 1, tiles = 2, empty = false, large = false }

  it("reports the counts for a write back into the inventory blueprint", function()
    local message = blueprint_io.save_result_message("stack", nil, summary)
    assert.truthy(message:find("3 entities", 1, true))
    assert.truthy(message:find("2 tiles", 1, true))
  end)

  it("says nothing extra for a record written in place (teleport_out reports it)", function()
    assert.is_nil(blueprint_io.save_result_message("record", nil, summary))
  end)

  it("explains the fallback to a new blueprint by reason", function()
    local read_only = blueprint_io.save_result_message("new", "record_read_only", summary)
    assert.truthy(read_only:find("read-only", 1, true))
    assert.truthy(read_only:find("new blueprint", 1, true))
    local invalid = blueprint_io.save_result_message("new", "record_invalid", summary)
    assert.truthy(invalid:find("no longer valid", 1, true))
    local missing = blueprint_io.save_result_message("new", "record_missing", summary)
    assert.truthy(missing:find("new blueprint", 1, true))
    local in_hand = blueprint_io.save_result_message("new", "source_in_hand", summary)
    assert.truthy(in_hand:find("hand", 1, true))
    local new_mode = blueprint_io.save_result_message("new", "new_mode", summary)
    assert.truthy(new_mode:find("new blueprint", 1, true))
    assert.is_nil(new_mode:find("read-only", 1, true))
  end)

  it("fails fast on an unknown fallback reason", function()
    assert.has_error(function() blueprint_io.save_result_message("new", "because", summary) end)
  end)
end)

-- write_blueprint_data -- API-зависимая функция, но её двухфазность (пробная
-- запись во временный blueprint, затем в цель) проверяется на минимальных
-- заглушках: цель и временный blueprint -- таблицы, записывающие вызовы;
-- game.create_inventory подменяется на время теста.
describe("blueprint_io.write_blueprint_data (two-phase write)", function()
  local saved_log, saved_game, log_lines

  before_each(function()
    saved_log, saved_game = _G.log, _G.game
    log_lines = {}
    _G.log = function(message) log_lines[#log_lines + 1] = message end
  end)

  after_each(function()
    _G.log, _G.game = saved_log, saved_game
  end)

  -- Заглушка LuaItemStack: методы записывают вызовы, присваивания атрибутов
  -- (snap-поля, label, preview_icons) -- тоже, чтобы проверить порядок.
  local function fake_blueprint(options)
    local calls = {}
    local methods = {
      calls = calls,
      object_name = "LuaItemStack",
      set_stack = function(stack)
        calls[#calls + 1] = { "set_stack", stack.name }
        return true
      end,
      set_blueprint_entities = function(entities, fix_positions)
        calls[#calls + 1] = { "set_blueprint_entities", entities, fix_positions }
      end,
      set_blueprint_tiles = function(tiles)
        if options and options.fail_tiles then
          error("tiles rejected by the game")
        end
        calls[#calls + 1] = { "set_blueprint_tiles", tiles }
      end,
    }
    return setmetatable({}, {
      __index = methods,
      __newindex = function(self, key, value)
        calls[#calls + 1] = { "set", key, value }
        rawset(self, key, value)
      end,
    })
  end

  local function install_game(trial)
    local inventory = { trial, destroyed = false }
    inventory.destroy = function() inventory.destroyed = true end
    _G.game = { create_inventory = function() return inventory end }
    return inventory
  end

  local export = {
    entities = { { entity_number = 1, name = "iron-chest", position = { x = 0, y = 0 } } },
    tiles = { { name = "concrete", position = { x = 0, y = 0 } } },
  }
  local metadata = { label = "Base", preview_icons = { { signal = { name = "iron-chest" }, index = 1 } },
    blueprint_snap_to_grid = { x = 2, y = 2 }, blueprint_absolute_snapping = false }

  it("leaves the target untouched when the trial write fails, and destroys the trial inventory", function()
    local inventory = install_game(fake_blueprint({ fail_tiles = true }))
    local target = fake_blueprint()
    local ok, message = blueprint_io.write_blueprint_data(target, export, metadata)
    assert.is_false(ok)
    assert.are.same({}, target.calls)
    assert.is_true(inventory.destroyed)
    assert.truthy(message:find("tiles rejected by the game", 1, true))
    assert.truthy(message:find("kept", 1, true))
    assert.truthy(log_lines[1]:find("tiles rejected by the game", 1, true))
  end)

  it("writes into the target after a successful trial: snap fields, entities with fix_positions = false, tiles, label, icons", function()
    local trial = fake_blueprint()
    local inventory = install_game(trial)
    local target = fake_blueprint()
    local ok = blueprint_io.write_blueprint_data(target, export, metadata)
    assert.is_true(ok)
    assert.is_true(inventory.destroyed)
    assert.are.equal("set_stack", trial.calls[1][1])
    assert.are.same({
      { "set", "blueprint_snap_to_grid", metadata.blueprint_snap_to_grid },
      { "set", "blueprint_absolute_snapping", false },
      { "set_blueprint_entities", export.entities, false },
      { "set_blueprint_tiles", export.tiles },
      { "set", "label", "Base" },
      { "set", "preview_icons", metadata.preview_icons },
    }, target.calls)
  end)

  it("does not write metadata fields that are nil", function()
    install_game(fake_blueprint())
    local target = fake_blueprint()
    assert.is_true(blueprint_io.write_blueprint_data(target, export, {}))
    assert.are.same({
      { "set_blueprint_entities", export.entities, false },
      { "set_blueprint_tiles", export.tiles },
    }, target.calls)
  end)

  it("reports honestly when the target write fails after the trial passed", function()
    local inventory = install_game(fake_blueprint())
    local target = fake_blueprint({ fail_tiles = true })
    local ok, message = blueprint_io.write_blueprint_data(target, export, metadata)
    assert.is_false(ok)
    assert.is_true(inventory.destroyed)
    assert.is_nil(message:find("kept", 1, true))
    assert.truthy(message:find("partially", 1, true))
    assert.truthy(message:find("tiles rejected by the game", 1, true))
    local permanent = {}
    for _, line in ipairs(log_lines) do
      if not line:find("eb playtest:", 1, true) then permanent[#permanent + 1] = line end
    end
    assert.are.equal(1, #permanent)
    assert.truthy(permanent[1]:find("after a successful trial", 1, true))
  end)
end)
