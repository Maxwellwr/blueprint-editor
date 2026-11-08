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
